/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared
import os.log

// MARK: - SearchEnginePickerDelegate

protocol SearchEnginePickerDelegate: AnyObject {
  func searchEnginePicker(
    _ searchEnginePicker: SearchEnginePicker?,
    didSelectSearchEngine engine: OpenSearchEngine?, forType: DefaultEngineType?)
}

// MARK: - SearchSettingsTableViewController

class SearchSettingsTableViewController: UITableViewController {

  // MARK: UX

  struct UX {
    static let iconSize = CGSize(
      width: OpenSearchEngine.preferredIconSize,
      height: OpenSearchEngine.preferredIconSize)

    static let headerHeight: CGFloat = 44
  }

  // MARK: Constants

  struct Constants {
    static let addCustomEngineRowIdentifier = "addCustomEngineRowIdentifier"
    static let searchEngineRowIdentifier = "searchEngineRowIdentifier"
    static let showSearchSuggestionsRowIdentifier = "showSearchSuggestionsRowIdentifier"
    static let showRecentSearchesRowIdentifier = "showRecentSearchRowIdentifier"
    static let showBrowserSuggestionsRowIdentifier = "showBrowserSuggestionsRowIdentifier"
    static let quickSearchEngineRowIdentifier = "quickSearchEngineRowIdentifier"
    static let customSearchEngineRowIdentifier = "customSearchEngineRowIdentifier"
      
      static let shouldMutiHelp = "shouldMutiHelp"

      static let shouldAiHelp = "shouldAiHelp"

  }

  // MARK: Section

  enum Section: Int, CaseIterable {
    case current
    case customSearch
    case plug
  }

  // MARK: CurrentEngineType

  enum CurrentEngineType: Int, CaseIterable {
    case standard
    case `private`
    case quick
    case searchSuggestions
    case recentSearches
    case browserSuggestions
  }
    
    enum PlugEngineType: Int, CaseIterable {
      case muti
      case ai
    }

  private var searchEngines: SearchEngines
  private let profile: Profile
  private var showDeletion = false
  private var privateBrowsingManager: PrivateBrowsingManager

  private func searchPickerEngines(type: DefaultEngineType) -> [OpenSearchEngine] {
    var orderedEngines = searchEngines.orderedEngines
      .sorted { $0.shortName < $1.shortName }
      .sorted { engine, _ in engine.shortName == OpenSearchEngine.EngineNames.brave }

    if let priorityEngine = InitialSearchEngines().priorityEngine?.rawValue {
      orderedEngines =
        orderedEngines
        .sorted { engine, _ in
          engine.engineID == priorityEngine
        }
    }

    return orderedEngines
  }

  private var customSearchEngines: [OpenSearchEngine] {
    searchEngines.orderedEngines.filter { $0.isCustomEngine }
  }

  // MARK: Lifecycle

