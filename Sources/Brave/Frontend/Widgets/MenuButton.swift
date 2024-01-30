// 版权所有 2021 年 Brave 作者。保留所有权利。
// 此源代码表单受 Mozilla Public License，版本 2.0 的条款约束。
// 如果未随此文件分发 MPL 的副本，则可以在 http://mozilla.org/MPL/2.0/ 处获得一份。

import Foundation
import UIKit
import DesignSystem

/// 显示更多图标 (`•••`) 和一组徽章的按钮
class MenuButton: ToolbarButton {
  /// 可以添加到菜单图标的徽章
  struct Badge: Hashable {
    var gradientView: () -> BraveGradientView  // 徽章的渐变视图
    var icon: UIImage?  // 徽章图标

    func hash(into hasher: inout Hasher) {
      hasher.combine(icon)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
      return lhs.icon == rhs.icon
    }

    static let playlist: Self = .init(
      gradientView: { .gradient02 },
      icon: UIImage(named: "playlist-menu-badge", in: .module, compatibleWith: nil)?.withTintColor(.white)
    )
  }

  private(set) var badges: [Badge: UIView] = [:]  // 存储徽章及其对应的视图

  // 设置徽章
  func setBadges(_ badges: [Badge]) {
    badges.forEach { [self] in
      addBadge($0, animated: false)
    }
  }

  // 添加徽章
  func addBadge(_ badge: Badge, animated: Bool) {
    if badges[badge] != nil {
      // 徽章已经存在
      return
    }

    guard let imageView = imageView else { return }

    let view = BadgeView(badge: badge)
    badges[badge] = view
    addSubview(view)
    if badges.count > 1 {
      // TODO: 所有徽章变为仅背景
    } else {
      view.snp.makeConstraints {
        $0.centerY.equalTo(imageView.snp.top)
        $0.centerX.equalTo(imageView.snp.trailing)
        $0.size.equalTo(13)
      }
      if animated {
        view.transform = CGAffineTransform(scaleX: 0.0001, y: 0.0001)
        UIViewPropertyAnimator(duration: 0.4, dampingRatio: 0.6) {
          view.transform = .identity
        }
        .startAnimation()
      }
    }
  }

  // 移除徽章
  func removeBadge(_ badge: Badge, animated: Bool) {
    let view = badges[badge]
    badges[badge] = nil
    if let view = view {
      if animated {
        let animator = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 1.0) {
          view.transform = CGAffineTransform(scaleX: 0.0001, y: 0.0001)
        }
        animator.addCompletion { _ in
          view.removeFromSuperview()
        }
        animator.startAnimation()
      } else {
        view.removeFromSuperview()
      }
    }
  }

  private class BadgeView: UIView {
    let badge: Badge
    var contentView: UIView?

    init(badge: Badge) {
      self.badge = badge
      super.init(frame: .zero)
      clipsToBounds = true

      snp.makeConstraints {
        $0.width.greaterThanOrEqualTo(snp.height)
      }

      let backgroundView = badge.gradientView()
      addSubview(backgroundView)
      backgroundView.snp.makeConstraints {
        $0.edges.equalToSuperview()
      }

      if let image = badge.icon {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .center
        addSubview(imageView)
        imageView.snp.makeConstraints {
          $0.edges.equalToSuperview().inset(1)
        }
        contentView = imageView
      }
    }
    @available(*, unavailable)
    required init(coder: NSCoder) {
      fatalError()
    }
    override func layoutSubviews() {
      super.layoutSubviews()
      layer.cornerRadius = bounds.height / 2.0
    }
  }
}
