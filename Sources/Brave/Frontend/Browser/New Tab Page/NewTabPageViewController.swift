// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import BraveCore
import BraveNews
import BraveShared
import BraveUI
import Combine
import CoreData
import Data
import DesignSystem
import Growth
import Preferences
import Shared
import SnapKit
import SwiftUI
import UIKit

/// The behavior for sizing sections when the user is in landscape orientation
enum NTPLandscapeSizingBehavior {
    /// The section is given half the available space
    ///
    /// Layout is decided by device type (iPad vs iPhone)
    case halfWidth
    /// The section is given the full available space
    ///
    /// Layout is up to the section to define
    case fullWidth
}

/// NTPSectionProvider 协议定义了将在 NTP（New Tab Page） 中显示的一个部分。部分负责其自己项的布局和交互。
protocol NTPSectionProvider: NSObject, UICollectionViewDelegateFlowLayout, UICollectionViewDataSource {
    /// 在 `collectionView` 中注册该部分的单元格和补充视图
    func registerCells(to collectionView: UICollectionView)

    /// 用户处于横向模式时的定义行为。
    ///
    /// 默认为 `halfWidth`，将只给该部分提供可用宽度的一半（并根据设备自动调整布局）
    var landscapeBehavior: NTPLandscapeSizingBehavior { get }
}

extension NTPSectionProvider {
    var landscapeBehavior: NTPLandscapeSizingBehavior { .halfWidth }

    /// 自动调整单元格大小的边界尺寸，受制于集合视图中的最大可用宽度，考虑安全区域插图和给定部分的插图
    func fittingSizeForCollectionView(_ collectionView: UICollectionView, section: Int) -> CGSize {
        let sectionInset: UIEdgeInsets

        if let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            if let flowLayoutDelegate = collectionView.delegate as? UICollectionViewDelegateFlowLayout {
                sectionInset = flowLayoutDelegate.collectionView?(collectionView, layout: collectionView.collectionViewLayout, insetForSectionAt: section) ?? flowLayout.sectionInset
            } else {
                sectionInset = flowLayout.sectionInset
            }
        } else {
            sectionInset = .zero
        }

        return CGSize(
            width: collectionView.bounds.width - collectionView.safeAreaInsets.left - collectionView.safeAreaInsets.right - sectionInset.left - sectionInset.right,
            height: 1000
        )
    }
}

/// NTPObservableSectionProvider 协议定义了一个可被观察的部分提供者，以通知 `NewTabPageViewController` 重新加载其部分
protocol NTPObservableSectionProvider: NTPSectionProvider {
    var sectionDidChange: (() -> Void)? { get set }
}

/// NewTabPageDelegate 协议定义了与 NTP 页面相关的一些动作的委托方法
protocol NewTabPageDelegate: AnyObject {
    func focusURLBar()
    func navigateToInput(_ input: String, inNewTab: Bool, switchingToPrivateMode: Bool)
    func handleFavoriteAction(favorite: Favorite, action: BookmarksAction)
    func brandedImageCalloutActioned(_ state: BrandedImageCalloutState)
    func tappedQRCodeButton(url: URL)
    func showNTPOnboarding()
}

/// The new tab page. Shows users a variety of information, including stats and
/// favourites
class NewTabPageViewController: UIViewController {
    weak var delegate: NewTabPageDelegate?

    var ntpStatsOnboardingFrame: CGRect? {
        guard let section = sections.firstIndex(where: { $0 is StatsSectionProvider }) else {
            return nil
        }

        if let cell = collectionView.cellForItem(at: IndexPath(item: 0, section: section)) as? NewTabCenteredCollectionViewCell<BraveShieldStatsView> {
            return cell.contentView.convert(cell.contentView.frame, to: view)
        }
        return nil
    }

    /// The modules to show on the new tab page
    private var sections: [NTPSectionProvider] = []

    private let layout = NewTabPageFlowLayout()
    private let collectionView: NewTabCollectionView
    private weak var tab: Tab?
    private let rewards: BraveRewards

    private var background: NewTabPageBackground
    private let backgroundView = NewTabPageBackgroundView()
    //  private let backgroundButtonsView: NewTabPageBackgroundButtonsView
    /// A gradient to display over background images to ensure visibility of
    /// the NTP contents and sponsored logo
    ///
    /// Only should be displayed when the user has background images enabled
//    let gradientView = GradientView(
//        colors: [
//            UIColor(white: 0.0, alpha: 0.5),
//            UIColor(white: 0.0, alpha: 0.0),
//            UIColor(white: 0.0, alpha: 0.3),
//        ],
//        positions: [0, 0.5, 0.8],
//        startPoint: .zero,
//        endPoint: CGPoint(x: 0, y: 1)
//    )

    private let feedDataSource: FeedDataSource
    private let feedOverlayView = NewTabPageFeedOverlayView()
    private var preventReloadOnBraveNewsEnabledChange = false

    // private let notifications: NewTabPageNotifications
    private var cancellables: Set<AnyCancellable> = []
    private let privateBrowsingManager: PrivateBrowsingManager

    private let p3aHelper: NewTabPageP3AHelper

    init(
        tab: Tab,
        profile: Profile,
        dataSource: NTPDataSource,
        feedDataSource: FeedDataSource,
        rewards: BraveRewards,
        privateBrowsingManager: PrivateBrowsingManager,
        p3aUtils: BraveP3AUtils,
        action: ((String) -> Void)?
    ) {
        // 初始化属性
        self.tab = tab
        self.rewards = rewards
        self.feedDataSource = feedDataSource
        self.privateBrowsingManager = privateBrowsingManager
        //    backgroundButtonsView = NewTabPageBackgroundButtonsView(privateBrowsingManager: privateBrowsingManager)
        p3aHelper = .init(p3aUtils: p3aUtils)
        background = NewTabPageBackground(dataSource: dataSource)
        //    notifications = NewTabPageNotifications(rewards: rewards)
        collectionView = NewTabCollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)