  init(profile: Profile, privateBrowsingManager: PrivateBrowsingManager) {
    self.profile = profile
    self.privateBrowsingManager = privateBrowsingManager
    self.searchEngines = profile.searchEngines
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    navigationItem.title = Strings.searchEngines

    tableView.do {
      $0.allowsSelectionDuringEditing = true
      $0.registerHeaderFooter(SettingsTableSectionHeaderFooterView.self)
      $0.register(UITableViewCell.self, forCellReuseIdentifier: Constants.addCustomEngineRowIdentifier)
      $0.register(UITableViewCell.self, forCellReuseIdentifier: Constants.searchEngineRowIdentifier)
      $0.register(UITableViewCell.self, forCellReuseIdentifier: Constants.showSearchSuggestionsRowIdentifier)
      $0.register(UITableViewCell.self, forCellReuseIdentifier: Constants.showRecentSearchesRowIdentifier)
      $0.register(UITableViewCell.self, forCellReuseIdentifier: Constants.showBrowserSuggestionsRowIdentifier)
        $0.register(UITableViewCell.self, forCellReuseIdentifier: Constants.shouldMutiHelp)

        $0.register(UITableViewCell.self, forCellReuseIdentifier: Constants.shouldAiHelp)

      $0.register(UITableViewCell.self, forCellReuseIdentifier: Constants.quickSearchEngineRowIdentifier)
      $0.register(UITableViewCell.self, forCellReuseIdentifier: Constants.customSearchEngineRowIdentifier)
      $0.sectionHeaderTopPadding = 5
    }

    // Insert Done button if being presented outside of the Settings Nav stack
    if navigationController?.viewControllers.first === self {
      navigationItem.leftBarButtonItem =
        UIBarButtonItem(title: Strings.settingsSearchDoneButton, style: .done, target: self, action: #selector(dismissAnimated))
    }

    let footer = SettingsTableSectionHeaderFooterView(frame: CGRect(width: tableView.bounds.width, height: UX.headerHeight))
    tableView.tableFooterView = footer
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    updateTableEditModeVisibility()
    tableView.reloadData()
  }

  // MARK: Internal

  private func configureSearchEnginePicker(_ type: DefaultEngineType) -> SearchEnginePicker {
    return SearchEnginePicker(type: type, showCancel: false).then {
      // Order alphabetically, so that picker is always consistently ordered.
      // Every engine is a valid choice for the default engine, even the current default engine.
      $0.engines = searchPickerEngines(type: type)
      $0.delegate = self
      $0.selectedSearchEngineName = searchEngines.defaultEngine(forType: type).shortName
    }
  }

  private func configureSearchEngineCell(type: DefaultEngineType, engineName: String?) -> UITableViewCell {
    guard let searchEngineName = engineName else { return UITableViewCell() }

    var text: String

    switch type {
    case .standard:
      text = Strings.standardTabSearch
    case .privateMode:
      text = Strings.privateTabSearch
    }

    let cell = UITableViewCell(style: .value1, reuseIdentifier: Constants.searchEngineRowIdentifier).then {
      $0.accessoryType = .disclosureIndicator
      $0.editingAccessoryType = .disclosureIndicator
      $0.accessibilityLabel = text
      $0.textLabel?.text = text
      $0.accessibilityValue = searchEngineName
      $0.detailTextLabel?.text = searchEngineName
    }

    return cell
  }
  
  private func updateTableEditModeVisibility() {
    tableView.endEditing(true)
    
    if customSearchEngines.isEmpty {
      navigationItem.rightBarButtonItem = nil
    } else {
      navigationItem.rightBarButtonItem = editButtonItem
    }
  }

  // MARK: TableViewDataSource - TableViewDelegate

  override func numberOfSections(in tableView: UITableView) -> Int {
    return Section.allCases.count
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    if section == Section.current.rawValue {
      return CurrentEngineType.allCases.count
    } else if section == Section.plug.rawValue{
        return PlugEngineType.allCases.count
    } else {
      // Adding an extra row for Add Search Engine Entry
      return customSearchEngines.count + 1
    }
  }

  override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
    return UX.headerHeight
  }

    // 在表视图中配置每个单元格
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell?
        var engine: OpenSearchEngine?

