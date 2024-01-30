// 此源代码受 Mozilla 公共许可证 v. 2.0 条款约束。
// 如果此文件未分发 MPL 副本，可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import UIKit

extension UITraitCollection {
  /// 根据当前首选大小类别返回用于工具栏按钮的大小类别
  var toolbarButtonContentSizeCategory: UIContentSizeCategory {
    let sizeCategory = preferredContentSizeCategory
    if sizeCategory < UIContentSizeCategory.extraLarge {
      return .large
    } else if sizeCategory < UIContentSizeCategory.extraExtraLarge {
      return .extraLarge
    }
    return .extraExtraLarge
  }
}

class ToolbarButton: UIButton {
  // 选中状态下的着色
  var selectedTintColor: UIColor? {
    didSet {
      updateTintColor()
    }
  }
  // 主要状态下的着色
  var primaryTintColor: UIColor? {
    didSet {
      updateTintColor()
    }
  }
  // 禁用状态下的着色
  var disabledTintColor: UIColor? {
    didSet {
      updateTintColor()
    }
  }

  // 初始化方法
  init() {
    super.init(frame: .zero)
    adjustsImageWhenHighlighted = false
    imageView?.contentMode = .scaleAspectFit
  }
  
  // 不可用的初始化方法
  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }

  // 按钮是否高亮
  override open var isHighlighted: Bool {
    didSet {
      updateTintColor()
    }
  }

  // 按钮是否启用
  override open var isEnabled: Bool {
    didSet {
      updateTintColor()
    }
  }

  // 设置按钮着色
  override var tintColor: UIColor! {
    didSet {
      self.imageView?.tintColor = self.tintColor
    }
  }
  
  // 更新按钮着色
  private func updateTintColor() {
    let tintColor: UIColor? = {
      if !isEnabled {
        if let disabledTintColor {
          return disabledTintColor
        } else {
          return primaryTintColor?.withAlphaComponent(0.4)
        }
      }
      if isHighlighted {
        return selectedTintColor
      }
      return primaryTintColor
    }()
    self.tintColor = tintColor
  }

  // 显示上下文菜单时的反馈振动
  override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
    UIImpactFeedbackGenerator(style: .medium).bzzt()
  }
}
