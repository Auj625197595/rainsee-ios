/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Growth
import os.log
import Preferences
import Shared
import Storage
import UIKit

private let customSearchEnginesFileName = "customEngines.plist"

// MARK: - SearchEngineError

enum SearchEngineError: Error {
    case duplicate
    case failedToSave
    case invalidQuery
    case missingInformation
    case invalidURL
}

// BRAVE TODO: Move to newer Preferences class(#259)
enum DefaultEngineType: String {
    case standard = "search.default.name"
    case privateMode = "search.defaultprivate.name"

    var option: Preferences.Option<String?> {
        switch self {
        case .standard: return Preferences.Search.defaultEngineName
        case .privateMode: return Preferences.Search.defaultPrivateEngineName
        }
    }
}

/**
 * Manage a set of Open Search engines.
 *
 * The search engines are ordered.  Individual search engines can be enabled and disabled.  The
 * first search engine is distinguished and labeled the "default" search engine; it can never be
 * disabled.  Search suggestions should always be sourced from the default search engine.
 *
 * Two additional bits of information are maintained: whether the user should be shown "opt-in to
 * search suggestions" UI, and whether search suggestions are enabled.
 *
 * Users can set standard tab default search engine and private tab search engine.
 *
 * Consumers will almost always use `defaultEngine` if they want a single search engine, and
 * `quickSearchEngines()` if they want a list of enabled quick search engines (possibly empty,
 * since the default engine is never included in the list of enabled quick search engines, and
 * it is possible to disable every non-default quick search engine).
 *
 * The search engines are backed by a write-through cache into a ProfilePrefs instance.  This class
 * is not thread-safe -- you should only access it on a single thread (usually, the main thread)!
 */
public class SearchEngines {
    fileprivate let fileAccessor: FileAccessor

    private let initialSearchEngines: InitialSearchEngines
    private let locale: Locale

    public init(files: FileAccessor, locale: Locale = .current) {
        self.initialSearchEngines = InitialSearchEngines(locale: locale)
        self.locale = locale
        self.fileAccessor = files
        self.disabledEngineNames = getDisabledEngineNames()
        self.orderedEngines = getOrderedEngines()
        //  self.recordSearchEngineChangedP3A(from: defaultEngine(forType: .standard))
    }

    public func searchEngineSetup() {
        let engine = initialSearchEngines.defaultSearchEngine
        setInitialDefaultEngine(engine.legacyName ?? engine.rawValue)
    }

    /// 如果未指定引擎类型，则此方法返回用于常规浏览的搜索引擎。
    func defaultEngine(forType engineType: DefaultEngineType) -> OpenSearchEngine {
        // 检查引擎类型是否存在
        if let name = engineType.option.value,
           let defaultEngine = orderedEngines.first(where: { $0.engineID == name || $0.shortName == name })
        {
            // 如果找到指定引擎类型，则返回该引擎
            return defaultEngine
        }

        // 如果未指定引擎类型，则使用默认搜索引擎的名称
        let defaultEngineName = initialSearchEngines.defaultSearchEngine.rawValue

        // 查找默认搜索引擎
        let defaultEngine = orderedEngines.first(where: { $0.engineID == defaultEngineName })

        // 如果找到默认搜索引擎，则返回；否则返回第一个搜索引擎
        return defaultEngine ?? orderedEngines[0]
    }

    /// 初始化默认引擎并设置其余搜索引擎的顺序。
    /// 仅在初始化时（应用启动或引导过程中）调用此方法。
    /// 要更新搜索引擎，请使用 `updateDefaultEngine()` 方法。
    func setInitialDefaultEngine(_ engine: String) {
        // 更新引擎
        DefaultEngineType.standard.option.value = engine
        DefaultEngineType.privateMode.option.value = engine

        // 获取先前的引擎
        let priorityEngine = initialSearchEngines.priorityEngine?.rawValue
        // 获取默认引擎
        let defEngine = defaultEngine(forType: .standard)

        // 排序引擎，将优先引擎置于第一位置
        var newlyOrderedEngines =
            orderedEngines
                .filter { engine in engine.shortName != defEngine.shortName }
                .sorted { e1, e2 in e1.shortName < e2.shortName }
                .sorted { e, _ in e.engineID == priorityEngine }

        // 在第一个位置插入默认引擎
        newlyOrderedEngines.insert(defEngine, at: 0)
        // 更新搜索引擎顺序
        orderedEngines = newlyOrderedEngines
    }

