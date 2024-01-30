// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import BraveCore
import BraveShared
import BraveUI
import DesignSystem
import Foundation
import Growth
import Preferences
import SafariServices
import Shared
import SnapKit
import UIKit

private enum WelcomeViewID: Int {
    case background = 1
    case topImage = 2
    case contents = 3
    case callout = 4
    case iconView = 5
    case searchView = 6
    case bottomImage = 7
    case iconBackground = 8
}

public class WelcomeViewController: UIViewController {
    private var state: WelcomeViewCalloutState?
    private let p3aUtilities: BraveP3AUtils // Privacy Analytics
    private let attributionManager: AttributionManager // Manager to handle daily active user and user referral

    public convenience init(p3aUtilities: BraveP3AUtils, attributionManager: AttributionManager) {
        self.init(state: .loading, p3aUtilities: p3aUtilities, attributionManager: attributionManager)
    }

    public init(state: WelcomeViewCalloutState?, p3aUtilities: BraveP3AUtils, attributionManager: AttributionManager) {
        self.state = state
        self.p3aUtilities = p3aUtilities
        self.attributionManager = attributionManager
        super.init(nibName: nil, bundle: nil)

        self.transitioningDelegate = self
        self.modalPresentationStyle = .fullScreen
        loadViewIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let backgroundGradientView = BraveGradientView(gradient: .backgroundGradient)

    private let contentContainer = UIStackView().then {
        $0.axis = .vertical
        $0.spacing = 8
        $0.layoutMargins = UIEdgeInsets(top: 0.0, left: 22.0, bottom: 0.0, right: 22.0)
        $0.isLayoutMarginsRelativeArrangement = true
    }

    private let calloutView = WelcomeViewCallout()

    private let iconView = UIImageView().then {
        $0.image = UIImage(named: "welcome-view-icon", in: .module, compatibleWith: nil)!
        $0.contentMode = .scaleAspectFit
        $0.setContentCompressionResistancePriority(.init(rawValue: 100), for: .vertical)
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        doLayout()

        if let state = state {
            setLayoutState(state: state)
        }
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Preferences.Onboarding.basicOnboardingCompleted.value = OnboardingState.completed.rawValue

        switch state {
        case .loading:
            let animation = CAKeyframeAnimation(keyPath: "transform.scale").then {
                $0.values = [1.0, 1.025, 1.0]
                $0.keyTimes = [0, 0.5, 1]
                $0.duration = 1.0
            }

            iconView.layer.add(animation, forKey: nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.animateToP3aState()
            }
        case .welcome:
            UIView.animate(withDuration: 0.5) {
                self.calloutView.frame.origin.y = self.calloutView.frame.origin.x - 35
            }

//      DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//        self.animateToP3aState()
//      }
        case .settings:
            calloutView.animateTitleViewVisibility(alpha: 1.0, duration: 1.5)

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.onSetDefaultBrowser()
            }
        default:
            break
        }
    }

    private func doLayout() {
        backgroundGradientView.tag = WelcomeViewID.background.rawValue
        contentContainer.tag = WelcomeViewID.contents.rawValue
        calloutView.tag = WelcomeViewID.callout.rawValue
        iconView.tag = WelcomeViewID.iconView.rawValue

        let stack = UIStackView().then {
            $0.distribution = .equalSpacing
            $0.axis = .vertical
            $0.setContentHuggingPriority(.init(rawValue: 5), for: .vertical)
        }

        let scrollView = UIScrollView()

        for item in [backgroundGradientView, scrollView] {
            view.addSubview(item)
        }

        scrollView.addSubview(stack)
        scrollView.snp.makeConstraints {
            $0.leading.trailing.top.equalToSuperview()
            $0.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(16)
        }

        scrollView.contentLayoutGuide.snp.makeConstraints {
            $0.width.equalTo(scrollView.frameLayoutGuide.snp.width)
            $0.height.greaterThanOrEqualTo(scrollView.frameLayoutGuide.snp.height)
        }

        stack.snp.makeConstraints {
            $0.edges.equalTo(scrollView.contentLayoutGuide.snp.edges)
        }

        stack.addStackViewItems(
            .view(UIView.spacer(.vertical, amount: 1)),
            .view(contentContainer),
            .view(UIView.spacer(.vertical, amount: 1)))

        for item in [calloutView, iconView] {
            contentContainer.addArrangedSubview(item)
        }

        backgroundGradientView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
    }

