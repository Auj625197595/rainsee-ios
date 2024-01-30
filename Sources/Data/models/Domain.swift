/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import BraveCore
import BraveShields
import CoreData
import Foundation
import os.log
import Preferences
import Shared
import UIKit

public final class Domain: NSManagedObject, CRUD {
    @NSManaged public var url: String?
    @NSManaged public var visits: Int32
    @NSManaged public var topsite: Bool // not currently used. Should be used once proper frecency code is in.
    @NSManaged public var blockedFromTopSites: Bool // don't show ever on top sites

    @NSManaged public var shield_allOff: NSNumber?
    @NSManaged public var shield_adblockAndTp: NSNumber? 

    @available(*, deprecated, message: "Per domain HTTPSE shield is currently unused.")
    @NSManaged public var shield_httpse: NSNumber?

    @NSManaged public var shield_noScript: NSNumber?
    @NSManaged public var shield_fpProtection: NSNumber?
    @NSManaged public var shield_safeBrowsing: NSNumber?

    @NSManaged public var bookmarks: NSSet?

    @NSManaged public var wallet_permittedAccounts: String?
    @NSManaged public var zoom_level: NSNumber?
    @NSManaged public var wallet_solanaPermittedAcccounts: String?

    private var urlComponents: URLComponents? {
        return URLComponents(string: url ?? "")
    }

    // TODO: @JS Replace this with the 1st party ad-block list
    // https://github.com/brave/brave-ios/issues/7611
    /// A list of etld+1s that are always aggressive
    private let alwaysAggressiveETLDs: Set<String> = ["youtube.com"]

    /// Return the shield level for this domain.
    ///
    /// - Warning: This does not consider the "all off" setting
    /// This also takes into consideration certain domains that are always aggressive.
    @MainActor public var blockAdsAndTrackingLevel: ShieldLevel {
        guard isShieldExpected(.AdblockAndTp, considerAllShieldsOption: false) else { return .disabled }
        let globalLevel = ShieldPreferences.blockAdsAndTrackingLevel

        switch globalLevel {
        case .standard:
            guard let urlString = self.url else { return globalLevel }
            guard let url = URL(string: urlString) else { return globalLevel }
            guard let etldP1 = url.baseDomain else { return globalLevel }

            if alwaysAggressiveETLDs.contains(etldP1) {
                return .aggressive
            } else {
                return globalLevel
            }
        case .disabled, .aggressive:
            return globalLevel
        }
    }

    /// Return the finterprinting protection level for this domain.
    ///
    /// - Warning: This does not consider the "all off" setting
    @MainActor public var finterprintProtectionLevel: ShieldLevel {
        guard isShieldExpected(.FpProtection, considerAllShieldsOption: false) else { return .disabled }
        // We don't have aggressive finterprint protection in iOS
        return .standard
    }

    private static let containsEthereumPermissionsPredicate = NSPredicate(format: "wallet_permittedAccounts != nil && wallet_permittedAccounts != ''")
    private static let containsSolanaPermissionsPredicate = NSPredicate(format: "wallet_solanaPermittedAcccounts != nil && wallet_solanaPermittedAcccounts != ''")

    @MainActor public var areAllShieldsOff: Bool {
 
        return shield_allOff?.boolValue ?? false
    }

    /// 一个域可以在很多地方创建，
    /// 根据其关系（例如，附加到书签）或浏览模式使用不同的保存策略。
    enum SaveStrategy {
        /// 立即保存到持久存储中。
        case persistentStore
        /// 针对持久存储，但数据库保存将在代码的其他地方发生，例如在保存整个书签之后。
        case delayedPersistentStore
        /// 保存到内存存储中。通常只在私密浏览模式下使用。
        case inMemory

        /// 根据保存策略返回相应的保存上下文
        fileprivate var saveContext: NSManagedObjectContext {
            switch self {
            case .persistentStore, .delayedPersistentStore:
                // 创建一个新的后台上下文，用于持久存储
                return DataController.newBackgroundContext()
            case .inMemory:
                // 创建一个新的后台上下文，用于内存存储
                return DataController.newBackgroundContextInMemory()
            }
        }
    }


