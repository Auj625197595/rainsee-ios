/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import WebKit
import Shared
import Storage
import SnapKit
import Data
import BraveShared
import BraveCore
import CoreData
import StoreKit
import BraveUI
import NetworkExtension
import SwiftUI
import class Combine.AnyCancellable
import BraveWallet
import BraveVPN
import BraveNews
import Preferences
import os.log
#if canImport(BraveTalk)
import BraveTalk
#endif
import Favicon
import Onboarding
import Growth
import BraveShields
import CertificateUtilities
import ScreenTime


private let KVOs: [KVOConstants] = [
  .estimatedProgress,
  .loading,
  .canGoBack,
  .canGoForward,
  .URL,
  .title,
  .hasOnlySecureContent,
  .serverTrust,
  ._sampledPageTopColor
]

public class BrowserViewController: UIViewController {
     
//mark删除
    func sendRequest(cookie: String) {
    }

    func showAlert(message: String) {
        let alertController = UIAlertController(title: Strings.Other.alertTitle, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        
        // 获取当前显示的视图控制器
        if let topViewController = UIApplication.shared.windows.first?.rootViewController {
            topViewController.present(alertController, animated: true, completion: nil)
        }
    }


    
    
    // 网页容器
    let webViewContainer = UIView()

    // 截图助手，用于处理截图相关功能
    private(set) lazy var screenshotHelper = ScreenshotHelper(tabManager: tabManager)

    // 顶部工具栏
    private(set) lazy var topToolbar: TopToolbarView = {
        // 设置URL栏，包装在一个视图中以获得透明效果
        let topToolbar = TopToolbarView(voiceSearchSupported: speechRecognizer.isVoiceSearchAvailable, privateBrowsingManager: privateBrowsingManager)
        topToolbar.translatesAutoresizingMaskIntoConstraints = false
        topToolbar.delegate = self
        topToolbar.tabToolbarDelegate = self

        let toolBarInteraction = UIContextMenuInteraction(delegate: self)
        topToolbar.locationView.addInteraction(toolBarInteraction)
        
        if UIDevice.current.userInterfaceIdiom == .phone {
            topToolbar.isHidden = true
        }
       
        return topToolbar
    }()

    // 标签栏
    private(set) lazy var tabsBar: TabsBarViewController = {
        let tabsBar = TabsBarViewController(tabManager: tabManager)
        tabsBar.delegate = self
        return tabsBar
    }()

    // 用于提供顶部和底部工具栏背景效果的视图
    private(set) lazy var header = HeaderContainerView(privateBrowsingManager: privateBrowsingManager)
    private let headerHeightLayoutGuide = UILayoutGuide()

    // 底部工具栏
    let footer: UIView = {
        let footer = UIView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        return footer
    }()

    private let topTouchArea: UIButton = {
        let topTouchArea = UIButton()
        topTouchArea.isAccessibilityElement = false
        return topTouchArea
    }()

    private let bottomTouchArea: UIButton = {
        let bottomTouchArea = UIButton()
        bottomTouchArea.isAccessibilityElement = false
        return bottomTouchArea
    }()

    /// 允许显示/隐藏标签栏的约束
    private var webViewContainerTopOffset: Constraint?

    /// 用于显示私人标签的灰色背景
    private let webViewContainerBackdrop: UIView = {
        let webViewContainerBackdrop = UIView()
        webViewContainerBackdrop.backgroundColor = .braveBackground
        webViewContainerBackdrop.alpha = 0
        return webViewContainerBackdrop
    }()

    var readerModeBar: ReaderModeBarView?
    var readerModeCache: ReaderModeCache

    private(set) lazy var statusBarOverlay: UIView = {
        // 用于覆盖未剪切的Web视图内容的临时解决方法
        let statusBarOverlay = UIView()
        statusBarOverlay.backgroundColor = privateBrowsingManager.browserColors.chromeBackground
        return statusBarOverlay
    }()

    private(set) var toolbar: BottomToolbarView?
    var searchLoader: SearchLoader?
    var searchController: SearchViewController?
    var favoritesController: FavoritesViewController?

    /// 应该添加到此视图上方的所有内容，位于底部工具栏之上（查找页面/小吃饭）
    let alertStackView: UIStackView = {
        let alertStackView = UIStackView()
        alertStackView.axis = .vertical
        alertStackView.alignment = .center
        return alertStackView
    }()

    var findInPageBar: FindInPageBar?
    var pageZoomBar: UIHostingController<PageZoomView>?
    private var pageZoomListener: NSObjectProtocol?
    private var openTabsModelStateListener: SendTabToSelfModelStateListener?
    private var syncServiceStateListener: AnyObject?
    let collapsedURLBarView = CollapsedURLBarView()

    // 用于所有收藏夹vcs的单个数据源
    public let backgroundDataSource: NTPDataSource
    let feedDataSource: FeedDataSource

    private var postSetupTasks: [() -> Void] = []
    private var setupTasksCompleted: Bool = false

    private var privateModeCancellable: AnyCancellable?
    private var appReviewCancelable: AnyCancellable?
    private var adFeatureLinkageCancelable: AnyCancellable?
    var onPendingRequestUpdatedCancellable: AnyCancellable?

    var action: ((String) -> Void)?

    
    /// 语音搜索
    var voiceSearchViewController: PopupViewController<VoiceSearchInputView>?
    var voiceSearchCancelable: AnyCancellable?
    let speechRecognizer = SpeechRecognizer()

    /// 自定义搜索引擎
    var openSearchEngine: OpenSearchReference?

    lazy var customSearchEngineButton = OpenSearchEngineButton(hidesWhenDisabled: false).then {
        $0.addTarget(self, action: #selector(addCustomSearchEngineForFocusedElement), for: .touchUpInside)
        $0.accessibilityIdentifier = "BrowserViewController.customSearchEngineButton"
        $0.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        $0.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    }

    var customSearchBarButtonItemGroup: UIBarButtonItemGroup?

    // 弹出窗口旋转处理
    var displayedPopoverController: UIViewController?
    var updateDisplayedPopoverProperties: (() -> Void)?

    public let windowId: UUID
    let profile: Profile
    let attributionManager: AttributionManager
    let braveCore: BraveCoreMain
    let tabManager: TabManager
    let migration: Migration?
    let bookmarkManager: BookmarkManager
    public let privateBrowsingManager: PrivateBrowsingManager


    /// 上一次会话是否由于崩溃而结束
    private let crashedLastSession: Bool

    // 用于在键盘动画期间放置在底部栏下面到工具栏之间的视图，以避免URL栏浮动时的奇怪外观
    private let bottomBarKeyboardBackground = UIView().then {
        $0.isUserInteractionEnabled = false
    }

    var toolbarVisibilityViewModel = ToolbarVisibilityViewModel(estimatedTransitionDistance: 44)
    private var toolbarLayoutGuide = UILayoutGuide().then {
        $0.identifier = "toolbar-visibility-layout-guide"
    }
    private var toolbarTopConstraint: Constraint?
    private var toolbarBottomConstraint: Constraint?
    var toolbarVisibilityCancellable: AnyCancellable?

    var keyboardState: KeyboardState?

    var pendingToast: Toast?  // 可能正在等待BVC出现之前显示的提示
    var downloadToast: DownloadToast?  // 显示组合下载进度的提示
    var addToPlayListActivityItem: (enabled: Bool, item: PlaylistInfo?)?  // 用于确定是否应添加AddToListActivity
    var openInPlaylistActivityItem: (enabled: Bool, item: PlaylistInfo?)?  // 用于确定是否应显示OpenInPlaylistActivity
    var shouldDownloadNavigationResponse: Bool = false
    var pendingDownloads = [WKDownload: PendingDownload]()

    var navigationToolbar: ToolbarProtocol {
        return toolbar ?? topToolbar
    }

    // 通过`webView(_:decidePolicyFor:decisionHandler:)`跟踪允许的`URLRequest`，以便在接收到`URLResponse`时获取原始`URLRequest`。这样可以在用户请求下载文件时重新触发`URLRequest`。
    var pendingRequests = [String: URLRequest]()

    // 当用户从上下文菜单中点击“下载链接”时设置。然后，通过与此web视图匹配的`WKNavigationDelegate`强制下载下一个请求。
    weak var pendingDownloadWebView: WKWebView?

    let downloadQueue = DownloadQueue()

    private var cancellables: Set<AnyCancellable> = []

    let rewards: BraveRewards
    var rewardsObserver: RewardsObserver?
    var promotionFetchTimer: Timer?
    private var notificationsHandler: AdsNotificationHandler?
    let notificationsPresenter = BraveNotificationsPresenter()
    var publisher: BraveCore.BraveRewards.PublisherInfo?

    //let vpnProductInfo = VPNProductInfo()

    /// 控制器需要生物识别身份验证时将使用的Window Protection实例
    public var windowProtection: WindowProtection?

    // 与产品通知相关的属性

    /// 跟踪产品通知是否已显示，以避免在现有弹出窗口上再次尝试显示另一个弹出窗口
    var benchmarkNotificationPresented = false
    /// 将临时保留的字符串域，用于跟踪已显示的站点通知，以避免一遍又一遍地处理站点列表
    var currentBenchmarkWebsite = ""

    /// 用于确定何时呈现基准弹出窗口的Navigation Helper
    /// 当前会话广告计数与实时广告计数进行比较
    /// 这样用户就不会直接被引入弹出窗口
    let benchmarkCurrentSessionAdCount = BraveGlobalShieldStats.shared.adblock + BraveGlobalShieldStats.shared.trackingProtection

    /// Brave Widgets使用的Navigation Helper
    private(set) lazy var navigationHelper = BrowserNavigationHelper(self)

    /// 用于确定Tab Tray是否在屏幕上活动，以决定是否应该呈现弹出窗口
    var isTabTrayActive = false

    /// 用于确定阻止统计信息的数据源对象
    var benchmarkBlockingDataSource: BlockingSummaryDataSource?

    /// 跟踪全屏标注或入门是否已显示，以避免在现有标注上再次尝试显示另一个标注
    var isOnboardingOrFullScreenCalloutPresented = false

    private(set) var widgetBookmarksFRC: NSFetchedResultsController<Favorite>?
    var widgetFaviconFetchers: [Task<Favicon, Error>] = []
    let deviceCheckClient: DeviceCheckClient?

    #if canImport(BraveTalk)
    // Brave Talk本机实现
    let braveTalkJitsiCoordinator = BraveTalkJitsiCoordinator()
    #endif

    /// 当前打开的WalletStore
   // weak var walletStore: WalletStore?

    var processAddressBarTask: Task<(), Never>?
    var topToolbarDidPressReloadTask: Task<(), Never>?

    /// VPN订阅操作的应用内购买观察者
    // let iapObserver: IAPObserver

    public init(
       windowId: UUID,
       profile: Profile,
       attributionManager: AttributionManager,
       diskImageStore: DiskImageStore?,
       braveCore: BraveCoreMain,
       rewards: BraveRewards,
       migration: Migration?,
       crashedLastSession: Bool,
       newsFeedDataSource: FeedDataSource,
       privateBrowsingManager: PrivateBrowsingManager,
       action: @escaping ((String) -> Void)
     ) {
       // 初始化各个属性
       self.windowId = windowId
       self.profile = profile
       self.attributionManager = attributionManager
       self.braveCore = braveCore
       self.bookmarkManager = BookmarkManager(bookmarksAPI: braveCore.bookmarksAPI)
       self.rewards = rewards
       self.migration = migration
       self.crashedLastSession = crashedLastSession
       self.privateBrowsingManager = privateBrowsingManager
       self.feedDataSource = newsFeedDataSource
       feedDataSource.historyAPI = braveCore.historyAPI
       backgroundDataSource = .init(service: braveCore.backgroundImagesService,
                                    privateBrowsingManager: privateBrowsingManager)

       self.action = action
       // 初始化TabManager
       self.tabManager = TabManager(
         windowId: windowId,
         prefs: profile.prefs,
         rewards: rewards,
         tabGeneratorAPI: braveCore.tabGeneratorAPI,
         privateBrowsingManager: privateBrowsingManager
       )
       
       // 将常规标签添加到同步链
       if Preferences.Chromium.syncOpenTabsEnabled.value {
         tabManager.addRegularTabsToSyncChain()
       }
       
       // 删除过时的最近关闭标签
       tabManager.deleteOutdatedRecentlyClosed()

       // 设置ReaderMode缓存
       self.readerModeCache = ReaderModeScriptHandler.cache(for: tabManager.selectedTab)

       // 如果BraveRewards不可用，禁用奖励服务
       if !BraveRewards.isAvailable {
         rewards.isEnabled = false
       } else {
         if rewards.isEnabled && !Preferences.Rewards.rewardsToggledOnce.value {
           Preferences.Rewards.rewardsToggledOnce.value = true
         }
       }

       // 初始化DeviceCheckClient
       self.deviceCheckClient = DeviceCheckClient(environment: BraveRewards.Configuration.current().environment)

       // 如果当前区域是"JP"（日本），初始化BlockingSummaryDataSource
       if Locale.current.regionCode == "JP" {
         benchmarkBlockingDataSource = BlockingSummaryDataSource()
       }
       
       // 初始化父类
       super.init(nibName: nil, bundle: nil)
       didInit()
       
      // iapObserver.delegate = self

       // 奖励服务启动后执行设置Ledger的操作
       rewards.rewardsServiceDidStart = { [weak self] _ in
         self?.setupLedger()
       }

       // 设置rewards.ads.captchaHandler
       rewards.ads.captchaHandler = self
       let shouldStartAds = rewards.ads.isEnabled || Preferences.BraveNews.isEnabled.value
       if shouldStartAds {
         // 只有在启用广告时才自动启动奖励服务
         if rewards.isEnabled {
           rewards.startRewardsService(nil)
         } else {
           rewards.ads.initialize() { _ in }
         }
       }

       // 设置feedDataSource的获取AdsAPI闭包
       self.feedDataSource.getAdsAPI = {
         // ads对象在关闭时会被重新创建，所以需要确保News从BraveRewards容器中获取它
         return rewards.ads
       }
       
       // 监听从其他设备发送的标签信息
       openTabsModelStateListener = braveCore.sendTabAPI.add(
         SendTabToSelfStateObserver { [weak self] stateChange in
           if case .sendTabToSelfEntriesAddedRemotely(let newEntries) = stateChange {
             // 获取从同步会话中发送的最后一个URL
             if let requestedURL = newEntries.last?.url {
               self?.presentTabReceivedToast(url: requestedURL)
             }
           }
         })

       // 监听同步链状态变化
       syncServiceStateListener = braveCore.syncAPI.addServiceStateObserver { [weak self] in
         guard let self = self else { return }
         // 观察同步状态以确定同步链是否从另一台设备上删除 - 清理本地同步链
         if self.braveCore.syncAPI.shouldLeaveSyncGroup {
           self.braveCore.syncAPI.leaveSyncGroup()
         }
       }
       
       // 如果启用了屏幕时间，初始化screenTimeViewController
       if Preferences.Privacy.screenTimeEnabled.value {
         screenTimeViewController = STWebpageController()
       }
     }


    deinit {
        // 移除打开标签模型状态观察者
        if let observer = openTabsModelStateListener {
            braveCore.sendTabAPI.removeObserver(observer)
        }
    }


  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    if UIDevice.current.userInterfaceIdiom == .phone {
      return .allButUpsideDown
    } else {
      return .all
    }
  }

  override public func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)

    dismissVisibleMenus()

