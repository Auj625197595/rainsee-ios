// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import DesignSystem
import Favicon
import Foundation
import Shared
import UIKit

class TabCell: UICollectionViewCell {
    enum UX {
        static let cornerRadius = 6.0
        static let defaultBorderWidth = 1.0 / UIScreen.main.scale
        static let textBoxHeight = 32.0
        static let faviconSize = 20.0
    }

    static let identifier = "TabCellIdentifier"
    static let borderWidth = 3.0

    let backgroundHolder = UIView()
    let screenshotView = UIImageView()
    let titleBackgroundView = GradientView(
        colors: [UIColor(white: 1.0, alpha: 0.98), UIColor(white: 1.0, alpha: 0.9), UIColor(white: 1.0, alpha: 0.0)],
        positions: [0, 0.5, 1],
        startPoint: .zero,
        endPoint: CGPoint(x: 0, y: 1)
    )
    let titleLabel: UILabel
    let favicon: UIImageView = UIImageView().then {
        $0.contentMode = .scaleAspectFit
    }

    let closeButton: UIButton

    var animator: SwipeAnimator!

    // Changes depending on whether we're full-screen or not.
    var margin = 0.0

    var closedTab: ((Tab) -> Void)?
    weak var tab: Tab?

    func configure(with tab: Tab) {
        self.tab = tab
        // 设置选项卡截图更新时的闭包
        tab.onScreenshotUpdated = { [weak self, weak tab] in
            // 确保 self 和 tab 不为 nil
            guard let self = self, let tab = tab else { return }

            // 如果选项卡的显示标题不为空，设置视图的无障碍标签为显示标题
            if !tab.displayTitle.isEmpty {
                self.accessibilityLabel = tab.displayTitle
            }

            // 设置视图标题为选项卡的显示标题
            self.titleLabel.text = tab.displayTitle
            // 设置视图的网站图标为选项卡的显示网站图标，如果为空则使用默认图标
            self.favicon.image = tab.displayFavicon?.image ?? Favicon.defaultImage
            // 设置视图的截图为选项卡的截图
            self.screenshotView.image = tab.screenshot
        }

        titleLabel.text = tab.displayTitle
        favicon.image = tab.displayFavicon?.image ?? Favicon.defaultImage

        if !tab.displayTitle.isEmpty {
            accessibilityLabel = tab.displayTitle
        } else {
            if let url = tab.url {
                accessibilityLabel = InternalURL(url)?.aboutComponent ?? ""
            } else {
                accessibilityLabel = ""
            }
        }
        isAccessibilityElement = true
        accessibilityHint = Strings.tabTrayCellCloseAccessibilityHint

        favicon.image = nil
        favicon.cancelFaviconLoad()

        // Tab may not be restored and so may not include a tab URL yet...
        if let displayFavicon = tab.displayFavicon {
            favicon.image = displayFavicon.image ?? Favicon.defaultImage
        } else if let url = tab.url, !url.isLocal, !InternalURL.isValid(url: url) {
            favicon.loadFavicon(for: url, isPrivateBrowsing: tab.isPrivate)
        } else {
            favicon.image = Favicon.defaultImage
        }

        screenshotView.image = tab.screenshot
    }

