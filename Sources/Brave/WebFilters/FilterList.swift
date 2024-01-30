// 版权 2022 年 Brave 作者。保留所有权利。
// 此源代码表单受 Mozilla Public License, v. 2.0 条款约束。
// 如果未与此文件一起分发 MPL 的副本，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import BraveCore

struct FilterList: Identifiable {
  /// "Fanboy's Mobile Notifications List" 的组件 ID，这是一个特殊的过滤列表，默认启用
  public static let mobileAnnoyancesComponentID = "bfpgedeaaibpoidldhjcknekahbikncb"
  /// cookie 同意通知过滤列表的组件 ID，这是一个具有更可访问 UI 控制的特殊过滤列表
  public static let cookieConsentNoticesComponentID = "cdbbhgbmjhfnhnmgeddbliobbofkgdhe"
  /// 一组安全的过滤列表，如果用户有匹配的本地化，则可以自动启用
  /// - 注意: 这些是良好维护的区域过滤列表。目前我们硬编码这些值，但将来如果我们的组件更新器告诉我们哪些是安全的将更好。
  public static let maintainedRegionalComponentIDs = [
    "llgjaaddopeckcifdceaaadmemagkepi" // 日本过滤列表
  ]
  /// 禁用的过滤列表的列表。这些列表被禁用，因为它们与 iOS 不兼容（目前）
  public static let disabledComponentIDs = [
    // 反色情列表有 500251 条规则，严格来说是全部由内容阻止驱动的内容
    // 规则存储的限制是 150000 条规则。在当前时刻，我们无法处理这种情况
    "lbnibkdpkdjnookgfeogjdanfenekmpe"
  ]
  
  /// 默认情况下应该打开的所有组件 ID 的集合。
  public static var defaultOnComponentIds: Set<String> {
    return [mobileAnnoyancesComponentID]
  }
  
  /// 这是一些具有特殊切换的过滤列表的组件到 UUID 的列表
  /// (在下载过滤列表之前可用的切换)
  /// 为了在下载过滤列表之前保存这些值，我们还需要有 UUID
  public static var componentToUUID: [String: String] {
    return [
      mobileAnnoyancesComponentID: "2F3DCE16-A19A-493C-A88F-2E110FBD37D6",
      cookieConsentNoticesComponentID: "AC023D22-AE88-4060-A978-4FEEEC4221693"
    ]
  }
  
  var id: String { return entry.uuid }
  let order: Int
  let entry: AdblockFilterListCatalogEntry
  var isEnabled: Bool = false
  
  /// 告诉我们这个过滤列表是否是区域性的（即是否包含语言限制）
  var isRegional: Bool {
    return !entry.languages.isEmpty
  }
  
  /// 告诉我们这个过滤列表是否总是具有攻击性。
  /// 具有攻击性的过滤列表是那些非区域性的列表。
  var isAlwaysAggressive: Bool { !isRegional }
  
  init(from entry: AdblockFilterListCatalogEntry, order: Int, isEnabled: Bool) {
    self.entry = entry
    self.order = order
    self.isEnabled = isEnabled
  }
}
