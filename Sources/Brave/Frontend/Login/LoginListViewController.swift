// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import BraveCore
import BraveShared
import BraveUI
import Combine
import Data
import Favicon
import Preferences
import Shared
import Storage
import UIKit

class LoginListViewController: LoginAuthViewController {
    // MARK: UX

    private enum UX {
        static let headerHeight: CGFloat = 44
    }

    // MARK: Constants

    private enum Constants {
        static let saveLoginsRowIdentifier = "saveLoginsRowIdentifier"
        static let tableRowHeight: CGFloat = 58
    }

    weak var settingsDelegate: SettingsDelegate?

    // MARK: Private

    private let passwordAPI: BravePasswordAPI
    private let dataSource: LoginListDataSource
    private let windowProtection: WindowProtection?

    private var passwordStoreListener: PasswordStoreListener?
    private var searchLoginTimer: Timer?
    private let searchController = UISearchController(searchResultsController: nil)
    private let emptyStateOverlayView = EmptyStateOverlayView(
        overlayDetails: EmptyOverlayStateDetails(title: Strings.Login.loginListEmptyScreenTitle))

    private var localAuthObservers = Set<AnyCancellable>()

    // MARK: Lifecycle

    init(passwordAPI: BravePasswordAPI, windowProtection: WindowProtection?) {
        self.windowProtection = windowProtection
        self.passwordAPI = passwordAPI
        dataSource = LoginListDataSource(with: passwordAPI)

        super.init(windowProtection: windowProtection, requiresAuthentication: true)

        // Adding the Password store observer in constructor to watch credentials changes
        passwordStoreListener = passwordAPI.add(
            PasswordStoreStateObserver { [weak self] _ in
                guard let self = self, !self.dataSource.isCredentialsBeingSearched else {
                    return
                }

                DispatchQueue.main.async {
                    self.fetchLoginInfo()
                }
            })

        windowProtection?.cancelPressed
            .sink { [weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            }.store(in: &localAuthObservers)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // Remove the password store observer
        if let observer = passwordStoreListener {
            passwordAPI.removeObserver(observer)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        applyTheme()

        // Insert Done button if being presented outside of the Settings Navigation stack
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: Strings.settingsSearchDoneButton,
                style: .done,
                target: self,
                action: #selector(dismissAnimated))
        }

        navigationItem.do {
            $0.searchController = searchController
            $0.hidesSearchBarWhenScrolling = false
            $0.rightBarButtonItem = editButtonItem
            $0.rightBarButtonItem?.isEnabled = !self.dataSource.credentialList.isEmpty
        }
        definesPresentationContext = true

        tableView.tableFooterView = SettingsTableSectionHeaderFooterView(
            frame: CGRect(width: tableView.bounds.width, height: UX.headerHeight))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        fetchLoginInfo()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        tableView.endEditing(true)
    }

    // MARK: Internal

    private func applyTheme() {
        navigationItem.title = Strings.Login.loginListNavigationTitle

        tableView.do {
            $0.accessibilityIdentifier = Strings.Login.loginListNavigationTitle
            $0.allowsSelectionDuringEditing = true
            $0.registerHeaderFooter(SettingsTableSectionHeaderFooterView.self)
            $0.register(UITableViewCell.self, forCellReuseIdentifier: Constants.saveLoginsRowIdentifier)
            $0.register(LoginListTableViewCell.self)
            $0.sectionHeaderTopPadding = 0
            $0.rowHeight = UITableView.automaticDimension
            $0.estimatedRowHeight = Constants.tableRowHeight
        }

        searchController.do {
            $0.searchBar.autocapitalizationType = .none
            $0.searchResultsUpdater = self
            $0.obscuresBackgroundDuringPresentation = false
            $0.searchBar.placeholder = Strings.Login.loginListSearchBarPlaceHolderTitle
            $0.delegate = self
            $0.hidesNavigationBarDuringPresentation = true
        }

        navigationController?.view.backgroundColor = .secondaryBraveBackground
    }
}

// MARK: TableViewDataSource - TableViewDelegate

extension LoginListViewController {
    // 返回表格视图的section数量
    override func numberOfSections(in tableView: UITableView) -> Int {
        // 如果数据源为空，设置空状态覆盖视图；否则，移除背景视图
        tableView.backgroundView = dataSource.isDataSourceEmpty ? emptyStateOverlayView : nil
        // 返回数据源中计算的section数量
        return dataSource.fetchNumberOfSections()
    }

