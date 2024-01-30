/* 此源代码表单受 Mozilla Public License, v. 2.0 的条款约束。
   如果未随此文件分发MPL副本，则可以在 http://mozilla.org/MPL/2.0/ 获取一个。 */

import UIKit
import CoreData
import Foundation
import Shared
import Storage
import os.log

// 定义一个协议，表示可以呈现为网站的对象
public protocol WebsitePresentable {
  var title: String? { get }
  var url: String? { get }
}

/// 注意：由于同步版本1的遗留原因，此类在我们的核心数据模型中被命名为`Bookmark`。
public final class Favorite: NSManagedObject, WebsitePresentable, CRUD {
  @NSManaged public var title: String?
  @NSManaged public var customTitle: String?
  @NSManaged public var url: String?
    
  @NSManaged public var lastVisited: Date?
  @NSManaged public var created: Date?
  @NSManaged public var order: Int16

  @NSManaged public var domain: Domain?

  // MARK: Legacy
  /// 在同步版本2之前，此对象可以是书签或收藏夹，此标志用于存储此信息。
  @NSManaged public var isFavorite: Bool
  /// 遗留：此属性不再使用，仅用于迁移。
  @NSManaged public var isFolder: Bool
  /// 未使用
  @NSManaged public var tags: [String]?
  /// 未使用
  @NSManaged public var visits: Int32

  @available(*, deprecated, message: "这是同步版本1的属性，不再使用")
  @NSManaged public var syncDisplayUUID: String?
  @available(*, deprecated, message: "这是同步版本1的属性，不再使用")
  @NSManaged public var syncParentDisplayUUID: String?
  @available(*, deprecated, message: "这是同步版本1的属性，不再使用")
  @NSManaged public var syncOrder: String?

  private static let isFavoritePredicate = NSPredicate(format: "isFavorite == true")

  // MARK: - 公共接口

  // MARK: 创建

  public class func add(from list: [(url: URL, title: String)]) {
    DataController.perform { context in
      list.forEach {
        addInternal(url: $0.url, title: $0.title, isFavorite: true, context: .existing(context))
      }
    }
  }

  public class func add(url: URL, title: String?) {
    addInternal(url: url, title: title, isFavorite: true)
  }

  // MARK: 读取

  public var displayTitle: String? {
    if let custom = customTitle, !custom.isEmpty {
      return customTitle
    }

    if let t = title, !t.isEmpty {
      return title
    }

    // 为了在前端上减少检查，希望返回nil
    return nil
  }

    // 获取用于操作收藏数据的 NSFetchedResultsController
    public static func frc() -> NSFetchedResultsController<Favorite> {
        // 获取视图上下文
        let context = DataController.viewContext
        
        // 创建收藏对象的 NSFetchRequest
        let fetchRequest = NSFetchRequest<Favorite>()
        
        // 设置 NSFetchRequest 的实体
        fetchRequest.entity = Favorite.entity(context: context)
        
        // 设置批量获取数据的大小
        fetchRequest.fetchBatchSize = 20
        
        // 设置排序规则，按照 "order" 升序和 "created" 降序排列
        let orderSort = NSSortDescriptor(key: "order", ascending: true)
        let createdSort = NSSortDescriptor(key: "created", ascending: false)
        fetchRequest.sortDescriptors = [orderSort, createdSort]
        
        // 设置筛选条件，仅获取收藏的数据
        fetchRequest.predicate = isFavoritePredicate
        
        // 创建并返回 NSFetchedResultsController，用于管理数据的获取和展示
        return NSFetchedResultsController(
            fetchRequest: fetchRequest, managedObjectContext: context,
            sectionNameKeyPath: nil, cacheName: nil)
    }


  public class func contains(url: URL) -> Bool {
    let predicate = NSPredicate(format: "url == %@ AND isFavorite == true", url.absoluteString)

    return (count(predicate: predicate) ?? 0) > 0
  }

  public class var hasFavorites: Bool {
    guard let favoritesCount = count(predicate: isFavoritePredicate) else { return false }
    return favoritesCount > 0
  }

  public class var allFavorites: [Favorite] {
    return all(where: isFavoritePredicate) ?? []
  }

  public class func get(with objectID: NSManagedObjectID) -> Favorite? {
    DataController.viewContext.object(with: objectID) as? Favorite
  }

  // MARK: 更新

  public func update(customTitle: String?, url: String?) {
    if !hasTitle(customTitle) { return }
    updateInternal(customTitle: customTitle, url: url)
  }

  // 标题不能为空。
  private func hasTitle(_ title: String?) -> Bool {
    return title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
  }

  /// 警告：此方法会删除所有当前的收藏夹，并用数组中的新收藏夹替换它们。
  public class func forceOverwriteFavorites(with favorites: [(url: URL, title: String)]) {
    DataController.perform { context in
      Favorite.deleteAll(predicate: isFavoritePredicate, context: .existing(context))

      favorites.forEach {
        addInternal(
          url: $0.url, title: $0.title, isFavorite: true,
          context: .existing(context))
      }
    }
  }

