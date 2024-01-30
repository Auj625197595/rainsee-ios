// 版权声明，该源代码受 Mozilla Public License, v. 2.0 许可的条款约束
// 如果未随此文件分发MPL的副本，您可以在 http://mozilla.org/MPL/2.0/ 获取一份副本。

import UIKit
import SnapKit
import DesignSystem

/// 非交互内容，出现在新标签页内容之后的背景视图
class NewTabPageBackgroundView: UIView {
  /// 如果用户启用了背景图片，则为图像壁纸
  let imageView = UIImageView().then {
    $0.contentMode = .scaleAspectFill
    $0.clipsToBounds = false
  }
  
  /// 根据X轴偏移更新图像位置
  func updateImageXOffset(by x: CGFloat) {
    bounds = .init(x: -x, y: 0, width: bounds.width, height: bounds.height)
  }

  override init(frame: CGRect) {
    super.init(frame: frame)

    clipsToBounds = true
    backgroundColor = .init {
      if $0.userInterfaceStyle == .dark {
        return .secondaryBraveBackground
      }
      // 当没有背景时，我们在这里使用特殊颜色，因为喜爱的单元格有白色文本
        
        return .white
      //return .init(rgb: 0x3b3e4f)
    }

    addSubview(imageView)
    imageView.snp.makeConstraints {
      $0.edges.equalToSuperview()
    }
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }
}
