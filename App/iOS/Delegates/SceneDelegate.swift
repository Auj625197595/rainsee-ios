// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Brave
import BraveCore
import BraveNews
import BraveShared
import BraveVPN
import BraveWidgetsModels
import BrowserIntentsModels
import Combine
import CoreSpotlight
import Data
import Growth
import os.log
import Preferences
import Shared
import Storage
import UIKit

private extension Logger {
  static var module: Logger {
    .init(subsystem: "\(Bundle.main.bundleIdentifier ?? "com.brave.ios")", category: "SceneDelegate")
  }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  // This property must be non-null because even though it's optional,
  // Chromium force unwraps it and uses it. For this reason, we always set this window property to the scene's main window.
  var window: UIWindow?
  private var windowProtection: WindowProtection?
  static var shouldHandleUrpLookup = false
  static var shouldHandleInstallAttributionFetch = false

  private var cancellables: Set<AnyCancellable> = []

  
  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    // 确保是 UIWindowScene 类型的场景
    guard let windowScene = (scene as? UIWindowScene) else { return }

    // 创建 AttributionManager 实例，用于处理统计信息
    let attributionManager = AttributionManager(dau: AppState.shared.dau, urp: UserReferralProgram.shared)

    // 创建浏览器视图控制器
    let browserViewController = createBrowserWindow(
      scene: windowScene,
      braveCore: AppState.shared.braveCore,
      profile: AppState.shared.profile,
      attributionManager: attributionManager,
      diskImageStore: AppState.shared.diskImageStore,
      migration: AppState.shared.migration,
      rewards: AppState.shared.rewards,
      newsFeedDataSource: AppState.shared.newsFeedDataSource,
      userActivity: connectionOptions.userActivities.first ?? session.stateRestorationActivity)

    // 设置场景激活条件
    let conditions = scene.activationConditions
    conditions.canActivateForTargetContentIdentifierPredicate = NSPredicate(value: true)
    if let windowId = session.userInfo?["WindowID"] as? String {
      let preferPredicate = NSPredicate(format: "self == %@", windowId)
      conditions.prefersToActivateForTargetContentIdentifierPredicate = preferPredicate
    }

    // 监听主题模式的更改并更新主题
    Preferences.General.themeNormalMode.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self, weak scene] _ in
        guard let self = self,
              let scene = scene as? UIWindowScene else { return }
        self.updateTheme(for: scene)
      }
      .store(in: &cancellables)

    // 监听夜间模式的开关并更新主题
    Preferences.General.nightModeEnabled.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self, weak scene] _ in
        guard let self = self,
              let scene = scene as? UIWindowScene else { return }
        self.updateTheme(for: scene)
      }
      .store(in: &cancellables)

    // 监听隐私浏览模式的开关并更新主题
    browserViewController.privateBrowsingManager.$isPrivateBrowsing
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self, weak scene] _ in
        guard let self = self,
              let scene = scene as? UIWindowScene else { return }
        self.updateTheme(for: scene)
      }
      .store(in: &cancellables)

    // 处理首次启动时的 URP 查询
    if SceneDelegate.shouldHandleUrpLookup {
      SceneDelegate.shouldHandleUrpLookup = false

      attributionManager.handleReferralLookup { [weak browserViewController] url in
        browserViewController?.openReferralLink(url: url)
      }
    }

    // 设置播放列表 CarPlay
    // TODO: 决定在有多个窗口的情况下如何处理
    // 因为只能有一个 CarPlay 实例，所以一旦迁移到 iOS 14+，就可以轻松解决这个问题，方法是传递一个 `MediaStreamer` 实例而不是一个 `BrowserViewController` 实例
    PlaylistCarplayManager.shared.do {
      $0.browserController = browserViewController
    }

    // 呈现浏览器视图控制器
    present(
      browserViewController: browserViewController,
      windowScene: windowScene,
      connectionOptions: connectionOptions)

    // 处理首次安装时的归因获取