        // 设置 P3AHelper 的数据源
        p3aHelper.dataSource = self

        // 监听偏好设置变化
        Preferences.NewTabPage.showNewTabPrivacyHub.observe(from: self)
        Preferences.NewTabPage.showNewTabFavourites.observe(from: self)

        // 初始化分区数组
        sections = [
            HomeTopIconProvider(action: { [weak self] actionName in
                print(actionName)
                if actionName == "search" {
                    self?.delegate?.focusURLBar()
                } else if actionName == "logo"{
                    let nTPTableViewController = NTPTableViewController()
                    let navController = ModalSettingsNavigationController(rootViewController: nTPTableViewController)

                    self?.present(navController, animated: true, completion: nil)
                } else {
                    action?("qrcode")
                }

            }),
            // StatsSectionProvider
//            StatsSectionProvider(isPrivateBrowsing: tab.isPrivate, openPrivacyHubPressed: { [weak self] in
//                if self?.privateBrowsingManager.isPrivateBrowsing == true {
//                    return
//                }
//
//                // 打开隐私报告视图
//                let host = UIHostingController(rootView: PrivacyReportsManager.prepareView(isPrivateBrowsing: privateBrowsingManager.isPrivateBrowsing))
//                host.rootView.onDismiss = { [weak self] in
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
//                        guard let self = self else { return }
//
//                        // 处理应用评分
//                        // 用户完成查看隐私报告（点击关闭）
//                        AppReviewManager.shared.handleAppReview(for: .revised, using: self)
//                    }
//                }
//
//                // 打开隐私报告链接
//                host.rootView.openPrivacyReportsUrl = { [weak self] in
//                    self?.delegate?.navigateToInput(
//                        URL.brave.privacyFeatures.absoluteString,
//                        inNewTab: false,
//                        // 隐私报告视图在私密模式下不可用
//                        switchingToPrivateMode: false
//                    )
//                }
//
//                self?.present(host, animated: true)
//            }, hidePrivacyHubPressed: { [weak self] in
//                self?.hidePrivacyHub()
//            }),
            // FavoritesSectionProvider
            FavoritesSectionProvider(action: { [weak self] bookmark, action in
                self?.handleFavoriteAction(favorite: bookmark, action: action)
            }, legacyLongPressAction: { [weak self] alertController in
                self?.present(alertController, animated: true)
            }, isPrivateBrowsing: privateBrowsingManager.isPrivateBrowsing),
            // FavoritesOverflowSectionProvider
            FavoritesOverflowSectionProvider(action: { [weak self] in
                self?.delegate?.focusURLBar()
            }),
        ]

        // 判断是否为背景为 NTPSI（New Tab Sponsored Image）
        var isBackgroundNTPSI = false
        if let ntpBackground = background.currentBackground, case .sponsoredImage = ntpBackground {
            isBackgroundNTPSI = true
        }

        // 创建 NTPDefaultBrowserCalloutProvider 实例
        let ntpDefaultBrowserCalloutProvider = NTPDefaultBrowserCalloutProvider(isBackgroundNTPSI: isBackgroundNTPSI)

        // 如果需要显示浏览器默认提示，则将其插入分区数组的第一个位置
        if ntpDefaultBrowserCalloutProvider.shouldShowCallout() {
            sections.insert(ntpDefaultBrowserCalloutProvider, at: 0)
        }

        // 如果不在私密浏览模式下，添加 BraveNewsSectionProvider 分区
        /*
         if !privateBrowsingManager.isPrivateBrowsing {
             sections.append(
                 BraveNewsSectionProvider(
                     dataSource: feedDataSource,
                     rewards: rewards,
                     actionHandler: { [weak self] in
                         self?.handleBraveNewsAction($0)
                     }
                 )
             )
             layout.braveNewsSection = sections.firstIndex(where: { $0 is BraveNewsSectionProvider })
         }
         */

        // 配置 collectionView 的代理和数据源
        collectionView.do {
            $0.delegate = self
            $0.dataSource = self
            $0.dragDelegate = self
            $0.dropDelegate = self
        }

        // 设置背景变化回调
        background.changed = { [weak self] in
            self?.setupBackgroundImage()
        }

        // 监听 BraveNews 开关状态
        // Preferences.BraveNews.isEnabled.observe(from: self)

