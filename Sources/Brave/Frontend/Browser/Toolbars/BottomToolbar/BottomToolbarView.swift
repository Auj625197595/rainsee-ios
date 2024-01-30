/*
 这个源代码形式受 Mozilla 公共许可证版本 2.0 的约束。如果没有在这个文件中分发 MPL，
 您可以在 http://mozilla.org/MPL/2.0/ 获取一份。
 */

import Combine
import Preferences
import Shared
import SnapKit
import UIKit

class BottomToolbarView: UIView, ToolbarProtocol {
    weak var tabToolbarDelegate: ToolbarDelegate?

    // 工具栏上的按钮
    let tabsButton = TabsButton()
    let forwardButton = ToolbarButton()
    let backButton = ToolbarButton()
    let shareButton = ToolbarButton()
        
    let addTabButton = ToolbarButton()
    let searchButton = ToolbarButton()

    let menuButton = MenuButton()
    
    let actionButtons: [UIView]
    let leftBottoms: [UIView]
    let rightBottoms: [UIView]
    
    let mUsvLeft = UIStackView()
    let mUsvRight = UIStackView()
    
    let centerButton = CustomView()
    
    // 工具栏帮助器和内容视图
    var helper: ToolbarHelper?
    private let contentView = UIStackView()
    private var cancellables: Set<AnyCancellable> = []
    //let line = UIView.separatorLine
    
    func updateProgressBar(_ progress: Float) {
      progressBar.alpha = 1
      progressBar.isHidden = false
      progressBar.setProgress(progress, animated: !isTransitioning)
    }
    
    private var isTransitioning: Bool = false {
      didSet {
        if isTransitioning {
          // Cancel any pending/in-progress animations related to the progress bar
          progressBar.setProgress(1, animated: false)
          progressBar.alpha = 0.0
        }
      }
    }
    
    private(set) lazy var progressBar = GradientProgressBar().then {
      $0.clipsToBounds = false
      $0.setGradientColors(startColor: .braveSuccessLabel, endColor: .braveSuccessLabel)
    }
    
    private let privateBrowsingManager: PrivateBrowsingManager

    init(privateBrowsingManager: PrivateBrowsingManager) {
        self.privateBrowsingManager = privateBrowsingManager
//    actionButtons = [backButton, menuButton, forwardButton, addTabButton, searchButton, tabsButton, ]
      
        centerButton.addTextView(searchView: searchButton)
        actionButtons = [mUsvLeft, centerButton, mUsvRight]
      
        leftBottoms = [backButton, menuButton]
        rightBottoms = [tabsButton, addTabButton]

        super.init(frame: .zero)
        setupAccessibility()

        // 设置背景颜色和内容视图
      //  backgroundColor = privateBrowsingManager.browserColors.chromeBackground
        
        backgroundColor = .clear
        addSubview(contentView)
      //  addSubview(line)
        addSubview(progressBar)

        helper = ToolbarHelper(toolbar: self)
    
        addButtons(actionButtons, contentView)
        addButtons(leftBottoms, mUsvLeft)
        addButtons(rightBottoms, mUsvRight)
      
        contentView.axis = .horizontal
        contentView.distribution = .fillEqually
        
        mUsvLeft.axis = .horizontal
        mUsvLeft.distribution = .fillEqually
        
        mUsvRight.axis = .horizontal
        mUsvRight.distribution = .fillEqually

        // 添加手势识别器用于滑动工具栏
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(didSwipeToolbar(_:))))
    
        // 设置分隔线约束