//    if SceneDelegate.shouldHandleInstallAttributionFetch {
//      SceneDelegate.shouldHandleInstallAttributionFetch = false
//
//      // 首次用户在完成最后阶段的 onboarding 后应发送 dau ping，即 P3A 同意屏幕
//      // P3A 启用时，发送搜索广告安装归因 API 方法前必须同意 P3A 用户同意
//      if !Preferences.AppState.dailyUserPingAwaitingUserConsent.value {
//        // 如果 P3A 未启用，则在每日 ping 时发送默认的有机安装代码 BRV001
//        // 用户未选择完全共享私密且匿名的产品见解
//        if AppState.shared.braveCore.p3aUtils.isP3AEnabled {
//          Task { @MainActor in
//            do {
//              try await attributionManager.handleSearchAdsInstallAttribution()
//            } catch {
//              Logger.module.debug("获取广告归因时出错 \(error)")
//              // 发送默认的有机安装代码进行 dau
//              attributionManager.setupReferralCodeAndPingServer()
//            }
//          }
//        } else {
//          // 发送默认的有机安装代码进行 dau
//          attributionManager.setupReferralCodeAndPingServer()
//        }
//      }
//    }

//    if Preferences.URP.installAttributionLookupOutstanding.value == nil {
//      // 类似于引荐查询，如果是新用户，则应设置此首选项
//      // 只在首次启动时触发安装归因获取
//      Preferences.URP.installAttributionLookupOutstanding.value = Preferences.General.isFirstLaunch.value
//    }

    // 安排通知，用于隐私报告管理器的调试模式
