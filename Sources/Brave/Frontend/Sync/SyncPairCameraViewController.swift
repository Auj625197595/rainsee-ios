/*
  此源代码受Mozilla公共许可证v. 2.0的条款约束。
  如果未随此文件分发MPL副本，您可以在http://mozilla.org/MPL/2.0/获取一份。
*/

import UIKit
import Shared
import AVFoundation
import BraveShared
import BraveCore
import Data
import BraveUI

// MARK: - SyncPairControllerDelegate 协议定义了同步配对控制器的委托方法
protocol SyncPairControllerDelegate: AnyObject {
  func syncOnScannedHexCode(_ controller: UIViewController & NavigationPrevention, hexCode: String)
  func syncOnWordsEntered(_ controller: UIViewController & NavigationPrevention, codeWords: String, isCodeScanned: Bool)
}

// MARK: - SyncPairCameraViewController 类定义了用于相机扫描的视图控制器
class SyncPairCameraViewController: SyncViewController {
  
  // MARK: 属性声明
  private var cameraLocked = false
  weak var delegate: SyncPairControllerDelegate?
  var cameraView: SyncCameraView!
  var titleLabel: UILabel!
  var descriptionLabel: UILabel!
  var enterWordsButton: RoundInterfaceButton!
  var loadingView: UIView!
  let loadingSpinner = UIActivityIndicatorView(style: .large).then {
    $0.color = .white
  }
  private let syncAPI: BraveSyncAPI
  private static let forcedCameraTimeout = 25.0

  // MARK: 初始化方法
  init(syncAPI: BraveSyncAPI) {
    self.syncAPI = syncAPI
    super.init()
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }

  // MARK: 视图加载完成时调用
  override func viewDidLoad() {
    super.viewDidLoad()

    title = Strings.scan

    let stackView = UIStackView().then {
      $0.axis = .vertical
      $0.distribution = .equalSpacing
      $0.alignment = .center
      $0.spacing = 4
    }

    view.addSubview(stackView)

    stackView.snp.makeConstraints { make in
      make.top.equalTo(self.view.safeArea.top).offset(16)
      make.left.right.equalTo(self.view).inset(16)
      make.bottom.equalTo(self.view.safeArea.bottom).inset(16)
    }

    cameraView = SyncCameraView().then {
      $0.translatesAutoresizingMaskIntoConstraints = false
      $0.backgroundColor = .black
      $0.layer.cornerRadius = 4
      $0.layer.cornerCurve = .continuous
      $0.layer.masksToBounds = true
      $0.scanCallback = { [weak self] data in
        self?.onQRCodeScanned(data: data)
      }
    }

    stackView.addArrangedSubview(cameraView)

    let titleDescriptionStackView = UIStackView().then {
      $0.axis = .vertical
      $0.spacing = 4
      $0.alignment = .center
      $0.setContentCompressionResistancePriority(UILayoutPriority(rawValue: 250), for: .vertical)
    }

    titleLabel = UILabel().then {
      $0.translatesAutoresizingMaskIntoConstraints = false
      $0.font = UIFont.systemFont(ofSize: 20, weight: UIFont.Weight.semibold)
      $0.text = Strings.syncToDevice
    }
    titleDescriptionStackView.addArrangedSubview(titleLabel)

    descriptionLabel = UILabel().then {
      $0.translatesAutoresizingMaskIntoConstraints = false
      $0.font = UIFont.systemFont(ofSize: 15, weight: UIFont.Weight.regular)
      $0.numberOfLines = 0
      $0.lineBreakMode = .byWordWrapping
      $0.textAlignment = .center
      $0.text = Strings.syncToDeviceDescription
    }
    titleDescriptionStackView.addArrangedSubview(descriptionLabel)

    let textStackView = UIStackView(arrangedSubviews: [
      UIView.spacer(.horizontal, amount: 16),
      titleDescriptionStackView,
      UIView.spacer(.horizontal, amount: 16),
    ])

    stackView.addArrangedSubview(textStackView)

    enterWordsButton = RoundInterfaceButton(type: .roundedRect)
    enterWordsButton.translatesAutoresizingMaskIntoConstraints = false
    enterWordsButton.setTitle(Strings.enterCodeWords, for: .normal)
    enterWordsButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: UIFont.Weight.semibold)
    enterWordsButton.addTarget(self, action: #selector(onEnterWordsPressed), for: .touchUpInside)
    stackView.addArrangedSubview(enterWordsButton)

    loadingSpinner.startAnimating()

    loadingView = UIView()
    loadingView.translatesAutoresizingMaskIntoConstraints = false
    loadingView.backgroundColor = UIColor(white: 0.5, alpha: 0.5)
    loadingView.isHidden = true
    loadingView.addSubview(loadingSpinner)
    cameraView.addSubview(loadingView)

    edgesForExtendedLayout = UIRectEdge()

    cameraView.snp.makeConstraints { (make) in
      if UIDevice.current.userInterfaceIdiom == .pad {
        make.size.equalTo(400)
      } else {
        make.size.equalTo(self.view.snp.width).multipliedBy(0.9)
      }
    }

    loadingView.snp.makeConstraints { make in
      make.left.right.top.bottom.equalTo(cameraView)
    }

    loadingSpinner.snp.makeConstraints { make in
      make.center.equalTo(loadingSpinner.superview!)
    }
  }

