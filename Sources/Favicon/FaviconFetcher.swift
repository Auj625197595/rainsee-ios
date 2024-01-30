// 版权所有 2022 年 Brave 作者。保留所有权利。
// 本源代码形式受 Mozilla Public License, v. 2.0 条款约束。
// 如果没有与此文件一起分发 MPL 的副本，
// 您可以在 http://mozilla.org/MPL/2.0/ 获取一份副本。

import BraveCore
import FaviconModels
import Foundation
import os.log
import SDWebImage
import Shared
import UIKit

/// Favicon 错误
public enum FaviconError: Error {
    case noImagesFound
    case noBundledImages
}

/// 处理从本地文件、数据库或互联网获取网站图标的类
public enum FaviconFetcher {
    /// 网站图标的尺寸要求
    public enum Kind {
        /// 加载标记为 `apple-touch-icon` 的网站图标。
        ///
        /// 用途: NTP, 收藏夹
        case largeIcon
        /// 加载较小的网站图标
        ///
        /// 用途: 历史记录, 搜索, 标签托盘
        case smallIcon
    }

    public static func clearCache() {
        SDImageCache.shared.memoryCache.removeAllObjects()
        SDImageCache.shared.diskCache.removeAllData()
    }

    /// 按照以下顺序获取网站图标：
    /// 1. 从缓存获取
    /// 2. 从 Brave-Core 获取
    /// 3. 从捆绑图标获取
    /// 4. 获取字母缩写图标
    /// 注意：不会请求从页面获取图标，请求仅在用户访问页面时在 FaviconScriptHandler 中进行。
    public static func loadIcon(url: URL, kind: FaviconFetcher.Kind = .smallIcon, persistent: Bool) async throws -> Favicon {
        try Task.checkCancellation()

        if let favicon = getFromCache(for: url) {
            return favicon
        }

        // 从 Brave-Core 获取图标
        let favicon = try? await FaviconRenderer.loadIcon(for: url, persistent: persistent)
        if let favicon = favicon, !favicon.isMonogramImage {
            storeInCache(favicon, for: url, persistent: persistent)
            try Task.checkCancellation()
            return favicon
        }

        // 获取捆绑或自定义图标
        // 如果出现错误，将尝试获取缓存的图标
        if let favicon = try? await BundledFaviconRenderer.loadIcon(url: url) {
            storeInCache(favicon, for: url, persistent: true)
            try Task.checkCancellation()
            return favicon
        }

        // 缓存并返回字母缩写图标
        if let favicon = favicon {
            storeInCache(favicon, for: url, persistent: persistent)
            return favicon
        }

        // 未找到图标
        throw FaviconError.noImagesFound
    }

    /// 创建字母缩写图标，具备以下条件
    /// 1. 如果 `monogramString` 不为空，则用它来渲染字母缩写图标。
    /// 2. 如果 `monogramString` 为空，则使用 URL 的域的第一个字符来渲染字母缩写图标。
    public static func monogramIcon(url: URL, monogramString: Character? = nil, persistent: Bool) async throws -> Favicon {
        try Task.checkCancellation()

        if let favicon = getFromCache(for: url) {
            return favicon
        }

        // 在 UIImage 上渲染字母缩写
        guard let attributes = BraveCore.FaviconAttributes.withDefaultImage() else {
            throw FaviconError.noImagesFound
        }

        let textColor = !attributes.isDefaultBackgroundColor ? attributes.textColor : nil
        let backColor = !attributes.isDefaultBackgroundColor ? attributes.backgroundColor : nil
        var monogramText = attributes.monogramString
        if let monogramString = monogramString ?? url.baseDomain?.first {
            monogramText = String(monogramString)
        }

        let favicon = await UIImage.renderMonogram(url, textColor: textColor, backgroundColor: backColor, monogramString: monogramText)
        storeInCache(favicon, for: url, persistent: persistent)
        try Task.checkCancellation()
        return favicon
    }