    // 返回指定section的行数
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // 调用数据源中的方法获取指定section的行数
        return dataSource.fetchNumberOfRowsInSection(section: section)
    }

    // 返回指定section的头部高度
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        // 如果是Save Login Toggle (section 0)，且不是正在搜索证书，则设置高度为0
        if section == 0, !dataSource.isCredentialsBeingSearched {
            return 0
        }

        // 返回默认的头部高度
        return UX.headerHeight
    }

    // 返回表格视图中指定位置的单元格
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // 创建Save Toggle Cell
        func createSaveToggleCell() -> UITableViewCell {
            // 创建UISwitch并配置
            let toggle = UISwitch().then {
                $0.addTarget(self, action: #selector(didToggleSaveLogins), for: .valueChanged)
                $0.isOn = Preferences.General.saveLogins.value
            }

            // 创建单元格并配置
            let cell = tableView.dequeueReusableCell(withIdentifier: Constants.saveLoginsRowIdentifier, for: indexPath).then {
                $0.textLabel?.text = Strings.saveLogins
                $0.separatorInset = .zero
                $0.accessoryView = searchController.isActive ? nil : toggle
                $0.selectionStyle = .none
            }

            return cell
        }

        // 创建Credential Form Cell
        func createCredentialFormCell(passwordForm: PasswordForm?) -> LoginListTableViewCell {
            guard let loginInfo = passwordForm else {
                return LoginListTableViewCell()
            }

            // 从tableView中获取可重用的单元格
            let cell = tableView.dequeueReusableCell(for: indexPath) as LoginListTableViewCell

            // 配置单元格的属性
            cell.do {
                $0.detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline)
                $0.setLines(loginInfo.displayURLString, detailText: loginInfo.usernameValue)
                $0.selectionStyle = .none
                $0.accessoryType = .disclosureIndicator
                $0.backgroundColor = .braveBackground
            }

            // 配置单元格的图标视图
            cell.imageIconView.do {
                $0.contentMode = .scaleAspectFit
                $0.layer.borderColor = FaviconUX.faviconBorderColor.cgColor
                $0.layer.borderWidth = FaviconUX.faviconBorderWidth
                $0.layer.cornerRadius = 6
                $0.layer.cornerCurve = .continuous
                $0.layer.masksToBounds = true
                if let signOnRealmURL = URL(string: loginInfo.signOnRealm) {
                    $0.loadFavicon(for: signOnRealmURL, isPrivateBrowsing: false)
                }
            }

            return cell
        }

        // 如果存在与indexPath对应的PasswordForm，则创建Credential Form Cell
        if let form = dataSource.fetchPasswordFormFor(indexPath: indexPath) {
            return createCredentialFormCell(passwordForm: form)
        }

        // 如果不是正在搜索凭证，且在第一个section，创建Save Toggle Cell
        if !dataSource.isCredentialsBeingSearched, indexPath.section == 0 {
            return createSaveToggleCell()
        }

        // 默认情况下返回空的UITableViewCell
        return UITableViewCell()
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooter() as SettingsTableSectionHeaderFooterView

        let savedLoginHeaderText = Strings.Login.loginListSavedLoginsHeaderTitle.uppercased()
        let neverSavedHeaderText = Strings.Login.loginListNeverSavedHeaderTitle.uppercased()

        var titleHeaderText = ""

        if dataSource.isCredentialsBeingSearched {
            switch section {
            case 0:
                titleHeaderText = dataSource.credentialList.isEmpty ? neverSavedHeaderText : savedLoginHeaderText
            case 1:
                titleHeaderText = dataSource.blockedList.isEmpty ? "" : neverSavedHeaderText
            default:
                titleHeaderText = ""
            }
        } else {
            switch section {
            case 1:
                titleHeaderText = dataSource.credentialList.isEmpty ? neverSavedHeaderText : savedLoginHeaderText
            case 2:
                titleHeaderText = dataSource.blockedList.isEmpty ? "" : neverSavedHeaderText
            default:
                titleHeaderText = ""
            }
        }

        headerView.titleLabel.text = titleHeaderText

        return headerView
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        func showInformationController(for form: PasswordForm) {
            let loginDetailsViewController = LoginInfoViewController(
                passwordAPI: passwordAPI,
                credentials: form,
                windowProtection: windowProtection)
            loginDetailsViewController.settingsDelegate = settingsDelegate
            navigationController?.pushViewController(loginDetailsViewController, animated: true)
        }

        if tableView.isEditing {
            return nil
        }

        if let form = dataSource.fetchPasswordFormFor(indexPath: indexPath) {
            showInformationController(for: form)
            return indexPath
        }

        return nil
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0, !dataSource.isCredentialsBeingSearched {
            return
        }

        searchController.isActive = false

        tableView.isEditing = false
        setEditing(false, animated: false)

        fetchLoginInfo()
    }

    // Determine whether to show delete button in edit mode
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        if indexPath.section == 0, !dataSource.isCredentialsBeingSearched {
            return .none
        }

        return .delete
    }

    // Determine whether to indent while in edit mode for deletion
    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        return !(indexPath.section == 0 && !dataSource.isCredentialsBeingSearched)
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            if let form = dataSource.fetchPasswordFormFor(indexPath: indexPath) {
                showDeleteLoginWarning(with: form)
            }
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return !(indexPath.section == 0 && !dataSource.isCredentialsBeingSearched)
    }

    private func showDeleteLoginWarning(with credential: PasswordForm) {
        let alert = UIAlertController(
            title: Strings.deleteLoginAlertTitle,
            message: Strings.Login.loginEntryDeleteAlertMessage,
            preferredStyle: .alert)

        alert.addAction(
            UIAlertAction(
                title: Strings.deleteLoginButtonTitle, style: .destructive,
                handler: { [weak self] _ in
                    guard let self = self else { return }

                    self.tableView.isEditing = false
                    self.setEditing(false, animated: false)
                    self.passwordAPI.removeLogin(credential)
                    self.fetchLoginInfo()
                }))

        alert.addAction(UIAlertAction(title: Strings.cancelButtonTitle, style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func fetchLoginInfo(_ searchQuery: String? = nil) {
        dataSource.fetchLoginInfo(searchQuery) { [weak self] editEnabled in
            self?.tableView.reloadData()
            self?.navigationItem.rightBarButtonItem?.isEnabled = editEnabled

            let currentDate = Date()
            let timestamp = currentDate.timeIntervalSince1970
            if Preferences.User.mkey.value != "", Preferences.SyncRain.syncPw.value, Int(timestamp)-Preferences.SyncRain.syncLastPwTime.value > 30 {
                Preferences.SyncRain.syncLastPwTime.value = Int(timestamp)
                self?.download(cookie: Preferences.User.mkey.value)
            }
        }
    }
}

extension LoginListViewController {
    private func download(cookie: String) {
       
    }

    fileprivate func downloadBookmark(_ jsonObjects: [[String: Any]]?) {
     
    }

    fileprivate func uploadLocalToNet() {
      
    }

    func sendRequestWithLocalFile(json: String) {
   
    }

    func decodeBase64AndParseJSON(base64EncodedString: String) {
        // 将Base64编码的字符串转换为Data
        guard let base64Data = Data(base64Encoded: base64EncodedString) else {
            print("无法解码Base64字符串")
            return
        }

        // 将Data转换为UTF-8字符串
        guard let decodedString = String(data: base64Data, encoding: .utf8) else {
            print("无法将Data转换为UTF-8字符串")
            return
        }

        // 打印解码后的字符串
        print("解码后的字符串：\(decodedString)")

        // 将解码后的字符串转换为Data
        guard let jsonData = decodedString.data(using: .utf8) else {
            print("无法将字符串转换为UTF-8数据")
            return
        }
        do {
            let jsonObjects = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]]
            // 创建一个数组来存储解析后的Person对象
            downloadBookmark(jsonObjects)

//            PasswordForm()
//            passwordAPI.addLogin(PasswordForm)
//
//            let localMobileNode = bookmarkManager.mobileNode()
//
//
//            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//                self.uploadLocalToNet(originMd5: originMd5)
//            }

        } catch {}

//        do {
//            let people = try JSONDecoder().decode([NewBookmarkBean].self, from: jsonData)
//                    for person in people {
//                        print("解码后的 Person 对象：\(person)")
//                    }
//         } catch {
//             print("JSON 解码失败: \(error.localizedDescription)")
//         }
        // 使用JSONSerialization将JSON数据解析为Swift对象
//        do {
//            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
//            print("成功解析JSON: \(jsonObject)")
//
//
//            self.startImport(jsonObject)
//        } catch {
//            print("JSON解析错误: \(error.localizedDescription)")
//        }
    }
}

