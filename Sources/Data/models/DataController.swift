/* 此源代码形式受 Mozilla Public License, v. 2.0 的条款约束。
   如果未随此文件分发 MPL 的副本，则可以在 http://mozilla.org/MPL/2.0/ 获取一个。 */

import UIKit
import CoreData
import Shared
import os.log
import Preferences

/// 用于 `DataController.perform()` 方法的辅助结构
/// 用于确定是使用新的上下文还是现有的上下文来执行数据库写操作。
public enum WriteContext {
  /// 请求 DataController 创建新的后台上下文以执行任务。
  case new(inMemory: Bool)
  /// 请求 DataController 使用现有的上下文。
  /// （为了防止每次调用创建多个上下文并混合线程）
  case existing(_ context: NSManagedObjectContext)
}

public class DataController {
  private static let databaseName = "Brave.sqlite"
  private static let modelName = "Model"

  /// 在加载持久存储时检查此代码。
  /// 对于除此代码之外的所有代码，由于数据库故障，我们使应用程序崩溃。
  private static let storeExistsErrorCode = 134081

  // MARK: - 初始化

  /// 数据库堆栈的托管对象模型。
  /// 只能创建一次，这是为了防止在使用内存存储进行测试时出现错误。
  /// 有关更多信息，请参见 https://stackoverflow.com/a/51857486。
  /// 注意：在 Swift 5.1 或更新版本中可能不需要这个。
  private static let model: NSManagedObjectModel = {
    guard let modelURL = Bundle.module.url(forResource: modelName, withExtension: "momd") else {
      fatalError("从 bundle 中加载模型时出错")
    }
    guard let mom = NSManagedObjectModel(contentsOf: modelURL) else {
      fatalError("从 \(modelURL) 初始化托管对象模型时出错")
    }

    return mom
  }()

  private let operationQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    return queue
  }()

  private var initializationCompleted = false

  /// 初始化逻辑仅在第一次运行时运行，然后在对此方法的后续调用中什么也不做。
  public func initializeOnce() {
    if initializationCompleted { return }

    configureContainer(container, store: supportStoreURL)
    initializationCompleted = true
  }

  // MARK: - 公共接口

  public static var shared: DataController = DataController()
  public static var sharedInMemory: DataController = InMemoryDataController()

  public func storeExists() -> Bool {
    return FileManager.default.fileExists(atPath: supportStoreURL.path)
  }

  private let container = NSPersistentContainer(
    name: DataController.modelName,
    managedObjectModel: DataController.model)

  /// 警告！请使用 `storeURL`。这仅用于迁移目的。
  private var supportStoreURL: URL {
    return storeURL(for: FileManager.SearchPathDirectory.applicationSupportDirectory)
  }

  private func storeURL(for directory: FileManager.SearchPathDirectory) -> URL {
    let urls = FileManager.default.urls(for: directory, in: .userDomainMask)
    guard let docURL = urls.last else {
      Logger.module.error("无法加载以下目录的 URL：\(directory.rawValue, privacy: .public)")
      fatalError()
    }

    return docURL.appendingPathComponent(DataController.databaseName)
  }

  // MARK: - 数据框架接口

  static func perform(
    context: WriteContext = .new(inMemory: false), save: Bool = true,
    task: @escaping (NSManagedObjectContext) -> Void
  ) {
    if !DataController.shared.initializationCompleted && !AppConstants.isRunningTest {
      assertionFailure("在数据库初始化之前在上下文上执行操作")
      return
    }

    switch context {
    case .existing(let existingContext):
      // 如果提供了现有上下文，我们仅调用代码闭包。
      // 在传递 `.new` WriteContext 时，在更高层次上调用 `performTask()` 来完成队列操作和保存。
      task(existingContext)
    case .new(let inMemory):
      // 虽然保持相同的队列没有任何区别，但为了独立处理它们，保持它们不同。
      let queue = inMemory ? DataController.sharedInMemory.operationQueue : DataController.shared.operationQueue

      queue.addOperation({
        let backgroundContext = inMemory ? DataController.newBackgroundContextInMemory() : DataController.newBackgroundContext()
        // performAndWait 不会阻塞主线程，因为它在 OperationQueue 的后台线程上触发。
        backgroundContext.performAndWait {
          task(backgroundContext)

          guard save && backgroundContext.hasChanges else { return }

          do {
            assert(!Thread.isMainThread)
            try backgroundContext.save()
          } catch {
            Logger.module.error("performTask 保存错误：\(error.localizedDescription, privacy: .public)")
          }
        }
      })
    }
  }

  public static func performOnMainContext(save: Bool = true, task: @escaping (NSManagedObjectContext) -> Void) {
    self.perform(context: .existing(self.viewContext), save: save, task: task)
  }

  public static var swiftUIContext: NSManagedObjectContext {
    return DataController.shared.container.viewContext
  }

  // Context 对象还允许我们访问所有持久容器数据（如果需要）。
  static var viewContext: NSManagedObjectContext {
    return DataController.shared.container.viewContext
  }

  // Context 对象还允许我们访问所有持久容器数据（如果需要）。
  static var viewContextInMemory: NSManagedObjectContext {
    return DataController.sharedInMemory.container.viewContext
  }

  func addPersistentStore(for container: NSPersistentContainer, store: URL) {
    let storeDescription = NSPersistentStoreDescription(url: store)

    // 这使数据库文件在设备重新启动后首次用户解锁之前都是加密的。
    let completeProtection = FileProtectionType.completeUntilFirstUserAuthentication as NSObject
    storeDescription.setOption(completeProtection, forKey: NSPersistentStoreFileProtectionKey)

    container.persistentStoreDescriptions = [storeDescription]
  }

  private func configureContainer(_ container: NSPersistentContainer, store: URL) {
    addPersistentStore(for: container, store: store)

    container.loadPersistentStores(completionHandler: { store, error in
      if let error = error {
        // 如果存储已经存在，则不要使应用程序崩溃。
        if (error as NSError).code != Self.storeExistsErrorCode {
          fatalError("加载持久存储时出错：\(error.localizedDescription)")
        }
      }

      if store.type != NSInMemoryStoreType {
        // 这使数据库文件在设备重新启动后首次用户解锁之前都是加密的。
        let completeProtection = FileProtectionType.completeUntilFirstUserAuthentication as NSObject
        store.setOption(completeProtection, forKey: NSPersistentStoreFileProtectionKey)
      }
    })
    // 我们需要这个，以便 `viewContext` 在后台任务更改时得到更新。
    container.viewContext.automaticallyMergesChangesFromParent = true
  }

  static func newBackgroundContext() -> NSManagedObjectContext {
    let backgroundContext = DataController.shared.container.newBackgroundContext()
    // 理论上，合并策略不应该有影响
    // 因为所有操作都在同步的操作队列上执行。
    // 但是为了防止任何错误，最好有一个，这样应用程序不会崩溃给用户。
    backgroundContext.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
    return backgroundContext
  }

  static func newBackgroundContextInMemory() -> NSManagedObjectContext {
    let backgroundContext = DataController.sharedInMemory.container.newBackgroundContext()
    backgroundContext.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
    return backgroundContext
  }
}