//    PrivacyReportsManager.scheduleNotification(debugMode: !AppConstants.buildChannel.isPublic)
//    PrivacyReportsManager.consolidateData()
//    PrivacyReportsManager.scheduleProcessingBlockedRequests(isPrivateBrowsing: browserViewController.privateBrowsingManager.isPrivateBrowsing)
//    PrivacyReportsManager.scheduleVPNAlertsTask()
  }

  // 添加这个方法用于获取当前的 UIViewController
  private func getCurrentViewController() -> UIViewController? {
    guard let window = window, let rootViewController = window.rootViewController else {
      return nil
    }

    if let navigationController = rootViewController as? UINavigationController {
      // 如果根视图控制器是导航控制器，返回导航控制器的 visibleViewController
      return navigationController.visibleViewController
    } else {
      // 否则直接返回根视图控制器
      return rootViewController
    }
  }



  private func present(browserViewController: BrowserViewController, windowScene: UIWindowScene, connectionOptions: UIScene.ConnectionOptions) {
    // Assign each browser a navigation controller
    let navigationController = UINavigationController(rootViewController: browserViewController).then {
      $0.isNavigationBarHidden = true
      $0.edgesForExtendedLayout = UIRectEdge(rawValue: 0)
    }

    // Assign each browser a window of its own
    let window = UIWindow(windowScene: windowScene).then {
      $0.backgroundColor = .black
      $0.overrideUserInterfaceStyle = expectedThemeOverride(for: windowScene)
      $0.tintColor = .braveBlurpleTint

      $0.rootViewController = navigationController
    }

    self.window = window

    // TODO: Refactor to accept a UIWindowScene
    // Then store the `windowProtection` in the `BrowserViewController` directly.
    // As each instance should have its own protection?
    windowProtection = WindowProtection(window: window)
    window.makeKeyAndVisible()

    // Open shared URLs on launch if there are any
    if !connectionOptions.urlContexts.isEmpty {
      scene(windowScene, openURLContexts: connectionOptions.urlContexts)
    }

    if let shortcutItem = connectionOptions.shortcutItem {
      QuickActions.sharedInstance.launchedShortcutItem = shortcutItem
    }

    if let response = connectionOptions.notificationResponse {
      if response.notification.request.identifier == BrowserViewController.defaultBrowserNotificationId {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
          Logger.module.error("[SCENE] - Failed to unwrap iOS settings URL")
          return
        }
        UIApplication.shared.open(settingsUrl)
      } else if response.notification.request.identifier == PrivacyReportsManager.notificationID {
        browserViewController.openPrivacyReport()
      }
    }
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    Logger.module.debug("[SCENE] - Scene Disconnected")
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    scene.userActivity?.becomeCurrent()

    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
          let scene = scene as? UIWindowScene
    else {
      return
    }

    if let windowId = (scene.userActivity?.userInfo?["WindowID"] ??
      scene.session.userInfo?["WindowID"]) as? String,
      let windowUUID = UUID(uuidString: windowId)
    {
      SessionWindow.setSelected(windowId: windowUUID)
    }

    Preferences.AppState.backgroundedCleanly.value = false
    AppState.shared.profile.reopen()

    appDelegate.receivedURLs = nil
    UIApplication.shared.applicationIconBadgeNumber = 0

    // handle quick actions is available
    let quickActions = QuickActions.sharedInstance
    if let shortcut = quickActions.launchedShortcutItem {
      // dispatch asynchronously so that BVC is all set up for handling new tabs
      // when we try and open them

      if let browserViewController = scene.browserViewController {
        quickActions.handleShortCutItem(shortcut, withBrowserViewController: browserViewController)
      }

      quickActions.launchedShortcutItem = nil
    }

    // We try to send DAU ping each time the app goes to foreground to work around network edge cases
    // (offline, bad connection etc.).
    // Also send the ping only after the URP lookup and install attribution has processed.
    if Preferences.URP.referralLookupOutstanding.value == true, Preferences.URP.installAttributionLookupOutstanding.value == true {
      AppState.shared.dau.sendPingToServer()
    }

    BraveSkusManager.refreshSKUCredential(isPrivate: scene.browserViewController?.privateBrowsingManager.isPrivateBrowsing == true)
  }

  func sceneWillResignActive(_ scene: UIScene) {
    Preferences.AppState.backgroundedCleanly.value = true
    scene.userActivity?.resignCurrent()
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
    if let scene = scene as? UIWindowScene {
      scene.browserViewController?.windowProtection = windowProtection
    }
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
    AppState.shared.profile.shutdown()
    // BraveVPN.sendVPNWorksInBackgroundNotification()
    Preferences.AppState.isOnboardingActive.value = false
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let scene = scene as? UIWindowScene else {
      Logger.module.error("[SCENE] - Scene is not a UIWindowScene")
      return
    }

    for URLContext in URLContexts {
      guard let routerpath = NavigationPath(url: URLContext.url, isPrivateBrowsing: scene.browserViewController?.privateBrowsingManager.isPrivateBrowsing == true) else {
        Logger.module.error("[SCENE] - Invalid Navigation Path: \(URLContext.url)")
        continue
      }

      scene.browserViewController?.handleNavigationPath(path: routerpath)
    }
  }

  func scene(_ scene: UIScene, didUpdate userActivity: NSUserActivity) {
    Logger.module.debug("[SCENE] - Updated User Activity for Scene")
  }

  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    guard let scene = scene as? UIWindowScene else {
      return
    }

    if let url = userActivity.webpageURL {
      switch UniversalLinkManager.universalLinkType(for: url, checkPath: false) {
      case .buyVPN:
        scene.browserViewController?.presentCorrespondingVPNViewController()
        return
      case .none:
        break
      }

      scene.browserViewController?.switchToTabForURLOrOpen(url, isPrivileged: true)
      return
    }

    switch userActivity.activityType {
    case CSSearchableItemActionType:
      // Otherwise, check if the `NSUserActivity` is a CoreSpotlight item and switch to its tab or
      // open a new one.
      if let userInfo = userActivity.userInfo,
         let urlString = userInfo[CSSearchableItemActivityIdentifier] as? String,
         let url = URL(string: urlString)
      {
        scene.browserViewController?.switchToTabForURLOrOpen(url, isPrivileged: false)
        return
      }
    case ActivityType.newTab.identifier:
      if let browserViewController = scene.browserViewController {
        ActivityShortcutManager.shared.performShortcutActivity(
          type: .newTab, using: browserViewController)
      }

      return
    case ActivityType.newPrivateTab.identifier:
      if let browserViewController = scene.browserViewController {
        ActivityShortcutManager.shared.performShortcutActivity(
          type: .newPrivateTab, using: browserViewController)
      }

      return
    case ActivityType.openHistoryList.identifier:
      if let browserViewController = scene.browserViewController {
        ActivityShortcutManager.shared.performShortcutActivity(
          type: .openHistoryList, using: browserViewController)
      }

      return
    case ActivityType.openBookmarks.identifier:
      if let browserViewController = scene.browserViewController {
        ActivityShortcutManager.shared.performShortcutActivity(
          type: .openBookmarks, using: browserViewController)
      }

      return
    case ActivityType.clearBrowsingHistory.identifier:
      if let browserViewController = scene.browserViewController {
        ActivityShortcutManager.shared.performShortcutActivity(
          type: .clearBrowsingHistory, using: browserViewController)
      }

      return
    case ActivityType.enableBraveVPN.identifier:
      if let browserViewController = scene.browserViewController {
        ActivityShortcutManager.shared.performShortcutActivity(
          type: .enableBraveVPN, using: browserViewController)
      }

      return
    case ActivityType.openBraveNews.identifier:
      if let browserViewController = scene.browserViewController {
        ActivityShortcutManager.shared.performShortcutActivity(
          type: .openBraveNews, using: browserViewController)
      }

      return
    case ActivityType.openPlayList.identifier:
      if let browserViewController = scene.browserViewController {
        ActivityShortcutManager.shared.performShortcutActivity(
          type: .openPlayList, using: browserViewController)
      }

    case ActivityType.openSyncedTabs.identifier:
      if let browserViewController = scene.browserViewController {
        ActivityShortcutManager.shared.performShortcutActivity(
          type: .openSyncedTabs, using: browserViewController)
      }
      return
    default:
      break
    }

    func switchToTabForIntentURL(intentURL: String?) {
      if let browserViewController = scene.browserViewController {
        guard let siteURL = intentURL, let url = URL(string: siteURL) else {
          browserViewController.openBlankNewTab(
            attemptLocationFieldFocus: false,
            isPrivate: Preferences.Privacy.privateBrowsingOnly.value)
          return
        }

        browserViewController.switchToTabForURLOrOpen(
          url,
          isPrivate: Preferences.Privacy.privateBrowsingOnly.value,
          isPrivileged: false)
      }
    }

    if let intent = userActivity.interaction?.intent as? OpenWebsiteIntent {
      switchToTabForIntentURL(intentURL: intent.websiteURL)
      return
    }

    if let intent = userActivity.interaction?.intent as? OpenHistoryWebsiteIntent {
      switchToTabForIntentURL(intentURL: intent.websiteURL)
      return
    }

    if let intent = userActivity.interaction?.intent as? OpenBookmarkWebsiteIntent {
      switchToTabForIntentURL(intentURL: intent.websiteURL)
      return
    }
  }

  func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
    if let browserViewController = windowScene.browserViewController {
      QuickActions.sharedInstance.handleShortCutItem(shortcutItem, withBrowserViewController: browserViewController)
      completionHandler(true)
    } else {
      completionHandler(false)
    }
  }

  func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
    return scene.userActivity
  }
}

