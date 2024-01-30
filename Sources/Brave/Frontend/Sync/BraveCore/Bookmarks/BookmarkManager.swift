// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import BraveCore
import CoreData
import Data
import Foundation
import Growth
import os.log
import Preferences
import Shared

class BookmarkManager {
    // MARK: Lifecycle

    init(bookmarksAPI: BraveBookmarksAPI?) {
        self.bookmarksAPI = bookmarksAPI
        // 设置根节点的ID为 BraveBookmarksAPI 中的根节点的ID
        BookmarkManager.rootNodeId = bookmarksAPI?.rootNode?.guid
    }

    // MARK: Internal

    // 静态属性，用于存储根节点的ID
    public static var rootNodeId: String?

    // 获取搜索到的书签对象的数量
    public var fetchedSearchObjectsCount: Int {
        searchBookmarkList.count
    }

    // 返回最后访问的文件夹
    // 如果没有访问过文件夹，则返回移动书签文件夹
    // 如果访问了根文件夹，则返回nil
    public func lastVisitedFolder() -> Bookmarkv2? {
        guard let bookmarksAPI = bookmarksAPI else {
            return nil
        }

        guard Preferences.General.showLastVisitedBookmarksFolder.value,
              let nodeId = Preferences.Chromium.lastBookmarksFolderNodeId.value
        else {
            // 默认文件夹是移动节点..
            if let mobileNode = bookmarksAPI.mobileNode {
                return Bookmarkv2(mobileNode)
            }
            return nil
        }

        // 显示根文件夹而不是移动节点..
        if nodeId == -1 {
            if let mobileNode = bookmarksAPI.mobileNode {
                return Bookmarkv2(mobileNode)
            }
            return nil
        }

        // 显示最后访问的文件夹..
        if let folderNode = bookmarksAPI.getNodeById(nodeId),
           folderNode.isVisible
        {
            return Bookmarkv2(folderNode)
        }

        // 默认文件夹是移动节点..
        if let mobileNode = bookmarksAPI.mobileNode {
            return Bookmarkv2(mobileNode)
        }
        return nil
    }

    // 返回最后访问文件夹的路径
    public func lastFolderPath() -> [Bookmarkv2] {
        guard let bookmarksAPI = bookmarksAPI else {
            return []
        }

        if Preferences.General.showLastVisitedBookmarksFolder.value,
           let nodeId = Preferences.Chromium.lastBookmarksFolderNodeId.value,
           var folderNode = bookmarksAPI.getNodeById(nodeId),
           folderNode.isVisible
        {
            // 我们从不显示根节点
            // 它是所有节点的母亲
            let rootNodeGuid = bookmarksAPI.rootNode?.guid

            var nodes = [BookmarkNode]()
            nodes.append(folderNode)

            while true {
                if let parent = folderNode.parent, parent.isVisible, parent.guid != rootNodeGuid {
                    nodes.append(parent)
                    folderNode = parent
                    continue
                }
                break
            }
            return nodes.map { Bookmarkv2($0) }.reversed()
        }

        // 默认文件夹是移动节点..
        if let mobileNode = bookmarksAPI.mobileNode {
            return [Bookmarkv2(mobileNode)]
        }

        return []
    }

    // 返回移动节点
    public func mobileNode() -> Bookmarkv2? {
        guard let bookmarksAPI = bookmarksAPI else {
            return nil
        }

        if let node = bookmarksAPI.mobileNode {
            return Bookmarkv2(node)
        }
        return nil
    }

    // 获取父节点
    public func fetchParent(_ bookmarkItem: Bookmarkv2?) -> Bookmarkv2? {
        guard let bookmarkItem = bookmarkItem, let bookmarksAPI = bookmarksAPI else {
            return nil
        }

        if let parent = bookmarkItem.bookmarkNode.parent {
            // 如果父节点是ROOT节点，则返回nil
            // 因为 AddEditBookmarkTableViewController.sortFolders
            // 通过具有nil父节点来排序根文件夹。
            // 如果更改该代码，我们应该在此处进行相应更改。
            if bookmarkItem.bookmarkNode.parent?.guid != bookmarksAPI.rootNode?.guid {
                return Bookmarkv2(parent)
            }
        }
        return nil
    }

    // 添加文件夹
    @discardableResult
    public func addFolder(title: String, parentFolder: Bookmarkv2? = nil) -> BookmarkNode? {
        guard let bookmarksAPI = bookmarksAPI else {
            return nil
        }

        if let parentFolder = parentFolder?.bookmarkNode {
            return bookmarksAPI.createFolder(withParent: parentFolder, title: title)
        } else {
            return bookmarksAPI.createFolder(withTitle: title)
        }
    }

