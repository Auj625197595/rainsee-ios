/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Storage
import Shared
import BraveCore
import Preferences
import SwiftyJSON
import Data
import os.log
import BraveWallet
import Favicon
import UserAgent

protocol TabContentScriptLoader {
  static func loadUserScript(named: String) -> String?
  static func secureScript(handlerName: String, securityToken: String, script: String) -> String
  static func secureScript(handlerNamesMap: [String: String], securityToken: String, script: String) -> String
}

protocol TabContentScript: TabContentScriptLoader {
  static var scriptName: String { get }
  static var scriptId: String { get }
  static var messageHandlerName: String { get }
  static var scriptSandbox: WKContentWorld { get }
  static var userScript: WKUserScript? { get }
  
  func verifyMessage(message: WKScriptMessage) -> Bool
  func verifyMessage(message: WKScriptMessage, securityToken: String) -> Bool
  
  func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void)
}

protocol TabDelegate {
  func tab(_ tab: Tab, didAddSnackbar bar: SnackBar)
  func tab(_ tab: Tab, didRemoveSnackbar bar: SnackBar)
  /// Triggered when "Find in Page" is selected on selected web text
  func tab(_ tab: Tab, didSelectFindInPageFor selectedText: String)
  /// Triggered when "Search with Brave" is selected on selected web text
  func tab(_ tab: Tab, didSelectSearchWithBraveFor selectedText: String)
  func tab(_ tab: Tab, didCreateWebView webView: WKWebView)
  func tab(_ tab: Tab, willDeleteWebView webView: WKWebView)
  func showRequestRewardsPanel(_ tab: Tab)
  func stopMediaPlayback(_ tab: Tab)
  func showWalletNotification(_ tab: Tab, origin: URLOrigin)
  func updateURLBarWalletButton()
  func isTabVisible(_ tab: Tab) -> Bool
  func reloadIPFSSchemeUrl(_ url: URL)
  func didReloadTab(_ tab: Tab)
}

@objc
protocol URLChangeDelegate {
  func tab(_ tab: Tab, urlDidChangeTo url: URL)
}

enum TabSecureContentState {
  case unknown
  case localhost
  case secure
  case invalidCert
  case missingSSL
  case mixedContent
  
  var shouldDisplayWarning: Bool {
    switch self {
    case .unknown, .invalidCert, .missingSSL, .mixedContent:
      return true
    case .localhost, .secure:
      return false
    }
  }
}

class Tab: NSObject {
  let id: UUID
  let rewardsId: UInt32

  var onScreenshotUpdated: (() -> Void)?
    
  var onScreenshotTopColorUpdated: (() -> Void)?

    
  var rewardsEnabledCallback: ((Bool) -> Void)?

  var alertShownCount: Int = 0
  var blockAllAlerts: Bool = false
  
  private(set) var type: TabType = .regular
  
  var redirectURLs = [URL]()

  var isPrivate: Bool {
    return type.isPrivate
  }

  var secureContentState: TabSecureContentState = .unknown
  var sslPinningError: Error?

  private let _syncTab: BraveSyncTab?
  private let _faviconDriver: FaviconDriver?
//  private var _walletEthProvider: BraveWalletEthereumProvider?
//  private var _walletSolProvider: BraveWalletSolanaProvider?
//  private var _walletKeyringService: BraveWalletKeyringService? {
//    didSet {
//      _walletKeyringService?.add(self)
//    }
//  }
  
  private weak var syncTab: BraveSyncTab? {
    _syncTab
  }
  
  weak var faviconDriver: FaviconDriver? {
    _faviconDriver
  }
  
//  weak var walletEthProvider: BraveWalletEthereumProvider? {
//    get { _walletEthProvider }
//    set { _walletEthProvider = newValue }
//  }
//  
//  weak var walletSolProvider: BraveWalletSolanaProvider? {
//    get { _walletSolProvider }
//    set { _walletSolProvider = newValue }
//  }
//  
//  weak var walletKeyringService: BraveWalletKeyringService? {
//    get { _walletKeyringService }
//    set { _walletKeyringService = newValue }
//  }
  
//  var tabDappStore: TabDappStore = .init()
  var isWalletIconVisible: Bool = false {
    didSet {
      tabDelegate?.updateURLBarWalletButton()
    }
  }
  
  // PageMetadata is derived from the page content itself, and as such lags behind the
  // rest of the tab.
  var pageMetadata: PageMetadata?

  var canonicalURL: URL? {
    if let string = pageMetadata?.siteURL,
      let siteURL = URL(string: string) {
      return siteURL
    }
    return self.url
  }

  /// The URL that should be shared when requested by the user via the share sheet
  ///
  /// If the canonical URL of the page points to a different base domain entirely, this will result in
  /// sharing the canonical URL. This is to ensure pages such as Google's AMP share the correct URL while
  /// also ensuring single page applications which don't update their canonical URLs on navigation share
  /// the current pages URL
  var shareURL: URL? {
    guard let url = url else { return nil }
    if let canonicalURL = canonicalURL, canonicalURL.baseDomain != url.baseDomain {
      return canonicalURL
    }
    return url
  }

  var userActivity: NSUserActivity?

