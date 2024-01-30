// 版权所有 2020 Brave 作者。保留所有权利。
// 此源代码表单受 Mozilla Public License，版本 2.0 的条款约束。
// 如果未随此文件分发 MPL 的副本，则可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import BraveUI
import UIKit

/// 一个新标签集合视图单元格，其中视图水平居中且可主题化。
class NewTabCenteredCollectionViewCell<View: UIView>: UICollectionViewCell, CollectionViewReusable {
  /// 内容视图
  let view = View()

  override init(frame: CGRect) {
    super.init(frame: frame)
    
    // 将视图添加到内容视图中
    contentView.addSubview(view)
    
    // 使用SnapKit库设置约束，使视图水平居中
    view.snp.remakeConstraints {
      $0.top.bottom.equalToSuperview()
      $0.centerX.equalToSuperview()
      $0.leading.greaterThanOrEqualToSuperview()
      $0.trailing.lessThanOrEqualToSuperview()
    }
  }

  // 必需的初始化方法，用于从 xib 或 storyboard 加载对象
  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }

  override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
    // swiftlint:disable:next force_cast
    // 复制布局属性以进行自适应布局
    let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
    
    // 使用系统自适应布局计算高度
    attributes.size.height = systemLayoutSizeFitting(layoutAttributes.size, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    
    return attributes
  }
}
