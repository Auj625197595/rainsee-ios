// 版权声明
// 版权所有© 2022 勇者作者。保留所有权利。
// 本源代码形式受 Mozilla Public License, v. 2.0 的条款约束。
// 如果没有随此文件一同分发MPL许可证的副本，
// 您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import Shared
import SwiftUI
import BraveUI
import Preferences

/// 夜间模式菜单按钮，提供切换夜间模式的快捷方式
struct NightModeMenuButton: View {
  // 使用 @ObservedObject 包装的夜间模式状态对象
  @ObservedObject private var nightMode = Preferences.General.nightModeEnabled
  // 是否显示视图的状态
  @State private var isViewDisplayed = false

  // 用于关闭视图的回调函数
  var dismiss: () -> Void
  
  var body: some View {
    HStack {
      // 菜单项的头部，包括图标和标题
      MenuItemHeaderView(
        icon: Image(braveSystemName: "leo.theme.dark"), // 使用 Brave 主题系统的图标
        title: Strings.NightMode.settingsTitle) // 夜间模式设置的标题
      Spacer() // 占位符，用于将 Toggle 推到右侧
      // 夜间模式的 Toggle 开关
      Toggle("", isOn: $nightMode.value)
        .labelsHidden() // 隐藏标签
        .toggleStyle(SwitchToggleStyle(tint: .accentColor)) // 切换样式，使用强调色
        .onChange(of: nightMode.value) { _ in
          guard isViewDisplayed else { return }
          dismiss()
        }
    }
    .padding(.horizontal, 14) // 左右边距
    .frame(maxWidth: .infinity, minHeight: 48.0) // 最大宽度和最小高度
    .background(
      // 用于点击整个区域切换夜间模式的透明按钮
      Button(action: {
        Preferences.General.nightModeEnabled.value.toggle()
        dismiss()
      }) {
        Color.clear
      }
      .buttonStyle(TableCellButtonStyle()) // 按钮样式
    )
    .accessibilityElement() // 辅助功能元素
    .accessibility(addTraits: .isButton) // 添加按钮特性
    .accessibility(label: Text(Strings.NightMode.settingsTitle)) // 辅助功能标签
    .onAppear {
        isViewDisplayed = true
    }
    .onDisappear {
        isViewDisplayed = false
    }
  }
}
