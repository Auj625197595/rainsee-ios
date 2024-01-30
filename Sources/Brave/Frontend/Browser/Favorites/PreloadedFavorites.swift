/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import BraveShared
import BraveStrings
import Foundation
import os.log
import Shared

typealias FavoriteSite = (url: URL, title: String)

enum PreloadedFavorites {
    /// Returns a list of websites that should be preloaded for specific region. Currently all users get the same websites.
    static func getList() -> [FavoriteSite] {
        func appendPopularEnglishWebsites() -> [FavoriteSite] {
            var list = [FavoriteSite]()

            // 翻译。购物工具 推荐脚本 精选

            if let url = URL(string: FaviconUrl.TRANSLATE) {
                list.append(FavoriteSite(url: url, title: Strings.Home.translate))
            }
            if let url = URL(string: FaviconUrl.SCRIPT) {
                list.append(FavoriteSite(url: url, title: Strings.Home.scriptPrim))
            }

            if let url = URL(string: FaviconUrl.FAV) {
                list.append(FavoriteSite(url: url, title: Strings.Home.premium))
            }

            return list
        }
        
        func appendchinaWebsites() -> [FavoriteSite] {
            var list = [FavoriteSite]()
            if let url = URL(string: FaviconUrl.SHOPHELP) {
                list.append(FavoriteSite(url: url, title: Strings.Home.shopHelper))
            }
            return list
        }
//        func appendJapaneseWebsites() -> [FavoriteSite] {
//            var list = [FavoriteSite]()
//
//            if let url = URL(string: "https://m.youtube.com/") {
//                list.append(FavoriteSite(url: url, title: "YouTube"))
//            }
//
//            if let url = URL(string: "https://m.yahoo.co.jp/") {
//                list.append(FavoriteSite(url: url, title: "Yahoo! Japan"))
//            }
//
//            if let url = URL(string: "https://brave.com/ja/ntp-tutorial") {
//                list.append(FavoriteSite(url: url, title: "Braveガイド"))
//            }
//
//            if let url = URL(string: "https://mobile.twitter.com/") {
//                list.append(FavoriteSite(url: url, title: "Twitter"))
//            }
//
//            return list
//        }

        var preloadedFavorites = [FavoriteSite]()

        // Locale consists of language and region, region makes more sense when it comes to setting preloaded websites imo.
        let region = Locale.current.regionCode ?? "" // Empty string will go to the default switch case
        Logger.module.debug("Preloading favorites, current region: \(region)")
        preloadedFavorites += appendPopularEnglishWebsites()
        switch region {
        case "PL":
            // We don't do any per region preloaded favorites at the moment.
            // But if we would like to, it is as easy as adding a region switch case and adding websites to the list.

            // try? list.append(FavoriteSite(url: "https://allegro.pl/".asURL(), title: "Allegro"))
           
//        case "JP":
//            preloadedFavorites += appendJapaneseWebsites()
            break
        case "CN":
            preloadedFavorites += appendchinaWebsites()
        default:
            preloadedFavorites += appendPopularEnglishWebsites()
        }

        return preloadedFavorites
    }
}
