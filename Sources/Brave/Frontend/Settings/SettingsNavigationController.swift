/* 该源代码形式受 Mozilla 公共许可证 2.0 版的条款约束。
 * 如果本文件未随此文件分发，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。 */

import UIKit

// 设置导航控制器类
class SettingsNavigationController: UINavigationController {
  var popoverDelegate: PresentingModalViewControllerDelegate?

  // 视图已经出现时的处理
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    if #available(iOS 16.0, *) {
      self.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
  }
  
  // 完成按钮点击处理
  @objc func done() {
    if let delegate = popoverDelegate {
      delegate.dismissPresentedModalViewController(self, animated: true)
    } else {
      self.dismiss(animated: true, completion: nil)
    }
  }

  // 设置状态栏样式
  override var preferredStatusBarStyle: UIStatusBarStyle {
    if self.view.overrideUserInterfaceStyle == .light || self.overrideUserInterfaceStyle == .light {
      return .darkContent
    }
    return .lightContent
  }

  // 支持的界面方向
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    return .portrait
  }

  // 首选的界面方向
  override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
    return .portrait
  }
}

// 呈现模态设置导航控制器类
class ModalSettingsNavigationController: UINavigationController {
  // 首选的状态栏样式
  override var preferredStatusBarStyle: UIStatusBarStyle {
    return .default
  }
}

// 呈现模态视图控制器委托协议
protocol PresentingModalViewControllerDelegate {
  func dismissPresentedModalViewController(_ modalViewController: UIViewController, animated: Bool)
}