    public func setLayoutState(state: WelcomeViewCalloutState) {
        self.state = state

        switch state {
        case .loading:
            iconView.transform = .identity
            contentContainer.spacing = 0.0
            iconView.snp.remakeConstraints {
                $0.height.equalTo(225.0)
            }
            calloutView.setState(state: state)

        case .welcome:
            let topTransform = { () -> CGAffineTransform in
                var transformation = CGAffineTransform.identity
                transformation = transformation.scaledBy(x: 1.1, y: 1.1)
                transformation = transformation.translatedBy(x: 0.0, y: -30.0)
                return transformation
            }()

            let bottomTransform = { () -> CGAffineTransform in
                var transformation = CGAffineTransform.identity
                transformation = transformation.scaledBy(x: 1.5, y: 1.5)
                transformation = transformation.translatedBy(x: 0.0, y: 20.0)
                return transformation
            }()

            iconView.transform = .identity
            contentContainer.spacing = 0.0
            contentContainer.layoutMargins = UIEdgeInsets(top: 0.0, left: 15.0, bottom: 0.0, right: 15.0)
            iconView.snp.remakeConstraints {
                $0.height.equalTo(175.0)
            }
            calloutView.setState(state: state)

        case .defaultBrowser:
            let topTransform = { () -> CGAffineTransform in
                var transformation = CGAffineTransform.identity
                transformation = transformation.scaledBy(x: 1.3, y: 1.3)
                transformation = transformation.translatedBy(x: 0.0, y: -50.0)
                return transformation
            }()

            let bottomTransform = { () -> CGAffineTransform in
                var transformation = CGAffineTransform.identity
                transformation = transformation.scaledBy(x: 1.75, y: 1.75)
                transformation = transformation.translatedBy(x: 0.0, y: 30.0)
                return transformation
            }()

            contentContainer.spacing = 25.0
            contentContainer.layoutMargins = UIEdgeInsets(top: 0.0, left: 22.0, bottom: 0.0, right: 22.0)
            iconView.snp.remakeConstraints {
                $0.height.equalTo(180.0)
            }
            calloutView.setState(state: state)
        case .p3a, .settings:
            let topTransform = { () -> CGAffineTransform in
                var transformation = CGAffineTransform.identity
                transformation = transformation.scaledBy(x: 1.5, y: 1.5)
                transformation = transformation.translatedBy(x: 0.0, y: -70.0)
                return transformation
            }()

            let bottomTransform = { () -> CGAffineTransform in
                var transformation = CGAffineTransform.identity
                transformation = transformation.scaledBy(x: 2.0, y: 2.0)
                transformation = transformation.translatedBy(x: 0.0, y: 40.0)
                return transformation
            }()

            contentContainer.spacing = 20.0
            iconView.snp.remakeConstraints {
                $0.height.equalTo(180.0)
            }
            calloutView.setState(state: state)
        case .defaultBrowserCallout:
            let topTransform = { () -> CGAffineTransform in
                var transformation = CGAffineTransform.identity
                transformation = transformation.scaledBy(x: 1.5, y: 1.5)
                transformation = transformation.translatedBy(x: 0.0, y: -70.0)
                return transformation
            }()

            let bottomTransform = { () -> CGAffineTransform in
                var transformation = CGAffineTransform.identity
                transformation = transformation.scaledBy(x: 2.0, y: 2.0)
                transformation = transformation.translatedBy(x: 0.0, y: 40.0)
                return transformation
            }()

            iconView.image = UIImage(named: "welcome-view-phone", in: .module, compatibleWith: nil)!
            contentContainer.spacing = 0.0
            iconView.snp.remakeConstraints {
                $0.height.equalTo(175.0)
            }
            calloutView.setState(state: state)
        }
    }