extension SceneDelegate {
  private func expectedThemeOverride(for scene: UIWindowScene?) -> UIUserInterfaceStyle {
    // The expected appearance theme should be dark mode when night mode is enabled for websites
    let themeValue = Preferences.General.nightModeEnabled.value ? DefaultTheme.dark.rawValue : Preferences.General.themeNormalMode.value

    let themeOverride = DefaultTheme(rawValue: themeValue)?.userInterfaceStyleOverride ?? .unspecified
    let isPrivateBrowsing = scene?.browserViewController?.privateBrowsingManager.isPrivateBrowsing == true
    return isPrivateBrowsing ? .dark : themeOverride
  }

  private func updateTheme(for scene: UIWindowScene) {
    for window in scene.windows {
      UIView.transition(
        with: window, duration: 0.15, options: [.transitionCrossDissolve],
        animations: {
          window.overrideUserInterfaceStyle = self.expectedThemeOverride(for: scene)
        }, completion: nil)
    }
  }
}

extension SceneDelegate {
  private func createBrowserWindow(scene: UIWindowScene,
                                   braveCore: BraveCoreMain,
                                   profile: Profile,
                                   attributionManager: AttributionManager,
                                   diskImageStore: DiskImageStore?,
                                   migration: Migration?,
                                   rewards: Brave.BraveRewards,
                                   newsFeedDataSource: BraveNews.FeedDataSource,
                                   userActivity: NSUserActivity?) -> BrowserViewController
  {
    // 创建私密浏览管理器
    let privateBrowsingManager = PrivateBrowsingManager()

    // 如果正在构建开发环境，则不要跟踪崩溃，因为通过Xcode终止/停止模拟器将被视为“崩溃”，并导致在下一次启动时出现恢复弹窗
    let crashedLastSession = !Preferences.AppState.backgroundedCleanly.value && AppConstants.buildChannel != .debug

    // 存储场景的活动信息
    let windowId: UUID
    let isPrivate: Bool
    let urlToOpen: URL?

    if UIApplication.shared.supportsMultipleScenes {
      let windowInfo: BrowserState.SessionState
      if let userActivity = userActivity {
        windowInfo = BrowserState.getWindowInfo(from: userActivity)
      } else {
        windowInfo = BrowserState.getWindowInfo(from: scene.session)
      }

      if let existingWindowId = windowInfo.windowId,
         let windowUUID = UUID(uuidString: existingWindowId)
      {
        // 从用户信息中的 WindowID 恢复场景
        windowId = windowUUID
        isPrivate = windowInfo.isPrivate
        privateBrowsingManager.isPrivateBrowsing = windowInfo.isPrivate
        urlToOpen = windowInfo.openURL

        // 如果窗口不存在，则创建一个新的会话窗口
        SessionWindow.createWindow(isPrivate: isPrivate, isSelected: true, uuid: windowId)
        Logger.module.info("[SCENE] - 会话已恢复")
      } else {
        // 尝试恢复活动窗口
        windowId = restoreOrCreateWindow().windowId
        isPrivate = false
        privateBrowsingManager.isPrivateBrowsing = false
        urlToOpen = nil
      }
    } else {
      // iPhone 不关心用户活动或会话信息，因为它始终只有一个窗口
      windowId = restoreOrCreateWindow().windowId
      isPrivate = false
      privateBrowsingManager.isPrivateBrowsing = false
      urlToOpen = nil
    }

    // 设置场景的用户活动
    scene.userActivity = BrowserState.userActivity(for: windowId.uuidString, isPrivate: false)
    BrowserState.setWindowInfo(for: scene.session, windowId: windowId.uuidString, isPrivate: false)

    // 创建浏览器实例
    let browserViewController = BrowserViewController(
      windowId: windowId,
      profile: profile,
      attributionManager: attributionManager,
      diskImageStore: diskImageStore,
      braveCore: braveCore,
      rewards: rewards,
      migration: migration,
      crashedLastSession: crashedLastSession,
      newsFeedDataSource: newsFeedDataSource,
      privateBrowsingManager: privateBrowsingManager,
      action: { [weak self] actionName in
     
        // print(actionName)
      })

    browserViewController.do {
      $0.edgesForExtendedLayout = []

      // 添加恢复类，该类将返回我们将使用的 ViewController。
      $0.restorationIdentifier = BrowserState.sceneId
      $0.restorationClass = SceneDelegate.self

      // 删除广告授予提醒
      $0.removeScheduledAdGrantReminders()
    }

    if let tabIdString = userActivity?.userInfo?["TabID"] as? String,
       let tabWindowId = userActivity?.userInfo?["TabWindowID"] as? String,
       let tabId = UUID(uuidString: tabIdString)
    {
      let currentTabScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter {
        guard let sceneWindowId = BrowserState.getWindowInfo(from: $0.session).windowId else {
          return false
        }

        return sceneWindowId == tabWindowId
      }.first

      if let currentTabScene = currentTabScene, let currentTabSceneBrowser = currentTabScene.browserViewController {
        browserViewController.loadViewIfNeeded()
        currentTabSceneBrowser.moveTab(tabId: tabId, to: browserViewController)
      }
    }

    if let urlToOpen = urlToOpen {
      DispatchQueue.main.async {
        browserViewController.loadViewIfNeeded()
        browserViewController.switchToTabForURLOrOpen(urlToOpen, isPrivileged: false)
      }
    }

    return browserViewController
  }

