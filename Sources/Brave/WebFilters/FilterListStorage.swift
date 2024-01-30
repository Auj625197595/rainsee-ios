// 版权 2023 年 Brave 作者保留所有权利。
// 此源代码表单受 Mozilla 公共许可证 2.0 版的条款约束。
// 如果未随此文件分发 MPL 的副本，您可以在 http://mozilla.org/MPL/2.0/ 处获取一份。

import Foundation
import Data
import BraveCore
import Preferences
import Onboarding
import Combine

@MainActor class FilterListStorage: ObservableObject {
  static let shared = FilterListStorage(persistChanges: true)
  
  /// 存储具有 componentId 作为键和版本作为值的过滤器列表的加载版本的列表
  var loadedRuleListVersions = Preferences.Option<[String: String]>(
    key: "filter_list_resource_downloader.loaded-adblock-versions", default: [:]
  )
  
  /// 这些设置是存储在内存中还是持久化的标志
  let persistChanges: Bool
  
  /// 过滤列表订阅
  private var filterListSubscription: AnyCancellable?
  /// 应加载过滤列表之前应设置的默认值列表
  /// 如果过滤列表尚未加载但用户已更改设置，则会使用此列表
  private var pendingDefaults: [String: Bool] = [:]
  /// 过滤列表订阅
  private var subscriptions: [AnyCancellable] = []
  
  /// 包含过滤列表的发布的列表，以便我们可以包含
  @Published var filterLists: [FilterList] = []
  
  /// 这是所有可用设置的列表。
  ///
  /// - 警告: 在加载核心数据之前不要调用此函数
  private(set) var allFilterListSettings: [FilterListSetting]
  
  init(persistChanges: Bool) {
    self.persistChanges = persistChanges
    allFilterListSettings = []
    recordP3ACookieListEnabled()
  }
  
  /// 加载过滤列表设置
  func loadFilterListSettings() {
    allFilterListSettings = FilterListSetting.loadAllSettings(fromMemory: !persistChanges)
  }
  
  /// 从广告拦截服务加载过滤列表并订阅任何过滤列表更改
  /// - 警告: 在调用此函数之前，您应始终调用 `loadFilterListSettings`
  func loadFilterLists(from regionalFilterLists: [AdblockFilterListCatalogEntry]) {
    let filterLists = regionalFilterLists.enumerated().compactMap { index, adBlockFilterList -> FilterList? in
      // 如果当前与 iOS 不兼容，则禁用某些过滤列表
      guard !FilterList.disabledComponentIDs.contains(adBlockFilterList.componentId) else { return nil }
      let setting = allFilterListSettings.first(where: { $0.componentId == adBlockFilterList.componentId })
      
      return FilterList(
        from: adBlockFilterList,
        order: index,
        isEnabled: pendingDefaults[adBlockFilterList.componentId] ?? setting?.isEnabled ?? adBlockFilterList.defaultToggle
      )
    }
    
    // 删除已删除的设置
    for setting in allFilterListSettings where !regionalFilterLists.contains(where: { $0.componentId == setting.componentId }) {
      allFilterListSettings.removeAll(where: { $0.componentId == setting.componentId })
      setting.delete(inMemory: !persistChanges)
    }
    
    // 创建缺失的过滤列表
    for filterList in filterLists {
      upsert(filterList: filterList)
    }
    
    pendingDefaults.removeAll()
    FilterListSetting.save(inMemory: !persistChanges)
    self.filterLists = filterLists
    
    // 现在我们的过滤列表已加载，让我们订阅对它们的任何更改
    // 这样我们确保我们的设置始终被存储。
    subscribeToFilterListChanges()
  }
  
  /// 确保存储过滤列表的设置
  /// - Parameters:
  ///   - componentId: 要更新的过滤列表的组件 id
  ///   - isEnabled: 一个布尔值，指示过滤列表是否启用
  public func ensureFilterList(for componentId: String, isEnabled: Bool) {
    defer { self.recordP3ACookieListEnabled() }
    
    // 启用设置
    if let index = filterLists.firstIndex(where: { $0.entry.componentId == componentId }) {
      // 仅在值更改时更新值
      guard filterLists[index].isEnabled != isEnabled else { return }
      filterLists[index].isEnabled = isEnabled
    } else if let index = allFilterListSettings.firstIndex(where: { $0.componentId == componentId }) {
      // 如果我们尚未加载过滤列表，至少尝试更新设置
      allFilterListSettings[index].isEnabled = isEnabled
      allFilterListSettings[index].componentId = componentId
      FilterListSetting.save(inMemory: !persistChanges)
    } else {
      // 如果我们甚至尚未加载设置，请设置待处理的默认值
      // 这将在加载过滤列表后强制创建设置
      pendingDefaults[componentId] = isEnabled
    }
  }
  
  /// - 警告: 在加载核心数据之前不要调用此函数
  public func isEnabled(for componentId: String) -> Bool {
    guard !FilterList.disabledComponentIDs.contains(componentId) else { return false }
    
    return filterLists.first(where: { $0.entry.componentId == componentId })?.isEnabled
      ?? allFilterListSettings.first(where: { $0.componentId == componentId })?.isEnabled
      ?? pendingDefaults[componentId]
      ?? false
  }
  
  /// 订阅对过滤列表的任何更改，以便我们的设置始终被存储
  private func subscribeToFilterListChanges() {
    $filterLists
      .receive(on: DispatchQueue.main)
      .sink { filterLists in
        for filterList in filterLists {
          self.upsert(filterList: filterList)
        }
      }
      .store(in: &subscriptions)
  }
  