        // 监听 FeedDataSource 状态变化
        feedDataSource.$state
            .scan((.initial, .initial)) { ($0.1, $1) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] oldState, newState in
                self?.handleFeedStateChange(oldState, newState)
            }
            .store(in: &cancellables)

        // 监听应用激活通知，检查是否有更新的 Feed
        NotificationCenter.default.addObserver(self, selector: #selector(checkForUpdatedFeed), name: UIApplication.didBecomeActiveNotification, object: nil)

        // 记录 BraveNews 功能使用情况
//        let braveNewsFeatureUsage = P3AFeatureUsage.braveNewsFeatureUsage
//        if isBraveNewsVisible && Preferences.BraveNews.isEnabled.value {
//            braveNewsFeatureUsage.recordHistogram()
//            recordBraveNewsDaysUsedP3A()
//        }

        // 记录新建标签页 P3A
        //    recordNewTabCreatedP3A()
        // 记录 BraveNews 每周使用次数 P3A
        //   recordBraveNewsWeeklyUsageCountP3A()
    }

    // 不可用的初始化方法，通过fatalError()表示不可用
    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError()
    }

    // 对象销毁时执行的方法，用于移除通知中心中的观察者
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // 视图加载完成时调用的方法
    override func viewDidLoad() {
        super.viewDidLoad()

        // 将 backgroundView 添加到视图中
        view.addSubview(backgroundView)

        // 将 gradientView 插入到 backgroundView 之上
      //  view.insertSubview(gradientView, aboveSubview: backgroundView)

        // 将 collectionView、feedOverlayView 添加到视图中
        view.addSubview(collectionView)
        view.addSubview(feedOverlayView)

        // 设置 collectionView 的背景视图为 backgroundButtonsView
        // collectionView.backgroundView = backgroundButtonsView

        // 配置 feedOverlayView 的按钮的点击事件
        feedOverlayView.headerView.settingsButton.addTarget(self, action: #selector(tappedBraveNewsSettings), for: .touchUpInside)

        // 如果不是公共频道，添加长按手势
        if !AppConstants.buildChannel.isPublic {
            feedOverlayView.headerView.settingsButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressedBraveNewsSettingsButton)))
        }

        // 配置 feedOverlayView 中 newContentAvailableButton 的点击事件
        feedOverlayView.newContentAvailableButton.addTarget(self, action: #selector(tappedNewContentAvailable), for: .touchUpInside)

        // 配置 backgroundButtonsView 中 active 按钮的点击事件
//        backgroundButtonsView.tappedActiveButton = { [weak self] sender in
//            self?.tappedActiveBackgroundButton(sender)
//        }

        // 设置背景图片
        setupBackgroundImage()

        // 设置 backgroundView 的约束
        backgroundView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        // 设置 collectionView 的约束
        collectionView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        // 设置 feedOverlayView 的约束
        feedOverlayView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        // 设置 gradientView 的约束
//        gradientView.snp.makeConstraints {
//            $0.edges.equalTo(backgroundView)
//        }

        // 遍历并注册每个 section 的单元格
        for (index, provider) in sections.enumerated() {
            provider.registerCells(to: collectionView)

            // 如果是可观察的 section，则配置其变化回调
            if let observableProvider = provider as? NTPObservableSectionProvider {
                observableProvider.sectionDidChange = { [weak self] in
                    guard let self = self else { return }
                    if self.parent != nil {
                        UIView.performWithoutAnimation {
                            // 在 iOS 16.4 中，reloadSections 似乎对不需要刷新的其他部分进行了某种底层数据的验证
                            // 这可能导致需要在相同批次中重新加载的部分产生断言。由于我们不对该部分进行动画处理
                            // 我们可以在这里切换到 `reloadData`。
                            self.collectionView.reloadData()
                        }
                    }
                    self.collectionView.collectionViewLayout.invalidateLayout()
                }
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkForUpdatedFeed()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        collectionView.reloadData()

        // Make sure that imageView has a frame calculated before we attempt
        // to use it.
        backgroundView.layoutIfNeeded()

        calculateBackgroundCenterPoints()
    }

    // 当视图已经出现在屏幕上时调用的方法
    override func viewDidAppear(_ animated: Bool) {
        // 调用父类的方法，确保父类的方法也被执行
        super.viewDidAppear(animated)

        // 向后台报告已经展示了赞助图片事件
//        reportSponsoredImageBackgroundEvent(.served)

        // 使用异步延时执行，等待1秒钟后执行以下代码块
//        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//          // 作为临时解决方案，直到1.53.x版本，我们在1秒后触发.viewed事件，
//          // 以便给.served事件足够的时间被触发；否则，由于需要相应的.served事件，
//          // 赞助图片的viewed事件将失败。在1.53.x及以上版本中，
//          // 我们应该触发.served事件，并在完成块中如果成功应该触发.viewed事件。
//          self.reportSponsoredImageBackgroundEvent(.viewed)
//        }

        // 弹出通知
        //       presentNotification()

        // 使用异步延时执行，等待0.50秒钟后执行以下代码块
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
//          // 调用代理的方法以显示新闻推送(onboarding)
//          self.delegate?.showNTPOnboarding()
//        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        //  backgroundButtonsView.collectionViewSafeAreaInsets = view.safeAreaInsets
    }

    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)

        if parent == nil {
            backgroundView.imageView.image = nil
        } else {
            if  Preferences.NewTabPage.backgroundImages.value {
                // 判断文件是否存在
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let destinationPath = documentsDirectory.appendingPathComponent("selectedImage.jpg")
                if FileManager.default.fileExists(atPath: destinationPath.path) {
                    // 文件存在，显示图片
                    // displayImage(atPath: lastSelectedImagePath)
                    if let image = UIImage(contentsOfFile: destinationPath.path) {
                        // 设置图片到UIImageView中
                        backgroundView.imageView.image = image
                    }

                } else {
                    // 文件不存在，设置存储的路径为空
                    //Preferences.NewTabPage.lastSelectedImagePath.value = ""
                    Preferences.NewTabPage.backgroundImages.value = false
                }
            }
            
        }
        // backgroundView.imageView.image = parent == nil ? nil : background.backgroundImage
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if previousTraitCollection?.verticalSizeClass
            != traitCollection.verticalSizeClass
        {
            calculateBackgroundCenterPoints()
        }
    }

    // MARK: - 背景

    /// 隐藏任何可见的赞助图像通知，如果当前背景不再是赞助图像，则隐藏。如果可见通知不是关于赞助图像的，则不执行任何操作。
