// HomeTopIconProvider 类: NSObject 和 NTPObservableSectionProvider 协议

import BraveCore
import BraveNews
import BraveUI
import DesignSystem
import Foundation
import Growth
import Preferences
import Shared

class HomeTopIconProvider: NSObject, NTPSectionProvider {
    // 点击按钮触发的动作
    let action: (String) -> Void
    // 初始化方法
    init(action: @escaping (String) -> Void) {
        self.action = action
        super.init()
    }
    
    

    var sectionDidChange: (() -> Void)?

    // 集合视图的数据源方法

    // 返回节(section)中的单元格数量
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 1
    }

    // 注册单元格
    func registerCells(to collectionView: UICollectionView) {
        collectionView.register(IconSearchCell<IconSearchView>.self)
    }

    // 返回单元格
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(for: indexPath) as IconSearchCell<IconSearchView> // 替换为你自定义的单元格类型
        cell.view.action = { [weak self] parameter in
                 // Trigger the action inside IconSearchView with the provided parameter
                 self?.action(parameter)
             }
        return cell
    }

    // 返回单元格大小
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        // 返回你的单元格大小，根据你的布局需求进行调整
        // collectionView.bounds.width
        let h =  UIScreen.main.bounds.width <= 375 ? 290 : 340
        
        return CGSize(width: collectionView.bounds.width,
                      height: UIDevice.current.userInterfaceIdiom == .pad ? 40 : CGFloat(h))
    }

    // 返回节的内边距
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets { .zero }
    
    
//    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
//      // 调整左侧边距以适应纵向iPad
//        //collectionView.readableContentGuide.layoutFrame.origin.x
//        return UIEdgeInsets(top: 0, left: CGFloat(50), bottom: 6, right: CGFloat(50))
//    }

}
