import BraveUI
import Foundation
import UIKit

/// 一个自动调整大小的新标签集合视图单元格，只包含一个可主题化的视图
class IconSearchCell<View: IconSearchView>: UICollectionViewCell, CollectionViewReusable  {
    /// 内容视图
    let view = View()
    
    var action: (() -> Void)?
    
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
