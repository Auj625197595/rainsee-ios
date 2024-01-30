// 版权 2020 年 Brave 作者保留所有权利。
// 此源代码表单受 Mozilla Public License，版本 2.0 的条款约束。
// 如果没有随此文件一起分发 MPL 的副本，
// 您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation

struct SearchServiceEngine: Codable {
    let name: String
    let url: String
    let urlpc: String?
    let icon: String
    let intro: String?
}

/// 这是用户在首次启动时可用的搜索引擎列表。
/// 要查找用户控制的搜索引擎类，请查找 `SearchEngines.swift`
class InitialSearchEngines {
    /// 用户可用的搜索引擎类型。
    enum SearchEngineID: String, CaseIterable {
        case baidu, sogou, shenma, toutiao, google, bingchina, braveSearch, bing, duckduckgo, yandex, qwant, startpage, ecosia, naver, daum

        /// 默认搜索引擎的 Open Search 引用
        var openSearchReference: String {
            switch self {
            case .baidu: return "baidu.com"
            case .sogou: return "sogou.com"
            case .shenma: return "sm.cn"
            case .toutiao: return "toutiao.com"
            case .bingchina: return "cn.bing.com"

            case .google: return "google.com"
            case .braveSearch: return "search.brave"
            case .bing: return "bing.com"
            case .duckduckgo: return "duckduckgo.com/opensearch"
            case .yandex: return "yandex.com/search"
            case .qwant: return "qwant.com/opensearch"
            case .startpage: return "startpage.com/en/opensearch"
            case .ecosia: return "ecosia.org/opensearch"
            case .naver: return "naver.com"
            case .daum: return "search.daum.net/OpenSearch"
            }
        }

        /// 由于传统原因，搜索引擎名称可能需要使用旧值。
        /// 这是因为我们使用 'display name' 作为首选项键。
        var legacyName: String? {
            switch self {
            case .braveSearch: return "Brave Search beta"
            default: return nil
            }
        }

        func excludedFromOnboarding(for locale: Locale) -> Bool {
            switch self {
            case .braveSearch: return true
            // 通常我们希望所有引擎都可以选择，
            // 因此在这里使用默认子句而不是逐个选择引擎
            default: return false
            }
        }
    }

    struct SearchEngine: Equatable, CustomStringConvertible {
        /// 引擎的 ID，如果未提供 `customId`，还将用于查找给定搜索引擎的 xml 文件。
        let id: SearchEngineID
        /// 一些搜索引擎具有区域变体，对应于“SearchPlugins”文件夹中的不同 xml 文件。
        /// 如果提供此自定义 ID，则在访问 Open Search xml 文件时将使用它，而不是 `regular` ID。
        var customId: String?
        /// 用于确定搜索引擎是否已添加
        /// 特别是为了防止使用 Open Search Auto-Add 添加默认搜索引擎
        var reference: String? {
            return id.openSearchReference
        }

        // 只有 `id` 在比较搜索引擎时有关紧要。
        // 这是为了防止添加超过 2 个相同类型的引擎。
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
        }

