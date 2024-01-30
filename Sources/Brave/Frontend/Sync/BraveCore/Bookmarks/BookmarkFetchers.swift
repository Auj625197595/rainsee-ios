// 版权 2020 年 Brave 作者。保留所有权利。
// 本源代码形式受 Mozilla Public License，版本 2.0 的条款约束。
// 如果未随此文件分发 MPL 的副本，则可以在 http://mozilla.org/MPL/2.0/ 获取。

import Foundation
import BraveCore
import CoreData

// 定义用于获取书签的协议
protocol BookmarksV2FetchResultsDelegate: AnyObject {
  // 通知代理内容将要发生更改
  func controllerWillChangeContent(_ controller: BookmarksV2FetchResultsController)

  // 通知代理内容已经发生更改
  func controllerDidChangeContent(_ controller: BookmarksV2FetchResultsController)

  // 通知代理特定对象的更改
  func controller(_ controller: BookmarksV2FetchResultsController, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?)

  // 通知代理内容已重新加载
  func controllerDidReloadContents(_ controller: BookmarksV2FetchResultsController)
}

// 定义用于获取书签的协议
protocol BookmarksV2FetchResultsController {
  /* weak */ var delegate: BookmarksV2FetchResultsDelegate? { get set }

  // 获取已检索到的书签对象数组
  var fetchedObjects: [Bookmarkv2]? { get }

  // 获取已检索到的书签对象数量
  var fetchedObjectsCount: Int { get }

  // 执行书签检索
  func performFetch() throws

  // 获取指定位置的书签对象
  func object(at indexPath: IndexPath) -> Bookmarkv2?
}

// 实现获取书签的类
class Bookmarkv2Fetcher: NSObject, BookmarksV2FetchResultsController {
  weak var delegate: BookmarksV2FetchResultsDelegate?
  private var bookmarkModelListener: BookmarkModelListener?
  private weak var bookmarksAPI: BraveBookmarksAPI?

  private let parentNode: BookmarkNode?
  private var children = [Bookmarkv2]()

  // 初始化方法，接受父节点和 BraveBookmarksAPI 对象
  init(_ parentNode: BookmarkNode?, api: BraveBookmarksAPI) {
    self.parentNode = parentNode
    self.bookmarksAPI = api
    super.init()

    // 添加书签模型监听器，以便在书签发生更改时刷新内容
    self.bookmarkModelListener = api.add(
      BookmarkModelStateObserver { [weak self] _ in
        guard let self = self else { return }
        // 异步刷新内容，确保在主线程上执行
        DispatchQueue.main.async {
          self.delegate?.controllerDidReloadContents(self)
        }
      })
  }

  // 获取已检索到的书签对象数组
  var fetchedObjects: [Bookmarkv2]? {
    return children
  }

  // 获取已检索到的书签对象数量
  var fetchedObjectsCount: Int {
    return children.count
  }

  // 执行书签检索
  func performFetch() throws {
    // 清空子节点数组
    children.removeAll()

    if let parentNode = self.parentNode {
      // 如果存在父节点，则将其子节点添加到数组中
      children.append(contentsOf: parentNode.children.map({ Bookmarkv2($0) }))
    } else {
      // 否则，检查并添加移动节点、桌面节点和其他节点的子节点
      if let node = bookmarksAPI?.mobileNode {
        children.append(Bookmarkv2(node))
      }

      if let node = bookmarksAPI?.desktopNode, node.childCount > 0 {
        children.append(Bookmarkv2(node))
      }

      if let node = bookmarksAPI?.otherNode, node.childCount > 0 {
        children.append(Bookmarkv2(node))
      }

      // 如果没有子节点，则抛出错误
      if children.isEmpty {
        throw NSError(
          domain: "brave.core.migrator", code: -1,
          userInfo: [
            NSLocalizedFailureReasonErrorKey: "Invalid Bookmark Nodes"
          ])
      }
    }
  }

  // 获取指定位置的书签对象
  func object(at indexPath: IndexPath) -> Bookmarkv2? {
    return children[safe: indexPath.row]
  }
}

// 实现获取独占书签的类
class Bookmarkv2ExclusiveFetcher: NSObject, BookmarksV2FetchResultsController {
  weak var delegate: BookmarksV2FetchResultsDelegate?
  private var bookmarkModelListener: BookmarkModelListener?

  private var excludedFolder: BookmarkNode?
  private var children = [Bookmarkv2]()
  private weak var bookmarksAPI: BraveBookmarksAPI?

  // 初始化方法，接受排除的文件夹和 BraveBookmarksAPI 对象
  init(_ excludedFolder: BookmarkNode?, api: BraveBookmarksAPI) {
    self.excludedFolder = excludedFolder
    self.bookmarksAPI = api
    super.init()

    // 添加书签模型监听器，以便在书签发生更改时刷新内容
    self.bookmarkModelListener = api.add(
      BookmarkModelStateObserver { [weak self] _ in
        guard let self = self else { return }
        // 异步刷新内容，确保在主线程上执行
        DispatchQueue.main.async {
          self.delegate?.controllerDidReloadContents(self)
        }
      })
  }

  // 获取已检索到的书签对象数组
  var fetchedObjects: [Bookmarkv2]? {
    return children
  }

  // 获取已检索到的书签对象数量
  var fetchedObjectsCount: Int {
    return children.count
  }

  // 执行书签检索
  func performFetch() throws {
    // 清空子节点数组
    children = []

    if let node = bookmarksAPI?.mobileNode {
      // 添加移动节点的嵌套文件夹，排除指定的文件夹
      children.append(contentsOf: getNestedFolders(node, guid: excludedFolder?.guid))
    }

    if let node = bookmarksAPI?.desktopNode, node.childCount > 0 {
      // 添加桌面节点的嵌套文件夹，排除指定的文件夹
      children.append(contentsOf: getNestedFolders(node, guid: excludedFolder?.guid))
    }

    if let node = bookmarksAPI?.otherNode, node.childCount > 0 {
      // 添加其他节点的嵌套文件夹，排除指定的文件夹
      children.append(contentsOf: getNestedFolders(node, guid: excludedFolder?.guid))
    }

    // 如果没有子节点，则抛出错误
    if children.isEmpty {
      throw NSError(
        domain: "brave.core.migrator", code: -1,
        userInfo: [
          NSLocalizedFailureReasonErrorKey: "Invalid Bookmark Nodes"
        ])
    }
  }

  // 获取指定位置的书签对象
  func object(at indexPath: IndexPath) -> Bookmarkv2? {
    return children[safe: indexPath.row]
  }

  // 获取嵌套文件夹的方法
  private func getNestedFolders(_ node: BookmarkNode, guid: String?) -> [Bookmarkv2] {
    if let guid = guid {
      // 返回排除指定文件夹后的嵌套子文件夹
      return node.nestedChildFolders.filter({ $0.bookmarkNode.guid != guid }).map({ BraveBookmarkFolder($0) })
    }
    // 返回所有嵌套子文件夹
    return node.nestedChildFolders.map({ BraveBookmarkFolder($0) })
  }
}
