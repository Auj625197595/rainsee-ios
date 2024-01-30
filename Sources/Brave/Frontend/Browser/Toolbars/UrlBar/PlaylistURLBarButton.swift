// 版权声明
// 2021年，Brave作者版权所有。
// 本源代码形式受 Mozilla Public License, v. 2.0 许可的条款约束。
// 如果未随此文件分发MPL的副本，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import UIKit
import DesignSystem
import SnapKit
import Data
import BraveStrings

// 自定义类，继承自UIButton，用于处理播放列表URL按钮
class PlaylistURLBarButton: UIButton {
    // 定义枚举表示按钮的状态
    enum State: Equatable {
        case addToPlaylist
        case addedToPlaylist(PlaylistInfo?)
        case none
    }
    
    // 定义菜单动作
    enum MenuAction {
        case openInPlaylist
        case changeFolders
        case remove
        case undoRemove(originalFolderUUID: String?)
    }
    
    // 处理菜单动作的回调
    var menuActionHandler: ((MenuAction) -> Void)?
    
    // 根据标题、图像和处理程序创建菜单元素
    private func menuSwappingAction(
        title: String,
        image: UIImage?,
        attributes: UIMenuElement.Attributes = [],
        handler: @escaping () -> UIMenu
    ) -> UIAction {
        let action: UIAction
        if #available(iOS 16.0, *) {
            action = UIAction(title: title, image: image, attributes: attributes.union(.keepsMenuPresented), handler: { _ in
                let menu = handler()
                self.menu = menu
            })
        } else {
            action = UIAction(title: title, image: image, attributes: attributes, handler: UIAction.deferredActionHandler { _ in
                let menu = handler()
                self.menu = menu
                self.contextMenuInteraction?.perform(Selector("_presentMenuAtLocation:"), with: CGPoint.zero)
            })
        }
        return action
    }
    
    // 创建默认菜单
    private func defaultMenu(for info: PlaylistInfo?) -> UIMenu {
        return UIMenu(title: "", image: nil, identifier: nil, options: [], children: [
            UIDeferredMenuElement.uncached { handler in
                let item = info.flatMap { PlaylistItem.getItem(uuid: $0.tagId) }
                handler([
                    UIAction(
                        title: String.localizedStringWithFormat(Strings.PlayList.addedToPlaylistMessage, item?.playlistFolder?.title ?? "Playlist"),
                        image: UIImage(braveSystemNamed: "leo.check.circle-filled")?.withTintColor(.braveSuccessLabel).withRenderingMode(.alwaysOriginal),
                        attributes: .disabled,
                        handler: { _ in }
                    ),
                ])
            },
            UIMenu(title: "", subtitle: nil, image: nil, identifier: nil, options: .displayInline, children: [
                UIAction(title: Strings.PlayList.openInPlaylistButtonTitle, image: UIImage(braveSystemNamed: "leo.product.playlist"), handler: { _ in
                    self.menuActionHandler?(.openInPlaylist)
                }),
                UIAction(title: Strings.PlayList.changeFoldersButtonTitle, image: UIImage(braveSystemNamed: "leo.folder.exchange"), handler: { _ in
                    self.menuActionHandler?(.changeFolders)
                }),
                menuSwappingAction(title: Strings.PlayList.removeActionButtonTitle, image: UIImage(braveSystemNamed: "leo.trash"), attributes: .destructive, handler: {
                    // 从播放列表中移除？
                    self.menuActionHandler?(.remove)
                    return self.deletedMenu(for: info)
                })
            ])
        ])
    }
    
    // 创建已删除菜单
    private func deletedMenu(for info: PlaylistInfo?) -> UIMenu {
        return UIMenu(title: "", image: nil, identifier: nil, options: [], children: [
            UIDeferredMenuElement.uncached { handler in
                let item = info.flatMap { PlaylistItem.getItem(uuid: $0.tagId) }
                let folderUUID = item?.playlistFolder?.uuid
                handler([
                    UIAction(
                        title: String.localizedStringWithFormat(Strings.PlayList.removedFromPlaylistMessage, item?.playlistFolder?.title ?? "Playlist"),
                        image: UIImage(braveSystemNamed: "leo.check.circle-filled")?.withTintColor(.braveSuccessLabel).withRenderingMode(.alwaysOriginal),
                        attributes: .disabled,
                        handler: { _ in }
                    ),
                    UIMenu(title: "", subtitle: nil, image: nil, identifier: nil, options: .displayInline, children: [
                        self.menuSwappingAction(title: Strings.PlayList.undoRemoveButtonTitle, image: UIImage(braveSystemNamed: "leo.arrow.back"), handler: {
                            // 重新添加到播放列表
                            self.menuActionHandler?(.undoRemove(originalFolderUUID: folderUUID))
                            return self.defaultMenu(for: info)
                        })
                    ])
                ])
            },
        ])
    }

    // 按钮状态，设置不同状态下的图标、文本和菜单
    var buttonState: State = .none {
        didSet {
            switch buttonState {
            case .addToPlaylist:
                accessibilityLabel = Strings.tabToolbarAddToPlaylistButtonAccessibilityLabel
                setImage(UIImage(sharedNamed: "leo.playlist.bold.add"), for: .normal)
                showsMenuAsPrimaryAction = false
                // 如果从已添加到播放列表的状态切换，不隐藏菜单
                if case .addedToPlaylist = oldValue {
                } else {
                    menu = nil
                }
            case .addedToPlaylist(let item):
                accessibilityLabel = Strings.tabToolbarPlaylistButtonAccessibilityLabel
                setImage(UIImage(sharedNamed: "leo.playlist.bold.added"), for: .normal)
                showsMenuAsPrimaryAction = true
                menu = defaultMenu(for: item)
            case .none:
                setImage(nil, for: .normal)
            }
            updateForTraitCollection()
        }
    }
    
    // 构造函数
    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView?.contentMode = .scaleAspectFit
        imageView?.adjustsImageSizeForAccessibilityContentSizeCategory = true
        
        updateForTraitCollection()
    }
    
    // 必要的初始化方法
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // 处理屏幕适配变化
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateForTraitCollection()
    }
    
    // 更新图标尺寸以适应屏幕适配
    private func updateForTraitCollection() {
        let sizeCategory = traitCollection.toolbarButtonContentSizeCategory
        let pointSize = UIFont.preferredFont(
            forTextStyle: .body,
            compatibleWith: .init(preferredContentSizeCategory: sizeCategory)
        ).pointSize
        if let size = imageView?.image?.size {
            // 缩放PDF，使其与SF符号相同
            let scale = (pointSize / UIFont.preferredFont(forTextStyle: .body, compatibleWith: .init(preferredContentSizeCategory: .large)).pointSize)
            imageView?.snp.remakeConstraints {
                $0.width.equalTo(size.width * scale)
                $0.height.equalTo(size.height * scale)
                $0.center.equalToSuperview()
            }
        }
    }
}