//        line.snp.makeConstraints {
//            $0.bottom.equalTo(self.snp.top)
//            $0.leading.trailing.equalToSuperview()
//        }
        progressBar.snp.makeConstraints {
            $0.bottom.equalTo(self.snp.top)
            $0.leading.trailing.equalToSuperview()
            $0.height.equalTo(2)

        }
        // 使用 Combine 监听是否处于隐私浏览模式
        privateModeCancellable = privateBrowsingManager
            .$isPrivateBrowsing
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink(receiveValue: { [weak self] _ in
                guard let self = self else { return }
                self.updateColors()
                self.helper?.updateForTraitCollection(self.traitCollection, browserColors: privateBrowsingManager.browserColors)
            })
    
        // 更新工具栏颜色和外观
        helper?.updateForTraitCollection(traitCollection, browserColors: privateBrowsingManager.browserColors)
    
        // 更新背景颜色
        updateColors()
    }

    // 用于取消 Combine 订阅的对象
    private var privateModeCancellable: AnyCancellable?
  
    // 更新工具栏颜色
    private func updateColors() {
       // backgroundColor = privateBrowsingManager.browserColors.chromeBackground
    }

    // 控制搜索按钮的可用状态
    private var isSearchButtonEnabled: Bool = false {
        didSet {
            //  addTabButton.isHidden = isSearchButtonEnabled
            // searchButton.isHidden = !addTabButton.isHidden
        }
    }

    // 设置搜索按钮的状态
    func setSearchButtonState(url: URL?) {
        if let url = url {
            isSearchButtonEnabled = InternalURL(url)?.isAboutHomeURL == true
        } else {
            isSearchButtonEnabled = false
        }
    }

    // 更新工具栏约束
    override func updateConstraints() {
        contentView.snp.makeConstraints { make in
            make.leading.trailing.top.equalTo(self)
            make.bottom.equalTo(self.safeArea.bottom)
            make.height.equalTo(UIConstants.toolbarHeight)
        }
        super.updateConstraints()
    }
  
    // 处理屏幕显示模式变化
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        helper?.updateForTraitCollection(traitCollection, browserColors: privateBrowsingManager.browserColors)
    }

    // 设置辅助功能标识符
    private func setupAccessibility() {
        backButton.accessibilityIdentifier = "TabToolbar.backButton"
        forwardButton.accessibilityIdentifier = "TabToolbar.forwardButton"
        tabsButton.accessibilityIdentifier = "TabToolbar.tabsButton"
        shareButton.accessibilityIdentifier = "TabToolbar.shareButton"
        addTabButton.accessibilityIdentifier = "TabToolbar.addTabButton"
        searchButton.accessibilityIdentifier = "TabToolbar.searchButton"
        accessibilityNavigationStyle = .combined
        accessibilityLabel = Strings.tabToolbarAccessibilityLabel
    }

    // 必需的初始化方法
    @available(*, unavailable)
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 添加按钮到内容视图
    func addButtons(_ buttons: [UIView]) {
        buttons.forEach { contentView.addArrangedSubview($0) }
    }

    func addButtons(_ buttons: [UIView], _ contentView: UIStackView) {
        buttons.forEach { contentView.addArrangedSubview($0) }
    }

    // 记录上一次的 X 坐标值
    private var previousX: CGFloat = 0.0
  
    // 处理工具栏的滑动手势
    @objc private func didSwipeToolbar(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            let velocity = pan.velocity(in: self)
            if velocity.x > 100 {
                tabToolbarDelegate?.tabToolbarDidSwipeToChangeTabs(self, direction: .right)
            } else if velocity.x < -100 {
                tabToolbarDelegate?.tabToolbarDidSwipeToChangeTabs(self, direction: .left)
            }
            previousX = pan.translation(in: self).x
        case .changed:
            let point = pan.translation(in: self)
            if point.x > previousX + 50 {
                tabToolbarDelegate?.tabToolbarDidSwipeToChangeTabs(self, direction: .right)
                previousX = point.x
            } else if point.x < previousX - 50 {
                tabToolbarDelegate?.tabToolbarDidSwipeToChangeTabs(self, direction: .left)
                previousX = point.x
            }
        default:
            break
        }
    }
  
    // 更新前进按钮的状态
    func updateForwardStatus(_ canGoForward: Bool) {
        if canGoForward {
            if let buttonSuperview = forwardButton.superview {
                print("按钮有父视图：\(buttonSuperview)")
            } else {
                let shareIndex = mUsvLeft.arrangedSubviews.firstIndex(of: menuButton)!
                mUsvLeft.insertArrangedSubview(forwardButton, at: shareIndex)
            }
          
        } else {
            forwardButton.removeFromSuperview()
        }
        
//        if canGoForward, let shareIndex = contentView.arrangedSubviews.firstIndex(of: shareButton) {
//            shareButton.removeFromSuperview()
//
//        } else if !canGoForward, let forwardIndex = contentView.arrangedSubviews.firstIndex(of: forwardButton) {
//            forwardButton.removeFromSuperview()
//            contentView.insertArrangedSubview(shareButton, at: forwardIndex)
//        }
    }
}

class CustomView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    public func addTextView(searchView: ToolbarButton) {
        searchView.setTitleColor(UIColor(named: "Color_txt", in: .module, compatibleWith: nil), for: .normal)
        
        searchView.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        searchView.titleLabel?.lineBreakMode = .byCharWrapping  // 设置省略号
        searchView.titleLabel?.numberOfLines = 1  // 设置为一行
        parentView.addSubview(searchView)
        
        searchView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.lessThanOrEqualTo(parentView.snp.width).offset(-16)  // 考虑左右两侧各5的间距
                make.leading.equalToSuperview().offset(8)  // 左侧间距
                make.trailing.equalToSuperview().offset(-8) // 右侧间距
        }
    }
    
    let parentView = UIView()
    private func setupView() {
        // 创建父视图
       
        parentView.backgroundColor = UIColor(named: "Color_center_bg", in: .module, compatibleWith: nil)
        parentView.layer.cornerRadius = 13
        addSubview(parentView)
        
        // 添加约束
        parentView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(8)
        }
    }
}