        // 如果单元格位于“当前搜索引擎”部分
        if indexPath.section == Section.current.rawValue {
            // 根据不同的搜索引擎类型配置单元格
            switch indexPath.item {
            case CurrentEngineType.standard.rawValue:
                engine = searchEngines.defaultEngine(forType: .standard)
                cell = configureSearchEngineCell(type: .standard, engineName: engine?.displayName)
            case CurrentEngineType.private.rawValue:
                engine = searchEngines.defaultEngine(forType: .privateMode)
                cell = configureSearchEngineCell(type: .privateMode, engineName: engine?.displayName)
            case CurrentEngineType.quick.rawValue:
                // 配置快速搜索引擎的单元格
                cell = tableView.dequeueReusableCell(withIdentifier: Constants.quickSearchEngineRowIdentifier, for: indexPath).then {
                    $0.textLabel?.text = Strings.quickSearchEngines
                    $0.accessoryType = .disclosureIndicator
                    $0.editingAccessoryType = .disclosureIndicator
                }
            case CurrentEngineType.searchSuggestions.rawValue:
                // 配置显示搜索建议设置的开关单元格
                let toggle = UISwitch().then {
                    $0.addTarget(self, action: #selector(didToggleSearchSuggestions), for: .valueChanged)
                    $0.isOn = searchEngines.shouldShowSearchSuggestions
                }

                cell = tableView.dequeueReusableCell(withIdentifier: Constants.showSearchSuggestionsRowIdentifier, for: indexPath).then {
                    $0.textLabel?.text = Strings.searchSettingSuggestionCellTitle
                    $0.accessoryView = toggle
                    $0.selectionStyle = .none
                }
            case CurrentEngineType.recentSearches.rawValue:
                // 配置显示最近搜索设置的开关单元格
                let toggle = UISwitch().then {
                    $0.addTarget(self, action: #selector(didToggleRecentSearches), for: .valueChanged)
                    $0.isOn = searchEngines.shouldShowRecentSearches
                }

                cell = tableView.dequeueReusableCell(withIdentifier: Constants.showRecentSearchesRowIdentifier, for: indexPath).then {
                    $0.textLabel?.text = Strings.searchSettingRecentSearchesCellTitle
                    $0.accessoryView = toggle
                    $0.selectionStyle = .none
                }
            case CurrentEngineType.browserSuggestions.rawValue:
                // 配置显示浏览器建议设置的开关单元格
                let toggle = UISwitch().then {
                    $0.addTarget(self, action: #selector(didToggleBrowserSuggestions), for: .valueChanged)
                    $0.isOn = searchEngines.shouldShowBrowserSuggestions
                }

                cell = UITableViewCell(style: .subtitle, reuseIdentifier: Constants.showBrowserSuggestionsRowIdentifier).then {
                    $0.textLabel?.text = Strings.searchSettingBrowserSuggestionCellTitle
                    $0.detailTextLabel?.numberOfLines = 0
                    $0.detailTextLabel?.textColor = .secondaryBraveLabel
                    $0.detailTextLabel?.text = Strings.searchSettingBrowserSuggestionCellDescription
                    $0.accessoryView = toggle
                    $0.selectionStyle = .none
                }
            default:
                // 不应该发生的情况
                break
            }
        } else if indexPath.section == Section.plug.rawValue {
            if indexPath.item == PlugEngineType.muti.rawValue {
                // 配置显示浏览器建议设置的开关单元格
                let toggle = UISwitch().then {
                    $0.addTarget(self, action: #selector(didToggleMuti), for: .valueChanged)
                    $0.isOn = searchEngines.shouldMutiHelp
                }

                cell = UITableViewCell(style: .subtitle, reuseIdentifier: Constants.shouldMutiHelp).then {
                    $0.textLabel?.text = Strings.aggregatedSearchPanelTitle
                    $0.detailTextLabel?.numberOfLines = 0
                    $0.detailTextLabel?.textColor = .secondaryBraveLabel
                    $0.detailTextLabel?.text = Strings.aggregatedSearchPanelDetail
                    $0.accessoryView = toggle
                    $0.selectionStyle = .none
                }
            } else {
                // 配置显示浏览器建议设置的开关单元格
                let toggle = UISwitch().then {
                    $0.addTarget(self, action: #selector(didToggleAi), for: .valueChanged)
                    $0.isOn = searchEngines.shouldAiHelp
                }

                cell = UITableViewCell(style: .subtitle, reuseIdentifier: Constants.shouldAiHelp).then {
                    $0.textLabel?.text = Strings.qATitle
                    $0.detailTextLabel?.numberOfLines = 0
                    $0.detailTextLabel?.textColor = .secondaryBraveLabel
                    $0.detailTextLabel?.text = Strings.qADetail
                    $0.accessoryView = toggle
                    $0.selectionStyle = .none
                }
            }
        } else {
            // 添加自定义搜索引擎
            if indexPath.item == customSearchEngines.count {
                // 配置添加自定义搜索引擎的单元格
                cell = tableView.dequeueReusableCell(withIdentifier: Constants.addCustomEngineRowIdentifier, for: indexPath).then {
                    $0.textLabel?.text = Strings.searchSettingAddCustomEngineCellTitle
                    $0.accessoryType = .disclosureIndicator
                    $0.editingAccessoryType = .disclosureIndicator
                }
            } else {
                // 配置自定义搜索引擎的单元格
                engine = customSearchEngines[indexPath.item]

                cell = tableView.dequeueReusableCell(withIdentifier: Constants.customSearchEngineRowIdentifier, for: indexPath).then {
                    $0.textLabel?.text = engine?.displayName
                    $0.textLabel?.adjustsFontSizeToFitWidth = true
                    $0.textLabel?.minimumScaleFactor = 0.5
                    $0.imageView?.image = engine?.image.createScaled(UX.iconSize)
                    $0.imageView?.layer.cornerRadius = 4
                    $0.imageView?.layer.cornerCurve = .continuous
                    $0.imageView?.layer.masksToBounds = true
                    $0.selectionStyle = .none
                }
            }
        }

        // 确保单元格不为空，否则返回一个空的 UITableViewCell
        guard let tableViewCell = cell else { return UITableViewCell() }
        tableViewCell.separatorInset = .zero

        return tableViewCell
    }


  override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
    let headerView = tableView.dequeueReusableHeaderFooter() as SettingsTableSectionHeaderFooterView
      var sectionTitle: String = ""
      if section == Section.current.rawValue {
          sectionTitle = Strings.currentlyUsedSearchEngines
      } else if section == Section.plug.rawValue {
          sectionTitle = Strings.plugEngine
      } else {
          
          sectionTitle = Strings.customSearchEngines
     
      }

    headerView.titleLabel.text = sectionTitle
    return headerView
  }

    // 当用户将要选择表视图中的某一行时调用此方法
    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        // 如果选中的行位于“当前搜索引擎”部分，并且是标准搜索引擎类型
        if indexPath.section == Section.current.rawValue && indexPath.item == CurrentEngineType.standard.rawValue {
            // 推送到配置标准搜索引擎选择器的视图控制器
            navigationController?.pushViewController(configureSearchEnginePicker(.standard), animated: true)
        }
        // 如果选中的行位于“当前搜索引擎”部分，并且是私密搜索引擎类型
        else if indexPath.section == Section.current.rawValue && indexPath.item == CurrentEngineType.private.rawValue {
            // 推送到配置私密搜索引擎选择器的视图控制器
            navigationController?.pushViewController(configureSearchEnginePicker(.privateMode), animated: true)
        }
        // 如果选中的行位于“当前搜索引擎”部分，并且是快速搜索引擎类型
        else if indexPath.section == Section.current.rawValue && indexPath.item == CurrentEngineType.quick.rawValue {
            // 创建快速搜索引擎视图控制器，并推送到导航控制器
            let quickSearchEnginesViewController = SearchQuickEnginesViewController(profile: profile, isPrivateBrowsing: privateBrowsingManager.isPrivateBrowsing)
            navigationController?.pushViewController(quickSearchEnginesViewController, animated: true)
        }
        // 如果选中的行位于“自定义搜索引擎”部分，并且是自定义搜索引擎数组的最后一项
        else if indexPath.section == Section.customSearch.rawValue && indexPath.item == customSearchEngines.count {
            // 创建自定义搜索引擎视图控制器，并推送到导航控制器
            let customEngineViewController = SearchCustomEngineViewController(profile: profile, privateBrowsingManager: privateBrowsingManager)
            navigationController?.pushViewController(customEngineViewController, animated: true)
        }

        // 返回 nil，表示不允许选择行
        return nil
    }


  // Determine whether to show delete button in edit mode
  override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
    guard indexPath.section == Section.customSearch.rawValue, indexPath.row != customSearchEngines.count else {
      return .none
    }

    return .delete
  }

  // Determine whether to indent while in edit mode for deletion
  override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
    return indexPath.section == Section.customSearch.rawValue && indexPath.row != customSearchEngines.count
  }

