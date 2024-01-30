// 版权 © 2022 Brave 作者。保留所有权利。
// 本源代码形式受 Mozilla Public License, v. 2.0 的条款约束。
// 如果未随此文件分发 MPL 的副本，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import Foundation
import Shared
import UIKit

/// 表示一个网站图标的结构
public class Favicon: Codable {
    public let image: UIImage? // 图标的图像
    public let isMonogramImage: Bool // 是否为单字母图像
    public let backgroundColor: UIColor // 背景颜色

    public static let defaultImage = UIImage(named: "defaultFavicon", // 默认图标图像
                                             in: .module,
                                             compatibleWith: nil)!
    public static let youhuiImage = UIImage(named: "icon_youhuiv2", // 默认图标图像
                                            in: .module,
                                            compatibleWith: nil)!
    public static let transImage = UIImage(named: "icon_fanyiv2", // 默认图标图像
                                           in: .module,
                                           compatibleWith: nil)!
    public static let favImage = UIImage(named: "icon_jxv2", // 默认图标图像
                                         in: .module,
                                         compatibleWith: nil)!
    public static let scriptImage = UIImage(named: "icon_olov2", // 默认图标图像
                                            in: .module,
                                            compatibleWith: nil)!

    public static let `default` = Favicon(image: Favicon.defaultImage, // 默认 Favicon 实例
                                          isMonogramImage: false,
                                          backgroundColor: .clear)

    public var hasTransparentBackground: Bool {
        backgroundColor.rgba == UIColor.clear.rgba // 判断是否有透明背景
    }

    public init(image: UIImage?, isMonogramImage: Bool, backgroundColor: UIColor) {
        self.image = image
        self.isMonogramImage = isMonogramImage
        self.backgroundColor = backgroundColor
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let data = try container.decodeIfPresent(Data.self, forKey: .image) {
            let scale = try container.decodeIfPresent(CGFloat.self, forKey: .imageScale) ?? 1.0
            image = UIImage(data: data, scale: scale)
        } else {
            image = nil
        }

        isMonogramImage = try container.decode(Bool.self, forKey: .isMonogramImage)
        backgroundColor = try UIColor(rgba: container.decode(UInt32.self, forKey: .backgroundColor))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(image?.pngData(), forKey: .image)
        try container.encode(image?.scale, forKey: .imageScale)
        try container.encode(isMonogramImage, forKey: .isMonogramImage)
        try container.encode(backgroundColor.rgba, forKey: .backgroundColor)
    }

    private enum CodingKeys: CodingKey {
        case image
        case imageScale
        case isMonogramImage
        case backgroundColor
    }
}