    /// 更新所选的默认引擎，其余搜索引擎的顺序保持不变。
    func updateDefaultEngine(_ engine: String, forType type: DefaultEngineType) {
        // 获取原始引擎
        let originalEngine = defaultEngine(forType: type)
        // 更新指定类型的引擎
        type.option.value = engine

        // 默认引擎始终启用
        enableEngine(defaultEngine(forType: type))

        // 仅在重新排序引擎时查看标准浏览的默认搜索引擎
        if type == .standard {
            // 确保不更改私人模式的默认引擎，因为其依赖于未设置时的顺序
            if Preferences.Search.defaultPrivateEngineName.value == nil, let firstEngine = orderedEngines.first {
                // 因此，将私人模式的默认引擎设置为在更改标准引擎之前的默认引擎
                updateDefaultEngine(firstEngine.shortName, forType: .privateMode)
            }
            // 默认引擎始终位于列表的第一位
            var newlyOrderedEngines =
                orderedEngines.filter { engine in engine.shortName != defaultEngine(forType: type).shortName }
            newlyOrderedEngines.insert(defaultEngine(forType: type), at: 0)
            // 更新搜索引擎顺序
            orderedEngines = newlyOrderedEngines
        }

        // 如果是标准类型的引擎更新，则记录搜索引擎P3A事件并记录引擎更改的P3A事件
    }

    func isEngineDefault(_ engine: OpenSearchEngine, type: DefaultEngineType) -> Bool {
        return defaultEngine(forType: type).shortName == engine.shortName
    }

    // The keys of this dictionary are used as a set.
    fileprivate var disabledEngineNames: [String: Bool]! {
        didSet {
            Preferences.Search.disabledEngines.value = Array(disabledEngineNames.keys)
        }
    }

    var orderedEngines: [OpenSearchEngine]! {
        didSet {
            Preferences.Search.orderedEngines.value = orderedEngines.map { $0.shortName }
        }
    }

    var quickSearchEngines: [OpenSearchEngine]! {
        return orderedEngines.filter { engine in self.isEngineEnabled(engine) }
    }

    var shouldShowSearchSuggestionsOptIn: Bool {
        get { return Preferences.Search.shouldShowSuggestionsOptIn.value }
        set { Preferences.Search.shouldShowSuggestionsOptIn.value = newValue }
    }

    var shouldShowSearchSuggestions: Bool {
        get { return Preferences.Search.showSuggestions.value }
        set { Preferences.Search.showSuggestions.value = newValue }
    }

    var shouldShowRecentSearchesOptIn: Bool {
        get { return Preferences.Search.shouldShowRecentSearchesOptIn.value }
        set { Preferences.Search.shouldShowRecentSearchesOptIn.value = newValue }
    }

    var shouldShowRecentSearches: Bool {
        get { return Preferences.Search.shouldShowRecentSearches.value }
        set { Preferences.Search.shouldShowRecentSearches.value = newValue }
    }

    var shouldShowBrowserSuggestions: Bool {
        get { return Preferences.Search.showBrowserSuggestions.value }
        set { Preferences.Search.showBrowserSuggestions.value = newValue }
    }

    var shouldMutiHelp: Bool {
        get { return Preferences.Search.shouldMutiHelp.value }
        set { Preferences.Search.shouldMutiHelp.value = newValue }
    }

    var shouldAiHelp: Bool {
        get { return Preferences.Search.shouldAiHelp.value }
        set { Preferences.Search.shouldAiHelp.value = newValue } 
    }

    func isEngineEnabled(_ engine: OpenSearchEngine) -> Bool {
        return disabledEngineNames.index(forKey: engine.shortName) == nil
    }

    func enableEngine(_ engine: OpenSearchEngine) {
        disabledEngineNames.removeValue(forKey: engine.shortName)
    }

    func disableEngine(_ engine: OpenSearchEngine, type: DefaultEngineType) {
        if isEngineDefault(engine, type: type) {
            // Can't disable default engine.
            return
        }
        disabledEngineNames[engine.shortName] = true
    }

    func deleteCustomEngine(_ engine: OpenSearchEngine) throws {
        // We can't delete a preinstalled engine
        if !engine.isCustomEngine {
            return
        }

        customEngines.remove(at: customEngines.firstIndex(of: engine)!)
        do {
            try saveCustomEngines()
        } catch {
            throw SearchEngineError.failedToSave
        }

        orderedEngines = getOrderedEngines()
    }

    /// Adds an engine to the front of the search engines list.
    func addSearchEngine(_ engine: OpenSearchEngine) throws {
        guard orderedEngines.contains(where: { $0.searchTemplate != engine.searchTemplate }) else {
            throw SearchEngineError.duplicate
        }

        customEngines.append(engine)
        orderedEngines.insert(engine, at: 1)

        do {
            try saveCustomEngines()
        } catch {
            throw SearchEngineError.failedToSave
        }
    }

    func queryForSearchURL(_ url: URL?, forType engineType: DefaultEngineType) -> String? {
        return defaultEngine(forType: engineType).queryForSearchURL(url)
    }

    fileprivate func getDisabledEngineNames() -> [String: Bool] {
        if let disabledEngineNames = Preferences.Search.disabledEngines.value {
            var disabledEngineDict = [String: Bool]()
            for engineName in disabledEngineNames {
                disabledEngineDict[engineName] = true
            }
            return disabledEngineDict
        } else {
            return [String: Bool]()
        }
    }

