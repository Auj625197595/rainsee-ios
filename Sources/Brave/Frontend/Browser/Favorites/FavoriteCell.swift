/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared
import BraveShared
import BraveUI

// 定义 FavoriteCellDelegate 协议，用于通知委托对象编辑收藏
@objc protocol FavoriteCellDelegate {
  func editFavorite(_ favoriteCell: FavoriteCell)
}

// 收藏单元格类，继承自 UICollectionViewCell，并采用 CollectionViewReusable 协议
class FavoriteCell: UICollectionViewCell, CollectionViewReusable {
  
  // 静态属性，用于指定图像宽高比
  static let imageAspectRatio: Float = 1.0
  // 静态属性，用于指定占位图像
  static let placeholderImage = UIImage(named: "defaultTopSiteIcon", in: .module, compatibleWith: nil)!
  // 静态属性，用于指定单元格标识符
  static let identifier = "FavoriteCell"

  // UI 相关的常量定义
  private struct UI {
    static let cornerRadius: CGFloat = 8  // 图片圆角半径
    static let spacing: CGFloat = 8  // 视图之间的间距
    static let labelAlignment: NSTextAlignment = .center  // 文本标签的对齐方式
  }

  // 弱引用委托对象
  weak var delegate: FavoriteCellDelegate?

  // 图像和单元格的内边距
  var imageInsets: UIEdgeInsets = UIEdgeInsets.zero
  var cellInsets: UIEdgeInsets = UIEdgeInsets.zero

  // 文本标签
  let textLabel = UILabel().then {
    $0.setContentHuggingPriority(UILayoutPriority.defaultHigh, for: NSLayoutConstraint.Axis.vertical)
    $0.font = DynamicFontHelper.defaultHelper.DefaultSmallFont
    $0.textAlignment = UI.labelAlignment
    $0.numberOfLines = 1
  }

  // 图片视图
  let imageView = LargeFaviconView()

  // 是否高亮状态，用于响应用户的点击效果
  override var isHighlighted: Bool {
    didSet {
      UIView.animate(
        withDuration: 0.25, delay: 0, options: [.beginFromCurrentState],
        animations: {
          self.imageView.alpha = self.isHighlighted ? 0.7 : 1.0
        })
    }
  }

  // 垂直堆栈视图，用于排列图像和文本
  let stackView = UIStackView().then {
    $0.axis = .vertical
    $0.spacing = UI.spacing
    $0.alignment = .center
    $0.isUserInteractionEnabled = false
  }

  // 初始化方法
  override init(frame: CGRect) {
    super.init(frame: frame)

    isAccessibilityElement = true

    // 将堆栈视图添加到内容视图中
    contentView.addSubview(stackView)
    // 在堆栈视图中添加图像和文本
    stackView.addArrangedSubview(imageView)
    stackView.addArrangedSubview(textLabel)

    // 设置图像视图的约束
    imageView.snp.makeConstraints {
      $0.height.equalTo(imageView.snp.width)
      $0.leading.trailing.equalToSuperview().inset(12)
    }
    // 设置堆栈视图的约束
    stackView.snp.makeConstraints {
      $0.top.leading.trailing.equalToSuperview()
      $0.bottom.lessThanOrEqualToSuperview()
    }

    // 防止文本标签在优先级较高的情况下被压缩
    textLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

    // 添加 UIPointerInteraction 以响应鼠标悬停效果
    addInteraction(UIPointerInteraction(delegate: self))
  }

  // 析构方法，用于移除通知观察者
  deinit {
    NotificationCenter.default.removeObserver(self, name: .thumbnailEditOn, object: nil)
    NotificationCenter.default.removeObserver(self, name: .thumbnailEditOff, object: nil)
  }

  // 必要的初始化方法，不使用 storyboard 进行初始化时会调用
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // 准备重用，设置背景色为空
  override func prepareForReuse() {
    super.prepareForReuse()
    backgroundColor = .clear
  }

  // 指定单元格布局属性的方法，用于自定义单元格的布局
  override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
    // 单元格的大小在单元格外部确定，直接返回传入的布局属性
    return layoutAttributes
  }

  // 计算单元格高度的静态方法
  static func height(forWidth width: CGFloat) -> CGFloat {
    let imageHeight = (width - 24)
    let labelHeight = (DynamicFontHelper.defaultHelper.DefaultSmallFont.lineHeight * 2)
    return ceil(imageHeight + UI.spacing + labelHeight)
  }
}

// 扩展 FavoriteCell，实现 UIPointerInteractionDelegate 协议
extension FavoriteCell: UIPointerInteractionDelegate {
  // UIPointerInteractionDelegate 协议方法，用于指定鼠标悬停时的样式
  func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
    let preview = UITargetedPreview(view: imageView)
    return UIPointerStyle(effect: .lift(preview))
  }
}
