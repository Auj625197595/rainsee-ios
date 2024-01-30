// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import BraveCore
import BraveUI
import BraveVPN
import BraveWallet
import Data
import Foundation
import os.log
import Preferences
import Shared
import SwiftUI


extension BrowserViewController {
    // 创建名为 featuresMenuSection 的函数，接受 MenuViewController 类型的参数 menuController，并返回一个 View
    func featuresMenuSection(_ menuController: MenuViewController) -> some View {
        // 使用 VStack 垂直布局，对齐方式为左对齐，间距为 5
        VStack(alignment: .leading, spacing: 5) {
            // RegionMenuButton 是处理区域选择的按钮
//            RegionMenuButton(
//                // 激活的 VPN 区域信息
//                vpnRegionInfo: BraveVPN.activatedRegion,
//                // 设置标题是否启用
//                settingTitleEnabled: false,
//                // 区域选择操作
//                regionSelectAction: {
//                    // 创建 BraveVPNRegionPickerViewController 实例
//                    let vc = BraveVPNRegionPickerViewController()
//                    // 通过将视图控制器推送到内部菜单，显示区域选择
//                    (self.presentedViewController as? MenuViewController)?.pushInnerMenu(vc)
//                }
//            )
        }
    }

    func privacyFeaturesMenuSection(_ menuController: MenuViewController) -> some View {
        // VStack是一个垂直方向的容器，用于包裹各个视图
        VStack(alignment: .leading, spacing: 5) {
            // 隐私功能菜单标题
            Text(Strings.OptionsMenu.menuSectionTitle.capitalized)
                .font(.callout.weight(.semibold))
                .foregroundColor(Color(.braveLabel))
                .padding(.horizontal, 14)
                .padding(.bottom, 5)

            // 区域按钮，用于选择 VPN 区域
//          RegionMenuButton(vpnRegionInfo: BraveVPN.activatedRegion, regionSelectAction: {
//            let vc = BraveVPNRegionPickerViewController()
//            (self.presentedViewController as? MenuViewController)?
//              .pushInnerMenu(vc)
//          })
          
            // 分割线
            Divider()
            
            // 播放列表按钮，用于显示 Brave Playlist
            MenuItemFactory.button(for: .playlist(subtitle: Strings.OptionsMenu.bravePlaylistItemDescription)) { [weak self] in
                guard let self = self else { return }
                self.presentPlaylistController()
            }

            // 仅在非隐私浏览模式下显示 Brave Talk 和 News 选项
//            if !privateBrowsingManager.isPrivateBrowsing {
//                // 如果是首次启动或 Brave News 已启用，则显示 Brave News 按钮
//                if Preferences.General.isFirstLaunch.value || (!Preferences.General.isFirstLaunch.value && Preferences.BraveNews.isEnabled.value) {
//                    MenuItemFactory.button(for: .news) { [weak self] in
//                        guard let self = self, let newTabPageController = self.tabManager.selectedTab?.newTabPageViewController else {
//                            return
//                        }
//
//                        self.popToBVC()
//                        newTabPageController.scrollToBraveNews()
//                    }
//                }
//
//
//            }
          
            // Brave Wallet 按钮
//          MenuItemFactory.button(for: .wallet(subtitle: Strings.OptionsMenu.braveWalletItemDescription)) { [unowned self] in
//            self.presentWallet()
//          }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 10)
        .padding(.bottom, 5)
    }

    fileprivate func goBookmark(_ menuController: MenuViewController) {
        let vc = BookmarksViewController(
            folder: self.bookmarkManager.lastVisitedFolder(),
            bookmarkManager: bookmarkManager,
            isPrivateBrowsing: privateBrowsingManager.isPrivateBrowsing)
        vc.toolbarUrlActionsDelegate = self
        menuController.presentInnerMenu(vc)
    }
    
    struct WebView: UIViewRepresentable {
        var url: URL
       
        func makeUIView(context: Context) -> WKWebView {
            WKWebView()
        }

        func updateUIView(_ uiView: WKWebView, context: Context) {
            let request = URLRequest(url: url)
            uiView.load(request)
        }
    }
    
    fileprivate func goUser(_ menu: MenuViewController) {
        
        var urlString = URL(string: "\(URL.brave.user_center_h5.absoluteString)?sync_book=\(Preferences.SyncRain.syncBook.value)&sync_home=\(Preferences.SyncRain.syncHome.value)&sync_pw=\(Preferences.SyncRain.syncPw.value)")! // 替换为你的URL
        if Preferences.User.mkey.value == ""{
            urlString = URL.brave.user_h5
        }
    
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
    }
    
    fileprivate func goAitxt(_ menu: MenuViewController) {
        let tab = self.tabManager.selectedTab
        DispatchQueue.main.async {
            // swiftlint:disable:next safe_javascript
            tab?.webView?.evaluateJavaScript("document.body.innerText") { result, error in
                if let error = error {
                    print("Error evaluating JavaScript: \(error)")
                }

                if let text = result as? String {
                    if let encodedTxt = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        print("All text content in WKWebView: \(encodedTxt)")
                    }
                    // print("All text content in WKWebView: \(text)")
                    // 设置菜单的初始高度，如果选定标签的URL不为nil，则为470，否则为500
                    let initialHeight: CGFloat = 470
                        
                    // 创建菜单控制器
                    let menuController = AiTxtController(text, tab?.webView?.url!.absoluteString ?? "")
                        
                    // 弹出PanModal菜单
                    self.presentPanModal(menuController)
                        
                    // 如果菜单控制器的模态呈现样式是弹出窗口
                    if menuController.modalPresentationStyle == .popover {
                        // 配置弹出窗口的外边距和允许的箭头方向
                        menuController.popoverPresentationController?.popoverLayoutMargins = .init(equalInset: 4)
                        menuController.popoverPresentationController?.permittedArrowDirections = [.up, .down]
                    }
                }
            }
        }
    }
    
