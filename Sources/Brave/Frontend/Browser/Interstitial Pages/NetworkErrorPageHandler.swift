// 版权 © 2021 Brave 作者。保留所有权利。
// 本源代码表单受 Mozilla 公共许可证 2.0 版的条款约束。
// 如果未随此文件分发 MPL 的副本，则可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import Shared
import BraveShared

// 网络错误页面处理类
class NetworkErrorPageHandler: InterstitialPageHandler {
  
  // 判断是否能够处理给定的 NSError
  func canHandle(error: NSError) -> Bool {
    // 处理 CFNetwork 错误
    if error.domain == kCFErrorDomainCFNetwork as String,
      let code = CFNetworkErrors(rawValue: Int32(error.code)) {

      let handledCodes: [CFNetworkErrors] = [
        .cfurlErrorNotConnectedToInternet
      ]

      return handledCodes.contains(code)
    }

    // 处理 NSURLError
    if error.domain == NSURLErrorDomain as String {
      let handledCodes: [Int] = [
        NSURLErrorNotConnectedToInternet
      ]

      return handledCodes.contains(error.code)
    }
    return false
  }

  // 生成错误页面的响应
  func response(for model: ErrorPageModel) -> (URLResponse, Data)? {
    // 获取存储在模块资源束中的 NetworkError.html 文件的路径
    guard let asset = Bundle.module.path(forResource: "NetworkError", ofType: "html") else {
      assert(false)
      return nil
    }

    // 读取文件内容
    guard var html = try? String(contentsOfFile: asset) else {
      assert(false)
      return nil
    }

    // 获取一些用于替换 HTML 内容的数据
    var domain = model.domain

    // 更新错误代码域
    if domain == kCFErrorDomainCFNetwork as String,
      let code = CFNetworkErrors(rawValue: Int32(model.errorCode)) {
      domain = GenericErrorPageHandler.CFErrorToName(code)
    } else if domain == NSURLErrorDomain {
      domain = GenericErrorPageHandler.NSURLErrorToName(model.errorCode)
    }

    let host = model.originalURL.normalizedHost(stripWWWSubdomainOnly: true) ?? model.originalHost

    let variables = [
      "page_title": host,
      "error_code": "\(model.errorCode)",
      "error_title": Strings.errorPagesNoInternetTitle,
      "error_domain": domain,
      "error_try_list": Strings.errorPagesNoInternetTry,
      "error_list_1": Strings.errorPagesNoInternetTryItem1,
      "error_list_2": Strings.errorPagesNoInternetTryItem2,
    ]

    // 替换 HTML 内容中的占位符
    variables.forEach { (arg, value) in
      html = html.replacingOccurrences(of: "%\(arg)%", with: value)
    }

    // 将 HTML 转换为 UTF-8 编码的 Data
    guard let data = html.data(using: .utf8) else {
      return nil
    }

    // 获取 InternalSchemeHandler 的响应
    let response = InternalSchemeHandler.response(forUrl: model.originalURL)
    return (response, data)
  }
}
