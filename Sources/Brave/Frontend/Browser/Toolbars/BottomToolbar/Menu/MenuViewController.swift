// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import UIKit
import PanModal
import Shared
import BraveShared
import BraveUI
import SwiftUI
import Growth

// 菜单项头部视图，显示图标、标题和副标题
struct MenuItemHeaderView: View {
  @Environment(\.colorScheme) private var colorScheme: ColorScheme
  @ScaledMetric private var iconSize: CGFloat = 32.0
  var icon: Image
  var title: String
  var subtitle: String?
  var body: some View {
    HStack(spacing: 14) {
      // 图标
      icon
        .font(.body)
        .frame(width: iconSize, height: iconSize)
        .foregroundColor(Color(.braveLabel))
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.secondaryBraveGroupedBackground))
            .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
        )
        .padding(.vertical, 2)
      VStack(alignment: .leading, spacing: 3) {
        // 标题
        Text(verbatim: title)
        // 副标题
        if let subTitle = subtitle {
          Text(subTitle)
            .font(.subheadline)
            .foregroundColor(Color(.secondaryBraveLabel))
        }
      }
      .padding(.vertical, subtitle != nil ? 5 : 0)
    }
    .foregroundColor(Color(.braveLabel))
  }
}

// 私有结构体，用于呈现菜单内容的 ScrollView
private struct MenuView<Content: View>: View {
  var content: Content
  var body: some View {
    ScrollView(.vertical) {
      content
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .accentColor(Color(.braveBlurpleTint))
    }
  }
}

// 菜单项按钮，包含图标、标题、副标题和触发动作
struct MenuItemButton: View {
  @Environment(\.colorScheme) var colorScheme: ColorScheme

  var icon: Image
  var title: String
  var subtitle: String?
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      // 菜单项头部视图
      MenuItemHeaderView(icon: icon, title: title, subtitle: subtitle)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 44.0, alignment: .leading)
    }
    .buttonStyle(TableCellButtonStyle())
  }
}

// 菜单视图控制器，继承 UINavigationController，并实现 UIPopoverPresentationControllerDelegate 协议
class MenuViewController: UINavigationController, UIPopoverPresentationControllerDelegate {

  private var menuNavigationDelegate: MenuNavigationControllerDelegate?
  private let initialHeight: CGFloat

  // 初始化方法，接受初始高度和一个用于构建菜单内容的闭包
  init<MenuContent: View>(initialHeight: CGFloat, @ViewBuilder content: (MenuViewController) -> MenuContent) {
    self.initialHeight = initialHeight
    super.init(nibName: nil, bundle: nil)
    viewControllers = [MenuHostingController(content: content(self))]
    menuNavigationDelegate = MenuNavigationControllerDelegate(panModal: self)
    delegate = menuNavigationDelegate
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }

  private var previousPreferredContentSize: CGSize?
  
