/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
import Storage
import AVFoundation
import MessageUI
import SDWebImage
import LocalAuthentication
import CoreSpotlight
import UserNotifications
import BraveShared
import Data
import StoreKit
import BraveCore
import Combine
import Brave
import BraveVPN
import Growth
import RuntimeWarnings
import BraveNews
#if canImport(BraveTalk)
import BraveTalk
#endif
import Onboarding
import os
import BraveWallet
import Preferences
import BraveShields
import PrivateCDN
import Playlist
import UserAgent

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "app-delegate")
  
  var window: UIWindow?
  private weak var application: UIApplication?
  let appVersion = Bundle.main.infoDictionaryString(forKey: "CFBundleShortVersionString")
  var receivedURLs: [URL]?
  
  private var cancellables: Set<AnyCancellable> = []

  @discardableResult
  func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
      // 保存 willFinishLaunching 的参数以延迟应用程序启动
      self.application = application
      
      // 必须先初始化应用程序常量
      #if MOZ_CHANNEL_RELEASE
      AppConstants.buildChannel = .release
      #elseif MOZ_CHANNEL_BETA
      AppConstants.buildChannel = .beta
      #elseif MOZ_CHANNEL_DEV
      AppConstants.buildChannel = .dev
      #elseif MOZ_CHANNEL_ENTERPRISE
      AppConstants.buildChannel = .enterprise
      #elseif MOZ_CHANNEL_DEBUG
      AppConstants.buildChannel = .debug
      #endif
      
      // 设置应用程序状态为启动中，包括启动选项和活跃状态
      AppState.shared.state = .launching(options: launchOptions ?? [:], active: false)
      
      // 设置 Safari 的用户代理以便浏览
      setUserAgent()

      // 获取 GRDRegion 的详细信息，用于自动选择区域
     // BraveVPN.fetchLastUsedRegionDetail()
      
      // 启动键盘助手以监视和缓存键盘状态
      KeyboardHelper.defaultHelper.startObserving()
      DynamicFontHelper.defaultHelper.startObserving()
      ReaderModeFonts.registerCustomFonts()

      MenuHelper.defaultHelper.setItems()

      SDImageCodersManager.shared.addCoder(PrivateCDNImageCoder())

      // 临时修复 Bug 1390871 - NSInvalidArgumentException: -[WKContentView menuHelperFindInPage]: unrecognized selector
      if let clazz = NSClassFromString("WKCont" + "ent" + "View"), let swizzledMethod = class_getInstanceMethod(TabWebViewMenuHelper.self, #selector(TabWebViewMenuHelper.swizzledMenuHelperFindInPage)) {
        class_addMethod(clazz, MenuHelper.selectorFindInPage, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))
      }

      // 如果 BraveNews 启用且用户未选择加入，则强制退出
      if Preferences.BraveNews.isEnabled.value && !Preferences.BraveNews.userOptedIn.value {
        // 将 BraveNews 启用状态设为 false
        Preferences.BraveNews.isEnabled.value = false
        // 用户现在必须明确选择加入
        Preferences.BraveNews.isShowingOptIn.value = true
      }

      // 如果用户的语言被检查但未包含在 News 支持的语言列表中，则每次启动都检查一次
      // 这是因为更新可能添加对新语言的支持。但是，如果用户先前选择了 News，则不应再显示选择加入卡片。
      let shouldPerformLanguageCheck = !Preferences.BraveNews.languageChecked.value ||
        Preferences.BraveNews.languageWasUnavailableDuringCheck.value == true
      let isNewsEnabledOrPreviouslyOptedIn = Preferences.BraveNews.isEnabled.value ||
        Preferences.BraveNews.userOptedIn.value
      if shouldPerformLanguageCheck, !isNewsEnabledOrPreviouslyOptedIn,
         let languageCode = Locale.preferredLanguages.first?.prefix(2) {
        Preferences.BraveNews.languageChecked.value = true
        let languageShouldShowOptIn = FeedDataSource.supportedLanguages.contains(String(languageCode)) ||
          FeedDataSource.knownSupportedLocales.contains(Locale.current.identifier)
        Preferences.BraveNews.languageWasUnavailableDuringCheck.value = !languageShouldShowOptIn
        Preferences.BraveNews.isShowingOptIn.value = languageShouldShowOptIn
      }

      // 在首次运行时执行一些系统操作
      SystemUtils.onFirstRun()
      return true
  }


  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
      // 设置应用程序状态为启动中，包括启动选项和活跃状态
      AppState.shared.state = .launching(options: launchOptions ?? [:], active: true)
      
      // IAP（In-App Purchases）可能会在应用程序启动时触发，
      // 例如当以前的交易尚未完成并处于挂起状态时。
