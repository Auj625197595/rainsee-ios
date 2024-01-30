/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit

public extension URL {
    enum Brave {
        public static let privacy_h5 = URL(string: "https://admin.yujianpay.com/h5/pages/privacy/privacy")!
        public static let user_h5 = URL(string: "https://")!

        public static let user_javascript = URL(string: "https://")!
        public static let user_javascript_manage = URL(string: "https://")!
        public static let user_center_h5 = URL(string: "https://")!

        public static let contact_us = "https://club.yujianpay.com/index.php/archives/90/"
        public static let update_log = "https://club.yujianpay.com/index.php/rsios.html"
        public static let api_checkuser = "https://"
        public static let api_uploadBookmark = "https://"
        public static let api_uploadBookmarkIos = "https://"
        public static let api_uploadPwIos = "https://"

        public static let api_downloadPw = "https://"

        public static let api_downloadHome = "https://"
        public static let api_uploadHomeIos = "https://"
        public static let translate = "https://"
        public static let qrcodeScan = URL(string: "https://admin.yujianpay.com/api/image/qrcode")!


        public static let community = URL(string: "https://community.brave.com/")!
        public static let account = URL(string: "https://account.brave.com")!
        public static let privacy = URL(string: "https://brave.com/privacy/")!
        public static let braveNews = URL(string: "https://brave.com/brave-news/")!
        public static let braveNewsPrivacy = URL(string: "https://brave.com/privacy/#brave-news")!
        public static let braveOffers = URL(string: "https://offers.brave.com/")!
        public static let playlist = URL(string: "https://brave.com/playlist")!
        public static let rewardsOniOS = URL(string: "https://brave.com/rewards-ios/")!
        public static let rewardsUnverifiedPublisherLearnMoreURL = URL(string: "https://brave.com/faq-rewards/#unclaimed-funds")!
        public static let termsOfUse = URL(string: "https://www.brave.com/terms_of_use")!
        public static let batTermsOfUse = URL(string: "https://basicattentiontoken.org/user-terms-of-service/")!
        public static let ntpTutorialPage = URL(string: "https://brave.com/ja/ntp-tutorial")!
        public static let privacyFeatures = URL(string: "https://brave.com/privacy-features/")!
        public static let support = URL(string: "https://support.brave.com")!
        public static let p3aHelpArticle = URL(string: "https://support.brave.com/hc/en-us/articles/9140465918093-What-is-P3A-in-Brave-")!
        public static let braveVPNFaq = URL(string: "https://support.brave.com/hc/en-us/articles/360045045952")!
        public static let braveVPNLinkReceiptProd = URL(string: "https://account.brave.com/?intent=connect-receipt&product=vpn")!
        public static let braveVPNLinkReceiptStaging = URL(string: "https://account.bravesoftware.com/?intent=connect-receipt&product=vpn")!
        public static let braveVPNLinkReceiptDev = URL(string: "https://account.brave.software/?intent=connect-receipt&product=vpn")!
        public static let safeBrowsingHelp =
            URL(string: "https://support.brave.com/hc/en-us/articles/15222663599629-Safe-Browsing-in-Brave")!
        public static let screenTimeHelp =
            URL(string: "https://support.apple.com/guide/security/secd8831e732/web")!
    }

    enum Apple {
        public static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")
    }

    static let brave = Brave.self
    static let apple = Apple.self
}

public enum AppURLScheme {
    /// The apps URL scheme for the current build channel
    public static var appURLScheme: String {
        Bundle.main.infoDictionary?["BRAVE_URL_SCHEME"] as? String ?? "brave"
    }
}