  override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
    if editingStyle == .delete {
      guard let engine = customSearchEngines[safe: indexPath.row] else { return }
      
      func deleteCustomEngine() {
        do {
          try searchEngines.deleteCustomEngine(engine)
          tableView.deleteRows(at: [indexPath], with: .right)
          tableView.reloadData()
          updateTableEditModeVisibility()
        } catch {
          Logger.module.error("Search Engine Error while deleting")
        }
      }

      if engine == searchEngines.defaultEngine(forType: .standard) {
        let alert = UIAlertController(
          title: String(format: Strings.CustomSearchEngine.deleteEngineAlertTitle, engine.displayName),
          message: Strings.CustomSearchEngine.deleteEngineAlertDescription,
          preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: Strings.cancelButtonTitle, style: .cancel))
        
        alert.addAction(UIAlertAction(title: Strings.delete, style: .destructive) { [weak self] _ in
          guard let self = self else { return }
          
          self.searchEngines.updateDefaultEngine(
            self.searchEngines.defaultEngine(forType: .privateMode).shortName,
            forType: .standard)
          
          deleteCustomEngine()
        })

        UIImpactFeedbackGenerator(style: .medium).bzzt()
        present(alert, animated: true, completion: nil)
      } else {
        deleteCustomEngine()
      }
    }
  }

  override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
    return indexPath.section == Section.customSearch.rawValue
  }
}