  var webView: BraveWebView?
  var tabDelegate: TabDelegate?
  weak var urlDidChangeDelegate: URLChangeDelegate?  // TODO: generalize this.
  var bars = [SnackBar]()
  var favicon: Favicon
  var lastExecutedTime: Timestamp?
  var sessionData: (title: String, interactionState: Data)?
  fileprivate var lastRequest: URLRequest?
  var restoring: Bool = false
  var pendingScreenshot = false
  
  /// This object holds on to information regarding the current web page
  ///
  /// The page data is cleared when the user leaves the page (i.e. when the main frame url changes)
  var currentPageData: PageData?
  
  /// The url set after a successful navigation. This will also set the `url` property.
  ///
  /// - Note: Unlike the `url` property, which may be set during pre-navigation,
  /// the `committedURL` is only assigned when navigation was committed..
  var committedURL: URL? {
    willSet {
      url = newValue
      previousComittedURL = committedURL
      
      // Clear the current request url and the redirect source url
      // We don't need these values after the request has been comitted
      currentRequestURL = nil
      redirectSourceURL = nil
      isInternalRedirect = false
    }
  }
  
  /// This is the url for the current request
  var currentRequestURL: URL? {
    willSet {
      // Lets push the value as a redirect value
      redirectSourceURL = currentRequestURL
    }
  }
  
  /// This tells us if we internally redirected while navigating (i.e. debounce or query stripping)
  var isInternalRedirect: Bool = false
  
  // If the current reqest wasn't comitted and a new one was set
  // we were redirected and therefore this is set
  var redirectSourceURL: URL?
  
  /// The previous url that was set before `comittedURL` was set again
  private(set) var previousComittedURL: URL?
  
  var url: URL? {
    didSet {
      if let _url = url, let internalUrl = InternalURL(_url), internalUrl.isAuthorized {
        url = URL(string: internalUrl.stripAuthorization)
      }
      
      // Setting URL in SyncTab is adding pending item to navigation manager on brave-core side
      if let url = url, !isPrivate, !url.isLocal, !InternalURL.isValid(url: url), !url.isReaderModeURL {
        syncTab?.setURL(url)
      }
    }
  }

  var mimeType: String?
  var isEditing: Bool = false
  var shouldClassifyLoadsForAds = true
  var playlistItem: PlaylistInfo?
  var playlistItemState: PlaylistItemAddedState = .none

  /// The tabs new tab page controller.
  ///
  /// Should be setup in BVC then assigned here for future use.
  var newTabPageViewController: NewTabPageViewController? {
    willSet {
      if newValue == nil {
        deleteNewTabPageController()
      }
    }
  }

  private func deleteNewTabPageController() {
    guard let controller = newTabPageViewController, controller.parent != nil else { return }
    controller.willMove(toParent: nil)
    controller.removeFromParent()
    controller.view.removeFromSuperview()
  }

  /// When viewing a non-HTML content type in the webview (like a PDF document), this URL will
  /// point to a tempfile containing the content so it can be shared to external applications.
  var temporaryDocument: TemporaryDocument?

  // There is no 'available macro' on props, we currently just need to store ownership.
  lazy var contentBlocker = ContentBlockerHelper(tab: self)
  lazy var requestBlockingContentHelper = RequestBlockingContentScriptHandler(tab: self)

  /// The last title shown by this tab. Used by the tab tray to show titles for zombie tabs.
  var lastTitle: String?

  var isDesktopSite: Bool {
    webView?.customUserAgent?.lowercased().contains("mobile") == false
  }
  
  var containsWebPage: Bool {
    if let url = url {
      let isHomeURL = InternalURL(url)?.isAboutHomeURL
      return url.isWebPage() && isHomeURL != true
    }
    
    return false
  }

  /// In-memory dictionary of websites that were explicitly set to use either desktop or mobile user agent.
  /// Key is url's base domain, value is desktop mode on or off.
  /// Each tab has separate list of website overrides.
  private var userAgentOverrides: [String: Bool] = [:]

  var readerModeAvailableOrActive: Bool {
    if let readerMode = self.getContentScript(name: ReaderModeScriptHandler.scriptName) as? ReaderModeScriptHandler {
      return readerMode.state != .unavailable
    }
    return false
  }

  fileprivate(set) var screenshot: UIImage?
    
  fileprivate(set) var screenshotTopColor: UIColor?

  
  var webStateDebounceTimer: Timer?
  var onPageReadyStateChanged: ((ReadyState.State) -> Void)?

  // If this tab has been opened from another, its parent will point to the tab from which it was opened
  weak var parent: Tab?

  fileprivate var contentScriptManager = TabContentScriptManager()
  private var userScripts = Set<UserScriptManager.ScriptType>()
  private var customUserScripts = Set<UserScriptType>()

  fileprivate var configuration: WKWebViewConfiguration?

  /// Any time a tab tries to make requests to display a Javascript Alert and we are not the active
  /// tab instance, queue it for later until we become foregrounded.
  fileprivate var alertQueue = [JSAlertInfo]()

