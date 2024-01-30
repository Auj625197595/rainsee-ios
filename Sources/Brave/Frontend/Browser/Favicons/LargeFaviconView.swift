// 版权 2020 Brave Authors。保留所有权利。
// 此源代码形式受 Mozilla Public License, v. 2.0 的条款约束。
// 如果未随此文件分发MPL的副本，您可以在 http://mozilla.org/MPL/2.0/ 处获得一份。

import Foundation
import BraveShared
import Data
import UIKit
import Favicon

// FaviconUX 结构体，定义了用于 Favicon 视图的一些外观属性
struct FaviconUX {
  static let faviconBorderColor = UIColor(white: 0, alpha: 0.2)  // Favicon 边框颜色
  static let faviconBorderWidth = 1.0 / UIScreen.main.scale  // Favicon 边框宽度
}

/// 显示给定站点的大型 Favicon
class LargeFaviconView: UIView {
  // 加载 Favicon，接收站点 URL、是否为私密浏览以及备用字符（用于单色图标）
  func loadFavicon(siteURL: URL, isPrivateBrowsing: Bool, monogramFallbackCharacter: Character? = nil) {
    faviconTask?.cancel()  // 取消之前的任务，以确保不会同时加载多个 Favicon
    if let favicon = FaviconFetcher.getIconFromCache(for: siteURL) {
      faviconTask = nil
      
      self.imageView.image = favicon.image ?? Favicon.defaultImage
      self.backgroundColor = favicon.backgroundColor
      self.imageView.contentMode = .scaleAspectFit
      
      if let image = favicon.image {
        self.backgroundView.isHidden = !favicon.isMonogramImage && !image.hasTransparentEdges
      } else {
        self.backgroundView.isHidden = !favicon.hasTransparentBackground && !favicon.isMonogramImage
      }
      return
    }
    
    faviconTask = Task { @MainActor in
      let isPersistent = !isPrivateBrowsing
      do {
        // 通过 FaviconFetcher 异步加载 Favicon
        let favicon = try await FaviconFetcher.loadIcon(url: siteURL,
                                                        kind: .largeIcon,
                                                        persistent: isPersistent)
        
        self.imageView.image = favicon.image
        self.backgroundColor = favicon.backgroundColor
        self.imageView.contentMode = .scaleAspectFit
        
        if let image = favicon.image {
          self.backgroundView.isHidden = !favicon.isMonogramImage && !image.hasTransparentEdges
        } else {
          self.backgroundView.isHidden = !favicon.hasTransparentBackground && !favicon.isMonogramImage
        }
      } catch {
        // 加载失败时，显示默认图标
        self.imageView.image = Favicon.defaultImage
        self.backgroundColor = nil
        self.imageView.contentMode = .scaleAspectFit
        self.backgroundView.isHidden = false
      }
    }
  }

  // 取消加载 Favicon 的任务
  func cancelLoading() {
    faviconTask?.cancel()
    faviconTask = nil
    imageView.image = nil
    imageView.contentMode = .scaleAspectFit
    backgroundColor = .clear
    layoutMargins = .zero
    backgroundView.isHidden = false
  }

  private var faviconTask: Task<Void, Error>?  // 异步加载 Favicon 的任务

  private let imageView = UIImageView().then {
    $0.contentMode = .scaleAspectFit
  }

  private let monogramFallbackLabel = UILabel().then {
    $0.textColor = .white
    $0.isHidden = true
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    if bounds.height > 0 {
      monogramFallbackLabel.font = .systemFont(ofSize: bounds.height / 2)
    }
  }

  private let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .regular)).then {
    $0.isHidden = true
  }

  // 初始化 Favicon 视图
  override init(frame: CGRect) {
    super.init(frame: frame)

    layer.cornerRadius = 6
    layer.cornerCurve = .continuous

    clipsToBounds = true
    layer.borderColor = FaviconUX.faviconBorderColor.cgColor
    layer.borderWidth = FaviconUX.faviconBorderWidth

    layoutMargins = .zero

    addSubview(backgroundView)
    addSubview(monogramFallbackLabel)
      
    addSubview(imageView)

    backgroundView.snp.makeConstraints {
      $0.edges.equalToSuperview()
    }

    imageView.snp.makeConstraints {
      $0.center.equalTo(self)
      $0.leading.top.greaterThanOrEqualTo(layoutMarginsGuide)
      $0.trailing.bottom.lessThanOrEqualTo(layoutMarginsGuide)
    }
    monogramFallbackLabel.snp.makeConstraints {
      $0.center.equalTo(self)
    }
  }

  // 不可用的初始化方法
  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }
}