  /// 传入`isInteractiveDragReorder`将强制在主视图上进行写入。
  /// 默认为`false`
  public class func reorder(
    sourceIndexPath: IndexPath,
    destinationIndexPath: IndexPath,
    isInteractiveDragReorder: Bool = false
  ) {
    if destinationIndexPath.row == sourceIndexPath.row {
      Logger.module.error("源和目标书签相同!")
      return
    }

    // 如果进行交互式拖放重排序，则要确保在主队列上进行重新排序，
    // 以便立即更新底层数据集和FRC，以防动画在放下时出现故障。
    //
    // 在后台线程上进行将导致收藏夹叠加显示旧项，并需要进行完整的表刷新。
    let context: WriteContext = isInteractiveDragReorder ? .existing(DataController.viewContext) : .new(inMemory: false)

    DataController.perform(context: context) { context in
      let destinationIndex = destinationIndexPath.row
      let source = sourceIndexPath.row

      var allFavorites = Favorite.getAllFavorites(context: context).sorted { $0.order < $1.order }

      if let sourceIndex = allFavorites.firstIndex(where: { $0.order == source }) {
        let removedItem = allFavorites.remove(at: sourceIndex)
        allFavorites.insert(removedItem, at: destinationIndex)
      }

      // 更新所有已更改的收藏夹的顺序。
      for (index, element) in allFavorites.enumerated() where index != element.order {
        element.order = Int16(index)
      }

      if isInteractiveDragReorder && context.hasChanges {
        do {
          assert(Thread.isMainThread)
          try context.save()
        } catch {
          Logger.module.error("performTask保存错误：\(error.localizedDescription)")
        }
      }
    }
  }

  // MARK: 删除

  public func delete(context: WriteContext? = nil) {
    deleteInternal(context: context ?? .new(inMemory: false))
  }
}

// MARK: - 内部实现
extension Favorite {
  /// 由于遗留原因，收藏夹被命名为`Bookmark`。
  /// 在同步版本2之前，我们使用此类同时处理书签和收藏夹。
  static func entity(context: NSManagedObjectContext) -> NSEntityDescription {
    return NSEntityDescription.entity(forEntityName: "Bookmark", in: context)!
  }

  // MARK: 创建

  /// - 参数 completion: 返回与此对象关联的对象ID。
  /// 重要提示：此ID在对象保存到持久存储后可能会更改。最好在一个上下文中使用它。
  class func addInternal(
    url: URL?,
    title: String?,
    customTitle: String? = nil,
    isFavorite: Bool,
    save: Bool = true,
    context: WriteContext = .new(inMemory: false)
  ) {

    DataController.perform(
      context: context, save: save,
      task: { context in
        let bk = Favorite(entity: entity(context: context), insertInto: context)

        let location = url?.absoluteString

        bk.url = location
        bk.title = title
        bk.customTitle = customTitle
        bk.isFavorite = isFavorite
        bk.created = Date()
        bk.lastVisited = bk.created

        if let location = location, let url = URL(string: location) {
          bk.domain = Domain.getOrCreateInternal(
            url, context: context,
            saveStrategy: .delayedPersistentStore)
        }

        let favorites = getAllFavorites(context: context)

        // 第一个收藏夹是零，然后我们递增所有其他收藏夹。
        if favorites.count > 1, let lastOrder = favorites.map(\.order).max() {
          bk.order = lastOrder + 1
        }
      })
  }

  // MARK: 更新

  private func updateInternal(
    customTitle: String?, url: String?, save: Bool = true,
    context: WriteContext = .new(inMemory: false)
  ) {

    DataController.perform(context: context) { context in
      guard let bookmarkToUpdate = context.object(with: self.objectID) as? Favorite else { return }

      // 看看是否有任何更改
      if bookmarkToUpdate.customTitle == customTitle && bookmarkToUpdate.url == url {
        return
      }

      bookmarkToUpdate.customTitle = customTitle
      bookmarkToUpdate.title = customTitle ?? bookmarkToUpdate.title

      if let u = url, !u.isEmpty {
        bookmarkToUpdate.url = url
        if let theURL = URL(string: u) {
          bookmarkToUpdate.domain =
            Domain.getOrCreateInternal(
              theURL, context: context,
              saveStrategy: .delayedPersistentStore)
        } else {
          bookmarkToUpdate.domain = nil
        }
      }
    }
  }

  // MARK: 读取

  private static func getAllFavorites(context: NSManagedObjectContext? = nil) -> [Favorite] {
    let predicate = NSPredicate(format: "isFavorite == YES")

    return all(where: predicate, context: context ?? DataController.viewContext) ?? []
  }

  // MARK: 删除

  private func deleteInternal(context: WriteContext = .new(inMemory: false)) {
    func deleteFromStore(context: WriteContext) {
      DataController.perform(context: context) { context in
        let objectOnContext = context.object(with: self.objectID)
        context.delete(objectOnContext)
      }
    }

    if isFavorite { deleteFromStore(context: context) }
    deleteFromStore(context: context)
  }
}

// MARK: - Comparable
extension Favorite: Comparable {
  public static func < (lhs: Favorite, rhs: Favorite) -> Bool {
    return lhs.order < rhs.order
  }
}

extension Favorite {
    public func toRainseeDict() -> [String: String] {

       return [
        "url": url ?? "",
         "title": title ?? ""
        ]
   }
}