    coordinator.animate(
      alongsideTransition: { context in
        if let popover = self.displayedPopoverController {
          self.updateDisplayedPopoverProperties?()
          self.present(popover, animated: true, completion: nil)
        }
#if canImport(BraveTalk)
        self.braveTalkJitsiCoordinator.resetPictureInPictureBounds(.init(size: size))
#endif
      },
      completion: { _ in
        if let tab = self.tabManager.selectedTab {
          WindowRenderScriptHandler.executeScript(for: tab)
        }
      })
  }

  override public func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    ScriptFactory.shared.clearCaches()
    
    Task {
      await AdBlockStats.shared.didReceiveMemoryWarning()
    }

    for tab in tabManager.tabsForCurrentMode where tab.id != tabManager.selectedTab?.id {
      tab.newTabPageViewController = nil
    }
  }

  private var rewardsEnabledObserveration: NSKeyValueObservation?

  fileprivate func didInit() {
    updateApplicationShortcuts()
    tabManager.addDelegate(self)
    tabManager.addNavigationDelegate(self)
  //  UserScriptManager.shared.fetchWalletScripts(from: braveCore.braveWalletAPI)
    downloadQueue.delegate = self

    // Observe some user preferences
    Preferences.Privacy.privateBrowsingOnly.observe(from: self)
    Preferences.General.tabBarVisibility.observe(from: self)
    Preferences.UserAgent.alwaysRequestDesktopSite.observe(from: self)
    Preferences.General.enablePullToRefresh.observe(from: self)
    Preferences.General.mediaAutoBackgrounding.observe(from: self)
    Preferences.General.youtubeHighQuality.observe(from: self)
    Preferences.General.defaultPageZoomLevel.observe(from: self)
    Preferences.Shields.allShields.forEach { $0.observe(from: self) }
    Preferences.Privacy.blockAllCookies.observe(from: self)
    Preferences.Rewards.hideRewardsIcon.observe(from: self)
    Preferences.Rewards.rewardsToggledOnce.observe(from: self)
    Preferences.Playlist.enablePlaylistMenuBadge.observe(from: self)
    Preferences.Playlist.enablePlaylistURLBarButton.observe(from: self)
    Preferences.Playlist.syncSharedFoldersAutomatically.observe(from: self)
    Preferences.NewTabPage.backgroundSponsoredImages.observe(from: self)
    ShieldPreferences.blockAdsAndTrackingLevelRaw.observe(from: self)
    Preferences.Privacy.screenTimeEnabled.observe(from: self)
    
    pageZoomListener = NotificationCenter.default.addObserver(forName: PageZoomView.notificationName, object: nil, queue: .main) { [weak self] _ in
      self?.tabManager.allTabs.forEach({
        guard let url = $0.webView?.url else { return }
        let zoomLevel = self?.privateBrowsingManager.isPrivateBrowsing == true ? 1.0 : Domain.getPersistedDomain(for: url)?.zoom_level?.doubleValue ?? Preferences.General.defaultPageZoomLevel.value
        
        $0.webView?.setValue(zoomLevel, forKey: PageZoomHandler.propertyName)
      })
    }
    
    rewardsEnabledObserveration = rewards.ads.observe(\.isEnabled, options: [.new]) { [weak self] _, _ in
      guard let self = self else { return }
      self.updateRewardsButtonState()
      self.setupAdsNotificationHandler()
      self.recordAdsUsageType()
    }
    Preferences.Playlist.webMediaSourceCompatibility.observe(from: self)
    Preferences.PrivacyReports.captureShieldsData.observe(from: self)
    Preferences.PrivacyReports.captureVPNAlerts.observe(from: self)
  //  Preferences.Wallet.defaultEthWallet.observe(from: self)

    if rewards.rewardsAPI != nil {
      // Ledger was started immediately due to user having ads enabled
      setupLedger()
    }

    Preferences.NewTabPage.attemptToShowClaimRewardsNotification.value = true

      backgroundDataSource.initializeFavorites = { sites in
          // 异步切换到主队列执行
          DispatchQueue.main.async {
              // 在此处延迟设置标志以确保首选项已初始化
              defer { Preferences.NewTabPage.preloadedFavoritiesInitialized.value = true }

              // 如果已经初始化或已存在收藏夹，直接返回
              if Preferences.NewTabPage.preloadedFavoritiesInitialized.value || Favorite.hasFavorites {
                  return
              }

              // 如果提供的站点为空，则添加默认收藏
              guard let sites = sites, !sites.isEmpty else {
                  FavoritesHelper.addDefaultFavorites()
                  return
              }

              // 将提供的站点转换为自定义收藏，并添加到收藏夹
              let customFavorites = sites.compactMap { $0.asFavoriteSite }
              Favorite.add(from: customFavorites)
          }
      }


    setupAdsNotificationHandler()
    backgroundDataSource.replaceFavoritesIfNeeded = { sites in
      if Preferences.NewTabPage.initialFavoritesHaveBeenReplaced.value { return }

      guard let sites = sites, !sites.isEmpty else { return }

      DispatchQueue.main.async {
        let defaultFavorites = PreloadedFavorites.getList()
        let currentFavorites = Favorite.allFavorites

        if defaultFavorites.count != currentFavorites.count {
          return
        }

        let exactSameFavorites = Favorite.allFavorites
          .filter {
            guard let urlString = $0.url,
              let url = URL(string: urlString),
              let title = $0.displayTitle
            else {
              return false
            }

            return defaultFavorites.contains(where: { defaultFavorite in
              defaultFavorite.url == url && defaultFavorite.title == title
            })
          }

        if currentFavorites.count == exactSameFavorites.count {
          let customFavorites = sites.compactMap { $0.asFavoriteSite }
          Preferences.NewTabPage.initialFavoritesHaveBeenReplaced.value = true
          Favorite.forceOverwriteFavorites(with: customFavorites)
        }
      }
    }

    // Setup Widgets FRC
    widgetBookmarksFRC = Favorite.frc()
    widgetBookmarksFRC?.fetchRequest.fetchLimit = 16
    widgetBookmarksFRC?.delegate = self
    try? widgetBookmarksFRC?.performFetch()

    updateWidgetFavoritesData()

    // Eliminate the older usage days
    // Used in App Rating criteria
    AppReviewManager.shared.processMainCriteria(for: .daysInUse)
    
    // P3A Record
    maybeRecordInitialShieldsP3A()
   // recordVPNUsageP3A(vpnEnabled: BraveVPN.isConnected)
    recordAccessibilityDisplayZoomEnabledP3A()
    recordAccessibilityDocumentsDirectorySizeP3A()
    recordTimeBasedNumberReaderModeUsedP3A(activated: false)
    recordGeneralBottomBarLocationP3A()
    PlaylistP3A.recordHistogram()
    recordAdsUsageType()
    
    // Revised Review Handling
    AppReviewManager.shared.handleAppReview(for: .revisedCrossPlatform, using: self)
  }

  private func setupAdsNotificationHandler() {
    notificationsHandler = AdsNotificationHandler(ads: rewards.ads,
                                                  presentingController: self,
                                                  notificationsPresenter: notificationsPresenter)
    notificationsHandler?.canShowNotifications = { [weak self] in
      guard let self = self else { return false }
      return !self.privateBrowsingManager.isPrivateBrowsing && !self.topToolbar.inOverlayMode
    }
    notificationsHandler?.actionOccured = { [weak self] ad, action in
      guard let self = self, let ad = ad else { return }
      if action == .opened {
        var url = URL(string: ad.targetURL)
        if url == nil,
           let percentEncodedURLString =
            ad.targetURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
          // Try to percent-encode the string and try that
          url = URL(string: percentEncodedURLString)
        }
        guard let targetURL = url else {
          assertionFailure("Invalid target URL for creative instance id: \(ad.creativeInstanceID)")
          return
        }
        let request = URLRequest(url: targetURL)
        self.tabManager.addTabAndSelect(request, isPrivate: self.privateBrowsingManager.isPrivateBrowsing)
      }
    }
  }

    // 根据先前的Trait Collection 判断是否应该显示底部工具栏
    func shouldShowFooterForTraitCollection(_ previousTraitCollection: UITraitCollection) -> Bool {
        
        // 判断垂直尺寸类别是否不是紧凑模式（compact）
        // 且水平尺寸类别是否不是正常模式（regular）
        return previousTraitCollection.verticalSizeClass != .compact && previousTraitCollection.horizontalSizeClass != .regular
    }

  
    // 根据指定的 UITraitCollection 更新 isUsingBottomBar 的私有方法
    private func updateUsingBottomBar(using traitCollection: UITraitCollection) {
        // 根据偏好设置和设备特性，确定是否使用底部工具栏
        isUsingBottomBar = Preferences.General.isUsingBottomBar.value &&
            traitCollection.horizontalSizeClass == .compact &&
            traitCollection.verticalSizeClass == .regular &&
            traitCollection.userInterfaceIdiom == .phone
        
        // 如果存在 favoritesController，则重新插入其视图
        if let favoritesController {
            insertFavoritesControllerView(favoritesController: favoritesController)
        }
    }


  public override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    
    topTouchArea.isEnabled = view.safeAreaInsets.top > 0
    statusBarOverlay.isHidden = view.safeAreaInsets.top.isZero
  }
  
    // 更新工具栏状态，基于新的Trait Collection，并可选择性地使用过渡协调器
    fileprivate func updateToolbarStateForTraitCollection(_ newCollection: UITraitCollection, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator? = nil) {
        
        // 确定是否应该显示底部工具栏
        let showToolbar = shouldShowFooterForTraitCollection(newCollection)
        
        // 更新底部触摸区域的启用状态
        bottomTouchArea.isEnabled = showToolbar
        
        // 设置顶部工具栏的显示状态
        topToolbar.setShowToolbar(!showToolbar)
        
        // 根据需要添加或移除工具栏
        if (showToolbar && toolbar == nil) || (!showToolbar && toolbar != nil) {
            
            // 如果工具栏存在，则从视图中移除
            toolbar?.removeFromSuperview()
            toolbar?.tabToolbarDelegate = nil
            toolbar = nil
            
            // 如果需要显示工具栏，则创建并添加
            if showToolbar {
                toolbar = BottomToolbarView(privateBrowsingManager: privateBrowsingManager)
                toolbar?.setSearchButtonState(url: tabManager.selectedTab?.url)
                
                footer.addSubview(toolbar!)
                toolbar?.tabToolbarDelegate = self
                toolbar?.menuButton.setBadges(Array(topToolbar.menuButton.badges.keys))
            }
            
            // 触发视图约束的更新
            view.setNeedsUpdateConstraints()
        }
        
        // 使用Tab Manager更新工具栏
        updateToolbarUsingTabManager(tabManager)
        
        // 使用新的Trait Collection更新底部栏
        updateUsingBottomBar(using: newCollection)
        
        // 如果选定了选项卡，并且WebView存在，则更新URL条、导航栏状态和顶部工具栏
        if let tab = tabManager.selectedTab,
            let webView = tab.webView {
            updateURLBar()
            navigationToolbar.updateBackStatus(webView.canGoBack)
            updateForwardStatusIfNeeded(webView: webView)
            topToolbar.locationView.loading = tab.loading
        }

        // 设置工具栏可见性模型的工具栏状态为展开
        toolbarVisibilityViewModel.toolbarState = .expanded
        
        // 更新选项卡栏的可见性
        updateTabsBarVisibility()
    }

  
  func updateToolbarSecureContentState(_ secureContentState: TabSecureContentState) {
    topToolbar.secureContentState = secureContentState
    collapsedURLBarView.secureContentState = secureContentState
  }
  
  func updateToolbarCurrentURL(_ currentURL: URL?) {
    topToolbar.currentURL = currentURL
    collapsedURLBarView.currentURL = currentURL
    updateScreenTimeUrl(currentURL)
  }

  override public func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
    super.willTransition(to: newCollection, with: coordinator)

    // During split screen launching on iPad, this callback gets fired before viewDidLoad gets a chance to
    // set things up. Make sure to only update the toolbar state if the view is ready for it.
    if isViewLoaded {
      updateToolbarStateForTraitCollection(newCollection, withTransitionCoordinator: coordinator)
    }

    displayedPopoverController?.dismiss(animated: true, completion: nil)
    coordinator.animate(
      alongsideTransition: { context in
        if self.isViewLoaded {
          self.updateStatusBarOverlayColor()
          self.bottomBarKeyboardBackground.backgroundColor = self.topToolbar.backgroundColor
          self.setNeedsStatusBarAppearanceUpdate()
        }
      },
      completion: { _ in
        if let tab = self.tabManager.selectedTab {
          WindowRenderScriptHandler.executeScript(for: tab)
        }
      })
  }

  func dismissVisibleMenus() {
    displayedPopoverController?.dismiss(animated: true)
  }

  @objc func sceneDidEnterBackgroundNotification(_ notification: NSNotification) {
    guard let scene = notification.object as? UIScene, scene == currentScene else {
      return
    }
    
    displayedPopoverController?.dismiss(animated: false) {
      self.updateDisplayedPopoverProperties = nil
      self.displayedPopoverController = nil
    }
  }
  
  @objc func appWillTerminateNotification() {
    tabManager.saveAllTabs()
    tabManager.removePrivateWindows()
  }
  
    // 当收缩状态的 URL 栏被点击时调用的方法
    @objc private func tappedCollapsedURLBar() {
        // 如果键盘处于打开状态，同时使用底部工具栏且顶部工具栏不处于覆盖模式
        if keyboardState != nil && isUsingBottomBar && !topToolbar.inOverlayMode {
            // 隐藏键盘
            view.endEditing(true)
        } else {
            // 否则，执行 tappedTopArea 方法
            tappedTopArea()
        }
    }


  @objc func tappedTopArea() {
    toolbarVisibilityViewModel.toolbarState = .expanded
  }

  @objc func sceneWillResignActiveNotification(_ notification: NSNotification) {
    guard let scene = notification.object as? UIScene, scene == currentScene else {
      return
    }
    
    tabManager.saveAllTabs()
    
    // Dismiss any popovers that might be visible
    displayedPopoverController?.dismiss(animated: false) {
      self.updateDisplayedPopoverProperties = nil
      self.displayedPopoverController = nil
    }

    // If we are displaying a private tab, hide any elements in the tab that we wouldn't want shown
    // when the app is in the home switcher
    if let tab = tabManager.selectedTab, tab.isPrivate {
      webViewContainerBackdrop.alpha = 1
      webViewContainer.alpha = 0
      activeNewTabPageViewController?.view.alpha = 0
      favoritesController?.view.alpha = 0
      searchController?.view.alpha = 0
      header.contentView.alpha = 0
      presentedViewController?.popoverPresentationController?.containerView?.alpha = 0
      presentedViewController?.view.alpha = 0
    }
    
    // Stop Voice Search and dismiss controller
    stopVoiceSearch()
  }

  @objc func vpnConfigChanged() {
    // Load latest changes to the vpn.
//    NEVPNManager.shared().loadFromPreferences { _ in }
//    
//    if case .purchased(let enabled) = BraveVPN.vpnState, enabled {
//      recordVPNUsageP3A(vpnEnabled: true)
//    }
  }

  @objc func sceneDidBecomeActiveNotification(_ notification: NSNotification) {
    guard let scene = notification.object as? UIScene, scene == currentScene else {
      return
    }
    
    guard let tab = tabManager.selectedTab, tab.isPrivate else {
      return
    }
    // Re-show any components that might have been hidden because they were being displayed
    // as part of a private mode tab
    UIView.animate(
      withDuration: 0.2, delay: 0, options: UIView.AnimationOptions(),
      animations: {
        self.webViewContainer.alpha = 1
        self.header.contentView.alpha = 1
        self.activeNewTabPageViewController?.view.alpha = 1
        self.favoritesController?.view.alpha = 1
        self.searchController?.view.alpha = 1
        self.presentedViewController?.popoverPresentationController?.containerView?.alpha = 1
        self.presentedViewController?.view.alpha = 1
        self.view.backgroundColor = .clear
      },
      completion: { _ in
        self.webViewContainerBackdrop.alpha = 0
      })
  }
  
  private(set) var isUsingBottomBar: Bool = false {
    didSet {
        // 更新与 isUsingBottomBar 相关的视图和约束
        header.isUsingBottomBar = isUsingBottomBar // 更新头部视图的 isUsingBottomBar 属性
        collapsedURLBarView.isUsingBottomBar = isUsingBottomBar // 更新收缩状态 URL 栏的 isUsingBottomBar 属性
        searchController?.isUsingBottomBar = isUsingBottomBar // 更新搜索控制器的 isUsingBottomBar 属性
        bottomBarKeyboardBackground.isHidden = !isUsingBottomBar // 根据 isUsingBottomBar 的值设置底部键盘背景的隐藏状态
        topToolbar.displayTabTraySwipeGestureRecognizer?.isEnabled = isUsingBottomBar // 设置顶部工具栏的标签托盘滑动手势的启用状态
        updateTabsBarVisibility() // 更新标签栏的可见性
        updateStatusBarOverlayColor() // 更新状态栏覆盖层的颜色
        updateViewConstraints() // 更新视图的约束

    }
  }
    @objc func handleSmallBottomTap(_ sender: UITapGestureRecognizer) {
            // 处理点击事件的代码
            print("View Tapped!")
        }
  override public func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .braveBackground
    
    // Add layout guides
    view.addLayoutGuide(pageOverlayLayoutGuide)
    view.addLayoutGuide(headerHeightLayoutGuide)
    view.addLayoutGuide(toolbarLayoutGuide)
    
    // Add views
    view.addSubview(webViewContainerBackdrop)
    view.addSubview(webViewContainer)
    header.expandedBarStackView.addArrangedSubview(topToolbar)
    header.collapsedBarContainerView.addSubview(collapsedURLBarView)
      
      
    addChild(tabsBar)
    tabsBar.didMove(toParent: self)

    view.addSubview(alertStackView)
    view.addSubview(bottomTouchArea)
    view.addSubview(topTouchArea)
    view.addSubview(bottomBarKeyboardBackground)
    view.addSubview(footer)
    view.addSubview(statusBarOverlay)
    view.addSubview(header)
    
    // For now we hide some elements so they are not visible
    header.isHidden = true
    footer.isHidden = true
    
    // Setup constraints
    setupConstraints()
    updateToolbarStateForTraitCollection(self.traitCollection)
    
    // Legacy Review Handling
    AppReviewManager.shared.handleAppReview(for: .legacy, using: self)
    
    // Adding Screenshot Service Delegate to browser to fetch full screen webview screenshots
    currentScene?.screenshotService?.delegate = self
    
    self.setupInteractions()
      
          //mark删除
      let user = Preferences.User.mkey.value
      if user != "" {
          self.sendRequest(cookie: user)
      }
      
      
      // 延迟3秒执行
      let delayInSeconds: Double = 3.0
      // 在全局队列中创建一个子线程
      let dispatchQueue = DispatchQueue.global(qos: .background)
      // 延迟执行任务
      dispatchQueue.asyncAfter(deadline: .now() + delayInSeconds) {
          // 在这里放置需要延迟执行的代码
          let currentDate = Date()
          let timestamp = currentDate.timeIntervalSince1970
          if Preferences.User.mkey.value != "", Preferences.SyncRain.syncHome.value, Int(timestamp)-Preferences.SyncRain.syncLastHomeTime.value > 30 {
              Preferences.SyncRain.syncLastHomeTime.value = Int(timestamp)
              self.download(cookie: Preferences.User.mkey.value)
          }
        
          if Preferences.General.injectAdblock.value {
            
          }
         

      }
 

  }
  
    private func setupInteractions() {
        // 我们现在显示一些元素，因为我们准备好使用应用程序了
        header.isHidden = false
        footer.isHidden = false
        
        NotificationCenter.default.do {
          $0.addObserver(
            self, selector: #selector(sceneWillResignActiveNotification(_:)), 
            name: UIScene.willDeactivateNotification, object: nil)
          $0.addObserver(
            self, selector: #selector(sceneDidBecomeActiveNotification(_:)),
            name: UIScene.didActivateNotification, object: nil)
          $0.addObserver(
            self, selector: #selector(sceneDidEnterBackgroundNotification),
            name: UIScene.didEnterBackgroundNotification, object: nil)
          $0.addObserver(
            self, selector: #selector(appWillTerminateNotification),
            name: UIApplication.willTerminateNotification, object: nil)
          $0.addObserver(
            self, selector: #selector(resetNTPNotification),
            name: .adsOrRewardsToggledInSettings, object: nil)
          $0.addObserver(
            self, selector: #selector(vpnConfigChanged),
            name: .NEVPNConfigurationChange, object: nil)
          $0.addObserver(
            self, selector: #selector(updateShieldNotifications),
            name: NSNotification.Name(rawValue: BraveGlobalShieldStats.didUpdateNotification), object: nil)
        }
        
        BraveGlobalShieldStats.shared.$adblock
          .scan((BraveGlobalShieldStats.shared.adblock, BraveGlobalShieldStats.shared.adblock), { ($0.1, $1) })
          .sink { [weak self] (oldValue, newValue) in
            let change = newValue - oldValue
            if change > 0 {
              self?.recordDataSavedP3A(change: change)
            }
          }
          .store(in: &cancellables)
        
        KeyboardHelper.defaultHelper.addDelegate(self)
        UNUserNotificationCenter.current().delegate = self
        
        // 添加交互
        topTouchArea.addTarget(self, action: #selector(tappedTopArea), for: .touchUpInside)
        bottomTouchArea.addTarget(self, action: #selector(tappedTopArea), for: .touchUpInside)
        header.collapsedBarContainerView.addTarget(self, action: #selector(tappedCollapsedURLBar), for: .touchUpInside)
        updateRewardsButtonState()

        // 设置 UIDropInteraction 以处理从其他应用程序拖放链接到视图中的操作。
        let dropInteraction = UIDropInteraction(delegate: self)
        view.addInteraction(dropInteraction)
        topToolbar.addInteraction(dropInteraction)

        // 在获取之前添加小延迟可以提高其可靠性，


        // 计划默认浏览器本地通知
        // 如果通知尚未计划或
        // 在 Brave 中打开了外部 URL（这表明 Brave 被设置为默认值）
        if !Preferences.DefaultBrowserIntro.defaultBrowserNotificationScheduled.value {
          scheduleDefaultBrowserNotification()
        }

        privateModeCancellable = privateBrowsingManager
          .$isPrivateBrowsing
          .removeDuplicates()
          .receive(on: RunLoop.main)
          .sink(receiveValue: { [weak self] isPrivateBrowsing in
            guard let self = self else { return }
            self.updateStatusBarOverlayColor()
            self.bottomBarKeyboardBackground.backgroundColor = self.topToolbar.backgroundColor
            self.collapsedURLBarView.browserColors = self.privateBrowsingManager.browserColors
          })
        
        appReviewCancelable = AppReviewManager.shared
          .$isRevisedReviewRequired
          .removeDuplicates()
          .sink(receiveValue: { [weak self] isRevisedReviewRequired in
            guard let self = self else { return }
            if isRevisedReviewRequired {
              AppReviewManager.shared.isRevisedReviewRequired = false
              
              // 处理应用评级
              // 用户更改了 Brave News 源（点击关闭）
              AppReviewManager.shared.handleAppReview(for: .revised, using: self)
            }
          })
        
        adFeatureLinkageCancelable = attributionManager
          .$adFeatureLinkage
          .removeDuplicates()
          .sink(receiveValue: { [weak self] featureLinkageType in
            guard let self = self else { return }
            switch featureLinkageType {
            case .playlist:
              self.presentPlaylistController()
            case .vpn:
                Logger.module.info("vpn")
             // self.navigationHelper.openVPNBuyScreen(iapObserver: self.iapObserver)
            default:
              return
            }
          })
        // 监听偏好设置中 isUsingBottomBar 属性的变化
        Preferences.General.isUsingBottomBar.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // 弱引用 self，确保在闭包执行时不会形成强引用循环
                guard let self = self else { return }
                
                // 更新标签栏的可见性
                self.updateTabsBarVisibility()
                
                // 根据当前设备特性更新底部工具栏的使用状态
                self.updateUsingBottomBar(using: self.traitCollection)
            }
            .store(in: &cancellables)

        
        syncPlaylistFolders()
        checkCrashRestorationOrSetupTabs()
    }

    // 默认浏览器通知的标识符
    public static let defaultBrowserNotificationId = "defaultBrowserNotification"


    
    // 安排默认浏览器通知
    private func scheduleDefaultBrowserNotification() {
        let center = UNUserNotificationCenter.current()

        center.requestAuthorization(options: [.provisional, .alert, .sound, .badge]) { granted, error in
            if let error = error {
                Logger.module.error("请求通知权限失败：\(error.localizedDescription, privacy: .public)")
                return
            }

            if !granted {
                Logger.module.info("未授权安排通知")
                return
            }

            center.getPendingNotificationRequests { requests in
                if requests.contains(where: { $0.identifier == Self.defaultBrowserNotificationId }) {
                    // 已经安排过一个通知，无需再次安排。
                    return
                }

                let content = UNMutableNotificationContent().then {
                    $0.title = Strings.DefaultBrowserCallout.notificationTitle
                    $0.body = Strings.DefaultBrowserCallout.notificationBody
                }

                let timeToShow = AppConstants.buildChannel.isPublic ? 2.hours : 2.minutes
                let timeTrigger = UNTimeIntervalNotificationTrigger(timeInterval: timeToShow, repeats: false)

                let request = UNNotificationRequest(
                    identifier: Self.defaultBrowserNotificationId,
                    content: content,
                    trigger: timeTrigger)

                center.add(request) { error in
                    if let error = error {
                        Logger.module.error("添加通知失败：\(error.localizedDescription, privacy: .public)")
                        return
                    }

                    Preferences.DefaultBrowserIntro.defaultBrowserNotificationScheduled.value = true
                }
            }
        }
    }

    // 取消安排默认浏览器通知
    private func cancelScheduleDefaultBrowserNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.defaultBrowserNotificationId])

        Preferences.DefaultBrowserIntro.defaultBrowserNotificationIsCanceled.value = true
    }

    // 在设置完成后执行
    private func executeAfterSetup(_ block: @escaping () -> Void) {
        if setupTasksCompleted {
            block()
        } else {
            postSetupTasks.append(block)
        }
    }

    // 设置标签
    private func setupTabs() {
        let isPrivate = privateBrowsingManager.isPrivateBrowsing || Preferences.Privacy.privateBrowsingOnly.value
        let noTabsAdded = self.tabManager.tabsForCurrentMode.isEmpty

        var tabToSelect: Tab?

        if noTabsAdded {
            // 如果tabmanager中没有标签，则有两种情况：
            // 1. 我们尚未恢复标签，尝试恢复或者如果没有则创建一个新标签。
            // 2. 我们处于私密浏览模式，并且需要添加一个新的私密标签。
            tabToSelect = isPrivate ? self.tabManager.addTab(isPrivate: true) : self.tabManager.restoreAllTabs
        } else {
            if let selectedTab = tabManager.selectedTab, !selectedTab.isPrivate {
                tabToSelect = selectedTab
            } else {
                tabToSelect = tabManager.tabsForCurrentMode.last
            }
        }
        self.tabManager.selectTab(tabToSelect)

        if !setupTasksCompleted {
            for task in postSetupTasks {
                DispatchQueue.main.async {
                    task()
                }
            }
            setupTasksCompleted = true
        }
    }

    // 设置约束
    private func setupConstraints() {
        toolbarLayoutGuide.snp.makeConstraints {
            self.toolbarTopConstraint = $0.top.equalTo(view.safeArea.top).constraint
            self.toolbarBottomConstraint = $0.bottom.equalTo(view).constraint
            $0.leading.trailing.equalTo(view)
        }

        collapsedURLBarView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        tabsBar.view.snp.makeConstraints { make in
            make.height.equalTo(UX.TabsBar.height)
        }

        webViewContainerBackdrop.snp.makeConstraints { make in
            make.edges.equalTo(webViewContainer)
        }

        topTouchArea.snp.makeConstraints { make in
            make.top.left.right.equalTo(self.view)
            make.height.equalTo(32)
        }

        bottomTouchArea.snp.makeConstraints { make in
            make.bottom.left.right.equalTo(self.view)
            make.height.equalTo(44)
        }
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 重新设置状态栏叠加视图的约束
        statusBarOverlay.snp.remakeConstraints { make in
            make.top.left.right.equalTo(self.view)
            make.bottom.equalTo(view.safeArea.top)
        }
        
        // 设置工具栏可见性视图的过渡距离和最小可折叠内容高度
        toolbarVisibilityViewModel.transitionDistance = header.expandedBarStackView.bounds.height - header.collapsedBarContainerView.bounds.height
        // 由于WKWebView在折叠时高度会改变，因此需要使用一个稳定的值来确定工具栏是否可以折叠。我们不减去底部安全区插图，因为底部包括了该安全区域
        toolbarVisibilityViewModel.minimumCollapsableContentHeight = view.bounds.height - view.safeAreaInsets.top
        
        var additionalInsets: UIEdgeInsets = .zero
        // 根据 isUsingBottomBar 的值设置额外的插入值
        if isUsingBottomBar {
            // 如果使用底部工具栏，则设置额外插入值，使其底部留出 topToolbar 的高度
            additionalInsets = UIEdgeInsets(top: 0, left: 0, bottom: topToolbar.bounds.height, right: 0)
        } else {
            // 如果不使用底部工具栏，则设置额外插入值，使其顶部留出 header 的高度
            additionalInsets = UIEdgeInsets(top: header.bounds.height, left: 0, bottom: 0, right: 0)
        }

        searchController?.additionalSafeAreaInsets = additionalInsets
        favoritesController?.additionalSafeAreaInsets = additionalInsets
        
        // 刷新标签栏数据并还原选定的标签，不使用动画
        tabsBar.reloadDataAndRestoreSelectedTab(isAnimated: false)
    }

    override public var canBecomeFirstResponder: Bool {
        return true
    }

    override public func becomeFirstResponder() -> Bool {
        // 使Web视图成为第一响应者，以便它可以显示选择菜单。
        return tabManager.selectedTab?.webView?.becomeFirstResponder() ?? false
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 更新使用TabManager的工具栏
        updateToolbarUsingTabManager(tabManager)

        // 如果选定的标签具有奖励ID，并且奖励API的选定标签ID为0，则将选定标签ID设置为奖励ID
        if let tabId = tabManager.selectedTab?.rewardsId, rewards.rewardsAPI?.selectedTabId == 0 {
            rewards.rewardsAPI?.selectedTabId = tabId
        }
    }

    #if swift(>=5.9)
    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        
        if #available(iOS 17, *) {
            // 必须推迟到下一个循环，以避免iOS中的一个bug，该bug在没有任何底部安全区域的情况下布局工具栏，导致布局错误。
            DispatchQueue.main.async {
                // 在iOS 17上，将设备旋转到横向然后返回到纵向时，不会触发`traitCollectionDidChange`/`willTransition`等调用，因此工具栏保持在错误的状态。
                self.updateToolbarStateForTraitCollection(self.traitCollection)
            }
        }
    }
    #endif

    // 检查是否有崩溃恢复或设置标签
    private func checkCrashRestorationOrSetupTabs() {
        if crashedLastSession {
            showRestoreTabsAlert()
        } else {
            setupTabs()
        }
    }

    // 显示恢复标签的警告
    fileprivate func showRestoreTabsAlert() {
        guard canRestoreTabs() else {
            self.tabManager.addTabAndSelect(isPrivate: self.privateBrowsingManager.isPrivateBrowsing)
            return
        }
        let alert = UIAlertController.restoreTabsAlert(
            okayCallback: { _ in
                self.setupTabs()
            },
            noCallback: { _ in
                SessionTab.deleteAll()
                self.tabManager.addTabAndSelect(isPrivate: self.privateBrowsingManager.isPrivateBrowsing)
            }
        )
        self.present(alert, animated: true, completion: nil)
    }

    // 检查是否可以恢复标签
    fileprivate func canRestoreTabs() -> Bool {
        // 确保至少有一个真实标签已打开
        return !SessionTab.all().compactMap({ $0.url }).isEmpty
    }

    // 当视图已经出现时调用
    override public func viewDidAppear(_ animated: Bool) {
        
        // 如果是新用户，显示引导页，已存在用户将不会看到引导页
        presentOnboardingIntro()

        // 全屏呼叫提示展示
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.presentFullScreenCallouts()
        }

        // 设置截图助手的视图可见性为true
        screenshotHelper.viewIsVisible = true
        
        // 对当前所有选项卡进行待处理的屏幕截图
        screenshotHelper.takePendingScreenshots(tabManager.allTabs)

        // 调用父类的viewDidAppear方法
        super.viewDidAppear(animated)

        // 如果有待显示的提示信息，延迟显示
        if let toast = self.pendingToast {
            self.pendingToast = nil
            show(toast: toast, afterWaiting: ButtonToastUX.toastDelay)
        }

        // 如果有等待的警告弹窗，显示
        showQueuedAlertIfAvailable()
        
        // 检查是否为隐私浏览模式
        let isPrivateBrowsing = SessionWindow.from(windowId: windowId)?.isPrivate == true
        
        // 获取当前窗口场景的用户活动
        var userActivity = view.window?.windowScene?.userActivity
        
        // 如果有用户活动，则设置窗口信息
        if let userActivity = userActivity {
            BrowserState.setWindowInfo(for: userActivity, windowId: windowId.uuidString, isPrivate: isPrivateBrowsing)
        } else {
            // 否则，从浏览器状态获取窗口信息
            userActivity = BrowserState.userActivity(for: windowId.uuidString, isPrivate: isPrivateBrowsing)
        }
        
        // 设置当前窗口场景的用户活动
        if let scene = view.window?.windowScene {
            scene.userActivity = userActivity
            BrowserState.setWindowInfo(for: scene.session, windowId: windowId.uuidString, isPrivate: isPrivateBrowsing)
        }
        
        // 刷新所有已打开的场景会话
        for session in UIApplication.shared.openSessions {
            UIApplication.shared.requestSceneSessionRefresh(session)
        }
    }


    /// 是否在此会话中显示播放列表引导提示
    var shouldShowPlaylistOnboardingThisSession = true

    /// 如果有待显示的警告弹窗，显示
    public func showQueuedAlertIfAvailable() {
        if let queuedAlertInfo = tabManager.selectedTab?.dequeueJavascriptAlertPrompt() {
            let alertController = queuedAlertInfo.alertController()
            alertController.delegate = self
            present(alertController, animated: true, completion: nil)
        }
    }

    // 当视图即将消失时调用
    override public func viewWillDisappear(_ animated: Bool) {
        // 设置截图助手的视图可见性为false
        screenshotHelper.viewIsVisible = false
        super.viewWillDisappear(animated)

        // 重置奖励API中的选定标签ID
        rewards.rewardsAPI?.selectedTabId = 0
        
        // 清空窗口场景的用户活动
        view.window?.windowScene?.userActivity = nil
    }

    /// 定义收藏夹和NTP覆盖层的布局指南
    let pageOverlayLayoutGuide = UILayoutGuide()

    /// 单个控制器每个bvc/window。每个标签或webview使用一个控制器会导致崩溃。
    var screenTimeViewController: STWebpageController?

    // 更新视图约束
    override public func updateViewConstraints() {
        readerModeBar?.snp.remakeConstraints { make in
            // 根据是否使用底部工具栏设置顶部约束
            if self.isUsingBottomBar {
                make.top.equalTo(self.view.safeArea.top)
            } else {
                make.top.equalTo(self.header.snp.bottom)
            }
            make.height.equalTo(UIConstants.toolbarHeight)
            make.leading.trailing.equalTo(self.view)
        }
        
        // 如果screenTimeViewController存在且有父视图，则重新设置其约束
        if let screenTimeViewController = screenTimeViewController, screenTimeViewController.parent != nil {
            screenTimeViewController.view.snp.remakeConstraints {
                $0.edges.equalTo(webViewContainer)
            }
        }
        
        webViewContainer.snp.remakeConstraints { make in
            // 设置左右边距
            make.left.right.equalTo(self.view)
            
            // 根据是否使用底部工具栏设置顶部约束
            if self.isUsingBottomBar {
                // 设置webViewContainerTopOffset，它是一个Auto Layout约束，
                //将webViewContainer的顶部与readerModeBar的底部（如果存在）或toolbarLayoutGuide的顶部对齐
                webViewContainerTopOffset = make.top.equalTo(self.readerModeBar?.snp.bottom ?? self.toolbarLayoutGuide.snp.top).constraint

            } else {
                // 设置webViewContainerTopOffset，它是一个Auto Layout约束，
                // 将webViewContainer的顶部与readerModeBar的底部（如果存在）或header的底部对齐
                webViewContainerTopOffset = make.top.equalTo(self.readerModeBar?.snp.bottom ?? self.header.snp.bottom).constraint

            }

            let findInPageHeight = (findInPageBar == nil) ? 0 : UIConstants.toolbarHeight
            // 根据是否使用底部工具栏设置底部约束
            if self.isUsingBottomBar {
                // 创建一个Auto Layout约束，将当前视图的底部与header的顶部对齐，并向上偏移findInPageHeight
                make.bottom.equalTo(self.header.snp.top).offset(-findInPageHeight)

            } else {
                make.bottom.equalTo(self.footer.snp.top).offset(-findInPageHeight)
            }
        }

        // 设置header的约束
        header.snp.remakeConstraints { make in
            if self.isUsingBottomBar {
                // 当底部工具栏启用时，需要检查Find In Page Bar是否启用，以便在启用底部工具栏时正确对齐它
                // 是否需要评估键盘约束
                var shouldEvaluateKeyboardConstraints = false
                var activeKeyboardHeight: CGFloat = 0
                var searchEngineSettingsDismissed = false

                if let keyboardHeight = keyboardState?.intersectionHeightForView(self.view) {
                    activeKeyboardHeight = keyboardHeight
                }
                
                if let presentedNavigationController = presentedViewController as? ModalSettingsNavigationController,
                   let presentedRootController = presentedNavigationController.viewControllers.first,
                   presentedRootController is SearchSettingsTableViewController {
                    searchEngineSettingsDismissed = true
                }
                
                shouldEvaluateKeyboardConstraints = (activeKeyboardHeight > 0)
                  && (presentedViewController == nil || searchEngineSettingsDismissed || findInPageBar != nil)
                        
                if shouldEvaluateKeyboardConstraints {
                    var offset = -activeKeyboardHeight
                    if !topToolbar.inOverlayMode {
                        // 在键盘弹起时显示折叠的URL栏
                        offset += toolbarVisibilityViewModel.transitionDistance
                    }
                    make.bottom.equalTo(self.view).offset(offset)
                } else {
                    if topToolbar.inOverlayMode {
                        make.bottom.equalTo(self.view.safeArea.bottom)
                    } else {
                        make.bottom.equalTo(footer.snp.top)
                    }
                }
            } else {
                make.top.equalTo(toolbarLayoutGuide)
            }
            make.left.right.equalTo(self.view)
        }
        
        // 设置headerHeightLayoutGuide的约束
        // 使用SnapKit库重新设置headerHeightLayoutGuide的约束
        headerHeightLayoutGuide.snp.remakeConstraints {
            // 如果正在使用底部工具栏，将headerHeightLayoutGuide的底部与footer的顶部对齐
            // 否则，将headerHeightLayoutGuide的顶部与toolbarLayoutGuide的底部对齐
            if self.isUsingBottomBar {
                $0.bottom.equalTo(footer.snp.top)
            } else {
                $0.top.equalTo(toolbarLayoutGuide)
            }
            
            // 设置headerHeightLayoutGuide的高度等于header的高度
            $0.height.equalTo(header)
            
            // 设置headerHeightLayoutGuide的leading和trailing与当前视图相等
            $0.leading.trailing.equalTo(self.view)
        }


        // 设置footer的约束
        footer.snp.remakeConstraints { make in
            make.bottom.equalTo(toolbarLayoutGuide)
            make.leading.trailing.equalTo(self.view)
            if toolbar == nil {
                make.height.equalTo(0)
            }
        }

        // 设置bottomBarKeyboardBackground的约束
        bottomBarKeyboardBackground.snp.remakeConstraints {
            if self.isUsingBottomBar {
                $0.top.equalTo(header)
                $0.bottom.equalTo(footer)
            } else {
                $0.top.bottom.equalTo(footer)
            }
            $0.leading.trailing.equalToSuperview()
        }


    
        // 重新设置约束，即使我们已经显示主页控制器。
        // 如果我们在about:home页面上点击URL栏，主页控制器可能会更改大小。
        pageOverlayLayoutGuide.snp.remakeConstraints { make in
            // 根据是否使用底部工具栏设置顶部约束
            if self.isUsingBottomBar {
                webViewContainerTopOffset = make.top.equalTo(readerModeBar?.snp.bottom ?? 0).constraint
            } else {
                webViewContainerTopOffset = make.top.equalTo(readerModeBar?.snp.bottom ?? self.header.snp.bottom).constraint
            }

            make.left.right.equalTo(self.view)
            // 根据是否使用底部工具栏设置底部约束
//            if self.isUsingBottomBar {
//                make.bottom.equalTo(self.headerHeightLayoutGuide.snp.top)
//            } else {
//                make.bottom.equalTo(self.footer.snp.top)
//            }
            make.bottom.equalTo(self.view)
        }

        // 重新设置弹窗堆叠视图的约束
        alertStackView.snp.remakeConstraints { make in
            make.centerX.equalTo(self.view)
            make.width.equalTo(self.view.safeArea.width)
            
            // 如果键盘弹起，调整底部约束
            if let keyboardHeight = keyboardState?.intersectionHeightForView(self.view), keyboardHeight > 0 {
                if self.isUsingBottomBar {
                    var offset = -keyboardHeight
                    if !topToolbar.inOverlayMode {
                        // 在键盘弹起时显示折叠的URL栏
                        offset += toolbarVisibilityViewModel.transitionDistance
                    }
                    make.bottom.equalTo(header.snp.top)
                } else {
                    make.bottom.equalTo(self.view).offset(-keyboardHeight)
                }
            } else if isUsingBottomBar {
                make.bottom.equalTo(header.snp.top)
            } else if let toolbar = self.toolbar {
                make.bottom.lessThanOrEqualTo(toolbar.snp.top)
                make.bottom.lessThanOrEqualTo(self.view.safeArea.bottom)
            } else {
                make.bottom.equalTo(self.view.safeArea.bottom)
            }
        }

        // 设置底部工具栏的约束
        toolbar?.snp.remakeConstraints { make in
            make.edges.equalTo(self.footer)
        }

        // 调用父类的updateViewConstraints方法
        super.updateViewConstraints()

  }

    // 显示新的标签页控制器
    fileprivate func showNewTabPageController() {
        // 确保选择的标签不为空
        guard let selectedTab = tabManager.selectedTab else { return }
        
        // 如果选定的标签页尚未创建新标签页控制器
        if selectedTab.newTabPageViewController == nil {
            
            
            // 创建新标签页控制器
            let ntpController = NewTabPageViewController(
                tab: selectedTab,
                profile: profile,
                dataSource: backgroundDataSource,
                feedDataSource: feedDataSource,
                rewards: rewards,
                privateBrowsingManager: privateBrowsingManager,
                p3aUtils: braveCore.p3aUtils,
                action: { [weak self] actionName in
                    self!.scanQRCode()
                    // print(actionName)
                }
            )
            
            // 为自定义建议捐赠新标签页活动
            let newTabPageActivity = ActivityShortcutManager.shared.createShortcutActivity(type: selectedTab.isPrivate ? .newPrivateTab : .newTab)
            
            // 设置新标签页控制器的代理和用户活动
            ntpController.delegate = self
            ntpController.userActivity = newTabPageActivity
            
            // 将新标签页活动设置为当前活动
            newTabPageActivity.becomeCurrent()
            
            // 将新标签页控制器分配给选定的标签
            selectedTab.newTabPageViewController = ntpController
        }
        
        // 确保新标签页控制器已成功分配给选定的标签
        guard let ntpController = selectedTab.newTabPageViewController else {
            assertionFailure("homePanelController is still nil after assignment.")
            return
        }
        
        // 如果有活动的新标签页控制器且不同于当前的新标签页控制器
        if let activeController = activeNewTabPageViewController, ntpController != activeController {
            // 先移除活动的控制器
            activeController.willMove(toParent: nil)
            activeController.removeFromParent()
            activeController.view.removeFromSuperview()
        }
        
        // 如果新标签页控制器没有父控制器
        if ntpController.parent == nil {
            // 将新标签页控制器添加为子控制器
            activeNewTabPageViewController = ntpController
            addChild(ntpController)
            
            // 根据使用底部栏还是状态栏覆盖添加新标签页视图
            let subview = isUsingBottomBar ? header : statusBarOverlay
            view.insertSubview(ntpController.view, belowSubview: footer)
            ntpController.didMove(toParent: self)
            
            // 设置新标签页视图的约束
            ntpController.view.snp.makeConstraints {
                $0.edges.equalTo(pageOverlayLayoutGuide)
            }
            ntpController.view.layoutIfNeeded()
            
            // 运行动画，确保新标签页视图透明度为1
            UIView.animate(
                withDuration: 0.2,
                animations: {
                    ntpController.view.alpha = 1
                },
                completion: { finished in
                    // 动画完成后，将webViewContainer的accessibilityElementsHidden设置为true，并发出屏幕已更改的通知
                    if finished {
                        self.webViewContainer.accessibilityElementsHidden = true
                        UIAccessibility.post(notification: .screenChanged, argument: nil)
                    }
                }
            )
        }
    }


  private(set) weak var activeNewTabPageViewController: NewTabPageViewController?

  fileprivate func hideActiveNewTabPageController(_ isReaderModeURL: Bool = false) {
    guard let controller = activeNewTabPageViewController else { return }

    UIView.animate(
      withDuration: 0.2,
      animations: {
        controller.view.alpha = 0.0
      },
      completion: { finished in
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        self.webViewContainer.accessibilityElementsHidden = false
        UIAccessibility.post(notification: .screenChanged, argument: nil)

        // Refresh the reading view toolbar since the article record may have changed
        if let tab = self.tabManager.selectedTab,
          let readerMode = tab.getContentScript(name: ReaderModeScriptHandler.scriptName) as? ReaderModeScriptHandler,
          readerMode.state == .active,
          isReaderModeURL {
          self.showReaderModeBar(animated: false)
          self.updatePlaylistURLBar(tab: tab, state: tab.playlistItemState, item: tab.playlistItem)
        }
      })
  }

    /// 根据 VPN 的状态显示相应的 VPN 屏幕。
    public func presentCorrespondingVPNViewController() {
      // 如果需要保持显示会话过期状态，显示会话过期的警告
//      if BraveSkusManager.keepShowingSessionExpiredState {
//        let alert = BraveSkusManager.sessionExpiredStateAlert(loginCallback: { [unowned self] _ in
//          // 在新标签页中打开 Brave 账户页面
//          self.openURLInNewTab(.brave.account, isPrivate: self.privateBrowsingManager.isPrivateBrowsing,
//                               isPrivileged: false)
//        })
//        
//        // 显示警告
//        present(alert, animated: true)
//        return
//      }
//      
//      // 获取启用 VPN 时的目标视图控制器
//      guard let vc = BraveVPN.vpnState.enableVPNDestinationVC else { return }
//      
//      // 创建一个带有取消按钮的导航控制器
//      let navigationController = SettingsNavigationController(rootViewController: vc)
//      navigationController.navigationBar.topItem?.leftBarButtonItem =
//        .init(barButtonSystemItem: .cancel, target: navigationController, action: #selector(navigationController.done))
//      
//      // 获取设备的界面风格
//      let idiom = UIDevice.current.userInterfaceIdiom
//      
//      // 在手机上强制将设备方向更改为纵向
//      DeviceOrientation.shared.changeOrientationToPortraitOnPhone()
//     
//      // 根据设备的界面风格设置模态呈现样式
//      navigationController.modalPresentationStyle = idiom == .phone ? .pageSheet : .formSheet
//      
//      // 显示导航控制器
//      present(navigationController, animated: true)
    }

  func updateInContentHomePanel(_ url: URL?) {
    let isAboutHomeURL = { () -> Bool in
      if let url = url {
        return InternalURL(url)?.isAboutHomeURL == true
      }
      return false
    }()

    if !topToolbar.inOverlayMode {
      guard let url = url else {
        hideActiveNewTabPageController()
        return
      }

      if isAboutHomeURL {
        showNewTabPageController()
      } else if !url.absoluteString.hasPrefix("\(InternalURL.baseUrl)/\(SessionRestoreHandler.path)") {
        hideActiveNewTabPageController(url.isReaderModeURL)
      }
    } else if isAboutHomeURL {
      showNewTabPageController()
    }
  }

    // 更新标签栏（Tabs Bar）的可见性
    func updateTabsBarVisibility() {
        // 使用defer确保在函数执行结束时设置底部工具栏线的可见性
//        defer {
//            toolbar?.line.isHidden = isUsingBottomBar
//        }
        
        // 从视图中移除标签栏
        tabsBar.view.removeFromSuperview()
        
        // 根据底部栏使用情况将标签栏添加到扩展栏堆栈视图中
        if isUsingBottomBar {
            header.expandedBarStackView.insertArrangedSubview(tabsBar.view, at: 0)
        } else {
            header.expandedBarStackView.addArrangedSubview(tabsBar.view)
        }

        // 如果未选择任何标签，则隐藏标签栏并返回
        if tabManager.selectedTab == nil {
            tabsBar.view.isHidden = true
            return
        }

        // 内部函数，用于确定是否应该显示标签栏
        func shouldShowTabBar() -> Bool {
            // 如果顶部工具栏处于叠加模式或键盘状态不为nil，并且使用底部栏，则不显示标签栏
            if (topToolbar.inOverlayMode || keyboardState != nil) && isUsingBottomBar {
                return false
            }
            
            // 获取当前模式下标签的数量
            let tabCount = tabManager.tabsForCurrentMode.count
            
            // 获取标签栏可见性的偏好设置值
            guard let tabBarVisibility = TabBarVisibility(rawValue: Preferences.General.tabBarVisibility.value) else {
                // 这不应该发生，如果发生则断言失败
                assertionFailure("Invalid tab bar visibility preference: \(Preferences.General.tabBarVisibility.value).")
                return tabCount > 1
            }
            
            // 根据偏好设置值确定是否显示标签栏
            switch tabBarVisibility {
            case .always:
                return tabCount > 1 || UIDevice.current.userInterfaceIdiom == .pad
            case .landscapeOnly:
                return (tabCount > 1 && UIDevice.current.orientation.isLandscape) || UIDevice.current.userInterfaceIdiom == .pad
            case .never:
                return false
            }
        }

        // 获取标签栏当前的显示状态和是否应该显示的状态
        let isShowing = tabsBar.view.isHidden == false
        let shouldShow = shouldShowTabBar()

        // 如果当前显示状态与应该显示状态不同，并且没有正在呈现的视图控制器，则执行动画设置标签栏的可见性
        if isShowing != shouldShow && presentedViewController == nil {
            UIView.animate(withDuration: 0.1) {
                self.tabsBar.view.isHidden = !shouldShow
            }
        } else {
            // 否则直接设置标签栏的可见性
            tabsBar.view.isHidden = !shouldShow
        }
    }


  private func updateApplicationShortcuts() {
    let newTabItem = UIMutableApplicationShortcutItem(
      type: "\(Bundle.main.bundleIdentifier ?? "").NewTab",
      localizedTitle: Strings.quickActionNewTab,
      localizedSubtitle: nil,
      icon: UIApplicationShortcutIcon(templateImageName: "quick_action_new_tab"),
      userInfo: [:])
    
    let privateTabItem = UIMutableApplicationShortcutItem(
      type: "\(Bundle.main.bundleIdentifier ?? "").NewPrivateTab",
      localizedTitle: Strings.quickActionNewPrivateTab,
      localizedSubtitle: nil,
      icon: UIApplicationShortcutIcon(templateImageName: "quick_action_new_private_tab"),
      userInfo: [:])
    
    let scanQRCodeItem = UIMutableApplicationShortcutItem(
      type: "\(Bundle.main.bundleIdentifier ?? "").ScanQRCode",
      localizedTitle: Strings.scanQRCodeViewTitle,
      localizedSubtitle: nil,
      icon: UIApplicationShortcutIcon(templateImageName: "recent-search-qrcode"),
      userInfo: [:])
    
    UIApplication.shared.shortcutItems = Preferences.Privacy.privateBrowsingOnly.value ? [privateTabItem, scanQRCodeItem] : [newTabItem, privateTabItem, scanQRCodeItem]
  }

  /// The method that executes the url and make changes in UI to reset the toolbars
  /// for urls coming from various sources
  /// If url is bookmarklet check if it is coming from user defined source to decide whether to execute
  /// using isUserDefinedURLNavigation
  /// - Parameters:
  ///   - url: The url submitted
  ///   - isUserDefinedURLNavigation: Boolean for  determining if url navigation is done from user defined spot
  ///     user defined spot like Favourites or Bookmarks
  func finishEditingAndSubmit(_ url: URL, isUserDefinedURLNavigation: Bool = false) {
    if url.isBookmarklet {
      topToolbar.leaveOverlayMode()

      guard let tab = tabManager.selectedTab else {
        return
      }

      // Another Fix for: https://github.com/brave/brave-ios/pull/2296
      // Disable any sort of privileged execution contexts
      // IE: The user must explicitly tap a bookmark they have saved.
      // Block all other contexts such as redirects, downloads, embed, linked, etc..
      if isUserDefinedURLNavigation, let webView = tab.webView, let code = url.bookmarkletCodeComponent {
        webView.evaluateSafeJavaScript(
          functionName: code,
          contentWorld: .bookmarkletSandbox,
          asFunction: false
        ) { _, error in
          if let error = error {
            Logger.module.error("\(error.localizedDescription, privacy: .public)")
          }
        }
      }
    } else {
      updateToolbarCurrentURL(url)
      topToolbar.leaveOverlayMode()

      guard let tab = tabManager.selectedTab else {
        return
      }

      tab.loadRequest(URLRequest(url: url))

      updateWebViewPageZoom(tab: tab)
    }
  }
  
  func showIPFSInterstitialPage(originalURL: URL) {
//    topToolbar.leaveOverlayMode()
//
//    guard let tab = tabManager.selectedTab, let encodedURL = originalURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics), let internalUrl = URL(string: "\(InternalURL.baseUrl)/\(IPFSSchemeHandler.path)?url=\(encodedURL)") else {
//      return
//    }
//    let scriptHandler = tab.getContentScript(name: Web3IPFSScriptHandler.scriptName) as? Web3IPFSScriptHandler
//    scriptHandler?.originalURL = originalURL
//
//    tab.webView?.load(PrivilegedRequest(url: internalUrl) as URLRequest)
  }

