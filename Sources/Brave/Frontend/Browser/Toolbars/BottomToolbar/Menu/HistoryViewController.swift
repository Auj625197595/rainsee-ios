/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import BraveShared
import Preferences
import Storage
import Data
import CoreData
import BraveCore
import Favicon
import UIKit
import DesignSystem
import ScreenTime

class HistoryViewController: SiteTableViewController, ToolbarUrlActionsProtocol {

    weak var toolbarUrlActionsDelegate: ToolbarUrlActionsDelegate?
    // 空状态叠加视图1
    private lazy var emptyStateOverlayView = EmptyStateOverlayView(
        overlayDetails: EmptyOverlayStateDetails(
            title: Preferences.Privacy.privateBrowsingOnly.value
                ? Strings.History.historyPrivateModeOnlyStateTitle
                : Strings.History.historyEmptyStateTitle,
            icon: UIImage(named: "emptyHistory", in: .module, compatibleWith: nil)))

    private let historyAPI: BraveHistoryAPI
    private let tabManager: TabManager
    private var historyFRC: HistoryV2FetchResultsController?

    private let isPrivateBrowsing: Bool  /// 某些书签操作在隐私浏览模式下是不同的。
    private let isModallyPresented: Bool
    private var isHistoryRefreshing = false

    private var searchHistoryTimer: Timer?
    private var isHistoryBeingSearched = false
    private let searchController = UISearchController(searchResultsController: nil)
    private var searchQuery = ""

    // 初始化方法
    init(isPrivateBrowsing: Bool, isModallyPresented: Bool = false, historyAPI: BraveHistoryAPI, tabManager: TabManager) {
        self.isPrivateBrowsing = isPrivateBrowsing
        self.isModallyPresented = isModallyPresented
        self.historyAPI = historyAPI
        self.tabManager = tabManager
        super.init(nibName: nil, bundle: nil)

        historyFRC = historyAPI.frc()
        historyFRC?.delegate = self
    }

    // 不使用 storyboard 初始化时需要实现的初始化方法
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 视图加载完成时调用
    override func viewDidLoad() {
        super.viewDidLoad()

        // 应用主题
        applyTheme()

        // 配置表格视图
        tableView.do {
            $0.accessibilityIdentifier = "History List"
            $0.sectionHeaderTopPadding = 5
        }

        // 配置导航栏项
        navigationItem.do {
            if !Preferences.Privacy.privateBrowsingOnly.value {
                $0.searchController = searchController
                $0.hidesSearchBarWhenScrolling = false
                $0.rightBarButtonItem =
                    UIBarButtonItem(image: UIImage(braveSystemNamed: "leo.trash")!.template, style: .done, target: self, action: #selector(performDeleteAll))
            }

            if isModallyPresented {
                $0.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(performDone))
            }
        }

        // 定义呈现上下文
        definesPresentationContext = true
    }

