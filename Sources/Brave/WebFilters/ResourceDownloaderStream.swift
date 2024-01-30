// 版权 2022 年 Brave 作者。保留所有权利。
// 此源代码表单受 Mozilla Public License, v. 2.0 条款约束。
// 如果未与此文件一起分发 MPL 的副本，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation

/// 为给定资源的无限序列迭代器
struct ResourceDownloaderStream<Resource: DownloadResourceInterface>: Sendable, AsyncSequence, AsyncIteratorProtocol {
  typealias Element = Result<ResourceDownloader<Resource>.DownloadResult, Error>
  private let resource: Resource
  private let resourceDownloader: ResourceDownloader<Resource>
  private let fetchInterval: TimeInterval
  private var firstLoad = true
  
  init(resource: Resource, resourceDownloader: ResourceDownloader<Resource>, fetchInterval: TimeInterval) {
    self.resource = resource
    self.resourceDownloader = resourceDownloader
    self.fetchInterval = fetchInterval
  }
  
  /// 返回下一个下载的值，如果自上次下载以来已更改。将返回一个缓存的结果作为初始值。
  ///
  /// - 注意: 仅引发 `CancellationError` 错误。下载错误作为 `Result` 对象返回
  mutating func next() async throws -> Element? {
    if firstLoad {
      // 在第一次加载时，返回结果，以便它们立即可用。
      // 然后，我们只等待在睡眠时进行更改
      do {
        self.firstLoad = false
        let result = try await resourceDownloader.download(resource: resource)
        return .success(result)
      } catch let error as URLError {
        // 对这些错误进行软失败
        return .failure(error)
      } catch {
        throw error
      }
    }
    
    // 保持获取新数据，直到我们获得新结果
    while true {
      try await Task.sleep(seconds: fetchInterval)
      
      do {
        let result = try await resourceDownloader.download(resource: resource)
        guard result.isModified else { continue }
        return .success(result)
      } catch let error as URLError {
        // 对这些错误进行软失败
        return .failure(error)
      } catch {
        throw error
      }
    }
  }
  
  func makeAsyncIterator() -> ResourceDownloaderStream {
    return self
  }
}