//    private func hideVisibleSponsoredImageNotification() {
//        if case .brandedImages = visibleNotification {
//            guard let background = background.currentBackground else {
//                hideNotification()
//                return
//            }
//            switch background {
//            case .image, .superReferral:
//                hideNotification()
//            case .sponsoredImage:
//                // 当前背景仍然是赞助图像，因此它可以保持可见
//                break
//            }
//        }
//    }

    func setupBackgroundImage() {
        collectionView.reloadData()

        //     hideVisibleSponsoredImageNotification()

//        if let background = background.currentBackground {
//            switch background {
//            case .image(let background):
//                if case let name = background.author, !name.isEmpty {
//                    backgroundButtonsView.activeButton = .imageCredit(name)
//                } else {
//                    backgroundButtonsView.activeButton = .none
//                }
//            case .sponsoredImage(let background):
//                backgroundButtonsView.activeButton = .brandLogo(background.logo)
//            case .superReferral:
//                backgroundButtonsView.activeButton = .QRCode
//            }
//        } else {
//            backgroundButtonsView.activeButton = .none
//        }

     //  gradientView.isHidden = false

        if  Preferences.NewTabPage.backgroundImages.value {
            // 判断文件是否存在
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let destinationPath = documentsDirectory.appendingPathComponent("selectedImage.jpg")
            if FileManager.default.fileExists(atPath: destinationPath.path) {
                // 文件存在，显示图片
                // displayImage(atPath: lastSelectedImagePath)
                if let image = UIImage(contentsOfFile: destinationPath.path) {
                    // 设置图片到UIImageView中
                    backgroundView.imageView.image = image
                }

            } else {
                // 文件不存在，设置存储的路径为空
             //   Preferences.NewTabPage.lastSelectedImagePath.value = ""
                Preferences.NewTabPage.backgroundImages.value = false
            }
        } else {
            backgroundView.imageView.image = nil
        }
        
    }

    private func calculateBackgroundCenterPoints() {
        // 仅当iPhone竖屏设备时，调整图像的偏移中心。
        // 在其他情况下，图像始终居中。
        guard let image = backgroundView.imageView.image,
              traitCollection.horizontalSizeClass == .compact && traitCollection.verticalSizeClass == .regular
        else {
            // 重置先前计算的偏移量。
            backgroundView.updateImageXOffset(by: 0)
            return
        }

        // 如果未提供焦点，则不执行任何操作。图像默认居中。
        guard let focalPoint = background.currentBackground?.focalPoint else {
            return
        }

        let focalX = focalPoint.x

        // 计算`image`和`imageView`之间的尺寸差异，以确定像素差异比率。
        // 大多数图像计算必须使用此属性以正确获取坐标。
        let sizeRatio = backgroundView.imageView.frame.size.height / image.size.height

        // 根据设置的焦点坐标计算图像应该偏移的量。
        // 我们通过查看需要将图像移动到远离图像中心的程度来计算它。
        let focalXOffset = ((image.size.width / 2) - focalX) * sizeRatio

        // 在一侧裁剪的图像空间量，在屏幕上不可见。
        // 我们使用此信息防止在更新`x`偏移时越过图像边界。
        let extraHorizontalSpaceOnOneSide = ((image.size.width * sizeRatio) - backgroundView.frame.width) / 2

        // 由于焦点偏移可能离图像中心太远
        // 导致没有足够的图像空间覆盖视图的整个宽度，并留下空白空间。
        // 如果焦点偏移超出边界，我们将其居中到最大值，以确保整个
        // 图像能够覆盖视图。
        let realisticXOffset = abs(focalXOffset) > extraHorizontalSpaceOnOneSide ?
            extraHorizontalSpaceOnOneSide : focalXOffset

        backgroundView.updateImageXOffset(by: realisticXOffset)
    }

    private func reportSponsoredImageBackgroundEvent(_ event: BraveAds.NewTabPageAdEventType) {
        if case .sponsoredImage(let sponsoredBackground) = background.currentBackground {
            let eventType: NewTabPageP3AHelper.EventType? = {
                switch event {
                case .clicked: return .tapped
                case .viewed: return .viewed
                default: return nil
                }
            }()
            if let eventType {
                p3aHelper.recordEvent(eventType, on: sponsoredBackground)
            }
            rewards.ads.triggerNewTabPageAdEvent(
                background.wallpaperId.uuidString,
                creativeInstanceId: sponsoredBackground.creativeInstanceId,
                eventType: event,
                completion: { _ in }
            )
        }
    }

    // MARK: - Notifications

//    private var notificationController: UIViewController?
    // //   private var visibleNotification: NewTabPageNotifications.NotificationType?
//    private var notificationShowing: Bool {
//        notificationController?.parent != nil
//    }

//    private func presentNotification() {
//        if privateBrowsingManager.isPrivateBrowsing || notificationShowing {
//            return
//        }
//
//        var isShowingSponseredImage = false
//        if case .sponsoredImage = background.currentBackground {
//            isShowingSponseredImage = true
//        }
//
//        guard
//            let notification = notifications.notificationToShow(
//                isShowingBackgroundImage: background.currentBackground != nil,
//                isShowingSponseredImage: isShowingSponseredImage
//            )
//        else {
//            return
//        }
//
//        var vc: UIViewController?
//
//        switch notification {
//        case .brandedImages(let state):
//            if Preferences.NewTabPage.atleastOneNTPNotificationWasShowed.value { return }
//
//            guard let notificationVC = NTPNotificationViewController(state: state, rewards: rewards) else { return }
//
//            notificationVC.closeHandler = { [weak self] in
//                self?.notificationController = nil
//            }
//
//            notificationVC.learnMoreHandler = { [weak self] in
//                self?.delegate?.brandedImageCalloutActioned(state)
//            }
//
//            vc = notificationVC
//        }
//
//        guard let viewController = vc else { return }
//        notificationController = viewController
//        visibleNotification = notification
//
//        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
//            guard let self = self else { return }
//
//            if case .brandedImages = notification {
//                Preferences.NewTabPage.atleastOneNTPNotificationWasShowed.value = true
//            }
//
//            self.addChild(viewController)
//            self.view.addSubview(viewController.view)
//        }
//    }

