// 版权 2023 年 The Brave Authors. 保留所有权利。
// 此源代码形式受 Mozilla Public License，v. 2.0 的条款约束。
// 如果没有随此文件分发 MPL 的副本，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation

/// 表示资源下载器错误的对象
enum ResourceFileError: Error {
  case failedToCreateCacheFolder
}

/// 提供可与 `ResourceDownloader` 一起使用的下载资源接口的对象。
/// 这提供了一种通用的多用途方式，用于下载任何文件。
public protocol DownloadResourceInterface: Sendable {
  /// 在此数据下应保存的文件夹名称
  var cacheFolderName: String { get }
  var cacheFileName: String { get }
  var externalURL: URL { get }
  var headers: [String: String] { get }
}

extension DownloadResourceInterface {
  /// 存储所有下载文件的目录
  private static var cacheFolderDirectory: FileManager.SearchPathDirectory {
    return FileManager.SearchPathDirectory.applicationSupportDirectory
  }
  
  /// 保存在缓存文件夹中的 Etag 名称
  var etagFileName: String {
    return [cacheFileName, "etag"].joined(separator: ".")
  }
  
  /// 获取此资源的下载文件 URL
  ///
  /// - 注意：如果文件不存在，则返回 nil
  var downloadedFileURL: URL? {
    guard let cacheFolderURL = createdCacheFolderURL else {
      return nil
    }
    
    let fileURL = cacheFolderURL.appendingPathComponent(cacheFileName)
    
    if FileManager.default.fileExists(atPath: fileURL.path) {
      return fileURL
    } else {
      return nil
    }
  }
  
  /// 获取下载文件的 etag 的文件 URL
  ///
  /// - 注意：如果 etag 不存在，则返回 nil
  var createdEtagURL: URL? {
    guard let cacheFolderURL = createdCacheFolderURL else { return nil }
    let fileURL = cacheFolderURL.appendingPathComponent(etagFileName)
    
    if FileManager.default.fileExists(atPath: fileURL.path) {
      return fileURL
    } else {
      return nil
    }
  }
  
  /// 获取此资源的缓存文件夹
  ///
  /// - 注意：如果缓存文件夹不存在，则返回 nil
  var createdCacheFolderURL: URL? {
    guard let folderURL = Self.cacheFolderDirectory.url else { return nil }
    let cacheFolderURL = folderURL.appendingPathComponent(cacheFolderName)
    
    if FileManager.default.fileExists(atPath: cacheFolderURL.path) {
      return cacheFolderURL
    } else {
      return nil
    }
  }
  
  /// 加载此资源的数据
  ///
  /// - 注意：如果数据不存在，则返回 nil
  func downloadedData() throws -> Data? {
    guard let fileUrl = downloadedFileURL else { return nil }
    return FileManager.default.contents(atPath: fileUrl.path)
  }
  
  /// 加载此资源的字符串
  ///
  /// - 注意：如果数据不存在或文件不是在正确的编码下，则返回 nil
  func downloadedString(encoding: String.Encoding = .utf8) throws -> String? {
    guard let data = try downloadedData() else { return nil }
    return String(data: data, encoding: encoding)
  }
  
  /// 获取下载文件的创建日期
  ///
  /// - 注意：如果数据不存在，则返回 nil
  func creationDate() throws -> Date? {
    guard let fileURL = downloadedFileURL else { return nil }
    let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    return fileAttributes[.creationDate] as? Date
  }
  
  /// 获取此资源的现有 etag
  ///
  /// - 注意：如果没有创建 etag（即文件未被下载），则返回 nil
  func createdEtag() throws -> String? {
    guard let fileURL = createdEtagURL else { return nil }
    guard let data = FileManager.default.contents(atPath: fileURL.path) else { return nil }
    return String(data: data, encoding: .utf8)
  }
  
  /// 删除给定 `Resource` 的文件。不会删除包含它的文件夹。
  func removeFile() throws {
    guard
      let fileURL = downloadedFileURL
    else {
      return
    }
    
    try FileManager.default.removeItem(atPath: fileURL.path)
  }
  
  /// 删除给定 `Resource` 的所有数据
  func removeCacheFolder() throws {
    guard
      let folderURL = createdCacheFolderURL
    else {
      return
    }
    
    try FileManager.default.removeItem(atPath: folderURL.path)
  }
  
  /// 获取或创建给定 `Resource` 的缓存文件夹
  ///
  /// - 注意：从技术上讲，这实际上不能返回 nil，因为位置和文件夹是硬编码的
  func getOrCreateCacheFolder() throws -> URL {
    guard let folderURL = FileManager.default.getOrCreateFolder(
      name: cacheFolderName,
      location: Self.cacheFolderDirectory
    ) else {
      throw ResourceFileError.failedToCreateCacheFolder
    }
    
    return folderURL
  }
  
  /// 获取表示缓存下载结果的对象。
  /// 如果没有下载任何内容，则返回 nil。
  func cachedResult() throws -> ResourceDownloader<Self>.DownloadResult? {
    guard let fileURL = downloadedFileURL else { return nil }
    guard let creationDate = try creationDate() else { return nil }
    return ResourceDownloader<Self>.DownloadResult(date: creationDate, fileURL: fileURL, isModified: false)
  }
}
