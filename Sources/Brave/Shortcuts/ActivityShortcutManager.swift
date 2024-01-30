// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Shared
import Data
import Preferences
import Intents
import CoreSpotlight
import MobileCoreServices
import UIKit
import BrowserIntentsModels
import BraveVPN
import BraveNews
import Growth
import os.log
import SwiftUI
import UniformTypeIdentifiers

/// 快捷活动类型和创建执行操作的详细信息
public enum ActivityType: String {
  case newTab = "NewTab"
  case newPrivateTab = "NewPrivateTab"
  case openBookmarks = "OpenBookmarks"
  case openHistoryList = "OpenHistoryList"
  case clearBrowsingHistory = "ClearBrowsingHistory"
  case enableBraveVPN = "EnableBraveVPN"
  case openBraveNews = "OpenBraveNews"
  case openPlayList = "OpenPlayList"
  case openSyncedTabs = "OpenSyncedTabs"

  public var identifier: String {
    return "\(Bundle.main.bundleIdentifier ?? "").\(self.rawValue)"
  }

  /// 活动类型的标题
  public var title: String {
    switch self {
    case .newTab:
      return Strings.Shortcuts.activityTypeNewTabTitle
    case .newPrivateTab:
      return Strings.Shortcuts.activityTypeNewPrivateTabTitle
    case .openBookmarks:
      return Strings.Shortcuts.activityTypeOpenBookmarksTitle
    case .openHistoryList:
      return Strings.Shortcuts.activityTypeOpenHistoryListTitle
    case .clearBrowsingHistory:
      return Strings.Shortcuts.activityTypeClearHistoryTitle
    case .enableBraveVPN:
      return Strings.Shortcuts.activityTypeEnableVPNTitle
    case .openBraveNews:
      return Strings.Shortcuts.activityTypeOpenBraveNewsTitle
    case .openPlayList:
      return Strings.Shortcuts.activityTypeOpenPlaylistTitle
    case .openSyncedTabs:
      return Strings.Shortcuts.activityTypeOpenSyncedTabsTitle
    }
  }

  /// 活动类型的内容描述
  public var description: String {
    switch self {
    case .newTab, .newPrivateTab:
      return Strings.Shortcuts.activityTypeTabDescription
    case .openHistoryList:
      return Strings.Shortcuts.activityTypeOpenHistoryListDescription
    case .openBookmarks:
      return Strings.Shortcuts.activityTypeOpenBookmarksDescription
    case .clearBrowsingHistory:
      return Strings.Shortcuts.activityTypeClearHistoryDescription
    case .enableBraveVPN:
      return Strings.Shortcuts.activityTypeEnableVPNDescription
    case .openBraveNews:
      return Strings.Shortcuts.activityTypeBraveNewsDescription
    case .openPlayList:
      return Strings.Shortcuts.activityTypeOpenPlaylistDescription
    case .openSyncedTabs:
      return Strings.Shortcuts.activityTypeOpenSyncedTabsDescription
    }
  }

  /// 用户创建快捷方式时向用户建议的短语
  public var suggestedPhrase: String {
    switch self {
    case .newTab:
      return Strings.Shortcuts.activityTypeNewTabSuggestedPhrase
    case .newPrivateTab:
      return Strings.Shortcuts.activityTypeNewPrivateTabSuggestedPhrase
    case .openBookmarks:
      return Strings.Shortcuts.activityTypeOpenBookmarksSuggestedPhrase
    case .openHistoryList:
      return Strings.Shortcuts.activityTypeOpenHistoryListSuggestedPhrase
    case .clearBrowsingHistory:
      return Strings.Shortcuts.activityTypeClearHistorySuggestedPhrase
    case .enableBraveVPN:
      return Strings.Shortcuts.activityTypeEnableVPNSuggestedPhrase
    case .openBraveNews:
      return Strings.Shortcuts.activityTypeOpenBraveNewsSuggestedPhrase
    case .openPlayList:
      return Strings.Shortcuts.activityTypeOpenPlaylistSuggestedPhrase
    case .openSyncedTabs:
      return Strings.Shortcuts.activityTypeOpenSyncedTabsSuggestedPhrase
    }
  }
}

/// 单例管理器处理活动的创建和执行
public class ActivityShortcutManager: NSObject {

  /// 自定义意图类型
  public enum IntentType {
    case openWebsite
    case openHistory
    case openBookmarks
  }

  // MARK: 生命周期

  public static var shared = ActivityShortcutManager()

  // MARK: 活动创建方法