//    private func hideNotification() {
//        guard let controller = notificationController else { return }
//        controller.willMove(toParent: nil)
//        controller.removeFromParent()
//        controller.view.removeFromSuperview()
//        notificationController = nil
//    }

    // MARK: - Brave News

    private var newsArticlesOpened: Set<FeedItem.ID> = []

    private var newContentAvailableDismissTimer: Timer? {
        didSet {
            oldValue?.invalidate()
        }
    }

    private func handleFeedStateChange(
        _ oldValue: FeedDataSource.State,
        _ newValue: FeedDataSource.State
    ) {
        guard let section = layout.braveNewsSection, parent != nil else { return }

        func _completeLoading() {
            UIView.animate(
                withDuration: 0.2,
                animations: {
                    self.feedOverlayView.loaderView.alpha = 0.0
                },
                completion: { _ in
                    self.feedOverlayView.loaderView.stop()
                    self.feedOverlayView.loaderView.alpha = 1.0
                    self.feedOverlayView.loaderView.isHidden = true
                }
            )
            if collectionView.contentOffset.y == collectionView.contentInset.top {
                collectionView.reloadData()
                collectionView.layoutIfNeeded()
                let cells = collectionView.indexPathsForVisibleItems
                    .filter { $0.section == section }
                    .compactMap(collectionView.cellForItem(at:))
                for cell in cells {
                    cell.transform = .init(translationX: 0, y: 200)
                    UIView.animate(
                        withDuration: 0.5, delay: 0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0, options: [.beginFromCurrentState],
                        animations: {
                            cell.transform = .identity
                        }, completion: nil
                    )
                }
            } else {
                collectionView.reloadSections(IndexSet(integer: section))
            }
        }

        switch (oldValue, newValue) {
        case (.loading, .loading):
            // Nothing to do
            break
        case (
            .failure(let error1 as NSError),
            .failure(let error2 as NSError)
        ) where error1 == error2:
            // Nothing to do
            break
        case (
            .loading(.failure(let error1 as NSError)),
            .failure(let error2 as NSError)
        ) where error1 == error2:
            if let cell = collectionView.cellForItem(at: IndexPath(item: 0, section: section)) as? FeedCardCell<BraveNewsErrorView> {
                cell.content.refreshButton.isLoading = false
            } else {
                _completeLoading()
            }
        case (_, .loading):
            if collectionView.contentOffset.y == collectionView.contentInset.top || collectionView.numberOfItems(inSection: section) == 0 {
                feedOverlayView.loaderView.isHidden = false
                feedOverlayView.loaderView.start()

                let numberOfItems = collectionView.numberOfItems(inSection: section)
                if numberOfItems > 0 {
                    collectionView.reloadSections(IndexSet(integer: section))
                }
            }
        case (.loading, _):
            _completeLoading()
        default:
            collectionView.reloadSections(IndexSet(integer: section))
        }
    }

    @objc private func checkForUpdatedFeed() {
        if !isBraveNewsVisible || Preferences.BraveNews.isShowingOptIn.value { return }
        if collectionView.contentOffset.y == collectionView.contentInset.top {
            // Reload contents if the user is not currently scrolled into the feed
            loadFeedContents()
        } else {
            if case .failure = feedDataSource.state {
                // Refresh button already exists on the users failure card
                return
            }
            // Possibly show the "new content available" button
            if feedDataSource.shouldLoadContent {
                feedOverlayView.showNewContentAvailableButton()
            }
        }
    }

    private func loadFeedContents(completion: (() -> Void)? = nil) {
        if !feedDataSource.shouldLoadContent {
            return
        }
        feedDataSource.load(completion)
    }

    private func hidePrivacyHub() {
        if Preferences.NewTabPage.hidePrivacyHubAlertShown.value {
            Preferences.NewTabPage.showNewTabPrivacyHub.value = false
            collectionView.reloadData()
        } else {
            let alert = UIAlertController(
                title: Strings.PrivacyHub.hidePrivacyHubWidgetActionTitle,
                message: Strings.PrivacyHub.hidePrivacyHubWidgetAlertDescription,
                preferredStyle: .alert
            )

            alert.addAction(UIAlertAction(title: Strings.cancelButtonTitle, style: .cancel))
            alert.addAction(UIAlertAction(title: Strings.PrivacyHub.hidePrivacyHubWidgetActionButtonTitle, style: .default) { [weak self] _ in
                Preferences.NewTabPage.showNewTabPrivacyHub.value = false
                Preferences.NewTabPage.hidePrivacyHubAlertShown.value = true
                self?.collectionView.reloadData()
            })

            UIImpactFeedbackGenerator(style: .medium).bzzt()
            present(alert, animated: true, completion: nil)
        }
    }

    // MARK: - Actions

    @objc private func tappedNewContentAvailable() {
        if case .loading = feedDataSource.state {
            return
        }
        let todayStart = collectionView.frame.height - feedOverlayView.headerView.bounds.height - 32 - 16
        newContentAvailableDismissTimer = nil
        feedOverlayView.newContentAvailableButton.isLoading = true
        loadFeedContents { [weak self] in
            guard let self = self else { return }
            self.feedOverlayView.hideNewContentAvailableButton()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.collectionView.setContentOffset(CGPoint(x: 0, y: todayStart), animated: true)
            }
        }
    }

    @objc private func tappedBraveNewsSettings() {
        let controller = NewsSettingsViewController(dataSource: feedDataSource, openURL: { [weak self] url in
            guard let self else { return }
            self.dismiss(animated: true)
            self.delegate?.navigateToInput(url.absoluteString, inNewTab: false, switchingToPrivateMode: false)
        })
        controller.viewDidDisappear = { [weak self] in
            if Preferences.Review.braveNewsCriteriaPassed.value {
                AppReviewManager.shared.isRevisedReviewRequired = true
                Preferences.Review.braveNewsCriteriaPassed.value = false
            }
            self?.checkForUpdatedFeed()
        }
        let container = UINavigationController(rootViewController: controller)
        present(container, animated: true)
    }

    private func tappedActiveBackgroundButton(_ sender: UIControl) {
        guard let background = background.currentBackground else { return }
        switch background {
        case .image:
            presentImageCredit(sender)
        case .sponsoredImage(let background):
            tappedSponsorButton(background.logo)
        case .superReferral(_, let code):
            tappedQRCode(code)
        }
    }

    private func tappedSponsorButton(_ logo: NTPSponsoredImageLogo) {
        UIImpactFeedbackGenerator(style: .medium).bzzt()
        if let url = logo.destinationURL {
            delegate?.navigateToInput(url.absoluteString, inNewTab: false, switchingToPrivateMode: false)
        }

        reportSponsoredImageBackgroundEvent(.clicked)
    }

    private func tappedQRCode(_ code: String) {
        // Super referrer websites come in format https://brave.com/r/REF_CODE
        let refUrl = URL(string: "https://brave.com/")?
            .appendingPathComponent("r")
            .appendingPathComponent(code)

        guard let url = refUrl else { return }
        delegate?.tappedQRCodeButton(url: url)
    }

    private func handleFavoriteAction(favorite: Favorite, action: BookmarksAction) {
        delegate?.handleFavoriteAction(favorite: favorite, action: action)
    }

    private func presentImageCredit(_ button: UIControl) {
        guard case .image(let background) = background.currentBackground else { return }

        let alert = UIAlertController(title: background.author, message: nil, preferredStyle: .actionSheet)

        if let creditURL = background.link {
            let websiteTitle = String(format: Strings.viewOn, creditURL.hostSLD.capitalizeFirstLetter)
            alert.addAction(
                UIAlertAction(title: websiteTitle, style: .default) { [weak self] _ in
                    self?.delegate?.navigateToInput(creditURL.absoluteString, inNewTab: false, switchingToPrivateMode: false)
                })
        }

        alert.popoverPresentationController?.sourceView = button
        alert.popoverPresentationController?.permittedArrowDirections = [.down, .up]
        alert.addAction(UIAlertAction(title: Strings.close, style: .cancel, handler: nil))

        UIImpactFeedbackGenerator(style: .medium).bzzt()
        present(alert, animated: true, completion: nil)
    }

    @objc private func longPressedBraveNewsSettingsButton() {
        assert(
            !AppConstants.buildChannel.isPublic,
            "Debug settings are not accessible on public builds"
        )
        let settings = BraveNewsDebugSettingsView(dataSource: feedDataSource) { [weak self] in
            self?.dismiss(animated: true)
        }
        let container = UINavigationController(
            rootViewController: UIHostingController(rootView: settings)
        )
        present(container, animated: true)
    }
}