    fileprivate func goHistory(_ menuController: MenuViewController) {
        let vc = HistoryViewController(
            isPrivateBrowsing: privateBrowsingManager.isPrivateBrowsing,
            historyAPI: self.braveCore.historyAPI,
            tabManager: self.tabManager)
        vc.toolbarUrlActionsDelegate = self
        menuController.pushInnerMenu(vc)
    }
    
    fileprivate func goSettle(_ menuController: MenuViewController) {
        // 获取是否处于私密浏览模式
        let isPrivateMode = privateBrowsingManager.isPrivateBrowsing
        
        // 创建钱包服务相关实例
        //                let keyringService = BraveWallet.KeyringServiceFactory.get(privateMode: isPrivateMode)
        //                let walletService = BraveWallet.ServiceFactory.get(privateMode: isPrivateMode)
        //                let rpcService = BraveWallet.JsonRpcServiceFactory.get(privateMode: isPrivateMode)
        
        //                // 初始化 KeyringStore 实例
        //                var keyringStore: KeyringStore? = walletStore?.keyringStore
        //                if keyringStore == nil {
        //                    if let keyringService = keyringService,
        //                       let walletService = walletService,
        //                       let rpcService = rpcService {
        //                        keyringStore = KeyringStore(
        //                            keyringService: keyringService,
        //                            walletService: walletService,
        //                            rpcService: rpcService
        //                        )
        //                    }
        //                }
        //
        //                // 初始化 CryptoStore 实例
        //                var cryptoStore: CryptoStore? = walletStore?.cryptoStore
        //                if cryptoStore == nil {
        //                    cryptoStore = CryptoStore.from(ipfsApi: braveCore.ipfsAPI, privateMode: isPrivateMode)
        //                }
        
        // 创建设置视图控制器实例
        let vc = SettingsViewController(
            profile: self.profile,
            tabManager: self.tabManager,
            feedDataSource: self.feedDataSource,
            rewards: self.rewards,
            windowProtection: self.windowProtection,
            braveCore: self.braveCore,
            attributionManager: attributionManager)
        vc.settingsDelegate = self
        menuController.pushInnerMenu(vc)
    }
    
    fileprivate func goShare() {
        self.dismiss(animated: true)
        self.tabToolbarDidPressShare()
    }
    
