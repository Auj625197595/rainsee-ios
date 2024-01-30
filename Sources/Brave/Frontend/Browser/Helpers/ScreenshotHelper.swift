/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Shared
import UIKit
import os.log

/**
 * Handles screenshots for a given tab, including pages with non-webview content.
 */
class ScreenshotHelper {
  var viewIsVisible = false

  fileprivate weak var tabManager: TabManager?

  init(tabManager: TabManager) {
    self.tabManager = tabManager
  }

    /// 在给定的选项卡上进行截图。
    ///
    /// - Parameter tab: 要截图的选项卡（Tab）。
    func takeScreenshot(_ tab: Tab) {
        // 确保选项卡的 webView 和 url 不为空
        guard let webView = tab.webView, let url = tab.url else {
            Logger.module.error("选项卡的 webView 或 url 为空")
            tab.setScreenshot(nil)
            return
        }

        // 如果是关于主页的 URL
        if InternalURL(url)?.isAboutHomeURL == true {
            // 如果有主页面板
            if let homePanel = tabManager?.selectedTab?.newTabPageViewController {
                // 对主页面板进行截图
                let screenshot = homePanel.view.screenshot(quality: UIConstants.activeScreenshotQuality)
                tab.setScreenshot(screenshot)
            } else {
                // 如果没有主页面板，将截图设为 nil
                tab.setScreenshot(nil)
            }
        } else {
            // 对 webView 进行截图配置
            let configuration = WKSnapshotConfiguration()
            // 修复某些 iOS 13 版本中的 bug，设置这个布尔值为 false 可以解决截图问题
            configuration.afterScreenUpdates = false

            // 使用 webView 进行截图
            webView.takeSnapshot(with: configuration) { [weak tab] image, error in
                if let image = image {
                    // 成功获取到截图，设置截图
                    tab?.setScreenshot(image)
                } else if let error = error {
                    // 获取截图失败，记录错误信息并将截图设为 nil
                    Logger.module.error("\(error.localizedDescription)")
                    tab?.setScreenshot(nil)
                } else {
                    // 获取截图失败，没有错误描述，记录错误信息并将截图设为 nil
                    Logger.module.error("无法截图 - 没有错误描述")
                    tab?.setScreenshot(nil)
                }
            }
        }
    }


    /// 在经过短暂延迟后进行截图。
    /// 尝试在 didFinishNavigation 后立即截图会导致获取到前一页的截图，可能是由于 iOS 的一个 bug 引起的。通过添加一个短暂的延迟来解决这个问题。
    ///
    /// - Parameter tab: 要截图的选项卡（Tab）。
    func takeDelayedScreenshot(_ tab: Tab) {
        // 延迟 100 毫秒后执行
        let time = DispatchTime.now() + Double(Int64(100 * NSEC_PER_MSEC)) / Double(NSEC_PER_SEC)
        DispatchQueue.main.asyncAfter(deadline: time) {
            // 如果视图控制器不可见，截图将为空白。
            // 等待视图控制器再次可见以进行截图。
            guard self.viewIsVisible else {
                // 如果视图控制器不可见，将标记选项卡为待截图状态
                tab.pendingScreenshot = true
                return
            }

            // 进行截图
            self.takeScreenshot(tab)
        }
    }


  func takePendingScreenshots(_ tabs: [Tab]) {
    for tab in tabs where tab.pendingScreenshot {
      tab.pendingScreenshot = false
      takeDelayedScreenshot(tab)
    }
  }
}