//  func showWeb3ServiceInterstitialPage(service: Web3Service, originalURL: URL) {
//    topToolbar.leaveOverlayMode()
//
//    guard let tab = tabManager.selectedTab,
//          let encodedURL = originalURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
//          let internalUrl = URL(string: "\(InternalURL.baseUrl)/\(Web3DomainHandler.path)?\(Web3NameServiceScriptHandler.ParamKey.serviceId.rawValue)=\(service.rawValue)&url=\(encodedURL)") else {
//      return
//    }
//    let scriptHandler = tab.getContentScript(name: Web3NameServiceScriptHandler.scriptName) as? Web3NameServiceScriptHandler
//    scriptHandler?.originalURL = originalURL
//    
//    tab.webView?.load(PrivilegedRequest(url: internalUrl) as URLRequest)
//  }
  
  override public func accessibilityPerformEscape() -> Bool {
    if topToolbar.inOverlayMode {
      topToolbar.didClickCancel()
      return true
    } else if let selectedTab = tabManager.selectedTab, selectedTab.canGoBack {
      selectedTab.goBack()
      resetExternalAlertProperties(selectedTab)
      return true
    }
    return false
  }

  // This variable is used to keep track of current page. It is used to detect internal site navigation
  // to report internal page load to Rewards lib
  var rewardsXHRLoadURL: URL?

  override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {

    guard let webView = object as? WKWebView else {
      Logger.module.error("An object of type: \(String(describing: object), privacy: .public) is being observed instead of a WKWebView")
      return  // False alarm.. the source MUST be a web view.
    }

    // WebView is a zombie and somehow still has an observer attached to it
    guard let tab = tabManager[webView] else {
      Logger.module.error("WebView has been removed from TabManager but still has attached observers")
      return
    }

    // Must handle ALL keypaths
    guard let kp = keyPath else {
      assertionFailure("Unhandled KVO key: \(keyPath ?? "nil")")
      return
    }

    let path = KVOConstants(keyPath: kp)
    switch path {
    case .estimatedProgress:
      guard tab === tabManager.selectedTab,
        // `WKWebView.estimatedProgress` is a `Double` type so it must be casted as such
        let progress = change?[.newKey] as? Double
      else { break }
      if let url = webView.url, !InternalURL.isValid(url: url) {
        topToolbar.updateProgressBar(Float(progress))
          navigationToolbar.updateProgressBar(Float(progress))
      } else {
        topToolbar.hideProgressBar()
      }
    case .loading:
      if tab === tabManager.selectedTab {
        topToolbar.locationView.loading = tab.loading
        // There is a bug in WebKit where if you cancel a load on a request the progress can stick to 0.1
        if !tab.loading, webView.estimatedProgress != 1 {
          topToolbar.updateProgressBar(1)
        }
      }
    case .URL:
      guard let tab = tabManager[webView] else { break }

      // Special case for "about:blank" popups, if the webView.url is nil, keep the tab url as "about:blank"
      if tab.url?.absoluteString == "about:blank" && webView.url == nil {
        break
      }

      // To prevent spoofing, only change the URL immediately if the new URL is on
      // the same origin as the current URL. Otherwise, do nothing and wait for
      // didCommitNavigation to confirm the page load.
      if tab.url?.origin == webView.url?.origin {
        tab.url = webView.url

        if tab === tabManager.selectedTab && !tab.restoring {
          updateUIForReaderHomeStateForTab(tab)
        }
        // Catch history pushState navigation, but ONLY for same origin navigation,
        // for reasons above about URL spoofing risk.
        navigateInTab(tab: tab)
      }

      // Rewards reporting
      if let url = change?[.newKey] as? URL, !url.isLocal {
        // Notify Rewards of new page load.
        if let rewardsURL = rewardsXHRLoadURL,
          url.host == rewardsURL.host {
          tabManager.selectedTab?.reportPageNavigation(to: rewards)
          // Not passing redirection chain here, in page navigation should not use them.
          tabManager.selectedTab?.reportPageLoad(to: rewards, redirectionURLs: [])
        }
      }
      
      // Update the estimated progress when the URL changes. Estimated progress may update to 0.1 when the url
      // is still an internal URL even though a request may be pending for a web page.
      if tab === tabManager.selectedTab, let url = webView.url,
         !InternalURL.isValid(url: url), webView.estimatedProgress > 0 {
        topToolbar.updateProgressBar(Float(webView.estimatedProgress))
      }
    case .title:
      // Ensure that the tab title *actually* changed to prevent repeated calls
      // to navigateInTab(tab:).
      guard let title = (webView.title?.isEmpty == true ? webView.url?.absoluteString : webView.title) else { break }
      if !title.isEmpty && title != tab.lastTitle {
        navigateInTab(tab: tab)
        tabsBar.updateSelectedTabTitle()
      }
        if !title.isEmpty {
            if title.contains("local/about/home") {
                toolbar?.searchButton.setTitle(Strings.Home.homePage, for: .normal)
            } else {
                toolbar?.searchButton.setTitle(title, for: .normal)
            }
           
        }
    case .canGoBack:
      guard tab === tabManager.selectedTab, let canGoBack = change?[.newKey] as? Bool else {
        break
      }

      navigationToolbar.updateBackStatus(canGoBack)
    case .canGoForward:
      guard tab === tabManager.selectedTab, let canGoForward = change?[.newKey] as? Bool else {
        break
      }

      navigationToolbar.updateForwardStatus(canGoForward)
    case .hasOnlySecureContent:
      guard let tab = tabManager[webView] else {
        break
      }

      if tab.secureContentState == .secure, !webView.hasOnlySecureContent,
         tab.url?.origin == tab.webView?.url?.origin {
        if let url = tab.webView?.url, url.isReaderModeURL {
          break
        }
        tab.secureContentState = .mixedContent
      }

      if tabManager.selectedTab === tab {
        updateToolbarSecureContentState(tab.secureContentState)
      }
    case .serverTrust:
      guard let tab = tabManager[webView] else {
        break
      }

      tab.secureContentState = .unknown

      guard let serverTrust = tab.webView?.serverTrust else {
        if let url = tab.webView?.url ?? tab.url {
          if InternalURL.isValid(url: url),
            let internalUrl = InternalURL(url),
            (internalUrl.isAboutURL || internalUrl.isAboutHomeURL) {

            tab.secureContentState = .localhost
            if tabManager.selectedTab === tab {
              updateToolbarSecureContentState(.localhost)
            }
            break
          }

          if InternalURL.isValid(url: url),
            let internalUrl = InternalURL(url),
            internalUrl.isErrorPage {

            if ErrorPageHelper.certificateError(for: url) != 0 {
              tab.secureContentState = .invalidCert
            } else {
              tab.secureContentState = .missingSSL
            }
            if tabManager.selectedTab === tab {
              updateToolbarSecureContentState(tab.secureContentState)
            }
            break
          }

          if url.isReaderModeURL || InternalURL.isValid(url: url) {
            tab.secureContentState = .localhost
            if tabManager.selectedTab === tab {
              updateToolbarSecureContentState(.localhost)
            }
            break
          }

          // All our checks failed, we show the page as insecure
          tab.secureContentState = .missingSSL
        } else {
          // When there is no URL, it's likely a new tab.
          tab.secureContentState = .localhost
        }

        if tabManager.selectedTab === tab {
          updateToolbarSecureContentState(tab.secureContentState)
        }
        break
      }
      
      guard let scheme = tab.webView?.url?.scheme,
            let host = tab.webView?.url?.host else {
        tab.secureContentState = .unknown
        self.updateURLBar()
        return
      }
      
      let port: Int
      if let urlPort = tab.webView?.url?.port {
        port = urlPort
      } else if scheme == "https" {
        port = 443
      } else {
        port = 80
      }
      
      Task { @MainActor in
        do {
          let result = await BraveCertificateUtils.verifyTrust(serverTrust, host: host, port: port)
          
          // Cert is valid!
          if result == 0 {
            tab.secureContentState = .secure
          } else if result == Int32.min {
            // Cert is valid but should be validated by the system
            // Let the system handle it and we'll show an error if the system cannot validate it
            try await BraveCertificateUtils.evaluateTrust(serverTrust, for: host)
            tab.secureContentState = .secure
          } else {
            tab.secureContentState = .invalidCert
          }
        } catch {
          tab.secureContentState = .invalidCert
        }
        
        self.updateURLBar()
      }
    case ._sampledPageTopColor:
      //updateStatusBarOverlayColor()
        break
    default:
      assertionFailure("Unhandled KVO key: \(kp)")
    }
  }

  func updateForwardStatusIfNeeded(webView: WKWebView) {
    if let forwardListItem = webView.backForwardList.forwardList.first, forwardListItem.url.isReaderModeURL {
      navigationToolbar.updateForwardStatus(false)
    } else {
      navigationToolbar.updateForwardStatus(webView.canGoForward)
    }
  }
    
  func updateUIForReaderHomeStateForTab(_ tab: Tab) {
    updateURLBar()
    toolbarVisibilityViewModel.toolbarState = .expanded

    if let url = tab.url {
      if url.isReaderModeURL {
        showReaderModeBar(animated: false)
        NotificationCenter.default.addObserver(self, selector: #selector(dynamicFontChanged), name: .dynamicFontChanged, object: nil)
      } else {
        hideReaderModeBar(animated: false)
        NotificationCenter.default.removeObserver(self, name: .dynamicFontChanged, object: nil)
      }

      updateInContentHomePanel(url as URL)
      updateScreenTimeUrl(url)
      updatePlaylistURLBar(tab: tab, state: tab.playlistItemState, item: tab.playlistItem)
    }
  }

  /// Updates the URL bar security, text and button states.
  func updateURLBar() {
    guard let tab = tabManager.selectedTab else { return }

    updateRewardsButtonState()

    DispatchQueue.main.async {
      if let item = tab.playlistItem {
        if PlaylistItem.itemExists(uuid: item.tagId) || PlaylistItem.itemExists(pageSrc: item.pageSrc) {
          self.updatePlaylistURLBar(tab: tab, state: .existingItem, item: item)
        } else {
          self.updatePlaylistURLBar(tab: tab, state: .newItem, item: item)
        }
      } else {
        self.updatePlaylistURLBar(tab: tab, state: .none, item: nil)
      }
    }

    updateToolbarCurrentURL(tab.url?.displayURL)
      
      //更新底部文本
      let myTitle = tab.title

      // 检查标题是否为非空字符串
      if !myTitle.isEmpty {
          if myTitle.contains("local/about/home") {
              toolbar?.searchButton.setTitle(Strings.Home.homePage, for: .normal)
          } else {
              toolbar?.searchButton.setTitle(myTitle, for: .normal)
          }
      }
  
    
      
    if tabManager.selectedTab === tab {
      updateToolbarSecureContentState(tab.secureContentState)
    }

    let isPage = tab.url?.isWebPage() ?? false
    navigationToolbar.updatePageStatus(isPage)
    updateWebViewPageZoom(tab: tab)
  }
  
  public func moveTab(tabId: UUID, to browser: BrowserViewController) {
    guard let tab = tabManager.allTabs.filter({ $0.id == tabId }).first,
          let url = tab.url else {
      return
    }
    
    let isPrivate = tab.isPrivate
    tabManager.removeTab(tab)
    browser.tabManager.addTabsForURLs([url], zombie: false, isPrivate: isPrivate)
  }

  public func switchToTabForURLOrOpen(_ url: URL, isPrivate: Bool = false, isPrivileged: Bool, isExternal: Bool = false) {
    if !isExternal {
      popToBVC()
    }

    if let tab = tabManager.getTabForURL(url) {
      tabManager.selectTab(tab)
    } else {
      openURLInNewTab(url, isPrivate: isPrivate, isPrivileged: isPrivileged)
    }
  }
  
  func switchToTabOrOpen(id: UUID?, url: URL) {
    popToBVC()
    
    if let tabID = id, let tab = tabManager.getTabForID(tabID) {
      tabManager.selectTab(tab)
    } else if let tab = tabManager.getTabForURL(url) {
      tabManager.selectTab(tab)
    } else {
      openURLInNewTab(url, isPrivate: privateBrowsingManager.isPrivateBrowsing, isPrivileged: false)
    }
  }

  func openURLInNewTab(_ url: URL?, isPrivate: Bool = false, isPrivileged: Bool) {
    topToolbar.leaveOverlayMode(didCancel: true)

    if let selectedTab = tabManager.selectedTab {
      screenshotHelper.takeScreenshot(selectedTab)
    }
    let request: URLRequest?
    if let url = url {
      // If only empty tab present, the url will open in existing tab
      if tabManager.isBrowserEmptyForCurrentMode {
        finishEditingAndSubmit(url)
        return
      }
      request = isPrivileged ? PrivilegedRequest(url: url) as URLRequest : URLRequest(url: url)
    } else {
      request = nil
    }

    tabManager.addTabAndSelect(request, isPrivate: isPrivate)
    
    // Has to go after since switching tabs will cause the URL bar to update to the selected Tab's url (which
    // is going to be nil still until the web view first commits
    updateToolbarCurrentURL(url)
  }

  public func openBlankNewTab(attemptLocationFieldFocus: Bool, isPrivate: Bool, searchFor searchText: String? = nil, isExternal: Bool = false) {
    if !isExternal {
      popToBVC()
    }

    openURLInNewTab(nil, isPrivate: isPrivate, isPrivileged: true)
    let freshTab = tabManager.selectedTab

    // Focus field only if requested and background images are not supported
    if attemptLocationFieldFocus {
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
        // Without a delay, the text field fails to become first responder
        // Check that the newly created tab is still selected.
        // This let's the user spam the Cmd+T button without lots of responder changes.
        guard freshTab == self.tabManager.selectedTab else { return }
        if let text = searchText {
          self.topToolbar.submitLocation(text)
        } else {
          self.focusURLBar()
        }
      }
    }
  }
  
  func openInNewWindow(url: URL?, isPrivate: Bool) {
    let activity = BrowserState.userActivity(for: UUID().uuidString, isPrivate: isPrivate, openURL: url)

    let options = UIScene.ActivationRequestOptions().then {
      $0.requestingScene = view.window?.windowScene
    }
    
    UIApplication.shared.requestSceneSessionActivation(nil,
                                                       userActivity: activity,
                                                       options: options,
                                                       errorHandler: { error in
      Logger.module.error("Error creating new window: \(error)")
    })
  }

  func clearHistoryAndOpenNewTab() {
    // When PB Only mode is enabled
    // All private tabs closed and a new private tab is created
    if Preferences.Privacy.privateBrowsingOnly.value {
      tabManager.removeAll()
      openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: true, isExternal: true)
      popToBVC()
    } else {
      braveCore.historyAPI.deleteAll { [weak self] in
        guard let self = self else { return }

        self.tabManager.clearTabHistory() {
          self.openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: false, isExternal: true)
          self.popToBVC()
        }
      }
    }
  }

  func openInsideSettingsNavigation(with viewController: UIViewController) {
    let settingsNavigationController = SettingsNavigationController(rootViewController: viewController)
    settingsNavigationController.isModalInPresentation = false
    settingsNavigationController.modalPresentationStyle =
      UIDevice.current.userInterfaceIdiom == .phone ? .pageSheet : .formSheet
    settingsNavigationController.navigationBar.topItem?.leftBarButtonItem =
      UIBarButtonItem(barButtonSystemItem: .done, target: settingsNavigationController, action: #selector(settingsNavigationController.done))

    // All menu views should be opened in portrait on iPhones.
    DeviceOrientation.shared.changeOrientationToPortraitOnPhone()

    present(settingsNavigationController, animated: true)
  }

  func popToBVC(completion: (() -> Void)? = nil) {
    guard let currentViewController = navigationController?.topViewController else {
      return
    }
    currentViewController.dismiss(animated: true, completion: completion)

    if currentViewController != self {
      _ = self.navigationController?.popViewController(animated: true)
    } else if topToolbar.inOverlayMode {
      topToolbar.didClickCancel()
    }
  }
  
  func displayPageZoom(visible: Bool) {
    if !visible || pageZoomBar != nil {
      pageZoomBar?.view.removeFromSuperview()
      updateViewConstraints()
      pageZoomBar = nil
      
      return
    }
    
    guard let selectTab = tabManager.selectedTab else { return }
    let zoomHandler = PageZoomHandler(tab: selectTab, isPrivateBrowsing: privateBrowsingManager.isPrivateBrowsing)
    let pageZoomBar = UIHostingController(rootView: PageZoomView(zoomHandler: zoomHandler))

    pageZoomBar.rootView.dismiss = { [weak self] in
      guard let self = self else { return }
      pageZoomBar.view.removeFromSuperview()
      self.updateViewConstraints()
      self.pageZoomBar = nil
    }
    
    if #unavailable(iOS 16.0) {
      if let findInPageBar = findInPageBar {
        updateFindInPageVisibility(visible: false)
        findInPageBar.endEditing(true)
        findInPageBar.removeFromSuperview()
        self.findInPageBar = nil
        updateViewConstraints()
      }
    }
    
    alertStackView.arrangedSubviews.forEach({
      $0.removeFromSuperview()
    })
    alertStackView.addArrangedSubview(pageZoomBar.view)

    pageZoomBar.view.snp.makeConstraints { make in
      make.height.greaterThanOrEqualTo(UIConstants.toolbarHeight)
      make.height.equalTo(UIConstants.toolbarHeight).priority(.high)
      make.edges.equalTo(alertStackView)
    }
    
    updateViewConstraints()
    self.pageZoomBar = pageZoomBar
  }
  
  func updateWebViewPageZoom(tab: Tab) {
    if let currentURL = tab.url {
      let domain = Domain.getPersistedDomain(for: currentURL)
      
      let zoomLevel = privateBrowsingManager.isPrivateBrowsing ? 1.0 : domain?.zoom_level?.doubleValue ?? Preferences.General.defaultPageZoomLevel.value
      tab.webView?.setValue(zoomLevel, forKey: PageZoomHandler.propertyName)
    }
  }
  
    public override var preferredStatusBarStyle: UIStatusBarStyle {
       
        
        if isUsingBottomBar,
            // 检查当前选中的标签（Tab）
            let tab = tabManager.selectedTab,
            // 检查标签的URL是否为无效的内部URL
          //  tab.url.map(InternalURL.isValid) == false,
            // 获取标签对应的WebView，并获取采样的页面顶部颜色
            let color =  tab.screenshotTopColor ?? tab.webView?.sampledPageTopColor {
           // print(color.description)
            // 如果采样的页面顶部颜色是浅色，则设置状态栏样式为.darkContent，否则设置为.lightContent
            return color.isLight ? .darkContent : .lightContent
        } else {
            if Preferences.NewTabPage.backgroundImages.value {
                return Preferences.NewTabPage.imagesTopColor.value ? .darkContent : .lightContent
            }
        }
        
        // 如果不满足上述条件，则调用父类的 preferredStatusBarStyle
        return super.preferredStatusBarStyle
    }

  
    func updateStatusBarOverlayColor() {
        // 使用 defer 关键字，确保在函数执行结束前调用 setNeedsStatusBarAppearanceUpdate()
        defer { setNeedsStatusBarAppearanceUpdate() }
        
//        let color = ( tab.webView?.screenshotTopColor == nil ? tab.webView?.sampledPageTopColor : tab.webView?.screenshotTopColor )
        // 检查是否正在使用底部栏、选中的标签（Tab）存在、标签的URL为无效的内部URL
        if UIDevice.current.userInterfaceIdiom == .pad {
            statusBarOverlay.backgroundColor = privateBrowsingManager.browserColors.chromeBackground
            return
        }
        
        guard isUsingBottomBar,
            let tab = tabManager.selectedTab,
            tab.url.map(InternalURL.isValid) == false,
            // 获取标签对应的WebView，并获取采样的页面顶部颜色
              let color =  tab.screenshotTopColor ?? tab.webView?.sampledPageTopColor  else {
            
          
            if Preferences.NewTabPage.backgroundImages.value {
                statusBarOverlay.backgroundColor = .clear
                return
            }
            // 如果不满足上述条件，将状态栏覆盖的背景颜色设置为私密浏览管理器的浏览器颜色的 chromeBackground
            statusBarOverlay.backgroundColor = .clear
            //= privateBrowsingManager.browserColors.chromeBackground
            return
        }
   //     print("中间点颜色：2", color)
        // 如果满足上述条件，将状态栏覆盖的背景颜色设置为采样的页面顶部颜色
        statusBarOverlay.backgroundColor = color
    }


  func navigateInTab(tab: Tab, to navigation: WKNavigation? = nil) {
    tabManager.expireSnackbars()
      
      
      do {
          if tab.onScreenshotTopColorUpdated == nil {
              tab.onScreenshotTopColorUpdated = { [weak self, weak tab] in
                  self?.updateStatusBarOverlayColor()
              }
          }
      } catch {
          print("捕获到异常：", error)
      }

    guard let webView = tab.webView else {
      print("Cannot navigate in tab without a webView")
      return
    }

    if let url = webView.url {
      // Whether to show search icon or + icon
      toolbar?.setSearchButtonState(url: url)

      if (!InternalURL.isValid(url: url) || url.isReaderModeURL), !url.isFileURL {
        // Fire the readability check. This is here and not in the pageShow event handler in ReaderMode.js anymore
        // because that event will not always fire due to unreliable page caching. This will either let us know that
        // the currently loaded page can be turned into reading mode or if the page already is in reading mode. We
        // ignore the result because we are being called back asynchronous when the readermode status changes.
        webView.evaluateSafeJavaScript(functionName: "\(ReaderModeNamespace).checkReadability", contentWorld: ReaderModeScriptHandler.scriptSandbox)

        // Only add history of a url which is not a localhost url
        if !url.isReaderModeURL {
          if !tab.isPrivate {
              DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                  self.braveCore.historyAPI.add(url: url, title: tab.title, dateAdded: Date())
              }
          }
          
          // Saving Tab.
          tabManager.saveTab(tab)
        }
      }

      TabEvent.post(.didChangeURL(url), for: tab)
    }

    if tab === tabManager.selectedTab {
     // updateStatusBarOverlayColor()
            self.updateStatusBarOverlayColor()
      UIAccessibility.post(notification: .screenChanged, argument: nil)
      // must be followed by LayoutChanged, as ScreenChanged will make VoiceOver
      // cursor land on the correct initial element, but if not followed by LayoutChanged,
      // VoiceOver will sometimes be stuck on the element, not allowing user to move
      // forward/backward. Strange, but LayoutChanged fixes that.
      UIAccessibility.post(notification: .layoutChanged, argument: nil)

      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
        self.screenshotHelper.takeScreenshot(tab)
      }
    } else if let webView = tab.webView {
      // Ref #2016: Keyboard auto hides while typing
      // For some reason the web view will steal first responder as soon
      // as its added to the view heirarchy below. This line fixes that...
      // somehow...
      webView.resignFirstResponder()
      // To Screenshot a tab that is hidden we must add the webView,
      // then wait enough time for the webview to render.
      view.insertSubview(webView, at: 0)
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
        self.screenshotHelper.takeScreenshot(tab)
        if webView.superview == self.view {
          webView.removeFromSuperview()
        }
      }
    }
  }

  public func scanQRCode() {
    if RecentSearchQRCodeScannerController.hasCameraPermissions {
      let qrCodeController = RecentSearchQRCodeScannerController { [weak self] string in
        guard let self = self else { return }

        if let url = URIFixup.getURL(string), url.isWebPage(includeDataURIs: false) {
          self.didScanQRCodeWithURL(url)
        } else {
          self.didScanQRCodeWithText(string)
        }
      }

      let navigationController = UINavigationController(rootViewController: qrCodeController)
      navigationController.modalPresentationStyle =
        UIDevice.current.userInterfaceIdiom == .phone ? .pageSheet : .formSheet

      self.present(navigationController, animated: true, completion: nil)
    } else {
      let alert = UIAlertController(title: Strings.scanQRCodeViewTitle, message: Strings.scanQRCodePermissionErrorMessage, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: Strings.scanQRCodeErrorOKButton, style: .default, handler: nil))
      self.present(alert, animated: true, completion: nil)
    }
  }
  
  func toggleReaderMode() {
    guard let tab = tabManager.selectedTab else { return }
    if let readerMode = tab.getContentScript(name: ReaderModeScriptHandler.scriptName) as? ReaderModeScriptHandler {
      switch readerMode.state {
      case .available:
        enableReaderMode()
      case .active:
        disableReaderMode()
      case .unavailable:
          let toast = ButtonToast(
              labelText: Strings.Other.readEnable,
              image: UIImage(braveSystemNamed: "leo.smartphone.tablet-portrait"),
              buttonText: Strings.OBContinueButton,
              completion: { [weak self] buttonPressed in
                  guard let self = self else { return }

              })

          show(toast: toast, duration: ButtonToastUX.toastDismissShortAfter)
        break
      }
    }
  }
  
    func handleToolbarVisibilityStateChange(
      _ state: ToolbarVisibilityViewModel.ToolbarState,
      progress: CGFloat?
    ) {
      // 检查是否有选定的标签，以及标签是否包含WebView并且WebView未处于加载状态
      guard
        let tab = tabManager.selectedTab,
        let webView = tab.webView,
        !webView.isLoading else {
        
        // 如果没有选定的标签或WebView正在加载，则将工具栏的约束更新为0
        toolbarTopConstraint?.update(offset: 0)
        toolbarBottomConstraint?.update(offset: 0)
        
        // 检查UI侧是否已经折叠
        if topToolbar.locationContainer.alpha < 1 {
          // 如果已经折叠，则创建动画以展开UI侧
          let animator = toolbarVisibilityViewModel.toolbarChangePropertyAnimator
          animator.addAnimations { [self] in
            view.layoutIfNeeded()
            topToolbar.locationContainer.alpha = 1
            topToolbar.actionButtons.forEach { $0.alpha = topToolbar.locationContainer.alpha }
            header.collapsedBarContainerView.alpha = 1 - topToolbar.locationContainer.alpha
            tabsBar.view.alpha = topToolbar.locationContainer.alpha
            toolbar?.actionButtons.forEach { $0.alpha = topToolbar.locationContainer.alpha }
          }
          animator.startAnimation()
        }
          if UIDevice.current.userInterfaceIdiom == .phone {
              topToolbar.isHidden = true
          }
        return
      }
      
      // 如果有选定的标签且WebView不在加载状态
      let headerHeight = isUsingBottomBar ? 0 : toolbarVisibilityViewModel.transitionDistance
      let footerHeight = footer.bounds.height + (isUsingBottomBar ? toolbarVisibilityViewModel.transitionDistance - view.safeAreaInsets.bottom : 0)
      
      // 在滚动时更改WebView的大小并且PDF可见时，会导致奇怪的闪烁，因此仅在PDF可见时显示最终的扩展/折叠状态
      if let progress = progress, tab.mimeType != MIMEType.PDF {
        switch state {
        case .expanded:
          // 更新工具栏约束以展开UI
            if UIDevice.current.userInterfaceIdiom == .phone {
                topToolbar.isHidden = true
            }
            
          toolbarTopConstraint?.update(offset: -min(headerHeight, max(0, headerHeight * progress)))
          topToolbar.locationContainer.alpha = max(0, min(1, 1 - (progress * 1.5))) // 使其更快地消失
          toolbarBottomConstraint?.update(offset: min(footerHeight, max(0, footerHeight * progress)))
        case .collapsed:
          // 更新工具栏约束以折叠UI
          toolbarTopConstraint?.update(offset: -min(headerHeight, max(0, headerHeight * (1 - progress))))
          topToolbar.locationContainer.alpha = progress
          toolbarBottomConstraint?.update(offset: min(footerHeight, max(0, footerHeight * (1 - progress))))
            
            topToolbar.isHidden = false
        }
        // 更新其他UI元素的透明度
        topToolbar.actionButtons.forEach { $0.alpha = topToolbar.locationContainer.alpha }
        tabsBar.view.alpha = topToolbar.locationContainer.alpha
        header.collapsedBarContainerView.alpha = 1 - topToolbar.locationContainer.alpha
        toolbar?.actionButtons.forEach { $0.alpha = topToolbar.locationContainer.alpha }
        return
      }
      
      // 如果没有提供进度值，则根据工具栏状态执行不同的操作
      switch state {
      case .expanded:
          if UIDevice.current.userInterfaceIdiom == .phone {
              topToolbar.isHidden = true
          }
        // 更新工具栏约束以展开UI
        toolbarTopConstraint?.update(offset: 0)
        toolbarBottomConstraint?.update(offset: 0)
        topToolbar.locationContainer.alpha = 1
      case .collapsed:
        // 更新工具栏约束以折叠UI
        toolbarTopConstraint?.update(offset: -headerHeight)
        topToolbar.locationContainer.alpha = 0
        toolbarBottomConstraint?.update(offset: footerHeight)
          topToolbar.isHidden = false
      }
      // 更新其他UI元素的透明度
      tabsBar.view.alpha = topToolbar.locationContainer.alpha
      topToolbar.actionButtons.forEach { $0.alpha = topToolbar.locationContainer.alpha }
      header.collapsedBarContainerView.alpha = 1 - topToolbar.locationContainer.alpha
      toolbar?.actionButtons.forEach { $0.alpha = topToolbar.locationContainer.alpha }
      
      // 创建动画以确保界面布局的平滑过渡
      let animator = toolbarVisibilityViewModel.toolbarChangePropertyAnimator
      animator.addAnimations {
        self.view.layoutIfNeeded()
      }
      animator.startAnimation()
    }

}