        var description: String {
            var desc = id.rawValue
            if let customId = customId {
                desc += " with '\(customId)' custom id"
            }
            return desc
        }
    }

    private let locale: Locale
    /// 为给定语言环境列出的可用引擎列表。此列表按优先级排序，顶部是默认引擎和默认引擎。
    var engines: [SearchEngine]

    /// 在入门过程中可用的引擎列表。
    var onboardingEngines: [SearchEngine] {
        engines.filter { !$0.id.excludedFromOnboarding(for: locale) }
    }

    static let braveSearchDefaultRegions = ["US", "CA", "GB", "FR", "DE", "AD", "AT", "ES", "MX", "BR", "AR", "IN"]
    static let yandexDefaultRegions = ["AM", "AZ", "BY", "KG", "KZ", "MD", "RU", "TJ", "TM", "TZ"]
    static let ecosiaEnabledRegions = [
        "AT", "AU", "BE", "CA", "DK", "ES", "FI", "GR", "HU", "IT",
        "LU", "NO", "PT", "US", "GB", "FR", "DE", "NL", "CH", "SE", "IE",
    ]
    static let naverDefaultRegions = ["KR"]
    static let daumEnabledRegions = ["KR"]

    /// 为给定语言环境设置默认搜索引擎。
    /// 如果引擎不存在于 `engines` 列表中，则将其添加到其中。
    private(set) var defaultSearchEngine: SearchEngineID {
        didSet {
            if !engines.contains(.init(id: defaultSearchEngine)) {
                // 作为后备，我们添加缺失的引擎
                engines.append(.init(id: defaultSearchEngine))
            }
        }
    }

    /// 为给定语言环境设置默认优先级引擎。
    /// 优先引擎显示在搜索引擎入门以及搜索引擎设置的顶部，除非用户更改搜索引擎顺序。
    /// 如果引擎不存在于 `engines` 列表中，则将其添加到其中。
    private(set) var priorityEngine: SearchEngineID? {
        didSet {
            guard let engine = priorityEngine else { return }
            if !engines.contains(.init(id: engine)) {
                // 作为后备，我们添加缺失的引擎
                engines.append(.init(id: engine))
            }
        }
    }

    init(locale: Locale = .current) {
//      let jsonString = """
//      [
//          { "name": "百度", "url": "https://m.baidu.com/s?from=1015011i&word=%s", "urlpc": "https://www.baidu.com/s?wd=%s&from=1015011i", "icon": "http://down.csyunkj.com/engine_baidu.png", "intro": "老牌搜索" },
//          { "name": "雨见搜索", "url": "yjsearch://go?q=%s", "icon": "http://down.csyunkj.com/icon_app.png", "intro": "聚合搜索引擎" },
//          { "name": "搜狗", "url": "https://wap.sogou.com/web/sl?bid=sogou-mobb-dc0fc2d90d6102ba&keyword=%s", "icon": "https://file.yujianpay.com/sougou3.png", "intro": "方便快捷" },
//          { "name": "谷歌", "url": "https://www.google.com/search?q=%s", "icon": "http://down.csyunkj.com/engine_google.png" },
//          { "name": "必应", "url": "http://cn.bing.com/search?q=%s", "icon": "http://down.csyunkj.com/engine_bing.png" }
//      ]
//      """
//      var searchEngines: [SearchServiceEngine] = [
//        SearchServiceEngine(name: "百度", url: "https://m.baidu.com/s?from=1015011i&word=%s", urlpc: "https://www.baidu.com/s?wd=%s&from=1015011i", icon: "http://down.csyunkj.com/engine_baidu.png", intro: "老牌搜索"),
//        SearchServiceEngine(name: "搜狗", url: "https://wap.sogou.com/web/sl?bid=sogou-mobb-dc0fc2d90d6102ba&keyword=%s", urlpc: "", icon: "https://file.yujianpay.com/sougou3.png", intro: "方便快捷"),
//        SearchServiceEngine(name: "谷歌", url: "https://www.google.com/search?q=%s", urlpc: "", icon: "http://down.csyunkj.com/engine_google.png", intro: ""),
//        SearchServiceEngine(name: "必应", url: "http://cn.bing.com/search?q=%s", urlpc: "", icon: "http://down.csyunkj.com/engine_bing.png", intro: "")
//      ]
//
//      if let jsonData = jsonString.data(using: .utf8) {
//          do {
//              searchEngines = try JSONDecoder().decode([SearchServiceEngine].self, from: jsonData)
//
//          } catch {
//
//          }
//      } else {
//          print("Invalid JSON string")
//      }
//
//      print(searchEngines)

        //   SearchEngine()

        self.locale = locale

        // 默认的顺序和可用搜索引擎，适用于所有语言环境
        engines = [
            .init(id: .google),
        ]
        //  engines.insert(SearchEngine())
        defaultSearchEngine = .google

        // 可以在这里修改具有特定语言环境和区域的覆盖
        // 对于冲突的规则，优先级如下：
        regionOverrides()
        // 1. 优先规则，放入任何您想要的规则。
        priorityOverrides()

        // 初始引擎应始终按优先级和默认搜索引擎在顶部排序，
        // 剩余的搜索引擎按添加的顺序保留。
        sortEngines()
    }

    private func regionOverrides() {
        guard let region = locale.regionCode else { return }

        if region == "CN" {
            replaceOrInsert(engineId: .baidu, customId: nil)
            defaultSearchEngine = .baidu

            replaceOrInsert(engineId: .sogou, customId: nil)
            replaceOrInsert(engineId: .bingchina, customId: nil)
            // replaceOrInsert(engineId: .toutiao, customId: nil)
            // replaceOrInsert(engineId: .shenma, customId: nil)
        } else {
            replaceOrInsert(engineId: .bing, customId: nil)

            replaceOrInsert(engineId: .braveSearch, customId: nil)
            replaceOrInsert(engineId: .duckduckgo, customId: nil)
            replaceOrInsert(engineId: .qwant, customId: nil)
            replaceOrInsert(engineId: .startpage, customId: nil)

            if Self.yandexDefaultRegions.contains(region) {
                defaultSearchEngine = .yandex
            }

            if Self.ecosiaEnabledRegions.contains(region) {
                replaceOrInsert(engineId: .ecosia, customId: nil)
            }

            if Self.braveSearchDefaultRegions.contains(region) {
                defaultSearchEngine = .braveSearch
            }

            if Self.naverDefaultRegions.contains(region) {
                defaultSearchEngine = .naver
            }

            if Self.daumEnabledRegions.contains(region) {
                replaceOrInsert(engineId: .daum, customId: nil)
            }
        }
    }

    // MARK: - 区域覆盖

    private func priorityOverrides() {
        // 目前没有优先级引擎
    }

    // MARK: - 辅助函数

    private func sortEngines() {
        engines =
            engines
                .sorted { e, _ in e.id == defaultSearchEngine }
                .sorted { e, _ in e.id == priorityEngine }
    }

    private func replaceOrInsert(engineId: SearchEngineID, customId: String?) {
        guard let engineIndex = engines.firstIndex(where: { $0.id == engineId }) else {
            engines.append(.init(id: engineId, customId: customId))
            return
        }

        engines[engineIndex] = .init(id: engineId, customId: customId)
    }
}