  // 呈现内部菜单，可选择是否展开至长表单形式
  func presentInnerMenu(
    _ viewController: UIViewController,
    expandToLongForm: Bool = true
  ) {
    let container = InnerMenuNavigationController(rootViewController: viewController)
    container.delegate = menuNavigationDelegate
    container.modalPresentationStyle = .overCurrentContext  // 为了修复 dismiss 动画
    container.innerMenuDismissed = { [weak self] in
      guard let self = self else { return }
      if !self.isDismissing {
        self.panModalSetNeedsLayoutUpdate()
      }
      // 恢复原始内容大小
      if let contentSize = self.previousPreferredContentSize {
        self.preferredContentSize = contentSize
      }
    }
    // 保存当前内容大小，在内部菜单关闭时恢复
    if preferredContentSize.height < 580 {
      previousPreferredContentSize = preferredContentSize
      preferredContentSize = CGSize(width: 375, height: 580)
    }
    present(container, animated: true) {
      self.panModalSetNeedsLayoutUpdate()
    }
    if expandToLongForm {
      // 延迟一小段时间，使动画看起来更加流畅
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        self.panModalTransition(to: .longForm)
      }
    }
  }

  // 推入内部菜单，可选择是否展开至长表单形式
  func pushInnerMenu(
    _ viewController: UIViewController,
    expandToLongForm: Bool = true
  ) {
    super.pushViewController(viewController, animated: true)
    if expandToLongForm {
      panModalTransition(to: .longForm)
    }
  }

  @available(*, unavailable, message: "Use 'pushInnerMenu(_:expandToLongForm:)' instead")
  override func pushViewController(_ viewController: UIViewController, animated: Bool) {
    super.pushViewController(viewController, animated: animated)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationBar.isTranslucent = false
    recordMenuOpenedP3A()
  }
  
  // 记录菜单打开的 P3A 事件
  private func recordMenuOpenedP3A() {
    var storage = P3ATimedStorage<Int>.menuPresentedStorage
    storage.add(value: 1, to: Date())
    UmaHistogramRecordValueToBucket(
      "Brave.Toolbar.MenuOpens",
      buckets: [
        0,
        .r(1...5),
        .r(6...15),
        .r(16...29),
        .r(30...49),
        .r(50...),
      ],
      value: storage.combinedValue
    )
  }

  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()

    // 由于 pan modal 与隐藏导航栏引起的 bug，导致安全区域插图归零
    if view.safeAreaInsets == .zero, isPanModalPresented,
      var insets = view.window?.safeAreaInsets {
      // 当发生此情况时，通过 additionalSafeAreaInsets 重新设置它们
      // 使用 window 的安全区域，因为 pan modal 出现在整个屏幕上，我们可以安全地使用 window 的安全区域
      // 顶部将保持为 0，因为我们使用的是非透明导航栏，并且顶部永远不会达到安全区域（由 pan modal 处理）
      insets.top = 0
      additionalSafeAreaInsets = insets
    }
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    .lightContent
  }

  override var shouldAutorotate: Bool {
    // 由于 PanModal 中的 bug，当打开此菜单时，呈现控制器不会接收到安全区域更新，因此目前不允许旋转
    //
    // 问题：https://github.com/slackhq/PanModal/issues/139
    false
  }

  private var isDismissing = false

  override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
    if let _ = presentedViewController as? InnerMenuNavigationController,
      presentingViewController?.presentedViewController === self {
      isDismissing = true
      presentingViewController?.dismiss(animated: flag, completion: completion)
    } else {
      super.dismiss(animated: flag, completion: completion)
    }
  }

  private var isPresentingInnerMenu: Bool {
    presentedViewController is InnerMenuNavigationController
  }

  override func accessibilityPerformEscape() -> Bool {
    dismiss(animated: true)
    return true
  }
}

// MARK: PanModalPresentable

extension MenuViewController: PanModalPresentable {
  var panScrollable: UIScrollView? {
    // 对于 SwiftUI：
    //  - 在 iOS 13 中，ScrollView 存在于主机视图中
    //  - 在 iOS 14 中，它将是一个直接的子视图
    // 对于 UIKit：
    //  - UITableViewController 的视图是 UITableView，因此视图本身是 UIScrollView
    //  - 对于我们的非 UITVC，滚动视图通常是主视图的子视图
    func _scrollViewChild(in parentView: UIView, depth: Int = 0) -> UIScrollView? {
      if depth > 2 { return nil }
      if let scrollView = parentView as? UIScrollView {
        return scrollView
      }
      for view in parentView.subviews {
        if let scrollView = view as? UIScrollView {
          return scrollView
        }
        if !view.subviews.isEmpty, let childScrollView = _scrollViewChild(in: view, depth: depth + 1) {
          return childScrollView
        }
      }
      return nil
    }
    if let vc = presentedViewController, !vc.isBeingPresented {
      if let nc = vc as? UINavigationController, let vc = nc.topViewController {
        let scrollView = _scrollViewChild(in: vc.view)
        return scrollView
      }
      let scrollView = _scrollViewChild(in: vc.view)
      return scrollView
    }
    guard let topVC = topViewController else { return nil }
    topVC.view.layoutIfNeeded()
    return _scrollViewChild(in: topVC.view)
  }
  var topOffset: CGFloat {
    let topInset = view.window?.safeAreaInsets.top ?? 0
    return topInset + 32
  }
  var longFormHeight: PanModalHeight {
    .maxHeight
  }
  var shortFormHeight: PanModalHeight {
    isPresentingInnerMenu ? .maxHeight : .contentHeight(initialHeight)
  }