//      SKPaymentQueue.default().add(BraveVPN.iapObserver)
//      // 编辑产品促销列表
//      Task { @MainActor in
//        await BraveVPN.updateStorePromotionOrder()
//        await BraveVPN.hideActiveStorePromotion()
//      }
      
      // 在应用程序启动后进行自定义的重写点。
      var shouldPerformAdditionalDelegateHandling = true
      AdblockEngine.setDomainResolver()

      UIView.applyAppearanceDefaults()

      if Preferences.Rewards.isUsingBAP.value == nil {
        Preferences.Rewards.isUsingBAP.value = Locale.current.regionCode == "JP"
      }

      // 如果通过快捷方式启动了应用程序，请显示其信息并采取适当的操作
      if let shortcutItem = launchOptions?[UIApplication.LaunchOptionsKey.shortcutItem] as? UIApplicationShortcutItem {
        QuickActions.sharedInstance.launchedShortcutItem = shortcutItem
        // 这将阻止调用 "performActionForShortcutItem:completionHandler"
        shouldPerformAdditionalDelegateHandling = false
      }

      // 强制将 ToolbarTextField 设置为从左到右（LTR）模式
      // 没有这个改变，UITextField 的清除按钮将位于不正确的位置并重叠在输入文本上。不清楚这是否是 iOS 的错误。
      AutocompleteTextField.appearance().semanticContentAttribute = .forceLeftToRight

      Preferences.Review.launchCount.value += 1

      let isFirstLaunch = Preferences.General.isFirstLaunch.value
      
      Preferences.AppState.isOnboardingActive.value = isFirstLaunch
      Preferences.AppState.dailyUserPingAwaitingUserConsent.value = isFirstLaunch
      
      if Preferences.Onboarding.basicOnboardingCompleted.value == OnboardingState.undetermined.rawValue {
        Preferences.Onboarding.basicOnboardingCompleted.value =
          isFirstLaunch ? OnboardingState.unseen.rawValue : OnboardingState.completed.rawValue
      }

      // 检查用户是否在应用程序启动前启动过应用程序，并确定它是否是新的留存用户
      if Preferences.General.isFirstLaunch.value, Preferences.Onboarding.isNewRetentionUser.value == nil {
        Preferences.Onboarding.isNewRetentionUser.value = true
      }

      if Preferences.DAU.appRetentionLaunchDate.value == nil {
        Preferences.DAU.appRetentionLaunchDate.value = Date()
      }
      
//      // Brave Search 促销的启动日期，标记为 15 天期间
//      if Preferences.BraveSearch.braveSearchPromotionLaunchDate.value == nil {
//        Preferences.BraveSearch.braveSearchPromotionLaunchDate.value = Date()
//      }
//      
//      // 在用户在促销中选择了“稍后再说”后，横幅将不会在同一会话中再次显示给用户
//      if Preferences.BraveSearch.braveSearchPromotionCompletionState.value ==
//          BraveSearchPromotionState.maybeLaterSameSession.rawValue {
//        Preferences.BraveSearch.braveSearchPromotionCompletionState.value =
//          BraveSearchPromotionState.maybeLaterUpcomingSession.rawValue
//      }
      
      if isFirstLaunch {
        Preferences.PrivacyReports.ntpOnboardingCompleted.value = false
      }

      Preferences.General.isFirstLaunch.value = false

      // 在 'firstLaunch' 循环之外必须检查搜索引擎设置，因为存在 #2770 的问题。
      // 当您跳过入门流程时，默认搜索引擎首选项不会被设置。
      if Preferences.Search.defaultEngineName.value == nil {
        AppState.shared.profile.searchEngines.searchEngineSetup()
      }

      if isFirstLaunch {
        Preferences.DAU.installationDate.value = Date()

        // VPN 凭据保存在钥匙串中，并在应用程序重新安装之间持久存在。
        // 为了避免意外问题，我们清除所有 VPN 钥匙串项。
        // 在购买或还原 IAP 时，将创建一组新的钥匙串项。
       // BraveVPN.clearCredentials()
        
        // 对于新用户，始终在 Brave 中加载 YouTube
        Preferences.General.keepYouTubeInBrave.value = true
      }

      if Preferences.URP.referralLookupOutstanding.value == nil {
        // 此首选项从未设置过，这意味着这是一个新的或升级的用户。
        // 必须进行此区分，以确定是否应该进行网络请求以查找引荐代码。

        // 将其设置为明确的值，以便在后续启动时永远不会被覆盖。
        // 升级用户不应该有引荐代码的 ping 请求。
        Preferences.URP.referralLookupOutstanding.value = isFirstLaunch
      }

      SceneDelegate.shouldHandleUrpLookup = true
      SceneDelegate.shouldHandleInstallAttributionFetch = true

  #if canImport(BraveTalk)
      BraveTalkJitsiCoordinator.sendAppLifetimeEvent(
        .didFinishLaunching(options: launchOptions ?? [:])
      )
  #endif
      
      // DAU 可能在第一次启动时未 ping，因此 weekOfInstallation 首选项可能尚未设置
      if let weekOfInstall = Preferences.DAU.weekOfInstallation.value ??
          Preferences.DAU.installationDate.value?.mondayOfCurrentWeekFormatted,
         AppConstants.buildChannel != .debug {
        AppState.shared.braveCore.initializeP3AService(
          forChannel: AppConstants.buildChannel.serverChannelParam,
          weekOfInstall: weekOfInstall
        )
      }
      
      Task(priority: .low) {
        await self.cleanUpLargeTemporaryDirectory()
      }
      
      Task(priority: .high) {
        // 立即开始准备广告拦截服务，以便更快地准备好
        await LaunchHelper.shared.prepareAdBlockServices(
          adBlockService: AppState.shared.braveCore.adblockService
        )
      }
      
      // 设置播放列表
      // 这将恢复播放列表中未完成的下载。因此，如果在应用程序关闭时启动了下载并中断了，我们将在下次启动时重新开始它。
      Task(priority: .low) { @MainActor in
        PlaylistManager.shared.setupPlaylistFolder()
        PlaylistManager.shared.restoreSession()
      }
      
      return shouldPerformAdditionalDelegateHandling
  }

  
