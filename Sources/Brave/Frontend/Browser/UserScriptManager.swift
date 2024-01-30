/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import WebKit
import Shared
import Data
import BraveCore
import Preferences
import BraveWallet
import os.log

private class ScriptLoader: TabContentScriptLoader { }

class UserScriptManager {
  static let shared = UserScriptManager()
  
  static let securityToken = ScriptLoader.uniqueID
  static let walletSolanaNameSpace = "W\(ScriptLoader.uniqueID)"
  
  private let alwaysEnabledScripts: [ScriptType] = [
    .faviconFetcher,
    .rewardsReporting,
    .playlist,
    .resourceDownloader,
    .windowRenderHelper,
    .readyStateHelper,
    .youtubeQuality,
    .customUserScriptsHandler
  ]
  
  /// Scripts that are loaded after `staticScripts`
  private var dynamicScripts: [ScriptType: WKUserScript] = {
    ScriptType.allCases.reduce(into: [:]) { $0[$1] = $1.script }
  }()
  
    
    public func fresh(){
        dynamicScripts = {
          ScriptType.allCases.reduce(into: [:]) { $0[$1] = $1.script }
        }()
    }
    /// 这是在 `baseScripts` 之后、`dynamicScripts` 之前加载的经过 web 打包的脚本
    private let staticScripts: [WKUserScript] = {
        return [
            // 在文档开始时注入，不仅限于主框架，不使用沙盒
            (WKUserScriptInjectionTime.atDocumentStart, mainFrameOnly: false, sandboxed: false),
            // 在文档结束时注入，不仅限于主框架，不使用沙盒
            (WKUserScriptInjectionTime.atDocumentEnd, mainFrameOnly: false, sandboxed: false),
            // 在文档开始时注入，不仅限于主框架，使用沙盒
            (WKUserScriptInjectionTime.atDocumentStart, mainFrameOnly: false, sandboxed: true),
            // 在文档结束时注入，不仅限于主框架，使用沙盒
            (WKUserScriptInjectionTime.atDocumentEnd, mainFrameOnly: false, sandboxed: true),
            // 在文档开始时注入，仅限于主框架，不使用沙盒
            (WKUserScriptInjectionTime.atDocumentStart, mainFrameOnly: true, sandboxed: false),
            // 在文档结束时注入，仅限于主框架，不使用沙盒
            (WKUserScriptInjectionTime.atDocumentEnd, mainFrameOnly: true, sandboxed: false),
            // 在文档开始时注入，仅限于主框架，使用沙盒
            (WKUserScriptInjectionTime.atDocumentStart, mainFrameOnly: true, sandboxed: true),
            // 在文档结束时注入，仅限于主框架，使用沙盒
            (WKUserScriptInjectionTime.atDocumentEnd, mainFrameOnly: true, sandboxed: true),
        ].compactMap { (injectionTime, mainFrameOnly, sandboxed) in
            
            // 构造脚本名称
            let name = (mainFrameOnly ? "MainFrame" : "AllFrames") + "AtDocument" + (injectionTime == .atDocumentStart ? "Start" : "End") + (sandboxed ? "Sandboxed" : "")
            
            // 如果能够加载指定名称的用户脚本
            if let source = ScriptLoader.loadUserScript(named: name) {
                // 在源代码周围包装一个函数，同时添加安全令牌
                let wrappedSource = "(function() { const SECURITY_TOKEN = '\(UserScriptManager.securityToken)'; \(source) })()"
                
                // 返回一个 WKUserScript 对象
                return WKUserScript(
                    source: wrappedSource,
                    injectionTime: injectionTime,
                    forMainFrameOnly: mainFrameOnly,
                    in: sandboxed ? .defaultClient : .page)
            }
            
            // 无法加载指定名称的用户脚本，则返回 nil
            return nil
        }
    }()

