// 版权声明
// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// 导入所需的库
import Foundation
import BraveUI
import Preferences
import Data
import CoreData
import Shared
import UIKit
import os.log

// 书签操作的枚举
enum BookmarksAction {
  case opened(inNewTab: Bool = false, switchingToPrivateMode: Bool = false)
  case edited
}

// 收藏夹提供者类，用于提供收藏夹的数据给界面展示
class FavoritesSectionProvider: NSObject, NTPObservableSectionProvider {
  
  // Section改变时的回调闭包
  var sectionDidChange: (() -> Void)?
  
  // 处理书签操作的闭包
  var action: (Favorite, BookmarksAction) -> Void
  
  // 处理旧的长按动作的闭包
  var legacyLongPressAction: (UIAlertController) -> Void
  
  // 是否处于私密浏览模式
  private let isPrivateBrowsing: Bool

  // 是否有多个收藏项
  var hasMoreThanOneFavouriteItems: Bool {
    frc.fetchedObjects?.count ?? 0 > 0
  }

  // 收藏夹的核心数据控制器
  private var frc: NSFetchedResultsController<Favorite>

  // 初始化方法
  init(
    action: @escaping (Favorite, BookmarksAction) -> Void,
    legacyLongPressAction: @escaping (UIAlertController) -> Void,
    isPrivateBrowsing: Bool
  ) {
    self.action = action
    self.legacyLongPressAction = legacyLongPressAction
    self.isPrivateBrowsing = isPrivateBrowsing

    frc = Favorite.frc()
    super.init()
    frc.fetchRequest.fetchLimit = 20
    frc.delegate = self

    do {
      try frc.performFetch()
    } catch {
      Logger.module.error("Favorites fetch error")
    }
  }

  // 默认图标大小
  static var defaultIconSize = CGSize(width: 62, height: FavoriteCell.height(forWidth: 62))
  
  // 更大图标大小
  static var largerIconSize = CGSize(width: 100, height: FavoriteCell.height(forWidth: 100))

  /// 每行包含的图标数量
  static func numberOfItems(in collectionView: UICollectionView, availableWidth: CGFloat) -> Int {
    // 两个考虑因素:
    // 1. 图标大小的最小值
    // 2. 特性集合
    // 3. 方向 ("is landscape")
    let icons = (min: 4, max: 6)
    let defaultWidth: CGFloat = defaultIconSize.width
    let fittingNumber: Int

    if collectionView.traitCollection.horizontalSizeClass == .regular {
      if collectionView.frame.width > collectionView.frame.height {
        fittingNumber = Int(floor(availableWidth / defaultWidth))
      } else {
        fittingNumber = Int(floor(availableWidth / largerIconSize.width))
      }
    } else {
      fittingNumber = Int(floor(availableWidth / defaultWidth))
    }

    return max(icons.min, min(icons.max, fittingNumber))
  }

  // 注册单元格
  func registerCells(to collectionView: UICollectionView) {
    collectionView.register(FavoriteCell.self, forCellWithReuseIdentifier: FavoriteCell.identifier)
  }