  var nightMode: Bool {
    didSet {
      var isNightModeEnabled = false
      
      if let fetchedTabURL = fetchedURL, !fetchedTabURL.isNightModeBlockedURL, nightMode {
        isNightModeEnabled = true
      }
      
      if let webView = webView {
        NightModeScriptHandler.executeScript(for: webView, isNightModeEnabled: isNightModeEnabled)
      }
      
      self.setScript(script: .nightMode, enabled: isNightModeEnabled)
    }
  }
  
  /// Boolean tracking custom url-scheme alert presented
  var isExternalAppAlertPresented = false
  var externalAppAlertCounter = 0
  var isExternalAppAlertSuppressed = false
  var externalAppURLDomain: String?
  
  func resetExternalAlertProperties() {
    externalAppAlertCounter = 0
    isExternalAppAlertPresented = false
    isExternalAppAlertSuppressed = false
    externalAppURLDomain = nil
  }

  init(configuration: WKWebViewConfiguration, id: UUID = UUID(), type: TabType = .regular, tabGeneratorAPI: BraveTabGeneratorAPI? = nil) {
    self.configuration = configuration
    self.favicon = Favicon.default
    self.id = id
    rewardsId = UInt32.random(in: 1...UInt32.max)
    nightMode = Preferences.General.nightModeEnabled.value
    _syncTab = tabGeneratorAPI?.createBraveSyncTab(isOffTheRecord: type == .private)
    
    if let syncTab = _syncTab {
      _faviconDriver = FaviconDriver(webState: syncTab.webState).then {
        $0.setMaximumFaviconImageSize(CGSize(width: 1024, height: 1024))
      }
    } else {
      _faviconDriver = nil
    }

    super.init()
    self.type = type
  }

  weak var navigationDelegate: WKNavigationDelegate? {
    didSet {
      if let webView = webView {
        webView.navigationDelegate = navigationDelegate
      }
    }
  }

  /// A helper property that handles native to Brave Search communication.
  var braveSearchManager: BraveSearchManager?

