/* 该源代码受 Mozilla 公共许可证 2.0 版本的约束。
 * 如果此文件未与该许可证一起分发，您可以在 http://mozilla.org/MPL/2.0/ 获取一份副本。 */

import UIKit
import Shared
import Storage

// SiteTableViewControllerUX 结构体，定义了一些用于界面设计的常量
struct SiteTableViewControllerUX {
  static let headerHeight = CGFloat(32)  // 头部高度
  static let rowHeight = CGFloat(44)     // 行高
  static let headerFont = UIFont.systemFont(ofSize: 12, weight: UIFont.Weight.medium)  // 头部字体
  static let headerTextMargin = CGFloat(16)  // 头部文本边距
}

// SiteTableViewHeader 类，继承自 UITableViewHeaderFooterView，表示表格视图的头部
class SiteTableViewHeader: UITableViewHeaderFooterView {
  let titleLabel = UILabel()  // 头部标题标签

  override var textLabel: UILabel? {
    return titleLabel
  }

  override init(reuseIdentifier: String?) {
    super.init(reuseIdentifier: reuseIdentifier)

    titleLabel.font = DynamicFontHelper.defaultHelper.DeviceFontMediumBold
    titleLabel.textColor = .braveLabel

    contentView.addSubview(titleLabel)

    // 由于表格视图在应用实际大小之前使用 CGSizeZero 初始化头部，因此标签的约束
    // 不应强加对内容视图的最小宽度。
    titleLabel.snp.makeConstraints { make in
      make.left.equalTo(contentView).offset(SiteTableViewControllerUX.headerTextMargin).priority(999)
      make.right.equalTo(contentView).offset(-SiteTableViewControllerUX.headerTextMargin).priority(999)
      make.left.greaterThanOrEqualTo(contentView)  // 当左空间约束断开时的回退
      make.right.lessThanOrEqualTo(contentView)  // 当右空间约束断开时的回退
      make.centerY.equalTo(contentView)
    }
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

/**
 * 提供站点行和头部的基本共享功能。
 */
@objcMembers
public class SiteTableViewController: LoadingViewController, UITableViewDelegate, UITableViewDataSource {
  fileprivate let CellIdentifier = "CellIdentifier"  // 单元格标识符
  fileprivate let HeaderIdentifier = "HeaderIdentifier"  // 头部标识符
  var profile: Profile! {
    didSet {
      reloadData()
    }
  }

  var data = [Site]()  // 数据数组
  var tableView = UITableView()  // 表格视图

  override public func viewDidLoad() {
    super.viewDidLoad()

    view.addSubview(tableView)
    tableView.snp.makeConstraints { make in
      make.edges.equalTo(self.view)
      return
    }

    tableView.do {
      $0.delegate = self
      $0.dataSource = self
      $0.register(SiteTableViewCell.self, forCellReuseIdentifier: CellIdentifier)
      $0.register(SiteTableViewHeader.self, forHeaderFooterViewReuseIdentifier: HeaderIdentifier)
      $0.layoutMargins = .zero
      $0.keyboardDismissMode = .onDrag
      $0.backgroundColor = .secondaryBraveBackground
      $0.separatorColor = .braveSeparator
      $0.accessibilityIdentifier = "SiteTable"
      $0.cellLayoutMarginsFollowReadableWidth = false
      $0.sectionHeaderTopPadding = 5
    }

    // 设置一个空的页脚以防止空单元格出现在列表中。
    tableView.tableFooterView = UIView()
  }

  deinit {
    // 视图可能在动画中超过此视图控制器的寿命；
    // 明确将其对我们的引用设置为 nil 以避免崩溃。Bug 1218826。
    tableView.dataSource = nil
    tableView.delegate = nil
  }

  func reloadData() {
    self.tableView.reloadData()
  }

  public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return data.count
  }

  public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: CellIdentifier, for: indexPath)
    if self.tableView(tableView, hasFullWidthSeparatorForRowAtIndexPath: indexPath) {
      cell.separatorInset = .zero
    }
    return cell
  }

  public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
    return tableView.dequeueReusableHeaderFooterView(withIdentifier: HeaderIdentifier)
  }

  public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
    return SiteTableViewControllerUX.headerHeight
  }

  public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    return SiteTableViewControllerUX.rowHeight
  }

  public func tableView(_ tableView: UITableView, hasFullWidthSeparatorForRowAtIndexPath indexPath: IndexPath) -> Bool {
    return false
  }

  public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
    true
  }
}
