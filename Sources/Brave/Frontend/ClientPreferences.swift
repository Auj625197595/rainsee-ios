/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
import Foundation
import Preferences
import Shared
import UIKit

// MARK: - 用户偏好设置

enum TabBarVisibility: Int, CaseIterable {
    case never          // 永不显示标签栏
    case always         // 始终显示标签栏
    case landscapeOnly  // 仅在横屏时显示标签栏
}

public extension Preferences {
    enum AutoCloseTabsOption: Int, CaseIterable {
        case manually       // 手动关闭标签
        case oneDay         // 一天后自动关闭
        case oneWeek        // 一周后自动关闭
        case oneMonth       // 一个月后自动关闭

        /// 返回删除旧标签的时间间隔，如果不需要删除标签则返回nil。
        public var timeInterval: TimeInterval? {
            let isPublic = AppConstants.buildChannel.isPublic
            switch self {
            case .manually: return nil
            case .oneDay: return isPublic ? 1.days : 5.minutes
            case .oneWeek: return isPublic ? 7.days : 10.minutes
            case .oneMonth: return isPublic ? 30.days : 1.hours
            }
        }
    }
}

public extension Preferences {
    enum User {
        static let avator = Option<String>(key: "general.user-avator", default: "")
        static let nickName = Option<String>(key: "general.user-nickName", default: "")
        static let mkey = Option<String>(key: "general.user-mkey", default: "")
        static let sign = Option<String>(key: "general.user-sign", default: "")
    }

    enum SyncRain{
        // 上次书签同步时间
        public static let timeForBookMark = Option<Int>(key: "syncrain.time_bookmark", default: 0)
        
        public static let syncBook = Option<Bool>(key: "syncrain.syncBook", default: true)
        public static let syncHome = Option<Bool>(key: "syncrain.syncHome", default: true)
        public static let syncPw = Option<Bool>(key: "syncrain.syncPw", default: false)
        public static let syncPwTime = Option<Int>(key: "syncrain.syncPwTime", default: 0)
        public static let syncLastPwTime = Option<Int>(key: "syncrain.syncLastPwTime", default: 0)
        //本地的密码改动时间，增删改
        
        public static let syncHomeTime = Option<Int>(key: "syncrain.syncHomeTime", default: 0)
        public static let syncLastHomeTime = Option<Int>(key: "syncrain.syncLastHomeTime", default: 0)

    }
    enum General {
        
        
        public static let injectAdblock = Option<Bool>(key: "general.first-injectAdblock", default: true)
        // 用户首次启动Brave后是否为true。*永远不应手动设置为`true`！*
        public static let isFirstLaunch = Option<Bool>(key: "general.first-launch", default: true)
        /// 是否保存Brave中的登录信息
        static let saveLogins = Option<Bool>(key: "general.save-logins", default: true)
        /// 是否自动阻止来自网站的弹出窗口
        static let blockPopups = Option<Bool>(key: "general.block-popups", default: true)
        /// 控制标签栏的显示方式（或不显示）
        static let tabBarVisibility = Option<Int>(key: "general.tab-bar-visiblity", default: TabBarVisibility.always.rawValue)
        /// 在应用启动时，未使用的标签自动删除的时间
        static let autocloseTabs = Option<Int>(
            key: "general.autoclose-tabs",
            default: AutoCloseTabsOption.manually.rawValue)
        /// 定义用户的常规浏览主题
        /// `system`，跟随当前的操作系统显示模式
        public static let themeNormalMode = Option<String>(key: "general.normal-mode-theme", default: DefaultTheme.system.rawValue)
        /// 指定是否启用夜间模式
        public static let nightModeEnabled = Option<Bool>(key: "general.night-mode-enabled", default: false)
        /// 指定工具栏上是否显示书签按钮
        static let showBookmarkToolbarShortcut = Option<Bool>(key: "general.show-bookmark-toolbar-shortcut", default: UIDevice.isIpad)
        /// 控制媒体是否在后台继续播放
        static let mediaAutoBackgrounding = Option<Bool>(key: "general.media-auto-backgrounding", default: false)
        /// 控制YouTube视频是否默认以最高质量播放
        static let youtubeHighQuality = Option<String>(key: "general.youtube-high-quality", default: "wifi")
        /// 控制是否显示最后访问的书签文件夹
        static let showLastVisitedBookmarksFolder = Option<Bool>(key: "general.bookmarks-show-last-visited-bookmarks-folder", default: true)

        /// 用于确定是否显示adblock入门弹窗的首选项
        static let onboardingAdblockPopoverShown = Option<Bool>(key: "general.basic-onboarding-adblock-popover-shown", default: false)

        /// 是否显示长按操作时的链接预览。
        static let enableLinkPreview = Option<Bool>(key: "general.night-mode", default: true)

