// 该源代码形式受 Mozilla 公共许可证 2.0 版的条款约束。
// 如果本文件未随此文件分发，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import UIKit
import Shared
import DesignSystem
import Preferences
extension UIImage {
    // 缩放图片到指定大小
    func scaled(toSize newSize: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}


@objcMembers
class ToolbarHelper: NSObject { 
    let toolbar: ToolbarProtocol

   

    init(toolbar: ToolbarProtocol) {
        self.toolbar = toolbar
        super.init()
        
        // 配置返回按钮
        toolbar.backButton.setImage(UIImage(braveSystemNamed: "leo.browser.back"), for: .normal)
        toolbar.backButton.accessibilityLabel = Strings.tabToolbarBackButtonAccessibilityLabel
        let longPressGestureBackButton = UILongPressGestureRecognizer(target: self, action: #selector(didLongPressBack))
        toolbar.backButton.addGestureRecognizer(longPressGestureBackButton)
        toolbar.backButton.addTarget(self, action: #selector(didClickBack), for: .touchUpInside)
        
        // 配置分享按钮
        toolbar.shareButton.setImage(UIImage(braveSystemNamed: "leo.share.macos"), for: .normal)
        toolbar.shareButton.accessibilityLabel = Strings.tabToolbarShareButtonAccessibilityLabel
        toolbar.shareButton.addTarget(self, action: #selector(didClickShare), for: UIControl.Event.touchUpInside)
        
        
        
        // 设置按钮的文本
       
        // 配置标签按钮
        toolbar.tabsButton.addTarget(self, action: #selector(didClickTabs), for: .touchUpInside)
        
        // 配置添加标签按钮
      //  toolbar.addTabButton.setImage(UIImage(braveSystemNamed: "leo.plus.add"), for: .normal)
        
        
        if let image2 = UIImage(named: "bar_home", in: .module, compatibleWith: nil) {
            // 调整图片大小并设置按钮图片
            let scaledImage = image2.scaled(toSize: CGSize(width: 20, height: 20)).withRenderingMode(.alwaysTemplate)
            toolbar.addTabButton.setImage(scaledImage, for: .normal)
        }
        
        // 设置按钮的 contentMode
        toolbar.addTabButton.imageView?.contentMode = .scaleAspectFit
        
        // 如果需要设置图片在按钮内的边距，使用 imageEdgeInsets
        toolbar.addTabButton.imageEdgeInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        
        
        toolbar.addTabButton.accessibilityLabel = Strings.tabToolbarAddTabButtonAccessibilityLabel
        toolbar.addTabButton.addTarget(self, action: #selector(didClickAddTab), for: UIControl.Event.touchUpInside)
        if let parentView = toolbar.searchButton.superview {
            // 在这里使用 parentView
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didClickSearch))
            parentView.addGestureRecognizer(tapGesture)
        } else {
            print("没有父视图")
        }
        // 配置搜索按钮
//        toolbar.searchButton.setImage(UIImage(braveSystemNamed: "leo.search"), for: .normal)
//        // 由于在底部工具栏类中覆盖了辅助功能标签，因此不需要辅助功能标签。
        toolbar.searchButton.addTarget(self, action: #selector(didClickSearch), for: UIControl.Event.touchUpInside)
        toolbar.searchButton.setTitle( Strings.Home.homePage, for: .normal)
        
        
        let longPressGestureNewTabButton = UILongPressGestureRecognizer(target: self, action: #selector(didLongPressNewTab))
        toolbar.tabsButton.addGestureRecognizer(longPressGestureNewTabButton)
        
        if let image = UIImage(named: "bar_menu", in: .module, compatibleWith: nil) {
            // 调整图片大小并设置按钮图片
            let scaledImage = image.scaled(toSize: CGSize(width: 20, height: 20)).withRenderingMode(.alwaysTemplate)
            toolbar.menuButton.setImage(scaledImage, for: .normal)
        }
        
        // 设置按钮的 contentMode
        toolbar.menuButton.imageView?.contentMode = .scaleAspectFit
        
        // 如果需要设置图片在按钮内的边距，使用 imageEdgeInsets
        toolbar.menuButton.imageEdgeInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        
 
        
      

        
        toolbar.menuButton.accessibilityLabel = Strings.tabToolbarMenuButtonAccessibilityLabel
        toolbar.menuButton.addTarget(self, action: #selector(didClickMenu), for: UIControl.Event.touchUpInside)

        // 配置前进按钮
        toolbar.forwardButton.setImage(UIImage(braveSystemNamed: "leo.browser.forward"), for: .normal)
        toolbar.forwardButton.accessibilityLabel = Strings.tabToolbarForwardButtonAccessibilityLabel
        let longPressGestureForwardButton = UILongPressGestureRecognizer(target: self, action: #selector(didLongPressForward))
        toolbar.forwardButton.addGestureRecognizer(longPressGestureForwardButton)
        toolbar.forwardButton.addTarget(self, action: #selector(didClickForward), for: .touchUpInside)
    }

    // 点击菜单按钮
    func didClickMenu() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressMenu(toolbar)
    }

    // 点击返回按钮
    func didClickBack() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressBack(toolbar, button: toolbar.backButton)
    }

    // 长按返回按钮
    func didLongPressBack(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            toolbar.tabToolbarDelegate?.tabToolbarDidLongPressBack(toolbar, button: toolbar.backButton)
        }
    }

    // 点击标签按钮
    func didClickTabs() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressTabs(toolbar, button: toolbar.tabsButton)
    }

    // 点击前进按钮
    func didClickForward() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressForward(toolbar, button: toolbar.forwardButton)
    }

    // 长按前进按钮
    func didLongPressForward(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            toolbar.tabToolbarDelegate?.tabToolbarDidLongPressForward(toolbar, button: toolbar.forwardButton)
        }
    }
    // 长按新标签页按钮
    func didLongPressNewTab(_ recognizer: UILongPressGestureRecognizer) {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressAddTabReal(toolbar, button: toolbar.tabsButton)
       
    }
    // 点击分享按钮
    func didClickShare() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressShare()
    }

    // 点击添加标签按钮
    func didClickAddTab() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressAddTab(toolbar, button: toolbar.shareButton)
    }

    // 点击搜索按钮
    func didClickSearch() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressSearch(toolbar, button: toolbar.searchButton)
    }

    // 根据特征集合更新工具栏
    func updateForTraitCollection(_ traitCollection: UITraitCollection, browserColors: some BrowserColors, additionalButtons: [UIButton] = []) {
        let toolbarTraitCollection = UITraitCollection(preferredContentSizeCategory: traitCollection.toolbarButtonContentSizeCategory)
        let config = UIImage.SymbolConfiguration(pointSize: UIFont.preferredFont(forTextStyle: .body, compatibleWith: toolbarTraitCollection).pointSize, weight: .regular, scale: .large)
        let buttons: [UIButton] = [
            toolbar.backButton,
            toolbar.forwardButton,
            toolbar.addTabButton,
            toolbar.menuButton,
            //toolbar.searchButton,
            toolbar.shareButton
        ] + additionalButtons
        for button in buttons {
            button.setPreferredSymbolConfiguration(config, forImageIn: .normal)
            button.tintColor = browserColors.iconDefault
            
            let night = traitCollection.userInterfaceStyle == .dark || Preferences.General.nightModeEnabled.value
            if let button = button as? ToolbarButton {
                button.primaryTintColor = night ? UIColor.white : UIColor.black
                button.selectedTintColor = browserColors.iconActive
                button.disabledTintColor = browserColors.iconDisabled
            }
        }
        toolbar.tabsButton.browserColors = browserColors
    }
}
