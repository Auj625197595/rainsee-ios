// Copyright 2023 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation

/// 在多个不同目标中访问的首选项
///
/// 一些应该在将来移动到 ClientPreferences 或它们自己的目标首选项文件中的首选项
extension Preferences {
  public final class BlockStats {
    public static let adsCount = Option<Int>(key: "stats.adblock", default: 0)
    public static let trackersCount = Option<Int>(key: "stats.tracking", default: 0)
    public static let scriptsCount = Option<Int>(key: "stats.scripts", default: 0)
    public static let imagesCount = Option<Int>(key: "stats.images", default: 0)
    public static let phishingCount = Option<Int>(key: "stats.phishing", default: 0)
    public static let fingerprintingCount = Option<Int>(key: "stats.fingerprinting", default: 0)
  }
  
  public final class BlockFileVersion {
    public static let adblock = Option<String?>(key: "blockfile.adblock", default: nil)
    public static let httpse = Option<String?>(key: "blockfile.httpse", default: nil)
  }
  
  public final class ProductNotificationBenchmarks {
    public static let videoAdBlockShown = Option<Bool>(key: "product-benchmark.videoAdBlockShown", default: false)
    public static let trackerTierCount = Option<Int>(key: "product-benchmark.trackerTierCount", default: 0)
    public static let showingSpecificDataSavedEnabled = Option<Bool>(key: "product-benchmark.showingSpecificDataSavedEnabled", default: false)
  }
  
  public final class Shields {
    public static let allShields = [httpsEverywhere, googleSafeBrowsing, blockScripts, fingerprintingProtection, blockImages]
    
    /// 如果加载的页面尝试使用 HTTP，则将网站升级到 HTTPS
    public static let httpsEverywhere = Option<Bool>(key: "shields.https-everywhere", default: true)
    
    /// 启用 Google 安全浏览
    public static let googleSafeBrowsing = Option<Bool>(key: "shields.google-safe-browsing", default: false)
    
    /// 在浏览器中禁用 JavaScript 执行
    public static let blockScripts = Option<Bool>(key: "shields.block-scripts", default: false)
    
    /// 对用户会话启用指纹保护
    public static let fingerprintingProtection = Option<Bool>(key: "shields.fingerprinting-protection", default: true)
    
    /// 启用将 Google 的 AMP（加速移动页面）重定向到原始页面
    public static let autoRedirectAMPPages = Option<Bool>(key: "shields.auto-redirect-amp-pages", default: true)
    
    /// 启用重定向跟踪 URL（即去抖动）
    public static let autoRedirectTrackingURLs = Option<Bool>(key: "shields.auto-redirect-tracking-urls", default: true)
    
    /// 在浏览器中禁用图像加载
    public static let blockImages = Option<Bool>(key: "shields.block-images", default: false)
    
    /// 除了全局广告拦截规则外，添加自定义基于国家的规则。
    /// 此设置对所有区域设置默认启用。
    public static let useRegionAdBlock = Option<Bool>(key: "shields.regional-adblock", default: true)
    
    /// 广告拦截统计数据的下载数据文件版本。
    public static let adblockStatsDataVersion = Option<Int?>(key: "stats.adblock-data-version", default: nil)
    
    /// 盾牌 UI 中高级控件是否默认可见
    public static let advancedControlsVisible = Option<Bool>(key: "shields.advanced-controls-visible", default: false)
    
    /// 我们是否报告了盾牌的初始状态以供 p3a 使用
    public static let initialP3AStateReported = Option<Bool>(key: "shields.initial-p3a-state-reported", default: false)
  }
  
  public final class Rewards {
    public static let hideRewardsIcon = Option<Bool>(key: "rewards.new-hide-rewards-icon", default: false)
    public static let rewardsToggledOnce = Option<Bool>(key: "rewards.rewards-toggled-once", default: false)
    public static let isUsingBAP = Option<Bool?>(key: "rewards.is-using-bap", default: nil)
    public static let adaptiveCaptchaFailureCount = Option<Int>(key: "rewards.adaptive-captcha-failure-count", default: 0)
    public static let adsEnabledTimestamp = Option<Date?>(key: "rewards.ads.last-time-enabled", default: nil)
    public static let adsDisabledTimestamp = Option<Date?>(key: "rewards.ads.last-time-disabled", default: nil)
    
    public enum EnvironmentOverride: Int {
      case none
      case staging
      case prod
      case dev
      
      public var name: String {
        switch self {
        case .none: return "None"
        case .staging: return "Staging"
        case .prod: return "Prod"
        case .dev: return "Dev"
        }
      }
      
      public static var sortedCases: [EnvironmentOverride] {
        return [.none, .dev, .staging, .prod]
      }
    }
    
