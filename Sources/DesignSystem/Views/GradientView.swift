// 版权声明：2021年 Brave 作者。保留所有权利。
// 本源代码形式受 Mozilla Public License，版本 2.0 规定的条款约束。
// 如果未随此文件分发 MPL 的副本，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import UIKit
import SwiftUI

/// 一个 UIView，其图层是一个渐变层
public class GradientView: UIView {

  public convenience init() {
    self.init(colors: [], positions: [], startPoint: .zero, endPoint: CGPoint(x: 0, y: 1))
  }

  public init(colors: [UIColor], positions: [CGFloat], startPoint: CGPoint, endPoint: CGPoint) {
    super.init(frame: .zero)

    // 将颜色解析为当前环境下的颜色，并设置渐变层的颜色、位置、起点和终点
    gradientLayer.colors = colors.map { $0.resolvedColor(with: traitCollection).cgColor }
    gradientLayer.locations = positions.map { NSNumber(value: Double($0)) }
    gradientLayer.startPoint = startPoint
    gradientLayer.endPoint = endPoint
  }

  /// 您可以修改的渐变层
  public var gradientLayer: CAGradientLayer {
    return layer as! CAGradientLayer  // swiftlint:disable:this force_cast
  }

  public override class var layerClass: AnyClass {
    return CAGradientLayer.self
  }

  @available(*, unavailable)
  required init?(coder aDecoder: NSCoder) {
    fatalError()
  }
}

/// 一个渐变视图，它使用 BraveGradient 根据 trait 集合调整其渐变属性。
///
/// 如果要将 `BraveGradient` 解析为特定的用户界面样式，请使用 `init(gradient:)` 或设置 `overrideUserInterfaceStyle`，如果您已经使用了预设的提供程序。
public class BraveGradientView: GradientView {
  private var provider: (UITraitCollection) -> BraveGradient

  public init(dynamicProvider provider: @escaping (UITraitCollection) -> BraveGradient) {
    self.provider = provider
    super.init(colors: [], positions: [], startPoint: .zero, endPoint: .zero)
    updateGradient()
  }

  public convenience init(gradient: BraveGradient) {
    self.init(dynamicProvider: { _ in gradient })
  }

  private func updateGradient() {
    let gradient = provider(traitCollection)
    gradientLayer.type = gradient.type
    gradientLayer.colors = gradient.stops.map(\.color.cgColor)
    gradientLayer.locations = gradient.stops.map({ NSNumber(value: $0.position) })
    gradientLayer.startPoint = gradient.startPoint
    gradientLayer.endPoint = gradient.endPoint
  }

  public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
      updateGradient()
    }
  }
}

/// 一个渐变控件，它使用 BraveGradient 根据 trait 集合调整其渐变属性。
public class BraveGradientButton: UIButton {
  private var provider: (UITraitCollection) -> BraveGradient

  public init(dynamicProvider provider: @escaping (UITraitCollection) -> BraveGradient, colors: [UIColor], positions: [CGFloat], startPoint: CGPoint, endPoint: CGPoint) {
    self.provider = provider
    
    super.init(frame: .zero)

    // 将颜色解析为当前环境下的颜色，并设置渐变层的颜色、位置、起点和终点
    gradientLayer.colors = colors.map { $0.resolvedColor(with: traitCollection).cgColor }
    gradientLayer.locations = positions.map { NSNumber(value: Double($0)) }
    gradientLayer.startPoint = startPoint
    gradientLayer.endPoint = endPoint
    
    updateGradient()
  }
  
  public convenience init(gradient: BraveGradient) {
    self.init(dynamicProvider: { _ in gradient }, colors: [], positions: [], startPoint: .zero, endPoint: CGPoint(x: 0, y: 1))
  }
  
  /// 您可以修改的渐变层
  public var gradientLayer: CAGradientLayer {
    return layer as! CAGradientLayer  // swiftlint:disable:this force_cast
  }

  public override class var layerClass: AnyClass {
    return CAGradientLayer.self
  }

  @available(*, unavailable)
  required init?(coder aDecoder: NSCoder) {
    fatalError()
  }

  private func updateGradient() {
    let gradient = provider(traitCollection)
    gradientLayer.type = gradient.type
    gradientLayer.colors = gradient.stops.map(\.color.cgColor)
    gradientLayer.locations = gradient.stops.map({ NSNumber(value: $0.position) })
    gradientLayer.startPoint = gradient.startPoint
    gradientLayer.endPoint = gradient.endPoint
  }

  public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
      updateGradient()
    }
  }
}