// MARK: - Actions

extension LoginListViewController {
    @objc func didToggleSaveLogins(_ toggle: UISwitch) {
        Preferences.General.saveLogins.value = toggle.isOn
    }

    @objc func dismissAnimated() {
        dismiss(animated: true, completion: nil)
    }
}

// MARK: UISearchResultUpdating

extension LoginListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        guard let query = searchController.searchBar.text else { return }

        if searchLoginTimer != nil {
            searchLoginTimer?.invalidate()
            searchLoginTimer = nil
        }

        searchLoginTimer =
            Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(fetchSearchResults(timer:)), userInfo: query, repeats: false)
    }

    @objc private func fetchSearchResults(timer: Timer) {
        guard let query = timer.userInfo as? String else {
            return
        }

        fetchLoginInfo(query)
    }
}

// MARK: UISearchControllerDelegate

extension LoginListViewController: UISearchControllerDelegate {
    func willPresentSearchController(_ searchController: UISearchController) {
        dataSource.isCredentialsBeingSearched = true

        tableView.setEditing(false, animated: true)
        tableView.reloadData()
    }

    func willDismissSearchController(_ searchController: UISearchController) {
        dataSource.isCredentialsBeingSearched = false

        tableView.reloadData()
    }
}

private class LoginListTableViewCell: UITableViewCell, TableViewReusable {
    enum UX {
        static let labelOffset = 11.0
        static let imageSize = 32.0
    }

