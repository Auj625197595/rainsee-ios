// 版权声明
// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import BraveUI
import UIKit

// 空白单元格类
private class EmptyCollectionViewCell: UICollectionViewCell, CollectionViewReusable {
}

// FlexibleSpaceSectionProvider 类: NSObject 和 NTPSectionProvider 协议
class FlexibleSpaceSectionProvider: NSObject, NTPSectionProvider {
  
  // 注册单元格
  func registerCells(to collectionView: UICollectionView) {
    collectionView.register(EmptyCollectionViewCell.self)
  }

  // 返回节(section)中的单元格数量
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    return 1
  }

  // 返回单元格
  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    return collectionView.dequeueReusableCell(for: indexPath) as EmptyCollectionViewCell
  }
}