  private lazy var refreshControl = UIRefreshControl().then {
    $0.addTarget(self, action: #selector(reload), for: .valueChanged)
  }

  func createWebview() {
    if webView == nil {
      assert(configuration != nil, "Create webview can only be called once")
      configuration!.userContentController = WKUserContentController()
      configuration!.preferences = WKPreferences()
      configuration!.preferences.javaScriptCanOpenWindowsAutomatically = false
      configuration!.preferences.isFraudulentWebsiteWarningEnabled = Preferences.Shields.googleSafeBrowsing.value
      configuration!.allowsInlineMediaPlayback = true
      // Enables Zoom in website by ignoring their javascript based viewport Scale limits.
      configuration!.ignoresViewportScaleLimits = true
      configuration!.upgradeKnownHostsToHTTPS = Preferences.Shields.httpsEverywhere.value
      configuration!.enablePageTopColorSampling()

      if configuration!.urlSchemeHandler(forURLScheme: InternalURL.scheme) == nil {
        configuration!.setURLSchemeHandler(InternalSchemeHandler(), forURLScheme: InternalURL.scheme)
      }
      let webView = TabWebView(frame: .zero, tab: self, configuration: configuration!, isPrivate: isPrivate)
      webView.delegate = self

      webView.accessibilityLabel = Strings.webContentAccessibilityLabel
      webView.allowsBackForwardNavigationGestures = true
      webView.allowsLinkPreview = true

      // Turning off masking allows the web content to flow outside of the scrollView's frame
      // which allows the content appear beneath the toolbars in the BrowserViewController
      webView.scrollView.layer.masksToBounds = false
      webView.navigationDelegate = navigationDelegate

      restore(webView, restorationData: self.sessionData)

      self.webView = webView
      self.webView?.addObserver(self, forKeyPath: KVOConstants.URL.keyPath, options: .new, context: nil)
      
        // 通知 tabDelegate，新的 WebView 已创建
        tabDelegate?.tab(self, didCreateWebView: webView)

        // 创建脚本偏好设置字典，其中包含各种脚本类型及其对应的布尔值
        let scriptPreferences: [UserScriptManager.ScriptType: Bool] = [
            .cookieBlocking: Preferences.Privacy.blockAllCookies.value,
            .mediaBackgroundPlay: Preferences.General.mediaAutoBackgrounding.value,
            .nightMode: Preferences.General.nightModeEnabled.value,
            .deAmp: Preferences.Shields.autoRedirectAMPPages.value,
            .playlistMediaSource: Preferences.Playlist.webMediaSourceCompatibility.value,
        ]

        // 根据脚本偏好设置过滤出需要注入的用户脚本，形成一个 Set
        userScripts = Set(scriptPreferences.filter({ $0.value }).map({ $0.key }))

        // 更新已注入的脚本
        self.updateInjectedScripts()

      nightMode = Preferences.General.nightModeEnabled.value
        
        
        
        
    }
  }

  func resetWebView(config: WKWebViewConfiguration) {
    configuration = config
    deleteWebView()
    contentScriptManager.helpers.removeAll()
  }

  func clearHistory(config: WKWebViewConfiguration) {
    guard let webView = webView else {
      return
    }

    /*
     * Clear selector is used on WKWebView backForwardList because backForwardList list is only exposed with a getter
     * and this method Removes all items except the current one in the tab list so when another url is added it will add the list properly
     * This approach is chosen to achieve removing tab history in the event of removing  browser history
     * Best way perform this is to clear the backforward list and in our case there is no drawback to clear the list
     * And alternative would be to reload webpages which will be costly and also can cause unexpected results
     */
    let argument: [Any] = ["_c", "lea", "r"]

    let method = argument.compactMap { $0 as? String }.joined()
    let selector: Selector = NSSelectorFromString(method)

    if webView.backForwardList.responds(to: selector) {
      webView.backForwardList.performSelector(onMainThread: selector, with: nil, waitUntilDone: true)
    }
    
    // Remove the tab history from saved tabs
    // To remove history from WebKit, we simply update the session data AFTER calling "clear" above
    SessionTab.update(tabId: id, interactionState: webView.sessionData ?? Data(), title: title, url: webView.url ?? TabManager.ntpInteralURL)
  }

  func restore(_ webView: WKWebView, restorationData: (title: String, interactionState: Data)?) {
    // Pulls restored session data from a previous SavedTab to load into the Tab. If it's nil, a session restore
    // has already been triggered via custom URL, so we use the last request to trigger it again; otherwise,
    // we extract the information needed to restore the tabs and create a NSURLRequest with the custom session restore URL
    // to trigger the session restore via custom handlers
    if let sessionInfo = restorationData {
      restoring = true
      lastTitle = sessionInfo.title
      webView.interactionState = sessionInfo.interactionState
      restoring = false
      self.sessionData = nil
    } else if let request = lastRequest {
      webView.load(request)
    } else {
      Logger.module.warning("creating webview with no lastRequest and no session data: \(self.url?.absoluteString ?? "nil")")
    }
  }
  
  func restore(_ webView: WKWebView, requestRestorationData: (title: String, request: URLRequest)?) {
    if let sessionInfo = requestRestorationData {
      restoring = true
      lastTitle = sessionInfo.title
      webView.load(sessionInfo.request)
      restoring = false
      self.sessionData = nil
    } else if let request = lastRequest {
      webView.load(request)
    } else {
      Logger.module.warning("creating webview with no lastRequest and no session data: \(self.url?.absoluteString ?? "nil")")
    }
  }

  func deleteWebView() {
    contentScriptManager.uninstall(from: self)

    if let webView = webView {
      webView.removeObserver(self, forKeyPath: KVOConstants.URL.keyPath)
      tabDelegate?.tab(self, willDeleteWebView: webView)
    }
    webView = nil
  }

  deinit {
    deleteWebView()
    deleteNewTabPageController()
    contentScriptManager.helpers.removeAll()
    
    // A number of mojo-powered core objects have to be deconstructed on the same
    // thread they were constructed
    var mojoObjects: [Any?] = [
      _faviconDriver,
      _syncTab,
//      _walletEthProvider,
//      _walletSolProvider,
//      _walletKeyringService
    ]
    
    DispatchQueue.main.async {
      // Reference inside to retain it, supress warnings by reading/writing
      _ = mojoObjects
      mojoObjects = []
    }
  }

  var loading: Bool {
    return webView?.isLoading ?? false
  }

  var estimatedProgress: Double {
    return webView?.estimatedProgress ?? 0
  }

  var backList: [WKBackForwardListItem]? {
    return webView?.backForwardList.backList
  }

  var forwardList: [WKBackForwardListItem]? {
    return webView?.backForwardList.forwardList
  }

  var historyList: [URL] {
    func listToUrl(_ item: WKBackForwardListItem) -> URL { return item.url }
    var tabs = self.backList?.map(listToUrl) ?? [URL]()
    tabs.append(self.url!)
    return tabs
  }

  var title: String {
    return webView?.title ?? ""
  }

  var displayTitle: String {
    if let displayTabTitle = fetchDisplayTitle(using: url, title: title) {
      syncTab?.setTitle(displayTabTitle)
      return displayTabTitle
    }

    // When picking a display title. Tabs with sessionData are pending a restore so show their old title.
    // To prevent flickering of the display title. If a tab is restoring make sure to use its lastTitle.
    if let url = self.url, InternalURL(url)?.isAboutHomeURL ?? false, sessionData == nil, !restoring {
      syncTab?.setTitle(Strings.Hotkey.newTabTitle)
      return Strings.Hotkey.newTabTitle
    }

    if let url = self.url, !InternalURL.isValid(url: url), let shownUrl = url.displayURL?.absoluteString, webView != nil {
      syncTab?.setTitle(shownUrl)
      return shownUrl
    }

    guard let lastTitle = lastTitle, !lastTitle.isEmpty else {
      // FF uses url?.displayURL?.absoluteString ??  ""
      if let title = url?.absoluteString {
        syncTab?.setTitle(title)
        return title
      } else if let tab = SessionTab.from(tabId: id) {
        if tab.title.isEmpty {
          return Strings.Hotkey.newTabTitle
        }
        syncTab?.setTitle(tab.title)
        return tab.title
      }
      
      syncTab?.setTitle("")
      return ""
    }

    syncTab?.setTitle(lastTitle)
    return lastTitle
  }

  var currentInitialURL: URL? {
    return self.webView?.backForwardList.currentItem?.initialURL
  }

  var displayFavicon: Favicon? {
    if let url = url, InternalURL(url)?.isAboutHomeURL == true {
      return Favicon(image: UIImage(sharedNamed: "brave.logo"),
                     isMonogramImage: false,
                     backgroundColor: .clear)
    }
    return favicon
  }

  var canGoBack: Bool {
    return webView?.canGoBack ?? false
  }

  var canGoForward: Bool {
    return webView?.canGoForward ?? false
  }
  
  /// This property is for fetching the actual URL for the Tab
  /// In private browsing the URL is in memory but this is not the case for normal mode
  /// For Normal  Mode Tab information is fetched using Tab ID from
  var fetchedURL: URL? {
    if isPrivate {
      if let url = url, url.isWebPage() {
        return url
      }
    } else {
      if let tabUrl = url, tabUrl.isWebPage() {
        return tabUrl
      } else if let fetchedTab = SessionTab.from(tabId: id), fetchedTab.url.isWebPage() {
        return url
      }
    }
    
    return nil
  }
  
  func fetchDisplayTitle(using url: URL?, title: String?) -> String? {
    if let tabTitle = title, !tabTitle.isEmpty {
      var displayTitle = tabTitle
      
      // Checking host is "localhost" || host == "127.0.0.1"
      // or hostless URL (iOS forwards hostless URLs (e.g., http://:6571) to localhost.)
      // DisplayURL will retrieve original URL even it is redirected to Error Page
      if let isLocal = url?.displayURL?.isLocal, isLocal {
        displayTitle = ""
      }

      syncTab?.setTitle(displayTitle)
      return displayTitle
    }
    
    return nil
  }

  func goBack() {
    _ = webView?.goBack()
  }

  func goForward() {
    _ = webView?.goForward()
  }

  func goToBackForwardListItem(_ item: WKBackForwardListItem) {
    _ = webView?.go(to: item)
  }

  @discardableResult func loadRequest(_ request: URLRequest) -> WKNavigation? {
    if let webView = webView {
      lastRequest = request
      sslPinningError = nil
      if let url = request.url {
        if url.isFileURL, request.isPrivileged {
          return webView.loadFileURL(url, allowingReadAccessTo: url)
        }

        // Donate Custom Intent Open Website
        if url.isSecureWebPage(), !isPrivate {
          ActivityShortcutManager.shared.donateCustomIntent(for: .openWebsite, with: url.absoluteString)
        }
      }

      return webView.load(request)
    }
    return nil
  }

  func stop() {
    webView?.stopLoading()
  }

  @objc func reload() {
    // Clear the user agent before further navigation.
    // Proper User Agent setting happens in BVC's WKNavigationDelegate.
    // This prevents a bug with back-forward list, going back or forward and reloading the tab
    // loaded wrong user agent.
    webView?.customUserAgent = nil

    defer {
      if let refreshControl = webView?.scrollView.refreshControl,
        refreshControl.isRefreshing {
        refreshControl.endRefreshing()
      }
    }
    
    tabDelegate?.didReloadTab(self)

    // If the current page is an error page, and the reload button is tapped, load the original URL
    if let url = webView?.url, let internalUrl = InternalURL(url), let page = internalUrl.originalURLFromErrorPage {
//      if page.isIPFSScheme {
//        tabDelegate?.reloadIPFSSchemeUrl(page)
//      } else {
        webView?.replaceLocation(with: page)
    //  }
      return
    }

    if let _ = webView?.reloadFromOrigin() {
      nightMode = Preferences.General.nightModeEnabled.value
      Logger.module.debug("reloaded zombified tab from origin")
      return
    }

    if let webView = self.webView {
      Logger.module.debug("restoring webView from scratch")
      restore(webView, restorationData: sessionData)
    }
  }

  func updateUserAgent(_ webView: WKWebView, newURL: URL) {
    guard let baseDomain = newURL.baseDomain else { return }
    
    let screenWidth = webView.currentScene?.screen.bounds.width ?? webView.bounds.size.width
    if webView.traitCollection.horizontalSizeClass == .compact && (webView.bounds.size.width < screenWidth / 2.0) {
      let desktopMode = userAgentOverrides[baseDomain] == true
      webView.customUserAgent = desktopMode ? UserAgent.desktop : UserAgent.mobile
      return
    }

    let desktopMode = userAgentOverrides[baseDomain] ?? UserAgent.shouldUseDesktopMode
    webView.customUserAgent = desktopMode ? UserAgent.desktop : UserAgent.mobile
  }

  func addContentScript(_ helper: TabContentScript, name: String, contentWorld: WKContentWorld) {
    contentScriptManager.addContentScript(helper, name: name, forTab: self, contentWorld: contentWorld)
  }
  
  func removeContentScript(name: String, forTab tab: Tab, contentWorld: WKContentWorld) {
    contentScriptManager.removeContentScript(name: name, forTab: tab, contentWorld: contentWorld)
  }
  
  func replaceContentScript(_ helper: TabContentScript, name: String, forTab tab: Tab) {
    contentScriptManager.replaceContentScript(helper, name: name, forTab: tab)
  }

  func getContentScript(name: String) -> TabContentScript? {
    return contentScriptManager.getContentScript(name)
  }

  func hideContent(_ animated: Bool = false) {
    webView?.isUserInteractionEnabled = false
    if animated {
      UIView.animate(
        withDuration: 0.25,
        animations: { () -> Void in
          self.webView?.alpha = 0.0
        })
    } else {
      webView?.alpha = 0.0
    }
  }

  func showContent(_ animated: Bool = false) {
    webView?.isUserInteractionEnabled = true
    if animated {
      UIView.animate(
        withDuration: 0.25,
        animations: { () -> Void in
          self.webView?.alpha = 1.0
        })
    } else {
      webView?.alpha = 1.0
    }
  }

  func addSnackbar(_ bar: SnackBar) {
    bars.append(bar)
    tabDelegate?.tab(self, didAddSnackbar: bar)
  }

  func removeSnackbar(_ bar: SnackBar) {
    if let index = bars.firstIndex(of: bar) {
      bars.remove(at: index)
      tabDelegate?.tab(self, didRemoveSnackbar: bar)
    }
  }

  func removeAllSnackbars() {
    // Enumerate backwards here because we'll remove items from the list as we go.
    bars.reversed().forEach { removeSnackbar($0) }
  }

  func expireSnackbars() {
    // Enumerate backwards here because we may remove items from the list as we go.
    bars.reversed().filter({ !$0.shouldPersist(self) }).forEach({ removeSnackbar($0) })
  }

  func setScreenshot(_ screenshot: UIImage?) {
    self.screenshot = screenshot
      if let image = screenshot{
          if let hexString = image[3, 3] {
                      print("中间点颜色：", hexString)
              setScreenshotTopColor(hexString)
           }
      }
    onScreenshotUpdated?()
  }

    func setScreenshotTopColor(_ color: UIColor?) {
      self.screenshotTopColor = color
        onScreenshotTopColorUpdated?()
    }
    
  /// Switches user agent Desktop -> Mobile or Mobile -> Desktop.
  func switchUserAgent() {
      // 如果 webView 不为 nil，获取其当前 URL 的基础域名
      if let urlString = webView?.url?.baseDomain {
          // 网站已经发生过一次更改，需要翻转 override.onScreenshotUpdated
          if let siteOverride = userAgentOverrides[urlString] {
              // 如果基础域名已经存在于字典中，则将其值翻转
              userAgentOverrides[urlString] = !siteOverride
          } else {
              // 首次切换，将基础域名添加到字典，并赋予翻转后的值
              userAgentOverrides[urlString] = !UserAgent.shouldUseDesktopMode
          }
      }


    reload()
  }

  func queueJavascriptAlertPrompt(_ alert: JSAlertInfo) {
    alertQueue.append(alert)
  }

  func dequeueJavascriptAlertPrompt() -> JSAlertInfo? {
    guard !alertQueue.isEmpty else {
      return nil
    }
    return alertQueue.removeFirst()
  }

  func cancelQueuedAlerts() {
    alertQueue.forEach { alert in
      alert.cancel()
    }
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    guard let webView = object as? BraveWebView, webView == self.webView,
      let path = keyPath, path == KVOConstants.URL.keyPath
    else {
      return assertionFailure("Unhandled KVO key: \(keyPath ?? "nil")")
    }
    guard let url = self.webView?.url else {
      return
    }

    updatePullToRefreshVisibility()

    self.urlDidChangeDelegate?.tab(self, urlDidChangeTo: url)
  }

  func updatePullToRefreshVisibility() {
    guard let url = webView?.url, let webView = webView else { return }
    webView.scrollView.refreshControl = url.isLocalUtility || !Preferences.General.enablePullToRefresh.value ? nil : refreshControl
  }

  func isDescendentOf(_ ancestor: Tab) -> Bool {
    return sequence(first: parent) { $0?.parent }.contains { $0 == ancestor }
  }

  func injectUserScriptWith(fileName: String, type: String = "js", injectionTime: WKUserScriptInjectionTime = .atDocumentEnd, mainFrameOnly: Bool = true, contentWorld: WKContentWorld) {
    guard let webView = self.webView else {
      return
    }
    if let path = Bundle.module.path(forResource: fileName, ofType: type),
      let source = try? String(contentsOfFile: path) {
      let userScript = WKUserScript(source: source, injectionTime: injectionTime, forMainFrameOnly: mainFrameOnly, in: contentWorld)
      webView.configuration.userContentController.addUserScript(userScript)
    }
  }

  func observeURLChanges(delegate: URLChangeDelegate) {
    self.urlDidChangeDelegate = delegate
  }

  func removeURLChangeObserver(delegate: URLChangeDelegate) {
    if let existing = self.urlDidChangeDelegate, existing === delegate {
      self.urlDidChangeDelegate = nil
    }
  }

  func stopMediaPlayback() {
    tabDelegate?.stopMediaPlayback(self)
  }
  
  func addTabInfoToSyncedSessions(url: URL, displayTitle: String) {
    syncTab?.setURL(url)
    syncTab?.setTitle(displayTitle)
  }
}

extension Tab: TabWebViewDelegate {
  /// Triggered when "Find in Page" is selected on selected text
  fileprivate func tabWebView(_ tabWebView: TabWebView, didSelectFindInPageFor selectedText: String) {
    tabDelegate?.tab(self, didSelectFindInPageFor: selectedText)
  }

