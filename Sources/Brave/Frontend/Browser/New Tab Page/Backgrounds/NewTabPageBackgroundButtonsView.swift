// 版权所有 © 2020 勇敢浏览器的作者。保留所有权利。
// 此源代码形式受 Mozilla 公共许可证 v. 2.0 条款的约束。
// 如果未随此文件分发 MPL 副本，可以在 http://mozilla.org/MPL/2.0/ 处获取一份。

import UIKit
import BraveUI
import Preferences
import Shared
import SnapKit
import BraveCore

/// 新标签页背景按钮视图，用于容纳静态元素，如图片来源、品牌标志或通过 QR 码分享按钮
///
/// 目前此视图仅显示单个活动按钮
class NewTabPageBackgroundButtonsView: UIView, PreferencesObserver {
  /// 要显示的按钮类型
  enum ActiveButton {
    /// 显示图片来源按钮，显示给定 `name` 的来源
    case imageCredit(_ name: String)
    /// 显示品牌标志按钮
    case brandLogo(_ logo: NTPSponsoredImageLogo)
    /// 显示带有小型 QR 码图像的按钮
    case QRCode
  }
  
  /// 当用户点击活动按钮之一时执行的块
  var tappedActiveButton: ((UIControl) -> Void)?
  
  /// 当前活动按钮
  ///
  /// 将其设置为 `nil` 可隐藏所有按钮类型
  var activeButton: ActiveButton? {
    didSet {
      guard let activeButton = activeButton else {
        activeView = nil
        return
      }

    }
  }
  
  /// 当前显示的按钮
  private var activeView: UIView? {
    willSet {
      activeView?.isHidden = true
    }
    didSet {
      activeView?.isHidden = false
    }
  }

  /// 父级安全区域插图（由于 UICollectionView 在将 `contentInsetAdjustmentBehavior` 设置为 `always` 时无法向下传递正确的 `safeAreaInsets`）
  var collectionViewSafeAreaInsets: UIEdgeInsets = .zero {
    didSet {
      safeAreaInsetsConstraint?.update(inset: collectionViewSafeAreaInsets)
    }
  }
  private var safeAreaInsetsConstraint: Constraint?
  private let collectionViewSafeAreaLayoutGuide = UILayoutGuide()
  private let privateBrowsingManager: PrivateBrowsingManager

  init(privateBrowsingManager: PrivateBrowsingManager) {
    self.privateBrowsingManager = privateBrowsingManager
    
    super.init(frame: .zero)

    Preferences.BraveNews.isEnabled.observe(from: self)

    backgroundColor = .clear
    addLayoutGuide(collectionViewSafeAreaLayoutGuide)
    collectionViewSafeAreaLayoutGuide.snp.makeConstraints {
      self.safeAreaInsetsConstraint = $0.edges.equalTo(self).constraint
    }

  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    let isLandscape = frame.width > frame.height

    let braveNewsVisible =
      !privateBrowsingManager.isPrivateBrowsing && (Preferences.BraveNews.isEnabled.value || Preferences.BraveNews.isShowingOptIn.value)

  }

  @objc private func tappedButton(_ sender: UIControl) {
    tappedActiveButton?(sender)
  }

  func preferencesDidChange(for key: String) {
    setNeedsLayout()
  }
}

extension NewTabPageBackgroundButtonsView {
  private class ImageCreditButton: SpringButton {
    private let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .light)).then {
      $0.clipsToBounds = true
      $0.isUserInteractionEnabled = false
      $0.layer.cornerRadius = 4
      $0.layer.cornerCurve = .continuous
    }

    let label = UILabel().then {
      $0.textColor = .white
      $0.font = UIFont.systemFont(ofSize: 12.0, weight: .medium)
    }

    override init(frame: CGRect) {
      super.init(frame: frame)

      addSubview(backgroundView)
      backgroundView.contentView.addSubview(label)

      backgroundView.snp.makeConstraints {
        $0.edges.equalToSuperview()
      }
      label.snp.makeConstraints {
        $0.edges.equalToSuperview().inset(UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10))
      }
    }
  }
  private class SponsorLogoButton: SpringButton {
    let imageView = UIImageView().then {
      $0.contentMode = .scaleAspectFit
    }
    override init(frame: CGRect) {
      super.init(frame: frame)

      addSubview(imageView)
      imageView.snp.makeConstraints {
        $0.edges.equalToSuperview()
      }
    }
  }
  private class QRCodeButton: SpringButton {
    let imageView = UIImageView(image: UIImage(named: "qr_code_button", in: .module, compatibleWith: nil)!)

    override init(frame: CGRect) {
      super.init(frame: frame)

      contentMode = .scaleAspectFit
      backgroundColor = .white
      clipsToBounds = true
      layer.shadowRadius = 1
      layer.shadowOpacity = 0.5

      addSubview(imageView)
      imageView.snp.makeConstraints {
        $0.center.equalToSuperview()
      }
    }

    override func layoutSubviews() {
      super.layoutSubviews()

      layer.cornerRadius = bounds.height / 2.0
      layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
    }
  }
}