    // 添加书签
    public func add(url: URL, title: String?, parentFolder: Bookmarkv2? = nil) {
        guard let bookmarksAPI = bookmarksAPI else {
            return
        }

        if let parentFolder = parentFolder?.bookmarkNode {
            bookmarksAPI.createBookmark(withParent: parentFolder, title: title ?? "", with: url)
        } else {
            bookmarksAPI.createBookmark(withTitle: title ?? "", url: url)
        }

        // 处理评审管理器的子标准，用于 .numberOfBookmarks
        AppReviewManager.shared.processSubCriteria(for: .numberOfBookmarks)
    }

    // 获取父节点的BookmarksV2FetchResultsController
    public func frc(parent: Bookmarkv2?) -> BookmarksV2FetchResultsController? {
        guard let bookmarksAPI = bookmarksAPI else {
            return nil
        }

        return Bookmarkv2Fetcher(parent?.bookmarkNode, api: bookmarksAPI)
    }

    // 获取文件夹的BookmarksV2FetchResultsController，可排除指定的文件夹
    public func foldersFrc(excludedFolder: Bookmarkv2? = nil) -> BookmarksV2FetchResultsController? {
        guard let bookmarksAPI = bookmarksAPI else {
            return nil
        }

        return Bookmarkv2ExclusiveFetcher(excludedFolder?.bookmarkNode, api: bookmarksAPI)
    }

    // 获取文件夹的子节点，可选择是否包括文件夹
    public func getChildren(forFolder folder: Bookmarkv2, includeFolders: Bool) -> [Bookmarkv2]? {
        let result = folder.bookmarkNode.children.map { Bookmarkv2($0) }
        return includeFolders ? result : result.filter { $0.isFolder == false }
    }

    // 按照频率获取书签，可传入查询字符串
    public func byFrequency(query: String? = nil, completion: @escaping ([WebsitePresentable]) -> Void) {
        // 无效的查询.. BraveCore 不基于最后访问的书签进行存储。
        // 任何最后访问的书签都会显示在 `History` 中。
        // BraveCore 也会自动按日期对其进行排序。
        guard let query = query, !query.isEmpty, let bookmarksAPI = bookmarksAPI else {
            completion([])
            return
        }

        return bookmarksAPI.search(
            withQuery: query, maxCount: 200,
            completion: { nodes in
                completion(nodes.compactMap { !$0.isFolder ? Bookmarkv2($0) : nil })
            })
    }

    // 按照查询获取书签
    public func fetchBookmarks(with query: String = "", _ completion: @escaping () -> Void) {
        guard let bookmarksAPI = bookmarksAPI else {
            searchBookmarkList = []
            completion()
            return
        }

        bookmarksAPI.search(
            withQuery: query, maxCount: 200,
            completion: { [weak self] nodes in
                guard let self = self else { return }

                self.searchBookmarkList = nodes.compactMap { !$0.isFolder ? Bookmarkv2($0) : nil }

                completion()
            })
    }

    public func checkHave(with query: String = "", _ completion: @escaping (Bookmarkv2?) -> Void) {
        guard let bookmarksAPI = bookmarksAPI else {
            completion(nil)
            return
        }

        bookmarksAPI.search(
            withQuery: query, maxCount: 1,
            completion: { [weak self] nodes in
                guard let self = self else { return }

                let result = nodes.compactMap { !$0.isFolder ? Bookmarkv2($0) : nil }

                if result.count > 0, result[0].url == query {
                    completion( result[0])
                    return
                }
                completion(nil)
            })
    }

    public func reorderBookmarks(frc: BookmarksV2FetchResultsController?, sourceIndexPath: IndexPath, destinationIndexPath: IndexPath) {
        guard let frc = frc, let bookmarksAPI = bookmarksAPI else {
            return
        }

        if let node = frc.object(at: sourceIndexPath)?.bookmarkNode,
            let parent = node.parent ?? bookmarksAPI.mobileNode
        {
            // 如果在列表中向下移动节点，目标索引应该增加1
            let destinationIndex = sourceIndexPath.row > destinationIndexPath.row ? destinationIndexPath.row : destinationIndexPath.row + 1
            node.move(toParent: parent, index: UInt(destinationIndex))

            // 通知委托已移动项目
            // 这已经在`Bookmarkv2Fetcher`监听器中自动完成
            // 但是，Brave-Core委托在移动实际完成之前或太快之前就被调用
            // 所以为了修复它，我们在移动完成后在这里重新加载，以便UI可以相应更新
            frc.delegate?.controllerDidReloadContents(frc)
        }
    }

