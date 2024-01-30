// 此源代码形式受 Mozilla Public License, v. 2.0 的条款约束。
// 如果没有随此文件分发的 MPL 副本，可以在 http://mozilla.org/MPL/2.0/ 处获得一份。

import Foundation
import Storage
import BraveUI
import SnapKit
import UIKit

/// 定义基本的动态卡片单元格。动态卡片可以显示1个或多个动态项。此单元格由 `View` 类型定义。
public class FeedCardCell<Content: FeedCardContent>: UICollectionViewCell, CollectionViewReusable {
  public var content = Content()
  private var widthConstraint: Constraint?

  public override init(frame: CGRect) {
    super.init(frame: frame)

    // 将内容视图添加到单元格的内容视图中
    contentView.addSubview(content.view)
    content.view.snp.makeConstraints {
      // 设置内容视图的约束：顶部、底部与父视图相等，宽度为375
      $0.top.bottom.equalToSuperview()
      widthConstraint = $0.width.equalTo(375).constraint
      $0.centerX.equalToSuperview()
    }
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }

  public override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
    // swiftlint:disable:next force_cast
    // 复制布局属性
    let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
    // 让 iPad 上的卡片稍大，因为有更多的空间
    if traitCollection.horizontalSizeClass == .regular {
      widthConstraint?.update(offset: min(600, attributes.size.width))
    } else {
      widthConstraint?.update(offset: min(400, attributes.size.width))
    }
    // 计算布局适应的大小
    attributes.size.height =
      systemLayoutSizeFitting(
        UIView.layoutFittingCompressedSize,
        withHorizontalFittingPriority: .required,
        verticalFittingPriority: .fittingSizeLevel
      ).height
    return attributes
  }
}
