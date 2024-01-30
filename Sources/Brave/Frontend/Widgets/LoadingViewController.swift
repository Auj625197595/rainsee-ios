// 版权声明：© 2023 The Brave Authors. 保留所有权利。
// 此源代码表单受 Mozilla Public License，v. 2.0 的条款约束。
// 如果未随此文件分发 MPL 的副本，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import UIKit
import BraveShared
import Shared
import LocalAuthentication

// 加载视图控制器，用于显示加载状态
public class LoadingViewController: UIViewController {

  // 活动指示器，用于显示加载状态
  let spinner = UIActivityIndicatorView().then {
    $0.snp.makeConstraints { make in
      make.size.equalTo(24)
    }
    $0.hidesWhenStopped = true
    $0.isHidden = true
  }

  // 是否正在加载的标志
  var isLoading: Bool = false {
    didSet {
      if isLoading {
        view.addSubview(spinner)
        spinner.snp.makeConstraints {
          $0.center.equalTo(view.snp.center)
        }
        spinner.startAnimating()
      } else {
        spinner.stopAnimating()
        spinner.removeFromSuperview()
      }
    }
  }
}

// 身份验证控制器，继承自加载视图控制器
public class AuthenticationController: LoadingViewController {
  let windowProtection: WindowProtection?
  let requiresAuthentication: Bool
  
  // 生命周期
  
  // 初始化方法
  init(windowProtection: WindowProtection? = nil,
       requiresAuthentication: Bool = false,
       isCancellable: Bool = false,
       unlockScreentitle: String = "") {
    self.windowProtection = windowProtection
    self.requiresAuthentication = requiresAuthentication
    
    super.init(nibName: nil, bundle: nil)
    
    self.windowProtection?.isCancellable = isCancellable
    self.windowProtection?.unlockScreentitle = unlockScreentitle
  }
  
  // 必需的初始化方法，如果从 storyboard 中加载会触发 fatalError
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  /// 请求生物识别身份验证的方法
  /// - Parameter completion: 返回身份验证状态的回调
  func askForAuthentication(viewType: AuthViewType, completion: ((Bool, LAError.Code?) -> Void)? = nil) {
    guard let windowProtection = windowProtection else {
      completion?(false, nil)
      return
    }

    if !windowProtection.isPassCodeAvailable {
      if viewType == .tabTray {
        completion?(false, LAError.passcodeNotSet)
      } else {
        showSetPasscodeError(viewType: viewType) {
          completion?(false, LAError.passcodeNotSet)
        }
      }
    } else {
      windowProtection.presentAuthenticationForViewController(
        determineLockWithPasscode: false, viewType: viewType) { status, error in
          completion?(status, error)
      }
    }
  }
  
  /// 显示设置密码错误的警告的方法，提醒用户设置密码以使用功能
  /// - Parameter completion: Ok 按钮按下后的回调
  func showSetPasscodeError(viewType: AuthViewType, completion: @escaping (() -> Void)) {
    var alertMessage: String?
    
    switch viewType {
    case .sync:
      alertMessage = Strings.Sync.syncSetPasscodeAlertDescription
    case .tabTray:
      alertMessage = Strings.Privacy.tabTraySetPasscodeAlertDescription
    default:
      alertMessage = nil
    }
    
    let alert = UIAlertController(
      title: Strings.Sync.syncSetPasscodeAlertTitle,
      message: alertMessage,
      preferredStyle: .alert)

    alert.addAction(
      UIAlertAction(title: Strings.OKString, style: .default, handler: { _ in
        completion()
      })
    )
    
    present(alert, animated: true, completion: nil)
  }
}