extension BrowserViewController {
  func didScanQRCodeWithURL(_ url: URL) {
    let overlayText = URLFormatter.formatURL(url.absoluteString, formatTypes: [], unescapeOptions: [])

    popToBVC() {
      self.topToolbar.enterOverlayMode(overlayText, pasted: false, search: false)
    }

    if !url.isBookmarklet && !privateBrowsingManager.isPrivateBrowsing {
      RecentSearch.addItem(type: .qrCode, text: nil, websiteUrl: url.absoluteString)
    }
  }

  func didScanQRCodeWithText(_ text: String) {
    popToBVC()
    submitSearchText(text)

    if !privateBrowsingManager.isPrivateBrowsing {
      RecentSearch.addItem(type: .qrCode, text: text, websiteUrl: nil)
    }
  }
}

extension BrowserViewController: SettingsDelegate {
  func settingsOpenURLInNewTab(_ url: URL) {
    let forcedPrivate = privateBrowsingManager.isPrivateBrowsing
    self.openURLInNewTab(url, isPrivate: forcedPrivate, isPrivileged: false)
  }

  func settingsOpenURLs(_ urls: [URL], loadImmediately: Bool) {
    let tabIsPrivate = TabType.of(tabManager.selectedTab).isPrivate
    self.tabManager.addTabsForURLs(urls, zombie: !loadImmediately, isPrivate: tabIsPrivate)
  }
}