    /// 在调试/测试中，这是被覆盖的环境。
    public static let environmentOverride = Option<Int>(
      key: "rewards.environment-override",
      default: EnvironmentOverride.none.rawValue)
    
    public static let debugFlagIsDebug = Option<Bool?>(key: "rewards.flag.is-debug", default: nil)
    public static let debugFlagRetryInterval = Option<Int?>(key: "rewards.flag.retry-interval", default: nil)
    public static let debugFlagReconcileInterval = Option<Int?>(key: "rewards.flag.reconcile-interval", default: nil)
    
    /// 在调试/测试中，广告应在自动解除之前的秒数
    public static let adsDurationOverride = Option<Int?>(key: "rewards.ads.dismissal-override", default: nil)
    
    /// 用户先前是否成功注册
    public static let didEnrollDeviceCheck = Option<Bool>(key: "rewards.devicecheck.did.enroll", default: false)
  }
  
  public final class BraveCore {
    /// 传递到 BraveCoreMain 的开关
    ///
    /// 此首选项存储 `BraveCoreSwitch` 原始值列表
    public static let activeSwitches = Option<[String]>(key: "brave-core.active-switches", default: [])
    
    /// 如果活动，每个键是 `BraveCoreSwitch` 的值
    ///
    /// 每个键都是 `BraveCoreSwitch`
    public static let switchValues = Option<[String: String]>(key: "brave-core.switches.values", default: [:])
  }
  
  public final class AppState {
    /// 用于确定应用程序在前一会话中是否以用户交互退出的标志
    ///
    /// 只应在启动时检查值
    public static let backgroundedCleanly = Option<Bool>(key: "appstate.backgrounded-cleanly", default: true)
    
    /// 用于上次获取的过滤列表文件夹路径的缓存值
    ///
    /// 这是一个有用的设置，因为在启动期间加载过滤列表需要太长时间
    /// 因此我们可以尝试立即加载它们，并在第一次标签加载时准备好它们
    @MainActor public static let lastLegacyDefaultFilterListFolderPath =
      Option<String?>(key: "caching.last-default-filter-list-folder-path", default: nil)
    
    /// 用于上次获取的广告拦截资源文件夹路径的缓存值
    ///
    /// 这是一个有用的设置，因为在启动期间加载广告拦截需要太长时间
    /// 因此我们可以尝试立即加载它们，并在第一次标签加载时准备好它们
    @MainActor public static let lastAdBlockResourcesFolderPath =
      Option<String?>(key: "caching.last-ad-block-resources-folder-path", default: nil)
    
    /// 用于上次获取的过滤列表组件文件夹路径的缓存值
    ///
    /// 这是一个有用的设置，因为在启动期间加载过滤列表需要太长时间
    /// 因此我们可以尝试立即加载它们，并在第一次标签加载时准备好它们
    @MainActor public static let lastFilterListCatalogueComponentFolderPath =
      Option<String?>(key: "caching.last-filter-list-catalogue-component-folder-path", default: nil)
    
    /// 用于指示是否正在积极进行入门的缓存值
    ///
    /// 这用于确定是否可以触发并向用户显示商店的推广购买
    public static let isOnboardingActive = Option<Bool>(key: "appstate.onboarding-active", default: false)
    
    /// 用于指示是否在入门时等待 p3a 选择的缓存值
    ///
    /// 这用于确定用户是否在入门中同意了 p3a，且 dau ping 可以从 Apple API 获取推荐代码
    public static let dailyUserPingAwaitingUserConsent = Option<Bool>(key: "appstate.dau-awaiting", default: false)
  }
  
    public final class Chromium {
        /// 设备是否在同步链上
        public static let syncEnabled = Option<Bool>(key: "chromium.sync.enabled", default: false)
        
        /// 设备同步链上启用的书签同步类型
        public static let syncBookmarksEnabled = Option<Bool>(key: "chromium.sync.syncBookmarksEnabled", default: true)
        
        /// 设备同步链上启用的历史同步类型
        public static let syncHistoryEnabled = Option<Bool>(key: "chromium.sync.syncHistoryEnabled", default: false)
        
        /// 设备同步链上启用的密码同步类型
        public static let syncPasswordsEnabled = Option<Bool>(key: "chromium.sync.syncPasswordsEnabled", default: false)
        
        /// 设备同步链上启用的打开标签页同步类型
        public static let syncOpenTabsEnabled = Option<Bool>(key: "chromium.sync.openTabsEnabled", default: false)
        
        /// 上一个书签文件夹的节点ID
        public static let lastBookmarksFolderNodeId = Option<Int?>(key: "chromium.last.bookmark.folder.node.id", default: nil)
    }

}
