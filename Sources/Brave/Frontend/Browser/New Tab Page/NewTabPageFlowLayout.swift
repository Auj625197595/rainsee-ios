// 版权 2020 Brave Authors。保留所有权利。
// 本源代码表单受 Mozilla Public License，版本 2.0 的条款约束。
// 如果未随此文件分发 MPL 的副本，则可以在 http://mozilla.org/MPL/2.0/ 处获得一份。

import Foundation
import UIKit

/// 新标签页集合视图布局
///
/// 处理在使用自动调整大小的单元格时，纠正流布局中居中对齐的单个项
class NewTabPageFlowLayout: UICollectionViewFlowLayout {
  /// 勇敢新闻部分的行为略有不同，尽管有空间，它被推到屏幕底部，因此在启用勇敢新闻时必须为整体内容大小提供额外空间
  var braveNewsSection: Int? {
    didSet {
      invalidateLayout()
    }
  }

  override init() {
    super.init()
    estimatedItemSize = Self.automaticSize
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }

  private var gapLength: CGFloat = 0.0
  private var extraHeight: CGFloat = 0.0
  private let gapPadding: CGFloat = 32.0

  override func prepare() {
    super.prepare()
    if let braveNewsSection = braveNewsSection,
      let collectionView = collectionView,
      collectionView.numberOfItems(inSection: braveNewsSection) != 0,
      let attribute = super.layoutAttributesForItem(at: IndexPath(item: 0, section: braveNewsSection)) {
      let diff = collectionView.frame.height - attribute.frame.minY
      gapLength = diff - gapPadding

      // 获取勇敢新闻部分的总高度，以计算要添加的任何额外高度
      // 到内容大小。额外的高度将确保始终有足够的空间来滚动
      // 标头完全可见
      let numberOfItems = collectionView.numberOfItems(inSection: braveNewsSection)
      if let lastItemAttribute = super.layoutAttributesForItem(at: IndexPath(item: numberOfItems - 1, section: braveNewsSection)) {
        if lastItemAttribute.frame.maxY - attribute.frame.minY < collectionView.bounds.height - gapPadding {
          extraHeight = (collectionView.bounds.height - gapPadding) - (lastItemAttribute.frame.maxY - attribute.frame.minY)
        }
      }

      lastSizedElementMinY = nil
      lastSizedElementPreferredHeight = nil
    }
  }

  override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
    guard let attribute = super.layoutAttributesForItem(at: indexPath)?.copy() as? UICollectionViewLayoutAttributes,
      let collectionView = collectionView
    else {
      return nil
    }

    if attribute.representedElementCategory != .cell {
      return attribute
    }

    // 如果只有一个项目，则左对齐单元格，因为它们会自动居中
    // 1部分中有1个项目，并使用automaticSize...
    if estimatedItemSize == UICollectionViewFlowLayout.automaticSize {
      let indexPath = attribute.indexPath
      if collectionView.numberOfItems(inSection: indexPath.section) == 1 {
        // 获取每个单元格适当布局的部分插入/间距
        let sectionInset: UIEdgeInsets
        let minimumInteritemSpacing: CGFloat
        if let flowLayoutDelegate = collectionView.delegate as? UICollectionViewDelegateFlowLayout {
          // 如果布局有一个委托来获取部分特定的信息
          // 信息，获取它
          sectionInset = flowLayoutDelegate.collectionView?(collectionView, layout: self, insetForSectionAt: indexPath.section) ?? self.sectionInset
          minimumInteritemSpacing = flowLayoutDelegate.collectionView?(collectionView, layout: self, minimumInteritemSpacingForSectionAt: indexPath.section) ?? self.minimumInteritemSpacing
        } else {
          // 否则默认为布局本身定义的全局值
          sectionInset = self.sectionInset
          minimumInteritemSpacing = self.minimumInteritemSpacing
        }
        // 将第一项在部分中布局到最左边
        if attribute.indexPath.item == 0 {
          attribute.frame.origin.x = sectionInset.left
        } else {
          // 否则基于前一个项目的原点布局
          if let previousItemAttribute = layoutAttributesForItem(at: IndexPath(item: indexPath.item - 1, section: indexPath.section)) {
            attribute.frame.origin.x = previousItemAttribute.frame.maxX + minimumInteritemSpacing
          }
        }
      }
    }