#if canImport(BraveTalk)
  func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
    return BraveTalkJitsiCoordinator.sendAppLifetimeEvent(.continueUserActivity(userActivity, restorationHandler: restorationHandler))
  }
  
  func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    return BraveTalkJitsiCoordinator.sendAppLifetimeEvent(.openURL(url, options: options))
  }
#endif
  
  func applicationWillTerminate(_ application: UIApplication) {
      // 关闭应用程序时，执行 AppState 中的 profile 关闭操作
      AppState.shared.profile.shutdown()
      
     // 移除 IAP 观察者（根据需要取消注释）
     // SKPaymentQueue.default().remove(BraveVPN.iapObserver)

      // 清理 BraveCore
      AppState.shared.braveCore.syncAPI.removeAllObservers()

      // 打印调试信息，表示应用程序已经干净地终止
      log.debug("Cleanly Terminated the Application")
  }


  func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
    if let presentedViewController = window?.rootViewController?.presentedViewController {
      return presentedViewController.supportedInterfaceOrientations
    } else {
      return window?.rootViewController?.supportedInterfaceOrientations ?? .portraitUpsideDown
    }
  }

  fileprivate func setUserAgent() {
      // 设置用户代理为桌面模式
      let userAgent = UserAgent.userAgentForDesktopMode

      // 设置图片加载器和图标获取器。
      // 这只需要在运行时执行一次。请注意，我们在这里使用了可从扩展中读取的默认值，
      // 因此它们可以直接使用缓存的标识符。

      SDWebImageDownloader.shared.setValue(userAgent, forHTTPHeaderField: "User-Agent")

      // 设置 WebcompatReporter 的用户代理
      WebcompatReporter.userAgent = userAgent

      // 记录用户代理以供搜索建议客户端使用
      SearchViewController.userAgent = userAgent
  }
  

  /// 如果临时目录的总大小超过阈值（以字节为单位），则清理临时目录
  private nonisolated func cleanUpLargeTemporaryDirectory(thresholdInBytes: Int = 100_000_000) async {
      let fileManager = FileManager.default
      let tmp = fileManager.temporaryDirectory
      guard let enumerator = fileManager.enumerator(
          at: tmp,
          includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .totalFileSizeKey]
      ) else { return }
      var totalSize: Int = 0
      while let fileURL = enumerator.nextObject() as? URL {
          guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .totalFileSizeKey]),
                let isRegularFile = values.isRegularFile,
                isRegularFile else {
              continue
          }
          totalSize += values.totalFileAllocatedSize ?? values.totalFileSize ?? 0
          if totalSize > thresholdInBytes {
              // 完全删除 tmp 目录，然后重新创建
              do {
                  try fileManager.removeItem(at: tmp)
                  try fileManager.createDirectory(at: tmp, withIntermediateDirectories: false)
              } catch {
                  log.warning("无法删除和重新创建超出大小限制的 tmp 目录：\(error.localizedDescription)")
              }
              return
          }
      }
  }

}

extension AppDelegate: MFMailComposeViewControllerDelegate {
  func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
    // Dismiss the view controller and start the app up
    controller.dismiss(animated: true, completion: nil)
  }
}

extension AppDelegate {
  // MARK: UISceneSession Lifecycle

  func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return UISceneConfiguration(
      name: connectingSceneSession.configuration.name,
      sessionRole: connectingSceneSession.role
    ).then {
      $0.sceneClass = connectingSceneSession.configuration.sceneClass
      $0.delegateClass = connectingSceneSession.configuration.delegateClass
    }
  }

  func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    
    sceneSessions.forEach { session in
      if let windowIdString = BrowserState.getWindowInfo(from: session).windowId,
         let windowId = UUID(uuidString: windowIdString) {
        SessionWindow.delete(windowId: windowId)
      } else if let userActivity = session.scene?.userActivity,
                let windowIdString = BrowserState.getWindowInfo(from: userActivity).windowId,
                let windowId = UUID(uuidString: windowIdString) {
        SessionWindow.delete(windowId: windowId)
      }
    }
  }
}