    // 视图即将显示时调用
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // 刷新历史记录
        refreshHistory()
    }

    // 应用主题样式
    private func applyTheme() {
        title = Strings.historyScreenTitle

        searchController.do {
            $0.searchBar.autocapitalizationType = .none
            $0.searchResultsUpdater = self
            $0.obscuresBackgroundDuringPresentation = false
            $0.searchBar.placeholder = Strings.History.historySearchBarTitle
            $0.delegate = self
            $0.hidesNavigationBarDuringPresentation = true
        }
    }

    // 刷新历史记录
    private func refreshHistory() {
        if isHistoryBeingSearched {
            return
        }

        if Preferences.Privacy.privateBrowsingOnly.value {
            showEmptyPanelState()
        } else {
            if !isHistoryRefreshing {
                isLoading = true
                isHistoryRefreshing = true

                historyAPI.waitForHistoryServiceLoaded { [weak self] in
                    guard let self = self else { return }

                    self.reloadData() {
                        self.isHistoryRefreshing = false
                        self.isLoading = false
                    }
                }
            }
        }
    }

    // 重新加载数据，可带有查询条件
    private func reloadData(with query: String = "", _ completion: @escaping () -> Void) {
        // 如果之前已删除，则重新创建 FRC（Fetched Results Controller）
        if historyFRC == nil {
            historyFRC = historyAPI.frc()
            historyFRC?.delegate = self
        }

        // 执行历史记录 FRC 的查询操作
        historyFRC?.performFetch(withQuery: query) { [weak self] in
            guard let self = self else { return }

            // 刷新表格数据
            self.tableView.reloadData()
            // 更新空面板状态
            self.updateEmptyPanelState()

            completion()
        }
    }

    // 重新加载数据并显示加载状态
    private func reloadDataAndShowLoading(with query: String) {
        isLoading = true
        // 调用重新加载数据的方法，并在完成后设置 isLoading 为 false
        reloadData(with: query) { [weak self] in
            self?.isLoading = false
        }
    }

    // 更新空面板状态
    private func updateEmptyPanelState() {
        if historyFRC?.fetchedObjectsCount == 0 {
            // 显示空面板状态
            showEmptyPanelState()
        } else {
            // 移除空面板视图
            emptyStateOverlayView.removeFromSuperview()
        }
    }

    // 显示空面板状态
    private func showEmptyPanelState() {
        if emptyStateOverlayView.superview == nil {
            // 根据是否正在搜索显示不同的信息
            if isHistoryBeingSearched {
                emptyStateOverlayView.updateInfoLabel(with: Strings.noSearchResultsfound)
            } else {
                emptyStateOverlayView.updateInfoLabel(
                    with: Preferences.Privacy.privateBrowsingOnly.value
                        ? Strings.History.historyPrivateModeOnlyStateTitle
                        : Strings.History.historyEmptyStateTitle)
            }

            // 将空面板添加到视图并设置约束
            view.addSubview(emptyStateOverlayView)
            view.bringSubviewToFront(emptyStateOverlayView)
            emptyStateOverlayView.snp.makeConstraints { make -> Void in
                make.edges.equalTo(tableView)
            }
        }
    }

    // 使搜索定时器失效
    private func invalidateSearchTimer() {
        if searchHistoryTimer != nil {
            searchHistoryTimer?.invalidate()
            searchHistoryTimer = nil
        }
    }

    // 执行删除所有历史记录的操作
    @objc private func performDeleteAll() {
        // 根据设备类型选择警告框样式
        let style: UIAlertController.Style = UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet
        // 创建警告框
        let alert = UIAlertController(
            title: Strings.History.historyClearAlertTitle, message: Strings.History.historyClearAlertDescription, preferredStyle: style)

        // 添加删除操作
        alert.addAction(
            UIAlertAction(
                title: Strings.History.historyClearActionTitle, style: .destructive,
                handler: { [weak self] _ in
                    guard let self = self, let allHistoryItems = historyFRC?.fetchedObjects else {
                        return
                    }

                    // 删除本地历史记录
                    self.historyAPI.deleteAll {
                        // 清除标签历史记录
                        self.tabManager.clearTabHistory() {
                            self.refreshHistory()
                        }

                        // 清除历史记录应该同时清除最近关闭的标签
                        RecentlyClosed.removeAll()

                        // 为建议操作创建“清除浏览器历史记录”捐赠
                        let clearBrowserHistoryActivity = ActivityShortcutManager.shared.createShortcutActivity(type: .clearBrowsingHistory)
                        self.userActivity = clearBrowserHistoryActivity
                        clearBrowserHistoryActivity.becomeCurrent()
                    }

                    // 请求同步引擎删除访问记录
                    for historyItems in allHistoryItems {
                        self.historyAPI.removeHistory(historyItems)
                    }
                }))
        // 添加取消操作
        alert.addAction(UIAlertAction(title: Strings.cancelButtonTitle, style: .cancel, handler: nil))

        // 弹出警告框
        present(alert, animated: true, completion: nil)
    }

    // 执行完成操作
    @objc private func performDone() {
        dismiss(animated: true)
    }

    // UITableViewDelegate 和 UITableViewDataSource 方法的实现
    // ...
    // MARK: UITableViewDelegate - UITableViewDataSource

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
      let cell = super.tableView(tableView, cellForRowAt: indexPath)
      configureCell(cell, atIndexPath: indexPath)

      return cell
    }
    // 处理单元格的配置
    func configureCell(_ cell: UITableViewCell, atIndexPath indexPath: IndexPath) {
        // 确保历史记录在索引路径存在，`frc.object(at:)` 否则会崩溃，不能安全地返回 nil
        if let objectsCount = historyFRC?.fetchedObjectsCount, indexPath.row >= objectsCount {
            assertionFailure("History FRC index out of bounds")
            return
        }

        // 强制转换为 TwoLineTableViewCell 类型
        guard let cell = cell as? TwoLineTableViewCell else { return }

        // 如果表格视图不在编辑状态，移除单元格的所有手势
        if !tableView.isEditing {
            cell.gestureRecognizers?.forEach { cell.removeGestureRecognizer($0) }
        }

        // 获取对应索引路径的历史记录项
        guard let historyItem = historyFRC?.object(at: indexPath) else { return }

        // 配置单元格
        cell.do {
            $0.backgroundColor = UIColor.clear
            $0.setLines(historyItem.title, detailText: historyItem.url.absoluteString)

            $0.imageView?.contentMode = .scaleAspectFit
            $0.imageView?.layer.borderColor = FaviconUX.faviconBorderColor.cgColor
            $0.imageView?.layer.borderWidth = FaviconUX.faviconBorderWidth
            $0.imageView?.layer.cornerRadius = 6
            $0.imageView?.layer.cornerCurve = .continuous
            $0.imageView?.layer.masksToBounds = true

            // 获取或创建与 URL 相关的域信息
            let domain = Domain.getOrCreate(
                forUrl: historyItem.url,
                persistent: !isPrivateBrowsing)

            // 如果域的 URL 不为 nil，则加载对应 URL 的网站图标
            if domain.url?.asURL != nil {
                cell.imageView?.loadFavicon(for: historyItem.url, isPrivateBrowsing: isPrivateBrowsing)
            } else {
                // 如果没有 URL，则清除单色网站图标并设置默认图标
                cell.imageView?.clearMonogramFavicon()
                cell.imageView?.image = Favicon.defaultImage
            }
        }
    }

    // 处理选中行为
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // 获取对应索引路径的历史记录项
        guard let historyItem = historyFRC?.object(at: indexPath) else { return }

        // 如果正在搜索历史记录，则结束搜索状态
        if isHistoryBeingSearched {
            searchController.isActive = false
        }

        // 获取历史记录项的 URL
        if let url = URL(string: historyItem.url.absoluteString) {
            // 如果是安全网页，则捐赠“打开网站”自定义意图
            if url.isSecureWebPage(), !isPrivateBrowsing {
                ActivityShortcutManager.shared.donateCustomIntent(for: .openHistory, with: url.absoluteString)
            }

            // 关闭当前视图控制器并通过委托选择 URL
            dismiss(animated: true) {
                self.toolbarUrlActionsDelegate?.select(url: url, isUserDefinedURLNavigation: false)
            }
        }

        // 取消选中状态
        tableView.deselectRow(at: indexPath, animated: true)
    }

    // 获取表格视图的分区数
    func numberOfSections(in tableView: UITableView) -> Int {
        return historyFRC?.sectionCount ?? 0
    }

    // 获取分区的标题
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return historyFRC?.titleHeader(for: section)
    }

    // 获取表格视图的行数
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return historyFRC?.objectCount(for: section) ?? 0
    }

    // 处理编辑样式以及在滑动删除时的操作
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        switch editingStyle {
        case .delete:
            // 获取对应索引路径的历史记录项
            guard let historyItem = historyFRC?.object(at: indexPath) else { return }
            // 移除历史记录项
            historyAPI.removeHistory(historyItem)

            // 移除对应的最近关闭的标签项
            RecentlyClosed.remove(with: historyItem.url.absoluteString)

            do {
                // 尝试初始化 STWebHistory，并删除历史记录
                let screenTimeHistory = try STWebHistory(bundleIdentifier: Bundle.main.bundleIdentifier!)
                screenTimeHistory.deleteHistory(for: historyItem.url)
            } catch {
                assertionFailure("STWebHistory could not be initialized: \(error)")
            }

            // 如果正在搜索历史记录，则重新加载带有搜索条件的数据，否则刷新历史记录
            if isHistoryBeingSearched {
                reloadDataAndShowLoading(with: searchQuery)
            } else {
                refreshHistory()
            }
        default:
            break
        }
    }


    // 在表格视图中为每一行配置上下文菜单
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        // 获取历史记录项的 URL
        guard let historyItemURL = historyFRC?.object(at: indexPath)?.url else {
            return nil
        }

        // 创建上下文菜单配置
        return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { [unowned self] _ in
            // 定义在新标签中打开的操作
            let openInNewTabAction = UIAction(
                title: Strings.openNewTabButtonTitle,
                image: UIImage(systemName: "plus.square.on.square"),
                handler: UIAction.deferredActionHandler { _ in
                    // 调用委托方法，在新标签中打开历史记录项的 URL
                    self.toolbarUrlActionsDelegate?.openInNewTab(historyItemURL, isPrivate: self.isPrivateBrowsing)
                    // 关闭当前视图控制器
                    self.presentingViewController?.dismiss(animated: true)
                })

            // 定义在新私密标签中打开的操作
            let newPrivateTabAction = UIAction(
                title: Strings.openNewPrivateTabButtonTitle,
                image: UIImage(systemName: "plus.square.fill.on.square.fill"),
                handler: UIAction.deferredActionHandler { [unowned self] _ in
                    // 如果不是私密浏览，且启用了私密浏览锁定，则请求本地身份验证
                    if !isPrivateBrowsing, Preferences.Privacy.privateBrowsingLock.value {
                        self.askForLocalAuthentication { [weak self] success, error in
                            if success {
                                // 调用委托方法，在新私密标签中打开历史记录项的 URL
                                self?.toolbarUrlActionsDelegate?.openInNewTab(historyItemURL, isPrivate: true)
                            }
                        }
                    } else {
                        // 调用委托方法，在新私密标签中打开历史记录项的 URL
                        self.toolbarUrlActionsDelegate?.openInNewTab(historyItemURL, isPrivate: true)
                    }
                })

            // 定义复制链接的操作
            let copyAction = UIAction(
                title: Strings.copyLinkActionTitle,
                image: UIImage(systemName: "doc.on.doc"),
                handler: UIAction.deferredActionHandler { _ in
                    // 调用委托方法，复制历史记录项的 URL
                    self.toolbarUrlActionsDelegate?.copy(historyItemURL)
                })

            // 定义分享链接的操作
            let shareAction = UIAction(
                title: Strings.shareLinkActionTitle,
                image: UIImage(systemName: "square.and.arrow.up"),
                handler: UIAction.deferredActionHandler { _ in
                    // 调用委托方法，分享历史记录项的 URL
                    self.toolbarUrlActionsDelegate?.share(historyItemURL)
                })

            // 根据是否私密浏览添加不同的操作到新标签的菜单
            var newTabActionMenu: [UIAction] = [openInNewTabAction]
            if !isPrivateBrowsing {
                newTabActionMenu.append(newPrivateTabAction)
            }

            // 创建 URL 菜单，包含在新标签中打开的操作
            let urlMenu = UIMenu(title: "", options: .displayInline, children: newTabActionMenu)
            // 创建链接菜单，包含复制和分享的操作
            let linkMenu = UIMenu(title: "", options: .displayInline, children: [copyAction, shareAction])

            // 创建最终的上下文菜单，包含 URL 菜单和链接菜单
            return UIMenu(title: historyItemURL.absoluteString, identifier: nil, children: [urlMenu, linkMenu])
        }
    }

}