extension NewTabPageViewController: PreferencesObserver {
    func preferencesDidChange(for key: String) {
        if key == Preferences.NewTabPage.showNewTabPrivacyHub.key || key == Preferences.NewTabPage.showNewTabFavourites.key {
            collectionView.reloadData()
            return
        }

        if !preventReloadOnBraveNewsEnabledChange {
            collectionView.reloadData()
        }
        if !isBraveNewsVisible {
            collectionView.verticalScrollIndicatorInsets = .zero
            feedOverlayView.headerView.alpha = 0.0
            //  backgroundButtonsView.alpha = 1.0
        }
        preventReloadOnBraveNewsEnabledChange = false
    }
}

// MARK: - UIScrollViewDelegate

extension NewTabPageViewController {
    var isBraveNewsVisible: Bool {
        return !privateBrowsingManager.isPrivateBrowsing && (Preferences.BraveNews.isEnabled.value || Preferences.BraveNews.isShowingOptIn.value)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        for section in sections {
            section.scrollViewDidScroll?(scrollView)
        }
//        guard isBraveNewsVisible, let newsSection = layout.braveNewsSection else { return }
//        if collectionView.numberOfItems(inSection: newsSection) > 0 {
//            // Hide the buttons as Brave News feeds appear
//            backgroundButtonsView.alpha = 1.0 - max(0.0, min(1.0, (scrollView.contentOffset.y - scrollView.contentInset.top) / 16))
//            // Show the header as Brave News feeds appear
//            // Offset of where Brave News starts
//            let todayStart = collectionView.frame.height - feedOverlayView.headerView.bounds.height - 32 - 16
//            // Offset of where the header should begin becoming visible
//            let alphaInStart = collectionView.frame.height / 2.0
//            let value = scrollView.contentOffset.y
//            let alpha = max(0.0, min(1.0, (value - alphaInStart) / (todayStart - alphaInStart)))
//            feedOverlayView.headerView.alpha = alpha
//
//            if feedOverlayView.newContentAvailableButton.alpha != 0, !feedOverlayView.newContentAvailableButton.isLoading {
//                let velocity = scrollView.panGestureRecognizer.velocity(in: scrollView).y
//                if velocity > 0, collectionView.contentOffset.y < todayStart {
//                    // Scrolling up
//                    feedOverlayView.hideNewContentAvailableButton()
//                } else if velocity < 0 {
//                    // Scrolling down
//                    if newContentAvailableDismissTimer == nil {
//                        let timer = Timer(
//                            timeInterval: 4,
//                            repeats: false
//                        ) { [weak self] _ in
//                            guard let self = self else { return }
//                            self.feedOverlayView.hideNewContentAvailableButton()
//                            self.newContentAvailableDismissTimer = nil
//                        }
//                        // Adding the timer manually under `common` mode allows it to execute while the user
//                        // is scrolling through the feed rather than have to wait until input stops
//                        RunLoop.main.add(timer, forMode: .common)
//                        newContentAvailableDismissTimer = timer
//                    }
//                }
//            }
//
        ////            if scrollView.contentOffset.y >= todayStart {
        ////                recordBraveNewsUsageP3A()
        ////            }
//        }
    }

    /// Moves New Tab Page Scroll to start of Brave News - Used for shortcut
    func scrollToBraveNews() {
        // Offset of where Brave News starts
        let todayStart = collectionView.frame.height - feedOverlayView.headerView.bounds.height - 32 - 16
        collectionView.contentOffset.y = todayStart
    }