  public func createShortcutActivity(type: ActivityType) -> NSUserActivity {
    let attributes = CSSearchableItemAttributeSet(itemContentType: UTType.item.identifier)
    attributes.contentDescription = type.description

    let activity = NSUserActivity(activityType: type.identifier)
    activity.persistentIdentifier = NSUserActivityPersistentIdentifier(type.identifier)

    activity.isEligibleForSearch = true
    activity.isEligibleForPrediction = true

    activity.title = type.title
    activity.suggestedInvocationPhrase = type.suggestedPhrase
    activity.contentAttributeSet = attributes

    return activity
  }

  // MARK: 活动执行方法

  public func performShortcutActivity(type: ActivityType, using bvc: BrowserViewController) {
    // 添加轻微延迟以克服 bvc 设置的并发问题
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      self.handleActivityDetails(type: type, using: bvc)
    }
  }

  private func handleActivityDetails(type: ActivityType, using bvc: BrowserViewController) {
    switch type {
    case .newTab:
      bvc.openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: bvc.privateBrowsingManager.isPrivateBrowsing, isExternal: true)
      bvc.popToBVC()
    case .newPrivateTab:
      bvc.openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: true, isExternal: true)
      bvc.popToBVC()
    case .openBookmarks:
      bvc.popToBVC()
      bvc.navigationHelper.openBookmarks()
    case .openHistoryList:
      bvc.popToBVC()
      bvc.navigationHelper.openHistory(isModal: true)
    case .clearBrowsingHistory:
      bvc.clearHistoryAndOpenNewTab()
    case .enableBraveVPN:
      bvc.openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: bvc.privateBrowsingManager.isPrivateBrowsing, isExternal: true)
      bvc.popToBVC()

//      switch BraveVPN.vpnState {
//      case .notPurchased, .expired:
//        guard let enableVPNController = BraveVPN.vpnState.enableVPNDestinationVC else { return }
//
//        bvc.openInsideSettingsNavigation(with: enableVPNController)
//      case .purchased(let connected):
//        if !connected {
//          BraveVPN.reconnect()
//        }
//      }
    case .openBraveNews:
      // 仅在浏览器转到 PB 且 Brave News 在私人标签上不可用时才执行
      guard !Preferences.Privacy.privateBrowsingOnly.value else {
        return
      }

      if Preferences.BraveNews.isEnabled.value {
        bvc.openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: false, isExternal: true)
        bvc.popToBVC()

        guard let newTabPageController = bvc.tabManager.selectedTab?.newTabPageViewController else { return }
        newTabPageController.scrollToBraveNews()
      } else {
        let controller = NewsSettingsViewController(dataSource: bvc.feedDataSource, openURL: { url in
          bvc.dismiss(animated: true)
          bvc.select(url: url, isUserDefinedURLNavigation: false)
        })
        controller.viewDidDisappear = {
          if Preferences.Review.braveNewsCriteriaPassed.value {
            AppReviewManager.shared.isRevisedReviewRequired = true
            Preferences.Review.braveNewsCriteriaPassed.value = false
          }
        }
        let container = UINavigationController(rootViewController: controller)
        bvc.present(container, animated: true)
      }
    case .openPlayList:
      bvc.popToBVC()
      
      let tab = bvc.tabManager.selectedTab
      PlaylistCarplayManager.shared.getPlaylistController(tab: tab) { playlistController in
        playlistController.modalPresentationStyle = .fullScreen
        PlaylistP3A.recordUsage()
        bvc.present(playlistController, animated: true)
      }
    case .openSyncedTabs:
      bvc.popToBVC()
      bvc.showTabTray(isExternallyPresented: true)
    }
  }

  // MARK: 意图创建方法

  private func createCustomIntent(for type: IntentType, with urlString: String) -> INIntent {
    switch type {
    case .openWebsite:
      let intent = OpenWebsiteIntent()
      intent.websiteURL = urlString
      intent.suggestedInvocationPhrase = Strings.Shortcuts.customIntentOpenWebsiteSuggestedPhrase

      return intent
    case .openHistory:
      let intent = OpenHistoryWebsiteIntent()
      intent.websiteURL = urlString
      intent.suggestedInvocationPhrase = Strings.Shortcuts.customIntentOpenHistorySuggestedPhrase

      return intent
    case .openBookmarks:
      let intent = OpenBookmarkWebsiteIntent()
      intent.websiteURL = urlString
      intent.suggestedInvocationPhrase = Strings.Shortcuts.customIntentOpenBookmarkSuggestedPhrase

      return intent
    }
  }

  // MARK: 意图捐赠方法

  public func donateCustomIntent(for type: IntentType, with urlString: String) {
    guard !urlString.isEmpty,
          URL(string: urlString) != nil else {
      return
    }

    let intent = createCustomIntent(for: type, with: urlString)

    let interaction = INInteraction(intent: intent, response: nil)
    interaction.donate { error in
      guard let error = error else {
        return
      }

      Logger.module.error("Failed to donate shortcut open website, error: \(error.localizedDescription)")
    }
  }
}