    override init(frame: CGRect) {
        backgroundHolder.backgroundColor = .white
        backgroundHolder.layer.cornerRadius = UX.cornerRadius
        backgroundHolder.layer.cornerCurve = .continuous
        backgroundHolder.clipsToBounds = true

        screenshotView.contentMode = .scaleAspectFill
        screenshotView.clipsToBounds = true
        screenshotView.isUserInteractionEnabled = false
        screenshotView.backgroundColor = .braveBackground

        favicon.backgroundColor = .clear
        favicon.layer.cornerRadius = 2.0
        favicon.layer.cornerCurve = .continuous
        favicon.layer.masksToBounds = true

        self.titleLabel = UILabel()
        titleLabel.isUserInteractionEnabled = false
        titleLabel.numberOfLines = 1
        titleLabel.font = DynamicFontHelper.defaultHelper.DefaultSmallFontBold
        titleLabel.textColor = .black
        titleLabel.backgroundColor = .clear

        self.closeButton = UIButton()
        closeButton.setImage(UIImage(named: "tab_close", in: .module, compatibleWith: nil)!, for: [])
        closeButton.imageView?.contentMode = .scaleAspectFit
        closeButton.contentMode = .center
        closeButton.imageEdgeInsets = UIEdgeInsets(equalInset: 7)

        super.init(frame: frame)

        self.animator = SwipeAnimator(animatingView: self)
        animator.delegate = self
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        layer.borderWidth = UX.defaultBorderWidth
        layer.borderColor = UIColor.braveSeparator.resolvedColor(with: traitCollection).cgColor
        layer.cornerRadius = UX.cornerRadius
        layer.cornerCurve = .continuous

        contentView.addSubview(backgroundHolder)
        backgroundHolder.addSubview(screenshotView)
        backgroundHolder.addSubview(titleBackgroundView)

        titleBackgroundView.addSubview(closeButton)
        titleBackgroundView.addSubview(titleLabel)
        titleBackgroundView.addSubview(favicon)

        self.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: Strings.tabAccessibilityCloseActionLabel, target: animator, selector: #selector(SwipeAnimator.closeWithoutGesture))
        ]
    }

    func setTabSelected(_ tab: Tab) {
        layer.shadowColor = UIColor.braveInfoBorder.resolvedColor(with: traitCollection).cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = 0 // A 0 radius creates a solid border instead of a gradient blur
        layer.masksToBounds = false
        // create a frame that is "BorderWidth" size bigger than the cell
        layer.shadowOffset = CGSize(width: -TabCell.borderWidth, height: -TabCell.borderWidth)
        let shadowPath = CGRect(width: layer.frame.width + (TabCell.borderWidth * 2), height: layer.frame.height + (TabCell.borderWidth * 2))
        layer.shadowPath = UIBezierPath(roundedRect: shadowPath, cornerRadius: UX.cornerRadius + TabCell.borderWidth).cgPath
        layer.borderWidth = 0.0
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        backgroundHolder.frame = CGRect(x: margin, y: margin, width: frame.width, height: frame.height)
        screenshotView.frame = CGRect(size: backgroundHolder.frame.size)

        titleBackgroundView.snp.makeConstraints { make in
            make.top.left.right.equalTo(backgroundHolder)
            make.height.equalTo(UX.textBoxHeight + 15.0)
        }

        favicon.snp.makeConstraints { make in
            make.leading.equalTo(titleBackgroundView).offset(6)
            make.top.equalTo((UX.textBoxHeight - UX.faviconSize) / 2)
            make.size.equalTo(UX.faviconSize)
        }

        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(favicon.snp.trailing).offset(6)
            make.trailing.equalTo(closeButton.snp.leading).offset(-6)
            make.centerY.equalTo(favicon)
        }

        closeButton.snp.makeConstraints { make in
            make.size.equalTo(32)
            make.trailing.equalTo(titleBackgroundView)
            make.centerY.equalTo(favicon)
        }

        let shadowPath = CGRect(width: layer.frame.width + (TabCell.borderWidth * 2), height: layer.frame.height + (TabCell.borderWidth * 2))
        layer.shadowPath = UIBezierPath(roundedRect: shadowPath, cornerRadius: UX.cornerRadius + TabCell.borderWidth).cgPath
    }

    override func prepareForReuse() {
        // Reset any close animations.
        backgroundHolder.transform = .identity
        backgroundHolder.alpha = 1
        titleLabel.font = DynamicFontHelper.defaultHelper.DefaultSmallFontBold
        layer.shadowOffset = .zero
        layer.shadowPath = nil
        layer.shadowOpacity = 0
        layer.borderWidth = UX.defaultBorderWidth
    }

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        var right: Bool
        switch direction {
        case .left:
            right = false
        case .right:
            right = true
        default:
            return false
        }
        animator.close(right: right)
        return true
    }

    @objc
    func close() {
        if let tab = tab {
            closedTab?(tab)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // cgcolor does not dynamically update
        traitCollection.performAsCurrent {
            layer.shadowColor = UIColor.braveInfoBorder.cgColor
            layer.borderColor = UIColor.braveSeparator.cgColor
        }
    }
}

extension TabCell: SwipeAnimatorDelegate {
    func swipeAnimator(_ animator: SwipeAnimator, viewWillExitContainerBounds: UIView) {
        if let tab = tab {
            closedTab?(tab)
        }
    }
}

extension UIImage {
    /**
     根据坐标获取图片中的像素颜色值
     */
    subscript(x: Int, y: Int) -> UIColor? {
        let image = self
        let point = CGPoint(x: x, y: y)
        guard CGRect(origin: CGPoint(x: 0, y: 0), size: image.size).contains(point) else {
               return nil
           }

           let pointX = trunc(point.x)
           let pointY = trunc(point.y)

           let width = image.size.width
           let height = image.size.height
           let colorSpace = CGColorSpaceCreateDeviceRGB()
           var pixelData: [UInt8] = [0, 0, 0, 0]

           pixelData.withUnsafeMutableBytes { pointer in
               if let context = CGContext(data: pointer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let cgImage = image.cgImage {
                   context.setBlendMode(.copy)
                   context.translateBy(x: -pointX, y: pointY - height)
                   context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
               }
           }

           let red = CGFloat(pixelData[0]) / CGFloat(255.0)
           let green = CGFloat(pixelData[1]) / CGFloat(255.0)
           let blue = CGFloat(pixelData[2]) / CGFloat(255.0)
           let alpha = CGFloat(pixelData[3]) / CGFloat(255.0)
        
        if(alpha==0){
            print("xxx")
            return nil
        }

           if #available(iOS 10.0, *) {
               return UIColor(displayP3Red: red, green: green, blue: blue, alpha: alpha)
           } else {
               return UIColor(red: red, green: green, blue: blue, alpha: alpha)
           }
    }
}
