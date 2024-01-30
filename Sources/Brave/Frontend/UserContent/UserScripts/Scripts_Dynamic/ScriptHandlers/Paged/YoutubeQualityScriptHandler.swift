// 版权 2023 Brave 作者。保留所有权利。
// 此源代码表单受 Mozilla Public License，版本 2.0 的条款约束。
// 如果未与此文件一起分发 MPL 的副本，可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import WebKit
import Preferences
import Shared
import BraveUI

class YoutubeQualityScriptHandler: NSObject, TabContentScript {
  private weak var tab: Tab?
  private var url: URL?
  private var urlObserver: NSObjectProtocol?

  // 初始化方法
  init(tab: Tab) {
    self.tab = tab
    self.url = tab.url
    super.init()

    // 监听 WebView 的 URL 变化
    urlObserver = tab.webView?.observe(
      \.url, options: [.new],
      changeHandler: { [weak self] object, change in
        guard let self = self, let url = change.newValue else { return }
        if self.url?.withoutFragment != url?.withoutFragment {
          self.url = url

          // 调用 JavaScript 函数来刷新 YouTube 视频质量
          object.evaluateSafeJavaScript(functionName: "window.__firefox__.\(Self.refreshQuality)",
                                        contentWorld: Self.scriptSandbox,
                                        asFunction: true)
        }
      })
  }

  // 静态属性和常量
  private static let refreshQuality = "refresh_youtube_quality_\(uniqueID)"
  private static let setQuality = "set_youtube_quality_\(uniqueID)"
  private static let highestQuality = "'hd2160p'"

  static let scriptName = "YoutubeQualityScript"
  static let scriptId = UUID().uuidString
  static let messageHandlerName = "\(scriptName)_\(messageUUID)"
  static let scriptSandbox: WKContentWorld = .page
  static let userScript: WKUserScript? = {
    guard var script = loadUserScript(named: scriptName) else {
      return nil
    }

    // 创建 WKUserScript 来注入 JavaScript 代码
    return WKUserScript(source: secureScript(handlerNamesMap: ["$<message_handler>": messageHandlerName,
                                                               "$<refresh_youtube_quality>": refreshQuality,
                                                               "$<set_youtube_quality>": setQuality],
                                             securityToken: scriptId,
                                             script: script),
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true,
                        in: scriptSandbox)
  }()

  // 静态方法：设置选项是否启用
  static func setEnabled(option: Preferences.Option<String>, for tab: Tab) {
    let enabled = canEnableHighQuality(option: option)

    // 调用 JavaScript 函数来设置 YouTube 视频质量
    tab.webView?.evaluateSafeJavaScript(functionName: "window.__firefox__.\(Self.setQuality)", args: [enabled ? Self.highestQuality: "''"], contentWorld: Self.scriptSandbox, escapeArgs: false, asFunction: true)
  }

  // 实现 WKScriptMessageHandler 协议方法
  func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage, replyHandler: (Any?, String?) -> Void) {
    if !verifyMessage(message: message) {
      assertionFailure("缺少必需的安全令牌。")
      return
    }

    // 根据偏好设置决定是否启用高质量
    replyHandler(Self.canEnableHighQuality(option: Preferences.General.youtubeHighQuality) ?
                 Self.highestQuality : "", nil)
  }

  // 静态方法：判断是否可以启用高质量
  private static func canEnableHighQuality(option: Preferences.Option<String>) -> Bool {
    guard let qualityPreference = YoutubeHighQualityPreference(rawValue: option.value) else {
      return false
    }

    switch Reach().connectionStatus() {
    case .offline, .unknown: return false
    case .online(let type):
      if type == .wiFi {
        return qualityPreference == .wifi || qualityPreference == .on
      }

      return qualityPreference == .on
    }
  }
}
