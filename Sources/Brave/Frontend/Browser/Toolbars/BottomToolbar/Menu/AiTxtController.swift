// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import BraveShared
import BraveUI
import Growth
import PanModal
import Shared
import SwiftUI
import UIKit

import PanModal
import WebKit
import Preferences

class AiTxtController: UIViewController, WKNavigationDelegate, PanModalPresentable {
    private var txt: String
    private var webView: WKWebView!
    private var weburl: String
    init(_ txt: String, _ weburl: String) {
        self.txt = txt
        self.weburl = weburl
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 创建 WKWebView
        webView = WKWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = true

        webView.navigationDelegate = self
        view.addSubview(webView)

        let night = traitCollection.userInterfaceStyle == .dark || Preferences.General.nightModeEnabled.value
        let language = Locale.current.languageCode
        // 加载网页
        if let url = URL(string: "****") {
            let request = URLRequest(url: url)
            webView.load(request)
        }
        webView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        webView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        webView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        webView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 网页加载完成
        panModalSetNeedsLayoutUpdate()
        sendMsg(webView: webView)
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.minimumZoomScale = 1.0
    }

    // 获取 WKWebView 中的所有文本内容
    func sendMsg(webView: WKWebView) {
        DispatchQueue.main.async {
            if let encodedTxt = self.txt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                let scriptSource = "addDocIos({key:'\(encodedTxt)'})"
                // swiftlint:disable:next safe_javascript
                webView.evaluateJavaScript(scriptSource)
            } else {
                // 处理编码失败的情况
                print("Failed to encode 'self.txt'")
            }
        }
    }

    // MARK: - PanModalPresentable

    var panScrollable: UIScrollView? {
        return webView.scrollView
    }

    var longFormHeight: PanModalHeight {
        return .contentHeight(400)
    }

    // 其他 PanModal 相关配置可以根据需要添加
    var allowsExtendedPanScrolling: Bool {
        return true // 允许手势传递给内部 ScrollView
    }
}
