// Copyright 2023 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AVFoundation
import BraveCore
import BraveNews
import BraveShared
import BraveStrings
import BraveUI
import BraveWallet
import CertificateUtilities
import Data
import os.log
import Playlist
import Preferences
import Shared
import Storage
import SwiftUI

// MARK: - TopToolbarDelegate

extension BrowserViewController: TopToolbarDelegate {
    func showTabTray(isExternallyPresented: Bool = false) {
        if tabManager.tabsForCurrentMode.isEmpty {
            return
        }
        if #unavailable(iOS 16.0) {
            updateFindInPageVisibility(visible: false)
        }
        displayPageZoom(visible: false)

        if tabManager.selectedTab == nil {
            tabManager.selectTab(tabManager.tabsForCurrentMode.first)
        }
        if let tab = tabManager.selectedTab {
            screenshotHelper.takeScreenshot(tab)
        }

        isTabTrayActive = true

        let tabTrayController = TabTrayController(
            isExternallyPresented: isExternallyPresented,
            tabManager: tabManager,
            braveCore: braveCore,
            windowProtection: windowProtection).then {
            $0.delegate = self
            $0.toolbarUrlActionsDelegate = self
        }
        let container = UINavigationController(rootViewController: tabTrayController)
        container.delegate = self

        if !UIAccessibility.isReduceMotionEnabled {
            if !isExternallyPresented {
                container.transitioningDelegate = tabTrayController
            }
            container.modalPresentationStyle = .fullScreen
        }
        present(container, animated: !isExternallyPresented)
    }

    func topToolbarDidPressReload(_ topToolbar: TopToolbarView) {
        if let url = topToolbar.currentURL {
            tabManager.selectedTab?.reload()
        } else {
            tabManager.selectedTab?.reload()
        }
    }

    func topToolbarDidPressStop(_ topToolbar: TopToolbarView) {
        stopTabToolbarLoading()
    }

    func topToolbarDidLongPressReloadButton(_ topToolbar: TopToolbarView, from button: UIButton) {
        guard let tab = tabManager.selectedTab, let url = tab.url, !url.isLocal, !url.isReaderModeURL else { return }

        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: Strings.cancelButtonTitle, style: .cancel, handler: nil))

        let toggleActionTitle = tab.isDesktopSite == true ? Strings.appMenuViewMobileSiteTitleString : Strings.appMenuViewDesktopSiteTitleString
        alert.addAction(
            UIAlertAction(
                title: toggleActionTitle, style: .default,
                handler: { _ in
                    tab.switchUserAgent()
                }))

        UIImpactFeedbackGenerator(style: .heavy).bzzt()
        if UIDevice.current.userInterfaceIdiom == .pad {
            alert.popoverPresentationController?.sourceView = view
            alert.popoverPresentationController?.sourceRect = view.convert(button.frame, from: button.superview)
            alert.popoverPresentationController?.permittedArrowDirections = [.up]
        }
        present(alert, animated: true)
    }

    func topToolbarDidPressTabs(_ topToolbar: TopToolbarView) {
        showTabTray()
    }

    func topToolbarDidPressReaderMode(_ topToolbar: TopToolbarView) {
        toggleReaderMode()
    }

    func topToolbarDidPressPlaylistButton(_ urlBar: TopToolbarView) {
        guard let tab = tabManager.selectedTab, let playlistItem = tab.playlistItem else { return }
        let state = urlBar.locationView.playlistButton.buttonState
        switch state {
        case .addToPlaylist:
            addToPlaylist(item: playlistItem) { [weak self] didAddItem in
                guard let self else { return }

                if didAddItem {
                    self.updatePlaylistURLBar(tab: tab, state: .existingItem, item: playlistItem)

                    DispatchQueue.main.async { [self] in
                        let popover = self.createPlaylistPopover(item: playlistItem, tab: tab)
                        popover.present(from: self.topToolbar.locationView.playlistButton, on: self)
                    }
                }
            }
        case .addedToPlaylist:
            // Shows its own menu
            break
        case .none:
            break
        }
    }

    func topToolbarDidPressPlaylistMenuAction(_ urlBar: TopToolbarView, action: PlaylistURLBarButton.MenuAction) {
        guard let tab = tabManager.selectedTab, let info = tab.playlistItem else { return }
        switch action {
        case .changeFolders:
            guard let item = PlaylistItem.getItem(uuid: info.tagId) else { return }
            let controller = PlaylistChangeFoldersViewController(item: item)
            present(controller, animated: true)
        case .openInPlaylist:
            DispatchQueue.main.async {
                self.openPlaylist(tab: tab, item: info)
            }
        case .remove:
            DispatchQueue.main.async {
                if PlaylistManager.shared.delete(item: info) {
                    self.updatePlaylistURLBar(tab: tab, state: .newItem, item: info)
                }
            }
        case .undoRemove(let originalFolderUUID):
            addToPlaylist(item: info, folderUUID: originalFolderUUID)
        }
    }

    func topToolbarDisplayTextForURL(_ topToolbar: URL?) -> (String?, Bool) {
        // use the initial value for the URL so we can do proper pattern matching with search URLs
        var searchURL = tabManager.selectedTab?.currentInitialURL
        if let url = searchURL, InternalURL.isValid(url: url) {
            searchURL = url
        }
        if let query = profile.searchEngines.queryForSearchURL(searchURL as URL?,
                                                               forType: privateBrowsingManager.isPrivateBrowsing ? .privateMode : .standard)
        {
            return (query, true)
        } else {
            return (topToolbar?.absoluteString, false)
        }
    }

    func topToolbarDidPressScrollToTop(_ topToolbar: TopToolbarView) {
        if let selectedTab = tabManager.selectedTab, favoritesController == nil {
            // Only scroll to top if we are not showing the home view controller
            selectedTab.webView?.scrollView.setContentOffset(CGPoint.zero, animated: true)
        }
    }

    func topToolbar(_ topToolbar: TopToolbarView, didEnterText text: String) {
        if text.isEmpty {
            hideSearchController()
        } else {
            showSearchController()
            searchController?.setSearchQuery(query: text)
            searchLoader?.query = text.lowercased()
        }
    }

    func topToolbar(_ topToolbar: TopToolbarView, didSubmitText text: String) {
        processAddressBar(text: text)
    }

    func processAddressBar(text: String, isBraveSearchPromotion: Bool = false, isUserDefinedURLNavigation: Bool = false) {
        processAddressBarTask?.cancel()
        processAddressBarTask = Task { @MainActor in
            if !isBraveSearchPromotion, await submitValidURL(text, isUserDefinedURLNavigation: isUserDefinedURLNavigation) {
                return
            } else {
                // We couldn't build a URL, so pass it on to the search engine.
                submitSearchText(text, isBraveSearchPromotion: isBraveSearchPromotion)

                if !privateBrowsingManager.isPrivateBrowsing {
                    RecentSearch.addItem(type: .text, text: text, websiteUrl: nil)
                }
            }
        }
    }

    @MainActor private func submitValidURL(_ text: String, isUserDefinedURLNavigation: Bool) async -> Bool {
        // 如果能够通过URIFixup获取URL
        if let fixupURL = URIFixup.getURL(text) {
            // 不允许用户输入以下协议的URL，而是将它们提交给搜索引擎，类似于Chrome-iOS的做法。
            if !["file"].contains(fixupURL.scheme) {
                // 检查文本是否是去中心化DNS支持的域名
//                if let decentralizedDNSHelper = self.decentralizedDNSHelperFor(url: fixupURL) {
//                    // 离开覆盖模式
//                    topToolbar.leaveOverlayMode()
//                    // 更新工具栏当前的URL
//                    updateToolbarCurrentURL(fixupURL)
//                    // 设置加载状态为true
//                    topToolbar.locationView.loading = true
//                    // 使用去中心化DNS助手进行域名查找
//                    let result = await decentralizedDNSHelper.lookup(domain: fixupURL.schemelessAbsoluteDisplayString)
//                    // 恢复工具栏加载状态
//                    topToolbar.locationView.loading = tabManager.selectedTab?.loading ?? false
//                    // 如果任务被取消，则返回true（用户按下停止按钮或输入了新的URL）
//                    guard !Task.isCancelled else { return true }
//
//                    // 处理去中心化DNS查找结果
//                    switch result {
//                    case let .loadInterstitial(service):
//                        // 展示Web3服务的插页页面
//                        // showWeb3ServiceInterstitialPage(service: service, originalURL: fixupURL)
//                        return true
//                    case let .load(resolvedURL):
//                        // 如果解析后的URL使用了IPFS协议
//                        if resolvedURL.isIPFSScheme {
//                            return handleIPFSSchemeURL(resolvedURL)
//                        } else {
//                            // 完成编辑并提交解析后的URL
//                            finishEditingAndSubmit(resolvedURL)
//                            return true
//                        }
//                    case .none:
//                        break
//                    }
//                }

                // 用户输入了URL，因此使用它
                // 确定URL导航是从收藏夹还是书签中进行的，以正确处理书签脚本
                finishEditingAndSubmit(fixupURL, isUserDefinedURLNavigation: isUserDefinedURLNavigation)
                return true
            }
        }

        return false
    }

    @discardableResult
    func handleIPFSSchemeURL(_ url: URL) -> Bool {
        guard !privateBrowsingManager.isPrivateBrowsing else {
            topToolbar.leaveOverlayMode()
            if let errorPageHelper = tabManager.selectedTab?.getContentScript(name: ErrorPageHelper.scriptName) as? ErrorPageHelper, let webView = tabManager.selectedTab?.webView {
                errorPageHelper.loadPage(IPFSErrorPageHandler.privateModeError, forUrl: url, inWebView: webView)
            }
            return true
        }

//    guard let ipfsPref = Preferences.Wallet.Web3IPFSOption(rawValue: Preferences.Wallet.resolveIPFSResources.value) else {
//      return false
//    }

//    switch ipfsPref {
//    case .ask:
//      showIPFSInterstitialPage(originalURL: url)
//      return true
//    case .enabled:
//      if let resolvedUrl = braveCore.ipfsAPI.resolveGatewayUrl(for: url) {
//        finishEditingAndSubmit(resolvedUrl)
//        return true
//      }
//    case .disabled:
//      topToolbar.leaveOverlayMode()
//      if let errorPageHelper = tabManager.selectedTab?.getContentScript(name: ErrorPageHelper.scriptName) as? ErrorPageHelper, let webView = tabManager.selectedTab?.webView {
//        errorPageHelper.loadPage(IPFSErrorPageHandler.privateModeError, forUrl: url, inWebView: webView)
//      }
//      return true
//    }

        return false
    }

    func submitSearchText(_ text: String, isBraveSearchPromotion: Bool = false) {
        var engine = profile.searchEngines.defaultEngine(forType: privateBrowsingManager.isPrivateBrowsing ? .privateMode : .standard)

        if isBraveSearchPromotion {
            let braveSearchEngine = profile.searchEngines.orderedEngines.first {
                $0.shortName == OpenSearchEngine.EngineNames.brave
            }

            if let searchEngine = braveSearchEngine {
                engine = searchEngine
            }
        }

        if let searchURL = engine.searchURLForQuery(text, isBraveSearchPromotion: isBraveSearchPromotion) {
            // We couldn't find a matching search keyword, so do a search query.
            finishEditingAndSubmit(searchURL)
        } else {
            // We still don't have a valid URL, so something is broken. Give up.
            print("Error handling URL entry: \"\(text)\".")
            assertionFailure("Couldn't generate search URL: \(text)")
        }
    }

    func topToolbarDidEnterOverlayMode(_ topToolbar: TopToolbarView) {
        updateTabsBarVisibility()
        displayFavoritesController()
    }

    func topToolbarDidLeaveOverlayMode(_ topToolbar: TopToolbarView) {
        hideSearchController()
        hideFavoritesController()
        updateScreenTimeUrl(tabManager.selectedTab?.url)
        updateInContentHomePanel(tabManager.selectedTab?.url as URL?)
        updateTabsBarVisibility()
        if isUsingBottomBar {
            updateViewConstraints()
        }
    }

    func topToolbarDidBeginDragInteraction(_ topToolbar: TopToolbarView) {
        dismissVisibleMenus()
    }

    func topToolbarDidTapBraveShieldsButton(_ topToolbar: TopToolbarView) {
        presentBraveShieldsViewController()
    }

    func presentBraveShieldsViewController() {
        guard let selectedTab = tabManager.selectedTab, var url = selectedTab.url else { return }
        if let internalUrl = InternalURL(url), internalUrl.isErrorPage, let originalURL = internalUrl.originalURLFromErrorPage {
            url = originalURL
        }

        if url.isLocalUtility || InternalURL(url)?.isAboutURL == true || InternalURL(url)?.isAboutHomeURL == true {
            return
        }

        if #available(iOS 16.0, *) {
            // System components sit on top so we want to dismiss it
            selectedTab.webView?.findInteraction?.dismissFindNavigator()
        }

        let shields = ShieldsViewController(tab: selectedTab)
        shields.shieldsSettingsChanged = { [unowned self] _, shield in
            let currentDomain = self.tabManager.selectedTab?.url?.baseDomain
            let browsers = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.compactMap { $0.browserViewController }

            for browser in browsers {
                // Update the shields status immediately
                browser.topToolbar.refreshShieldsStatus()

                // Reload the tabs. This will also trigger an update of the brave icon in `TabLocationView` if
                // the setting changed is the global `.AllOff` shield
                for tab in browser.tabManager.allTabs {
                    if tab.url?.baseDomain == currentDomain {
                        tab.reload()
                    }
                }
            }

            // Record P3A shield changes
//            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//                // Record shields & FP related hisotgrams, wait a sec for CoreData to sync contexts
//                self.recordShieldsUpdateP3A(shield: shield)
//            }

            // In 1.6 we "reload" the whole web view state, dumping caches, etc. (reload():BraveWebView.swift:495)
            // BRAVE TODO: Port over proper tab reloading with Shields
        }

        shields.showGlobalShieldsSettings = { [unowned self] vc in
            vc.dismiss(animated: true) {
                weak var spinner: SpinnerView?
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

                        if isLoading, spinner == nil {
                            let newSpinner = SpinnerView()
                            newSpinner.present(on: view)
                            spinner = newSpinner
                        } else {
                            spinner?.dismiss()
                            spinner = nil
                        }

                        if isHistoryCleared {
                            // Donate Clear Browser History for suggestions
                            let clearBrowserHistoryActivity = ActivityShortcutManager.shared.createShortcutActivity(type: .clearBrowsingHistory)
                            self?.userActivity = clearBrowserHistoryActivity
                            clearBrowserHistoryActivity.becomeCurrent()
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
        }

        shields.showSubmitReportView = { [weak self] shieldsViewController in
            shieldsViewController.dismiss(animated: true) {
                guard let url = shieldsViewController.tab.url else { return }
                self?.showSubmitReportView(for: url)
            }
        }

        let container = PopoverNavigationController(rootViewController: shields)
        let popover = PopoverController(contentController: container, contentSizeBehavior: .preferredContentSize)
        popover.present(from: navigationToolbar.menuButton, on: self)
    }

    func showSubmitReportView(for url: URL) {
        // Strip fragments and query params from url
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        components?.queryItems = nil
        guard let cleanedURL = components?.url else { return }

        let viewController = UIHostingController(rootView: SubmitReportView(
            url: cleanedURL, isPrivateBrowsing: privateBrowsingManager.isPrivateBrowsing))

        viewController.modalPresentationStyle = .popover

        if let popover = viewController.popoverPresentationController {
            popover.sourceView = topToolbar.shieldsButton
            popover.sourceRect = topToolbar.shieldsButton.bounds

            let sheet = popover.adaptiveSheetPresentationController
            sheet.largestUndimmedDetentIdentifier = .medium
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        navigationController?.present(viewController, animated: true)
    }

    // TODO: This logic should be fully abstracted away and share logic from current MenuViewController
    // See: https://github.com/brave/brave-ios/issues/1452
    func topToolbarDidTapBookmarkButton(_ topToolbar: TopToolbarView) {
        navigationHelper.openBookmarks()
    }

    func topToolbarDidTapBraveRewardsButton(_ topToolbar: TopToolbarView) {
        showBraveRewardsPanel()
    }

    func topToolbarDidTapMenuButton(_ topToolbar: TopToolbarView) {
        tabToolbarDidPressMenu(topToolbar)
    }

    func topToolbarDidPressQrCodeButton(_ urlBar: TopToolbarView) {
        scanQRCode()
    }

    func topToolbarDidPressVoiceSearchButton(_ urlBar: TopToolbarView) {
        Task { @MainActor in
            onPendingRequestUpdatedCancellable = speechRecognizer.$finalizedRecognition.sink { [weak self] finalizedRecognition in
                guard let self else { return }

                if finalizedRecognition.status {
                    // Feedback indicating recognition is finalized
                    AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
                    UIImpactFeedbackGenerator(style: .medium).bzzt()
                    stopVoiceSearch(searchQuery: finalizedRecognition.searchQuery)
                }
            }

            let permissionStatus = await speechRecognizer.askForUserPermission()

            if permissionStatus {
                openVoiceSearch(speechRecognizer: speechRecognizer)
            } else {
                showNoMicrophoneWarning()
            }
        }

        func openVoiceSearch(speechRecognizer: SpeechRecognizer) {
            // Pause active playing in PiP when Audio Search is enabled
            if let pipMediaPlayer = PlaylistCarplayManager.shared.mediaPlayer?.pictureInPictureController?.playerLayer.player {
                pipMediaPlayer.pause()
            }

            voiceSearchViewController = PopupViewController(rootView: VoiceSearchInputView(speechModel: speechRecognizer))

            if let voiceSearchController = voiceSearchViewController {
                voiceSearchController.modalTransitionStyle = .crossDissolve
                voiceSearchController.modalPresentationStyle = .overFullScreen
                present(voiceSearchController, animated: true)
            }
        }

        func showNoMicrophoneWarning() {
            let alertController = UIAlertController(
                title: Strings.VoiceSearch.microphoneAccessRequiredWarningTitle,
                message: Strings.VoiceSearch.microphoneAccessRequiredWarningDescription,
                preferredStyle: .alert)

            let settingsAction = UIAlertAction(
                title: Strings.settings,
                style: .default)
            { _ in
                let url = URL(string: UIApplication.openSettingsURLString)!
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }

            let cancelAction = UIAlertAction(title: Strings.CancelString, style: .cancel, handler: nil)

            alertController.addAction(settingsAction)
            alertController.addAction(cancelAction)

            present(alertController, animated: true)
        }
    }

    func stopVoiceSearch(searchQuery: String? = nil) {
        voiceSearchViewController?.dismiss(animated: true) {
            if let query = searchQuery {
                self.submitSearchText(query)
            }

            self.speechRecognizer.clearSearch()
        }
    }

    func topToolbarDidTapWalletButton(_ urlBar: TopToolbarView) {
//    guard let selectedTab = tabManager.selectedTab else {
//      return
//    }
//    if #available(iOS 16.0, *) {
//      // System components sit on top so we want to dismiss it
//      selectedTab.webView?.findInteraction?.dismissFindNavigator()
//    }
//    presentWalletPanel(from: selectedTab.getOrigin(), with: selectedTab.tabDappStore)
    }

    private func hideSearchController() {
        if let searchController = searchController {
            searchController.willMove(toParent: nil)
            searchController.view.removeFromSuperview()
            searchController.removeFromParent()
            self.searchController = nil
            searchLoader = nil
            favoritesController?.view.isHidden = false
        }
    }

    private func showSearchController() {
        if searchController != nil { return }

        // Setting up data source for SearchSuggestions
        let tabType = TabType.of(tabManager.selectedTab)
        let searchDataSource = SearchSuggestionDataSource(
            forTabType: tabType,
            searchEngines: profile.searchEngines)

        // Setting up controller for SearchSuggestions
        searchController = SearchViewController(with: searchDataSource, browserColors: privateBrowsingManager.browserColors)
        searchController?.isUsingBottomBar = isUsingBottomBar
        guard let searchController = searchController else { return }
        searchController.setupSearchEngineList()
        searchController.searchDelegate = self
        searchController.profile = profile

        searchLoader = SearchLoader(
            historyAPI: braveCore.historyAPI,
            bookmarkManager: bookmarkManager,
            tabManager: tabManager)
        searchLoader?.addListener(searchController)
        searchLoader?.autocompleteSuggestionHandler = { [weak self] completion in
            self?.topToolbar.setAutocompleteSuggestion(completion)
        }

        addChild(searchController)
        if let favoritesController = favoritesController {
            view.insertSubview(searchController.view, aboveSubview: favoritesController.view)
        } else {
            view.insertSubview(searchController.view, belowSubview: header)
        }
        searchController.view.snp.makeConstraints {
            $0.edges.equalTo(view)
        }
        searchController.didMove(toParent: self)
        searchController.view.setNeedsLayout()
        searchController.view.layoutIfNeeded()

        favoritesController?.view.isHidden = true
    }

    func insertFavoritesControllerView(favoritesController: FavoritesViewController) {
        if let ntpController = activeNewTabPageViewController, ntpController.parent != nil {
            view.insertSubview(favoritesController.view, aboveSubview: ntpController.view)
        } else {
            // Two different behaviors here:
            // 1. For bottom bar we do not want to show the status bar color
            // 2. For top bar we do so it matches the address bar background
            let subview = isUsingBottomBar ? statusBarOverlay : footer
            view.insertSubview(favoritesController.view, aboveSubview: subview)
        }
    }

    private func displayFavoritesController() {
        if favoritesController == nil {
            let tabType = TabType.of(tabManager.selectedTab)
            let favoritesController = FavoritesViewController(
                tabType: tabType,
                privateBrowsingManager: privateBrowsingManager,
                action: { [weak self] bookmark, action in
                    self?.handleFavoriteAction(favorite: bookmark, action: action)
                },
                recentSearchAction: { [weak self] recentSearch, shouldSubmitSearch in
                    guard let self = self else { return }

                    let submitSearch = { [weak self] (text: String) in
                        if let fixupURL = URIFixup.getURL(text) {
                            self?.finishEditingAndSubmit(fixupURL)
                            return
                        }

                        self?.submitSearchText(text)
                    }

                    if let recentSearch = recentSearch,
                       let searchType = RecentSearchType(rawValue: recentSearch.searchType)
                    {
                        if shouldSubmitSearch {
                            recentSearch.update(dateAdded: Date())
                        }

                        switch searchType {
                        case .text, .website:
                            if let text = recentSearch.text {
                                self.topToolbar.setLocation(text, search: false)
                                self.topToolbar(self.topToolbar, didEnterText: text)

                                if shouldSubmitSearch {
                                    submitSearch(text)
                                }
                            }
                        case .qrCode:
                            if let text = recentSearch.text {
                                self.topToolbar.setLocation(text, search: false)
                                self.topToolbar(self.topToolbar, didEnterText: text)

                                if shouldSubmitSearch {
                                    submitSearch(text)
                                }
                            } else if let websiteUrl = recentSearch.websiteUrl {
                                self.topToolbar.setLocation(websiteUrl, search: false)
                                self.topToolbar(self.topToolbar, didEnterText: websiteUrl)

                                if shouldSubmitSearch {
                                    submitSearch(websiteUrl)
                                }
                            }
                        }
                    } else if UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs,
                              let searchQuery = UIPasteboard.general.string ?? UIPasteboard.general.url?.absoluteString
                    {
                        self.topToolbar.setLocation(searchQuery, search: false)
                        self.topToolbar(self.topToolbar, didEnterText: searchQuery)

                        if shouldSubmitSearch {
                            submitSearch(searchQuery)
                        }
                    }
                })
            self.favoritesController = favoritesController

            addChild(favoritesController)
            insertFavoritesControllerView(favoritesController: favoritesController)
            favoritesController.didMove(toParent: self)

            favoritesController.view.snp.makeConstraints {
                $0.leading.trailing.equalTo(pageOverlayLayoutGuide)
                $0.top.bottom.equalTo(view)
            }
            favoritesController.view.setNeedsLayout()
            favoritesController.view.layoutIfNeeded()
        }
        guard let favoritesController = favoritesController else { return }
        favoritesController.view.alpha = 0.0
        let animator = UIViewPropertyAnimator(duration: 0.2, dampingRatio: 1.0) {
            favoritesController.view.alpha = 1
        }
        animator.addCompletion { _ in
            self.webViewContainer.accessibilityElementsHidden = true
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
        animator.startAnimation()
    }

    private func hideFavoritesController() {
        guard let controller = favoritesController else { return }
        favoritesController = nil
        UIView.animate(
            withDuration: 0.1, delay: 0, options: [.beginFromCurrentState],
            animations: {
                controller.view.alpha = 0.0
            },
            completion: { _ in
                controller.willMove(toParent: nil)
                controller.view.removeFromSuperview()
                controller.removeFromParent()
                self.webViewContainer.accessibilityElementsHidden = false
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            })
    }

    // 打开添加书签的方法
    func openAddBookmark() {
        // 检查当前选定的标签是否存在，并且其URL不是本地URL或阅读器模式的URL
        guard let selectedTab = tabManager.selectedTab,
              let selectedUrl = selectedTab.url,
              !(selectedUrl.isLocal || selectedUrl.isReaderModeURL)
        else {
            // 如果条件不符合，则直接返回
            return
        }

        // 将选定标签的URL解码为阅读器模式URL，如果不存在则使用原始URL
        let bookmarkUrl = selectedUrl.decodeReaderModeURL ?? selectedUrl

        // 创建添加书签的编辑模式，使用选定标签的标题和解码后的URL
        let mode = BookmarkEditMode.addBookmark(title: selectedTab.displayTitle, url: bookmarkUrl.absoluteString)

        // 创建添加编辑书签的控制器，传递书签管理器、编辑模式和当前是否处于私密浏览模式
        let addBookMarkController = AddEditBookmarkTableViewController(bookmarkManager: bookmarkManager, mode: mode, isPrivateBrowsing: privateBrowsingManager.isPrivateBrowsing)

        // 使用自定义方法呈现设置导航控制器，同时启用取消按钮
        presentSettingsNavigation(with: addBookMarkController, cancelEnabled: true)
    }

    func presentSettingsNavigation(with controller: UIViewController, cancelEnabled: Bool = false) {
        let navigationController = SettingsNavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .formSheet

        let cancelBarbutton = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: navigationController,
            action: #selector(SettingsNavigationController.done))

        let doneBarbutton = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: navigationController,
            action: #selector(SettingsNavigationController.done))

        navigationController.navigationBar.topItem?.leftBarButtonItem = cancelEnabled ? cancelBarbutton : nil

        navigationController.navigationBar.topItem?.rightBarButtonItem = doneBarbutton

        present(navigationController, animated: true)
    }
}

extension BrowserViewController: ToolbarDelegate {
    func tabToolbarDidPressSearch(_ tabToolbar: ToolbarProtocol, button: UIButton) {
        topToolbar.tabLocationViewDidTapLocation(topToolbar.locationView)
    }

    func tabToolbarDidPressBack(_ tabToolbar: ToolbarProtocol, button: UIButton) {
        tabManager.selectedTab?.goBack()
        resetExternalAlertProperties(tabManager.selectedTab)
        recordNavigationActionP3A(isNavigationActionForward: false)
    }

    func tabToolbarDidLongPressBack(_ tabToolbar: ToolbarProtocol, button: UIButton) {
        UIImpactFeedbackGenerator(style: .heavy).bzzt()
        showBackForwardList()
    }

    func tabToolbarDidPressForward(_ tabToolbar: ToolbarProtocol, button: UIButton) {
        tabManager.selectedTab?.goForward()
        resetExternalAlertProperties(tabManager.selectedTab)
        recordNavigationActionP3A(isNavigationActionForward: true)

        // tabManager.selectedTab?.webView?.load(<#T##request: URLRequest##URLRequest#>)
        // let url = URLRequest(url: URL(string: "internal://local/about/home#panel=0")!)
    }

//    func didLongPressNewTab(_ tabToolbar: ToolbarProtocol, button: UIButton) {
//        if Preferences.Privacy.privateBrowsingLock.value {
//            askForLocalAuthentication { [weak self] success, _ in
//                if success {
//                    self?.openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: true)
//                }
//            }
//        } else {
//            openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: true)
//        }
//    }

    func tabToolbarDidPressShare() {
        navigationHelper.openShareSheet()
    }

    // 当标签工具栏上的菜单按钮被按下时调用的方法
    func tabToolbarDidPressMenu(_ tabToolbar: ToolbarProtocol) {
        // 获取当前选定标签的URL
        let selectedTabURL: URL? = {
            // 如果无法获取URL，则返回nil
            guard let url = tabManager.selectedTab?.url else { return nil }

            // 如果是内部URL
            if let internalURL = InternalURL(url) {
                // 如果是错误页面，则返回原始URL
                if internalURL.isErrorPage {
                    return internalURL.originalURLFromErrorPage
                }
                // 如果是阅读器模式页面，则返回提取的URL参数
                if internalURL.isReaderModePage {
                    return internalURL.extractedUrlParam
                }
                // 其他情况返回nil
                return nil
            }
            // 如果是普通URL，则直接返回
            return url
        }()

        // 隐藏页面缩放
        displayPageZoom(visible: false)

        // 创建一个空的UIActivity数组
        var activities: [UIActivity] = []

        // 如果选定标签的URL和标签都不为nil
        if let url = selectedTabURL, let tab = tabManager.selectedTab {
            // 制作分享活动数组
            activities = makeShareActivities(for: url, tab: tab, sourceView: view, sourceRect: view.convert(topToolbar.menuButton.frame, from: topToolbar.menuButton.superview), arrowDirection: .up)
        }

        // 设置菜单的初始高度，如果选定标签的URL不为nil，则为470，否则为500
        let initialHeight: CGFloat = selectedTabURL != nil ? 470 : 500

        // 创建菜单控制器
        let menuController = MenuViewController(
            initialHeight: initialHeight,
            content: { menuController in
                // 判断菜单是否显示在网页上
                let isShownOnWebPage = selectedTabURL != nil

                // 构建垂直方向的堆栈视图
                VStack(spacing: 6) {
                    // 根据是否显示在网页上选择不同的菜单部分
//                    if isShownOnWebPage {
//                        featuresMenuSection(menuController)
//                    } else {
//                        privacyFeaturesMenuSection(menuController)
//                    }

                    // 添加分隔线
//                    Divider()

                    // 添加目标菜单部分
                    destinationMenuSection(self, menuController, isShownOnWebPage: isShownOnWebPage)

                    // 如果选定标签的URL不为nil，则添加页面操作菜单部分
//                    if let tabURL = selectedTabURL {
//                        Divider()
//                        PageActionsMenuSection(browserViewController: self, tabURL: tabURL, activities: activities)
//                    }
                }
                // 隐藏导航栏
                .navigationBarHidden(true)
            })

        // 弹出PanModal菜单
        presentPanModal(menuController, sourceView: tabToolbar.menuButton, sourceRect: tabToolbar.menuButton.bounds)

        // 如果菜单控制器的模态呈现样式是弹出窗口
        if menuController.modalPresentationStyle == .popover {
            // 配置弹出窗口的外边距和允许的箭头方向
            menuController.popoverPresentationController?.popoverLayoutMargins = .init(equalInset: 4)
            menuController.popoverPresentationController?.permittedArrowDirections = [.up, .down]
        }
    }

    func tabToolbarDidPressAddTab(_ tabToolbar: ToolbarProtocol, button: UIButton) {
//    self.openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: privateBrowsingManager.isPrivateBrowsing)

        tabManager.selectedTab?.loadRequest(PrivilegedRequest(url: TabManager.ntpInteralURL) as URLRequest)
    }
    func tabToolbarDidPressAddTabReal(_ tabToolbar: ToolbarProtocol, button: UIButton) {
//    self.openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: privateBrowsingManager.isPrivateBrowsing)

        self.openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: privateBrowsingManager.isPrivateBrowsing)
    }
    func tabToolbarDidLongPressForward(_ tabToolbar: ToolbarProtocol, button: UIButton) {
        UIImpactFeedbackGenerator(style: .heavy).bzzt()
        showBackForwardList()
    }

    func tabToolbarDidPressTabs(_ tabToolbar: ToolbarProtocol, button: UIButton) {
        showTabTray()
    }

    func topToolbarDidTapSecureContentState(_ urlBar: TopToolbarView) {
        guard let tab = tabManager.selectedTab, let url = tab.url, let secureContentStateButton = urlBar.locationView.secureContentStateButton else { return }
        let hasCertificate = (tab.webView?.serverTrust ?? (try? ErrorPageHelper.serverTrust(from: url))) != nil
        let pageSecurityView = PageSecurityView(
            displayURL: urlBar.locationView.urlDisplayLabel.text ?? url.absoluteDisplayString,
            secureState: tab.secureContentState,
            hasCertificate: hasCertificate,
            presentCertificateViewer: { [weak self] in
                self?.dismiss(animated: true)
                self?.displayPageCertificateInfo()
            })
        let popoverController = PopoverController(content: pageSecurityView)
        popoverController.present(from: secureContentStateButton, on: self)
    }

    func showBackForwardList() {
        if let backForwardList = tabManager.selectedTab?.webView?.backForwardList {
            let backForwardViewController = BackForwardListViewController(profile: profile, backForwardList: backForwardList)
            backForwardViewController.tabManager = tabManager
            backForwardViewController.bvc = self
            backForwardViewController.modalPresentationStyle = .overCurrentContext
            backForwardViewController.backForwardTransitionDelegate = BackForwardListAnimator()
            present(backForwardViewController, animated: true, completion: nil)
        }
    }

    func tabToolbarDidSwipeToChangeTabs(_ tabToolbar: ToolbarProtocol, direction: UISwipeGestureRecognizer.Direction) {
        let tabs = tabManager.tabsForCurrentMode
        guard let selectedTab = tabManager.selectedTab, let index = tabs.firstIndex(where: { $0 === selectedTab }) else { return }
        let newTabIndex = index + (direction == .left ? -1 : 1)
        if newTabIndex >= 0 && newTabIndex < tabs.count {
            tabManager.selectTab(tabs[newTabIndex])
        }
    }

    func stopTabToolbarLoading() {
        tabManager.selectedTab?.stop()
        processAddressBarTask?.cancel()
        topToolbarDidPressReloadTask?.cancel()
        topToolbar.locationView.loading = tabManager.selectedTab?.loading ?? false
    }
}

extension BrowserViewController: UIContextMenuInteractionDelegate {
    public func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        let configuration = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [unowned self] _ in
            let actionMenus: [UIMenu?] = [
                makePasteMenu(), makeCopyMenu(), makeReloadMenu()
            ]

            return UIMenu(children: actionMenus.compactMap { $0 })
        }

        if #available(iOS 16.0, *) {
            configuration.preferredMenuElementOrder = .priority
        }

        return configuration
    }

    /// Create the "Request Destop Site" / "Request Mobile Site" menu if the tab has a webpage loaded
    private func makeReloadMenu() -> UIMenu? {
        guard let tab = tabManager.selectedTab, let url = tab.url, url.isWebPage() else { return nil }
        let reloadTitle = tab.isDesktopSite == true ? Strings.appMenuViewMobileSiteTitleString : Strings.appMenuViewDesktopSiteTitleString
        let reloadIcon = tab.isDesktopSite == true ? "leo.smartphone" : "leo.monitor"
        let reloadAction = UIAction(
            title: reloadTitle,
            image: UIImage(braveSystemNamed: reloadIcon),
            handler: UIAction.deferredActionHandler { [weak tab] _ in
                tab?.switchUserAgent()
            })

        return UIMenu(options: .displayInline, children: [reloadAction])
    }

    /// Create the "Paste"  and "Paste and Go" menu if there is anything on the `UIPasteboard`
    private func makePasteMenu() -> UIMenu? {
        guard UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs else { return nil }

        var children: [UIAction] = [
            UIAction(
                identifier: .pasteAndGo,
                handler: UIAction.deferredActionHandler { _ in
                    if let pasteboardContents = UIPasteboard.general.string {
                        self.topToolbar(self.topToolbar, didSubmitText: pasteboardContents)
                    }
                }),
            UIAction(
                identifier: .paste,
                handler: UIAction.deferredActionHandler { _ in
                    if let pasteboardContents = UIPasteboard.general.string {
                        self.topToolbar.enterOverlayMode(pasteboardContents, pasted: true, search: true)
                    }
                })
        ]

        if #unavailable(iOS 16.0), isUsingBottomBar {
            children.reverse()
        }

        return UIMenu(options: .displayInline, children: children)
    }

    /// Create the "Copy Link" and "Copy Clean Link" menu if there is any URL loaded on the tab.
    ///
    /// - Note: "Copy Clean Link" will be included even if no cleaning is done to the url.
    private func makeCopyMenu() -> UIMenu? {
        let tab = tabManager.selectedTab
        guard let url = topToolbar.currentURL else { return nil }

        var children: [UIAction] = [
            UIAction(
                title: Strings.copyLinkActionTitle,
                image: UIImage(systemName: "doc.on.doc"),
                handler: UIAction.deferredActionHandler { _ in
                    UIPasteboard.general.url = url as URL
                }),
            UIAction(
                title: Strings.copyCleanLink,
                image: UIImage(braveSystemNamed: "leo.broom"),
                handler: UIAction.deferredActionHandler { _ in
                    let service = URLSanitizerServiceFactory.get(privateMode: tab?.isPrivate ?? true)
                    let cleanedURL = service?.sanitizeURL(url) ?? url
                    UIPasteboard.general.url = cleanedURL
                })
        ]

        if #unavailable(iOS 16.0), isUsingBottomBar {
            children.reverse()
        }

        return UIMenu(options: .displayInline, children: children)
    }
}

// MARK: UINavigationControllerDelegate

extension BrowserViewController: UINavigationControllerDelegate {
    public func navigationControllerSupportedInterfaceOrientations(_ navigationController: UINavigationController) -> UIInterfaceOrientationMask {
        return navigationController.visibleViewController?.supportedInterfaceOrientations ?? navigationController.supportedInterfaceOrientations
    }

    public func navigationControllerPreferredInterfaceOrientationForPresentation(_ navigationController: UINavigationController) -> UIInterfaceOrientation {
        return navigationController.visibleViewController?.preferredInterfaceOrientationForPresentation ?? navigationController.preferredInterfaceOrientationForPresentation
    }
}
