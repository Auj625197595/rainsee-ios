// 此源代码受 Mozilla 公共许可证版本 2.0 的条款约束。
// 如果未随此文件分发 MPL 的副本，则可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Data
import Preferences
import Shared
import SnapKit
import UIKit

class BookmarkDetailsView: AddEditHeaderView, BookmarkFormFieldsProtocol {
    // MARK: - BookmarkFormFieldsProtocol

    weak var delegate: BookmarkDetailsViewDelegate?

    // 标题文本框
    let titleTextField = UITextField().then {
        $0.placeholder = Strings.bookmarkTitlePlaceholderText
        $0.clearButtonMode = .whileEditing
        $0.translatesAutoresizingMaskIntoConstraints = false
    }

    // URL 文本框
    let urlTextField: UITextField? = UITextField().then {
        $0.placeholder = Strings.bookmarkUrlPlaceholderText
        $0.keyboardType = .URL
        $0.autocorrectionType = .no
        $0.autocapitalizationType = .none
        $0.smartDashesType = .no
        $0.smartQuotesType = .no
        $0.smartInsertDeleteType = .no
        $0.clearButtonMode = .whileEditing
        $0.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - 新增的勾选按钮相关代码

    // 添加到主页收藏夹勾选按钮
    let addToHomeSwitch = UISwitch().then {
        $0.isOn = Preferences.NewTabPage.iconAddHome.value
    }

    // MARK: - 视图设置

    // 内容堆栈视图
    private let contentStackView = UIStackView().then {
        $0.spacing = UX.defaultSpacing
        $0.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        $0.alignment = .center
    }

    // Favicon 图像视图
    private let faviconImageView = LargeFaviconView().then {
        $0.snp.makeConstraints {
            $0.size.equalTo(UX.faviconSize)
        }
    }

    // 文本框堆栈视图
    private let textFieldsStackView = UIStackView().then {
        $0.axis = .vertical
        $0.spacing = UX.defaultSpacing
    }

    // 新的勾选按钮和标签的堆栈视图
    private let addToHomeStackView = UIStackView().then {
        $0.axis = .horizontal
        $0.spacing = UX.defaultSpacing
        $0.alignment = .center
    }

    // MARK: - 初始化

    convenience init(title: String?, url: String?, isPrivateBrowsing: Bool) {
        self.init(frame: .zero)

        backgroundColor = .secondaryBraveGroupedBackground

        guard let urlTextField = urlTextField else { fatalError("Url text field must be set up") }

        // 将分隔线、内容堆栈视图和分隔线添加到主堆栈视图中
        [UIView.separatorLine, contentStackView, UIView.separatorLine]
            .forEach(mainStackView.addArrangedSubview)

        // 将标题文本框、分隔线、URL 文本框添加到文本框堆栈视图中
        [titleTextField, urlTextField]
            .forEach(textFieldsStackView.addArrangedSubview)

        // 添加宽度为零的间隔视图，UIStackView 的间距将负责将左边距添加到内容堆栈视图
        let emptySpacer = UIView.spacer(.horizontal, amount: 0)

        // 将空间视图、Favicon 图像视图、文本框堆栈视图添加到内容堆栈视图中
        [emptySpacer, faviconImageView, textFieldsStackView]
            .forEach(contentStackView.addArrangedSubview)

        let collectLabel = UILabel().then {
            $0.text = Strings.syncAddToHomePageFavorites
        }
        // 添加宽度为零的间隔视图，UIStackView 的间距将负责将左边距添加到内容堆栈视图
        // 添加到主页收藏夹的勾选按钮和标签
        
        addToHomeSwitch.addTarget(self, action: #selector(addToHomeSwitchValueChanged(_:)), for: .valueChanged)

        [addToHomeSwitch, collectLabel]
            .forEach(addToHomeStackView.addArrangedSubview)
        // 将新的勾选按钮和标签的堆栈视图添加到内容堆栈视图中
        [UIView.separatorLine, addToHomeStackView]
            .forEach(textFieldsStackView.addArrangedSubview)

        var url = url
        if url?.isBookmarklet == true {
            url = url?.removingPercentEncoding
        } else if let url = url, let favUrl = URL(string: url) {
            // 如果是书签，加载 Favicon 图标；如果是网址，加载网站的 Favicon 图标
            faviconImageView.loadFavicon(siteURL: favUrl, isPrivateBrowsing: isPrivateBrowsing)
        }

        // 设置标题文本框和 URL 文本框的默认文本
        titleTextField.text = title ?? Strings.newBookmarkDefaultName
        urlTextField.text = url ?? Strings.newFolderDefaultName

        // 设置文本框的目标
        setupTextFieldTargets()
    }

    // 设置文本框的目标
    private func setupTextFieldTargets() {
        for item in [titleTextField, urlTextField] {
            item?.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        }
    }

    // MARK: - 代理操作

    // 文本框内容变化时调用的方法
    @objc func textFieldDidChange(_ textField: UITextField) {
        // 根据文本框内容的不同，调用不同的代理方法
        if textField.text?.isBookmarklet == true {
            delegate?.correctValues(validationPassed: validateCodeFields())
        } else {
            delegate?.correctValues(validationPassed: validateFields())
        }
    }

    // 验证标题是否有效
    private func validateTitle(_ title: String?) -> Bool {
        guard let title = title else { return false }
        return !title.isEmpty
    }

    // 验证代码字段是否有效
    private func validateCodeFields() -> Bool {
        return BookmarkValidation.validateBookmarklet(title: titleTextField.text, url: urlTextField?.text)
    }

    // 勾选按钮值变化时调用的方法
    @objc func addToHomeSwitchValueChanged(_ sender: UISwitch) {
        Preferences.NewTabPage.iconAddHome.value = sender.isOn
        // delegate?.addToHomePageChanged(isChecked: sender.isOn)
    }
}
