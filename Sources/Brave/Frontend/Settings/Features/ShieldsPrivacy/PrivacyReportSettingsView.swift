// 版权 2022 年 Brave 作者。保留所有权利。
// 此源代码表单受 Mozilla Public License，v. 2.0 条款的约束。
// 如果未随此文件分发 MPL 的副本，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import SwiftUI
import Shared
import Preferences
import BraveUI

struct PrivacyReportSettingsView: View {
  
  // 监听用户隐私报告中“捕获护盾数据”和“捕获VPN警报”开关的状态
  @ObservedObject private var shieldsDataEnabled = Preferences.PrivacyReports.captureShieldsData
  @ObservedObject private var vpnAlertsEnabled = Preferences.PrivacyReports.captureVPNAlerts
  
  // 是否显示清除数据提示
  @State private var showClearDataPrompt: Bool = false
  
  var body: some View {
    List {
      // 护盾数据开关
      Section(footer: Text(Strings.PrivacyHub.settingsEnableShieldsFooter)) {
        Toggle(Strings.PrivacyHub.settingsEnableShieldsTitle, isOn: $shieldsDataEnabled.value)
          .toggleStyle(SwitchToggleStyle(tint: .accentColor))
      }
      .listRowBackground(Color(.secondaryBraveGroupedBackground))
      
//      // VPN警报开关
//      Section(footer: Text(Strings.PrivacyHub.settingsEnableVPNAlertsFooter)) {
//        Toggle(Strings.PrivacyHub.settingsEnableVPNAlertsTitle, isOn: $vpnAlertsEnabled.value)
//          .toggleStyle(SwitchToggleStyle(tint: .accentColor))
//      }
//      .listRowBackground(Color(.secondaryBraveGroupedBackground))
      
      // 清除数据部分
      Section(footer: Text(Strings.PrivacyHub.settingsSlearDataFooter)) {
        HStack() {
          Button(action: {
            showClearDataPrompt = true
          },
                 label: {
            Text(Strings.PrivacyHub.settingsSlearDataTitle)
              .frame(maxWidth: .infinity, alignment: .leading)
              .foregroundColor(Color.red)
          })
            .actionSheet(isPresented: $showClearDataPrompt) {
              // 目前 .actionSheet 不允许您为 sheet 留下空标题。
              // 一旦 iOS 15 成为最低支持版本，这可以转换为 .confirmationPrompt 或带有破坏性按钮的菜单
              .init(title: Text(Strings.PrivacyHub.clearAllDataPrompt),
                    buttons: [
                      .destructive(Text(Strings.yes), action: {
                        PrivacyReportsManager.clearAllData()
                      }),
                      .cancel()
                    ])
            }
        }
      }
      .listRowBackground(Color(.secondaryBraveGroupedBackground))
      
      // MARK: - Mini debug 部分。
      // 仅在非公开版本下显示，用于调试目的
      if !AppConstants.buildChannel.isPublic {
        Section(footer: Text("这将强制所有数据进行合并。所有 '最近7天' 的统计信息应该被清除，而 '所有时间的数据' 视图应该被保留。")) {
          HStack() {
            Button(action: {
              Preferences.PrivacyReports.nextConsolidationDate.value = Date().advanced(by: -2.days)
              PrivacyReportsManager.consolidateData(dayRange: -10)
            },
                   label: {
              Text("[Debug] - 合并数据")
                .frame(maxWidth: .infinity, alignment: .leading)
            })
          }
        }
        .listRowBackground(Color(.secondaryBraveGroupedBackground))
      }
    }
    // 导航栏标题
    .navigationTitle(Strings.PrivacyHub.privacyReportsTitle)
    // 列表样式
    .listStyle(.insetGrouped)
    // 列表背景颜色
    .listBackgroundColor(Color(UIColor.braveGroupedBackground))
  }
}

#if DEBUG
struct PrivacyReportSettingsView_Previews: PreviewProvider {
  static var previews: some View {
    PrivacyReportSettingsView()
  }
}
#endif
