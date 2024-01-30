// Copyright 2023 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveCore
import BraveShields
import BraveUI
import Data
import Growth
import Preferences
import Shared
import SnapKit
import Storage
import UIKit

/// Displays shield settings and shield stats for a given URL
class ShieldsViewController: UIViewController, PopoverContentComponent {
    let tab: Tab
    private lazy var url: URL? = {
        guard let _url = tab.url else { return nil }

        if let tabURL = _url.stippedInternalURL {
            return tabURL
        }

        return _url
    }()

    var shieldsSettingsChanged: ((ShieldsViewController, BraveShield) -> Void)?
    var showGlobalShieldsSettings: ((ShieldsViewController) -> Void)?
    var showSubmitReportView: ((ShieldsViewController) -> Void)?

    private var statsUpdateObservable: AnyObject?

    /// Create with an initial URL and block stats (or nil if you are not on any web page)
    init(tab: Tab) {
        self.tab = tab

        super.init(nibName: nil, bundle: nil)

        tab.contentBlocker.statsDidChange = { [weak self] _ in
            self?.updateShieldBlockStats()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    private var shieldsUpSwitch: ShieldsSwitch {
        return shieldsView.simpleShieldView.shieldsSwitch
    }

    // MARK: - State

    private func updateToggleStatus() {
        var domain: Domain?
        if let url = url {
            // 获取当前标签是否处于私密浏览模式
            let isPrivateBrowsing = tab.isPrivate
            // 根据URL获取或创建对应的域，持久性取决于是否处于私密浏览模式
            domain = Domain.getOrCreate(forUrl: url, persistent: !isPrivateBrowsing)
        }

        // 设置主界面上的 Shields 开关状态
        shieldsUpSwitch.isOn = domain?.isShieldExpected(.AllOff, considerAllShieldsOption: false) == false

        // 更新每个防护类型对应的开关状态
        for (shield, view) in shieldControlMapping {
            if let domain = domain {
                // 如果存在特定域，表示该域的防护状态已被覆盖，更新相应的开关状态
                view.toggleSwitch.isOn = domain.isShieldExpected(shield, considerAllShieldsOption: false)
            } else {
                switch shield {
                case .AdblockAndTp:
                    // 如果不存在特定域，使用全局设置更新 AdblockAndTp 防护的开关状态
                    view.toggleSwitch.isOn = ShieldPreferences.blockAdsAndTrackingLevel.isEnabled
                case .AllOff:
                    // 不应该出现 AllOff 的情况，如果出现则发出断言失败
                    assertionFailure()
                case .FpProtection:
                    // 如果不存在特定域，使用全局设置更新 FpProtection 防护的开关状态
                    view.toggleSwitch.isOn = Preferences.Shields.fingerprintingProtection.value
                case .NoScript:
                    // 如果不存在特定域，使用全局设置更新 NoScript 防护的开关状态
                    view.toggleSwitch.isOn = Preferences.Shields.blockScripts.value
                }
            }
        }

        // 更新全局防护状态
        updateGlobalShieldState(shieldsUpSwitch.isOn)
    }

    private func updateShieldBlockStats() {
        shieldsView.simpleShieldView.blockCountView.countLabel.text = String(
            tab.contentBlocker.stats.adCount + tab.contentBlocker.stats.trackerCount + tab.contentBlocker.stats.httpsCount + tab.contentBlocker.stats.scriptCount + tab.contentBlocker.stats.fingerprintingCount
        )
    }

    private func updateBraveShieldState(shield: BraveShield, on: Bool) {
        guard let url = url else { return }
        let allOff = shield == .AllOff
        // `.AllOff` 使用相反的逻辑。从技术上讲，当开关关闭时，我们设置为 "all off"，与其他所有开关不同
        // 如果新状态与全局首选项相同，则将其重置为nil，以便将来的防护状态查询
        // 遵循全局首选项而不是覆盖值。（防止切换域状态影响将来对全局首选项的更改）
        let isOn = allOff ? !on : on
        // 在域级别设置 BraveShield 状态，以确保全局首选项被尊重
        Domain.setBraveShield(
            forUrl: url, shield: shield, isOn: isOn,
            isPrivateBrowsing: tab.isPrivate)
    }

    private func updateGlobalShieldState(_ on: Bool, animated: Bool = false) {
        shieldsView.simpleShieldView.statusLabel.text = on ? Strings.Shields.statusValueUp.uppercased() : Strings.Shields.statusValueDown.uppercased()

        // Whether or not shields are available for this URL.
        let isShieldsAvailable = url?.isLocal == false
        // If shields aren't available, we don't show the switch and show the "off" state
        let shieldsEnabled = isShieldsAvailable ? on : false
        if animated {
            var partOneViews: [UIView]
            var partTwoViews: [UIView]
            if shieldsEnabled {
                partOneViews = [shieldsView.simpleShieldView.shieldsDownStackView]
                partTwoViews = [
                    shieldsView.simpleShieldView.blockCountView,
                    shieldsView.simpleShieldView.footerLabel,
                    shieldsView.advancedControlsBar,
                ]
                if advancedControlsShowing {
                    partTwoViews.append(shieldsView.advancedShieldView)
                }
            } else {
                partOneViews = [
                    shieldsView.simpleShieldView.blockCountView,
                    shieldsView.simpleShieldView.footerLabel,
                    shieldsView.advancedControlsBar,
                ]
                if advancedControlsShowing {
                    partOneViews.append(shieldsView.advancedShieldView)
                }
                partTwoViews = [shieldsView.simpleShieldView.shieldsDownStackView]
            }
            // Step 1, hide
            UIView.animate(
                withDuration: 0.1,
                animations: {
                    partOneViews.forEach { $0.alpha = 0.0 }
                },
                completion: { _ in
                    for partOneView in partOneViews {
                        partOneView.alpha = 1.0
                        partOneView.isHidden = true
                    }
                    for partTwoView in partTwoViews {
                        partTwoView.alpha = 0.0
                        partTwoView.isHidden = false
                    }
                    UIView.animate(
                        withDuration: 0.15,
                        animations: {
                            partTwoViews.forEach { $0.alpha = 1.0 }
                        })

                    self.updatePreferredContentSize()
                })
        } else {
            shieldsView.simpleShieldView.blockCountView.isHidden = !shieldsEnabled
            shieldsView.simpleShieldView.footerLabel.isHidden = !shieldsEnabled
            shieldsView.simpleShieldView.shieldsDownStackView.isHidden = shieldsEnabled
            shieldsView.advancedControlsBar.isHidden = !shieldsEnabled

            updatePreferredContentSize()
        }
    }

    private func updateContentView(to view: UIView, animated: Bool) {
        if animated {
            UIView.animate(
                withDuration: shieldsView.contentView == nil ? 0 : 0.1,
                animations: {
                    self.shieldsView.contentView?.alpha = 0.0
                },
                completion: { _ in
                    self.shieldsView.contentView = view
                    view.alpha = 0
                    self.updatePreferredContentSize()
                    UIView.animate(withDuration: 0.1) {
                        view.alpha = 1.0
                    }
                })
        } else {
            shieldsView.contentView = view
        }
    }

    private func updatePreferredContentSize() {
        guard let visibleView = shieldsView.contentView else { return }
        let width = min(360, UIScreen.main.bounds.width - 20)
        // Ensure the a static width is given to the main view so we can calculate the height
        // correctly when we force a layout
        let height = visibleView.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel).height

        preferredContentSize = CGSize(
            width: width,
            height: height)
    }

    // MARK: -

    /// Groups the shield types with their control and global preference
    private lazy var shieldControlMapping: [(BraveShield, AdvancedShieldsView.ToggleView)] = [
        (.AdblockAndTp, shieldsView.advancedShieldView.adsTrackersControl),
        (.NoScript, shieldsView.advancedShieldView.blockScriptsControl),
        (.FpProtection, shieldsView.advancedShieldView.fingerprintingControl),
    ]

    var shieldsView: View {
        return view as! View // swiftlint:disable:this force_cast
    }

    override func loadView() {
        view = View()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let url = url {
            shieldsView.simpleShieldView.faviconImageView.loadFavicon(for: url, isPrivateBrowsing: tab.isPrivate)
        } else {
            shieldsView.simpleShieldView.faviconImageView.isHidden = true
        }

        // Follows the logic in `updateTextWithURL` for formatting
        let normalizedDisplayHost = URLFormatter.formatURLOrigin(forDisplayOmitSchemePathAndTrivialSubdomains: url?.absoluteString ?? "")

        shieldsView.simpleShieldView.hostLabel.text = normalizedDisplayHost
        shieldsView.simpleShieldView.shieldsSwitch.addTarget(self, action: #selector(shieldsOverrideSwitchValueChanged), for: .valueChanged)
        shieldsView.advancedShieldView.siteTitle.titleLabel.text = normalizedDisplayHost.uppercased()
        shieldsView.advancedShieldView.globalControlsButton.addTarget(self, action: #selector(tappedGlobalShieldsButton), for: .touchUpInside)

        shieldsView.advancedControlsBar.addTarget(self, action: #selector(tappedAdvancedControlsBar), for: .touchUpInside)

//    shieldsView.simpleShieldView.blockCountView.infoButton.addTarget(self, action: #selector(tappedAboutShieldsButton), for: .touchUpInside)
        shieldsView.simpleShieldView.blockCountView.shareButton.addTarget(self, action: #selector(tappedShareShieldsButton), for: .touchUpInside)

//    shieldsView.simpleShieldView.reportSiteButton.addTarget(self, action: #selector(tappedReportSiteButton), for: .touchUpInside)

        updateShieldBlockStats()

        navigationController?.setNavigationBarHidden(true, animated: false)

        updateToggleStatus()

        if advancedControlsShowing && shieldsUpSwitch.isOn {
            shieldsView.advancedShieldView.isHidden = false
            shieldsView.advancedControlsBar.isShowingAdvancedControls = true
            updatePreferredContentSize()
        }

        for (shield, toggle) in shieldControlMapping {
            toggle.valueToggled = { [weak self] on in
                guard let self = self else { return }
                // Localized / per domain toggles triggered here
                self.updateBraveShieldState(shield: shield, on: on)
                // Wait a fraction of a second to allow DB write to complete otherwise it will not use the
                // updated shield settings when reloading the page
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.shieldsSettingsChanged?(self, shield)
                }
            }
        }
    }

    func showAlert() {
        let alertController = UIAlertController(title: Strings.Other.alertTitle, message: Strings.Other.duetolegal, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alertController, animated: true, completion: nil)
    }

    @objc private func shieldsOverrideSwitchValueChanged() {
        if Domain.isValidHost(url?.absoluteString) {
            shieldsView.simpleShieldView.shieldsSwitch.setOn(false, animated: false)
            showAlert()
            return
        }

        let isOn = shieldsUpSwitch.isOn
        updateGlobalShieldState(isOn, animated: true)
        updateBraveShieldState(shield: .AllOff, on: isOn)
        // Wait a fraction of a second to allow DB write to complete otherwise it will not use the updated
        // shield settings when reloading the page
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.shieldsSettingsChanged?(self, .AllOff)
        }
    }

    private var advancedControlsShowing: Bool {
        Preferences.Shields.advancedControlsVisible.value
    }

    @objc private func tappedAdvancedControlsBar() {
        Preferences.Shields.advancedControlsVisible.value.toggle()
        UIView.animate(withDuration: 0.25) {
            self.shieldsView.advancedShieldView.isHidden.toggle()
        }
        updatePreferredContentSize()
    }

    @objc private func tappedAboutShieldsButton() {
        let aboutShields = AboutShieldsViewController()
        aboutShields.preferredContentSize = preferredContentSize
        navigationController?.pushViewController(aboutShields, animated: true)
    }

    @objc private func tappedShareShieldsButton() {
        let globalShieldsActivityController =
            ShieldsActivityItemSourceProvider.shared.setupGlobalShieldsActivityController(isPrivateBrowsing: tab.isPrivate)
        globalShieldsActivityController.popoverPresentationController?.sourceView = view

        present(globalShieldsActivityController, animated: true, completion: nil)
    }

    @objc private func tappedReportSiteButton() {
        showSubmitReportView?(self)
    }

    @objc private func tappedGlobalShieldsButton() {
        showGlobalShieldsSettings?(self)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }
}