extension BrowserViewController: PresentingModalViewControllerDelegate {
  func dismissPresentedModalViewController(_ modalViewController: UIViewController, animated: Bool) {
    self.dismiss(animated: animated, completion: nil)
  }
}

extension BrowserViewController: TabsBarViewControllerDelegate {
  func tabsBarDidSelectAddNewTab(_ isPrivate: Bool) {
    openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: isPrivate)
  }

  func tabsBarDidSelectTab(_ tabsBarController: TabsBarViewController, _ tab: Tab) {
    if tab == tabManager.selectedTab { return }
    topToolbar.leaveOverlayMode(didCancel: true)
    if #unavailable(iOS 16.0) {
      updateFindInPageVisibility(visible: false)
    }
    
    tabManager.selectTab(tab)
  }

  func tabsBarDidLongPressAddTab(_ tabsBarController: TabsBarViewController, button: UIButton) {
    // The actions are carried to menu actions for Tab-Tray Button
  }
  
  func tabsBarDidChangeReaderModeVisibility(_ isHidden: Bool = true) {
    switch topToolbar.locationView.readerModeState {
    case .active:
      if isHidden {
        hideReaderModeBar(animated: false)
      } else {
        showReaderModeBar(animated: false)
      }
    case .unavailable:
      hideReaderModeBar(animated: false)
    default:
      break
    }
  }
  
  func tabsBarDidSelectAddNewWindow(_ isPrivate: Bool) {
    self.openInNewWindow(url: nil, isPrivate: isPrivate)
  }
}

