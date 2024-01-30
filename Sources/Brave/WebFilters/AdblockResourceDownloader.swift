// 此源代码形式受 Mozilla Public License，v. 2.0 的条款约束。
// 如果没有随此文件分发 MPL 的副本，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import BraveCore
import Shared
import BraveShared
import os.log

/// 一个负责下载一些通用广告拦截资源的类
public actor AdblockResourceDownloader: Sendable {
  
  public static let shared = AdblockResourceDownloader()
  
  /// 所有此下载器处理的不同资源
  static let handledResources: [BraveS3Resource] = [
    .adBlockRules, .debounceRules
  ]
  
  /// 需要删除的旧资源列表，以防占用用户的磁盘空间
  private static let deprecatedResources: [BraveS3Resource] = [.deprecatedGeneralCosmeticFilters]
  
  /// 将用于下载所有资源的资源下载器
  private let resourceDownloader: ResourceDownloader<BraveS3Resource>

  init(networkManager: NetworkManager = NetworkManager()) {
    self.resourceDownloader = ResourceDownloader(networkManager: networkManager)
  }
  
  /// 根据允许的模式加载缓存和捆绑数据
  func loadCachedAndBundledDataIfNeeded(allowedModes: Set<ContentBlockerManager.BlockingMode>) async {
    guard !allowedModes.isEmpty else { return }
    await loadCachedDataIfNeeded(allowedModes: allowedModes)
    await loadBundledDataIfNeeded(allowedModes: allowedModes)
  }
  
  /// 仅在文件尚未编译时加载给定内容阻止模式的捆绑数据
  private func loadBundledDataIfNeeded(allowedModes: Set<ContentBlockerManager.BlockingMode>) async {
    // 仅在我们没有任何已加载的内容时编译捆绑的阻止列表
    await ContentBlockerManager.GenericBlocklistType.allCases.asyncConcurrentForEach { genericType in
      let blocklistType = ContentBlockerManager.BlocklistType.generic(genericType)
      let modes = await blocklistType.allowedModes.asyncFilter { mode in
        guard allowedModes.contains(mode) else { return false }
        // 对于非 .blockAds，可以安全重新编译，因为它们永远不会被下载的文件替换
        if genericType != .blockAds { return true }
        
        // .blockAds 是特殊的，因为它可以被下载的文件替换
        // 因此，我们首先需要检查它是否已经存在
        if await ContentBlockerManager.shared.hasRuleList(for: blocklistType, mode: mode) {
          return false
        } else {
          return true
        }
      }
      
      do {
        try await ContentBlockerManager.shared.compileBundledRuleList(for: genericType, modes: modes)
      } catch {
        assertionFailure("捆绑文件不应该编译失败")
      }
    }
  }
  
  /// 加载缓存数据并等待结果
  private func loadCachedDataIfNeeded(allowedModes: Set<ContentBlockerManager.BlockingMode>) async {
    // 在此处加载下载的资源（如果需要）
    await Self.handledResources.asyncConcurrentForEach { resource in
      do {
        // 检查我们是否对给定资源有缓存的结果
        if let cachedResult = try resource.cachedResult() {
          await self.handle(downloadResult: cachedResult, for: resource, allowedModes: allowedModes)
        }
      } catch {
        ContentBlockerManager.log.error(
          "为资源 \(resource.cacheFileName) 加载缓存数据失败: \(error)"
        )
      }
    }
  }

  /// 启动获取资源
  public func startFetching() {
    let fetchInterval = AppConstants.buildChannel.isPublic ? 6.hours : 10.minutes
    
    for resource in Self.handledResources {
      startFetching(resource: resource, every: fetchInterval)
    }
    
    // 移除任何旧文件
    // 在不久的将来可以删除此代码
    for resource in Self.deprecatedResources {
      do {
        try resource.removeCacheFolder()
      } catch {
        ContentBlockerManager.log.error(
          "移除废弃文件 \(resource.cacheFileName) 失败: \(error)"
        )
      }
    }
  }
  
  /// 以固定时间间隔开始获取给定资源
  private func startFetching(resource: BraveS3Resource, every fetchInterval: TimeInterval) {
    Task { @MainActor in
      for try await result in await self.resourceDownloader.downloadStream(for: resource, every: fetchInterval) {
        switch result {
        case .success(let downloadResult):
          await self.handle(
            downloadResult: downloadResult, for: resource,
            allowedModes: Set(ContentBlockerManager.BlockingMode.allCases)
          )
        case .failure(let error):
          ContentBlockerManager.log.error("获取资源 `\(resource.cacheFileName)`: \(error.localizedDescription)")
        }
      }
    }
  }
  
  /// 处理给定资源的下载文件 URL
  private func handle(downloadResult: ResourceDownloader<BraveS3Resource>.DownloadResult, for resource: BraveS3Resource, allowedModes: Set<ContentBlockerManager.BlockingMode>) async {
    switch resource {
    case .adBlockRules:
      let blocklistType = ContentBlockerManager.BlocklistType.generic(.blockAds)
      var modes = blocklistType.allowedModes
      
      if !downloadResult.isModified && !allowedModes.isEmpty {
        // 如果下载没有被修改，仅为性能原因编译缺失的模式
        let missingModes = await ContentBlockerManager.shared.missingModes(for: blocklistType)
        modes = missingModes.filter({ allowedModes.contains($0) })
      }

      // 不需要编译任何模式
      guard !modes.isEmpty else { return }
      
      do {
        guard let fileURL = resource.downloadedFileURL else {
          assertionFailure("此文件已成功下载，不应为 nil")
          return
        }
        
        // 尝试编译
        try await ContentBlockerManager.shared.compileRuleList(
          at: fileURL, for: blocklistType, modes: modes
        )
      } catch {
        ContentBlockerManager.log.error(
          "编译 `\(blocklistType.debugDescription)` 的规则列表失败: \(error.localizedDescription)"
        )
      }
      
    case .debounceRules:
      // 我们不希望为相同的缓存文件多次设置防抖规则
      guard downloadResult.isModified || DebouncingService.shared.matcher == nil else {
        return
      }
      
      do {
        guard let data = try resource.downloadedData() else {
          assertionFailure("我们刚刚下载了此文件，它怎么可能不存在？")
          return
        }
        
        try DebouncingService.shared.setup(withRulesJSON: data)
      } catch {
        ContentBlockerManager.log.error("设置防抖规则失败: \(error.localizedDescription)")
      }
      
    case .deprecatedGeneralCosmeticFilters:
      assertionFailure("不应处理此资源类型")
    }
  }
}
