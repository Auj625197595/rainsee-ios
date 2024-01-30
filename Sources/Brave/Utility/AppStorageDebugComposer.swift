// 版权 © 2023 Brave 作者。保留所有权利。
// 本源代码表单受 Mozilla 公共许可证 2.0 版的条款约束。
// 如果未随此文件分发 MPL 的副本，则可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import UIKit
import os.log

// 应用存储调试组合器结构体
struct AppStorageDebugComposer {
  
  /// 此函数准备数据，以帮助我们识别用户可能遇到的任何应用存储问题。
  static func compose() -> String {
    // 打印设备信息
    var printDeviceInfo: String {
      let device = UIDevice.current
      let model = device.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
      let iOSVersion = "\(device.systemName) \(device.systemVersion)"
      let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
      
      return "设备信息: \(model), \(iOSVersion), Brave \(appVersion)"
    }
    
    // 打印文件夹树结构
    var printFolderTreeStructure: String {
      let fm = FileManager.default
      // 获取主目录路径
      guard let enumerator = fm.enumerator(
        at: URL(fileURLWithPath: NSHomeDirectory()),
        includingPropertiesForKeys: nil
      ) else { return "" }
      
      // 字节计数格式化器
      let formatter = ByteCountFormatter().then {
        $0.countStyle = .file
        $0.allowsNonnumericFormatting = false
        $0.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
      }
      
      var result = ""
      
      while let file = enumerator.nextObject() as? URL {
        do {
          // 判断是否为目录
          let isDirectory = (try file.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
          // 跳过单个文件，跳过嵌套超过 4 级的文件夹。
          guard isDirectory, enumerator.level <= 4 else { continue }

          let _1MB = 1000 * 1000
          // 跳过大小小于 1MB 的文件夹
          guard let directorySize = try fm.directorySize(at: file), directorySize > _1MB else { continue }
          
          // 格式化文件夹大小
          let formattedSize = formatter.string(fromByteCount: Int64(directorySize))
          
          let indentation = String(repeating: "\t", count: enumerator.level - 1)
          result += indentation + file.lastPathComponent + "(\(formattedSize))\n"
        } catch {
          // 打印错误信息并继续循环
          Logger.module.error("AppStorageDebug error: \(error)")
          continue
        }
      }
      
      return result
    }
    
    // 构建结果字符串
    let result =
    """
    \(printDeviceInfo)
    \(printFolderTreeStructure)
    """
    
    return result
  }
}
