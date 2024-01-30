// 版权 2020 年 The Brave Authors。保留所有权利。
// 本源代码表单受 Mozilla Public License, v. 2.0 的条款约束。
// 如果未随此文件分发 MPL 的副本，
// 您可以在 http://mozilla.org/MPL/2.0/ 处获取一份。

import Foundation
import BraveCore

// 书签模型状态观察者，实现 BraveServiceStateObserver 和 BookmarkModelObserver 协议
class BookmarkModelStateObserver: BraveServiceStateObserver, BookmarkModelObserver {
  private let listener: (StateChange) -> Void

  // 定义状态改变的枚举
  enum StateChange {
    case modelLoaded
    case nodeChanged(BookmarkNode)
    case favIconChanged(BookmarkNode)
    case childrenChanged(BookmarkNode)
    case nodeMoved(_ node: BookmarkNode, _ from: BookmarkNode, _ to: BookmarkNode)
    case nodeDeleted(_ node: BookmarkNode, _ from: BookmarkNode)
    case allRemoved
  }

  // 初始化方法，接受状态变化的监听器
  init(_ listener: @escaping (StateChange) -> Void) {
    self.listener = listener
  }

  // 实现 BookmarkModelObserver 协议的方法，书签模型加载完成
  func bookmarkModelLoaded() {
    self.listener(.modelLoaded)

    // 发送服务加载完成通知
    postServiceLoadedNotification()
  }

  // 实现 BookmarkModelObserver 协议的方法，书签节点发生变化
  func bookmarkNodeChanged(_ bookmarkNode: BookmarkNode) {
    self.listener(.nodeChanged(bookmarkNode))
  }

  // 实现 BookmarkModelObserver 协议的方法，书签节点的图标发生变化
  func bookmarkNodeFaviconChanged(_ bookmarkNode: BookmarkNode) {
    self.listener(.favIconChanged(bookmarkNode))
  }

  // 实现 BookmarkModelObserver 协议的方法，书签节点的子节点发生变化
  func bookmarkNodeChildrenChanged(_ bookmarkNode: BookmarkNode) {
    self.listener(.childrenChanged(bookmarkNode))
  }

  // 实现 BookmarkModelObserver 协议的方法，书签节点从一个父节点移动到另一个父节点
  func bookmarkNode(_ bookmarkNode: BookmarkNode, movedFromParent oldParent: BookmarkNode, toParent newParent: BookmarkNode) {
    self.listener(.nodeMoved(bookmarkNode, oldParent, newParent))
  }

  // 实现 BookmarkModelObserver 协议的方法，书签节点被从文件夹中删除
  func bookmarkNodeDeleted(_ node: BookmarkNode, fromFolder folder: BookmarkNode) {
    self.listener(.nodeDeleted(node, folder))
  }

  // 实现 BookmarkModelObserver 协议的方法，所有节点被移除
  func bookmarkModelRemovedAllNodes() {
    self.listener(.allRemoved)
  }
}
