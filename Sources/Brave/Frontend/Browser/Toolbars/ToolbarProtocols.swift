// 该源代码形式受 Mozilla 公共许可证 2.0 版的条款约束。
// 如果本文件未随此文件分发，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import UIKit

// 定义工具栏协议
protocol ToolbarProtocol: AnyObject {
    var tabToolbarDelegate: ToolbarDelegate? { get set }
    var tabsButton: TabsButton { get }
    var backButton: ToolbarButton { get }
    var forwardButton: ToolbarButton { get }
    var shareButton: ToolbarButton { get }
    

    var addTabButton: ToolbarButton { get }
    var searchButton: ToolbarButton { get }
    var menuButton: MenuButton { get }
    var actionButtons: [UIView] { get }

    func updateBackStatus(_ canGoBack: Bool)
    func updateForwardStatus(_ canGoForward: Bool)
    func updatePageStatus(_ isWebPage: Bool)
    func updateTabCount(_ count: Int)
    
    func updateProgressBar(_ progress: Float)
}

// 工具栏协议扩展
extension ToolbarProtocol {
    func updatePageStatus(_ isWebPage: Bool) {
        shareButton.isEnabled = isWebPage
    }

    func updateBackStatus(_ canGoBack: Bool) {
        backButton.isEnabled = canGoBack
    }

    func updateForwardStatus(_ canGoForward: Bool) {
        forwardButton.isEnabled = canGoForward
    }

    func updateTabCount(_ count: Int) {
        tabsButton.updateTabCount(count)
    }
    
   
}

// 工具栏 URL 操作协议
protocol ToolbarUrlActionsProtocol where Self: UIViewController {
    var toolbarUrlActionsDelegate: ToolbarUrlActionsDelegate? { get }
}

// 工具栏委托协议
protocol ToolbarDelegate: AnyObject {
    func tabToolbarDidPressBack(_ tabToolbar: ToolbarProtocol, button: UIButton)
    func tabToolbarDidPressForward(_ tabToolbar: ToolbarProtocol, button: UIButton)
    func tabToolbarDidLongPressBack(_ tabToolbar: ToolbarProtocol, button: UIButton)
    func tabToolbarDidLongPressForward(_ tabToolbar: ToolbarProtocol, button: UIButton)
    func tabToolbarDidPressTabs(_ tabToolbar: ToolbarProtocol, button: UIButton)
    func tabToolbarDidPressMenu(_ tabToolbar: ToolbarProtocol)
    func tabToolbarDidPressShare()
    func tabToolbarDidPressAddTab(_ tabToolbar: ToolbarProtocol, button: UIButton)
    func tabToolbarDidPressAddTabReal(_ tabToolbar: ToolbarProtocol, button: UIButton)
    
    func tabToolbarDidPressSearch(_ tabToolbar: ToolbarProtocol, button: UIButton)
    func tabToolbarDidSwipeToChangeTabs(_ tabToolbar: ToolbarProtocol, direction: UISwipeGestureRecognizer.Direction)
}