    if let section = braveNewsSection, indexPath.section == section {
      attribute.frame.origin.y += gapLength
    }

    return attribute
  }

  override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
    var adjustedRect = rect
    adjustedRect.origin.y -= gapLength
    adjustedRect.size.height += gapLength * 2
    guard let attributes = super.layoutAttributesForElements(in: adjustedRect) else {
      return nil
    }
    for attribute in attributes where attribute.representedElementCategory == .cell {
      if let frame = self.layoutAttributesForItem(at: attribute.indexPath)?.frame {
        attribute.frame = frame
      }
    }
    return attributes
  }

  override var collectionViewContentSize: CGSize {
    var size = super.collectionViewContentSize
    if braveNewsSection != nil {
      size.height += gapLength + extraHeight
    }
    return size
  }

  override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
    guard let section = braveNewsSection,
      collectionView?.numberOfItems(inSection: section) != 0,
      let item = layoutAttributesForItem(at: IndexPath(item: 0, section: section))
    else {
      return proposedContentOffset
    }
    var offset = proposedContentOffset
    let flicked = abs(velocity.y) > 0.3
    if (offset.y > item.frame.minY / 2 && offset.y < item.frame.minY) || (flicked && velocity.y > 0 && offset.y < item.frame.minY) {
      offset.y = item.frame.minY - 56  // FIXME: 使用标题的大小 + 填充
    } else if offset.y < item.frame.minY {
      offset.y = 0
    }
    return offset
  }

  override func shouldInvalidateLayout(
    forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
    withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
  ) -> Bool {
    if let section = braveNewsSection,
      preferredAttributes.representedElementCategory == .cell,
      preferredAttributes.indexPath.section == section {
      return preferredAttributes.size.height.rounded() != originalAttributes.size.height.rounded()
    }
    return super.shouldInvalidateLayout(
      forPreferredLayoutAttributes: preferredAttributes,
      withOriginalAttributes: originalAttributes
    )
  }

  override func invalidationContext(
    forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
    withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
  ) -> UICollectionViewLayoutInvalidationContext {
    let context = super.invalidationContext(
      forPreferredLayoutAttributes: preferredAttributes,
      withOriginalAttributes: originalAttributes
    )

    guard let collectionView = collectionView, let _ = braveNewsSection else {
      return context
    }

    // 感谢 Bryan Keller 在此`airbnb/MagazineLayout` PR 中找到的解决方案：
    // https://github.com/airbnb/MagazineLayout/pull/11/files
    //
    // 原始评论：
    // 如果在当前滚动位置之上丢弃布局信息（例如，旋转时），我们需要补偿
    // 因为我们正在向上滚动，因此调整对于正在上移的元素的首选大小的变化，否则
    // 每次调整元素大小时，集合视图都会出现跳跃。
    // 由于在同一行上可能对多个项目进行调整大小，因此我们需要考虑到这一点
    // 通过考虑先前调整大小的相同行中的先前调整大小元素的首选高度
    // 这样，我们只需调整内容偏移以创建平滑滚动的确切量。
    let currentElementY = originalAttributes.frame.minY
    let isScrolling = collectionView.isDragging || collectionView.isDecelerating
    let isSizingElementAboveTopEdge = originalAttributes.frame.minY < collectionView.contentOffset.y

    if isScrolling && isSizingElementAboveTopEdge {
      let isSameRowAsLastSizedElement = lastSizedElementMinY == currentElementY
      if isSameRowAsLastSizedElement {
        let lastSizedElementPreferredHeight = self.lastSizedElementPreferredHeight ?? 0
        if preferredAttributes.size.height > lastSizedElementPreferredHeight {
          context.contentOffsetAdjustment.y = preferredAttributes.size.height - lastSizedElementPreferredHeight
        }
      } else {
        context.contentOffsetAdjustment.y = preferredAttributes.size.height - originalAttributes.size.height
      }
    }

    lastSizedElementMinY = currentElementY
    lastSizedElementPreferredHeight = preferredAttributes.size.height

    return context
  }

  private var lastSizedElementMinY: CGFloat?
  private var lastSizedElementPreferredHeight: CGFloat?
}