extension BrowserViewController: TabDelegate {
    func tab(_ tab: Tab, didCreateWebView webView: WKWebView) {
        // 将 webView 的 frame 设置为 webViewContainer 的 frame
        webView.frame = webViewContainer.frame
        
        // 作为与 tab 一样长寿的观察者。确保在下面的 willDeleteWebView 中清除所有这些观察者！
        KVOs.forEach { webView.addObserver(self, forKeyPath: $0.keyPath, options: .new, context: nil) }
        webView.uiDelegate = self
        
        let enableScripts = Userscript.getEnable()

        // 遍历数组，拼接 script 字段
        var combinedScript = ""
        for userscript in enableScripts {
            if let script = userscript.script {
                combinedScript.append("try{")
                combinedScript.append(script)
                combinedScript.append("}catch(e){}\n") // 每次拼接都在末尾添加换行符
            }
        }

       
        
        // 注入的脚本数组
        var injectedScripts: [TabContentScript] = [
            ReaderModeScriptHandler(tab: tab),
            ErrorPageHelper(certStore: profile.certStore),
            SessionRestoreScriptHandler(tab: tab),
            PrintScriptHandler(browserController: self, tab: tab),
            CustomSearchScriptHandler(tab: tab),
            NightModeScriptHandler(tab: tab),
            FocusScriptHandler(tab: tab),
            BraveGetUA(tab: tab),
            BraveSearchScriptHandler(tab: tab, profile: profile, rewards: rewards),
            ResourceDownloadScriptHandler(tab: tab),
            DownloadContentScriptHandler(browserController: self, tab: tab),
            WindowRenderScriptHandler(tab: tab),
            PlaylistScriptHandler(tab: tab),
            PlaylistFolderSharingScriptHandler(tab: tab),
            //RewardsReportingScriptHandler(rewards: rewards, tab: tab),
            //AdsMediaReportingScriptHandler(rewards: rewards, tab: tab),
            ReadyStateScriptHandler(tab: tab),
            DeAmpScriptHandler(tab: tab),
            SiteStateListenerScriptHandler(tab: tab),
            CosmeticFiltersScriptHandler(tab: tab),
            URLPartinessScriptHandler(tab: tab),
            FaviconScriptHandler(tab: tab),
            YoutubeQualityScriptHandler(tab: tab),
            CustomUserScriptsHandler(browserController: self, tab: tab, javascript: combinedScript),
            
            tab.contentBlocker,
            tab.requestBlockingContentHelper,
        ]
        
        // 如果支持 iOS 16.0，添加 FindInPageScriptHandler
        if #unavailable(iOS 16.0) {
            injectedScripts.append(FindInPageScriptHandler(tab: tab))
        }
        
        // 如果支持 BraveTalk，添加 BraveTalkScriptHandler
//        #if canImport(BraveTalk)
//        injectedScripts.append(BraveTalkScriptHandler(tab: tab, rewards: rewards, launchNativeBraveTalk: { [weak self] tab, room, token in
//            self?.launchNativeBraveTalk(tab: tab, room: room, token: token)
//        }))
//        #endif
        
        // 如果存在 BraveSkusScriptHandler，则添加
        if let braveSkusHandler = BraveSkusScriptHandler(tab: tab) {
            injectedScripts.append(braveSkusHandler)
        }
        
        // 仅在 tab 不是私密浏览标签时添加登录处理程序和钱包提供程序
        if !tab.isPrivate {
            injectedScripts += [
                LoginsScriptHandler(tab: tab, profile: profile, passwordAPI: braveCore.passwordAPI),
//                EthereumProviderScriptHandler(tab: tab),
//                SolanaProviderScriptHandler(tab: tab)
            ]
        }

        // XXX: Bug 1390200 - 暂时禁用 NSUserActivity/CoreSpotlight
        // let spotlightHelper = SpotlightHelper(tab: tab)
        // tab.addHelper(spotlightHelper, name: SpotlightHelper.name())
        
        // 将注入的脚本添加到 tab 中
        injectedScripts.forEach {
            tab.addContentScript($0, name: type(of: $0).scriptName, contentWorld: type(of: $0).scriptSandbox)
        }
        
        // 设置一些脚本的委托
        (tab.getContentScript(name: ReaderModeScriptHandler.scriptName) as? ReaderModeScriptHandler)?.delegate = self
        (tab.getContentScript(name: SessionRestoreScriptHandler.scriptName) as? SessionRestoreScriptHandler)?.delegate = self
        if #unavailable(iOS 16.0) {
            (tab.getContentScript(name: FindInPageScriptHandler.scriptName) as? FindInPageScriptHandler)?.delegate = self
        }
        (tab.getContentScript(name: PlaylistScriptHandler.scriptName) as? PlaylistScriptHandler)?.delegate = self
        (tab.getContentScript(name: PlaylistFolderSharingScriptHandler.scriptName) as? PlaylistFolderSharingScriptHandler)?.delegate = self
//        (tab.getContentScript(name: Web3NameServiceScriptHandler.scriptName) as? Web3NameServiceScriptHandler)?.delegate = self
//        (tab.getContentScript(name: Web3IPFSScriptHandler.scriptName) as? Web3IPFSScriptHandler)?.delegate = self
    }


    // 删除WebView的代理方法
    func tab(_ tab: Tab, willDeleteWebView webView: WKWebView) {
        tab.cancelQueuedAlerts() // 取消排队的警告
        KVOs.forEach { webView.removeObserver(self, forKeyPath: $0.keyPath) } // 移除键值观察
        toolbarVisibilityViewModel.endScrollViewObservation(webView.scrollView) // 结束滚动视图观察
        webView.uiDelegate = nil // 清空WebView的UI代理
        webView.removeFromSuperview() // 从父视图中移除WebView
    }

    // 显示SnackBar的方法
    func showBar(_ bar: SnackBar, animated: Bool) {
        view.layoutIfNeeded() // 立即布局子视图
        UIView.animate(
          withDuration: animated ? 0.25 : 0,
          animations: {
            self.alertStackView.insertArrangedSubview(bar, at: 0) // 在堆栈视图中插入SnackBar
            self.view.layoutIfNeeded() // 重新布局
          })
    }

    // 移除SnackBar的方法
    func removeBar(_ bar: SnackBar, animated: Bool) {
        UIView.animate(
          withDuration: animated ? 0.25 : 0,
          animations: {
            bar.removeFromSuperview() // 从父视图中移除SnackBar
          })
    }

    // 移除所有SnackBar的方法
    func removeAllBars() {
        alertStackView.arrangedSubviews.forEach { $0.removeFromSuperview() } // 移除堆栈视图中的所有子视图
    }

    // Tab代理方法，当Snackbar添加到Tab时调用
    func tab(_ tab: Tab, didAddSnackbar bar: SnackBar) {
        showBar(bar, animated: true) // 显示SnackBar
    }

    // Tab代理方法，当Snackbar从Tab中移除时调用
    func tab(_ tab: Tab, didRemoveSnackbar bar: SnackBar) {
        removeBar(bar, animated: true) // 移除SnackBar
    }

    // Tab代理方法，当选择页面中的文本并选择“在页面中查找”时调用
    func tab(_ tab: Tab, didSelectFindInPageFor selectedText: String) {
        if #available(iOS 16.0, *), let findInteraction = tab.webView?.findInteraction {
            findInteraction.searchText = selectedText
            findInteraction.presentFindNavigator(showingReplace: false)
        } else {
            updateFindInPageVisibility(visible: true)
            findInPageBar?.text = selectedText
        }
    }

    // Tab代理方法，当选择页面中的文本并选择“使用Brave搜索”时调用
    func tab(_ tab: Tab, didSelectSearchWithBraveFor selectedText: String) {
        let engine = profile.searchEngines.defaultEngine(forType: tab.isPrivate ? .privateMode : .standard)

        guard let url = engine.searchURLForQuery(selectedText) else {
            assertionFailure("If this returns nil, investigate why and add proper handling or commenting")
            return
        }

        tabManager.addTabAndSelect(
          URLRequest(url: url),
          afterTab: tab,
          isPrivate: tab.isPrivate
        )
        
        if !privateBrowsingManager.isPrivateBrowsing {
            RecentSearch.addItem(type: .text, text: selectedText, websiteUrl: url.absoluteString)
        }
    }

    // 显示Brave Talk奖励面板的方法
    func showRequestRewardsPanel(_ tab: Tab) {
//        let vc = BraveTalkRewardsOptInViewController()
//
//        // 特殊情况：用户禁用了奖励按钮并希望访问免费的Brave Talk
//        // 我们重新启用按钮。稍后可以在设置中禁用它。
//        Preferences.Rewards.hideRewardsIcon.value = false
//
//        let popover = PopoverController(
//          contentController: vc,
//          contentSizeBehavior: .preferredContentSize)
//        popover.addsConvenientDismissalMargins = false
//        popover.present(from: topToolbar.rewardsButton, on: self)
//        popover.popoverDidDismiss = { _ in
//          // 如果用户手势取消了弹出窗口，则调用此处
//          // 这不会与'启用奖励'按钮冲突。
//          tab.rewardsEnabledCallback?(false)
//        }
//
//        vc.rewardsEnabledHandler = { [weak self] in
//          guard let self = self else { return }
//
//          self.rewards.isEnabled = true
//          tab.rewardsEnabledCallback?(true)
//
//          let vc2 = BraveTalkOptInSuccessViewController()
//          let popover2 = PopoverController(
//            contentController: vc2,
//            contentSizeBehavior: .preferredContentSize)
//          popover2.present(from: self.topToolbar.rewardsButton, on: self)
//        }
//
//        vc.linkTapped = { [unowned self] request in
//          tab.rewardsEnabledCallback?(false)
//          self.tabManager
//            .addTabAndSelect(request, isPrivate: privateBrowsingManager.isPrivateBrowsing)
//        }
    }


  func stopMediaPlayback(_ tab: Tab) {
    tabManager.allTabs.forEach({
      PlaylistScriptHandler.stopPlayback(tab: $0)
    })
  }
  
  func showWalletNotification(_ tab: Tab, origin: URLOrigin) {
//    // only display notification when BVC is front and center
//    guard presentedViewController == nil,
//          Preferences.Wallet.displayWeb3Notifications.value else {
//      return
//    }
//    let origin = tab.getOrigin()
//    let tabDappStore = tab.tabDappStore
//    let walletNotificaton = WalletNotification(priority: .low, origin: origin, isUsingBottomBar: isUsingBottomBar) { [weak self] action in
//      if action == .connectWallet {
//        self?.presentWalletPanel(from: origin, with: tabDappStore)
//      }
//    }
//    notificationsPresenter.display(notification: walletNotificaton, from: self)
  }
  
    // 判断给定的标签（Tab）是否可见
    func isTabVisible(_ tab: Tab) -> Bool {
        // 如果选定的标签与给定的标签相同，则返回 true，否则返回 false
        return tabManager.selectedTab === tab
    }

    // 更新URL栏的钱包按钮状态
    func updateURLBarWalletButton() {
        // 判断是否应该显示钱包按钮
        let shouldShowWalletButton = tabManager.selectedTab?.isWalletIconVisible == true
        
        if shouldShowWalletButton {
            // 异步任务，在主线程中执行
            Task { @MainActor in
                // 检查是否有未处理的请求
                let isPendingRequestAvailable = await isPendingRequestAvailable()
                // 更新顶部工具栏上的钱包按钮状态
                topToolbar.updateWalletButtonState(isPendingRequestAvailable ? .activeWithPendingRequest : .active)
            }
        } else {
            // 如果不应该显示钱包按钮，则将其状态设置为非活动状态
            topToolbar.updateWalletButtonState(.inactive)
        }
    }

    // 重新加载IPFS方案的URL
    func reloadIPFSSchemeUrl(_ url: URL) {
        // 处理IPFS方案的URL
        handleIPFSSchemeURL(url)
    }

    // 标签重新加载时调用的方法
    func didReloadTab(_ tab: Tab) {
        // 重置外部警报属性
        resetExternalAlertProperties(tab)
    }

    // 在主线程中异步检查是否有未处理的请求
    @MainActor
    private func isPendingRequestAvailable() async -> Bool {
        // 获取是否处于私密浏览模式
//        let privateMode = privateBrowsingManager.isPrivateBrowsing
//        
//        // 如果有打开的 `WalletStore`，则使用它以便在钱包打开时分配待处理的请求
//        // 这允许我们存储新的 `PendingRequest`，从而触发该请求的模态呈现
//        guard let cryptoStore = self.walletStore?.cryptoStore ?? CryptoStore.from(ipfsApi: braveCore.ipfsAPI, privateMode: privateMode) else {
//            return false
//        }
//        
//        // 检查是否有未处理的请求
//        if await cryptoStore.isPendingRequestAvailable() {
//            return true
//        } else if let selectedTabOrigin = tabManager.selectedTab?.url?.origin {
//            // 如果选定的标签有原始URL，则检查是否有待处理的请求
//            if WalletProviderAccountCreationRequestManager.shared.hasPendingRequest(for: selectedTabOrigin, coinType: .sol) {
//                return true
//            }
//            
//            // 检查是否有待处理的请求，根据选定标签的原始URL和币种类型
//            return WalletProviderPermissionRequestsManager.shared.hasPendingRequest(for: selectedTabOrigin, coinType: .eth)
//        }
//        
        // 如果没有未处理的请求，则返回 false
        return false
    }

  
  func resetExternalAlertProperties(_ tab: Tab?) {
    if let tab = tab {
      tab.resetExternalAlertProperties()
    }
  }
}