// MARK: - Actions

extension SearchSettingsTableViewController {

  @objc func didToggleSearchSuggestions(_ toggle: UISwitch) {
    // Setting the value in settings dismisses any opt-in.
    searchEngines.shouldShowSearchSuggestions = toggle.isOn
    searchEngines.shouldShowSearchSuggestionsOptIn = false
  }

  @objc func didToggleRecentSearches(_ toggle: UISwitch) {
    // Setting the value in settings dismisses any opt-in.
    searchEngines.shouldShowRecentSearches = toggle.isOn
    searchEngines.shouldShowRecentSearchesOptIn = false
  }
  
  @objc func didToggleBrowserSuggestions(_ toggle: UISwitch) {
    // Setting the value effects all the modes private normal pbo
    searchEngines.shouldShowBrowserSuggestions = toggle.isOn
  }
    
    @objc func didToggleMuti(_ toggle: UISwitch) {
      // Setting the value effects all the modes private normal pbo
      searchEngines.shouldMutiHelp = toggle.isOn
    }
    
    @objc func didToggleAi(_ toggle: UISwitch) {
      // Setting the value effects all the modes private normal pbo
      searchEngines.shouldAiHelp = toggle.isOn
    }

  @objc func dismissAnimated() {
    self.dismiss(animated: true, completion: nil)
  }
}

// MARK: SearchEnginePickerDelegate

extension SearchSettingsTableViewController: SearchEnginePickerDelegate {

  func searchEnginePicker(
    _ searchEnginePicker: SearchEnginePicker?,
    didSelectSearchEngine searchEngine: OpenSearchEngine?, forType: DefaultEngineType?
  ) {
    if let engine = searchEngine, let type = forType {
      searchEngines.updateDefaultEngine(engine.shortName, forType: type)
      self.tableView.reloadData()
    }
    _ = navigationController?.popViewController(animated: true)
  }
}