  // MARK: 视图旋转时调用
  override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    coordinator.animate(alongsideTransition: nil) { _ in
      self.cameraView.videoPreviewLayer?.connection?.videoOrientation = AVCaptureVideoOrientation(ui: UIApplication.shared.statusBarOrientation)
    }
  }

  // MARK: 点击输入单词按钮时调用
  @objc
  private func onEnterWordsPressed() {
    let wordsVC = SyncPairWordsViewController(syncAPI: syncAPI)
    wordsVC.delegate = delegate
    navigationController?.pushViewController(wordsVC, animated: true)
  }

  // MARK: 扫描到二维码时调用
  private func onQRCodeScanned(data: String) {
    // 防止多次扫描
    if cameraLocked { return }
    cameraLocked = true

    processQRCodeData(data: data)
  }
  
  // MARK: 处理二维码数据
  private func processQRCodeData(data: String) {
    // 暂停扫描
    cameraView.cameraOverlaySuccess()
    cameraView.stopRunning()

    // 振动
    AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))

    // 强制超时
    let task = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      self.cameraLocked = false
      self.cameraView.cameraOverlayError()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + SyncPairCameraViewController.forcedCameraTimeout, execute: task)

    // 检查网络连接
    if !DeviceInfo.hasConnectivity() {
      task.cancel()
      showErrorAlert(title: Strings.syncNoConnectionTitle, message: Strings.syncNoConnectionBody)
      return
    }
    
    let wordsValidation = syncAPI.getQRCodeValidationResult(data)
    if wordsValidation == .valid {
      // 同步码有效
      delegate?.syncOnScannedHexCode(self, hexCode: syncAPI.getHexSeed(fromQrCodeJson: data))
    } else {
      cameraView.cameraOverlayError()
      showErrorAlert(title: Strings.syncUnableCreateGroup, message: wordsValidation.errorDescription)
    }
  }

  // MARK: 显示错误提示框
  private func showErrorAlert(title: String, message: String) {
    let alert = UIAlertController(
      title: Strings.syncUnableCreateGroup,
      message: message,
      preferredStyle: .alert)

    alert.addAction(
      UIAlertAction(
        title: Strings.OKString, style: .default,
        handler: { [weak self] _ in
          guard let self = self else { return }
          self.cameraLocked = false
          self.cameraView.cameraOverlayNormal()
          self.cameraView.startRunning()
        }))
    present(alert, animated: true)
  }
}

// MARK: - NavigationPrevention 协议实现
extension SyncPairCameraViewController: NavigationPrevention {
  func enableNavigationPrevention() {
    loadingView.isHidden = false
    navigationItem.hidesBackButton = true
    enterWordsButton.isEnabled = false
  }

  func disableNavigationPrevention() {
    loadingView.isHidden = true
    navigationItem.hidesBackButton = false
    enterWordsButton.isEnabled = true
  }
}

// MARK: - AVCaptureVideoOrientation 扩展
extension AVCaptureVideoOrientation {
  var uiInterfaceOrientation: UIInterfaceOrientation {
    get {
      switch self {
      case .landscapeLeft: return .landscapeLeft
      case .landscapeRight: return .landscapeRight
      case .portrait: return .portrait
      case .portraitUpsideDown: return .portraitUpsideDown
      @unknown default: assertionFailure(); return .portrait
      }
    }
  }

  init(ui: UIInterfaceOrientation) {
    switch ui {
    case .landscapeRight: self = .landscapeRight
    case .landscapeLeft: self = .landscapeLeft
    case .portrait: self = .portrait
    case .portraitUpsideDown: self = .portraitUpsideDown
    default: self = .portrait
    }
  }
}
