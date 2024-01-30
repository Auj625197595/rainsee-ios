// 版权 © 2020 Brave 作者。保留所有权利。
// 本源代码形式受 Mozilla Public 许可证 v. 2.0 的条款约束。
// 如果未随此文件分发 MPL 的副本，则您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import BraveUI
import UIKit

/// 一个自动调整大小的新标签集合视图单元格，只包含一个可主题化的视图
class NewTabCollectionViewCell<View: UIView>: UICollectionViewCell, CollectionViewReusable {
  
  /// 内容视图
  let view = View()

  override init(frame: CGRect) {
    super.init(frame: frame)
    
    // 在内容视图中添加子视图
    contentView.addSubview(view)
    
    // 使用 SnapKit 设置约束
    view.snp.makeConstraints {
      $0.edges.equalToSuperview()
    }
  }

  // 不可用的初始化方法
  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }

  // 在布局属性拟合时调用，以返回适合的布局属性
  override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
    let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
    
    // 根据视图的系统布局大小和拟合优先级设置大小
    attributes.size = view.systemLayoutSizeFitting(layoutAttributes.size, withHorizontalFittingPriority: .fittingSizeLevel, verticalFittingPriority: .fittingSizeLevel)
    
    return attributes
  }
}
