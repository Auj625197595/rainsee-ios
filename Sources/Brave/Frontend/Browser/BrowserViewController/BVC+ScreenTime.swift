// Copyright 2023 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import Preferences

extension BrowserViewController {
    /// 更新屏幕时间控制器的URL。请注意，每个窗口都使用单个屏幕时间控制器。
    /// 多个实例似乎会导致应用崩溃。
    /// 还有一个必须的技巧：如果传递的方案不是http或https，则STWebpageController会中断，
    /// 它在其余生命周期内不会阻止任何内容。我们的内部URL必须桥接到一个空的https URL。
    func updateScreenTimeUrl(_ url: URL?) {
        guard let screenTimeViewController = screenTimeViewController else {
            return
        }
        
        // 如果URL为空或方案不是http或https，则执行以下代码块
        guard let url = url, (url.scheme == "http" || url.scheme == "https") else {
            // 这比从屏幕上移除视图控制器要好得多！
            // 如果我们使用`nil`，那么STViewController将永久进入损坏状态，直到应用程序重新启动
            // URL不能是nil，也不能是除了http(s)之外的任何其他东西，否则它将在整个应用程序运行期间中断。
            // Chromium通过不设置URL来解决此问题，而是将其从视图中完全移除。
            // 但将URL设置为空URL也是有效的。
            screenTimeViewController.url = NSURL() as URL
            return
        }
        
        // 将URL设置为传递的非空URL
        screenTimeViewController.url = url
    }

  
  func recordScreenTimeUsage(for tab: Tab) {
    screenTimeViewController?.suppressUsageRecording = tab.isPrivate || !Preferences.Privacy.screenTimeEnabled.value
  }
}