    private func animateToWelcomeState() {
        let nextController = WelcomeViewController(state: nil, p3aUtilities: p3aUtilities, attributionManager: attributionManager).then {
            $0.setLayoutState(state: WelcomeViewCalloutState.welcome(title: Strings.Onboarding.welcomeScreenTitle))
        }
        present(nextController, animated: true)
    }

    private func animateToDefaultBrowserState() {
        let nextController = WelcomeViewController(state: nil, p3aUtilities: p3aUtilities, attributionManager: attributionManager)
        let state = WelcomeViewCalloutState.defaultBrowser(
            info: WelcomeViewCalloutState.WelcomeViewDefaultBrowserDetails(
                title: Strings.Callout.defaultBrowserCalloutTitle,
                details: Strings.Callout.defaultBrowserCalloutDescription,
                secondaryDetails: Strings.Callout.defaultBrowserCalloutButtonDescription,
                primaryButtonTitle: Strings.Callout.defaultBrowserCalloutPrimaryButtonTitle,
                secondaryButtonTitle: Strings.DefaultBrowserCallout.introSkipButtonText,
                primaryButtonAction: {
                    nextController.animateToDefaultSettingsState()
                },
                secondaryButtonAction: {
                    nextController.animateToP3aState()
                })
        )
        nextController.setLayoutState(state: state)
        present(nextController, animated: true)
    }

    private func animateToDefaultSettingsState() {
        let nextController = WelcomeViewController(state: nil, p3aUtilities: p3aUtilities, attributionManager: attributionManager).then {
            $0.setLayoutState(
                state: WelcomeViewCalloutState.settings(
                    title: Strings.Onboarding.navigateSettingsOnboardingScreenTitle,
                    details: Strings.Onboarding.navigateSettingsOnboardingScreenDescription))
        }

        present(nextController, animated: true) {
            Preferences.Onboarding.basicOnboardingDefaultBrowserSelected.value = true
        }
    }

    private func animateToP3aState() {
        let nextController = WelcomeViewController(state: nil, p3aUtilities: p3aUtilities, attributionManager: attributionManager)
        let state = WelcomeViewCalloutState.p3a(
            info: WelcomeViewCalloutState.WelcomeViewDefaultBrowserDetails(
                title: Strings.Callout.beforeUsingRead,
                toggleTitle: Strings.Callout.privacyAgreement,
                details: Strings.Callout.privacyAgreementDetails,
                linkDescription: Strings.Callout.privacyAgreementLink,
                primaryButtonTitle: Strings.Callout.agreeToAgreement,
                secondaryButtonTitle: Strings.Callout.doNotUse,
                linkAction: { _ in
                    let p3aLearnMoreController = SFSafariViewController(url: .brave.privacy_h5, configuration: .init())
                    p3aLearnMoreController.modalPresentationStyle = .currentContext

                    nextController.present(p3aLearnMoreController, animated: true)
                },
                primaryButtonAction: { [weak nextController, weak self] in
                    guard let controller = nextController, let self = self else {
                        return
                    }
                    Preferences.Onboarding.isPrivacyAgree.value = true
                    self.handleAdReportingFeatureLinkage(with: controller)
                },
                secondaryButtonAction: {
                    self.animateToWelcomeState()
                })
        )

        nextController.setLayoutState(state: state)

        present(nextController, animated: true) { [unowned self] in
            self.p3aUtilities.isNoticeAcknowledged = true
            Preferences.Onboarding.p3aOnboardingShown.value = true
        }
    }

