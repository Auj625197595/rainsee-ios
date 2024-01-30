// 版权 2021 年 Brave 作者。保留所有权利。
// 此源代码表单受 Mozilla Public License, v. 2.0 的条款约束。
// 如果未随此文件分发 MPL 的副本，则可以在 http://mozilla.org/MPL/2.0/ 获取一个。

import Foundation
import CoreData
import Shared
import os.log

/// `DataSaved` 类是一个遵循 CRUD 协议的 Core Data 实体类。
public final class DataSaved: NSManagedObject, CRUD {
  @NSManaged public var savedUrl: String
  @NSManaged public var amount: String

  /// 通过给定的 `savedUrl` 获取 DataSaved 对象。
  /// - Parameter savedUrl: 要检索的 savedUrl。
  /// - Returns: 匹配的 DataSaved 对象，如果没有找到则返回 nil。
  public class func get(with savedUrl: String) -> DataSaved? {
    return getInternal(with: savedUrl)
  }

  /// 获取所有 DataSaved 对象的数组。
  /// - Returns: 包含所有 DataSaved 对象的数组。
  public class func all() -> [DataSaved] {
    all() ?? []
  }

  /// 根据给定的 `savedUrl` 删除相应的 DataSaved 对象。
  /// - Parameter savedUrl: 要删除的 savedUrl。
  public class func delete(with savedUrl: String) {
    DataController.perform { context in
      if let item = getInternal(with: savedUrl, context: context) {
        item.delete(context: .existing(context))
      }
    }
  }

  /// 插入一个新的 DataSaved 对象到 Core Data 中。
  /// - Parameters:
  ///   - savedUrl: 保存的 URL。
  ///   - amount: 相关的数量。
  public class func insert(savedUrl: String, amount: String) {
    DataController.perform { context in
      guard let entity = entity(in: context) else {
        Logger.module.error("从托管对象模型中获取实体 'DataSaved' 时出错")
        return
      }

      let newDataSaved = DataSaved(entity: entity, insertInto: context)
      newDataSaved.savedUrl = savedUrl
      newDataSaved.amount = amount
    }
  }

  /// 从给定的上下文中获取 DataSaved 实体。
  /// - Parameter context: Core Data 上下文。
  /// - Returns: DataSaved 实体的描述。
  private class func entity(in context: NSManagedObjectContext) -> NSEntityDescription? {
    NSEntityDescription.entity(forEntityName: "DataSaved", in: context)
  }

  /// 从 Core Data 中获取具有给定 savedUrl 的 DataSaved 对象。
  /// - Parameters:
  ///   - savedUrl: 要检索的 savedUrl。
  ///   - context: Core Data 上下文，默认为 DataController 的视图上下文。
  /// - Returns: 匹配的 DataSaved 对象，如果没有找到则返回 nil。
  private class func getInternal(
    with savedUrl: String,
    context: NSManagedObjectContext = DataController.viewContext
  ) -> DataSaved? {
    let predicate = NSPredicate(format: "\(#keyPath(DataSaved.savedUrl)) == %@", savedUrl)
    return first(where: predicate, context: context)
  }
}
