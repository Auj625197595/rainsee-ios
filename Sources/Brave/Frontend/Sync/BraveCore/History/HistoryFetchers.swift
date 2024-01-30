// 版权声明
// 版权所有 2021 年 Brave 作者。保留所有权利。
// 本源代码表受 Mozilla Public License, v. 2.0 条款的约束。
// 如果没有随此文件分发 MPL 的副本，则可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import BraveCore
import CoreData
import OrderedCollections
import Shared

// MARK: - HistoryV2FetchResultsDelegate

// 历史版本 2 数据获取结果代理
protocol HistoryV2FetchResultsDelegate: AnyObject {

  // 控制器将要变更内容
  func controllerWillChangeContent(_ controller: HistoryV2FetchResultsController)

  // 控制器已经变更内容
  func controllerDidChangeContent(_ controller: HistoryV2FetchResultsController)

  // 控制器变更了对象
  func controller(
    _ controller: HistoryV2FetchResultsController, didChange anObject: Any,
    at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?)

  // 控制器变更了段信息
  func controller(
    _ controller: HistoryV2FetchResultsController, didChange sectionInfo: NSFetchedResultsSectionInfo,
    atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType)

  // 控制器重新加载内容
  func controllerDidReloadContents(_ controller: HistoryV2FetchResultsController)
}

// MARK: - HistoryV2FetchResultsController

// 历史版本 2 数据获取结果控制器
protocol HistoryV2FetchResultsController {

  // 代理
  var delegate: HistoryV2FetchResultsDelegate? { get set }

  // 获取的对象数组
  var fetchedObjects: [HistoryNode]? { get }

  // 获取的对象数量
  var fetchedObjectsCount: Int { get }

  // 段数量
  var sectionCount: Int { get }

  // 执行数据获取
  func performFetch(withQuery: String, _ completion: @escaping () -> Void)

  // 获取指定 IndexPath 处的对象
  func object(at indexPath: IndexPath) -> HistoryNode?

  // 获取指定段的对象数量
  func objectCount(for section: Int) -> Int

  // 获取指定段的标题
  func titleHeader(for section: Int) -> String

}

// MARK: - Historyv2Fetcher

// 历史版本 2 数据获取器
class Historyv2Fetcher: NSObject, HistoryV2FetchResultsController {

  // MARK: Section

  // 段枚举
  enum Section: Int, CaseIterable {
    /// 今天发生的历史
    case today
    /// 昨天发生的历史
    case yesterday
    /// 昨天到本周结束之间发生的历史
    case lastWeek
    /// 本周结束到本月结束之间发生的历史
    case thisMonth
    /// 本月结束后发生的历史
    case earlier

    /// 时间段的标题列表
    var title: String {
      switch self {
      case .today:
        return Strings.today
      case .yesterday:
        return Strings.yesterday
      case .lastWeek:
        return Strings.lastWeek
      case .thisMonth:
        return Strings.lastMonth
      case .earlier:
        return Strings.earlier
      }
    }
  }

  // MARK: Lifecycle

  init(historyAPI: BraveHistoryAPI) {
    self.historyAPI = historyAPI
    super.init()

    // 添加历史服务状态监听器
    self.historyServiceListener = historyAPI.add(
      HistoryServiceStateObserver { [weak self] _ in
        guard let self = self else { return }

        DispatchQueue.main.async {
          self.delegate?.controllerDidReloadContents(self)
        }
      })
  }

  // MARK: Internal

  // 委托对象
  weak var delegate: HistoryV2FetchResultsDelegate?

  // 获取的对象数组
  var fetchedObjects: [HistoryNode]? {
    historyList
  }

  // 获取的对象数量
  var fetchedObjectsCount: Int {
    historyList.count
  }

  // 段数量
  var sectionCount: Int {
    return sectionDetails.elements.filter { $0.value > 0 }.count
  }

  // 执行数据获取
  func performFetch(withQuery: String, _ completion: @escaping () -> Void) {
    clearHistoryData()

    // 使用历史 API 进行搜索
    historyAPI?.search(
      withQuery: withQuery, maxCount: 200,
      completion: { [weak self] historyNodeList in
        guard let self = self else { return }

        // 处理历史节点列表
        self.historyList = historyNodeList.map { [unowned self] historyItem in
          if let section = self.fetchHistoryTimePeriod(dateAdded: historyItem.dateAdded),
            let numOfItemInSection = self.sectionDetails[section] {
            self.sectionDetails.updateValue(numOfItemInSection + 1, forKey: section)
          }

          return historyItem
        }

        completion()
      })
  }

  // 获取指定 IndexPath 处的对象
  func object(at indexPath: IndexPath) -> HistoryNode? {
    let filteredDetails = sectionDetails.elements.filter { $0.value > 0 }
    var totalItemIndex = 0

    for sectionIndex in 0..<indexPath.section {
      totalItemIndex += filteredDetails[safe: sectionIndex]?.value ?? 0
    }

    return fetchedObjects?[safe: totalItemIndex + indexPath.row]
  }

  // 获取指定段的对象数量
  func objectCount(for section: Int) -> Int {
    let filteredDetails = sectionDetails.elements.filter { $0.value > 0 }
    return filteredDetails[safe: section]?.value ?? 0
  }

  // 获取指定段的标题
  func titleHeader(for section: Int) -> String {
    let filteredDetails = sectionDetails.elements.filter { $0.value > 0 }
    return filteredDetails[safe: section]?.key.title ?? ""
  }

  // MARK: Private

  // 历史服务监听器
  private var historyServiceListener: HistoryServiceListener?

  // 弱引用历史 API
  private weak var historyAPI: BraveHistoryAPI?

  // 历史节点数组
  private var historyList = [HistoryNode]()

  // 段详情
  private var sectionDetails: OrderedDictionary<Section, Int> = [
    .today: 0,
    .yesterday: 0,
    .lastWeek: 0,
    .thisMonth: 0,
    .earlier: 0,
  ]

  // 根据添加日期获取历史时间段
  private func fetchHistoryTimePeriod(dateAdded: Date?) -> Section? {
    let todayOffset = 0
    let yesterdayOffset = -1
    let thisWeekOffset = -7
    let thisMonthOffset = -31

    if dateAdded?.compare(getDate(todayOffset)) == ComparisonResult.orderedDescending {
      return .today
    } else if dateAdded?.compare(getDate(yesterdayOffset)) == ComparisonResult.orderedDescending {
      return .yesterday
    } else if dateAdded?.compare(getDate(thisWeekOffset)) == ComparisonResult.orderedDescending {
      return .lastWeek
    } else if dateAdded?.compare(getDate(thisMonthOffset)) == ComparisonResult.orderedDescending {
      return .thisMonth
    }

    return .earlier
  }

  // 获取指定偏移天数的日期
  private func getDate(_ dayOffset: Int) -> Date {
    let calendar = Calendar(identifier: Calendar.Identifier.gregorian)
    let nowComponents = calendar.dateComponents(
      [Calendar.Component.year, Calendar.Component.month, Calendar.Component.day], from: Date())

    guard let today = calendar.date(from: nowComponents) else {
      return Date()
    }

    return (calendar as NSCalendar).date(
      byAdding: NSCalendar.Unit.day, value: dayOffset, to: today, options: []) ?? Date()
  }

  // 清除历史数据
  private func clearHistoryData() {
    historyList.removeAll()

    for key in sectionDetails.keys {
      sectionDetails.updateValue(0, forKey: key)
    }
  }

}