    /// 在所有其他脚本之前注入的基础脚本
    private let baseScripts: [WKUserScript] = {
        [
            // 在文档开始时注入，不仅限于主框架，不使用沙盒
            (WKUserScriptInjectionTime.atDocumentStart, mainFrameOnly: false, sandboxed: false),
            // 在文档结束时注入，不仅限于主框架，不使用沙盒
            (WKUserScriptInjectionTime.atDocumentEnd, mainFrameOnly: false, sandboxed: false),
            // 在文档开始时注入，不仅限于主框架，使用沙盒
            (WKUserScriptInjectionTime.atDocumentStart, mainFrameOnly: false, sandboxed: true),
            // 在文档结束时注入，不仅限于主框架，使用沙盒
            (WKUserScriptInjectionTime.atDocumentEnd, mainFrameOnly: false, sandboxed: true),
        ].compactMap { (injectionTime, mainFrameOnly, sandboxed) in
            
            // 如果能够加载指定名称的用户脚本
            if let source = ScriptLoader.loadUserScript(named: "__firefox__") {
                // 返回一个 WKUserScript 对象
                return WKUserScript(
                    source: source,
                    injectionTime: injectionTime,
                    forMainFrameOnly: mainFrameOnly,
                    in: sandboxed ? .defaultClient : .page)
            }
            
            // 无法加载指定名称的用户脚本，则返回 nil
            return nil
        }
    }()

  
  private var walletEthProviderScript: WKUserScript?
  private var walletSolProviderScript: WKUserScript?
  private var walletSolanaWeb3Script: WKUserScript?
  private var walletSolanaWalletStandardScript: WKUserScript?
  
  enum ScriptType: String, CaseIterable {
    case faviconFetcher
    case cookieBlocking
    case rewardsReporting
    case mediaBackgroundPlay
    case playlistMediaSource
    case playlist
    case nightMode
    case deAmp
    case requestBlocking
    case trackerProtectionStats
    case resourceDownloader
    case windowRenderHelper
    case readyStateHelper
  //  case ethereumProvider
    case youtubeQuality
      case customUserScriptsHandler
    
    fileprivate var script: WKUserScript? {
      switch self {
        // Conditionally enabled scripts
      case .cookieBlocking: return loadScript(named: "CookieControlScript")
      case .mediaBackgroundPlay: return loadScript(named: "MediaBackgroundingScript")
      case .playlistMediaSource: return loadScript(named: "PlaylistSwizzlerScript")
      case .nightMode: return NightModeScriptHandler.userScript
      case .deAmp: return DeAmpScriptHandler.userScript
      case .requestBlocking: return RequestBlockingContentScriptHandler.userScript
      case .trackerProtectionStats: return ContentBlockerHelper.userScript
  //    case .ethereumProvider: return EthereumProviderScriptHandler.userScript
        
      // Always enabled scripts
      case .faviconFetcher: return FaviconScriptHandler.userScript
      case .rewardsReporting: return RewardsReportingScriptHandler.userScript
      case .playlist: return PlaylistScriptHandler.userScript
      case .resourceDownloader: return ResourceDownloadScriptHandler.userScript
      case .windowRenderHelper: return WindowRenderScriptHandler.userScript
      case .readyStateHelper: return ReadyStateScriptHandler.userScript
      case .youtubeQuality: return YoutubeQualityScriptHandler.userScript
      case .customUserScriptsHandler: return CustomUserScriptsHandler.userScript
      }
    }
    