    public static let SHOPHELP: String = "https://api.yjllq.com/youhuihome?from=app"
    public static let FAV: String = "https://api.yjllq.com/api/Index/choice?theme=1&from=ios"
    public static let TRANSLATE: String = "https://admin.yujianpay.com/h5/pages/translate/translate?from=ios"
    public static let SCRIPT: String = "https://admin.yujianpay.com/h5/pages/scripts/scripts?from=ios"
    /// 从缓存中检索网站图标
    public static func getIconFromCache(for url: URL) -> Favicon? {
        // 处理内部 URL
        var url = url
        if let internalURL = InternalURL(url), let realUrl = internalURL.originalURLFromErrorPage ?? internalURL.extractedUrlParam {
            url = realUrl
        }

        // 如果 URL 包含 "yjllq"，则返回本地资源名为 "web" 的图标
        if url.absoluteString == SHOPHELP {
            return Favicon(image: Favicon.youhuiImage, // 默认 Favicon 实例
                           isMonogramImage: false,
                           backgroundColor: .clear)
        } else if url.absoluteString == FAV {
            return Favicon(image: Favicon.favImage, // 默认 Favicon 实例
                           isMonogramImage: false,
                           backgroundColor: .clear)
        } else if url.absoluteString == TRANSLATE {
            return Favicon(image: Favicon.transImage, // 默认 Favicon 实例
                           isMonogramImage: false,
                           backgroundColor: .clear)
        } else if url.absoluteString == SCRIPT {
            return Favicon(image: Favicon.scriptImage, // 默认 Favicon 实例
                           isMonogramImage: false,
                           backgroundColor: .clear)
        }

        // 从缓存获取
        if let favicon = getFromCache(for: url) {
            return favicon
        }

        // 当我们在 URL 栏中搜索域时，
        // 它会自动将方案更改为 `http`
        // 即使网站加载/重定向为 `https`
        // 尝试使用 `https` 图标（如果存在）
        if url.scheme == "http", var components = URLComponents(string: url.absoluteString) {
            components.scheme = "https"

            // 从缓存获取
            if let url = components.url, let favicon = FaviconFetcher.getIconFromCache(for: url) {
                return favicon
            }
        }

        return nil
    }

    /// 使用指定的图标更新缓存，如果没有图标，则从缓存中删除图标。
    public static func updateCache(_ favicon: Favicon?, for url: URL, persistent: Bool) {
        guard let favicon else {
            let cachedURL = cacheURL(for: url)
            SDImageCache.shared.memoryCache.removeObject(forKey: cachedURL.absoluteString)
            SDImageCache.shared.diskCache.removeData(forKey: cachedURL.absoluteString)
            return
        }

        storeInCache(favicon, for: url, persistent: persistent)
    }

    private static func cacheURL(for url: URL) -> URL {
        // 一些网站仍然仅为包括分段部分的完整 URL 拥有图标
        // 但它们不会为其域拥有图标
        // 在这种情况下，我们希望为整个域存储图标，而不考虑查询参数或分段部分
        // 例如: `https://app.uniswap.org/` 没有图标，但 `https://app.uniswap.org/#/swap?chain=mainnet` 有图标。
        return url.domainURL
    }

    private static func storeInCache(_ favicon: Favicon, for url: URL, persistent: Bool) {
        // 不要将非持久性图标缓存到磁盘
        if persistent {
            do {
                let cachedURL = cacheURL(for: url)
                SDImageCache.shared.memoryCache.setObject(favicon, forKey: cachedURL.absoluteString)
                try SDImageCache.shared.diskCache.setData(JSONEncoder().encode(favicon), forKey: cachedURL.absoluteString)
            } catch {
                Logger.module.error("缓存网站图标时发生错误: \(error)")
            }
        } else {
            // 仅将非持久性图标缓存到内存
            SDImageCache.shared.memoryCache.setObject(favicon, forKey: cacheURL(for: url).absoluteString)
        }
    }

    private static func getFromCache(for url: URL) -> Favicon? {
        let cachedURL = cacheURL(for: url)
        if let favicon = SDImageCache.shared.memoryCache.object(forKey: cachedURL.absoluteString) as? Favicon {
            return favicon
        }

        guard let data = SDImageCache.shared.diskCache.data(forKey: cachedURL.absoluteString) else {
            return nil
        }

        do {
            let favicon = try JSONDecoder().decode(Favicon.self, from: data)
            SDImageCache.shared.memoryCache.setObject(favicon, forKey: cachedURL.absoluteString)
            return favicon
        } catch {
            Logger.module.error("解码网站图标时发生错误: \(error)")
        }
        return nil
    }
}
