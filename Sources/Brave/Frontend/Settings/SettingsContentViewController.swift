/* 该源代码形式受 Mozilla 公共许可证 2.0 版的条款约束。
 * 如果本文件未随此文件分发，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。 */

import Shared
import SnapKit
import UIKit
import WebKit
import BraveShared

// 默认超时时间
let DefaultTimeoutTimeInterval = 10.0  // 秒。我们将在实际使用中收集一些有关加载时间的遥测数据。

/**
 * 一个管理单个 Web 视图并提供返回到设置页面的方式的控制器。
 */
class SettingsContentViewController: UIViewController, WKNavigationDelegate {
  let interstitialBackgroundColor: UIColor
  var settingsTitle: NSAttributedString?
  var url: URL!
  var timer: Timer?

  // 是否已加载标志
  var isLoaded: Bool = false {
    didSet {
      if isLoaded {
        UIView.transition(
          from: interstitialView, to: webView,
          duration: 0.5,
          options: .transitionCrossDissolve,
          completion: { finished in
            self.interstitialView.removeFromSuperview()
            self.interstitialSpinnerView.stopAnimating()
          })
      }
    }
  }

  // 是否发生错误标志
  fileprivate var isError: Bool = false {
    didSet {
      if isError {
        interstitialErrorView.isHidden = false
        UIView.transition(
          from: interstitialSpinnerView, to: interstitialErrorView,
          duration: 0.5,
          options: .transitionCrossDissolve,
          completion: { finished in
            self.interstitialSpinnerView.removeFromSuperview()
            self.interstitialSpinnerView.stopAnimating()
          })
      }
    }
  }

  // 在后台 Web 视图加载内容时显示的视图
  fileprivate var interstitialView: UIView!
  fileprivate var interstitialSpinnerView: UIActivityIndicatorView!
  fileprivate var interstitialErrorView: UILabel!

  // 显示内容的 Web 视图
  var webView: BraveWebView!

  // 开始加载内容
  fileprivate func startLoading(_ timeout: Double = DefaultTimeoutTimeInterval) {
    if self.isLoaded {
      return
    }
    if timeout > 0 {
      self.timer = Timer.scheduledTimer(timeInterval: timeout, target: self, selector: #selector(didTimeOut), userInfo: nil, repeats: false)
    } else {
      self.timer = nil
    }
    self.webView.load(PrivilegedRequest(url: url) as URLRequest)
    self.interstitialSpinnerView.startAnimating()
  }

  init(backgroundColor: UIColor = UIColor.white, title: NSAttributedString? = nil) {
    interstitialBackgroundColor = backgroundColor
    settingsTitle = title
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    // 此背景与网页背景一致。
    // 保持背景不变可防止颜色不匹配的弹出效果。
    view.backgroundColor = interstitialBackgroundColor

    self.webView = makeWebView()
    view.addSubview(webView)
    self.webView.snp.remakeConstraints { make in
      make.edges.equalTo(self.view)
    }

    // 解构 let 会导致问题。
    let ret = makeInterstitialViews()
    self.interstitialView = ret.0
    self.interstitialSpinnerView = ret.1
    self.interstitialErrorView = ret.2
    view.addSubview(interstitialView)
    self.interstitialView.snp.remakeConstraints { make in
      make.edges.equalTo(self.view)
    }

    startLoading()
  }

  // 创建 WebView
  func makeWebView() -> BraveWebView {
    let frame = CGRect(width: 1, height: 1)
    let configuration = WKWebViewConfiguration().then {
      $0.setURLSchemeHandler(InternalSchemeHandler(), forURLScheme: InternalURL.scheme)
    }
    let webView = BraveWebView(frame: frame, configuration: configuration)
    webView.allowsLinkPreview = false
    webView.navigationDelegate = self
    return webView
  }

  // 创建加载中的视图
  fileprivate func makeInterstitialViews() -> (UIView, UIActivityIndicatorView, UILabel) {
    let view = UIView()

    // 保持背景不变可防止颜色不匹配的弹出效果。
    view.backgroundColor = interstitialBackgroundColor

    let spinner = UIActivityIndicatorView(style: .medium)
    view.addSubview(spinner)

    let error = UILabel()
    if let _ = settingsTitle {
      error.text = Strings.settingsContentLoadErrorMessage
      error.textColor = .braveErrorLabel
      error.textAlignment = .center
    }
    error.isHidden = true
    view.addSubview(error)

    spinner.snp.makeConstraints { make in
      make.center.equalTo(view)
      return
    }

    error.snp.makeConstraints { make in
      make.center.equalTo(view)
      make.left.equalTo(view.snp.left).offset(20)
      make.right.equalTo(view.snp.right).offset(-20)
      make.height.equalTo(44)
      return
    }

    return (view, spinner, error)
  }

  // 超时处理方法
  @objc func didTimeOut() {
    self.timer = nil
    self.isError = true
  }

  // WKNavigationDelegate 方法 - 加载失败
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    didTimeOut()
  }

  // WKNavigationDelegate 方法 - 加载失败
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    didTimeOut()
  }

  // WKNavigationDelegate 方法 - 加载完成
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    self.timer?.invalidate()
    self.timer = nil
    self.isLoaded = true
  }
}