  /// Triggered when "Search with Brave" is selected on selected text
  fileprivate func tabWebView(_ tabWebView: TabWebView, didSelectSearchWithBraveFor selectedText: String) {
    tabDelegate?.tab(self, didSelectSearchWithBraveFor: selectedText)
  }
}

private class TabContentScriptManager: NSObject, WKScriptMessageHandlerWithReply {
  fileprivate var helpers = [String: TabContentScript]()

  func uninstall(from tab: Tab) {
    helpers.forEach {
      let name = type(of: $0.value).messageHandlerName
      tab.webView?.configuration.userContentController.removeScriptMessageHandler(forName: name)
    }
  }

  @objc func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
    for helper in helpers.values {
      let scriptMessageHandlerName = type(of: helper).messageHandlerName
      if scriptMessageHandlerName == message.name {
        helper.userContentController(userContentController, didReceiveScriptMessage: message, replyHandler: replyHandler)
        return
      }
    }
  }

  func addContentScript(_ helper: TabContentScript, name: String, forTab tab: Tab, contentWorld: WKContentWorld) {
    if let _ = helpers[name] {
      assertionFailure("Duplicate helper added: \(name)")
    }

    helpers[name] = helper

    // If this helper handles script messages, then get the handler name and register it. The Tab
    // receives all messages and then dispatches them to the right TabHelper.
    let scriptMessageHandlerName = type(of: helper).messageHandlerName
    tab.webView?.configuration.userContentController.addScriptMessageHandler(self, contentWorld: contentWorld, name: scriptMessageHandlerName)
  }
  