    //  private func animateToP3aState() {
//    let nextController = WelcomeViewController(state: nil, p3aUtilities: p3aUtilities, attributionManager: attributionManager)
//    let state = WelcomeViewCalloutState.p3a(
//      info: WelcomeViewCalloutState.WelcomeViewDefaultBrowserDetails(
//        title: Strings.Callout.p3aCalloutTitle,
//        toggleTitle: Strings.Callout.p3aCalloutToggleTitle,
//        details: Strings.Callout.p3aCalloutDescription,
//        linkDescription: Strings.Callout.p3aCalloutLinkTitle,
//        primaryButtonTitle: Strings.P3A.continueButton,
//        toggleAction: { [weak self] isOn in
//          self?.p3aUtilities.isP3AEnabled = isOn
//        },
//        linkAction: { url in
//          let p3aLearnMoreController = SFSafariViewController(url: .brave.p3aHelpArticle, configuration: .init())
//          p3aLearnMoreController.modalPresentationStyle = .currentContext
//
//          nextController.present(p3aLearnMoreController, animated: true)
//        },
//
//        primaryButtonAction: { [weak nextController, weak self] in
//          guard let controller = nextController, let self = self else {
//            return
//          }
//
//          self.handleAdReportingFeatureLinkage(with: controller)
//        }
//      )
//    )
//
//    nextController.setLayoutState(state: state)
//
//    present(nextController, animated: true) { [unowned self] in
//      self.p3aUtilities.isNoticeAcknowledged = true
//      Preferences.Onboarding.p3aOnboardingShown.value = true
//    }
    //  }

    private func handleAdReportingFeatureLinkage(with controller: WelcomeViewController) {
        // Check controller is not in loading state
        guard !controller.calloutView.isLoading else {
            return
        }
        // The loading state should start before calling API
        controller.calloutView.isLoading = true

        let attributionManager = controller.attributionManager

        Task { @MainActor in
            do {
                if controller.p3aUtilities.isP3AEnabled {
                    switch attributionManager.activeFetureLinkageLogic {
                    case .campaingId:
                        let featureType = try await attributionManager.handleSearchAdsFeatureLinkage()
                        attributionManager.adFeatureLinkage = featureType
                    case .reporting:
                        // Handle API calls and send linkage type
                        let featureType = try await controller.attributionManager.handleAdsReportingFeatureLinkage()
                        attributionManager.adFeatureLinkage = featureType
                    }
                } else {
                    // p3a consent is not given
                    attributionManager.setupReferralCodeAndPingServer()
                }

                controller.calloutView.isLoading = false
                close()
            } catch let FeatureLinkageError.executionTimeout(attributionData) {
                // Time out occurred while executing ad reports lookup
                // Ad Campaign Lookup is successful so dau server should be pinged
                // attribution data referral code
                await pingServerWithGeneratedReferralCode(
                    using: attributionData, controller: controller)
            } catch let SearchAdError.successfulCampaignFailedKeywordLookup(attributionData) {
                // Error occurred while executing ad reports lookup
                // Ad Campaign Lookup is successful so dau server should be pinged
                // attribution data referral code
                await pingServerWithGeneratedReferralCode(
                    using: attributionData, controller: controller)
            } catch {
                // Error occurred before getting successful
                // attributuion data, generic code should be pinged
                attributionManager.setupReferralCodeAndPingServer()

                controller.calloutView.isLoading = false
                close()
            }
        }
    }

    private func pingServerWithGeneratedReferralCode(using attributionData: AdAttributionData, controller: WelcomeViewController) async {
        Task {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    controller.attributionManager.generateReferralCodeAndPingServer(with: attributionData)
                    continuation.resume()
                }
            }
        }

        controller.calloutView.isLoading = false
        close()
    }

    private func onSetDefaultBrowser() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(settingsUrl)

        animateToP3aState()
    }

    private func close() {
        var presenting: UIViewController = self
        while true {
            if let presentingController = presenting.presentingViewController {
                presenting = presentingController
                continue
            }

            if let presentingController = presenting as? UINavigationController,
               let topController = presentingController.topViewController
            {
                presenting = topController
            }

            break
        }

        Preferences.Onboarding.basicOnboardingProgress.value = OnboardingProgress.newTabPage.rawValue
        presenting.dismiss(animated: false, completion: nil)
    }
}

extension WelcomeViewController: UIViewControllerTransitioningDelegate {
    public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return WelcomeAnimator(isPresenting: true)
    }

    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return WelcomeAnimator(isPresenting: false)
    }
}

// Disabling orientation changes
public extension WelcomeViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }

    override var shouldAutorotate: Bool {
        return false
    }
}

