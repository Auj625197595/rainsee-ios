// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import BraveCore
import Preferences
import Shared
import os.log

// 定义一个结构体表示同步设备信息
public struct BraveSyncDevice: Codable {
  let chromeVersion: String
  let hasSharingInfo: Bool
  let id: String
  let guid: String
  let isCurrentDevice: Bool
  let supportsSelfDelete: Bool
  let lastUpdatedTimestamp: TimeInterval
  let name: String?
  let os: String
  let sendTabToSelfReceivingEnabled: Bool
  let type: String
}

// 扩展 BraveSyncAPI
extension BraveSyncAPI {
  
  // 同步码的种子字节长度
  public static let seedByteLength = 32
  
  // 是否在同步组中
  var isInSyncGroup: Bool {
    return Preferences.Chromium.syncEnabled.value
  }
  
  /// 属性，确定本地同步链是否应该被重置
  var shouldLeaveSyncGroup: Bool {
    guard isInSyncGroup else {
      return false
    }
    
    return (!isSyncFeatureActive && !isInitialSyncFeatureSetupComplete) || isSyncAccountDeletedNoticePending
  }

  // 是否显示发送标签到自己选项
  var isSendTabToSelfVisible: Bool {
    guard let json = getDeviceListJSON(), let data = json.data(using: .utf8) else {
      return false
    }
    
    do {
      let devices = try JSONDecoder().decode([BraveSyncDevice].self, from: data)
      return devices.count > 1
    } catch {
      Logger.module.error("解析设备信息时发生错误：\(error.localizedDescription)")
      return false
    }
  }
  
  // 加入同步组
  @discardableResult
  func joinSyncGroup(codeWords: String, syncProfileService: BraveSyncProfileServiceIOS) -> Bool {
    if setSyncCode(codeWords) {
      // 在加入链时启用默认的同步类型“Bookmarks”
      Preferences.Chromium.syncBookmarksEnabled.value = true
      enableSyncTypes(syncProfileService: syncProfileService)
      requestSync()
      setSetupComplete()
      Preferences.Chromium.syncEnabled.value = true

      return true
    }
    return false
  }

  // 从同步组中删除设备
  func removeDeviceFromSyncGroup(deviceGuid: String) {
    deleteDevice(deviceGuid)
  }

  /// 离开同步链的方法
  /// 移除观察者，清除本地偏好设置，并在 brave-core 侧调用 reset chain
  /// - Parameter preservingObservers: 决定是否保留或移除观察者的参数
  func leaveSyncGroup(preservingObservers: Bool = false) {
    if !preservingObservers {
      // 在离开同步链之前移除所有观察者
      removeAllObservers()
    }
    
    resetSyncChain()
    Preferences.Chromium.syncEnabled.value = false
  }
  
  // 重置同步链
  func resetSyncChain() {
    Preferences.Chromium.syncHistoryEnabled.value = false
    Preferences.Chromium.syncPasswordsEnabled.value = false
    Preferences.Chromium.syncOpenTabsEnabled.value = false
    
    resetSync()
  }

  // 启用同步类型
  func enableSyncTypes(syncProfileService: BraveSyncProfileServiceIOS) {
    syncProfileService.userSelectedTypes = []
    
    if Preferences.Chromium.syncBookmarksEnabled.value {
      syncProfileService.userSelectedTypes.update(with: .BOOKMARKS)
    }

    if Preferences.Chromium.syncHistoryEnabled.value {
      syncProfileService.userSelectedTypes.update(with: .HISTORY)
    }

    if Preferences.Chromium.syncPasswordsEnabled.value {
      syncProfileService.userSelectedTypes.update(with: .PASSWORDS)
    }
    
    if Preferences.Chromium.syncOpenTabsEnabled.value {
      syncProfileService.userSelectedTypes.update(with: .TABS)
    }
  }

  /// 添加 SyncService 的 onStateChanged 和 onSyncShutdown 的观察者方法
  /// onStateChanged 可以在各种情况下调用，如成功初始化、服务不可用、同步关闭、同步错误、同步链已删除等
  /// - Parameters:
  ///   - onStateChanged: SyncService 状态更改的回调
  ///   - onServiceShutdown: SyncService 关闭的回调
  /// - Returns: 服务的监听器
  func addServiceStateObserver(_ onStateChanged: @escaping () -> Void, onServiceShutdown: @escaping () -> Void = {}) -> AnyObject {
    let serviceStateListener = BraveSyncServiceListener(onRemoved: { [weak self] observer in
      self?.serviceObservers.remove(observer)
    })
    serviceStateListener.observer = createSyncServiceObserver(onStateChanged, onSyncServiceShutdown: onServiceShutdown)

    serviceObservers.add(serviceStateListener)
    return serviceStateListener
  }