    fileprivate func customEngineFilePath() -> String {
        let profilePath = try! fileAccessor.getAndEnsureDirectory() as NSString // swiftlint:disable:this force_try
        return profilePath.appendingPathComponent(customSearchEnginesFileName)
    }

    fileprivate lazy var customEngines: [OpenSearchEngine] = {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: customEngineFilePath()))
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = true
            return unarchiver.decodeArrayOfObjects(ofClass: OpenSearchEngine.self, forKey: NSKeyedArchiveRootObjectKey) ?? []
        } catch {
            Logger.module.error("Failed to load custom search engines: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }()

    fileprivate func saveCustomEngines() throws {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: customEngines, requiringSecureCoding: true)
            try data.write(to: URL(fileURLWithPath: customEngineFilePath()))
        } catch {
            Logger.module.error("Failed to save custom engines: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 返回所有可能的语言标识符，按从最具体到最不具体的顺序排列。
    /// 例如，zh-Hans-CN 将返回 [zh-Hans-CN, zh-CN, zh]。
    class func possibilitiesForLanguageIdentifier(_ languageIdentifier: String) -> [String] {
        var possibilities: [String] = []
        let components = languageIdentifier.components(separatedBy: "-")
        possibilities.append(languageIdentifier)

        // 如果标识符包含三个组件，将最具体的和最不具体的组件合并
        if components.count == 3, let first = components.first, let last = components.last {
            possibilities.append("\(first)-\(last)")
        }

        // 如果标识符至少包含两个组件，将最具体的组件添加
        if components.count >= 2, let first = components.first {
            possibilities.append("\(first)")
        }

        return possibilities
    }

    /// 获取所有已捆绑（非自定义）的搜索引擎，首先是默认搜索引擎，
    /// 但其他引擎的顺序没有特定要求。
    class func getUnorderedBundledEngines(
        for selectedEngines: [String] = [],
        isOnboarding: Bool,
        locale: Locale
    ) -> [OpenSearchEngine] {
        // 创建搜索引擎解析器
        let parser = OpenSearchParser(pluginMode: true)

        // 获取插件目录
        guard let pluginDirectory = Bundle.module.resourceURL?.appendingPathComponent("SearchPlugins") else {
            assertionFailure("未找到搜索插件。请检查捆绑包。")
            return []
        }

        // 获取初始搜索引擎
        let se = InitialSearchEngines(locale: locale)
        // 根据是否在引导过程中，选择相应的引擎列表
        let engines = isOnboarding ? se.onboardingEngines : se.engines
        // 获取引擎标识符和引擎参考
        let engineIdentifiers: [(id: String, reference: String?)] = engines.map { (id: ($0.customId ?? $0.id.rawValue).lowercased(), reference: $0.reference) }
        assert(!engineIdentifiers.isEmpty, "没有搜索引擎")

        // 根据引擎标识符构建引擎路径，并过滤掉不存在的引擎文件
        return engineIdentifiers.map { (name: $0.id, path: pluginDirectory.appendingPathComponent("\($0.id).xml").path, reference: $0.reference) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .compactMap { parser.parse($0.path, engineID: $0.name, referenceURL: $0.reference) }
    }

    /// 获取所有已知的搜索引擎，可能按用户指定的顺序排列。
    fileprivate func getOrderedEngines() -> [OpenSearchEngine] {
        // 获取用户选择的搜索引擎名称
        let selectedSearchEngines = [Preferences.Search.defaultEngineName, Preferences.Search.defaultPrivateEngineName].compactMap { $0.value }

        // 获取未排序的引擎列表，包括捆绑的引擎和自定义引擎
        let unorderedEngines =
            SearchEngines.getUnorderedBundledEngines(
                for: selectedSearchEngines,
                isOnboarding: false,
                locale: locale
            ) + customEngines

        // 如果尝试更改默认引擎可能无效。
        guard let orderedEngineNames = Preferences.Search.orderedEngines.value else {
            // 我们还没有保存引擎顺序，因此返回从磁盘获取的任何顺序。
            return unorderedEngines
        }

        // 我们有一个已保存的引擎顺序，因此尝试使用该顺序。
        // 我们可能找到了未在有序列表中保存的引擎
        // （如果用户更改了区域设置或添加了新引擎）；这些引擎
        // 将附加到列表的末尾。
        return unorderedEngines.sorted { engine1, engine2 in
            let index1 = orderedEngineNames.firstIndex(of: engine1.shortName)
            let index2 = orderedEngineNames.firstIndex(of: engine2.shortName)

            if index1 == nil && index2 == nil {
                return engine1.shortName < engine2.shortName
            }

            // nil < N 对于所有非 nil 的 N 值。
            if index1 == nil || index2 == nil {
                return index1 ?? -1 > index2 ?? -1
            }

            return index1! < index2!
        }
    }
}