  private func restoreOrCreateWindow() -> (windowId: UUID, isPrivate: Bool, urlToOpen: URL?) {
    // 查找活动窗口/会话
    let activeWindow = SessionWindow.getActiveWindow(context: DataController.swiftUIContext)
    let activeSession = UIApplication.shared.openSessions
      .compactMap { BrowserState.getWindowInfo(from: $0) }
      .first(where: { $0.windowId != nil && $0.windowId == activeWindow?.windowId.uuidString })

    if activeSession != nil {
      if !UIApplication.shared.supportsMultipleScenes {
        // iPhone 不应该创建新窗口
        if let activeWindow = activeWindow {
          // 如果没有活动窗口，继续并创建一个
          return (activeWindow.windowId, false, nil)
        }
      }

      // 已经有一个现有窗口在屏幕上活动，因此创建一个新窗口
      let windowId = UUID()
      SessionWindow.createWindow(isPrivate: false, isSelected: true, uuid: windowId)
      Logger.module.info("[SCENE] - 创建新窗口")
      return (windowId, false, nil)
    }

    // 如果可能，恢复活动窗口
    let windowId: UUID
    if !UIApplication.shared.supportsMultipleScenes {
      // iPhone 没有多窗口，因此可以恢复活动窗口或找到的第一个窗口
      windowId = activeWindow?.windowId ?? SessionWindow.all().first?.windowId ?? UUID()
    } else {
      windowId = activeWindow?.windowId ?? UUID()
    }

    // 如果不存在，则创建一个新的会话窗口
    SessionWindow.createWindow(isPrivate: false, isSelected: true, uuid: windowId)
    Logger.module.info("[SCENE] - 恢复活动窗口或创建新窗口")
    return (windowId, false, nil)
  }
}