    // MARK: - P3A

//    private func recordBraveNewsUsageP3A() {
//        let braveNewsFeatureUsage = P3AFeatureUsage.braveNewsFeatureUsage
//        if !isBraveNewsVisible || !Preferences.BraveNews.isEnabled.value ||
//            Calendar.current.startOfDay(for: Date()) == braveNewsFeatureUsage.lastUsageOption.value
//        {
//            // Don't have Brave News enabled, or already recorded todays usage, no need to do it again
//            return
//        }
//
//        // Usage
//        braveNewsFeatureUsage.recordUsage()
//        var braveNewsWeeklyCount = P3ATimedStorage<Int>.braveNewsWeeklyCount
//        braveNewsWeeklyCount.add(value: 1, to: Date())
//
//        // Usage over the past month
//        var braveNewsDaysUsedStorage = P3ATimedStorage<Int>.braveNewsDaysUsedStorage
//        braveNewsDaysUsedStorage.replaceTodaysRecordsIfLargest(value: 1)
//        recordBraveNewsDaysUsedP3A()
//
//        // Weekly usage
//        recordBraveNewsWeeklyUsageCountP3A()
//    }

//    private func recordBraveNewsWeeklyUsageCountP3A() {
//        let storage = P3ATimedStorage<Int>.braveNewsWeeklyCount
//        UmaHistogramRecordValueToBucket(
//            "Brave.Today.WeeklySessionCount",
//            buckets: [
//                0,
//                1,
//                .r(2...3),
//                .r(4...7),
//                .r(8...12),
//                .r(13...18),
//                .r(19...25),
//                .r(26...),
//            ],
//            value: storage.combinedValue
//        )
//    }

//    private func recordBraveNewsDaysUsedP3A() {
//        let storage = P3ATimedStorage<Int>.braveNewsDaysUsedStorage
//        UmaHistogramRecordValueToBucket(
//            "Brave.Today.DaysInMonthUsedCount",
//            buckets: [
//                0,
//                1,
//                2,
//                .r(3...5),
//                .r(6...10),
//                .r(11...15),
//                .r(16...20),
//                .r(21...),
//            ],
//            value: storage.combinedValue
//        )
//    }

//    private func recordBraveNewsArticlesVisitedP3A() {
//        // Count is per NTP session, sends max value of the week
//        var storage = P3ATimedStorage<Int>.braveNewsVisitedArticlesCount
//        storage.replaceTodaysRecordsIfLargest(value: newsArticlesOpened.count)
//        UmaHistogramRecordValueToBucket(
//            "Brave.Today.WeeklyMaxCardVisitsCount",
//            buckets: [
//                0, // won't ever be sent
//                1,
//                .r(2...3),
//                .r(4...6),
//                .r(7...10),
//                .r(11...15),
//                .r(16...),
//            ],
//            value: storage.maximumDaysCombinedValue
//        )
//    }
//
//    private func recordNewTabCreatedP3A() {
//        var newTabsStorage = P3ATimedStorage<Int>.newTabsCreatedStorage
//        var sponsoredStorage = P3ATimedStorage<Int>.sponsoredNewTabsCreatedStorage
//
//        newTabsStorage.add(value: 1, to: Date())
//        let newTabsCreatedAnswer = newTabsStorage.maximumDaysCombinedValue
//
//        if case .sponsoredImage = background.currentBackground {
//            sponsoredStorage.add(value: 1, to: Date())
//        }
//
//        UmaHistogramRecordValueToBucket(
//            "Brave.NTP.NewTabsCreated",
//            buckets: [
//                0,
//                .r(1...3),
//                .r(4...8),
//                .r(9...20),
//                .r(21...50),
//                .r(51...100),
//                .r(101...),
//            ],
//            value: newTabsCreatedAnswer
//        )
//
//        if newTabsCreatedAnswer > 0 {
//            let sponsoredPercent = Int((Double(sponsoredStorage.maximumDaysCombinedValue) / Double(newTabsCreatedAnswer)) * 100.0)
//            UmaHistogramRecordValueToBucket(
//                "Brave.NTP.SponsoredNewTabsCreated",
//                buckets: [
//                    0,
//                    .r(0..<10),
//                    .r(10..<20),
//                    .r(20..<30),
//                    .r(30..<40),
//                    .r(40..<50),
//                    .r(50...),
//                ],
//                value: sponsoredPercent
//            )
//        }
//    }
}

// MARK: - NewTabPageP3AHelperDataSource

extension NewTabPageViewController: NewTabPageP3AHelperDataSource {
    var currentTabURL: URL? {
        tab?.url
    }

    var isRewardsEnabled: Bool {
        rewards.isEnabled
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension NewTabPageViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        sections[indexPath.section].collectionView?(collectionView, didSelectItemAt: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        sections[indexPath.section].collectionView?(collectionView, layout: collectionViewLayout, sizeForItemAt: indexPath) ?? .zero
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let sectionProvider = sections[section]
        var inset = sectionProvider.collectionView?(collectionView, layout: collectionViewLayout, insetForSectionAt: section) ?? .zero
        if sectionProvider.landscapeBehavior == .halfWidth {
            let isIphone = UIDevice.isPhone
            let isLandscape = view.frame.width > view.frame.height
            if isLandscape {
                let availableWidth = collectionView.bounds.width - collectionView.safeAreaInsets.left - collectionView.safeAreaInsets.right
                if isIphone {
                    inset.left = availableWidth / 2.0
                } else {
                    inset.right = availableWidth / 2.0
                }
            }
        }
        return inset
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        sections[section].collectionView?(collectionView, layout: collectionViewLayout, minimumLineSpacingForSectionAt: section) ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        sections[section].collectionView?(collectionView, layout: collectionViewLayout, minimumInteritemSpacingForSectionAt: section) ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        sections[section].collectionView?(collectionView, layout: collectionViewLayout, referenceSizeForHeaderInSection: section) ?? .zero
    }
}

// MARK: - UICollectionViewDelegate

extension NewTabPageViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        sections[indexPath.section].collectionView?(collectionView, willDisplay: cell, forItemAt: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        sections[indexPath.section].collectionView?(collectionView, didEndDisplaying: cell, forItemAt: indexPath)
    }
}

