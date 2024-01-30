// 此源代码表单受 Mozilla Public License, v. 2.0 的条款约束。
// 如果此文件未随附 MPL，则可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import BraveCore
import BraveShared
import BraveUI
import Foundation
import Preferences
import Shared
import Static

// NTPTableViewController 类，继承自 TableViewController
class NTPTableViewController: TableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    // 定义枚举，表示背景图片类型
    enum BackgroundImageType: RepresentableOptionType {
        case defaultImages
        case sponsored
        case superReferrer(String)

        // 枚举类型对应的键
        var key: String {
            displayString
        }

        // 显示用字符串
        public var displayString: String {
            switch self {
            case .defaultImages: return "\(Strings.NTP.settingsDefaultImagesOnly)"
            case .sponsored: return Strings.NTP.settingsSponsoredImagesSelection
            case .superReferrer(let referrer): return referrer
            }
        }
    }

    // 初始化方法
    init() {
        super.init(style: .insetGrouped)
    }

    // 不可用的初始化方法，标记为不可用
    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    // 视图加载完成
    override func viewDidLoad() {
        super.viewDidLoad()

        // 隐藏不必要的空行
        tableView.tableFooterView = UIView()

        // 设置导航栏标题
        navigationItem.title = Strings.Home.homePage
        tableView.accessibilityIdentifier = "NewTabPageSettings.tableView"

        // 加载配置项
        loadSections()

        // 监听 NewTabPage 背景图片的变化
        Preferences.NewTabPage.backgroundImages.observe(from: self)
    }

    // 加载配置项的私有方法
    private func loadSections() {
        // 背景图片配置项
//        var imageSection = Section(
//            header: .title(Strings.NTP.settingsBackgroundImages.uppercased()),
//            rows: [
//                .boolRow(
//                    title: Strings.NTP.settingsBackgroundImages,
//                    option: Preferences.NewTabPage.backgroundImages)
//            ])
//
//        // 如果开启了背景图片，则添加相关设置
//        if Preferences.NewTabPage.backgroundImages.value {
//            imageSection.rows.append(backgroundImagesSetting(section: imageSection))
//        }
        var imageSection = Section(
            header: .title(Strings.NTP.settingsBackgroundImages.uppercased()),
            rows: [
            ])

        imageSection.rows.append(Row(
            text: Strings.NTP.settingsBackgroundImages,
            selection: { [unowned self] in
                openPhotoLibrary()
            },
            image: UIImage(braveSystemNamed: "leo.window.tab-new")))
        
        if Preferences.NewTabPage.backgroundImages.value {
            imageSection.rows.append(Row(
                text: Strings.cancelButtonTitle,
                selection: { [unowned self] in
                 //   Preferences.NewTabPage.lastSelectedImagePath.value = ""
                    Preferences.NewTabPage.backgroundImages.value = false
                    loadSections()
                }))
        }

        // 小部件配置项
        let widgetSection = Section(
            header: .title(Strings.Widgets.widgetTitle.uppercased()),
            rows: [
                //        .boolRow(
//          title: Strings.PrivacyHub.privacyReportsTitle,
//          option: Preferences.NewTabPage.showNewTabPrivacyHub),
                .boolRow(
                    title: Strings.Widgets.favoritesWidgetTitle,
                    option: Preferences.NewTabPage.showNewTabFavourites)
            ])

        // 设置数据源的部分为背景图片和小部件
        dataSource.sections = [imageSection, widgetSection]
    }

    // MARK: - Actions

    private func openPhotoLibrary() {
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .photoLibrary
        imagePicker.delegate = self
        present(imagePicker, animated: true, completion: nil)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true, completion: nil)
        if let imageURL = info[.imageURL] as? URL {
                // 获取应用沙盒目录
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

                // 创建一个目标路径，将图片保存到应用沙盒中
                let destinationPath = documentsDirectory.appendingPathComponent("selectedImage.jpg")
            // 检查是否存在同名文件，如果存在则删除
                 if FileManager.default.fileExists(atPath: destinationPath.path) {
                     do { 
                         try FileManager.default.removeItem(at: destinationPath)
                     } catch {
                         // 删除文件时发生错误
                         print("Error deleting existing file: \(error.localizedDescription)")
                     }
                 }
                do {
                    // 将选取的图片复制到应用沙盒目录
                    try FileManager.default.copyItem(at: imageURL, to: destinationPath)

                    // 保存选取的图片路径到UserDefaults
                    saveSelectedImagePath(imagePath: destinationPath.path)

                    // 显示选取的图片
                    // displayImage(atPath: destinationPath.path)
                } catch {
                    // 复制文件时发生错误
                    print("Error copying file: \(error.localizedDescription)")
                }
            }
    }

    func saveSelectedImagePath(imagePath: String) {
        Preferences.NewTabPage.backgroundImages.value = true

        if let image = UIImage(contentsOfFile: imagePath) {
            let width = image.size.width
            let height = image.size.height
            if let hexStringTop = image[3, 3] {
                Preferences.NewTabPage.imagesTopColor.value = hexStringTop.isLight
            }
            if let hexStringCenter = image[Int(width)/2, Int(height)/2] {
                Preferences.NewTabPage.imagesCenterColor.value = hexStringCenter.isLight
            }
            if let hexStringCenter = image[3, Int(height) - 3] {
                Preferences.NewTabPage.imagesBottomColor.value = hexStringCenter.isLight
            }
        } else {
            print("无法加载图片")
        }
        loadSections()
    }

    // 获取当前选定的背景图片类型
    private func selectedItem() -> BackgroundImageType {
        if let referrer = Preferences.NewTabPage.selectedCustomTheme.value {
            return .superReferrer(referrer)
        }

        return Preferences.NewTabPage.backgroundSponsoredImages.value ? .sponsored : .defaultImages
    }

    // 惰性加载背景图片选项的数组
    private lazy var backgroundImageOptions: [BackgroundImageType] = {
        var available: [BackgroundImageType] = [.defaultImages, .sponsored]
        available += Preferences.NewTabPage.installedCustomThemes.value.map {
            .superReferrer($0)
        }
        return available
    }()

    // 创建背景图片设置的行
    private func backgroundImagesSetting(section: Section) -> Row {
        var row = Row(
            text: Strings.NTP.settingsBackgroundImageSubMenu,
            detailText: selectedItem().displayString,
            accessory: .disclosureIndicator,
            cellClass: Value1Cell.self)

        row.selection = { [unowned self] in
            // 显示选项以控制选项卡栏的可见性
            let optionsViewController = OptionSelectionViewController<BackgroundImageType>(
                headerText: Strings.NTP.settingsBackgroundImageSubMenu,
                footerText: Strings.NTP.imageTypeSelectionDescription,
                style: .insetGrouped,
                options: self.backgroundImageOptions,
                selectedOption: self.selectedItem(),
                optionChanged: { _, option in
                    // 在可能的情况下应该关闭此选项，以防止不必要的资源下载
                    Preferences.NewTabPage.backgroundSponsoredImages.value = option == .sponsored

                    if case .superReferrer(let referrer) = option {
                        Preferences.NewTabPage.selectedCustomTheme.value = referrer
                    } else {
                        Preferences.NewTabPage.selectedCustomTheme.value = nil
                    }

                    // 重新加载单元格以更新显示文本
                    self.dataSource.reloadCell(row: row, section: section, displayText: option.displayString)
                })
            optionsViewController.navigationItem.title = Strings.NTP.settingsBackgroundImageSubMenu
            self.navigationController?.pushViewController(optionsViewController, animated: true)
        }
        return row
    }
}

// 扩展 NTPTableViewController，实现 PreferencesObserver 协议
extension NTPTableViewController: PreferencesObserver {
    func preferencesDidChange(for key: String) {
        // 配置项发生变化时重新加载配置
        loadSections()
    }
}