  /// 更新（更新或插入）设置。
  private func upsert(filterList: FilterList) {
    upsertSetting(
      uuid: filterList.entry.uuid,
      isEnabled: filterList.isEnabled,
      isHidden: false,
      componentId: filterList.entry.componentId,
      allowCreation: true,
      order: filterList.order,
      isAlwaysAggressive: filterList.isAlwaysAggressive
    )
  }
  
  /// 设置过滤列表设置的启用状态和 componentId，如果设置存在。
  /// 否则，它将使用指定的属性创建新设置
  ///
  /// - 警告: 在加载核心数据之前不要调用此函数
  private func upsertSetting(
    uuid: String, isEnabled: Bool, isHidden: Bool, componentId: String,
    allowCreation: Bool, order: Int, isAlwaysAggressive: Bool
  ) {
    if allFilterListSettings.contains(where: { $0.uuid == uuid }) {
      updateSetting(
        uuid: uuid,
        componentId: componentId,
        isEnabled: isEnabled,
        isHidden: isHidden,
        order: order,
        isAlwaysAggressive: isAlwaysAggressive
      )
    } else if allowCreation {
      create(
        uuid: uuid,
        componentId: componentId,
        isEnabled: isEnabled,
        isHidden: isHidden,
        order: order,
        isAlwaysAggressive: isAlwaysAggressive
      )
    }
  }
  
  /// 设置过滤列表的文件夹 URL
  ///
  /// - 警告: 在加载核心数据之前不要调用此函数
  public func set(folderURL: URL, forUUID uuid: String) {
    guard let index = allFilterListSettings.firstIndex(where: { $0.uuid == uuid }) else {
      return
    }
    
    guard allFilterListSettings[index].folderURL != folderURL else { return }
    allFilterListSettings[index].folderURL = folderURL
    FilterListSetting.save(inMemory: !persistChanges)
  }
  
  /// 使用给定的 `componentId` 和 `isEnabled` 状态更新过滤列表设置
  /// 仅在这两个值之一更改时才会写入
  private func updateSetting(uuid: String, componentId: String, isEnabled: Bool, isHidden: Bool, order: Int, isAlwaysAggressive: Bool) {
    guard let index = allFilterListSettings.firstIndex(where: { $0.uuid == uuid }) else {
      return
    }
    
    // 确保我们在已同步的情况下停止，以避免事件循环
    // 和事物挂起太长时间。
    guard allFilterListSettings[index].isEnabled != isEnabled
            || allFilterListSettings[index].componentId != componentId
            || allFilterListSettings[index].order?.intValue != order
            || allFilterListSettings[index].isAlwaysAggressive != isAlwaysAggressive
            || allFilterListSettings[index].isHidden != isHidden
    else {
      return
    }
      
    allFilterListSettings[index].isEnabled = isEnabled
    allFilterListSettings[index].isAlwaysAggressive = isAlwaysAggressive
    allFilterListSettings[index].isHidden = isHidden
    allFilterListSettings[index].componentId = componentId
    allFilterListSettings[index].order = NSNumber(value: order)
    FilterListSetting.save(inMemory: !persistChanges)
  }
  
  /// 为给定的 UUID 和启用状态创建过滤列表设置
  private func create(uuid: String, componentId: String, isEnabled: Bool, isHidden: Bool, order: Int, isAlwaysAggressive: Bool) {
    let setting = FilterListSetting.create(
      uuid: uuid, componentId: componentId, isEnabled: isEnabled, isHidden: isHidden, order: order, inMemory: !persistChanges,
      isAlwaysAggressive: isAlwaysAggressive
    )
    allFilterListSettings.append(setting)
  }
  
  // MARK: - P3A
  
  private func recordP3ACookieListEnabled() {
    // Q69 您是否启用了 cookie 同意通知拦截？
//    Task { @MainActor in
//      UmaHistogramBoolean(
//        "Brave.Shields.CookieListEnabled",
//        isEnabled(for: FilterList.cookieConsentNoticesComponentID)
//      )
//    }
  }
}

// MARK: - FilterListLanguageProvider - 用于在多个结构/类之间共享 `defaultToggle` 逻辑的方式

private extension AdblockFilterListCatalogEntry {
  @available(iOS 16, *)
  /// 该过滤列表关注的区域的语言代码集合。
  /// 空集表示此过滤列表不关注任何特定区域。
  var supportedLanguageCodes: Set<Locale.LanguageCode> {
    return Set(languages.map({ Locale.LanguageCode($0) }))
  }
  
  /// 如果用户没有手动切换，则此方法返回此过滤列表的默认值。
  /// - 警告: 请确保使用 `componentID` 来标识过滤列表，因为 `uuid` 将来会被弃用。
  var defaultToggle: Bool {
    let componentIDsToOverride = [
      FilterList.mobileAnnoyancesComponentID,
      FilterList.cookieConsentNoticesComponentID
    ]
    
    if componentIDsToOverride.contains(componentId) {
      return true
    }
    
    // 由于兼容性原因，我们仅启用某些区域性过滤列表
    // 这些是已知良好维护的过滤列表。
    guard FilterList.maintainedRegionalComponentIDs.contains(componentId) else {
      return false
    }
    
    if #available(iOS 16, *), let languageCode = Locale.current.language.languageCode {
      return supportedLanguageCodes.contains(languageCode)
    } else if let languageCode = Locale.current.languageCode {
      return languages.contains(languageCode)
    } else {
      return false
    }
  }
}