    private func loadScript(named: String) -> WKUserScript? {
      guard var script = ScriptLoader.loadUserScript(named: named) else {
        return nil
      }
      
      script = ScriptLoader.secureScript(handlerNamesMap: [:], securityToken: "", script: script)
      return WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
    }
  }
  
//  func fetchWalletScripts(from braveWalletAPI: BraveWalletAPI) {
//    if let ethJS = braveWalletAPI.providerScripts(for: .eth)[.ethereum] {
//      let providerJS = """
//          window.__firefox__.execute(function($, $Object) {
//            if (window.isSecureContext) {
//              \(ethJS)
//            }
//          });
//          """
//      walletEthProviderScript = WKUserScript(
//        source: providerJS,
//        injectionTime: .atDocumentStart,
//        forMainFrameOnly: true,
//        in: EthereumProviderScriptHandler.scriptSandbox
//      )
//    }
//    if let solanaWeb3Script = braveWalletAPI.providerScripts(for: .sol)[.solanaWeb3] {
//      let script = """
//        // Define a global variable with a random name
//        // Local variables are NOT enumerable!
//        let \(UserScriptManager.walletSolanaNameSpace);
//        
//        window.__firefox__.execute(function($, $Object, $Function, $Array) {
//          // Inject Solana as a Local Variable.
//          \(solanaWeb3Script)
//        
//          \(UserScriptManager.walletSolanaNameSpace) = $({
//            solanaWeb3: $(solanaWeb3)
//          });
//        
//          // Failed to load SolanaWeb3
//          if (typeof \(UserScriptManager.walletSolanaNameSpace) === 'undefined') {
//            return;
//          }
//        
//          const freezeExceptions = $Array.of("BN");
//        
//          for (const value of $Object.values(\(UserScriptManager.walletSolanaNameSpace).solanaWeb3)) {
//            if (!value) {
//              continue;
//            }
//        
//            $.extensiveFreeze(value, freezeExceptions);
//          }
//        
//          $.deepFreeze(\(UserScriptManager.walletSolanaNameSpace).solanaWeb3);
//          $.deepFreeze(\(UserScriptManager.walletSolanaNameSpace));
//        });
//        """
//      self.walletSolanaWeb3Script = WKUserScript(
//        source: script,
//        injectionTime: .atDocumentStart,
//        forMainFrameOnly: true,
//        in: SolanaProviderScriptHandler.scriptSandbox
//      )
//    }
//    if let walletSolProviderScript = braveWalletAPI.providerScripts(for: .sol)[.solana] {
//      let script = """
//      window.__firefox__.execute(function($, $Object) {
//        \(walletSolProviderScript)
//      });
//      """
//      self.walletSolProviderScript = WKUserScript(
//        source: script,
//        injectionTime: .atDocumentStart,
//        forMainFrameOnly: true,
//        in: SolanaProviderScriptHandler.scriptSandbox
//      )
//    }
//    if let walletStandardScript = braveWalletAPI.providerScripts(for: .sol)[.walletStandard] {
//      let script = """
//      window.__firefox__.execute(function($, $Object) {
//         \(walletStandardScript)
//         window.addEventListener('wallet-standard:app-ready', (e) => {
//            walletStandardBrave.initialize(window.braveSolana);
//        })
//      });
//      """
//      self.walletSolanaWalletStandardScript = WKUserScript(
//        source: script,
//        injectionTime: .atDocumentStart,
//        forMainFrameOnly: true,
//        in: SolanaProviderScriptHandler.scriptSandbox
//      )
//    }
//  }
  
