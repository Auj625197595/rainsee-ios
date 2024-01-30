// 版权声明
// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import BraveUI
import Preferences
import Data
import CoreData
import Shared
import UIKit

// FavoritesOverflowButton 类: 继承自 SpringButton 类
class FavoritesOverflowButton: SpringButton {
  
  // 背景视图，采用轻量级模糊效果
  private let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .light)).then {
    $0.clipsToBounds = true
    $0.isUserInteractionEnabled = false
  }

  // 初始化方法
  override init(frame: CGRect) {
    super.init(frame: frame)

    // 创建标签，显示 "显示更多收藏"
    let label = UILabel().then {
      $0.text = Strings.NTP.showMoreFavorites
      $0.textColor = .white
      $0.font = UIFont.systemFont(ofSize: 12.0, weight: .medium)
    }

    // 设置背景视图的圆角
    backgroundView.layer.cornerCurve = .continuous

    // 将子视图添加到父视图
    addSubview(backgroundView)
    backgroundView.contentView.addSubview(label)

    // 设置约束
    backgroundView.snp.makeConstraints {
      $0.edges.equalToSuperview()
    }
    label.snp.makeConstraints {
      $0.edges.equalToSuperview().inset(UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10))
    }
  }

  // 重写布局方法
  override func layoutSubviews() {
    super.layoutSubviews()
    backgroundView.layer.cornerRadius = bounds.height / 2.0  // 胶囊形状
  }
}

// FavoritesOverflowSectionProvider 类: NSObject 和 NTPObservableSectionProvider 协议
class FavoritesOverflowSectionProvider: NSObject, NTPObservableSectionProvider {
  
  // 点击按钮触发的动作
  let action: () -> Void
  var sectionDidChange: (() -> Void)?

  // FavoritesOverflowCell 别名
  private typealias FavoritesOverflowCell = NewTabCenteredCollectionViewCell<FavoritesOverflowButton>

  // NSFetchedResultsController 用于管理 Favorite 实体
  private var frc: NSFetchedResultsController<Favorite>

  // 初始化方法
  init(action: @escaping () -> Void) {
    self.action = action
    frc = Favorite.frc()
    frc.fetchRequest.fetchLimit = 20
    super.init()
    try? frc.performFetch()
    frc.delegate = self
  }

  // 按钮点击事件
  @objc private func tappedButton() {
    action()
  }

  // 集合视图的数据源方法

  // 返回节(section)中的单元格数量
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    let width = fittingSizeForCollectionView(collectionView, section: section).width
    let count = frc.fetchedObjects?.count ?? 0
    
    // 检查是否显示 "显示更多" 按钮
    let isShowShowMoreButtonVisible = count > FavoritesSectionProvider.numberOfItems(in: collectionView, availableWidth: width)*3 &&
      Preferences.NewTabPage.showNewTabFavourites.value
    return isShowShowMoreButtonVisible ? 1 : 0
  }

  // 注册单元格
  func registerCells(to collectionView: UICollectionView) {
    collectionView.register(FavoritesOverflowCell.self)
  }

  // 返回单元格
  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(for: indexPath) as FavoritesOverflowCell
    cell.view.addTarget(self, action: #selector(tappedButton), for: .touchUpInside)
    return cell
  }

  // 返回单元格大小
  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    var size = fittingSizeForCollectionView(collectionView, section: indexPath.section)
    size.height = 24
    return size
  }

  // 返回节的内边距
  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    insetForSectionAt section: Int
  ) -> UIEdgeInsets { .zero }
}

// 扩展 FavoritesOverflowSectionProvider 类，实现 NSFetchedResultsControllerDelegate 协议
extension FavoritesOverflowSectionProvider: NSFetchedResultsControllerDelegate {
  
  // 当控制器的内容发生变化时调用
  func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
    try? frc.performFetch()
    DispatchQueue.main.async {
      self.sectionDidChange?()
    }
  }
}