    public func delete(_ bookmarkItem: Bookmarkv2) {
        guard let bookmarksAPI = bookmarksAPI else {
            return
        }

        if bookmarkItem.canBeDeleted {
            bookmarksAPI.removeBookmark(bookmarkItem.bookmarkNode)
        }
    }

    public func updateWithNewLocation(_ bookmarkItem: Bookmarkv2, customTitle: String?, url: URL?, location: Bookmarkv2?) {
        guard let bookmarksAPI = bookmarksAPI else {
            return
        }

        if let location = location?.bookmarkNode ?? bookmarksAPI.mobileNode {
            // 如果位置不同，将书签节点移动到新位置
            if location.guid != bookmarkItem.bookmarkNode.parent?.guid {
                bookmarkItem.bookmarkNode.move(toParent: location)
            }

            // 如果提供了自定义标题，将书签标题更新为自定义标题
            if let customTitle = customTitle {
                bookmarkItem.bookmarkNode.setTitle(customTitle)
            }

            // 如果提供了URL并且书签不是文件夹，将书签URL更新为新URL
            else if let url = url, !bookmarkItem.bookmarkNode.isFolder {
                bookmarkItem.bookmarkNode.url = url
            }
            // 如果提供了URL但是书签是文件夹，记录错误
            else if url != nil {
                Logger.module.error("Error: Moving bookmark - 无法将文件夹转换为具有URL的书签。")
            }
        } else {
            // 如果位置为空，记录错误
            Logger.module.error("Error: Moving bookmark - 无法将书签移动到根目录。")
        }
    }

    public func addFavIconObserver(_ bookmarkItem: Bookmarkv2, observer: @escaping () -> Void) {
        guard let bookmarksAPI = bookmarksAPI else {
            return
        }

        // 创建一个观察者，监视FavIcon的更改
        let observer = BookmarkModelStateObserver { [weak self] state in
            if case .favIconChanged(let node) = state {
                // 如果FavIcon更改是由我们监视的书签引起的
                if node.isValid && bookmarkItem.bookmarkNode.isValid
                    && node.guid == bookmarkItem.bookmarkNode.guid
                {
                    // 如果书签的FavIcon已加载，移除观察者
                    if bookmarkItem.bookmarkNode.isFavIconLoaded {
                        self?.removeFavIconObserver(bookmarkItem)
                    }

                    // 调用传入的闭包通知FavIcon更改
                    observer()
                }
            }
        }

        // 将观察者添加到FavIcon的状态监视中
        bookmarkItem.bookmarkFavIconObserver = bookmarksAPI.add(observer)
    }

    public func searchObject(at indexPath: IndexPath) -> Bookmarkv2? {
        // 返回搜索结果中指定索引处的书签
        searchBookmarkList[safe: indexPath.row]
    }

    // MARK: Private

    private var observer: BookmarkModelListener?
    private let bookmarksAPI: BraveBookmarksAPI?
    // 在搜索结果中列出的书签列表
    private var searchBookmarkList: [Bookmarkv2] = []

    private func removeFavIconObserver(_ bookmarkItem: Bookmarkv2) {
        // 移除FavIcon的状态监视
        bookmarkItem.bookmarkFavIconObserver = nil
    }

}

// MARK: Brave-Core Only

extension BookmarkManager {
    // 等待书签模型加载完成的方法，使用闭包作为参数
    public func waitForBookmarkModelLoaded(_ completion: @escaping () -> Void) {
        // 确保 bookmarksAPI 不为 nil
        guard let bookmarksAPI = bookmarksAPI else {
            return
        }

        // 如果书签API已加载，立即调用完成闭包
        if bookmarksAPI.isLoaded {
            DispatchQueue.main.async {
                completion()
            }
        } else {
            // 如果书签API尚未加载，添加观察者等待加载完成
            observer = bookmarksAPI.add(
                // 创建 BookmarkModelStateObserver 观察者，监听书签模型状态的变化
                BookmarkModelStateObserver { [weak self] in
                    // 当模型加载完成时
                    if case .modelLoaded = $0 {
                        // 销毁观察者，避免内存泄漏
                        self?.observer?.destroy()
                        self?.observer = nil

                        // 在主线程中调用完成闭包
                        DispatchQueue.main.async {
                            completion()
                        }
                    }
                })
        }
    }
}