extension BrowserViewController: SearchViewControllerDelegate {
  func searchViewController(_ searchViewController: SearchViewController, didSubmit query: String, braveSearchPromotion: Bool) {
    topToolbar.leaveOverlayMode()
    processAddressBar(text: query, isBraveSearchPromotion: braveSearchPromotion)
  }

  func searchViewController(_ searchViewController: SearchViewController, didSelectURL url: URL) {
    finishEditingAndSubmit(url)
  }

  func searchViewController(_ searchViewController: SearchViewController, didSelectOpenTab tabInfo: (id: UUID?, url: URL)) {
    switchToTabOrOpen(id: tabInfo.id, url: tabInfo.url)
  }
  
  func searchViewController(_ searchViewController: SearchViewController, didLongPressSuggestion suggestion: String) {
    self.topToolbar.setLocation(suggestion, search: true)
  }

  func presentSearchSettingsController() {
    let settingsNavigationController = SearchSettingsTableViewController(profile: profile, privateBrowsingManager: privateBrowsingManager)
    let navController = ModalSettingsNavigationController(rootViewController: settingsNavigationController)

    self.present(navController, animated: true, completion: nil)
  }
    
    func presentHomeSettingsController() {
      let nTPTableViewController = NTPTableViewController()
      let navController = ModalSettingsNavigationController(rootViewController: nTPTableViewController)

      self.present(navController, animated: true, completion: nil)
    }

  func searchViewController(_ searchViewController: SearchViewController, didHighlightText text: String, search: Bool) {
    self.topToolbar.setLocation(text, search: search)
  }

  func searchViewController(_ searchViewController: SearchViewController, shouldFindInPage query: String) {
    topToolbar.leaveOverlayMode()
    if #available(iOS 16.0, *), let findInteraction = tabManager.selectedTab?.webView?.findInteraction {
      findInteraction.searchText = query
      findInteraction.presentFindNavigator(showingReplace: false)
    } else {
      updateFindInPageVisibility(visible: true)
      findInPageBar?.text = query
    }
  }

  func searchViewControllerAllowFindInPage() -> Bool {
    if let url = tabManager.selectedTab?.webView?.url,
      let internalURL = InternalURL(url),
      internalURL.isAboutHomeURL {
      return false
    }
    return true
  }
}
// MARK: - UIPopoverPresentationControllerDelegate

// 实现UIPopoverPresentationControllerDelegate协议
extension BrowserViewController: UIPopoverPresentationControllerDelegate {
    
    // 当Popover被关闭时调用的方法
    public func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        displayedPopoverController = nil
        updateDisplayedPopoverProperties = nil
    }
}

// 实现UIAdaptivePresentationControllerDelegate协议
extension BrowserViewController: UIAdaptivePresentationControllerDelegate {
    
    // 在这里返回.none确保Popover以Popover形式呈现，而不是作为全屏模态，默认在紧凑设备上是全屏模态。
    public func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
}

// 实现SessionRestoreScriptHandlerDelegate协议
extension BrowserViewController: SessionRestoreScriptHandlerDelegate {
    
    // 当会话恢复处理程序完成对标签页的会话恢复时调用的方法
    func sessionRestore(_ handler: SessionRestoreScriptHandler, didRestoreSessionForTab tab: Tab) {
        tab.restoring = false
        
        // 如果当前有选定的标签页，则更新UI以反映阅读主页状态
        if let tab = tabManager.selectedTab {
            updateUIForReaderHomeStateForTab(tab)
        }
    }
}

// 实现TabTrayDelegate协议
extension BrowserViewController: TabTrayDelegate {
    
    // 当标签页顺序发生变化时调用的方法
    func tabOrderChanged() {
        tabsBar.updateData()
    }
}

// 实现JSPromptAlertControllerDelegate协议
extension BrowserViewController: JSPromptAlertControllerDelegate {
    
    // 当JSPromptAlertController被关闭时调用的方法
    func promptAlertControllerDidDismiss(_ alertController: JSPromptAlertController) {
        // 如果有等待显示的警报，则显示它
        showQueuedAlertIfAvailable()
    }
}


// BrowserViewController的扩展，遵循ToolbarUrlActionsDelegate协议
extension BrowserViewController: ToolbarUrlActionsDelegate {
    
  /// 用户在菜单中可以执行的不同操作类型
  private enum ToolbarURLAction {
    case openInCurrentTab
    case openInNewTab(isPrivate: Bool)
    case copy
    case share
  }

  // 在新标签中打开URL
  func openInNewTab(_ url: URL, isPrivate: Bool) {
    topToolbar.leaveOverlayMode()
    select(url, action: .openInNewTab(isPrivate: isPrivate), isUserDefinedURLNavigation: false)
  }

  // 复制URL
  func copy(_ url: URL) {
    select(url, action: .copy, isUserDefinedURLNavigation: false)
  }

  // 分享URL
  func share(_ url: URL) {
    select(url, action: .share, isUserDefinedURLNavigation: false)
  }

  // 批量打开多个URL
  func batchOpen(_ urls: [URL]) {
    let tabIsPrivate = TabType.of(tabManager.selectedTab).isPrivate
    self.tabManager.addTabsForURLs(urls, zombie: false, isPrivate: tabIsPrivate)
  }
  
  // 选择URL，用于在当前标签中打开
  func select(url: URL, isUserDefinedURLNavigation: Bool) {
    select(url, action: .openInCurrentTab, isUserDefinedURLNavigation: isUserDefinedURLNavigation)
  }

  // 处理选择URL的操作
  private func select(_ url: URL, action: ToolbarURLAction, isUserDefinedURLNavigation: Bool) {
    switch action {
    case .openInCurrentTab:
      // 在当前标签中完成编辑并提交URL
      finishEditingAndSubmit(url, isUserDefinedURLNavigation: isUserDefinedURLNavigation)
      updateURLBarWalletButton()
      
    case .openInNewTab(let isPrivate):
      // 在新标签中打开URL
      let tab = tabManager.addTab(PrivilegedRequest(url: url) as URLRequest, afterTab: tabManager.selectedTab, isPrivate: isPrivate)
      if isPrivate && !privateBrowsingManager.isPrivateBrowsing {
        // 如果是私密标签，且未启用私密浏览，则选择新标签
        tabManager.selectTab(tab)
      } else {
        // 如果正在显示顶部标签栏，用户可以使用顶部标签栏
        // 如果在覆盖模式下切换，无法正确关闭主页面板
        guard !topToolbar.inOverlayMode else {
          return
        }
        // 如果未显示顶部标签栏，则显示一个提示，以快速切换到新打开的标签
        let toast = ButtonToast(
          labelText: Strings.contextMenuButtonToastNewTabOpenedLabelText, buttonText: Strings.contextMenuButtonToastNewTabOpenedButtonText,
          completion: { buttonPressed in
            if buttonPressed {
              self.tabManager.selectTab(tab)
            }
          })
        show(toast: toast)
      }
      updateURLBarWalletButton()
      
    case .copy:
      // 复制URL到剪贴板
      UIPasteboard.general.url = url
      
    case .share:
      // 分享URL
      if presentedViewController != nil {
        dismiss(animated: true) {
          self.presentActivityViewController(
            url,
            sourceView: self.view,
            sourceRect: self.view.convert(self.topToolbar.shareButton.frame, from: self.topToolbar.shareButton.superview),
            arrowDirection: [.up]
          )
        }
      } else {
        presentActivityViewController(
          url,
          sourceView: view,
          sourceRect: view.convert(topToolbar.shareButton.frame, from: topToolbar.shareButton.superview),
          arrowDirection: [.up]
        )
      }
    }
  }
}


// 在BrowserViewController的扩展中实现NewTabPageDelegate协议的方法
extension BrowserViewController: NewTabPageDelegate {
  
  // 导航到输入的网址，可以选择在新标签中打开，同时可以选择切换到隐私模式
  func navigateToInput(_ input: String, inNewTab: Bool, switchingToPrivateMode: Bool) {
    // 调用处理URL输入的方法，传递相关参数
    handleURLInput(input, inNewTab: inNewTab, switchingToPrivateMode: switchingToPrivateMode, isFavourite: false)
  }

  // 处理收藏夹中的操作，比如打开，编辑等
  func handleFavoriteAction(favorite: Favorite, action: BookmarksAction) {
    guard let url = favorite.url else { return }
    switch action {
    // 处理打开操作，可以选择在新标签中打开，同时可以选择切换到隐私模式
    case .opened(let inNewTab, let switchingToPrivateMode):
      if switchingToPrivateMode, Preferences.Privacy.privateBrowsingLock.value {
        // 如果需要切换到隐私模式，则进行本地身份验证
        self.askForLocalAuthentication { [weak self] success, error in
          if success {
            // 验证成功后，处理URL输入
            self?.handleURLInput(
              url,
              inNewTab: inNewTab,
              switchingToPrivateMode: switchingToPrivateMode,
              isFavourite: true
            )
          }
        }
      } else {
        // 直接处理URL输入
        handleURLInput(
          url,
          inNewTab: inNewTab,
          switchingToPrivateMode: switchingToPrivateMode,
          isFavourite: true
        )
      }
    // 处理编辑操作
    case .edited:
      guard let title = favorite.displayTitle, let urlString = favorite.url else { return }
      // 弹出用户输入框，用于编辑标题和URL
      let editPopup =
        UIAlertController
        .userTextInputAlert(
          title: Strings.editFavorite,
          message: urlString,
          startingText: title, startingText2: favorite.url,
          placeholder2: urlString,
          keyboardType2: .URL
        ) { callbackTitle, callbackUrl in
          if let cTitle = callbackTitle, !cTitle.isEmpty, let cUrl = callbackUrl, !cUrl.isEmpty {
            if URL(string: cUrl) != nil {
              // 更新收藏夹信息
              favorite.update(customTitle: cTitle, url: cUrl)
            }
          }
        }
      self.present(editPopup, animated: true)
    }
  }
  
  // 处理URL输入的私有方法，根据需要在新标签中打开，并在编辑收藏夹时进行特殊处理
  private func handleURLInput(_ input: String, inNewTab: Bool, switchingToPrivateMode: Bool, isFavourite: Bool ) {
    let isPrivate = privateBrowsingManager.isPrivateBrowsing || switchingToPrivateMode
    if inNewTab {
      // 如果需要在新标签中打开，则添加新标签并选中
      tabManager.addTabAndSelect(isPrivate: isPrivate)
    }
    
    // 用于确定URL导航是否来自书签，如果是，则在finishEditingAndSubmit中进行不同处理
    processAddressBar(text: input, isUserDefinedURLNavigation: isFavourite)
  }

  // 聚焦URL地址栏的方法
  func focusURLBar() {
    topToolbar.tabLocationViewDidTapLocation(topToolbar.locationView)
  }

  // 处理品牌图片信息弹出框的方法
  func brandedImageCalloutActioned(_ state: BrandedImageCalloutState) {
    guard state.hasDetailViewController else { return }

    // 创建并显示LearnMore视图控制器
    let vc = NTPLearnMoreViewController(state: state, rewards: rewards)

    vc.linkHandler = { [weak self] url in
      // 处理链接点击事件，加载到选定标签中
      self?.tabManager.selectedTab?.loadRequest(PrivilegedRequest(url: url) as URLRequest)
    }

    addChild(vc)
    view.addSubview(vc.view)
    vc.view.snp.remakeConstraints {
      $0.right.top.bottom.leading.equalToSuperview()
    }
  }

  // 点击QR码按钮的方法
  func tappedQRCodeButton(url: URL) {
    // 创建并显示QR码弹出框
    let qrPopup = QRCodePopupView(url: url)
    qrPopup.showWithType(showType: .flyUp)
    qrPopup.qrCodeShareHandler = { [weak self] url in
      guard let self = self else { return }

      let viewRect = CGRect(origin: self.view.center, size: .zero)

      // 调用ActivityViewController分享URL
      self.presentActivityViewController(
        url, sourceView: self.view, sourceRect: viewRect,
        arrowDirection: .any)
    }
  }
}


extension BrowserViewController: PreferencesObserver {
    // 当用户偏好设置发生改变时调用的方法
    public func preferencesDidChange(for key: String) {
        switch key {
        case Preferences.General.tabBarVisibility.key:
            // 标签栏可见性发生改变，更新标签栏的可见性
            updateTabsBarVisibility()
        case Preferences.Privacy.privateBrowsingOnly.key:
            // 隐私浏览模式偏好设置发生改变
            privateBrowsingManager.isPrivateBrowsing = Preferences.Privacy.privateBrowsingOnly.value
            setupTabs()
            updateTabsBarVisibility()
            updateApplicationShortcuts()
        case Preferences.UserAgent.alwaysRequestDesktopSite.key:
            // 总是请求桌面站点的偏好设置发生改变
            tabManager.reset()
            tabManager.reloadSelectedTab()
        case Preferences.General.enablePullToRefresh.key:
            // 启用下拉刷新的偏好设置发生改变
            tabManager.selectedTab?.updatePullToRefreshVisibility()
        case ShieldPreferences.blockAdsAndTrackingLevelRaw.key,
             Preferences.Shields.blockScripts.key,
             Preferences.Shields.blockImages.key,
             Preferences.Shields.fingerprintingProtection.key,
             Preferences.Shields.useRegionAdBlock.key:
            // 广告和跟踪屏蔽相关的偏好设置发生改变
            tabManager.allTabs.forEach { $0.webView?.reload() }
        case Preferences.General.defaultPageZoomLevel.key:
            // 默认页面缩放级别的偏好设置发生改变
            tabManager.allTabs.forEach({
                guard let url = $0.webView?.url else { return }
                let zoomLevel = $0.isPrivate ? 1.0 : Domain.getPersistedDomain(for: url)?.zoom_level?.doubleValue ?? Preferences.General.defaultPageZoomLevel.value
                $0.webView?.setValue(zoomLevel, forKey: PageZoomHandler.propertyName)
            })
        case Preferences.Shields.httpsEverywhere.key:
            // HTTPS Everywhere偏好设置发生改变
            tabManager.reset()
            tabManager.reloadSelectedTab()
        case Preferences.Privacy.blockAllCookies.key,
             Preferences.Shields.googleSafeBrowsing.key:
            // 阻止所有 Cookie 和 Google 安全浏览偏好设置发生改变
            // 所有 'block all cookies' 开关需要 Webkit 配置的硬重置
            tabManager.reset()
            if !Preferences.Privacy.blockAllCookies.value {
                HTTPCookie.loadFromDisk { _ in
                    self.tabManager.reloadSelectedTab()
                    for tab in self.tabManager.allTabs where tab != self.tabManager.selectedTab {
                        tab.createWebview()
                        if let url = tab.webView?.url {
                            tab.loadRequest(PrivilegedRequest(url: url) as URLRequest)
                        }
                    }
                }
            } else {
                tabManager.reloadSelectedTab()
            }
        case Preferences.Rewards.hideRewardsIcon.key,
             Preferences.Rewards.rewardsToggledOnce.key:
            // 隐藏奖励图标和奖励开关偏好设置发生改变
            updateRewardsButtonState()
        case Preferences.Playlist.webMediaSourceCompatibility.key:
            // Web 媒体源兼容性偏好设置发生改变
            tabManager.allTabs.forEach {
                $0.setScript(script: .playlistMediaSource, enabled: Preferences.Playlist.webMediaSourceCompatibility.value)
                $0.webView?.reload()
            }
        case Preferences.General.mediaAutoBackgrounding.key:
            // 媒体自动后台播放偏好设置发生改变
            tabManager.allTabs.forEach {
                $0.setScript(script: .mediaBackgroundPlay, enabled: Preferences.General.mediaAutoBackgrounding.value)
                $0.webView?.reload()
            }
        case Preferences.General.youtubeHighQuality.key:
            // YouTube 高质量偏好设置发生改变
            tabManager.allTabs.forEach {
                YoutubeQualityScriptHandler.setEnabled(option: Preferences.General.youtubeHighQuality, for: $0)
            }
        case Preferences.Playlist.enablePlaylistMenuBadge.key,
             Preferences.Playlist.enablePlaylistURLBarButton.key:
            // 启用播放列表菜单徽章和启用播放列表 URL 按钮偏好设置发生改变
            let selectedTab = tabManager.selectedTab
            updatePlaylistURLBar(
                tab: selectedTab,
                state: selectedTab?.playlistItemState ?? .none,
                item: selectedTab?.playlistItem)
        case Preferences.PrivacyReports.captureShieldsData.key:
            // 捕获屏蔽数据偏好设置发生改变
            PrivacyReportsManager.scheduleProcessingBlockedRequests(isPrivateBrowsing: privateBrowsingManager.isPrivateBrowsing)
            PrivacyReportsManager.scheduleNotification(debugMode: !AppConstants.buildChannel.isPublic)
        case Preferences.PrivacyReports.captureVPNAlerts.key:
            // 捕获 VPN 警报偏好设置发生改变
            PrivacyReportsManager.scheduleVPNAlertsTask()
       
        case Preferences.Playlist.syncSharedFoldersAutomatically.key:
            // 自动同步共享文件夹播放列表偏好设置发生改变
            syncPlaylistFolders()
        case Preferences.NewTabPage.backgroundSponsoredImages.key:
            // 背景赞助图片偏好设置发生改变
            recordAdsUsageType()
        case Preferences.Privacy.screenTimeEnabled.key:
            // 屏幕时间启用偏好设置发生改变
            if Preferences.Privacy.screenTimeEnabled.value {
                screenTimeViewController = STWebpageController()
                if let tab = tabManager.selectedTab {
                    recordScreenTimeUsage(for: tab)
                }
            } else {
                screenTimeViewController?.view.removeFromSuperview()
                screenTimeViewController?.willMove(toParent: nil)
                screenTimeViewController?.removeFromParent()
                screenTimeViewController?.suppressUsageRecording = true
                screenTimeViewController = nil
            }
        default:
            // 未知偏好设置发生改变
            Logger.module.debug("Received a preference change for an unknown key: \(key, privacy: .public) on \(type(of: self), privacy: .public)")
            break
        }
    }
}


