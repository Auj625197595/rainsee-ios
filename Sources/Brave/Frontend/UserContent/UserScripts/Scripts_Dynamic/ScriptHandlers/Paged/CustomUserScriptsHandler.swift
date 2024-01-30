// 版权 2023 Brave 作者。保留所有权利。
// 此源代码表单受 Mozilla Public License，版本 2.0 的条款约束。
// 如果未与此文件一起分发 MPL 的副本，可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import BraveUI
import CoreData
import Foundation
import Preferences
import Shared
import WebKit

class CustomUserScriptsHandler: NSObject, TabContentScript {
    private weak var browserController: BrowserViewController?

    private weak var tab: Tab?
    private static var javascript: String?

    private var url: URL?
    private var urlObserver: NSObjectProtocol?
 
    // 初始化方法
    init(browserController: BrowserViewController, tab: Tab, javascript: String) {
        self.browserController = browserController
        self.tab = tab
        CustomUserScriptsHandler.javascript = javascript
        url = tab.url
        super.init()

        // 监听 WebView 的 URL 变化
        urlObserver = tab.webView?.observe(
            \.url, options: [.new],
            changeHandler: { [weak self] object, change in
                guard let self = self, let url = change.newValue else { return }
                if self.url?.withoutFragment != url?.withoutFragment {
                    self.url = url
                    
                   
                   
                    // swiftlint:disable:next safe_javascript
//                    object.evaluateJavaScript("console.log('xxxxxxxx');debugger;"+javascript+";console.log('mmmmmmmm');")

                    // 调用 JavaScript 函数来刷新 YouTube 视频质量
//          object.evaluateSafeJavaScript(functionName: "window.__firefox__.\(Self.refreshQuality)",
//                                        contentWorld: Self.scriptSandbox,
//                                        asFunction: true)
                }
            })
    }

    static let scriptName = "CustomUserScripts"
    static let scriptId = UUID().uuidString
    static let messageHandlerName = "CustomUserScripts"
    static let scriptSandbox: WKContentWorld = .page
    static var userScript: WKUserScript? = {
//        guard var script = loadUserScript(named: scriptName) else {
//            return nil
//        }

        // 创建 WKUserScript 来注入 JavaScript 代码
        return WKUserScript(source: "(function(){var t_ycsdilhvuev = \(Date().timeIntervalSince1970);window.rainsee_miantask_jcveu = t_ycsdilhvuev;setTimeout(()=>{if(t_ycsdilhvuev>=window.rainsee_miantask_jcveu){console.log('xxxxxxxx');"+javascript!+";}},1)})();",
                            injectionTime: .atDocumentStart,
                            forMainFrameOnly: false)
    }()

    // 实现 WKScriptMessageHandler 协议方法
    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage, replyHandler: (Any?, String?) -> Void) {
        if message.name == "CustomUserScripts", let body = message.body as? [String: Any] {
            // Handle the message from JavaScript
            let key = body["key"] as? String
            if key == "userScriptMutiSettle" {
                print("settle")
                browserController?.presentSearchSettingsController()
            }
        }
    }
}
