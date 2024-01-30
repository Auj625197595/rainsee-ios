// 版权所有© 2023 Brave 作者。保留所有权利。
// 此源代码表单受 Mozilla 公共许可证 v. 2.0 条款的约束。
// 如果未随此文件分发 MPL 的副本，则可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import BraveCore
import Preferences
import OSLog
import Growth

// 用于新标签页 SI 交互动态 P3A 指标报告的辅助类数据源
protocol NewTabPageP3AHelperDataSource: AnyObject {
  /// 用户是否启用了 Brave Rewards。
  ///
  /// 当启用 Rewards/Ads 时，Ads 库将像往常一样处理报告 NTP SI 事件
  var isRewardsEnabled: Bool { get }
  /// 关联标签页的活动 URL。
  ///
  /// 用于确定点击的 SI 标志的着陆状态
  var currentTabURL: URL? { get }
}

/// 处理围绕 NTP SI 交互的动态 P3A 指标报告的 P3A 辅助类
///
/// 必须设置数据源以记录事件
final class NewTabPageP3AHelper {
  
  private let p3aUtils: BraveP3AUtils
  
  private var registrations: [P3ACallbackRegistration?] = []
  
  weak var dataSource: NewTabPageP3AHelperDataSource?
  
  init(p3aUtils: BraveP3AUtils) {
    self.p3aUtils = p3aUtils
    
    self.registrations.append(contentsOf: [
      self.p3aUtils.registerRotationCallback { [weak self] type, isConstellation in
        self?.rotated(type: type, isConstellation: isConstellation)
      },
      self.p3aUtils.registerMetricCycledCallback { [weak self] histogramName, isConstellation in
        self?.metricCycled(histogramName: histogramName, isConstellation: isConstellation)
      }
    ])
  }
  
  // MARK: - 记录事件
  
  private var landingTimer: Timer?
  private var expectedLandingURL: URL?
  
