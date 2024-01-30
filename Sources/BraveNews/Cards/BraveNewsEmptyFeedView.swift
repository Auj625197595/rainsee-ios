// 版权声明
// 版权所有 2020 年 Brave 作者。保留所有权利。
// 此源代码形式受 Mozilla Public License, v. 2.0 条款的约束。
// 如果没有随此文件分发 MPL 的副本，
// 您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import BraveUI
import BraveShared
import Shared
import UIKit

// BraveNewsEmptyFeedView 类，继承自 UIView，并遵循 FeedCardContent 协议
public class BraveNewsEmptyFeedView: UIView, FeedCardContent {

  // 点击源和设置按钮的回调闭包
  public var sourcesAndSettingsButtonTapped: (() -> Void)?

  // 背景视图
  private let backgroundView = FeedCardBackgroundView()

  // 垂直堆栈视图
  private let stackView = UIStackView().then {
    $0.axis = .vertical
    $0.alignment = .center
    $0.spacing = 8
  }

  // 源和设置按钮
  private let sourcesAndSettingsButton = ActionButton(type: .system).then {
    $0.layer.borderWidth = 0
    $0.titleLabel?.font = .systemFont(ofSize: 16.0, weight: .semibold)
    $0.setTitle(Strings.BraveNews.sourcesAndSettings, for: .normal)
    $0.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
    $0.backgroundColor = UIColor.white.withAlphaComponent(0.2)
  }

  // 标题标签
  private let titleLabel = UILabel().then {
    $0.textAlignment = .center
    $0.textColor = .white
    $0.font = .systemFont(ofSize: 22, weight: .semibold)
    $0.numberOfLines = 0
    $0.text = Strings.BraveNews.emptyFeedTitle
  }

  // 消息标签
  private let messageLabel = UILabel().then {
    $0.textAlignment = .center
    $0.textColor = .white
    $0.font = .systemFont(ofSize: 16)
    $0.numberOfLines = 0
    $0.text = Strings.BraveNews.emptyFeedBody
  }

  // 初始化方法
  public required init() {
    super.init(frame: .zero)

    // 添加背景视图和堆栈视图到当前视图
    addSubview(backgroundView)
    addSubview(stackView)

    // 设置约束
    backgroundView.snp.makeConstraints {
      $0.edges.equalToSuperview()
    }
    stackView.snp.makeConstraints {
      $0.edges.equalToSuperview().inset(24)
    }

    // 向堆栈视图添加子视图
    stackView.addStackViewItems(
      .view(UIImageView(image: UIImage(named: "brave-today-error", in: .module, compatibleWith: nil)!)),
      .customSpace(16),
      .view(titleLabel),
      .view(messageLabel),
      .customSpace(20),
      .view(sourcesAndSettingsButton)
    )

    // 设置源和设置按钮的点击事件
    sourcesAndSettingsButton.addTarget(self, action: #selector(tappedSettingsButton), for: .touchUpInside)
  }

  // 不可用的初始化方法
  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }

  // 源和设置按钮的点击事件处理方法
  @objc private func tappedSettingsButton() {
    sourcesAndSettingsButtonTapped?()
  }

  // 未使用的属性和方法
  public var actionHandler: ((Int, FeedItemAction) -> Void)?
  public var contextMenu: FeedItemMenu?
}
