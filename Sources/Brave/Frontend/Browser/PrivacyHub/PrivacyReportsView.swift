/* 此源代码受 Mozilla Public License, v. 2.0 的条款约束。
 * 如果未随此文件分发 MPL 的副本，则您可以在 http://mozilla.org/MPL/2.0/ 获取一份。 */

import SwiftUI
import BraveUI
import Shared
import Preferences
import Data

struct PrivacyReportsView: View {
  // 获取当前视图的呈现模式
  @Environment(\.presentationMode) @Binding private var presentationMode
  
  // 上次 VPN 警报数组
  let lastVPNAlerts: [BraveVPNAlert]?
  
  // 是否处于隐私浏览模式
  private(set) var isPrivateBrowsing: Bool
  var onDismiss: (() -> Void)?
  var openPrivacyReportsUrl: (() -> Void)?
  
  // 用于观察是否应该显示通知权限 Callout
  @ObservedObject private var showNotificationPermissionCallout = Preferences.PrivacyReports.shouldShowNotificationPermissionCallout
  
  // 用于存储正确的身份验证状态
  @State private var correctAuthStatus: Bool = false
  
  // 用于显示清除数据提示的状态
  @State private var showClearDataPrompt: Bool = false
  
  /// 检测通知权限状态
  private func determineNotificationPermissionStatus() {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        correctAuthStatus =
        settings.authorizationStatus == .notDetermined || settings.authorizationStatus == .provisional
      }
    }
  }
  
  // 关闭视图
  private func dismissView() {
    presentationMode.dismiss()
    onDismiss?()
  }
  
  // 清除所有数据按钮
  private var clearAllDataButton: some View {
    Button(action: {
      showClearDataPrompt = true
    }, label: {
      Image(uiImage: .init(braveSystemNamed: "leo.trash")!.template)
    })
      .accessibility(label: Text(Strings.PrivacyHub.clearAllDataAccessibility))
      .foregroundColor(Color(.braveBlurpleTint))
      .actionSheet(isPresented: $showClearDataPrompt) {
        // 目前 .actionSheet 不允许您将 sheet 的标题留空。
        // 一旦 iOS 15 是最低支持版本，可以将其转换为 .confirmationPrompt 或带有破坏性按钮的菜单
        .init(title: Text(Strings.PrivacyHub.clearAllDataPrompt),
              buttons: [
                .destructive(Text(Strings.yes), action: {
                  PrivacyReportsManager.clearAllData()
                  // 解散以避免观察数据库更改以更新视图。
                  dismissView()
                }),
                .cancel()
              ])
      }
  }
  
  // 完成按钮
  private var doneButton: some View {
    Button(Strings.done, action: dismissView)
      .foregroundColor(Color(.braveBlurpleTint))
  }
  
  var body: some View {
    NavigationView {
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 16) {
          
          // 如果应该显示通知权限 Callout 且身份验证状态正确，则显示通知 Callout
//          if showNotificationPermissionCallout.value && correctAuthStatus {
//            NotificationCalloutView()
//          }
//                    
          // 显示上周隐私中心部分
          PrivacyHubLastWeekSection()
          
          Divider()
          
//          // 如果应该捕获 VPN 警报且存在最后的 VPN 警报，则显示 VPN 警报部分
//          if Preferences.PrivacyReports.captureVPNAlerts.value, let lastVPNAlerts = lastVPNAlerts, !lastVPNAlerts.isEmpty {
//            PrivacyHubVPNAlertsSection(lastVPNAlerts: lastVPNAlerts, onDismiss: dismissView)
//            
//            Divider()
//          }
          
          // 显示所有时间的隐私中心部分
          PrivacyHubAllTimeSection(isPrivateBrowsing: isPrivateBrowsing, onDismiss: dismissView)
          
          VStack {
            Text(Strings.PrivacyHub.privacyReportsDisclaimer)
              .font(.caption)
              .multilineTextAlignment(.center)
            
            // 打开隐私报告网址的按钮
            Button(action: {
              openPrivacyReportsUrl?()
              dismissView()
            }, label: {
              Text(Strings.learnMore)
                .underline()
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .center)
            })
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle(Strings.PrivacyHub.privacyReportsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          // 工具栏项 - 完成按钮
          ToolbarItem(placement: .confirmationAction) {
            doneButton
          }
          
          // 工具栏项 - 清除所有数据按钮
          ToolbarItem(placement: .cancellationAction) {
            clearAllDataButton
          }
        }
      }
      .background(Color(.secondaryBraveBackground).ignoresSafeArea())
    }
    .navigationViewStyle(.stack)
    .environment(\.managedObjectContext, DataController.swiftUIContext)
    .onAppear(perform: determineNotificationPermissionStatus)
  }
}

// 调试模式下的预览
#if DEBUG
struct PrivacyReports_Previews: PreviewProvider {
  static var previews: some View {
    
    Group {
      PrivacyReportsView(lastVPNAlerts: nil, isPrivateBrowsing: false)
      
      PrivacyReportsView(lastVPNAlerts: nil, isPrivateBrowsing: false)
        .preferredColorScheme(.dark)
    }
  }
}
#endif