  func removeContentScript(name: String, forTab tab: Tab, contentWorld: WKContentWorld) {
    if let helper = helpers[name] {
      let scriptMessageHandlerName = type(of: helper).messageHandlerName
      tab.webView?.configuration.userContentController.removeScriptMessageHandler(forName: scriptMessageHandlerName, contentWorld: contentWorld)
      helpers[name] = nil
    }
  }
  
  func replaceContentScript(_ helper: TabContentScript, name: String, forTab tab: Tab) {
    if helpers[name] != nil {
      helpers[name] = helper
    }
  }

  func getContentScript(_ name: String) -> TabContentScript? {
    return helpers[name]
  }
}

private protocol TabWebViewDelegate: AnyObject {
  /// Triggered when "Find in Page" is selected on selected text
  func tabWebView(_ tabWebView: TabWebView, didSelectFindInPageFor selectedText: String)
  /// Triggered when "Search with Brave" is selected on selected text
  func tabWebView(_ tabWebView: TabWebView, didSelectSearchWithBraveFor selectedText: String)
}

class TabWebView: BraveWebView, MenuHelperInterface {
  fileprivate weak var delegate: TabWebViewDelegate?
  private(set) weak var tab: Tab?
  
  init(frame: CGRect, tab: Tab, configuration: WKWebViewConfiguration = WKWebViewConfiguration(), isPrivate: Bool = true) {
    self.tab = tab
    super.init(frame: frame, configuration: configuration, isPrivate: isPrivate)
  }

  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if action == MenuHelper.selectorForcePaste {
      // If paste is allowed, show force paste as well
      return super.canPerformAction(#selector(paste(_:)), withSender: sender)
    }
    return super.canPerformAction(action, withSender: sender) || action == MenuHelper.selectorFindInPage
  }
  