        /// 是否忽略默认浏览器提示。
        /// 适用于所有种类的提示：NTP上的横幅、启动时的模态框等。
        static let defaultBrowserCalloutDismissed =
            Option<Bool>(key: "general.default-browser-callout-dismissed", default: false)

        /// 应用（在常规浏览模式下）是否跟随通用链接
        static let followUniversalLinks = Option<Bool>(key: "general.follow-universal-links", default: true)

        /// 应用是否始终在Brave中加载YouTube
        public static let keepYouTubeInBrave = Option<Bool>(key: "general.follow-universal-links.youtube", default: false)

        /// 是否向Web视图添加下拉刷新控件
        static let enablePullToRefresh = Option<Bool>(key: "general.enable-pull-to-refresh", default: true)

        /// 全局页面缩放级别
        static var defaultPageZoomLevel = Option<Double>(key: "general.default-page-zoom-level", default: 1.0)

        static let isUsingBottomBar = Option<Bool>(key: "general.bottom-bar", default: false)
    }

    enum Search {
        /// 用户输入时是否显示搜索建议
        static let showSuggestions = Option<Bool>(key: "search.show-suggestions", default: false)
        /// 用户是否应该看到显示搜索建议的选择
        static let shouldShowSuggestionsOptIn = Option<Bool>(key: "search.show-suggestions-opt-in", default: true)
        /// 禁用的搜索引擎列表
        static let disabledEngines = Option<[String]?>(key: "search.disabled-engines", default: nil)
        /// 有序搜索引擎列表，如果尚未设置则为nil
        static let orderedEngines = Option<[String]?>(key: "search.ordered-engines", default: nil)
        /// 常规模式下的默认选择搜索引擎
        public static let defaultEngineName = Option<String?>(key: "search.default.name", default: nil)
        /// 私密模式下的默认选择搜索引擎
        static let defaultPrivateEngineName = Option<String?>(key: "search.defaultprivate.name", default: nil)
        /// 是否显示最近搜索
        static let shouldShowRecentSearches = Option<Bool>(key: "search.should-show-recent-searches", default: false)
        /// 是否显示最近搜索的选择
        static let shouldShowRecentSearchesOptIn = Option<Bool>(key: "search.should-show-recent-searches.opt-in", default: true)
        /// 用户输入时是否显示来自浏览器“打开的标签、书签、历史记录”中的建议
        static let showBrowserSuggestions = Option<Bool>(key: "search.show-browser-suggestions", default: true)
        /// Brave搜索网站询问用户是否可以设置为默认浏览器的次数
        static let braveSearchDefaultBrowserPromptCount =
            Option<Int>(key: "search.brave-search-default-website-prompt", default: 0)
        
        static let shouldMutiHelp = Option<Bool>(key: "search.show-muti-help", default: true)
        static let shouldAiHelp = Option<Bool>(key: "search.show-ai-help", default: true)
    }

    enum BraveSearch {
        /// Brave搜索推广后的应用启动日期
        public static let braveSearchPromotionLaunchDate = Option<Date?>(key: "brave-search.promo-launch-date", default: nil)
        /// 用户是否与Brave搜索推广进行了交互
        /// 用户在推广入门中点击'稍后再说'不算作已取消。
        /// 单击“稍后再说”后的下一次会话将显示给用户
        public static let braveSearchPromotionCompletionState = Option<Int>(
            key: "brave-search.promo-completion-state",
            default: BraveSearchPromotionState.undetermined.rawValue)
    }

    enum Privacy {
        static let lockWithPasscode = Option<Bool>(key: "privacy.lock-with-passcode", default: false)
        static let privateBrowsingLock = Option<Bool>(key: "privacy.private-browsing-lock", default: false)
        /// 强制所有私密标签
        public static let privateBrowsingOnly = Option<Bool>(key: "privacy.private-only", default: false)
        /// 私密浏览标签是否可以会话恢复（持久性私密浏览）
        public static let persistentPrivateBrowsing = Option<Bool>(key: "privacy.private-browsing-persistence", default: false)
        /// 阻止所有Cookie和对本地存储的访问
        static let blockAllCookies = Option<Bool>(key: "privacy.block-all-cookies", default: false)
        /// 清除私人数据屏幕的切换状态
        static let clearPrivateDataToggles = Option<[Bool]>(key: "privacy.clear-data-toggles", default: [])
        /// 启用Apple的屏幕时间功能。
        public static let screenTimeEnabled = Option<Bool>(key: "privacy.screentime-toggle", default: false)
    }

    enum NewTabPage {
        /// 是否启用/显示书签图片
        static let backgroundImages = Option<Bool>(key: "newtabpage.background-images", default: false)
        static let iconAddHome = Option<Bool>(key: "newtabpage.icon-add-home", default: false)

        
        static let imagesTopColor = Option<Bool>(key: "newtabpage.background-top-images", default: false)

        static let imagesCenterColor = Option<Bool>(key: "newtabpage.background-center-images", default: false)

