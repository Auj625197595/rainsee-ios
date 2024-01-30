// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import Preferences
import BraveUI
import UIKit
import BraveCore

/// 用于给定新标签页的当前背景的类。
///
/// 该类负责为新标签页提供背景图像，并根据来自NTP外部的更改（例如用户在查看新标签页时更改私人模式或禁用背景图像偏好设置）更改背景。
class NewTabPageBackground: PreferencesObserver {
  /// 新标签页背景图像的来源
  private let dataSource: NTPDataSource
  /// 当前背景图像和可能的赞助商
  private(set) var currentBackground: NTPWallpaper? {
    didSet {
      wallpaperId = UUID()
      changed?()
    }
  }
  /// 唯一的壁纸标识符
  private(set) var wallpaperId = UUID()
  /// 如果可用，背景/壁纸图像
  var backgroundImage: UIImage? {
    currentBackground?.backgroundImage
  }
  /// 如果可用，赞助商的标志
  var sponsorLogoImage: UIImage? {
    currentBackground?.logoImage
  }
  /// 当前背景图像/赞助商标志更改时调用的块，当新标签页处于活动状态时
  var changed: (() -> Void)?
  /// 给定所有NTP背景图像的来源，创建一个背景持有者
  init(dataSource: NTPDataSource) {
    self.dataSource = dataSource
    self.currentBackground = dataSource.newBackground()

    Preferences.NewTabPage.backgroundImages.observe(from: self)
    Preferences.NewTabPage.backgroundSponsoredImages.observe(from: self)
    Preferences.NewTabPage.selectedCustomTheme.observe(from: self)
    
    recordSponsoredImagesEnabledP3A()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private var timer: Timer?

  func preferencesDidChange(for key: String) {
    // 防抖动多次更改首选项，因为切换背景图像会导致同时切换赞助商图像
    timer?.invalidate()
    timer = Timer.scheduledTimer(
      withTimeInterval: 0.25, repeats: false,
      block: { [weak self] _ in
        guard let self = self else { return }
        self.currentBackground = self.dataSource.newBackground()
        self.recordSponsoredImagesEnabledP3A()
      })
  }
  
  private func recordSponsoredImagesEnabledP3A() {
    // Q26 赞助商新标签页选项是否已启用？
    let isSIEnabled = Preferences.NewTabPage.backgroundImages.value &&
      Preferences.NewTabPage.backgroundSponsoredImages.value
    UmaHistogramBoolean("Brave.NTP.SponsoredImagesEnabled", isSIEnabled)
  }
}