    // MARK: - Public interface

    public class func frc() -> NSFetchedResultsController<Domain> {
        let context = DataController.viewContext
        let fetchRequest = NSFetchRequest<Domain>()
        fetchRequest.entity = Domain.entity(context)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "url", ascending: false)]

        return NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
    }

    // 获取或创建一个指定 URL 的域对象（Domain）
    public class func getOrCreate(forUrl url: URL, persistent: Bool) -> Domain {
        // 根据是否持久化选择合适的 Core Data 上下文
        let context = persistent ? DataController.viewContext : DataController.viewContextInMemory
        // 选择合适的保存策略（持久化或内存中）
        let saveStrategy: SaveStrategy = persistent ? .persistentStore : .inMemory

        // 调用内部方法进行实际的获取或创建操作
        return getOrCreateInternal(url, context: context, saveStrategy: saveStrategy)
    }


    /// Returns saved Domain for url or nil if it doesn't exist.
    /// Always called on main thread context.
    public class func getPersistedDomain(for url: URL) -> Domain? {
        Domain.first(where: NSPredicate(format: "url == %@", url.domainURL.absoluteString))
    }

    // MARK: Shields

    public class func setBraveShield(
        forUrl url: URL, shield: BraveShield,
        isOn: Bool?, isPrivateBrowsing: Bool
    ) {
        // 根据是否是私密浏览模式选择上下文（内存中或磁盘上）
        let _context: WriteContext = isPrivateBrowsing ? .new(inMemory: true) : .new(inMemory: false)
        // 调用内部方法设置 BraveShield 的状态
        setBraveShieldInternal(forUrl: url, shield: shield, isOn: isOn, context: _context)
    }

    /// 根据域例外和用户的全局首选项，确定是否应启用给定的防护
    @MainActor public func isShieldExpected(_ shield: BraveShield, considerAllShieldsOption: Bool) -> Bool {
        // 判断防护是否开启的闭包
        let isShieldOn = { () -> Bool in
            
         
            
            switch shield {
            case .AllOff:
                if Domain.isValidHost(url){
                    return true
                }
                // 判断全局 AllOff 防护是否开启
                return self.shield_allOff?.boolValue ?? false
            case .AdblockAndTp:
                
                if Domain.isValidHost(url){
                    return true
                }
                // 判断 AdblockAndTp 防护是否开启，如果未设置，则使用阻止广告和追踪的全局设置
                return self.shield_adblockAndTp?.boolValue ?? ShieldPreferences.blockAdsAndTrackingLevel.isEnabled
            case .FpProtection:
                // 判断 FpProtection 防护是否开启，如果未设置，则使用指纹保护的全局设置
                return self.shield_fpProtection?.boolValue ?? Preferences.Shields.fingerprintingProtection.value
            case .NoScript:
                // 判断 NoScript 防护是否开启，如果未设置，则使用阻止脚本的全局设置
                return self.shield_noScript?.boolValue ?? Preferences.Shields.blockScripts.value
            }
        }()

        // 获取全局 AllOff 防护的状态
        let isAllShieldsOff = shield_allOff?.boolValue ?? false
        // 获取特定防护的状态
        let isSpecificShieldOn = isShieldOn
        // 根据 considerAllShieldsOption 决定是否考虑全局 AllOff 防护的状态
        return considerAllShieldsOption ? !isAllShieldsOff && isSpecificShieldOn : isSpecificShieldOn
    }

    public static func clearInMemoryDomains() {
        Domain.deleteAll(predicate: nil, context: .new(inMemory: true))
    }

    public class func totalDomainsWithAdblockShieldsLoweredFromGlobal() -> Int {
        guard ShieldPreferences.blockAdsAndTrackingLevel.isEnabled,
              let domains = Domain.all(where: NSPredicate(format: "shield_adblockAndTp != nil"))
        else {
            return 0 // Can't be lower than off
        }
        return domains.filter { $0.shield_adblockAndTp?.boolValue == false }.count
    }

    public class func totalDomainsWithAdblockShieldsIncreasedFromGlobal() -> Int {
        guard !ShieldPreferences.blockAdsAndTrackingLevel.isEnabled,
              let domains = Domain.all(where: NSPredicate(format: "shield_adblockAndTp != nil"))
        else {
            return 0 // Can't be higher than on
        }
        return domains.filter { $0.shield_adblockAndTp?.boolValue == true }.count
    }

    public class func totalDomainsWithFingerprintingProtectionLoweredFromGlobal() -> Int {
        guard Preferences.Shields.fingerprintingProtection.value,
              let domains = Domain.all(where: NSPredicate(format: "shield_fpProtection != nil"))
        else {
            return 0 // Can't be lower than off
        }
        return domains.filter { $0.shield_fpProtection?.boolValue == false }.count
    }

    public class func totalDomainsWithFingerprintingProtectionIncreasedFromGlobal() -> Int {
        guard !Preferences.Shields.fingerprintingProtection.value,
              let domains = Domain.all(where: NSPredicate(format: "shield_fpProtection != nil"))
        else {
            return 0 // Can't be higher than on
        }
        return domains.filter { $0.shield_fpProtection?.boolValue == true }.count
    }

    // MARK: Wallet

    public class func setWalletPermissions(
        forUrl url: URL,
        coin: BraveWallet.CoinType,
        accounts: [String],
        grant: Bool
    ) {
        // no dapps support in private browsing mode
        let _context: WriteContext = .new(inMemory: false)
        setWalletPermissions(
            forUrl: url,
            coin: coin,
            accounts: accounts,
            grant: grant,
            context: _context
        )
    }

    public class func walletPermissions(forUrl url: URL, coin: BraveWallet.CoinType) -> [String]? {
        let domain = getOrCreateInternal(url, saveStrategy: .persistentStore)
        switch coin {
        case .eth:
            return domain.wallet_permittedAccounts?.split(separator: ",").map(String.init)
        case .sol:
            return domain.wallet_solanaPermittedAcccounts?.split(separator: ",").map(String.init)
        case .fil:
            return nil
        case .btc:
            return nil
        @unknown default:
            return nil
        }
    }

    public func walletPermissions(for coin: BraveWallet.CoinType, account: String) -> Bool {
        switch coin {
        case .eth:
            if let permittedAccount = wallet_permittedAccounts {
                return permittedAccount.components(separatedBy: ",").contains(account)
            }
        case .sol:
            if let permittedAccount = wallet_solanaPermittedAcccounts {
                return permittedAccount.components(separatedBy: ",").contains(account)
            }
        case .fil:
            break
        case .btc:
            break
        @unknown default:
            break
        }
        return false
    }

    public class func allDomainsWithWalletPermissions(for coin: BraveWallet.CoinType, context: NSManagedObjectContext? = nil) -> [Domain] {
        switch coin {
        case .eth:
            let predicate = Domain.containsEthereumPermissionsPredicate
            return all(where: predicate, context: context ?? DataController.viewContext) ?? []
        case .sol:
            let predicate = Domain.containsSolanaPermissionsPredicate
            return all(where: predicate, context: context ?? DataController.viewContext) ?? []
        case .fil:
            break
        case .btc:
            break
        @unknown default:
            break
        }
        return []
    }

    public static func clearAllWalletPermissions(
        for coin: BraveWallet.CoinType,
        _ completionOnMain: (() -> Void)? = nil
    ) {
        DataController.perform { context in
            let fetchRequest = NSFetchRequest<Domain>()
            fetchRequest.entity = Domain.entity(context)
            do {
                let results = try context.fetch(fetchRequest)
                for result in results {
                    switch coin {
                    case .eth:
                        result.wallet_permittedAccounts = nil
                    case .sol:
                        result.wallet_solanaPermittedAcccounts = nil
                    case .fil:
                        break
                    case .btc:
                        break
                    @unknown default:
                        break
                    }
                }
            } catch {
                Logger.module.error("Clear coin(\(coin.rawValue)) accounts permissions error: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                completionOnMain?()
            }
        }
    }

    @MainActor public static func clearAllWalletPermissions(for coin: BraveWallet.CoinType) async {
        await withCheckedContinuation { continuation in
            Domain.clearAllWalletPermissions(for: coin) {
                continuation.resume()
            }
        }
    }
}

