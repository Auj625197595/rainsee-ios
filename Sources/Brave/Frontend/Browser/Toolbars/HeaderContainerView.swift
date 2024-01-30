// 版权 © 2022 Brave Authors。保留所有权利。
// 此源代码形式受 Mozilla Public License, v. 2.0 条款的约束。
// 如果没有在此文件中分发 MPL 副本，可以在 http://mozilla.org/MPL/2.0/ 处获得一份。

import Foundation
import UIKit
import SnapKit
import Preferences
import Combine

// HeaderContainerView 类，继承自 UIView
class HeaderContainerView: UIView {
  
  // 用于垂直排列的 expandedBarStackView
  let expandedBarStackView = UIStackView().then {
    $0.axis = .vertical
  }
  
  // 用于收缩状态的容器视图 collapsedBarContainerView
  let collapsedBarContainerView = UIControl().then {
    $0.alpha = 0
  }
  
  // 是否使用底部工具栏的标志
  var isUsingBottomBar: Bool = false {
    didSet {
      updateConstraints()
    }
  }
  
  // 分割线视图
  let line = UIView()
  
  /// 包含扩展和折叠状态的 bar 的容器视图
  let contentView = UIView()
  
  // 私有浏览管理器，用于处理私有浏览状态
  private var privateBrowsingManager: PrivateBrowsingManager
  
  // 订阅集合，用于存储 Combine 订阅
  private var cancellables: Set<AnyCancellable> = []
  
  // 初始化方法，接受私有浏览管理器作为参数
  init(privateBrowsingManager: PrivateBrowsingManager) {
    self.privateBrowsingManager = privateBrowsingManager
    
    super.init(frame: .zero)
    
    // 将子视图添加到 HeaderContainerView
    addSubview(contentView)
    contentView.addSubview(expandedBarStackView)
    contentView.addSubview(collapsedBarContainerView)
    addSubview(line)
      line.isHidden = true
    
    // 设置 contentView 的约束
    contentView.snp.makeConstraints {
      $0.edges.equalToSuperview()
    }
    
    // 设置 collapsedBarContainerView 的约束
    collapsedBarContainerView.snp.makeConstraints {
      $0.leading.trailing.equalTo(safeAreaLayoutGuide)
      $0.bottom.equalToSuperview()
    }
    
    // 设置 expandedBarStackView 的约束
    expandedBarStackView.snp.makeConstraints {
      $0.edges.equalToSuperview()
    }
    
    // 更新颜色主题
    updateColors()
    
    // 监听私有浏览状态的变化，更新颜色主题
    privateBrowsingManager
      .$isPrivateBrowsing
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink(receiveValue: { [weak self] _ in
        self?.updateColors()
      })
      .store(in: &cancellables)
  }
  
  // 更新约束
  override func updateConstraints() {
    super.updateConstraints()
    
    // 重新设置 collapsedBarContainerView 的约束
    collapsedBarContainerView.snp.remakeConstraints {
      if isUsingBottomBar {
        $0.top.equalToSuperview()
      } else {
        $0.bottom.equalToSuperview()
      }
      $0.leading.trailing.equalTo(safeAreaLayoutGuide)
    }
    
    // 重新设置分割线的约束
    line.snp.remakeConstraints {
      if self.isUsingBottomBar {
        $0.bottom.equalTo(self.snp.top)
      } else {
        $0.top.equalTo(self.snp.bottom)
      }
      $0.leading.trailing.equalToSuperview()
      $0.height.equalTo(1.0 / UIScreen.main.scale)
    }
  }
  
  // 更新颜色主题的私有方法
  private func updateColors() {
    let browserColors = privateBrowsingManager.browserColors
    line.backgroundColor = browserColors.dividerSubtle
    backgroundColor = browserColors.chromeBackground
  }
  
  // 不可用的初始化方法，因为 HeaderContainerView 不应该从 xib 或 storyboard 中加载
  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }
}
