// 该源代码受 Mozilla Public License，版本 2.0 的条款约束。
// 如果未随此文件分发 MPL 的副本，则可以在 http://mozilla.org/MPL/2.0/ 处获取一份。

import UIKit

class IndentedImageTableViewCell: UITableViewCell {
  
  // 主要的 StackView，用于容纳图像和文件夹名称的垂直排列
  private let mainStackView = UIStackView().then {
    $0.spacing = 8
    $0.alignment = .fill
  }

  // 用于容纳文件夹名称的垂直 StackView
  private let folderNameStackView = UIStackView().then {
    $0.axis = .vertical
    $0.distribution = .equalSpacing
  }

  // 自定义图像视图
  let customImage = UIImageView().then {
    $0.image = UIImage(named: "shields-menu-icon", in: .module, compatibleWith: nil)!
    $0.tintColor = .braveLabel
    $0.contentMode = .scaleAspectFit
    $0.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    $0.setContentHuggingPriority(.defaultHigh, for: .horizontal)
  }

  // 文件夹名称标签
  let folderName = UILabel().then {
    $0.textAlignment = .left
    $0.textColor = .braveLabel
  }

  // 初始化方法，接受一个图像参数
  convenience init(image: UIImage) {
    self.init(style: .default, reuseIdentifier: nil)

    customImage.image = image
  }

  // 初始化方法，指定样式和可重用标识符
  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)

    // 缩进宽度
    indentationWidth = 20
    mainStackView.addArrangedSubview(customImage)

    // 创建透明的分隔线
    let transparentLine = UIView.separatorLine
    transparentLine.backgroundColor = .clear

    // 将透明线、文件夹名称标签和另一条分隔线添加到文件夹名称 StackView 中
    [transparentLine, folderName, UIView.separatorLine].forEach(folderNameStackView.addArrangedSubview)

    // 将文件夹名称 StackView 添加到主 StackView 中
    mainStackView.addArrangedSubview(folderNameStackView)

    // 隐藏 UITableViewCells 的分隔线，将使用自定义的分隔线。
    // 根据缩进更新此分隔线插入会有问题。
    separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: .greatestFiniteMagnitude)

    addSubview(mainStackView)

    // 设置主 StackView 的约束
    mainStackView.snp.makeConstraints {
      $0.top.bottom.equalTo(self)
      $0.leading.trailing.equalTo(self).inset(8)
      $0.centerY.equalTo(self)
    }
  }

  // 必需的初始化方法，使用 NSCoder 进行解码
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // 在视图布局发生更改时调用，用于更新主 StackView 的约束
  override func layoutSubviews() {
    super.layoutSubviews()
    let indentation = (CGFloat(indentationLevel) * indentationWidth)

    mainStackView.snp.remakeConstraints {
      $0.leading.equalTo(self).inset(indentation + 8)
      $0.top.bottom.equalTo(self)
      $0.trailing.equalTo(self).inset(8)
      $0.centerY.equalTo(self)
    }
  }
}