private class WelcomeAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let isPresenting: Bool

    private struct WelcomeViewInfo {
        let backgroundGradientView: UIView
        let contentContainer: UIView
        let calloutView: UIView
        let iconView: UIView
        let searchEnginesView: UIView

        var allViews: [UIView] {
            return [
                backgroundGradientView,
                contentContainer,
                calloutView,
                iconView,
                searchEnginesView,
            ]
        }

        init?(view: UIView) {
            guard let backgroundGradientView = view.subview(with: WelcomeViewID.background.rawValue),
                  let contentContainer = view.subview(with: WelcomeViewID.contents.rawValue),
                  let calloutView = view.subview(with: WelcomeViewID.callout.rawValue),
                  let iconView = view.subview(with: WelcomeViewID.iconView.rawValue),
                  let searchEnginesView = view.subview(with: WelcomeViewID.searchView.rawValue)
            else {
                return nil
            }

            self.backgroundGradientView = backgroundGradientView
            self.contentContainer = contentContainer
            self.calloutView = calloutView
            self.iconView = iconView
            self.searchEnginesView = searchEnginesView
        }
    }

    init(isPresenting: Bool) {
        self.isPresenting = isPresenting
    }

    func performDefaultAnimation(using transitionContext: UIViewControllerContextTransitioning) {
        let container = transitionContext.containerView

        guard let fromView = transitionContext.view(forKey: UITransitionContextViewKey.from) else {
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }

        guard let toView = transitionContext.view(forKey: UITransitionContextViewKey.to) else {
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }

        // Setup
        fromView.frame = container.bounds
        toView.frame = container.bounds
        container.addSubview(toView)
        fromView.setNeedsLayout()
        fromView.layoutIfNeeded()
        toView.setNeedsLayout()
        toView.layoutIfNeeded()

        // Setup animation
        let totalAnimationTime = transitionDuration(using: transitionContext)

        toView.alpha = 0.0
        UIView.animate(withDuration: totalAnimationTime, delay: 0.0, options: .curveEaseInOut) {
            toView.alpha = 1.0
        } completion: { finished in
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled && finished)
        }
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let container = transitionContext.containerView

        guard let fromView = transitionContext.view(forKey: UITransitionContextViewKey.from) else {
            performDefaultAnimation(using: transitionContext)
            return
        }

        guard let toView = transitionContext.view(forKey: UITransitionContextViewKey.to) else {
            performDefaultAnimation(using: transitionContext)
            return
        }

        // Get animatable views
        guard let fromWelcomeView = WelcomeViewInfo(view: fromView),
              let toWelcomeView = WelcomeViewInfo(view: toView)
        else {
            performDefaultAnimation(using: transitionContext)
            return
        }

        // Setup
        fromView.frame = container.bounds
        toView.frame = container.bounds
        container.addSubview(toView)
        fromView.setNeedsLayout()
        fromView.layoutIfNeeded()
        toView.setNeedsLayout()
        toView.layoutIfNeeded()

        // Setup animation
        let totalAnimationTime = transitionDuration(using: transitionContext)
        let fromViews = fromWelcomeView.allViews
        let toViews = toWelcomeView.allViews

        toWelcomeView.contentContainer.setNeedsLayout()
        toWelcomeView.contentContainer.layoutIfNeeded()

        // Do animations
        for e in fromViews.enumerated() {
            let fromView = e.element
            var toAlpha = 0.0
            let toView = toViews[e.offset].then {
                toAlpha = $0.alpha
                $0.alpha = 0.0
            }

            if fromView == fromWelcomeView.backgroundGradientView {
                continue
            }

            UIViewPropertyAnimator(duration: totalAnimationTime, curve: .easeInOut) {
                fromView.alpha = 0
                toView.alpha = toAlpha
            }
            .startAnimation()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + totalAnimationTime) {
            toWelcomeView.backgroundGradientView.alpha = 1.0
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.5
    }
}

private extension UIView {
    func subview(with tag: Int) -> UIView? {
        if self.tag == tag {
            return self
        }

        for view in subviews {
            if view.tag == tag {
                return view
            }

            if let view = view.subview(with: tag) {
                return view
            }
        }
        return nil
    }
}