  func shouldRespond(to panModalGestureRecognizer: UIPanGestureRecognizer) -> Bool {
    // 这允许重新排列元素而不与 PanModal 手势冲突，参见 bug #3787。
    if let tableView = panScrollable as? UITableView, tableView.isEditing {
      return false
    }
    return true
  }

  var allowsExtendedPanScrolling: Bool {
    true
  }
  var cornerRadius: CGFloat {
    10.0
  }
  var anchorModalToLongForm: Bool {
    isPresentingInnerMenu
  }
  var panModalBackgroundColor: UIColor {
    UIColor(white: 0.0, alpha: 0.5)
  }

  var dragIndicatorBackgroundColor: UIColor {
    UIColor(white: 0.95, alpha: 1.0)
  }
  var transitionDuration: Double {
    0.35
  }
  var springDamping: CGFloat {
    0.85
  }
}

// 私有类，用于承载 SwiftUI 菜单内容的 UIHostingController
private class MenuHostingController<MenuContent: View>: UIHostingController<MenuView<MenuContent>> {
  init(content: MenuContent) {
    super.init(rootView: MenuView(content: content))
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    .lightContent
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    let animateNavBar = (navigationController?.isBeingPresented == false ? animated : false)
    navigationController?.setNavigationBarHidden(true, animated: animateNavBar)
    self.navigationController?.preferredContentSize = {
      let controller = UIHostingController(rootView: self.rootView.content)
      let size = controller.view.sizeThatFits(CGSize(width: 375, height: 0))
      let navBarHeight = navigationController?.navigationBar.bounds.height ?? 0
      let preferredPopoverWidth: CGFloat = 375.0
      let minimumPopoverHeight: CGFloat = 240.0
      let maximumPopoverHeight: CGFloat = 580.0
      return CGSize(
        width: preferredPopoverWidth,
        // 必须通过隐藏的导航栏高度增加内容大小，以便在用户在菜单中导航时，大小不会改变
        height: min(max(size.height + 16, minimumPopoverHeight), maximumPopoverHeight + navBarHeight)
      )
    }()
    view.backgroundColor = .braveGroupedBackground
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if navigationController?.isBeingDismissed == false {
      navigationController?.setNavigationBarHidden(false, animated: animated)
      navigationController?.preferredContentSize = CGSize(width: 375, height: 580)
    }
  }
}

// MARK: MenuNavigationControllerDelegate

// 私有类，用于处理 UINavigationControllerDelegate 事件
private class MenuNavigationControllerDelegate: NSObject, UINavigationControllerDelegate {
  weak var panModal: (UIViewController & PanModalPresentable)?
  init(panModal: UIViewController & PanModalPresentable) {
    self.panModal = panModal
    super.init()
  }
  func navigationController(
    _ navigationController: UINavigationController,
    didShow viewController: UIViewController,
    animated: Bool
  ) {
    panModal?.panModalSetNeedsLayoutUpdate()
  }
  public func navigationControllerSupportedInterfaceOrientations(_ navigationController: UINavigationController) -> UIInterfaceOrientationMask {
    return navigationController.visibleViewController?.supportedInterfaceOrientations ?? navigationController.supportedInterfaceOrientations
  }

  public func navigationControllerPreferredInterfaceOrientationForPresentation(_ navigationController: UINavigationController) -> UIInterfaceOrientation {
    return navigationController.visibleViewController?.preferredInterfaceOrientationForPresentation ?? navigationController.preferredInterfaceOrientationForPresentation
  }
}

private class InnerMenuNavigationController: UINavigationController {
  var innerMenuDismissed: (() -> Void)?

  override func viewDidLoad() {
    super.viewDidLoad()

    // Needed or else pan modal top scroll insets are messed up for some reason
    navigationBar.isTranslucent = false
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    innerMenuDismissed?()
  }
}

class ColorAwareNavigationController: UINavigationController {
  var statusBarStyle: UIStatusBarStyle = .default {
    didSet {
      setNeedsStatusBarAppearanceUpdate()
    }
  }
  override var preferredStatusBarStyle: UIStatusBarStyle {
    return statusBarStyle
  }
}

extension P3ATimedStorage where Value == Int {
  fileprivate static var menuPresentedStorage: Self { .init(name: "menu-presented", lifetimeInDays: 7) }
}