  // 点击单元格时调用的方法
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard let bookmark = frc.fetchedObjects?[safe: indexPath.item] else {
      return
    }
    action(bookmark, .opened())
  }

  // 单元格数量
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    let fetchedCount = frc.fetchedObjects?.count ?? 0
    let lineNum = Self.numberOfItems(
        in: collectionView,
        availableWidth: fittingSizeForCollectionView(collectionView, section: section).width)
    let h =  UIScreen.main.bounds.width <= 375 ? 2 : 3
    let numberOfItems = min(fetchedCount, h*lineNum)
    return Preferences.NewTabPage.showNewTabFavourites.value ? numberOfItems : 0
  }

  // 配置单元格
  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    return collectionView.dequeueReusableCell(withReuseIdentifier: FavoriteCell.identifier, for: indexPath)
  }

  // 单元格将要显示时调用的方法
  func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {

    guard let cell = cell as? FavoriteCell else {
      return
    }

    let fav = frc.object(at: IndexPath(item: indexPath.item, section: 0))
    cell.textLabel.textColor = UIColor(named: "Color_txt", in: .module, compatibleWith: nil)
    cell.textLabel.text = fav.displayTitle ?? fav.url

    // 重置Fav图标的加载和图像视图为默认值
    cell.imageView.cancelLoading()
    cell.textLabel.lineBreakMode = .byCharWrapping

    if let url = fav.url?.asURL {
      cell.imageView.loadFavicon(siteURL: url, isPrivateBrowsing: isPrivateBrowsing)
    }
    cell.accessibilityLabel = cell.textLabel.text
  }

  // 单元格的大小
  private func itemSize(collectionView: UICollectionView, section: Int) -> CGSize {
    let width = fittingSizeForCollectionView(collectionView, section: section).width
    var size = Self.defaultIconSize

    let minimumNumberOfColumns = Self.numberOfItems(in: collectionView, availableWidth: width)
    let minWidth = floor(width / CGFloat(minimumNumberOfColumns))
    if minWidth < size.width {
      // 如果默认图标大小太大，使其稍微小一些以适应至少4个图标
      size = CGSize(width: floor(width / 4.0), height: FavoriteCell.height(forWidth: floor(width / 4.0)))
    } else if collectionView.traitCollection.horizontalSizeClass == .regular {
      // 如果我们在常规的水平尺寸类上，且计算出的图标大小大于`largerIconSize`，则使用`largerIconSize`
      if width / CGFloat(minimumNumberOfColumns) > Self.largerIconSize.width {
        size = Self.largerIconSize
      }
    }
    return size
  }

  // 单元格的大小代理方法
  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    return itemSize(collectionView: collectionView, section: indexPath.section)
  }

  // 单元格边距代理方法
  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
    let isLandscape = collectionView.frame.width > collectionView.frame.height
    // 调整左侧边距以适应纵向iPad
      //collectionView.readableContentGuide.layoutFrame.origin.x
    let inset = isLandscape ? 12 : 31
      return UIEdgeInsets(top: 6, left: CGFloat(inset), bottom: 6, right: CGFloat(inset))
  }

  // 单元格之间的最小间距代理方法
  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
    let width = fittingSizeForCollectionView(collectionView, section: section).width
    let size = itemSize(collectionView: collectionView, section: section)
    let numberOfItems = Self.numberOfItems(in: collectionView, availableWidth: width)

    return floor((width - (size.width * CGFloat(numberOfItems))) / (CGFloat(numberOfItems) - 1))
  }

  // 上下文菜单配置代理方法
  func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
    guard let favourite = frc.fetchedObjects?[indexPath.item] else { return nil }
    return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { _ -> UIMenu? in
      let openInNewTab = UIAction(
        title: Strings.openNewTabButtonTitle,
        handler: UIAction.deferredActionHandler { _ in
          self.action(favourite, .opened(inNewTab: true, switchingToPrivateMode: false))
        })
      let edit = UIAction(
        title: Strings.editFavorite,
        handler: UIAction.deferredActionHandler { _ in
          self.action(favourite, .edited)
        })
      let delete = UIAction(
        title: Strings.removeFavorite, attributes: .destructive,
        handler: UIAction.deferredActionHandler { _ in
          favourite.delete()
        })

      var urlChildren: [UIAction] = [openInNewTab]
      if !self.isPrivateBrowsing {
        let openInNewPrivateTab = UIAction(
          title: Strings.openNewPrivateTabButtonTitle,
          handler: UIAction.deferredActionHandler { _ in
            self.action(favourite, .opened(inNewTab: true, switchingToPrivateMode: true))
          })
        urlChildren.append(openInNewPrivateTab)
      }

      let urlMenu = UIMenu(title: "", options: .displayInline, children: urlChildren)
      let favMenu = UIMenu(title: "", options: .displayInline, children: [edit, delete])
      return UIMenu(title: favourite.title ?? favourite.url ?? "", identifier: nil, children: [urlMenu, favMenu])
    }
  }

  // 高亮上下文菜单时的预览方法
  func collectionView(_ collectionView: UICollectionView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
    guard let indexPath = configuration.identifier as? IndexPath,
      let cell = collectionView.cellForItem(at: indexPath) as? FavoriteCell
    else {
      return nil
    }
    return UITargetedPreview(view: cell.imageView)
  }

  // 取消上下文菜单时的预览方法
  func collectionView(_ collectionView: UICollectionView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
    guard let indexPath = configuration.identifier as? IndexPath,
      let cell = collectionView.cellForItem(at: indexPath) as? FavoriteCell
    else {
      return nil
    }
    return UITargetedPreview(view: cell.imageView)
  }
}

// NSFetchedResultsControllerDelegate协议的扩展
extension FavoritesSectionProvider: NSFetchedResultsControllerDelegate {
  func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
    try? frc.performFetch()
    DispatchQueue.main.async {
      self.sectionDidChange?()
    }
  }
}