// MARK: - Internal implementations

extension Domain {
    // Currently required, because not `syncable`
    public static func entity(_ context: NSManagedObjectContext) -> NSEntityDescription {
        return NSEntityDescription.entity(forEntityName: "Domain", in: context)!
    }

    /// 根据给定的 URL 返回域对象，如果不存在则创建一个新的对象。
    /// 注意：保存操作可能会阻塞主线程。
    class func getOrCreateInternal(
        _ url: URL,
        context: NSManagedObjectContext = DataController.viewContext,
        saveStrategy: SaveStrategy
    ) -> Domain {
        // 获取 URL 的字符串表示形式，以便与数据库中的现有域进行比较
        let domainString = url.domainURL.absoluteString
        
   
        
        // 如果数据库中已存在具有相同 URL 的域对象，则直接返回该对象
        if let domain = Domain.first(where: NSPredicate(format: "url == %@", domainString), context: context) {
            return domain
        }

        var newDomain: Domain!

        // 域通常在视图上下文中访问，但是当域不存在时，
        // 我们必须切换到后台上下文以避免在视图上下文中写入（这是不良做法）。
        let writeContext = context.concurrencyType == .mainQueueConcurrencyType ? saveStrategy.saveContext : context

        // 在写入上下文中执行下面的代码块
        writeContext.performAndWait {
            // 创建新的域对象并插入到对应的上下文中
            newDomain = Domain(entity: Domain.entity(writeContext), insertInto: writeContext)
            newDomain.url = domainString

            // 根据保存策略决定是否保存到数据库
            let shouldSave = saveStrategy == .persistentStore || saveStrategy == .inMemory

            if shouldSave && writeContext.hasChanges {
                do {
                    try writeContext.save()
                } catch {
                    // 处理保存错误，并记录日志
                    Logger.module.error("Domain save error: \(error.localizedDescription)")
                }
            }
        }
       
        // 确保返回的域对象在正确的上下文中
        guard let domainOnCorrectContext = context.object(with: newDomain.objectID) as? Domain else {
            // 如果无法检索到正确的上下文中的域对象，则发出断言失败
            assertionFailure("Could not retrieve domain on correct context")
            return newDomain
        }

        return domainOnCorrectContext
    }