  @objc func menuHelperForcePaste() {
    if let string = UIPasteboard.general.string {
      evaluateSafeJavaScript(
        functionName: "window.__firefox__.forcePaste",
        args: [string, UserScriptManager.securityToken],
        contentWorld: .defaultClient
      ) { _, _ in }
    }
  }

  @objc func menuHelperFindInPage() {
    getCurrentSelectedText { [weak self] selectedText in
      guard let self = self else { return }
      guard let selectedText = selectedText else {
        assertionFailure("Impossible to trigger this without selected text")
        return
      }

      self.delegate?.tabWebView(self, didSelectFindInPageFor: selectedText)
    }
  }

  @objc func menuHelperSearchWithBrave() {
    getCurrentSelectedText { [weak self] selectedText in
      guard let self = self else { return }
      guard let selectedText = selectedText else {
        assertionFailure("Impossible to trigger this without selected text")
        return
      }

      self.delegate?.tabWebView(self, didSelectSearchWithBraveFor: selectedText)
    }
  }

  // rdar://33283179 Apple bug where `serverTrust` is not defined as KVO when it should be
  override func value(forUndefinedKey key: String) -> Any? {
    if key == #keyPath(WKWebView.serverTrust) {
      return serverTrust
    }

    return super.value(forUndefinedKey: key)
  }

  private func getCurrentSelectedText(callback: @escaping (String?) -> Void) {
    evaluateSafeJavaScript(functionName: "getSelection().toString", contentWorld: .defaultClient) { result, _ in
      let selectedText = result as? String
      callback(selectedText)
    }
  }
}