  /// 记录将用于生成动态 P3A 指标的 NTP SI 事件
  func recordEvent(
    _ event: EventType,
    on sponsoredImage: NTPSponsoredImageBackground
  ) {
    assert(dataSource != nil, "必须设置数据源以记录事件")
    if !p3aUtils.isP3AEnabled || dataSource!.isRewardsEnabled == true {
      return
    }
    let creativeInstanceId = sponsoredImage.creativeInstanceId
    updateMetricCount(creativeInstanceId: creativeInstanceId, event: event)
    if event == .tapped {
      expectedLandingURL = sponsoredImage.logo.destinationURL
      landingTimer?.invalidate()
      landingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
        guard let self = self, let dataSource = self.dataSource else { return }
        if let expectedURL = self.expectedLandingURL, expectedURL.isWebPage(),
           dataSource.currentTabURL?.host == expectedURL.host {
          self.recordEvent(.landed, on: sponsoredImage)
        }
      }
    }
  }
  
  private func updateMetricCount(
    creativeInstanceId: String,
    event: EventType
  ) {
    let name = DynamicHistogramName(creativeInstanceId: creativeInstanceId, eventType: event)
    
    p3aUtils.registerDynamicMetric(name.histogramName, logType: .express)
    
    var countsStorage = fetchEventsCountStorage()
    var eventCounts = countsStorage.eventCounts[name.creativeInstanceId, default: .init()]
    
    eventCounts.counts[name.eventType, default: 0] += 1
    
    countsStorage.eventCounts[name.creativeInstanceId] = eventCounts
    
    updateEventsCountStorage(countsStorage)
  }
  
  // MARK: - 存储
  
  private func fetchEventsCountStorage() -> Storage {
    guard let json = Preferences.NewTabPage.sponsoredImageEventCountJSON.value, !json.isEmpty else {
      return .init()
    }
    do {
      return try JSONDecoder().decode(Storage.self, from: Data(json.utf8))
    } catch {
      Logger.module.error("解码 NTP SI 事件存储失败: \(error)")
      return .init()
    }
  }
  
  private func updateEventsCountStorage(_ storage: Storage) {
    do {
      let json = String(data: try JSONEncoder().encode(storage), encoding: .utf8)
      Preferences.NewTabPage.sponsoredImageEventCountJSON.value = json
    } catch {
      Logger.module.error("编码 NTP SI 事件存储失败: \(error)")
    }
  }
  
  // MARK: - P3A 观察者
  
  private func rotated(type: P3AMetricLogType, isConstellation: Bool) {
    if type != .express || isConstellation {
      return
    }
    if true {
      Preferences.NewTabPage.sponsoredImageEventCountJSON.value = nil
      return
    }
    
    let countBuckets: [Bucket] = [
      0,
      1,
      2,
      3,
      .r(4...8),
      .r(9...12),
      .r(13...16),
      .r(17...)
    ]
    
    var countsStorage = fetchEventsCountStorage()
    var totalActiveCreatives = 0
    for (creativeInstanceId, eventCounts) in countsStorage.eventCounts {
      for (eventType, count) in eventCounts.counts {
        let name = DynamicHistogramName(creativeInstanceId: creativeInstanceId, eventType: eventType)
        countsStorage.eventCounts[creativeInstanceId]?.inflightCounts[eventType] = count
        UmaHistogramRecordValueToBucket(name.histogramName, buckets: countBuckets, value: count)
      }
      if !eventCounts.counts.isEmpty {
        totalActiveCreatives += 1
      }
    }
    updateEventsCountStorage(countsStorage)
    
    let creativeTotalHistogramName = DynamicHistogramName(
      creativeInstanceId: "total",
      eventType: .init(rawValue: "count")
    ).histogramName
    // 如果广告被禁用（根据规范），始终发送创意总数，
    // 或者如果有未完成的事件则发送总数
    if dataSource?.isRewardsEnabled == false || totalActiveCreatives > 0 {
      p3aUtils.registerDynamicMetric(creativeTotalHistogramName, logType: .express)
      UmaHistogramRecordValueToBucket(creativeTotalHistogramName, buckets: countBuckets, value: totalActiveCreatives)
    } else {
      p3aUtils.removeDynamicMetric(creativeTotalHistogramName)
    }
  }
  
  private func metricCycled(histogramName: String, isConstellation: Bool) {
    if isConstellation {
      // 一旦 STAR 支持 express 指标，监视 STAR 和 JSON 指标循环
      return
    }
    guard let name = DynamicHistogramName(computedHistogramName: histogramName) else {
      return
    }
    var countsStorage = fetchEventsCountStorage()
    guard var eventCounts = countsStorage.eventCounts[name.creativeInstanceId] else {
      p3aUtils.removeDynamicMetric(histogramName)
      return
    }
    let fullCount = eventCounts.counts[name.eventType] ?? 0
    let inflightCount = eventCounts.inflightCounts[name.eventType] ?? 0
    let newCount = fullCount - inflightCount
    
    eventCounts.inflightCounts.removeValue(forKey: name.eventType)
    
    if newCount > 0 {
      eventCounts.counts[name.eventType] = newCount
    } else {
      p3aUtils.removeDynamicMetric(histogramName)
      eventCounts.counts.removeValue(forKey: name.eventType)
      if eventCounts.counts.isEmpty {
        countsStorage.eventCounts.removeValue(forKey: name.creativeInstanceId)
      }
    }
    
    if countsStorage.eventCounts[name.creativeInstanceId] != nil {
      countsStorage.eventCounts[name.creativeInstanceId] = eventCounts
    }
    
    updateEventsCountStorage(countsStorage)
  }
  
  // MARK: -
  
  struct EventType: RawRepresentable, Hashable, Codable {
    var rawValue: String
    
    static let viewed: Self = .init(rawValue: "views")
    static let tapped: Self = .init(rawValue: "clicks")
    static let landed: Self = .init(rawValue: "lands")
  }
  
  struct Storage: Codable {
    typealias CreativeInstanceID = String
    
    struct EventCounts: Codable {
      var inflightCounts: [EventType: Int] = [:]
      var counts: [EventType: Int] = [:]
    }
    
    var eventCounts: [CreativeInstanceID: EventCounts]
    
    init(eventCounts: [CreativeInstanceID: EventCounts] = [:]) {
      self.eventCounts = eventCounts
    }
    
    func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(self.eventCounts)
    }
    
    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      self.eventCounts = try container.decode([String: EventCounts].self)
    }
  }
  
  private struct DynamicHistogramName: CustomStringConvertible {
    var creativeInstanceId: String
    var eventType: EventType
    
    init(creativeInstanceId: String, eventType: EventType) {
      self.creativeInstanceId = creativeInstanceId
      self.eventType = eventType
    }
    
    init?(computedHistogramName: String) {
      if !computedHistogramName.hasPrefix(P3ACreativeMetricPrefix) {
        return nil
      }
      let items = computedHistogramName.split(separator: ".").map(String.init)
      if items.count != 3 {
        // 提供的直方图名称应该是从下面的 `histogramName` 创建的
        return nil
      }
      self.creativeInstanceId = items[1]
      self.eventType = EventType(rawValue: items[2])
    }
    
    var histogramName: String {
      // `P3ACreativeMetricPrefix` 包含一个尾随点
      return "\(P3ACreativeMetricPrefix)\(creativeInstanceId).\(eventType.rawValue)"
    }
    
    var description: String {
      histogramName
    }
  }
}