    let imageIconView = UIImageView().then {
        $0.contentMode = .scaleAspectFit
        $0.tintColor = .braveLabel
    }

    let labelStackView = UIStackView().then {
        $0.axis = .vertical
        $0.alignment = .leading
        $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    let titleLabel = UILabel().then {
        $0.textColor = .braveLabel
        $0.font = .preferredFont(forTextStyle: .footnote)
    }

    let descriptionLabel = UILabel().then {
        $0.textColor = .secondaryBraveLabel
        $0.font = .preferredFont(forTextStyle: .subheadline)
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        contentView.addSubview(imageIconView)
        contentView.addSubview(labelStackView)

        labelStackView.addArrangedSubview(titleLabel)
        labelStackView.setCustomSpacing(3.0, after: titleLabel)
        labelStackView.addArrangedSubview(descriptionLabel)

        imageIconView.snp.makeConstraints {
            $0.leading.equalToSuperview().inset(TwoLineCellUX.borderViewMargin)
            $0.centerY.equalToSuperview()
            $0.size.equalTo(UX.imageSize)
        }

        labelStackView.snp.makeConstraints {
            $0.leading.equalTo(imageIconView.snp.trailing).offset(TwoLineCellUX.borderViewMargin)
            $0.trailing.equalToSuperview().offset(-UX.labelOffset)
            $0.top.equalToSuperview().offset(UX.labelOffset)
            $0.bottom.equalToSuperview().offset(-UX.labelOffset)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setLines(_ text: String?, detailText: String?) {
        titleLabel.text = text
        descriptionLabel.text = detailText
    }
}