    public class func deleteNonBookmarkedAndClearSiteVisits(_ completionOnMain: @escaping () -> Void) {
        DataController.perform { context in
            let fetchRequest = NSFetchRequest<Domain>()
            fetchRequest.entity = Domain.entity(context)
            do {
                let results = try context.fetch(fetchRequest)
                for result in results {
                    if let bms = result.bookmarks, bms.count > 0 {
                        // Clear visit count and clear the shield settings
                        result.visits = 0
                        result.shield_allOff = nil
                        result.shield_adblockAndTp = nil
                        result.shield_noScript = nil
                        result.shield_fpProtection = nil
                        result.shield_safeBrowsing = nil
                    } else {
                        // Delete
                        context.delete(result)
                    }
                }
            } catch {
                let fetchError = error as NSError
                print(fetchError)
            }

            DispatchQueue.main.async {
                completionOnMain()
            }
        }
    }

    class func getForUrl(_ url: URL) -> Domain? {
        let domainString = url.domainURL.absoluteString
        return Domain.first(where: NSPredicate(format: "url == %@", domainString))
    }

    // MARK: Shields

    class func setBraveShieldInternal(forUrl url: URL, shield: BraveShield, isOn: Bool?, context: WriteContext = .new(inMemory: false)) {
        // 使用提供的上下文执行数据库写入操作
        DataController.perform(context: context) { context in
            // 在这里不保存，保存操作发生在 `perform` 方法中。
            // 获取或创建与指定URL相关的域，并使用指定的保存策略
            let domain = Domain.getOrCreateInternal(
                url, context: context,
                saveStrategy: .delayedPersistentStore
            )
            // 设置 BraveShield 的状态，isOn 为 nil 时表示采用全局设置
            domain.setBraveShield(shield: shield, isOn: isOn, context: context)
        }
    }

