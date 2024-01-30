// 版权所有 2022 年 Brave 作者。保留所有权利。
// 此源代码表单受 Mozilla 公共许可证 v. 2.0 条款约束。
// 如果未随此文件分发 MPL 的副本，则可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import Shared
import Preferences
import Data
import UIKit
import BraveVPN
import os.log

public struct PrivacyReportsManager {

  // MARK: - 数据处理
  
  /// 由于性能原因，阻止的请求不会立即存储到数据库中。
  /// 相反，会定期运行一个计时器，并在此期间收集的所有请求将保存在一个数据库事务中。
  public static var pendingBlockedRequests: [(host: String, domain: URL, date: Date)] = []
  
  private static func processBlockedRequests() {
    let itemsToSave = pendingBlockedRequests
    pendingBlockedRequests.removeAll()
    
    // 处理用户在有待保存项目时禁用数据捕获的任何奇怪边缘情况之前，我们在保存到数据库之前删除它们。
    if !Preferences.PrivacyReports.captureShieldsData.value { return }

    BlockedResource.batchInsert(items: itemsToSave)
  }

  private static var saveBlockedResourcesTimer: Timer?
  private static var vpnAlertsTimer: Timer?

  public static func scheduleProcessingBlockedRequests(isPrivateBrowsing: Bool) {
    saveBlockedResourcesTimer?.invalidate()
    
    let timeInterval = AppConstants.buildChannel.isPublic ? 60.0 : 10.0

    saveBlockedResourcesTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { _ in
      if !isPrivateBrowsing {
        processBlockedRequests()
      }
    }
  }
  
  public static func scheduleVPNAlertsTask() {
//    vpnAlertsTimer?.invalidate()
//
//    // 由于获取 VPN 提示涉及发出 URL 请求，
//    // 因此获取它们的时间间隔比本地设备上的阻止请求处理要长。
//    let timeInterval = AppConstants.buildChannel.isPublic ? 5.minutes : 1.minutes
//    vpnAlertsTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { _ in
//      if Preferences.PrivacyReports.captureVPNAlerts.value {
//       // BraveVPN.processVPNAlerts()
//      }
//    }
  }
  
  public static func clearAllData() {
    BraveVPNAlert.clearData()
    BlockedResource.clearData()
  }
  
  public static func consolidateData(dayRange range: Int = 30) {
    if Preferences.PrivacyReports.nextConsolidationDate.value == nil {
      Preferences.PrivacyReports.nextConsolidationDate.value = Date().advanced(by: 7.days)
    }
      
    if let consolidationDate = Preferences.PrivacyReports.nextConsolidationDate.value, Date() < consolidationDate {
      return
    }
    
    Preferences.PrivacyReports.nextConsolidationDate.value = Date().advanced(by: 7.days)
    
    BlockedResource.consolidateData(olderThan: range)
    BraveVPNAlert.consolidateData(olderThan: range)
  }

  // MARK: - 视图
  /// 获取呈现隐私报告视图所需的数据并返回视图。
  static func prepareView(isPrivateBrowsing: Bool) -> PrivacyReportsView {
    let last = BraveVPNAlert.last(3)
    let view = PrivacyReportsView(lastVPNAlerts: last, isPrivateBrowsing: isPrivateBrowsing)
    
    Preferences.PrivacyReports.ntpOnboardingCompleted.value = true

    return view
  }

  // MARK: - 通知

  public static let notificationID = "privacy-report-weekly-notification"

  public static func scheduleNotification(debugMode: Bool) {
    let notificationCenter = UNUserNotificationCenter.current()

    if debugMode {
      cancelNotification()
    }
    
    if !Preferences.PrivacyReports.captureShieldsData.value {
      cancelNotification()
      return
    }

    notificationCenter.getPendingNotificationRequests { requests in
      if !debugMode && requests.contains(where: { $0.identifier == notificationID }) {
        // 已经计划了一个通知，无需再次计划。
        return
      }

      let content = UNMutableNotificationContent()
      content.title = Strings.PrivacyHub.notificationTitle
      content.body = Strings.PrivacyHub.notificationMessage

      var dateComponents = DateComponents()
      let calendar = Calendar.current
      dateComponents.calendar = calendar

      // 出于测试目的，开发和本地构建将在启用通知后的几分钟内启动通知。
      if debugMode {
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        dateComponents.weekday = weekday
        dateComponents.hour = hour
        dateComponents.minute = minute + 5
      } else {
        // 每周日上午 11 点
        dateComponents.weekday = 1
        dateComponents.hour = 11
      }

      let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
      let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
      
      notificationCenter.add(request) { error in
        if let error = error {
          Logger.module.error("计划隐私报告通知出错：\(error.localizedDescription)")
        }
      }
    }
  }

  static func cancelNotification() {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
  }
}