        static let imagesBottomColor = Option<Bool>(key: "newtabpage.background-bottom-images", default: false)

        
        /// 是否将赞助图片包含在背景图片轮换中
        static let backgroundSponsoredImages = Option<Bool>(key: "newtabpage.background-sponsored-images", default: true)

        /// 至少显示一次通知后锁定显示后续通知
        static let atleastOneNTPNotificationWasShowed = Option<Bool>(
            key: "newtabpage.one-notificaiton-showed",
            default: false)

        /// 是否显示使用品牌图片的提示
        static let brandedImageShowed = Option<Bool>(
            key: "newtabpage.branded-image-callout-showed",
            default: false)

        /// 当为true时，将显示新标签页页面的通知，指示可以索取广告奖励（如果有奖励可用）。
        /// 此值在每次应用启动时重置，
        /// 目的是在仍然可用的情况下仅在每个应用会话中显示索赔奖励通知一次。
        static let attemptToShowClaimRewardsNotification =
            Option<Bool>(key: "newtabpage.show-grant-notification", default: true)

        /// 是否已初始化预加载的收藏夹。在超级推荐或默认收藏夹的情况下使用自定义收藏夹。
        static let preloadedFavoritiesInitialized =
            Option<Bool>(key: "newtabpage.favorites-initialized", default: false)

        /// 当超级引荐者无法下载并且用户未更改其默认收藏夹时，可能要尝试替换它们
        /// 为一旦可用就由超级引荐者提供的收藏夹。这应该只做一次。
        static let initialFavoritesHaveBeenReplaced =
            Option<Bool>(key: "newtabpage.initial-favorites-replaced", default: false)

        /// 在应用中使用的自定义主题。如果使用默认主题，则为nil。
        static let selectedCustomTheme =
            Option<String?>(key: "newtabpage.selected-custom-theme", default: nil)

        /// 设备上当前安装的主题列表。
        static let installedCustomThemes =
            Option<[String]>(key: "newtabpage.installed-custom-themes", default: [])

        /// 告诉应用程序是否应该在新标签页视图控制器中显示隐私中心
        public static let showNewTabPrivacyHub =
            Option<Bool>(key: "newtabpage.show-newtab-privacyhub", default: true)

        /// 触发隐私中心隐藏操作时第一次会向用户显示警报
        static let hidePrivacyHubAlertShown = Option<Bool>(
            key: "newtabpage.hide-privacyhub-alert",
            default: false)

        /// 通知应用程序是否应在新标签页视图控制器中显示收藏夹
        public static let showNewTabFavourites =
            Option<Bool>(key: "newtabpage.show-newtab-favourites", default: true)

        /// NewTabPageP3AHelperStorage的Codable JSON表示
        public static let sponsoredImageEventCountJSON = Option<String?>(key: "newtabpage.si-p3a.event-count", default: nil)
    }

    enum Debug {
        /// When general blocklists were last time updated on the device.
        static let lastGeneralAdblockUpdate = Option<Date?>(key: "last-general-adblock-update", default: nil)
        /// When regional blocklists were last time updated on the device.
        static let lastRegionalAdblockUpdate = Option<Date?>(key: "last-regional-adblock-update", default: nil)
        /// When cosmetic filters CSS was last time updated on the device.
        static let lastCosmeticFiltersCSSUpdate = Option<Date?>(key: "last-cosmetic-filters-css-update", default: nil)
        /// When cosmetic filters Scriptlets were last time updated on the device.
        static let lastCosmeticFiltersScripletsUpdate = Option<Date?>(key: "last-cosmetic-filters-scriptlets-update", default: nil)
    }

    enum PrivacyReports {
        /// Used to track whether to prompt user to enable app notifications.
        static let shouldShowNotificationPermissionCallout =
            Option<Bool>(key: "privacy-hub.show-notification-permission-callout", default: true)
        /// When disabled, no tracker data will be recorded for the Privacy Reports.
        static let captureShieldsData = Option<Bool>(key: "privacy-hub.capture-shields-data", default: false)
        /// When disabled, no Brave VPN alerts will be recorded for the Privacy Reports.
        static let captureVPNAlerts = Option<Bool>(key: "privacy-hub.capture-vpn-alerts", default: false)
        /// Tracker when to consolidate tracker and vpn data. By default the first consolidation happens 7 days after Privacy Reports build is installed.
        static let nextConsolidationDate =
            Option<Date?>(key: "privacy-hub.next-consolidation-date", default: nil)
        /// Determines whether to show a Privacy Reports onboarding popup on the NTP.
        public static let ntpOnboardingCompleted =
            Option<Bool>(key: "privacy-hub.onboarding-completed", default: true)
    }

    enum WebsiteRedirects {
        static let reddit = Option<Bool>(key: "website-redirect.reddit", default: false)
        static let npr = Option<Bool>(key: "website-redirect.npr", default: false)
    }
}
