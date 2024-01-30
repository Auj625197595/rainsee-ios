// 版权声明
// 版权所有 © 2023 Brave 作者。保留所有权利。
// 此源代码形式受 Mozilla Public License, v. 2.0 许可条款的约束。
// 如果没有随此文件分发 MPL 的副本，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import SwiftUI
import BraveUI
import BraveNews
import BraveCore
import Strings
import Preferences

// 高级护盾设置视图
struct AdvancedShieldsSettingsView: View {
  
  // 监听对象，用于观察设置的变化
  @ObservedObject private var settings: AdvancedShieldsSettings
  
  // 控制是否显示管理网站数据的标志
  @State private var showManageWebsiteData = false
  
  // 打开 URL 的操作闭包
  var openURLAction: ((URL) -> Void)?
  
  // 初始化方法
  init(
    profile: Profile, tabManager: TabManager,
    feedDataSource: FeedDataSource, historyAPI: BraveHistoryAPI, p3aUtilities: BraveP3AUtils,
    clearDataCallback: @escaping AdvancedShieldsSettings.ClearDataCallback
  ) {
    self.settings = AdvancedShieldsSettings(
      profile: profile,
      tabManager: tabManager,
      feedDataSource: feedDataSource,
      historyAPI: historyAPI,
      p3aUtilities: p3aUtilities,
      clearDataCallback: clearDataCallback
    )
  }

  // 视图的主体
  var body: some View {
    List {
      // 默认护盾视图
      DefaultShieldsViewView(settings: settings)
      
      // 清除数据部分视图
      ClearDataSectionView(settings: settings)
      
      // 护盾设置部分
      Section {
        // 管理网站数据按钮
        Button {
          showManageWebsiteData = true
        } label: {
          // 用于显示箭头的小技巧
          NavigationLink(destination: { EmptyView() }, label: {
            ShieldLabelView(
              title: Strings.manageWebsiteDataTitle,
              subtitle: nil
            )
          })
        }
        .buttonStyle(.plain)
        .listRowBackground(Color(.secondaryBraveGroupedBackground))
        .sheet(isPresented: $showManageWebsiteData) {
          ManageWebsiteDataView()
        }
        
        // 隐私报告设置导航链接
        NavigationLink { 
          PrivacyReportSettingsView()
        } label: {
          ShieldLabelView(
            title: Strings.PrivacyHub.privacyReportsTitle,
            subtitle: nil
          )
        }.listRowBackground(Color(.secondaryBraveGroupedBackground))
      }
      
      // 其他隐私设置部分
      OtherPrivacySettingsSectionView(settings: settings)
    }
    .listBackgroundColor(Color(UIColor.braveGroupedBackground))
    .listStyle(.insetGrouped)
    .navigationTitle(Strings.braveShieldsAndPrivacy)
    .environment(\.openURL, .init(handler: { [openURLAction] url in
      openURLAction?(url)
      return .handled
    }))
  }
}
