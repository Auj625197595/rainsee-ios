// 版权 2020 年 Brave 作者。保留所有权利。
// 此源代码表单受 Mozilla Public License，v. 2.0 的条款约束。
// 如果未随此文件分发 MPL 的副本，可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import BraveCore
import BraveShared

class NewTabPageNotifications {
  /// 不同类型的通知可呈现给用户。
  enum NotificationType {
    /// 通知用户有关品牌图像计划的信息。
    case brandedImages(state: BrandedImageCalloutState)
  }

  private let rewards: BraveRewards

  init(rewards: BraveRewards) {
    self.rewards = rewards
  }

  /// 决定要显示的通知类型。
  func notificationToShow(
    isShowingBackgroundImage: Bool,
    isShowingSponseredImage: Bool
  ) -> NotificationType? {
    // 如果不显示背景图像，则返回 nil。
    if !isShowingBackgroundImage {
      return nil
    }

    // 获取品牌图像状态。
    let state = BrandedImageCalloutState.getState(
      adsEnabled: rewards.ads.isEnabled,
      adsAvailableInRegion: BraveAds.isSupportedRegion(),
      isSponsoredImage: isShowingSponseredImage
    )
    
    // 返回品牌图像通知类型。
    return .brandedImages(state: state)
  }
}