  // 添加设备状态观察者
  func addDeviceStateObserver(_ observer: @escaping () -> Void) -> AnyObject {
    let deviceStateListener = BraveSyncDeviceListener(
      observer,
      onRemoved: { [weak self] observer in
        self?.deviceObservers.remove(observer)
      })
    deviceStateListener.observer = createSyncDeviceObserver(observer)

    deviceObservers.add(deviceStateListener)
    return deviceStateListener
  }

  // 移除所有观察者
  public func removeAllObservers() {
    serviceObservers.objectEnumerator().forEach({
      ($0 as? BraveSyncServiceListener)?.observer = nil
    })

    deviceObservers.objectEnumerator().forEach({
      ($0 as? BraveSyncDeviceListener)?.observer = nil
    })

    serviceObservers.removeAllObjects()
    deviceObservers.removeAllObjects()
  }

  private struct AssociatedObjectKeys {
    static var serviceObservers: Int = 0
    static var deviceObservers: Int = 1
  }

  // 服务观察者列表
  private var serviceObservers: NSHashTable<BraveSyncServiceListener> {
    if let observers = objc_getAssociatedObject(self, &AssociatedObjectKeys.serviceObservers) as? NSHashTable<BraveSyncServiceListener> {
      return observers
    }

    let defaultValue = NSHashTable<BraveSyncServiceListener>.weakObjects()
    objc_setAssociatedObject(self, &AssociatedObjectKeys.serviceObservers, defaultValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

    return defaultValue
  }

  // 设备观察者列表
  private var deviceObservers: NSHashTable<BraveSyncDeviceListener> {
    if let observers = objc_getAssociatedObject(self, &AssociatedObjectKeys.deviceObservers) as? NSHashTable<BraveSyncDeviceListener> {
      return observers
    }

    let defaultValue = NSHashTable<BraveSyncDeviceListener>.weakObjects()
    objc_setAssociatedObject(self, &AssociatedObjectKeys.deviceObservers, defaultValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

    return defaultValue
  }

}

// BraveSyncAPI 的扩展
extension BraveSyncAPI {
  // 用于监听 SyncService 状态的内部类
  private class BraveSyncServiceListener: NSObject {

    // MARK: Internal

    var observer: Any?
    private var onRemoved: (BraveSyncServiceListener) -> Void

    // MARK: Lifecycle

    fileprivate init(onRemoved: @escaping (BraveSyncServiceListener) -> Void) {
      self.onRemoved = onRemoved
      super.init()
    }

    deinit {
      self.onRemoved(self)
    }
  }

  // 用于监听 SyncDevice 状态的内部类
  private class BraveSyncDeviceListener: NSObject {

    // MARK: Internal

    var observer: Any?
    private var onRemoved: (BraveSyncDeviceListener) -> Void

    // MARK: Lifecycle

    fileprivate init(
      _ onDeviceInfoChanged: @escaping () -> Void,
      onRemoved: @escaping (BraveSyncDeviceListener) -> Void
    ) {
      self.onRemoved = onRemoved
      super.init()
    }

    deinit {
      self.onRemoved(self)
    }
  }
}

// BraveSyncAPI.QrCodeDataValidationResult 的扩展
extension BraveSyncAPI.QrCodeDataValidationResult {
  var errorDescription: String {
    switch self {
    case .valid:
      return ""
    case .notWellFormed:
      return Strings.invalidSyncCodeDescription
    case .versionDeprecated:
      return Strings.syncDeprecatedVersionError
    case .expired:
      return Strings.syncExpiredError
    case .validForTooLong:
      return Strings.syncValidForTooLongError
    default:
      assertionFailure("无效的错误描述")
      return Strings.invalidSyncCodeDescription
    }
  }
}

// BraveSyncAPI.WordsValidationStatus 的扩展
// 对 BraveSyncAPI.WordsValidationStatus 枚举的扩展
extension BraveSyncAPI.WordsValidationStatus {
  // 错误描述属性，用于获取不同状态下的错误描述字符串
  var errorDescription: String {
    switch self {
    case .valid:
      return "" // 有效状态，返回空字符串
    case .notValidPureWords:
      return Strings.invalidSyncCodeDescription // 同步码无效的纯文字状态
    case .versionDeprecated:
      return Strings.syncDeprecatedVersionError // 同步版本已废弃的状态
    case .expired:
      return Strings.syncExpiredError // 同步码过期的状态
    case .validForTooLong:
      return Strings.syncValidForTooLongError // 同步码有效期过长的状态
    case .wrongWordsNumber:
      return Strings.notEnoughWordsDescription // 同步码单词数量不足的状态
    default:
      assertionFailure("无效的错误描述") // 对于未处理的情况，发出断言错误
      return Strings.invalidSyncCodeDescription // 返回默认的无效同步码描述
    }
  }
}

