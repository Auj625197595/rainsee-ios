// 版权 2022 年 Brave 作者。保留所有权利。
// 此源代码表单受 Mozilla Public License, v. 2.0 条款约束。
// 如果未与此文件一起分发 MPL 的副本，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import Shared
import BraveCore

/// 泛型资源下载器类，负责获取资源的 actor
actor ResourceDownloader<Resource: DownloadResourceInterface>: Sendable {
  /// 表示下载的对象
  struct DownloadResult: Equatable {
    let date: Date
    let fileURL: URL
    let isModified: Bool
  }
  
  /// 表示在资源下载期间出现的错误的对象
  enum DownloadResultError: Error {
    case noData
  }
  
  /// 表示下载结果的对象
  private enum DownloadResultStatus {
    case notModified(URL, Date)
    case downloaded(CachedNetworkResource, Date)
  }
  
  /// 该资源下载器使用的默认获取间隔。在生产环境中为 6 小时，在调试环境中为每 10 分钟一次。
  private static var defaultFetchInterval: TimeInterval {
    return AppConstants.buildChannel.isPublic ? 6.hours : 10.minutes
  }
  
  /// 执行请求的网络管理器
  private let networkManager: NetworkManager
  
  /// 使用给定的网络管理器初始化此类
  init(networkManager: NetworkManager = NetworkManager()) {
    self.networkManager = networkManager
  }
  
  /// 为给定资源返回下载流。下载流将按照提供的 `fetchInterval` 指定的时间间隔获取数据。
  func downloadStream(for resource: Resource, every fetchInterval: TimeInterval = defaultFetchInterval) -> ResourceDownloaderStream<Resource> {
    return ResourceDownloaderStream(resource: resource, resourceDownloader: self, fetchInterval: fetchInterval)
  }
  
  /// 下载给定资源类型的过滤列表，并将其存储到缓存文件夹 URL 中
  @discardableResult
  func download(resource: Resource) async throws -> DownloadResult {
    let result = try await downloadInternal(resource: resource)
    
    switch result {
    case .downloaded(let networkResource, let date):
      // 清除任何旧数据
      try resource.removeFile()
      // 如果需要，创建一个缓存文件夹
      let cacheFolderURL = try resource.getOrCreateCacheFolder()
      // 将数据保存到文件
      let fileURL = cacheFolderURL.appendingPathComponent(resource.cacheFileName)
      try writeDataToDisk(data: networkResource.data, toFileURL: fileURL)
      // 将 etag 保存到文件
      if let data = networkResource.etag?.data(using: .utf8) {
        try writeDataToDisk(
          data: data,
          toFileURL: cacheFolderURL.appendingPathComponent(resource.etagFileName)
        )
      }
      // 返回文件 URL
      let creationDate = try? resource.creationDate()
      return DownloadResult(
        date: creationDate ?? date, fileURL: fileURL, isModified: true
      )
    case .notModified(let fileURL, let date):
      let creationDate = try? resource.creationDate()
      return DownloadResult(
        date: creationDate ?? date, fileURL: fileURL, isModified: false
      )
    }
  }
  
  private func downloadInternal(resource: Resource) async throws -> DownloadResultStatus {
    let etag = try? resource.createdEtag()
    
    do {
      let networkResource = try await self.networkManager.downloadResource(
        with: resource.externalURL,
        resourceType: .cached(etag: etag),
        checkLastServerSideModification: !AppConstants.buildChannel.isPublic,
        customHeaders: resource.headers)
      
      guard !networkResource.data.isEmpty else {
        throw DownloadResultError.noData
      }
      
      let date = try resource.creationDate()
      return .downloaded(networkResource, date ?? Date())
    } catch let error as NetworkManagerError {
      if error == .fileNotModified, let fileURL = resource.downloadedFileURL {
        let date = try resource.creationDate()
        return .notModified(fileURL, date ?? Date())
      } else {
        throw error
      }
    }
  }
  
  /// 将给定的 `Data` 写入磁盘到指定的文件 `URL`
  /// 到 `applicationSupportDirectory` `SearchPathDirectory` 中。
  ///
  /// - 注意: `fileName` 必须包含包括扩展名在内的完整文件名。
  private func writeDataToDisk(data: Data, toFileURL fileURL: URL) throws {
    try data.write(to: fileURL, options: [.atomic])
  }
}