extension BrowserViewController {
  public func openReferralLink(url: URL) {
    executeAfterSetup { [self] in
      openURLInNewTab(url, isPrivileged: false)
    }
  }

  public func handleNavigationPath(path: NavigationPath) {
    // Remove Default Browser Callout - Do not show scheduled notification
    // in case an external url is triggered
    if case .url(let navigatedURL, _) = path {
      if navigatedURL?.isWebPage(includeDataURIs: false) == true {
        Preferences.General.defaultBrowserCalloutDismissed.value = true
        Preferences.DefaultBrowserIntro.defaultBrowserNotificationScheduled.value = true
        
        // Remove pending notification if default browser is set brave
        // Recognized by external link is open
        if !Preferences.DefaultBrowserIntro.defaultBrowserNotificationIsCanceled.value {
          cancelScheduleDefaultBrowserNotification()
        }
      }
    }
    
    executeAfterSetup {
      NavigationPath.handle(nav: path, with: self)
    }
  }
}
extension BrowserViewController {
    // 在正常浏览模式下显示“Tab Received”提示
    func presentTabReceivedToast(url: URL) {
        // 仅在非隐私浏览模式下显示“Tab Received”指示器
        if !privateBrowsingManager.isPrivateBrowsing {
            let toast = ButtonToast(
                labelText: Strings.Callout.tabReceivedCalloutTitle,
                image: UIImage(braveSystemNamed: "leo.smartphone.tablet-portrait"),
                buttonText: Strings.goButtonTittle,
                completion: { [weak self] buttonPressed in
                    guard let self = self else { return }

                    if buttonPressed {
                        // 添加并选择新标签页
                        self.tabManager.addTabAndSelect(URLRequest(url: url), isPrivate: false)
                    }
                })

            show(toast: toast, duration: ButtonToastUX.toastDismissAfter)
        }
    }
}

extension BrowserViewController: UNUserNotificationCenterDelegate {
    // 处理用户通知中心的响应
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // 处理默认浏览器通知
        if response.notification.request.identifier == Self.defaultBrowserNotificationId {
            guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
                Logger.module.error("Failed to unwrap iOS settings URL")
                return
            }
            UIApplication.shared.open(settingsUrl)
        } else if response.notification.request.identifier == PrivacyReportsManager.notificationID {
            // 打开隐私报告
            openPrivacyReport()
        }
        completionHandler()
    }
}

// MARK: UIScreenshotServiceDelegate

extension BrowserViewController: UIScreenshotServiceDelegate {

    // 生成 PDF 表示的异步截图服务委托方法
    @MainActor
    public func screenshotServiceGeneratePDFRepresentation(_ screenshotService: UIScreenshotService) async -> (Data?, Int, CGRect) {
        await withCheckedContinuation { continuation in
            guard screenshotService.windowScene != nil,
                  presentedViewController == nil,
                  let webView = tabManager.selectedTab?.webView,
                  let url = webView.url,
                  url.isWebPage()
            else {
                continuation.resume(returning: (nil, 0, .zero))
                return
            }

            var rect = webView.scrollView.frame
            rect.origin.x = webView.scrollView.contentOffset.x
            rect.origin.y = webView.scrollView.contentSize.height - rect.height - webView.scrollView.contentOffset.y

            webView.createPDF { result in
                switch result {
                case .success(let data):
                    continuation.resume(returning: (data, 0, rect))
                case .failure:
                    continuation.resume(returning: (nil, 0, .zero))
                }
            }
        }
    }
}

// 隐私报告
extension BrowserViewController {
    // 打开隐私报告
    public func openPrivacyReport() {
        // 如果在隐私浏览模式下，直接返回
        if privateBrowsingManager.isPrivateBrowsing {
            return
        }

        let host = UIHostingController(rootView: PrivacyReportsManager.prepareView(isPrivateBrowsing: privateBrowsingManager.isPrivateBrowsing))

        host.rootView.openPrivacyReportsUrl = { [weak self] in
            guard let self = self else { return }
            // 添加新标签页以打开隐私报告
            let tab = self.tabManager.addTab(
                PrivilegedRequest(url: .brave.privacyFeatures) as URLRequest,
                afterTab: self.tabManager.selectedTab,
                // 隐私报告视图在私密模式下不可用
                isPrivate: false)
            self.tabManager.selectTab(tab)
        }

        self.present(host, animated: true)
    }
}


//extension BrowserViewController: IAPObserverDelegate {
//  public func purchasedOrRestoredProduct(validateReceipt: Bool) {
//    // No-op
//  }
//  
//  public func purchaseFailed(error: IAPObserver.PurchaseError) {
//    // No-op
//  }
//  
//  public func handlePromotedInAppPurchase() {
//    // Open VPN Buy Screen before system triggers buy action
//    // Delaying the VPN Screen launch delibrately to syncronize promoted purchase launch
//    Task.delayed(bySeconds: 2.0) { @MainActor in
//      self.popToBVC()
//      self.navigationHelper.openVPNBuyScreen(iapObserver: self.iapObserver)
//    }
//  }
//}

// Certificate info
// 在 BrowserViewController 的扩展中定义了一个名为 displayPageCertificateInfo 的方法
extension BrowserViewController {
  
  // 显示页面证书信息的方法
  func displayPageCertificateInfo() {
    // 获取当前选定标签页的 WebView
    guard let webView = tabManager.selectedTab?.webView else {
      Logger.module.error("无效的 WebView")
      return
    }
    
    // 从错误页面获取服务器信任（Server Trust）的闭包
    let getServerTrustForErrorPage = { () -> SecTrust? in
      do {
        if let url = webView.url {
          return try ErrorPageHelper.serverTrust(from: url)
        }
      } catch {
        Logger.module.error("\(error.localizedDescription)")
      }
      
      return nil
    }
    
    // 如果 WebView 中存在 Server Trust，则使用它；否则，尝试从错误页面获取
    guard let trust = webView.serverTrust ?? getServerTrustForErrorPage() else {
      return
    }
    
    // 获取 WebView 的主机
    let host = webView.url?.host
    
    // 使用 Task.detached 异步处理证书信息
    Task.detached {
      // 获取服务器证书链
      let serverCertificates: [SecCertificate] = SecTrustCopyCertificateChain(trust) as? [SecCertificate] ?? []
      
      // TODO: 替代只显示链中的第一个证书，设计一个用户界面，允许用户选择链中的任何证书（类似于桌面浏览器）
      if let serverCertificate = serverCertificates.first,
         let certificate = BraveCertificateModel(certificate: serverCertificate) {
        
        var errorDescription: String?
        
        do {
          // 尝试使用 BraveCertificateUtils.evaluateTrust 评估信任，并为主机执行异步操作
          try await BraveCertificateUtils.evaluateTrust(trust, for: host)
        } catch {
          Logger.module.error("\(error.localizedDescription)")
          
          // 移除错误消息的首部，这是因为证书查看器已经显示了它
          // 如果不匹配，则不会被移除，所以这是可以接受的
          errorDescription = error.localizedDescription
          if let range = errorDescription?.range(of: "“\(certificate.subjectName.commonName)” ") ??
              errorDescription?.range(of: "\"\(certificate.subjectName.commonName)\" ") {
            errorDescription = errorDescription?.replacingCharacters(in: range, with: "").capitalizeFirstLetter
          }
        }
        
        // 在主线程中显示证书视图控制器
        await MainActor.run { [errorDescription] in
          if #available(iOS 16.0, *) {
            // 如果可用，系统组件位于最上层，因此我们要将其关闭
            webView.findInteraction?.dismissFindNavigator()
          }
          let certificateViewController = CertificateViewController(certificate: certificate, evaluationError: errorDescription)
          certificateViewController.modalPresentationStyle = .pageSheet
          certificateViewController.sheetPresentationController?.detents = [.medium(), .large()]
          self.present(certificateViewController, animated: true)
        }
      }
    }
  }
    
    
}

extension BrowserViewController{
    public func addScript(name: String, desc: String, script: String, version: String, cid: Int64, origin_url: String) {
       /// favorites[0].name
        Userscript.add(name: name, desc: desc, script: script, version: version, cid: cid, origin_url: origin_url)
        
        
        
        let enableScripts = Userscript.getEnable()

        // 遍历数组，拼接 script 字段
        var combinedScript = script+"\n"
        for userscript in enableScripts {
            if let script = userscript.script {
                combinedScript.append("try{")
                combinedScript.append(script)
                combinedScript.append("}catch(e){}\n") // 每次拼接都在末尾添加换行符
            }
        }
        
        if let tab = tabManager.selectedTab{
            let handler = CustomUserScriptsHandler(browserController: self, tab: tab, javascript: combinedScript)
            tabManager.selectedTab?.removeContentScript(name: CustomUserScriptsHandler.scriptName, forTab: tab, contentWorld: type(of: handler).scriptSandbox)
            

            if let web = tab.webView {

                let script = WKUserScript(source: "(function(){let t_ycsdilhvuev = \(Date().timeIntervalSince1970);window.rainsee_miantask_jcveu = t_ycsdilhvuev;setTimeout(()=>{if(t_ycsdilhvuev>=window.rainsee_miantask_jcveu){console.log('x444444xxxxxxx');"+combinedScript+";}},1)})();",
                                          injectionTime: .atDocumentStart,
                                          forMainFrameOnly: false)
               // web.configuration.userContentController.removeAllUserScripts()
                CustomUserScriptsHandler.userScript = script
                
                UserScriptManager.shared.fresh()
                web.configuration.userContentController.addUserScript(script)

            }
         
        }
        
    }
    public func deleteJs(_ uuid: String) {
        let userscript = Userscript.remove(uuid)
        
        
        let enableScripts = Userscript.getEnable()

        // 遍历数组，拼接 script 字段
        var combinedScript = ""
        for userscript in enableScripts {
            if let item_uuid = userscript.uuid {
                if(item_uuid != uuid){
                    if let script = userscript.script {
                        combinedScript.append("try{")
                        combinedScript.append(script)
                        combinedScript.append("}catch(e){}\n") // 每次拼接都在末尾添加换行符
                    }
                }
            }
        }
        
        if let tab = tabManager.selectedTab{
            let handler = CustomUserScriptsHandler(browserController: self, tab: tab, javascript: combinedScript)
            tabManager.selectedTab?.removeContentScript(name: CustomUserScriptsHandler.scriptName, forTab: tab, contentWorld: type(of: handler).scriptSandbox)
            

            if let web = tab.webView {

                let script = WKUserScript(source: "(function(){let t_ycsdilhvuev = \(Date().timeIntervalSince1970);window.rainsee_miantask_jcveu = t_ycsdilhvuev;setTimeout(()=>{if(t_ycsdilhvuev>=window.rainsee_miantask_jcveu){console.log('x444444xxxxxxx');"+combinedScript+";}},1)})();",
                                          injectionTime: .atDocumentStart,
                                          forMainFrameOnly: false)
               // web.configuration.userContentController.removeAllUserScripts()
                CustomUserScriptsHandler.userScript = script
                
                UserScriptManager.shared.fresh()
                web.configuration.userContentController.addUserScript(script)

            }
         
        }
    }
    
    public func updateScript(_ message: [String: Any]) {
        if let uuid = message["uuid"] as? String,
                let userscript = Userscript.findByUUID(uuid) {
                userscript.update(with: message)
            
            
            let enableScripts = Userscript.getAll()

            // 遍历数组，拼接 script 字段
            var combinedScript = ""
            for userscript in enableScripts {
                if let item_uuid = userscript.uuid {
                    if(item_uuid == uuid){
                        if let enable = message["enable"] as? Bool {
                            if enable {
                                combinedScript.append("try{")
                                if let script = message["script"] as? String {
                                    combinedScript.append(script)
                                } else {
                                    combinedScript.append(userscript.script!)
                                }
                                combinedScript.append("}catch(e){}\n") // 每次拼接都在末尾添加换行符
                            }
                        } else {
                            if userscript.enable {
                                combinedScript.append("try{")
                                if let script = message["script"] as? String {
                                    combinedScript.append(script)
                                } else {
                                    combinedScript.append(userscript.script!)
                                }
                                combinedScript.append("}catch(e){}\n") // 每次拼接都在末尾添加换行符
                            }
                          
                        }
                    } else {
                        if userscript.enable {
                            if let script = userscript.script {
                                combinedScript.append("try{")
                                combinedScript.append(script)
                                combinedScript.append("}catch(e){}\n") // 每次拼接都在末尾添加换行符
                            }
                        }
                       
                    }
                }
            }
            
            if let tab = tabManager.selectedTab{
                let handler = CustomUserScriptsHandler(browserController: self, tab: tab, javascript: combinedScript)
                tabManager.selectedTab?.removeContentScript(name: CustomUserScriptsHandler.scriptName, forTab: tab, contentWorld: type(of: handler).scriptSandbox)
                

                if let web = tab.webView {

                    let script = WKUserScript(source: "(function(){let t_ycsdilhvuev = \(Date().timeIntervalSince1970);window.rainsee_miantask_jcveu = t_ycsdilhvuev;setTimeout(()=>{if(t_ycsdilhvuev>=window.rainsee_miantask_jcveu){console.log('x444444xxxxxxx');"+combinedScript+";}},1)})();",
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false)
                   // web.configuration.userContentController.removeAllUserScripts()
                    CustomUserScriptsHandler.userScript = script
                    
                    UserScriptManager.shared.fresh()
                    web.configuration.userContentController.addUserScript(script)

                }
             
            }
        }
    }
    
    public func showJsManege() {
        let scripts = Userscript.getAll()
        var urlString = URL.brave.user_javascript_manage // 替换为你的URL
    
        do {
            // 使用 JSONEncoder 将对象数组编码为 Data
            let jsonData = try JSONEncoder().encode(scripts)

            // 将 Data 转换为 JSON 字符串
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("JSON String: \(jsonString)")
                
                // 创建菜单控制器
                let menuController = CustomWebViewController(urlString.absoluteString, self)
                    
                // 弹出PanModal菜单
                self.presentPanModal(menuController)
                    
                // 如果菜单控制器的模态呈现样式是弹出窗口
                if menuController.modalPresentationStyle == .popover {
                    // 配置弹出窗口的外边距和允许的箭头方向
                    menuController.popoverPresentationController?.popoverLayoutMargins = .init(equalInset: 4)
                    menuController.popoverPresentationController?.permittedArrowDirections = [.up, .down]
                }
                
                if let data = jsonString.data(using: .utf8) {
                    // 使用 Data 的 base64EncodedString() 方法将其转换为 Base64 编码的字符串
                    let base64String = data.base64EncodedString()
                    menuController.addScriptAtEnd("window.injectList('\(base64String)')")
                 
                } else {
                    print("Error converting string to data.")
                }
               
              
            } else {
                print("Failed to convert Data to JSON String.")
            }
        } catch {
            print("Error encoding objectsArray to JSON: \(error)")
        }

    }
}

extension BrowserViewController {
    public func download(cookie: String) {
      
    }
    fileprivate func uploadLocalToNet() {
       
    }
    func sendRequestWithLocalFile(json: String) {
      
    }
    func decodeBase64AndParseJSON(base64EncodedString: String) {
        // 将Base64编码的字符串转换为Data
        guard let base64Data = Data(base64Encoded: base64EncodedString) else {
            print("无法解码Base64字符串")
            return
        }

        // 将Data转换为UTF-8字符串
        guard let decodedString = String(data: base64Data, encoding: .utf8) else {
            print("无法将Data转换为UTF-8字符串")
            return
        }

        // 打印解码后的字符串
        print("解码后的字符串：\(decodedString)")

        // 将解码后的字符串转换为Data
        guard let jsonData = decodedString.data(using: .utf8) else {
            print("无法将字符串转换为UTF-8数据")
            return
        }
        do {
            let jsonObjects = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]]
            // 创建一个数组来存储解析后的Person对象
            downloadBookmark(jsonObjects)

//            PasswordForm()
//            passwordAPI.addLogin(PasswordForm)
//
//            let localMobileNode = bookmarkManager.mobileNode()
//
//
//            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//                self.uploadLocalToNet(originMd5: originMd5)
//            }

        } catch {}

//        do {
//            let people = try JSONDecoder().decode([NewBookmarkBean].self, from: jsonData)
//                    for person in people {
//                        print("解码后的 Person 对象：\(person)")
//                    }
//         } catch {
//             print("JSON 解码失败: \(error.localizedDescription)")
//         }
        // 使用JSONSerialization将JSON数据解析为Swift对象
//        do {
//            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
//            print("成功解析JSON: \(jsonObject)")
//
//
//            self.startImport(jsonObject)
//        } catch {
//            print("JSON解析错误: \(error.localizedDescription)")
//        }
    }
    
    fileprivate func downloadBookmark(_ jsonObjects: [[String: Any]]?) {
        DispatchQueue.main.async {
            let exactSameFavorites = Favorite.allFavorites
                for jsonObject in jsonObjects! {
                    guard
                        var title = jsonObject["title"] as? String,
                        let url = jsonObject["url"] as? String
                    else {
                        continue // Skip to the next iteration if parsing fails
                    }

                    if title == "" {
                        continue
                    }
                    if url == "" {
                        continue
                    }
                
                    let urlUrl = URL(string: url)
//                    if Favorite.contains(url: urlUrl!) {
//                        continue
//                    }
//                    
                    if exactSameFavorites.contains(where: {  $0.url == url }) {
                        // Entry already exists, skip adding it
                        continue
                    }
                    Favorite.add(url: urlUrl!, title: title)
                }
            

        }


            let currentDate = Date()
            let timestamp = currentDate.timeIntervalSince1970
            Preferences.SyncRain.syncHomeTime.value = Int(timestamp)

            // 执行上传
            self.uploadLocalToNet()
        
    }
}