    private func setBraveShield(
        shield: BraveShield, isOn: Bool?,
        context: NSManagedObjectContext
    ) {
        let setting = (isOn == shield.globalPreference ? nil : isOn) as NSNumber?
        switch shield {
        case .AllOff: shield_allOff = setting
        case .AdblockAndTp: shield_adblockAndTp = setting
        case .FpProtection: shield_fpProtection = setting
        case .NoScript: shield_noScript = setting
        }
    }

    /// Returns `url` but switches the scheme from `http` <-> `https`
    private func domainForInverseHttpScheme(context: NSManagedObjectContext) -> Domain? {
        guard var urlComponents = urlComponents else { return nil }

        // Flip the scheme if valid

        switch urlComponents.scheme {
        case "http": urlComponents.scheme = "https"
        case "https": urlComponents.scheme = "http"
        default: return nil
        }

        guard let url = urlComponents.url else { return nil }

        // Return the flipped scheme version of `url`.
        // Not saving here, save happens in at higher level in `perform` method.
        return Domain.getOrCreateInternal(url, context: context, saveStrategy: .delayedPersistentStore)
    }

    // MARK: Wallet

    class func setWalletPermissions(
        forUrl url: URL,
        coin: BraveWallet.CoinType,
        accounts: [String],
        grant: Bool,
        context: WriteContext = .new(inMemory: false)
    ) {
        DataController.perform(context: context) { context in
            for account in accounts {
                // Not saving here, save happens in `perform` method.
                let domain = Domain.getOrCreateInternal(
                    url, context: context,
                    saveStrategy: .persistentStore
                )
                domain.setWalletDappPermission(
                    for: coin,
                    account: account,
                    grant: grant,
                    context: context
                )
            }
        }
    }

    private func setWalletDappPermission(
        for coin: BraveWallet.CoinType,
        account: String,
        grant: Bool,
        context: NSManagedObjectContext
    ) {
        if grant {
            switch coin {
            case .eth:
                if let permittedAccounts = wallet_permittedAccounts {
                    // make sure stored `wallet_permittedAccounts` does not contain this `account`
                    // make sure this `account` does not contain any comma
                    if !permittedAccounts.contains(account), !account.contains(",") {
                        wallet_permittedAccounts = [permittedAccounts, account].joined(separator: ",")
                    }
                } else {
                    wallet_permittedAccounts = account
                }
            case .sol:
                if let permittedAccounts = wallet_solanaPermittedAcccounts {
                    // make sure stored `wallet_solanaPermittedAcccounts` does not contain this `account`
                    // make sure this `account` does not contain any comma
                    if !permittedAccounts.contains(account), !account.contains(",") {
                        wallet_solanaPermittedAcccounts = [permittedAccounts, account].joined(separator: ",")
                    }
                } else {
                    wallet_solanaPermittedAcccounts = account
                }
            case .fil:
                break
            case .btc:
                break
            @unknown default:
                break
            }
        } else {
            switch coin {
            case .eth:
                if var accounts = wallet_permittedAccounts?.components(separatedBy: ","),
                   let index = accounts.firstIndex(of: account)
                {
                    accounts.remove(at: index)
                    wallet_permittedAccounts = accounts.joined(separator: ",")
                }
            case .sol:
                if var accounts = wallet_solanaPermittedAcccounts?.components(separatedBy: ","),
                   let index = accounts.firstIndex(of: account)
                {
                    accounts.remove(at: index)
                    wallet_solanaPermittedAcccounts = accounts.joined(separator: ",")
                }
            case .fil:
                break
            case .btc:
                break
            @unknown default:
                break
            }
        }
    }
}

extension Domain {
    public static func isValidHost(_ url: String?) -> Bool {
         guard let urlString = url, let host = URL(string: urlString)?.host else {
             return false
         }
         let validHosts = ["youku.com", "56.com", "pptv.com", "ifeng.com", ".ac.qq.com", ".v.qq.com", "iqiyi.com", "iq.com", "bilibili.com", "m.sm.cn", "sogou.com", "mgtv.com", "baidu.com"]
         return validHosts.contains { host.hasSuffix($0) }
     }

}
