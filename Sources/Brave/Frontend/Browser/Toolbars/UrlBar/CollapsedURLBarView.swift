// 版权声明
// 2022年Brave作者保留所有权利。
// 此源代码表单受Mozilla Public License，版本2.0的条款约束。
// 如果未随此文件分发MPL，则可以在http://mozilla.org/MPL/2.0/上获取一份副本。

import Foundation
import UIKit
import BraveCore
import BraveStrings
import SnapKit

/// 一个显示标签的安全内容状态和滚动到页面时显示URL的视图
class CollapsedURLBarView: UIView {
  
  // 垂直排列的 UI 元素的堆栈视图
  private let stackView = UIStackView().then {
    $0.spacing = 4
    $0.isUserInteractionEnabled = false
    $0.alignment = .firstBaseline
  }
  
  // 显示安全内容状态的按钮
  private let secureContentStateView = UIButton().then {
    $0.tintAdjustmentMode = .normal
  }
  
  // 分隔线标签
  private let separatorLine = UILabel().then {
    $0.isUserInteractionEnabled = false
    $0.isAccessibilityElement = false
    $0.text = "–" // en dash
  }
  
  // 显示URL的标签
  private let urlLabel = UILabel().then {
    $0.font = .preferredFont(forTextStyle: .caption1)
    $0.textColor = .bravePrimary
    $0.lineBreakMode = .byTruncatingHead
    $0.numberOfLines = 1
    $0.textAlignment = .right
    $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
  }
  
  // 浏览器颜色设置，默认为标准颜色
  var browserColors: any BrowserColors = .standard {
    didSet {
      updateForTraitCollectionAndBrowserColors()
    }
  }
  
  // 是否使用底部栏，默认为false
  var isUsingBottomBar: Bool = false {
    didSet {
      setNeedsUpdateConstraints()
    }
  }
  
  // 更新锁定图像的显示
  private func updateLockImageView() {
    secureContentStateView.isHidden = !secureContentState.shouldDisplayWarning
    separatorLine.isHidden = secureContentStateView.isHidden
    secureContentStateView.configuration = secureContentStateButtonConfiguration
  }
  
  // 获取安全内容状态按钮的配置
  private var secureContentStateButtonConfiguration: UIButton.Configuration {
    let clampedTraitCollection = traitCollection.clampingSizeCategory(maximum: .accessibilityLarge)
    var configuration = UIButton.Configuration.plain()
    configuration.preferredSymbolConfigurationForImage = .init(font: .preferredFont(forTextStyle: .caption1, compatibleWith: clampedTraitCollection), scale: .small)
    configuration.buttonSize = .small
    configuration.imagePadding = 4
    configuration.contentInsets = .init(top: 0, leading: 0, bottom: 0, trailing: 0)
    
    var title = AttributedString(Strings.tabToolbarNotSecureTitle)
    title.font = .preferredFont(forTextStyle: .caption1, compatibleWith: clampedTraitCollection)
    
    let isTitleVisible = !traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    
    switch secureContentState {
    case .localhost, .secure:
      break
    case .invalidCert:
      configuration.baseForegroundColor = UIColor(braveSystemName: .systemfeedbackErrorIcon)
      if isTitleVisible {
        configuration.attributedTitle = title
      }
      configuration.image = UIImage(braveSystemNamed: "leo.warning.triangle-filled")
    case .missingSSL, .mixedContent:
      configuration.baseForegroundColor = UIColor(braveSystemName: .textTertiary)
      if isTitleVisible {
        configuration.attributedTitle = title
      }
      configuration.image = UIImage(braveSystemNamed: "leo.warning.triangle-filled")
    case .unknown:
      configuration.baseForegroundColor = UIColor(braveSystemName: .iconDefault)
      configuration.image = UIImage(braveSystemNamed: "leo.warning.circle-filled")
    }
    return configuration
  }
  
  // 标签的安全内容状态，默认为未知状态
  var secureContentState: TabSecureContentState = .unknown {
    didSet {
      updateLockImageView()
    }
  }
  
  // 当前的URL
  var currentURL: URL? {
    didSet {
      urlLabel.text = currentURL.map {
        URLFormatter.formatURLOrigin(forDisplayOmitSchemePathAndTrivialSubdomains: $0.absoluteString)
      }
    }
  }
  
  // 键盘是否可见，默认为false
  var isKeyboardVisible: Bool = false {
    didSet {
      setNeedsUpdateConstraints()
      updateConstraints()
    }
  }
  
  // 顶部和底部约束
  private var topConstraint: Constraint?
  private var bottomConstraint: Constraint?
  
  // 初始化方法
  override init(frame: CGRect) {
    super.init(frame: frame)
    
    isUserInteractionEnabled = false
    clipsToBounds = false
    
    addSubview(stackView)
    stackView.addArrangedSubview(secureContentStateView)
    stackView.addArrangedSubview(separatorLine)
    stackView.addArrangedSubview(urlLabel)
    
    stackView.snp.makeConstraints {
      topConstraint = $0.top.equalToSuperview().constraint
      bottomConstraint = $0.bottom.equalToSuperview().constraint
      $0.leading.greaterThanOrEqualToSuperview().inset(12)
      $0.trailing.lessThanOrEqualToSuperview().inset(12)
      $0.centerX.equalToSuperview()
    }
    
    secureContentStateView.configurationUpdateHandler = { [unowned self] button in
      button.configuration = secureContentStateButtonConfiguration
    }
    
    updateForTraitCollectionAndBrowserColors()
  }
  
  // 屏幕特性变化时的回调
  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    updateForTraitCollectionAndBrowserColors()
  }
  
  // 根据屏幕特性和浏览器颜色更新视图
  private func updateForTraitCollectionAndBrowserColors() {
    let clampedTraitCollection = traitCollection.clampingSizeCategory(maximum: .accessibilityLarge)
    urlLabel.font = .preferredFont(forTextStyle: .caption1, compatibleWith: clampedTraitCollection)
    urlLabel.textColor = browserColors.textPrimary
    separatorLine.font = urlLabel.font
    separatorLine.textColor = browserColors.dividerSubtle
  }
  
  // 视图移动到窗口时的回调
  override func didMoveToWindow() {
    super.didMoveToWindow()
    setNeedsUpdateConstraints()
  }
  
  // 更新约束
  override func updateConstraints() {
    super.updateConstraints()
    
      // 如果键盘可见且使用底部工具栏
      if isKeyboardVisible && isUsingBottomBar {
          // 更新底部和顶部约束，将其都设置为0
          bottomConstraint?.update(inset: 0)
          topConstraint?.update(inset: 0)
      } else {
          // 获取窗口的安全区域插图，如果没有则默认为零
          let safeAreaInset = window.map(\.safeAreaInsets) ?? .zero
          
          // 根据条件更新底部约束
          bottomConstraint?.update(inset: safeAreaInset.top > 0 && !isUsingBottomBar ? 4 : 0)
          
          // 根据条件更新顶部约束
          topConstraint?.update(inset: safeAreaInset.bottom > 0 && isUsingBottomBar ? 4 : 0)
      }

  }
  
  // 不可用的初始化方法
  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }
}