    public func loadScripts(into webView: WKWebView, scripts: Set<ScriptType>) {
        var scripts = scripts
        
        // 获取 WebView 的配置控制器
        webView.configuration.userContentController.do { scriptController in
            // 移除所有之前添加的用户脚本
            scriptController.removeAllUserScripts()
            
            // 注入所有基础脚本
            self.baseScripts.forEach {
                scriptController.addUserScript($0)
            }
            
            // 在请求阻塞之前注入追踪保护统计脚本
            // 这是因为它需要在请求阻塞之前钩住请求
            if scripts.contains(.trackerProtectionStats), let script = self.dynamicScripts[.trackerProtectionStats] {
                scripts.remove(.trackerProtectionStats)
                scriptController.addUserScript(script)
            }
            
            // 在其他脚本之前注入请求阻塞脚本
            // 这是因为它需要在 RewardsReporting 之前钩住请求
            if scripts.contains(.requestBlocking), let script = self.dynamicScripts[.requestBlocking] {
                scripts.remove(.requestBlocking)
                scriptController.addUserScript(script)
            }
            
            // 注入所有静态脚本
            self.staticScripts.forEach {
                scriptController.addUserScript($0)
            }
            
            // 注入所有动态脚本，但始终启用的脚本
            self.dynamicScripts.filter({ self.alwaysEnabledScripts.contains($0.key) }).forEach {
                scriptController.addUserScript($0.value)
            }
            
            // 注入所有可选的脚本
            self.dynamicScripts.filter({ scripts.contains($0.key) }).forEach {
                scriptController.addUserScript($0.value)
            }
        }
    }

  
    // TODO: Get rid of this OR refactor wallet and domain scripts
    func loadCustomScripts(
      into tab: Tab,
      userScripts: Set<ScriptType>,
      customScripts: Set<UserScriptType>
    ) {
      guard let webView = tab.webView else {
        // 如果 Tab 中没有 WebView，记录日志并返回
        Logger.module.info("Injecting Scripts into a Tab that has no WebView")
        return
      }
      
      let logComponents = [
        // 将用户脚本和自定义脚本按指定顺序拼接成日志记录
        userScripts.sorted(by: { $0.rawValue < $1.rawValue}).map { scriptType in
          " \(scriptType.rawValue)"
        }.joined(separator: "\n"),
        customScripts.sorted(by: { $0.order < $1.order}).map { scriptType in
          " #\(scriptType.order) \(scriptType.debugDescription)"
        }.joined(separator: "\n")
      ]
      // 记录加载的脚本数量和详细信息
      ContentBlockerManager.log.debug("Loaded \(userScripts.count + customScripts.count) script(s): \n\(logComponents.joined(separator: "\n"))")
      // 调用 loadScripts 方法将用户脚本加载到 WebView 中
      loadScripts(into: webView, scripts: userScripts)
      
      webView.configuration.userContentController.do { scriptController in
        // TODO: Somehow refactor wallet and get rid of this
        // Inject WALLET specific scripts
        
        // 如果 Tab 不是私密模式，且默认以太坊钱包类型为 Brave
//        if !tab.isPrivate,
//           Preferences.Wallet.WalletType(rawValue: Preferences.Wallet.defaultEthWallet.value) == .brave,
//           let script = self.dynamicScripts[.ethereumProvider] {
//          
//          // 注入以太坊提供程序脚本
//          scriptController.addUserScript(script)
//
//          if let walletEthProviderScript = walletEthProviderScript {
//            scriptController.addUserScript(walletEthProviderScript)
//          }
//        }
        
//        // 注入 SolanaWeb3Script.js
//        if !tab.isPrivate,
//           Preferences.Wallet.WalletType(rawValue: Preferences.Wallet.defaultSolWallet.value) == .brave,
//           let solanaWeb3Script = self.walletSolanaWeb3Script {
//          scriptController.addUserScript(solanaWeb3Script)
//        }
//        
//        // 如果 Tab 不是私密模式，且默认 Solana 钱包类型为 Brave
//        if !tab.isPrivate,
//           Preferences.Wallet.WalletType(rawValue: Preferences.Wallet.defaultSolWallet.value) == .brave,
//           let script = self.dynamicScripts[.solanaProvider] {
//
//          // 注入 Solana 提供程序脚本
//          scriptController.addUserScript(script)
//
//          if let walletSolProviderScript = walletSolProviderScript {
//            scriptController.addUserScript(walletSolProviderScript)
//          }
//        }
//        
//        // 如果 Tab 不是私密模式，注入 Solana 标准钱包脚本
//        if !tab.isPrivate,
//           let walletStandardScript = self.walletSolanaWalletStandardScript {
//          scriptController.addUserScript(walletStandardScript)
//        }
        
        // TODO: Refactor this and get rid of the `UserScriptType`
        // 注入自定义脚本
        for userScriptType in customScripts.sorted(by: { $0.order < $1.order }) {
          do {
            let script = try ScriptFactory.shared.makeScript(for: userScriptType)
            scriptController.addUserScript(script)
          } catch {
            assertionFailure("Should never happen. The scripts are packed in the project and loading/modifying should always be possible.")
            Logger.module.error("\(error.localizedDescription)")
          }
        }
      }
    }

}