// MARK: - UICollectionViewDataSource

extension NewTabPageViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].collectionView(collectionView, numberOfItemsInSection: section)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        sections[indexPath.section].collectionView(collectionView, cellForItemAt: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        sections[indexPath.section].collectionView?(collectionView, viewForSupplementaryElementOfKind: kind, at: indexPath) ?? UICollectionReusableView()
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        sections[indexPath.section].collectionView?(collectionView, contextMenuConfigurationForItemAt: indexPath, point: point)
    }

    func collectionView(_ collectionView: UICollectionView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath else {
            return nil
        }
        return sections[indexPath.section].collectionView?(collectionView, previewForHighlightingContextMenuWithConfiguration: configuration)
    }

    func collectionView(_ collectionView: UICollectionView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath else {
            return nil
        }
        return sections[indexPath.section].collectionView?(collectionView, previewForHighlightingContextMenuWithConfiguration: configuration)
    }

    func collectionView(_ collectionView: UICollectionView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        guard let indexPath = configuration.identifier as? IndexPath else {
            return
        }
        sections[indexPath.section].collectionView?(collectionView, willPerformPreviewActionForMenuWith: configuration, animator: animator)
    }
}

// MARK: - UICollectionViewDragDelegate & UICollectionViewDropDelegate

extension NewTabPageViewController: UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        // Check If the item that is dragged is a favourite item
        guard sections[indexPath.section] is FavoritesSectionProvider else {
            return []
        }

        let itemProvider = NSItemProvider(object: "\(indexPath)" as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider).then {
            $0.previewProvider = { () -> UIDragPreview? in
                guard let cell = collectionView.cellForItem(at: indexPath) as? FavoriteCell else {
                    return nil
                }
                return UIDragPreview(view: cell.imageView)
            }
        }

        return [dragItem]
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let sourceIndexPath = coordinator.items.first?.sourceIndexPath else { return }
        let destinationIndexPath: IndexPath

        if let indexPath = coordinator.destinationIndexPath {
            destinationIndexPath = indexPath
        } else {
            let section = max(collectionView.numberOfSections - 1, 0)
            let row = collectionView.numberOfItems(inSection: section)
            destinationIndexPath = IndexPath(row: max(row - 1, 0), section: section)
        }

        guard sourceIndexPath.section == destinationIndexPath.section else { return }

        if coordinator.proposal.operation == .move {
            guard let item = coordinator.items.first else { return }
            _ = coordinator.drop(item.dragItem, toItemAt: destinationIndexPath)

            guard let favouritesSection = sections.firstIndex(where: { $0 is FavoritesSectionProvider }) else {
                return
            }

            Favorite.reorder(
                sourceIndexPath: sourceIndexPath,
                destinationIndexPath: destinationIndexPath,
                isInteractiveDragReorder: true
            )

            UIView.performWithoutAnimation {
                self.collectionView.reloadSections(IndexSet(integer: favouritesSection))
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard let destinationIndexSection = destinationIndexPath?.section,
              let favouriteSection = sections[destinationIndexSection] as? FavoritesSectionProvider,
              favouriteSection.hasMoreThanOneFavouriteItems
        else {
            return .init(operation: .cancel)
        }

        return .init(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        fetchInteractionPreviewParameters(at: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, dropPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        fetchInteractionPreviewParameters(at: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool {
        return true
    }

    private func fetchInteractionPreviewParameters(at indexPath: IndexPath) -> UIDragPreviewParameters {
        let previewParameters = UIDragPreviewParameters().then {
            $0.backgroundColor = .clear

            if let cell = collectionView.cellForItem(at: indexPath) as? FavoriteCell {
                $0.visiblePath = UIBezierPath(roundedRect: cell.imageView.frame, cornerRadius: 8)
            }
        }

        return previewParameters
    }
}

extension NewTabPageViewController {
    private class NewTabCollectionView: UICollectionView {
        override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
            super.init(frame: frame, collectionViewLayout: layout)

            // UIColor(named: "reside_bg", in: .module, compatibleWith: nil)
            backgroundColor = .clear
            delaysContentTouches = false
            alwaysBounceVertical = true
            showsHorizontalScrollIndicator = false
            // Needed for some reason, as its not setting safe area insets while in landscape
            contentInsetAdjustmentBehavior = .always
            showsVerticalScrollIndicator = false
            // Even on light mode we use a darker background now
            indicatorStyle = .white

            // Drag should be enabled to rearrange favourite
            dragInteractionEnabled = true
        }

        @available(*, unavailable)
        required init(coder: NSCoder) {
            fatalError()
        }

        override func touchesShouldCancel(in view: UIView) -> Bool {
            return true
        }
    }
}

private extension P3AFeatureUsage {
    static var braveNewsFeatureUsage: Self = .init(
        name: "brave-news-usage",
        histogram: "Brave.Today.LastUsageTime",
        returningUserHistogram: "Brave.Today.NewUserReturning"
    )
}

private extension P3ATimedStorage where Value == Int {
    static var braveNewsDaysUsedStorage: Self { .init(name: "brave-news-days-used", lifetimeInDays: 30) }
    static var braveNewsWeeklyCount: Self { .init(name: "brave-news-weekly-usage", lifetimeInDays: 7) }
    static var braveNewsVisitedArticlesCount: Self { .init(name: "brave-news-weekly-clicked", lifetimeInDays: 7) }
    static var newTabsCreatedStorage: Self { .init(name: "new-tabs-created", lifetimeInDays: 7) }
    static var sponsoredNewTabsCreatedStorage: Self { .init(name: "sponsored-new-tabs-created", lifetimeInDays: 7) }
}
