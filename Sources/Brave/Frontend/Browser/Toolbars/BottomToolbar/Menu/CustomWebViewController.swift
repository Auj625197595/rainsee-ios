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
import Preferences
import WebKit

import CoreData

class CustomWebViewController: UIViewController, WKNavigationDelegate, PanModalPresentable, WKScriptMessageHandler {
    private var url: String

    private var browserViewController: BrowserViewController?
    private var webView: WKWebView!

    init(_ url: String, _ browserViewController: BrowserViewController) {
        self.url = url
        self.browserViewController = browserViewController

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var scriptAtEnd: String?
    func addScriptAtEnd(_ script: String) {
        scriptAtEnd = script
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 创建 WKWebView
        webView = WKWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = true

        webView.navigationDelegate = self

        // Add user script to inject the object into the web page
        let night = traitCollection.userInterfaceStyle == .dark || Preferences.General.nightModeEnabled.value

        view.isHidden = true

        var script = ""
        if night {
            script = """
                document.querySelector('html').style.backgroundColor='black';
                document.querySelector('body').style.backgroundColor='black'
            """
        } else {
            script = """
                window.webkit.messageHandlers.native.postMessage({ key: 'value' });
            """
        }

        let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        let userContentController = WKUserContentController()
        userContentController.addUserScript(userScript)
        userContentController.add(self, name: "native") // Add script message handler

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController

        // Assign the configuration to the webView
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        view.addSubview(webView)

        var language = Locale.current.languageCode
        // 加载网页
        let now = NSDate()
        let timeInterval = now.timeIntervalSince1970
        let timeStamp = Int(timeInterval)
        if let preferredLanguage = Locale.preferredLanguages.first {
            language = Locale.components(fromIdentifier: preferredLanguage)[NSLocale.Key.languageCode.rawValue]
            print("用户首选主要语言：\(language ?? "未知")")
        } else {
            print("无法获取用户首选语言")
        }

        
        if url.contains("?") {
            url = "\(url)&token=\(Preferences.User.mkey.value)&night=\(night)&lang=\(language!)&t=\(timeStamp)"
        } else {
            url = "\(url)?token=\(Preferences.User.mkey.value)&night=\(night)&lang=\(language!)&t=\(timeStamp)"
        }

        if let url_res = URL(string: url) {
            let request = URLRequest(url: url_res)
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
        view.isHidden = false

        if let js = scriptAtEnd {
            // swiftlint:disable:next safe_javascript
            webView.evaluateJavaScript(js)
        }
        panModalSetNeedsLayoutUpdate()
    }

    // MARK: - PanModalPresentable

    var panScrollable: UIScrollView? {
        return webView.scrollView
    }

    var longFormHeight: PanModalHeight {
        return .maxHeight
    }

    // 其他 PanModal 相关配置可以根据需要添加
    var allowsExtendedPanScrolling: Bool {
        return true // 允许手势传递给内部 ScrollView
    }

    // MARK: - WKScriptMessageHandler

    // Implement WKScriptMessageHandler to handle messages from JavaScript
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "native", let body = message.body as? [String: Any] {
            // Handle the message from JavaScript
            let key = body["key"] as? String

            if key == "cookie" {
                if let img = body["img"] as? String {
                    Preferences.User.avator.value = img
                }
                if let nickname = body["nickname"] as? String {
                    Preferences.User.nickName.value = nickname
                }
                if let mkey = body["mkey"] as? String {
                    Preferences.User.mkey.value = mkey
                  
                    browserViewController?.sendRequest(cookie: mkey)
                    
                    
                    let delayInSeconds: Double = 3.0
                    // 在全局队列中创建一个子线程
                    let dispatchQueue = DispatchQueue.global(qos: .background)
                    // 延迟执行任务
                    dispatchQueue.asyncAfter(deadline: .now() + delayInSeconds) {
                        // 在这里放置需要延迟执行的代码
                        self.browserViewController?.download(cookie: mkey)
                    }
               
                }
            } else if key == "dismiss" {
                dismiss(animated: true)
            } else if key == "quitLogin" {
                dismiss(animated: true)
                Preferences.User.mkey.value = ""
                Preferences.User.nickName.value = ""
                Preferences.User.avator.value = ""
            } else if key == "updateImg" {
                dismiss(animated: true)
                if let url = body["url"] as? String {
                    Preferences.User.avator.value = url
                }

            } else if key == "goWeb" {
                dismiss(animated: true)
                if let url = body["url"] as? String {
                    let tab = browserViewController?.tabManager.selectedTab
                    tab?.webView?.load(URLRequest(url: URL(string: url)!))
                }
            } else if key == "addJavaScript" {
                dismiss(animated: true)
                let transRestlt: String = body["transRestlt"] as! String
                let id: Int64 = body["id"] as! Int64
                let name: String = body["name"] as! String
                let version: String = body["version"] as! String
                let originurl: String = body["originurl"] as! String
                let intro: String = body["synopsis"] as! String

                browserViewController?.addScript(name: name, desc: intro, script: transRestlt, version: version, cid: id, origin_url: originurl)
                

            } else if key == "updatejs" {
                browserViewController?.updateScript(body)

            } else if key == "deleteJs" {
                if let uuid = body["uuid"] as? String {
                    browserViewController?.deleteJs(uuid)
                }
            } else if key == "swicthBook" {
                if let enable = body["enable"] as? Bool {
                    Preferences.SyncRain.syncBook.value = enable
                }

            } else if key == "swicthHome" {
                if let enable = body["enable"] as? Bool {
                    Preferences.SyncRain.syncHome.value = enable
                }

            } else if key == "swicthPw" {
                if let enable = body["enable"] as? Bool {
                    Preferences.SyncRain.syncPw.value = enable
                }
            }
            // Call native methods based on the message received
            // ...
        }
    }

    func downloadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let image = UIImage(data: data) {
                // 将图像保存到本地
                self.saveImageToLocal(image: image, imageName: "localImage.jpg")
                completion(image)
            } else {
                completion(nil)
            }
        }.resume()
    }

    func saveImageToLocal(image: UIImage, imageName: String) {
        if let data = image.jpegData(compressionQuality: 1.0) {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileURL = documentsDirectory.appendingPathComponent(imageName)
            try? data.write(to: fileURL)
        }
    }
}