//
// Temporary fix for Bug 1390871 - NSInvalidArgumentException: -[WKContentView menuHelperFindInPage]: unrecognized selector
//
// This class only exists to contain the swizzledMenuHelperFindInPage. This class is actually never
// instantiated. It only serves as a placeholder for the method. When the method is called, self is
// actually pointing to a WKContentView. Which is not public, but that is fine, we only need to know
// that it is a UIView subclass to access its superview.
//

public class TabWebViewMenuHelper: UIView {
  @objc public func swizzledMenuHelperFindInPage() {
    if let tabWebView = superview?.superview as? TabWebView {
      tabWebView.evaluateSafeJavaScript(functionName: "getSelection().toString", contentWorld: .defaultClient) { result, _ in
        let selectedText = result as? String ?? ""
        tabWebView.delegate?.tabWebView(tabWebView, didSelectFindInPageFor: selectedText)
      }
    }
  }
}

// MARK: - Brave Search

extension Tab {
  /// 调用 Brave Search 网站上的 API，并将回退结果传递给它。
  /// 重要提示：无论是否有回退结果或者根本不应该发生回退调用，都会调用此方法。
  /// 该网站期望 iOS 设备始终调用此方法（在其上阻塞）。

  func injectResults() {
    DispatchQueue.main.async {
      // 如果备用搜索结果发生在 Brave Search 加载之前
      // 我们传递数据的方法未定义。
      // swiftlint:disable:next safe_javascript
      self.webView?.evaluateJavaScript("window.onFetchedBackupResults === undefined") {
        result, error in

        if let error = error {
          Logger.module.error("onFetchedBackupResults 存在性检查错误: \(error.localizedDescription, privacy: .public)")
        }

        guard let methodUndefined = result as? Bool else {
          Logger.module.error("onFetchedBackupResults 存在性检查，未能解包布尔结果值")
          return
        }

        if methodUndefined {
          Logger.module.info("搜索备份结果准备就绪，但页面尚未加载")
          return
        }

        var queryResult = "null"

        if let url = self.webView?.url,
          BraveSearchManager.isValidURL(url),
          let result = self.braveSearchManager?.fallbackQueryResult {
          queryResult = result
        }

        self.webView?.evaluateSafeJavaScript(
          functionName: "window.onFetchedBackupResults",
          args: [queryResult],
          contentWorld: BraveSearchScriptHandler.scriptSandbox,
          escapeArgs: false)

        // 清理
        self.braveSearchManager = nil
      }
    }
  }
}


// MARK: - Brave SKU
extension Tab {
  func injectLocalStorageItem(key: String, value: String) {
    self.webView?.evaluateSafeJavaScript(functionName: "localStorage.setItem",
                                         args: [key, value],
                                         contentWorld: BraveSkusScriptHandler.scriptSandbox)
  }
}

// MARK: Script Injection
extension Tab {
  func setScript(script: UserScriptManager.ScriptType, enabled: Bool) {
    setScripts(scripts: [script: enabled])
  }
  
  func setScripts(scripts: Set<UserScriptManager.ScriptType>, enabled: Bool) {
    var scriptMap = [UserScriptManager.ScriptType: Bool]()
    scripts.forEach({ scriptMap[$0] = enabled })
    setScripts(scripts: scriptMap)
  }
  
    // 根据传入的脚本类型及其启用状态，更新用户脚本集合
    func setScripts(scripts: [UserScriptManager.ScriptType: Bool]) {
        var scriptsToAdd = Set<UserScriptManager.ScriptType>()   // 需要添加的脚本集合
        var scriptsToRemove = Set<UserScriptManager.ScriptType>()   // 需要移除的脚本集合
        
        // 遍历传入的脚本类型及其启用状态
        for (script, enabled) in scripts {
            let scriptExists = userScripts.contains(script)   // 检查当前用户脚本集合中是否包含该脚本类型
            
            // 如果脚本不存在但被启用，则将其添加到需要添加的脚本集合中
            if !scriptExists && enabled {
                scriptsToAdd.insert(script)
            } else if scriptExists && !enabled {
                // 如果脚本存在但被禁用，则将其添加到需要移除的脚本集合中
                scriptsToRemove.insert(script)
            }
        }
        
        // 如果需要添加的脚本集合和需要移除的脚本集合都为空，表示脚本已经处于期望的状态
        if scriptsToAdd.isEmpty && scriptsToRemove.isEmpty {
            // 脚本已经处于期望的状态，无需更新
            return
        }
        
        // 添加需要添加的脚本到用户脚本集合中
        userScripts.formUnion(scriptsToAdd)
        // 从用户脚本集合中移除需要移除的脚本
        userScripts.subtract(scriptsToRemove)
        
        // 更新已注入的脚本
        updateInjectedScripts()
    }

  
  func setCustomUserScript(scripts: Set<UserScriptType>) {
    if customUserScripts != scripts {
      customUserScripts = scripts
      updateInjectedScripts()
    }
  }
  
  private func updateInjectedScripts() {
    UserScriptManager.shared.loadCustomScripts(into: self,
                                               userScripts: userScripts,
                                               customScripts: customUserScripts)
  }
}
