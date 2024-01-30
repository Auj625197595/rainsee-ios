// 版权 2022 年 Brave 作者。保留所有权利。
// 此源代码表单受 Mozilla 公共许可证版本 2.0 的条款约束。
// 如果未随此文件分发 MPL 的副本，则可以在 http://mozilla.org/MPL/2.0/ 获取其中一个。

import Combine
import Foundation
import Shared
import Preferences
import StoreKit
import UIKit
import BraveVPN

/// 单例管理器处理应用审查标准
public class AppReviewManager: ObservableObject {
  
  struct Constants {
    // 旧版审查常量
    static let firstThreshold = 14
    static let secondThreshold = 41
    static let lastThreshold = 121
    static let minDaysBetweenReviewRequest = 60

    // 修订版审查常量
    static let launchCountLimit = 5
    static let bookmarksCountLimit = 5
    static let playlistCountLimit = 5
    static let dappConnectionPeriod = AppConstants.buildChannel.isPublic ? 7.days : 7.minutes
    static let daysInUseMaxPeriod = AppConstants.buildChannel.isPublic ? 7.days : 7.minutes
    static let daysInUseRequiredPeriod = 4
    static let revisedMinDaysBetweenReviewRequest = 30
    
    // 新的评分卡
    static let minDaysBetweenRatingCardPresented = 7
  }
  
  /// 用于确定将使用哪种类型的应用审查逻辑的枚举
  /// 用于快速切换不同类型的逻辑的帮助器
  /// 可以使用 activeAppReviewLogicType 更改活动的请求审查类型
  public enum AppReviewLogicType: CaseIterable {
    // 旧版审查逻辑作为基线使用
    // 仅检查启动次数和审查之间的天数
    // 在应用启动时执行评级请求
    case legacy
    // 修订版审查逻辑用于测试
    // 审查请求的各种成功情况
    // 检查各种主要标准和子标准
    // 作为一些操作的结果执行评级请求
    // 此逻辑后来恢复为旧逻辑
    // 上下文：https://github.com/brave/brave-ios/pull/6210
    case revised
    // 与 Android 平台一致的修订审查逻辑
    // 检查各种主要标准和子标准
    // 在应用启动时执行评级请求
    case revisedCrossPlatform
    // 用于在新闻提要中显示评级卡的逻辑
    case newsRatingCard
    
    var mainCriteria: [AppReviewMainCriteriaType] {
      switch self {
      case .legacy:
        return [.threshold]
      case .revised:
        return [.launchCount, .daysInUse, .sessionCrash]
      case .revisedCrossPlatform:
        return [.launchCount, .daysInUse, .sessionCrash, .daysInBetweenReview]
      case .newsRatingCard:
        return [.launchCount, .daysInUse]
      }
    }
    
    var subCriteria: [AppReviewSubCriteriaType] {
      switch self {
      case .legacy:
        return []
      case .revised:
        return [.numberOfBookmarks, .paidVPNSubscription, .walletConnectedDapp,
                .numberOfPlaylistItems, .syncEnabledWithTabSync]
      case .revisedCrossPlatform:
        return [.numberOfBookmarks, .paidVPNSubscription]
      case .newsRatingCard:
        return []
      }
    }
  }
  
  /// 在检查子标准之前应满足的主要标准
  public enum AppReviewMainCriteriaType: CaseIterable {
    case threshold
    case launchCount
    case daysInUse
    case sessionCrash
    case daysInBetweenReview
  }
  
  /// 如果所有主要标准有效，则应满足的子标准
  public enum AppReviewSubCriteriaType: CaseIterable {
    case numberOfBookmarks
    case paidVPNSubscription
    case walletConnectedDapp
    case numberOfPlaylistItems
    case syncEnabledWithTabSync
  }
    
  @Published public var isRevisedReviewRequired = false
  private var activeAppReviewLogicType: AppReviewLogicType = .legacy
  
  // MARK: 生命周期
  
  public static var shared = AppReviewManager()
  
  // MARK: 处理审查请求
  
  public func handleAppReview(for logicType: AppReviewLogicType, using controller: UIViewController) {
    guard logicType == activeAppReviewLogicType else {
      return
    }
    
//    if checkLogicCriteriaSatisfied(for: logicType) {
//      guard AppConstants.buildChannel.isPublic else {
//        let alert = UIAlertController(
//          title: "显示应用评分",
//          message: "满足请求逻辑类型 \(logicType) 的标准以请求审查",
//          preferredStyle: .alert)
//        alert.addAction(UIAlertAction(title: "好的", style: .default, handler: nil))
//        controller.present(alert, animated: true)
//        
//        return
//      }
//      
//      DispatchQueue.main.async {
//        if let windowScene = controller.currentScene {
//          SKStoreReviewController.requestReview(in: windowScene)
//        }
//      }
//    }
  }
  
  // MARK: 审查请求查询

  public func checkLogicCriteriaSatisfied(for logicType: AppReviewLogicType, date: Date = Date()) -> Bool {
    // 在检查附加情况之前，应满足所有主要标准
    let mainCriteriaSatisfied = logicType.mainCriteria.allSatisfy({ criteria in
      checkMainCriteriaSatisfied(for: criteria, date: date)
    })
    
    var subCriteriaSatisfied = true
    if !logicType.subCriteria.isEmpty {
      // 此外，如果所有主要标准都已完成，则还必须满足以下条件之一
      if mainCriteriaSatisfied {
        subCriteriaSatisfied = logicType.subCriteria.contains(where: checkSubCriteriaSatisfied(for:))
      }
    }
    
    return mainCriteriaSatisfied && subCriteriaSatisfied
  }
  
