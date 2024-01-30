// 版权 2022 Brave 作者。保留所有权利。
// 此源代码表单受 Mozilla Public License，版本 2.0 的条款约束。
// 如果未随此文件分发 MPL 的副本，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import UIKit
import Shared

// 扩展 BrowserViewController，实现 KeyboardHelperDelegate 协议
extension BrowserViewController: KeyboardHelperDelegate {
  
  // 键盘将要显示时的回调
  public func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardWillShowWithState state: KeyboardState) {
    // 更新键盘状态
    keyboardState = state
    
    // 检查是否使用底部工具栏，且顶部工具栏不在覆盖模式下，且没有弹出的视图控制器
    if isUsingBottomBar && !topToolbar.inOverlayMode && presentedViewController == nil {
      UIView.animate(withDuration: 0.1) { [self] in
        // 由于工具栏的折叠/展开是基于许多 web 视图特性（如内容大小等）的，我们无法直接设置工具栏状态为折叠状态，因此直接使用折叠的工具栏视图
        if toolbarVisibilityViewModel.toolbarState == .expanded {
          header.collapsedBarContainerView.alpha = 1
        }
        header.expandedBarStackView.alpha = 0
        updateTabsBarVisibility()
      }
      collapsedURLBarView.isKeyboardVisible = true
      toolbarVisibilityViewModel.isEnabled = false
    }
    updateViewConstraints()
    
    // 动画显示键盘
    UIViewPropertyAnimator(duration: state.animationDuration, curve: state.animationCurve) {
      self.alertStackView.layoutIfNeeded()
      if self.isUsingBottomBar {
        self.header.superview?.layoutIfNeeded()
      }
    }
    .startAnimation()
    
    // 获取当前选中标签页的 web 视图，然后执行判断网站是否支持开放搜索引擎
    guard let webView = tabManager.selectedTab?.webView else { return }
    self.evaluateWebsiteSupportOpenSearchEngine(webView)
  }
  
  // 键盘将要隐藏时的回调
  public func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardWillHideWithState state: KeyboardState) {
    // 清空键盘状态
    keyboardState = nil
    
    // 检查是否使用底部工具栏，且顶部工具栏不在覆盖模式下，且没有弹出的视图控制器，或者折叠的 URL 栏可见时总是重置状态
    if isUsingBottomBar && !topToolbar.inOverlayMode &&
        (presentedViewController == nil || collapsedURLBarView.isKeyboardVisible) ||
        !toolbarVisibilityViewModel.isEnabled {
      UIView.animate(withDuration: 0.1) { [self] in
        // 由于工具栏的折叠/展开是基于许多 web 视图特性（如内容大小等）的，我们无法直接设置工具栏状态为展开状态，因此直接使用展开的工具栏视图
        if toolbarVisibilityViewModel.toolbarState == .expanded {
          header.collapsedBarContainerView.alpha = 0
        }
        header.expandedBarStackView.alpha = 1
        updateTabsBarVisibility()
        toolbarVisibilityViewModel.isEnabled = true
      }
      collapsedURLBarView.isKeyboardVisible = false
    }
    updateViewConstraints()
    
    // 清空自定义搜索栏按钮组
    customSearchBarButtonItemGroup?.barButtonItems.removeAll()
    customSearchBarButtonItemGroup = nil
    
    // 如果自定义搜索引擎按钮在视图中，将其移除
    if customSearchEngineButton.superview != nil {
      customSearchEngineButton.removeFromSuperview()
    }
    
    // 动画隐藏键盘
    UIViewPropertyAnimator(duration: state.animationDuration, curve: state.animationCurve) {
      self.alertStackView.layoutIfNeeded()
      if self.isUsingBottomBar {
        self.header.superview?.layoutIfNeeded()
      }
    }
    .startAnimation()
  }
}