    fileprivate func printPdf() {
        dismiss(animated: true)
        let tab = tabManager.selectedTab
        if let webView = tab?.webView, tab?.temporaryDocument == nil {
            webView.createPDF { [weak self] result in
                dispatchPrecondition(condition: .onQueue(.main))
                guard let self = self else {
                    return
                }
                switch result {
                case .success(let pdfData):
                    // Create a valid filename
                    let validFilenameSet = CharacterSet(charactersIn: ":/")
                        .union(.newlines)
                        .union(.controlCharacters)
                        .union(.illegalCharacters)
                    let filename = webView.title?.components(separatedBy: validFilenameSet).joined()
                    let url = URL(fileURLWithPath: NSTemporaryDirectory())
                        .appendingPathComponent("\(filename ?? "Untitled").pdf")
                    do {
                        try pdfData.write(to: url)
                        let pdfActivityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        if let popoverPresentationController = pdfActivityController.popoverPresentationController {
                            popoverPresentationController.sourceView = view
                            popoverPresentationController.sourceRect = self.view.convert(self.topToolbar.menuButton.frame, from: self.topToolbar.menuButton.superview)
                            popoverPresentationController.permittedArrowDirections = .up
                            popoverPresentationController.delegate = self
                        }
                        self.present(pdfActivityController, animated: true)
                    } catch {
                        Logger.module.error("Failed to write PDF to disk: \(error.localizedDescription, privacy: .public)")
                    }
                  
                case .failure(let error):
                    Logger.module.error("Failed to create PDF with error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func destinationMenuSection(_ browserViewController: BrowserViewController, _ menuController: MenuViewController, isShownOnWebPage: Bool) -> some View {
        // 创建垂直方向的视图容器
        VStack(spacing: 0) {
            ResideHeader { [self] tappedId in
                // 处理点击事件
                print("Tab button with id \(tappedId) tapped")
                switch tappedId {
                case "share":
                    self.goShare()
                case "settle":
                    self.goSettle(menuController)
                case "user":
                    dismiss(animated: false)
                    self.goUser(menuController)
                default:
                    self.goHistory(menuController)
                }
            }
            
            ColorMenu { [self] tappedId in
                // 处理点击事件
                print("Tab button with id \(tappedId) tapped")
                switch tappedId {
                case 0:
                    dismiss(animated: false)
                    browserViewController.showJsManege()
                case 1:
                    self.goBookmark(menuController)
                case 2:
                    FileManager.default.openBraveDownloadsFolder { success in
                        if !success {
                            self.displayOpenDownloadsError()
                        }
                    }
                default:
                    self.goHistory(menuController)
                }
            }
            
            var playlistActivity: (enabled: Bool, item: PlaylistInfo?)? {
                browserViewController.addToPlayListActivityItem ?? browserViewController.openInPlaylistActivityItem
            }
            var isPlaylistItemAdded: Bool {
                browserViewController.openInPlaylistActivityItem != nil
            }
            
            if let activity = playlistActivity, activity.enabled, let item = activity.item {
                PlaylistMenuButton(isAdded: isPlaylistItemAdded) {
                    if !isPlaylistItemAdded {
                        // Add to playlist
                        browserViewController.addToPlaylist(item: item) { _ in
                            Logger.module.debug("Playlist Item Added")
                            browserViewController.dismiss(animated: true) {
                                browserViewController.openPlaylist(tab: browserViewController.tabManager.selectedTab, item: item)
                            }
                        }
                    } else {
                        browserViewController.dismiss(animated: true) {
                            browserViewController.openPlaylist(tab: browserViewController.tabManager.selectedTab, item: item)
                        }
                    }
                }
                .animation(.default, value: true)
                .background(Color("reside_bg", bundle: .module))
                .cornerRadius(10)
                .padding(.top, 15)
                .padding(.horizontal, 15)
            }

            ResideSimpleGridView(onTapButton: { [self] tappedId in
                // 处理点击事件
                print("Tab button with id \(tappedId) tapped")
                
                
               
                
//                if tappedId == 1 {
//
//                } else {
                dismiss(animated: true)
//                }
                if !isShownOnWebPage, tappedId != 5, tappedId != 15, tappedId != 18 {
                    browserViewController.showAlert(message: "请在网页中执行")
                }
                let tab = self.tabManager.selectedTab
                switch tappedId {
                case 0:
                    browserViewController.dismiss(animated: true) {
                        browserViewController.openAddBookmark()
                    }
                case 1:
                    self.goAitxt(menuController)
                case 2:
                    toggleReaderMode()
                case 3:
                    // swiftlint:disable:next safe_javascript
                    tab?.webView?.evaluateJavaScript("""
                    
                    (function() {
                        function inject() {
                            console.log(window.translateelemet);
                            if (window.translateelemet) {
                                return
                            }
                            window.translateelemet = true;
                            injectHeadWaitHead()
                        }

                        function injectHeadWaitHead() {
                            var head = document.querySelector('head');
                            if (head && document.body && (document.readyState === 'complete' || document.readyState === 'interactive')) {
                                var script = document.createElement('script');
                                script.src = '\(URL.Brave.translate)';
                                document.querySelector('head').appendChild(script);
                                var google_translate_element = document.createElement('div');
                                google_translate_element.id = 'google_translate_element';
                                google_translate_element.style = 'font-size: 16px;position:fixed; bottom:10px; right:10px; cursor:pointer;Z-INDEX: 99999;';
                                document.documentElement.appendChild(google_translate_element);
                                script = document.createElement('script');
                                script.innerHTML = "function googleTranslateElementInit() {new google.translate.TranslateElement({layout: google.translate.TranslateElement.InlineLayout.SIMPLE,multilanguagePage: true,pageLanguage: 'auto',includedLanguages: 'zh-CN,zh-TW,en,hr,cs,da,nl,fr,de,el,iw,hu,ga,it,ja,ko,pt,ro,ru,sr,es,th,vi,hmn,eo,my,mn,tl,ar,ms,no,la,lo'}, 'google_translate_element');}";
                                document.getElementsByTagName('head')[0].appendChild(script);
                                setTimeout(function() {
                                    if (document.querySelectorAll('.goog-te-menu-value').length == 0) {
                                        var txt = document.getElementsByTagName('html')[0].innerHTML;
                                        JSInterface.addhtml(txt)
                                    }
                                }, 1600)
                            } else {
                                setTimeout(function() {
                                    injectHeadWaitHead()
                                }, 300)
                            }
                        }
                        inject()
                    })()
                    """)
                    
                case 4:
                    
                    tab?.reload()
                case 5:
                    Preferences.General.nightModeEnabled.value = !Preferences.General.nightModeEnabled.value
                case 9:
                    if #available(iOS 16.0, *), let findInteraction = self.tabManager.selectedTab?.webView?.findInteraction {
                        findInteraction.searchText = ""
                        findInteraction.presentFindNavigator(showingReplace: false)
                    } else {
                        self.updateFindInPageVisibility(visible: true)
                    }
                case 10:
                    self.printPdf()
                case 11:
                    tab?.switchUserAgent()
                case 12:
                    displayPageZoom(visible: true)
                case 13:
                    displayPageCertificateInfo()
                case 14:
                    browserViewController.tabToolbarDidPressShare()
                case 15:
                    self.presentPlaylistController()
                case 16:
                    // swiftlint:disable:next safe_javascript
                    browserViewController.tabManager.selectedTab?.webView?.evaluateJavaScript("(function() {function showDevTool(){if(typeof eruda != 'undefined') {try{eruda.init();eruda.add(erudaDom);eruda.show(\"elements\");eruda.show();if(intouDom){var element=eruda.get(\"elements\");element.set(intouDom)}}catch(e){mbrowser.showToast(\"Unable to open the developer module.\")}}else{JSInterface.syslog(\"无法加载模块 请刷新\")}}!(function(){if(typeof eruda!=\"undefined\"){showDevTool()}else{var script=document.createElement(\"script\");script.src=\"https://api.yjllq.com/static/js/liberudadom.js\";document.body.appendChild(script);var scriptDom=document.createElement(\"script\");scriptDom.src=\"https://api.yjllq.com/static/js/liberuda.js\";document.body.appendChild(scriptDom);script.onload=function(){setTimeout(()=>{showDevTool()},1000)}}})();})()")
                case 17:
                    browserViewController.tabManager.selectedTab?.loadRequest(URLRequest(url: URL(string: FaviconUrl.DONATE)!))
                    
                case 18:
                    if isShownOnWebPage {
                        presentBraveShieldsViewController()
                    } else {
                        
                            let controller = UIHostingController(rootView: AdvancedShieldsSettingsView(
                                profile: self.profile,
                                tabManager: self.tabManager,
                                feedDataSource: self.feedDataSource,
                                historyAPI: self.braveCore.historyAPI,
                                p3aUtilities: self.braveCore.p3aUtils,
                                clearDataCallback: { [weak self] isLoading, isHistoryCleared in
                                    guard let view = self?.navigationController?.view, view.window != nil else {
                                        assertionFailure()
                                        return
                                    }

                              
                                }))

                            controller.rootView.openURLAction = { [unowned self] _ in
                                // openDestinationURL(url)
                            }

                            let container = SettingsNavigationController(rootViewController: controller)
                            container.isModalInPresentation = true
                            container.modalPresentationStyle =
                                UIDevice.current.userInterfaceIdiom == .phone ? .pageSheet : .formSheet
                            controller.navigationItem.rightBarButtonItem = .init(
                                barButtonSystemItem: .done,
                                target: container,
                                action: #selector(SettingsNavigationController.done))
                            self.present(container, animated: true)
                        
                    }
                   
                default:
                    self.goHistory(menuController)
                }
            }, browserViewController)
            BraveShieldStatsViewWrapper().padding(15)
                .frame(height: 140)
                .onTapGesture {
                    self.dismiss(animated: true)
                    // 打开隐私报告视图
                    let host = UIHostingController(rootView: PrivacyReportsManager.prepareView(isPrivateBrowsing: self.privateBrowsingManager.isPrivateBrowsing))
                
                    // 打开隐私报告链接
                    host.rootView.openPrivacyReportsUrl = { [weak self] in
                        browserViewController.navigateToInput(
                            URL.brave.privacyFeatures.absoluteString,
                            inNewTab: false,
                            // 隐私报告视图在私密模式下不可用
                            switchingToPrivateMode: false)
                    }

                    browserViewController.present(host, animated: true)
                }.onLongPressGesture {
                    print("Rectangle long pressed!")
                }
            
            // 调整视图大小
//            GeometryReader { geometry in
//                            BraveShieldStatsViewWrapper()
//                                .frame(width: geometry.size.width-30) // 高度固定为 200
//                        }
            // 如果在网页上显示，则添加钱包和播放列表按钮
//            if isShownOnWebPage {
            ////                // 钱包按钮
            ////                MenuItemFactory.button(for: .wallet()) {[weak self] in
            ////                    self?.presentWallet()
            ////                }
//
//                // 播放列表按钮
//                MenuItemFactory.button(for: .playlist()) { [weak self] in
//                    guard let self = self else { return }
//                    self.presentPlaylistController()
//                }
//            }
        }
    }

    /// Presents Wallet without an origin (ex. from menu)
    func presentWallet() {
//    guard let walletStore = self.walletStore ?? newWalletStore() else { return }
//    walletStore.origin = nil
//    let vc = WalletHostingViewController(walletStore: walletStore, webImageDownloader: braveCore.webImageDownloader)
//    vc.delegate = self
//    self.dismiss(animated: true) {
//      self.present(vc, animated: true)
//    }
    }

    public func presentPlaylistController() {
        if PlaylistCarplayManager.shared.isPlaylistControllerPresented {
            let alert = UIAlertController(title: Strings.PlayList.playlistAlreadyShowingTitle,
                                          message: Strings.PlayList.playlistAlreadyShowingBody,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Strings.OKString, style: .default))
            dismiss(animated: true) {
                self.present(alert, animated: true)
            }
            return
        }
    
        // Present existing playlist controller
        if let playlistController = PlaylistCarplayManager.shared.playlistController {
            PlaylistP3A.recordUsage()
      
            dismiss(animated: true) {
                PlaylistCarplayManager.shared.isPlaylistControllerPresented = true
                self.present(playlistController, animated: true)
            }
        } else {
            // Retrieve the item and offset-time from the current tab's webview.
            let tab = self.tabManager.selectedTab
            PlaylistCarplayManager.shared.getPlaylistController(tab: tab) { [weak self] playlistController in
                guard let self = self else { return }

                playlistController.modalPresentationStyle = .fullScreen
                PlaylistP3A.recordUsage()
        
                self.dismiss(animated: true) {
                    PlaylistCarplayManager.shared.isPlaylistControllerPresented = true
                    self.present(playlistController, animated: true)
                }
            }
        }
    }

    struct BraveShieldStatsViewWrapper: UIViewRepresentable {
        func makeUIView(context: Context) -> BraveShieldStatsView {
            let statsView = BraveShieldStatsView()
                    
            statsView.isPrivateBrowsing = false
            
//            statsView.addGestureRecognizer(tap)
//            statsView.addGestureRecognizer(longPress)
//
//            statsView.openPrivacyHubPressed = { [weak self] in
//              self?.openPrivacyHubPressed()
//            }
//
//            statsView.hidePrivacyHubPressed = { [weak self] in
//              self?.hidePrivacyHubPressed()
//            }
                    
            return statsView
        }

        func updateUIView(_ uiView: BraveShieldStatsView, context: Context) {
            // 如果需要在更新时执行一些操作，可以在此添加代码
        }
    }

    struct PageActionsMenuSection: View {
        var browserViewController: BrowserViewController
        var tabURL: URL
        var activities: [UIActivity]

        @State private var playlistItemAdded: Bool = false

        private var playlistActivity: (enabled: Bool, item: PlaylistInfo?)? {
            self.browserViewController.addToPlayListActivityItem ?? self.browserViewController.openInPlaylistActivityItem
        }

        private var isPlaylistItemAdded: Bool {
            self.browserViewController.openInPlaylistActivityItem != nil
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                MenuTabDetailsView(tab: self.browserViewController.tabManager.selectedTab, url: self.tabURL)
                VStack(spacing: 0) {
                    if let activity = playlistActivity, activity.enabled, let item = activity.item {
                        PlaylistMenuButton(isAdded: self.isPlaylistItemAdded) {
                            if !self.isPlaylistItemAdded {
                                // Add to playlist
                                self.browserViewController.addToPlaylist(item: item) { didAddItem in
                                    Logger.module.debug("Playlist Item Added")
                                    if didAddItem {
                                        self.playlistItemAdded = true
                                    }
                                }
                            } else {
                                self.browserViewController.dismiss(animated: true) {
                                    self.browserViewController.openPlaylist(tab: self.browserViewController.tabManager.selectedTab, item: item)
                                }
                            }
                        }
                        .animation(.default, value: self.playlistItemAdded)
                    }
      
                    NightModeMenuButton(dismiss: {
                        self.browserViewController.dismiss(animated: true)
                    })
                  
                    ForEach(self.activities.compactMap { $0 as? MenuActivity }, id: \.activityTitle) { activity in
                        MenuItemButton(icon: activity.menuImage, title: activity.activityTitle ?? "") {
                            self.browserViewController.dismiss(animated: true) {
                                activity.perform()
                            }
                        }
                    }
                }
            }
        }
    }

    struct MenuTabDetailsView: View {
        @SwiftUI.Environment(\.colorScheme) var colorScheme: ColorScheme
        weak var tab: Tab?
        var url: URL

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                if let tab = tab {
                    Text(verbatim: tab.displayTitle)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundColor(Color(.braveLabel))
                }
                Text(verbatim: self.url.baseDomain ?? self.url.host ?? self.url.absoluteDisplayString)
                    .font(.footnote)
                    .lineLimit(1)
                    .foregroundColor(Color(.secondaryBraveLabel))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }
}
