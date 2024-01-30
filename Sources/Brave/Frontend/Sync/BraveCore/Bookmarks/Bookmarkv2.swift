// 版权 2020 年 The Brave Authors。保留所有权利。
// 本源代码表单受 Mozilla Public License, v. 2.0 的条款约束。
// 如果未随此文件分发 MPL 的副本，
// 您可以在 http://mozilla.org/MPL/2.0/ 处获取一份。

import BraveCore
import BraveShared
import CoreData
import Data
import Foundation
import Shared

// 一个围绕 BraveCore 书签的轻量级包装器
// 具有与“Bookmark（来自 CoreData）”相同的布局/接口
class Bookmarkv2: WebsitePresentable {
    // MARK: 生命周期

    init(_ bookmarkNode: BookmarkNode) {
        self.bookmarkNode = bookmarkNode
    }

    // MARK: 内部

    public let bookmarkNode: BookmarkNode

    public var bookmarkFavIconObserver: BookmarkModelListener?

    public var isFolder: Bool {
        return bookmarkNode.isFolder == true
    }

    public var title: String? {
        return bookmarkNode.titleUrlNodeTitle
    }

    public var url: String? {
        bookmarkNode.titleUrlNodeUrl?.absoluteString
    }

    public var domain: Domain? {
        if let url = bookmarkNode.titleUrlNodeUrl {
            return Domain.getOrCreate(forUrl: url, persistent: true)
        }
        return nil
    }

    public var parent: Bookmarkv2? {
        if let parent = bookmarkNode.parent {
            // 如果父节点是 ROOT 节点，则返回 nil
            // 因为 AddEditBookmarkTableViewController.sortFolders
            // 通过具有空父节点来排序根文件夹。
            // 如果该代码更改，我们应该在这里进行更改以匹配。
            if bookmarkNode.parent?.guid != BookmarkManager.rootNodeId {
                return Bookmarkv2(parent)
            }
        }
        return nil
    }

    public var children: [Bookmarkv2]? {
        return bookmarkNode.children.map { Bookmarkv2($0) }
    }

    public var canBeDeleted: Bool {
        return bookmarkNode.isPermanentNode == false
    }

    public var objectID: Int {
        return Int(bookmarkNode.nodeId)
    }

    public func update(customTitle: String?, url: URL?) {
        bookmarkNode.setTitle(customTitle ?? "")
        bookmarkNode.url = url
    }

    public func existsInPersistentStore() -> Bool {
        return bookmarkNode.isValid && bookmarkNode.parent != nil
    }
}

class BraveBookmarkFolder: Bookmarkv2 {
    public let indentationLevel: Int

    override private init(_ bookmarkNode: BookmarkNode) {
        self.indentationLevel = 0
        super.init(bookmarkNode)
    }

    public init(_ bookmarkFolder: BookmarkFolder) {
        self.indentationLevel = bookmarkFolder.indentationLevel
        super.init(bookmarkFolder.bookmarkNode)
    }
}

extension Bookmarkv2 {
    func flatten() -> [Bookmarkv2] {
        var flattenedBookmarks: [Bookmarkv2] = []
        if isFolder {
            if let children = children {
                for child in children {
                    flattenedBookmarks.append(contentsOf: child.flatten())
                }
            }
        } else {
            flattenedBookmarks.append(self)
        }

        return flattenedBookmarks
    }

    static func sortByURL(bookmarks: [Bookmarkv2]) -> [Bookmarkv2] {
        return bookmarks.sorted { bookmark1, bookmark2 -> Bool in
            // 使用 ?? 运算符，以确保 nil 值排在最后
            let url1 = bookmark1.url ?? ""
            let url2 = bookmark2.url ?? ""
            return url1.localizedCompare(url2) == .orderedAscending
        }
    }

    func tran2New() -> NewBookmarkBean {
        var flattenedBookmarks: [NewBookmarkBean] = []
        let item = NewBookmarkBean(self.title!)
        if isFolder {
            item.type = "folder"
            item.url = ""
            
            if let children = children {
                for child in children {
                    item.children.append(child.tran2New())
                }
            }
        } else {
            item.type = "bookmark"
            item.title = self.title
            item.url = self.url!
        }
       // flattenedBookmarks.append(item)
        return item
    }
}