extension SceneDelegate: UIViewControllerRestoration {
  public static func viewController(withRestorationIdentifierPath identifierComponents: [String], coder: NSCoder) -> UIViewController? {
    return nil
  }
}

extension UIWindowScene {
  /// A single scene should only have ONE browserViewController
  /// However, it is possible that someone can create multiple,
  /// Therefore, we support this possibility if needed
  var browserViewControllers: [BrowserViewController] {
    windows.compactMap {
      $0.rootViewController as? UINavigationController
    }.flatMap {
      $0.viewControllers.compactMap {
        $0 as? BrowserViewController
      }
    }
  }

  /// A scene should only ever have one browserViewController
  /// Returns the first instance of `BrowserViewController` that is found in the current scene
  var browserViewController: BrowserViewController? {
    return browserViewControllers.first
  }
}

extension UIView {
  /// Returns the `Scene` that this view belongs to.
  /// If the view does not belong to a scene, it returns the scene of its parent
  /// Otherwise returns nil if no scene is associated with this view.
  var currentScene: UIWindowScene? {
    if let scene = window?.windowScene {
      return scene
    }

    if let scene = superview?.currentScene {
      return scene
    }

    return nil
  }
}

extension UIViewController {
  /// Returns the `Scene` that this controller belongs to.
  /// If the controller does not belong to a scene, it returns the scene of its presenter or parent.
  /// Otherwise returns nil if no scene is associated with this controller.
  var currentScene: UIWindowScene? {
    if let scene = view.window?.windowScene {
      return scene
    }

    if let scene = parent?.currentScene {
      return scene
    }

    if let scene = presentingViewController?.currentScene {
      return scene
    }

    return nil
  }
}
