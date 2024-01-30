// 版权 2023 年 The Brave Authors. 保留所有权利。
// 本源代码形式受 Mozilla Public License，v. 2.0 的条款约束。
// 如果没有随此文件分发 MPL 的副本，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import Shared

// 定义 BraveS3Resource 枚举，实现 Hashable 和 DownloadResourceInterface 协议
enum BraveS3Resource: Hashable, DownloadResourceInterface {
  
  // 防抖链接的规则
  case debounceRules
  
  // Slim-list 处理的规则，为 iOS 使用进行过滤
  // 基于以下规则: https://github.com/brave/adblock-resources/blob/master/filter_lists/default.json
  case adBlockRules
  
  // 美化过滤规则
  // - 警告: 不要使用这个。这仅是为了我们能够删除文件而存在
  case deprecatedGeneralCosmeticFilters
  
  // 包含服务密钥的 info plist 键的名称
  private static let servicesKeyName = "SERVICES_KEY"
  
  // 包含服务密钥的标头值的名称
  private static let servicesKeyHeaderValue = "BraveServiceKey"
  
  // 托管防抖（和其他）文件的基本 s3 环境 URL。
  // 不能直接使用，必须与路径结合使用
  private static var baseResourceURL: URL = {
    if AppConstants.buildChannel.isPublic {
      return URL(string: "https://adblock-data.s3.brave.com")!
    } else {
      return URL(string: "https://adblock-data-staging.s3.bravesoftware.com")!
    }
  }()
  
  // 在此数据下应保存的文件夹名称
  var cacheFolderName: String {
    switch self {
    case .debounceRules:
      return "debounce-data"
    case .adBlockRules:
      return "abp-data"
    case .deprecatedGeneralCosmeticFilters:
      return "cmf-data"
    }
  }
  
  // 获取存储在设备上的文件名称
  var cacheFileName: String {
    switch self {
    case .debounceRules:
      return "ios-debouce.json"
    case .adBlockRules:
      return "latest.txt"
    case .deprecatedGeneralCosmeticFilters:
      return "ios-cosmetic-filters.dat"
    }
  }
  
  // 获取给定过滤器列表和此资源类型的外部路径
  var externalURL: URL {
      // 根据不同的 BraveS3Resource 枚举值，返回相应的资源路径
      switch self {
          // 防抖规则的路径
          case .debounceRules:
            return Self.baseResourceURL.appendingPathComponent("/ios/debounce.json")
            
          // AdBlock 规则的路径
          case .adBlockRules:
            return Self.baseResourceURL.appendingPathComponent("/ios/latest.txt")
            
          // 弃用的通用美化过滤器规则的路径
          case .deprecatedGeneralCosmeticFilters:
            return Self.baseResourceURL.appendingPathComponent("/ios/ios-cosmetic-filters.dat")
      }

  }
  
  // 请求标头
  var headers: [String: String] {
    var headers = [String: String]()
    
    if let servicesKeyValue = Bundle.main.getPlistString(for: Self.servicesKeyName) {
      headers[Self.servicesKeyHeaderValue] = servicesKeyValue
    }
    
    return headers
  }
}