// MARK: - HistoryV2FetchResultsDelegate

// HistoryV2FetchResultsDelegate 协议的实现，用于处理历史记录的数据变化
extension HistoryViewController: HistoryV2FetchResultsDelegate {
    
    // 当数据变化即将开始时调用，用于启动表格视图的更新
    func controllerWillChangeContent(_ controller: HistoryV2FetchResultsController) {
        tableView.beginUpdates()
    }

    // 当数据变化完成时调用，用于结束表格视图的更新
    func controllerDidChangeContent(_ controller: HistoryV2FetchResultsController) {
        tableView.endUpdates()
    }

    // 处理单个历史记录项的变化，包括插入、删除、更新和移动
    func controller(_ controller: HistoryV2FetchResultsController, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            if let indexPath = newIndexPath {
                tableView.insertRows(at: [indexPath], with: .automatic)
            }
        case .delete:
            if let indexPath = indexPath {
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }
        case .update:
            if let indexPath = indexPath, let cell = tableView.cellForRow(at: indexPath) {
                // 更新单元格内容
                configureCell(cell, atIndexPath: indexPath)
            }
        case .move:
            if let indexPath = indexPath {
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }

            if let newIndexPath = newIndexPath {
                tableView.insertRows(at: [newIndexPath], with: .automatic)
            }
        @unknown default:
            assertionFailure()
        }
        // 更新空面板状态
        updateEmptyPanelState()
    }

    // 处理分组信息的变化，包括分组的插入和删除
    func controller(_ controller: HistoryV2FetchResultsController, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        switch type {
        case .insert:
            let sectionIndexSet = IndexSet(integer: sectionIndex)
            // 插入新的分组
            self.tableView.insertSections(sectionIndexSet, with: .fade)
        case .delete:
            let sectionIndexSet = IndexSet(integer: sectionIndex)
            // 删除分组
            self.tableView.deleteSections(sectionIndexSet, with: .fade)
        default: break
        }
    }

    // 数据重新加载完成时的处理，刷新历史记录
    func controllerDidReloadContents(_ controller: HistoryV2FetchResultsController) {
        refreshHistory()
    }
}