  public func shouldShowNewsRatingCard() -> Bool {
    // 检查新评级卡演示的主要和子标准是否满足
    guard checkLogicCriteriaSatisfied(for: .newsRatingCard) else {
      return false
    }
    
    // 检查自上次卡演示以来是否至少经过 minDaysBetweenRatingCardPresented 天
    var daysSinceLastRequest = 0
    if let previousRequest = Preferences.Review.newsCardShownDate.value {
      daysSinceLastRequest = Calendar.current.dateComponents([.day], from: previousRequest, to: Date()).day ?? 0
    } else {
      // 首次演示日期，没有记录的演示
      return true
    }
    
    if abs(daysSinceLastRequest) < Constants.minDaysBetweenRatingCardPresented {
      return false
    }
    
    return true
  }
  
  // MARK: 处理审查标准过程

  /// 用于处理应用程序各个部分中主要标准更改的方法
  /// - Parameter mainCriteria: 主要标准的类型
  public func processMainCriteria(for mainCriteria: AppReviewMainCriteriaType) {
    switch mainCriteria {
    case .daysInUse:
      var daysInUse = Preferences.Review.daysInUse.value
      
      daysInUse.append(Date())
      daysInUse = daysInUse.filter { $0 < Date().addingTimeInterval(Constants.daysInUseMaxPeriod) }
      
      Preferences.Review.daysInUse.value = daysInUse
    default:
      break
    }
  }
  
  /// 用于处理应用程序各个部分中子标准更改的方法
  /// - Parameter subCriteria: 子标准的类型
  public func processSubCriteria(for subCriteria: AppReviewSubCriteriaType) {
    switch subCriteria {
    case .walletConnectedDapp:
      // 保存用户将其钱包连接到 Dapp 的日期
      Preferences.Review.dateWalletConnectedToDapp.value = Date()
    case .numberOfPlaylistItems:
      // 增加用户添加的播放列表项目的数量
      Preferences.Review.numberPlaylistItemsAdded.value += 1
    case .numberOfBookmarks:
      // 增加用户添加的书签数量
      Preferences.Review.numberBookmarksAdded.value += 1
    default:
      break
    }
  }
  
  /// 用于检查应用审查子标准是否满足的方法
  /// - Parameter type: 主要标准类型
  /// - Returns:Boolean 值，显示特定标准是否满足
  private func checkMainCriteriaSatisfied(for type: AppReviewMainCriteriaType, date: Date = Date()) -> Bool {
    switch type {
    case .threshold:
      let launchCount = Preferences.Review.launchCount.value
      let threshold = Preferences.Review.threshold.value

      var daysSinceLastRequest = 0
      if let previousRequest = Preferences.Review.lastReviewDate.value {
        daysSinceLastRequest = Calendar.current.dateComponents([.day], from: previousRequest, to: date).day ?? 0
      } else {
        daysSinceLastRequest = Constants.minDaysBetweenReviewRequest
      }

      if launchCount <= threshold || daysSinceLastRequest < Constants.minDaysBetweenReviewRequest {
        return false
      }

      Preferences.Review.lastReviewDate.value = date

      switch threshold {
      case Constants.firstThreshold:
        Preferences.Review.threshold.value = Constants.secondThreshold
      case Constants.secondThreshold:
        Preferences.Review.threshold.value = Constants.lastThreshold
      default:
        break
      }

      return true
    case .launchCount:
      return Preferences.Review.launchCount.value >= Constants.launchCountLimit
    case .daysInUse:
      return Preferences.Review.daysInUse.value.count >= Constants.daysInUseRequiredPeriod
    case .sessionCrash:
      return !(!Preferences.AppState.backgroundedCleanly.value && AppConstants.buildChannel != .debug)
    case .daysInBetweenReview:
      var daysSinceLastRequest = 0
      if let previousRequest = Preferences.Review.lastReviewDate.value {
        daysSinceLastRequest = Calendar.current.dateComponents([.day], from: previousRequest, to: date).day ?? 0
      } else {
        Preferences.Review.lastReviewDate.value = date
        return true
      }

      if daysSinceLastRequest < Constants.revisedMinDaysBetweenReviewRequest {
        return false
      }

      Preferences.Review.lastReviewDate.value = date
      return true
    }
  }
  
  /// 用于检查应用审查子标准是否满足的方法
  /// - Parameter type: 子标准类型
  /// - Returns: Boolean 值，显示特定标准是否满足
  private func checkSubCriteriaSatisfied(for type: AppReviewSubCriteriaType) -> Bool {
    switch type {
    case .numberOfBookmarks:
      return Preferences.Review.numberBookmarksAdded.value >= Constants.bookmarksCountLimit
    case .paidVPNSubscription:
     
      return false
    case .walletConnectedDapp:
      guard let connectedDappDate = Preferences.Review.dateWalletConnectedToDapp.value else {
        return false
      }
      return Date() < connectedDappDate.addingTimeInterval(Constants.dappConnectionPeriod)
    case .numberOfPlaylistItems:
      return Preferences.Review.numberPlaylistItemsAdded.value >= Constants.playlistCountLimit
    case .syncEnabledWithTabSync:
      return Preferences.Chromium.syncEnabled.value && Preferences.Chromium.syncOpenTabsEnabled.value
    }
  }
}
