/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import CoreData
import Shared
import Storage
import Data
import UIKit

/// 与收藏夹管理相关的一组方法。大多数只是对Bookmark模型的包装。
struct FavoritesHelper {
  // 表示是否已初始化收藏夹。
  static let initPrefsKey = "FavoritesHelperInitPrefsKey"

  // MARK: - 收藏夹初始化
  static func addDefaultFavorites() {
    // 从预加载的收藏夹列表添加默认收藏项。
    Favorite.add(from: PreloadedFavorites.getList())
  }

  static func convertToBookmarks(_ sites: [Site]) {
    // 将一组站点转换为书签。
    sites.forEach { site in
      if let url = URL(string: site.url) {
        // 如果站点URL有效，将其添加为收藏夹。
        Favorite.add(url: url, title: url.normalizedHost() ?? site.url)
      }
    }
  }

  static func add(url: URL, title: String?) {
    // 将指定URL和标题添加为收藏夹。
    Favorite.add(url: url, title: title)
  }

  static func isAlreadyAdded(_ url: URL) -> Bool {
    // 检查指定URL是否已经添加到收藏夹。
    return Favorite.contains(url: url)
  }

  static func fallbackIcon(withLetter letter: String, color: UIColor, andSize iconSize: CGSize) -> UIImage {
    // 创建带有字母的备用图标，使用指定的颜色和大小。
    let renderer = UIGraphicsImageRenderer(size: iconSize)
    return renderer.image { ctx in
      let rectangle = CGRect(x: 0, y: 0, width: iconSize.width, height: iconSize.height)

      // 绘制填充矩形。
      ctx.cgContext.addRect(rectangle)
      ctx.cgContext.setFillColor(color.cgColor)
      ctx.cgContext.drawPath(using: .fillStroke)

      let paragraphStyle = NSMutableParagraphStyle()
      paragraphStyle.alignment = .center

      // 配置字母的属性。
      let attrs = [
        NSAttributedString.Key.font: UIFont(name: "HelveticaNeue-Thin", size: iconSize.height - 90) ?? UIFont.systemFont(ofSize: iconSize.height - 90, weight: UIFont.Weight.thin),
        NSAttributedString.Key.paragraphStyle: paragraphStyle,
        NSAttributedString.Key.backgroundColor: UIColor.clear,
      ]

      let string: NSString = NSString(string: letter.uppercased())
      let size = string.size(withAttributes: attrs)
      // 在图标中央绘制字母。
      string.draw(at: CGPoint(x: (iconSize.width - size.width) / 2, y: (iconSize.height - size.height) / 2), withAttributes: attrs)
    }
  }
}
