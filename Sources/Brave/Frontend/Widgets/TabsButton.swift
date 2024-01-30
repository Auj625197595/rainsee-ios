/*
 * 此源代码形式受 Mozilla Public License，版本 2.0 的条款约束。
 * 如果没有与此文件一起分发的MPL副本，您可以在 http://mozilla.org/MPL/2.0/ 处获得一份。
 */

import Foundation
import Shared
import SnapKit
import UIKit
import Preferences

// 定义按钮外观相关的结构体
private enum TabsButtonUX {
    static let cornerRadius: CGFloat = 3 // 圆角半径
    static let borderStrokeWidth: CGFloat = 2 // 边框宽度
}

// 自定义标签按钮类，继承自 UIButton
class TabsButton: UIButton {
    private let countLabel = UILabel().then {
        $0.textAlignment = .center
        $0.isUserInteractionEnabled = false
    }

    private let borderView = UIView().then {
        $0.layer.borderWidth = TabsButtonUX.borderStrokeWidth
        $0.layer.cornerRadius = TabsButtonUX.cornerRadius
        $0.layer.cornerCurve = .continuous
        //  $0.layer.borderColor = UIColor.white.cgColor
        $0.isUserInteractionEnabled = false
    }

    // 浏览器颜色相关
    var browserColors: any BrowserColors = .standard {
        didSet {
            updateForTraitCollectionAndBrowserColors()
        }
    }

    // 初始化方法
    override init(frame: CGRect) {
        super.init(frame: frame)

        accessibilityTraits.insert(.button)
        isAccessibilityElement = true
        accessibilityLabel = Strings.showTabs

        addSubview(borderView)
        addSubview(countLabel)

        countLabel.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
        updateForTraitCollectionAndBrowserColors()
    }

    // 不可用的初始化方法
    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError()
    }

    // 按钮是否被高亮时的状态处理
    override var isHighlighted: Bool {
        didSet {
            let color: UIColor = isHighlighted ? browserColors.iconActive : UIColor(named: "Color_txt", in: .module, compatibleWith: nil)!
            countLabel.textColor = color
            borderView.layer.borderColor = color.resolvedColor(with: traitCollection).cgColor
        }
    }

    // 屏幕模式改变时的处理
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateForTraitCollectionAndBrowserColors()
    }

    // 根据屏幕模式和浏览器颜色更新按钮外观
    private func updateForTraitCollectionAndBrowserColors() {
        // CGColor 不会自动更新
        if Preferences.General.nightModeEnabled.value {
            borderView.layer.borderColor = isHighlighted ? browserColors.iconActive.cgColor : UIColor.white.cgColor
        } else {
            if let color = UIColor(named: "Color_txt", in: .module, compatibleWith: nil) {
                borderView.layer.borderColor = isHighlighted ? browserColors.iconActive.cgColor : color.cgColor
                countLabel.textColor = isHighlighted ? browserColors.iconActive : color

                
            }
        }

        let toolbarTraitCollection = UITraitCollection(preferredContentSizeCategory: traitCollection.toolbarButtonContentSizeCategory)
        let metrics = UIFontMetrics(forTextStyle: .body)
        borderView.snp.remakeConstraints {
            $0.center.equalToSuperview()
            $0.size.equalTo(metrics.scaledValue(for: 20, compatibleWith: toolbarTraitCollection))
        }
        countLabel.font = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: toolbarTraitCollection).pointSize, weight: .bold)
    }

    // 当前标签数量
    private var currentCount: Int?

    // 更新标签数量
    func updateTabCount(_ count: Int) {
        let count = max(count, 1)
        // 有时标签数量状态保存在克隆的标签按钮中。
        let infinity = "\u{221E}"
        let countToBe = (count < 100) ? "\(count)" : infinity
        currentCount = count
        countLabel.text = countToBe
        accessibilityValue = countToBe
    }

    // 上下文菜单交互，显示菜单时的反馈
    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        UIImpactFeedbackGenerator(style: .medium).bzzt()
    }
}