// UISearchResultsUpdating 协议的实现，用于处理搜索框内容变化时的操作
extension HistoryViewController: UISearchResultsUpdating {

    // 当搜索框内容变化时调用
    func updateSearchResults(for searchController: UISearchController) {
        guard let query = searchController.searchBar.text else { return }

        // 取消之前的搜索定时器
        invalidateSearchTimer()

        // 创建新的搜索定时器，0.1 秒后触发搜索操作
        searchHistoryTimer =
            Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(fetchSearchResults(timer:)), userInfo: query, repeats: false)
    }

    // 实际执行搜索操作的方法
    @objc private func fetchSearchResults(timer: Timer) {
        guard let query = timer.userInfo as? String else {
            searchQuery = ""
            return
        }

        // 更新搜索关键词并重新加载数据
        searchQuery = query
        reloadDataAndShowLoading(with: searchQuery)
    }
}

// UISearchControllerDelegate 协议的实现，处理搜索控制器的显示和消失
extension HistoryViewController: UISearchControllerDelegate {

    // 将要显示搜索控制器时调用
    func willPresentSearchController(_ searchController: UISearchController) {
        isHistoryBeingSearched = true
        searchQuery = ""
        tableView.setEditing(false, animated: true)
        tableView.reloadData()
    }

    // 将要取消搜索控制器时调用
    func willDismissSearchController(_ searchController: UISearchController) {
        // 取消搜索定时器
        invalidateSearchTimer()

        isHistoryBeingSearched = false
        tableView.reloadData()
    }
}
