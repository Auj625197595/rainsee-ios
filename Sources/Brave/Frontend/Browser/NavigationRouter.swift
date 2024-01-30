/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import Preferences
import Intents
import BraveWidgetsModels

// Used by the App to navigate to different views.
// To open a URL use /open-url or to open a blank tab use /open-url with no params
public enum DeepLink: String {
  case vpnCrossPlatformPromo = "vpn_promo"
}

// The root navigation for the Router. Look at the tests to see a complete URL
public enum NavigationPath: Equatable {
  case url(webURL: URL?, isPrivate: Bool)
  case deepLink(DeepLink)
  case text(String)
  case widgetShortcutURL(WidgetShortcut)

  public init?(url: URL, isPrivateBrowsing: Bool) {
    let urlString = url.absoluteString
    if url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" {
      self = .url(webURL: url, isPrivate: isPrivateBrowsing)
      return
    }

    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }

    guard let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [AnyObject],
      let urlSchemes = urlTypes.first?["CFBundleURLSchemes"] as? [String]
    else {
      assertionFailure()
      return nil
    }

    guard let scheme = components.scheme, urlSchemes.contains(scheme) else {
      return nil
    }

    if urlString.starts(with: "\(scheme)://deep-link"), let deepURL = components.valueForQuery("path"), let link = DeepLink(rawValue: deepURL) {
      self = .deepLink(link)
    } else if urlString.starts(with: "\(scheme)://open-url") {
      let urlText = components.valueForQuery("url")
      let url = URIFixup.getURL(urlText ?? "") ?? urlText?.asURL
      let forcedPrivate = Preferences.Privacy.privateBrowsingOnly.value || isPrivateBrowsing
      let isPrivate = Bool(components.valueForQuery("private") ?? "") ?? forcedPrivate
      self = .url(webURL: url, isPrivate: isPrivate)
    } else if urlString.starts(with: "\(scheme)://open-text") {
      let text = components.valueForQuery("text")
      self = .text(text ?? "")
    } else if urlString.starts(with: "\(scheme)://search") {
      let text = components.valueForQuery("q")
      self = .text(text ?? "")
    } else if urlString.starts(with: "\(scheme)://shortcut"),
      let valueString = components.valueForQuery("path"),
      let value = WidgetShortcut.RawValue(valueString),
      let path = WidgetShortcut(rawValue: value) {
      self = .widgetShortcutURL(path)
    } else {
      return nil
    }
  }

  static func handle(nav: NavigationPath, with bvc: BrowserViewController) {
    switch nav {
    case .deepLink(let link): NavigationPath.handleDeepLink(link, with: bvc)
    case .url(let url, let isPrivate): NavigationPath.handleURL(url: url, isPrivate: isPrivate, with: bvc)
    case .text(let text): NavigationPath.handleText(text: text, with: bvc)
    case .widgetShortcutURL(let path): NavigationPath.handleWidgetShortcut(path, with: bvc)
    }
  }

  private static func handleDeepLink(_ link: DeepLink, with bvc: BrowserViewController) {
//    switch link {
//    case .vpnCrossPlatformPromo:
//      bvc.presentVPNInAppEventCallout()
//    }
  }

  private static func handleURL(url: URL?, isPrivate: Bool, with bvc: BrowserViewController) {
    if let newURL = url {
      bvc.switchToTabForURLOrOpen(newURL, isPrivate: isPrivate, isPrivileged: false, isExternal: true)
      bvc.popToBVC()
    } else {
      bvc.openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: isPrivate)
    }
  }

  private static func handleText(text: String, with bvc: BrowserViewController) {
    bvc.openBlankNewTab(
      attemptLocationFieldFocus: true,
      isPrivate: bvc.privateBrowsingManager.isPrivateBrowsing,
      searchFor: text)
  }

    private static func handleWidgetShortcut(_ path: WidgetShortcut, with bvc: BrowserViewController) {
        // 处理小部件快捷方式的不同情况
        switch path {
        case .unknown, .search:
            // 如果当前选定的标签页的URL是关于主页的URL，则聚焦URL栏
            if let url = bvc.tabManager.selectedTab?.url, InternalURL(url)?.isAboutHomeURL == true {
                bvc.focusURLBar()
            } else {
                // 否则，打开一个新的空白标签页，并尝试聚焦到位置字段
                bvc.openBlankNewTab(attemptLocationFieldFocus: true, isPrivate: bvc.privateBrowsingManager.isPrivateBrowsing)
            }
        case .newTab:
            // 打开一个新的空白标签页，不尝试聚焦到位置字段
            bvc.openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: bvc.privateBrowsingManager.isPrivateBrowsing)
        case .newPrivateTab:
            // 如果启用了密码锁，则打开一个新的空白标签页，并尝试聚焦到位置字段
            if Preferences.Privacy.lockWithPasscode.value {
                bvc.openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: true)
            } else {
                // 如果启用了隐私浏览锁，则请求本地身份验证
                if Preferences.Privacy.privateBrowsingLock.value {
                    bvc.askForLocalAuthentication(viewType: .external) { [weak bvc] success, _ in
                        if success {
                            bvc?.openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: true)
                        }
                    }
                } else {
                    // 否则，打开一个新的空白标签页，并尝试聚焦到位置字段
                    bvc.openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: true)
                }
            }
        case .bookmarks:
            // 打开书签
            bvc.navigationHelper.openBookmarks()
        case .history:
            // 打开历史记录
            bvc.navigationHelper.openHistory()
        case .downloads:
            // 打开下载页面，并在不成功时显示错误
            bvc.navigationHelper.openDownloads() { success in
                if !success {
                    bvc.displayOpenDownloadsError()
                }
            }
        case .playlist:
            // 打开播放列表
            bvc.navigationHelper.openPlaylist()
        case .wallet:
            // 打开钱包
           // bvc.navigationHelper.openWallet()
            break
        case .scanQRCode:
            // 扫描QR码
            bvc.scanQRCode()
        case .braveNews:
            // 打开一个新的空白标签页，并滚动到Brave新闻
            bvc.openBlankNewTab(attemptLocationFieldFocus: false, isPrivate: false, isExternal: true)
            bvc.popToBVC()
            // 获取当前选定标签页的新标签页控制器，滚动到Brave新闻
            guard let newTabPageController = bvc.tabManager.selectedTab?.newTabPageViewController else { return }
            newTabPageController.scrollToBraveNews()
        @unknown default:
            // 未知情况，断言失败
            assertionFailure()
            break
        }
    }

}
