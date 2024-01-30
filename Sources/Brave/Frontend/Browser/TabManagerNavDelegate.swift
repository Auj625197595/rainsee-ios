import WebKit
import Shared
import Preferences

// WKNavigationDelegates 必须实现 NSObjectProtocol
class TabManagerNavDelegate: NSObject, WKNavigationDelegate {
  private var delegates = WeakList<WKNavigationDelegate>()
  weak var tabManager: TabManager?

  // 插入导航代理
  func insert(_ delegate: WKNavigationDelegate) {
    delegates.insert(delegate)
  }

  // 网页已经开始加载内容
  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    for delegate in delegates {
      delegate.webView?(webView, didCommit: navigation)
    }
  }

  // 网页加载失败
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    for delegate in delegates {
      delegate.webView?(webView, didFail: navigation, withError: error)
    }
  }

  // 网页临时导航加载失败
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    for delegate in delegates {
      delegate.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
    }
  }

  // 网页加载完成
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    for delegate in delegates {
      delegate.webView?(webView, didFinish: navigation)
    }
  }

  // 网页内容进程终止
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    for delegate in delegates {
      delegate.webViewWebContentProcessDidTerminate?(webView)
    }
  }

  // 处理认证挑战
  public func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
    let authenticatingDelegates = delegates.filter { wv in
      return wv.responds(to: #selector(WKNavigationDelegate.webView(_:didReceive:completionHandler:)))
    }

    guard let firstAuthenticatingDelegate = authenticatingDelegates.first else {
      return (.performDefaultHandling, nil)
    }

    // 不要更改为 `delegate.webView?(....)`，在当前时间写作 `2023年1月17日`，可选运算符会导致异步调用使编译器崩溃！
    // 必须在写作时进行强制解包。
    return await firstAuthenticatingDelegate.webView!(webView, respondTo: challenge)
  }

  // 处理临时导航的服务器重定向
  func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
    for delegate in delegates {
      delegate.webView?(webView, didReceiveServerRedirectForProvisionalNavigation: navigation)
    }
  }

  // 临时导航开始加载
  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    for delegate in delegates {
      delegate.webView?(webView, didStartProvisionalNavigation: navigation)
    }
  }

  // 默认允许策略
  private func defaultAllowPolicy(for navigationAction: WKNavigationAction) -> WKNavigationActionPolicy {
    let isPrivateBrowsing = tabManager?.privateBrowsingManager.isPrivateBrowsing == true
    func isYouTubeLoad() -> Bool {
      guard let domain = navigationAction.request.mainDocumentURL?.baseDomain else {
        return false
      }
      let domainsWithUniversalLinks: Set<String> = ["youtube.com", "youtu.be"]
      return domainsWithUniversalLinks.contains(domain)
    }
    if isPrivateBrowsing || !Preferences.General.followUniversalLinks.value ||
        (Preferences.General.keepYouTubeInBrave.value && isYouTubeLoad()) {
      // 使用私有的枚举值 `_WKNavigationActionPolicyAllowWithoutTryingAppLink` 阻止 Brave 打开通用链接
      // 定义在这里: https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKNavigationDelegatePrivate.h#L62
      let allowDecision = WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow
      return allowDecision
    }
    return .allow
  }
  
  @MainActor
  // 决定导航的策略，并提供偏好设置
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
    var res = defaultAllowPolicy(for: navigationAction)
    var pref = preferences
    
    for delegate in delegates {
      // 解决模糊的委托签名问题: https://github.com/apple/swift/issues/45652#issuecomment-1149235081
      typealias WKNavigationActionSignature = (WKNavigationDelegate) -> ((WKWebView, WKNavigationAction, WKWebpagePreferences, @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) -> Void)?
      
      // 检测异步实现是否存在，因为我们不能直接检测它们
      if delegate.responds(to: #selector(WKNavigationDelegate.webView(_:decidePolicyFor:preferences:decisionHandler:) as WKNavigationActionSignature)) {
        // 不要更改为 `delegate.webView?(....)`，在当前时间写作 `2023年1月10日`，可选运算符会导致异步调用使编译器崩溃！
        // 必须在写作时进行强制解包。
        let (policy, preferences) = await delegate.webView!(webView, decidePolicyFor: navigationAction, preferences: preferences)
        if policy == .cancel {
          res = policy
        }
        
        if policy == .download {
          res = policy
        }
        
        pref = preferences
      }
    }
    
    return (res, pref)
  }
  
  @MainActor
  // 决定导航响应的策略
  func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
    var res = WKNavigationResponsePolicy.allow
    for delegate in delegates {
      // 解决模糊的委托签名问题: https://github.com/apple/swift/issues/45652#issuecomment-1149235081
      typealias WKNavigationResponseSignature = (WKNavigationDelegate) -> ((WKWebView, WKNavigationResponse, @escaping (WKNavigationResponsePolicy) -> Void) -> Void)?
      
      // 检测异步实现是否存在，因为我们不能直接检测它们
      if delegate.responds(to: #selector(WKNavigationDelegate.webView(_:decidePolicyFor:decisionHandler:) as WKNavigationResponseSignature)) {
        // 不要更改为 `delegate.webView?(....)`，在当前时间写作 `2023年1月10日`，可选运算符会导致异步调用使编译器崩溃！
        // 必须在写作时进行强制解包。
        let policy = await delegate.webView!(webView, decidePolicyFor: navigationResponse)
        if policy == .cancel {
          res = policy
        }
        
        if policy == .download {
          res = policy
        }
      }
    }

    if res == .allow {
      let tab = tabManager?[webView]
      tab?.mimeType = navigationResponse.response.mimeType
    }
    
    return res
  }
  
  @MainActor
  // 导航动作变为下载
  public func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
    for delegate in delegates {
      delegate.webView?(webView, navigationAction: navigationAction, didBecome: download)
      if download.delegate != nil {
        return
      }
    }
  }
  
  @MainActor
  // 导航响应变为下载
  public func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
    for delegate in delegates {
      delegate.webView?(webView, navigationResponse: navigationResponse, didBecome: download)
      if download.delegate != nil {
        return
      }
    }
  }
}
