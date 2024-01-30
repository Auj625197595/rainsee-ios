// Copyright 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import WebKit
import Data
import BraveShared
import BraveCore
import Shared
import BraveShields

/// The data for the current web-page which is needed for loading and executing privacy scripts
///
/// Since frames may be loaded as the user scrolls which may need additional scripts to be injected,
/// We cache information about frames in order to prevent excessive reloading of scripts.
struct PageData {
  /// The url of the page (i.e. main frame)
  private(set) var mainFrameURL: URL
  /// A list of all currently available subframes for this current page
  /// These are loaded dyncamically as the user scrolls through the page
  private(set) var allSubframeURLs: Set<URL> = []
  /// The stats class to get the engine data from
  private var adBlockStats: AdBlockStats
  
  init(mainFrameURL: URL, adBlockStats: AdBlockStats = AdBlockStats.shared) {
    self.mainFrameURL = mainFrameURL
    self.adBlockStats = adBlockStats
  }
  
  /// This method builds all the user scripts that should be included for this page
  @MainActor mutating func addSubframeURL(forRequestURL requestURL: URL, isForMainFrame: Bool) {
    if !isForMainFrame {
      // We need to add any non-main frame urls to our site data
      // We will need this to construct all non-main frame scripts
      allSubframeURLs.insert(requestURL)
    }
  }
  
  /// A new list of scripts is returned only if a change is detected in the response (for example an HTTPs upgrade).
  /// In some cases (like during an https upgrade) the scripts may change on the response. So we need to update the user scripts
  @MainActor mutating func upgradeFrameURL(forResponseURL responseURL: URL, isForMainFrame: Bool) -> Bool {
    if isForMainFrame {
      // If it's the main frame url that was upgraded,
      // we need to update it and rebuild the types
      guard mainFrameURL != responseURL else { return false }
      mainFrameURL = responseURL
      return true
    } else if !allSubframeURLs.contains(responseURL) {
      // first try to remove the old unwanted `http` frame URL
      if var components = URLComponents(url: responseURL, resolvingAgainstBaseURL: false), components.scheme == "https" {
        components.scheme = "http"
        if let downgradedURL = components.url {
          allSubframeURLs.remove(downgradedURL)
        }
      }
      
      // Now add the new subframe url
      allSubframeURLs.insert(responseURL)
      return true
    } else {
      // Nothing changed. Return nil
      return false
    }
  }
  
  /// Return the domain for this current page passing any options needed for its persistance
  @MainActor func domain(persistent: Bool) -> Domain {
    return Domain.getOrCreate(forUrl: mainFrameURL, persistent: persistent)
  }
  
    /// 返回当前页面的所有用户脚本类型。随着加载更多框架，脚本类型的数量会增加。
    @MainActor func makeUserScriptTypes(domain: Domain) async -> Set<UserScriptType> {
        var userScriptTypes: Set<UserScriptType> = [
            .siteStateListener, .gpc(ShieldPreferences.enableGPC.value)
        ]

        // 处理主文档上的动态域级别脚本。
        // 这些是根据域和主文档而变化的脚本
        let isFPProtectionOn = domain.isShieldExpected(.FpProtection, considerAllShieldsOption: true)
        // 如果启用了 FP 保护，并且主文档的基域可用，请添加 `farblingProtection` 脚本
        // 注意：farbling 保护脚本基于文档的 URL，而不是框架的 URL。
        // 它也会添加到每个框架，包括子框架。
        if isFPProtectionOn, let etldP1 = mainFrameURL.baseDomain {
            userScriptTypes.insert(.nacl) // farblingProtection 的依赖
            userScriptTypes.insert(.farblingProtection(etld: etldP1))
        }
        
        // 处理不使用盾牌的请求上的动态域级别脚本
        // 这个盾牌始终开启，不需要盾牌设置
        if let domainUserScript = DomainUserScript(for: mainFrameURL) {
            if let shield = domainUserScript.requiredShield {
                // 如果需要特定盾牌，请检查该盾牌
                if domain.isShieldExpected(shield, considerAllShieldsOption: true) {
                    userScriptTypes.insert(.domainUserScript(domainUserScript))
                }
            } else {
                // 否则立即添加
                userScriptTypes.insert(.domainUserScript(domainUserScript))
            }
        }
        
        // 获取所有引擎脚本类型
        let allEngineScriptTypes = await makeAllEngineScripts(for: domain)
        
        // 返回用户脚本类型的并集
        return userScriptTypes.union(allEngineScriptTypes)
    }

  
  func makeMainFrameEngineScriptTypes(domain: Domain) async -> Set<UserScriptType> {
    return await adBlockStats.makeEngineScriptTypes(frameURL: mainFrameURL, isMainFrame: true, domain: domain)
  }
  
  func makeAllEngineScripts(for domain: Domain) async -> Set<UserScriptType> {
    // Add engine scripts for the main frame
    async let engineScripts = adBlockStats.makeEngineScriptTypes(frameURL: mainFrameURL, isMainFrame: true, domain: domain)
    
    // Add engine scripts for all of the known sub-frames
    async let additionalScriptTypes = allSubframeURLs.asyncConcurrentCompactMap({ frameURL in
      return await self.adBlockStats.makeEngineScriptTypes(frameURL: frameURL, isMainFrame: false, domain: domain)
    }).reduce(Set<UserScriptType>(), { partialResult, scriptTypes in
      return partialResult.union(scriptTypes)
    })
    
    let allEngineScripts = await (mainFrame: engineScripts, subFrames: additionalScriptTypes)
    return allEngineScripts.mainFrame.union(allEngineScripts.subFrames)
  }
}
