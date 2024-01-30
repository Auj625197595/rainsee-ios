/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import BraveCore
import Foundation
import os.log
import Preferences
import Shared
import Storage
import SwiftyJSON
import WebKit

class LoginsScriptHandler: TabContentScript {
    private weak var tab: Tab?
    private let profile: Profile
    private let passwordAPI: BravePasswordAPI

    private var snackBar: SnackBar?

    required init(tab: Tab, profile: Profile, passwordAPI: BravePasswordAPI) {
        self.tab = tab
        self.profile = profile
        self.passwordAPI = passwordAPI
    }

    static let scriptName = "LoginsScript"
    static let scriptId = UUID().uuidString
    static let scriptSandbox: WKContentWorld = .defaultClient
    static let messageHandlerName = "loginsScriptMessageHandler"
    static let userScript: WKUserScript? = nil

    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage, replyHandler: (Any?, String?) -> Void) {
        // 在方法结束时调用replyHandler，确保始终调用
        defer { replyHandler(nil, nil) }

        // 验证接收到的消息是否具有正确的安全令牌
        if !verifyMessage(message: message, securityToken: UserScriptManager.securityToken) {
            assertionFailure("缺少必需的安全令牌。")
            return
        }

        // 将消息体解析为字典
        guard let body = message.body as? [String: AnyObject] else {
            return
        }

        // 从消息体中获取 "data" 键对应的字典
        guard let res = body["data"] as? [String: AnyObject] else { return }

        // 从字典中获取 "type" 键对应的字符串
        guard let type = res["type"] as? String else { return }

        // 在尝试检查登录信息之前，检查应用是否处于前台运行且未关闭
        guard UIApplication.shared.applicationState == .active && !profile.isShutdown else {
            return
        }

        // 获取消息的请求URL
        if let url = message.frameInfo.request.url {
            // 仅处理主框架请求，以避免XSS攻击
            if type == "request" {
                // 获取保存的登录信息并调用自动填充请求的凭据
                passwordAPI.getSavedLogins(for: url, formScheme: .typeHtml) { [weak self] logins in
                    guard let self = self else { return }

                    if let requestId = res["requestId"] as? String {
                        self.autoFillRequestedCredentials(
                            formSubmitURL: res["formSubmitURL"] as? String ?? "",
                            logins: logins,
                            requestId: requestId,
                            frameInfo: message.frameInfo)
                    }
                }
            } else if type == "submit" {
                // 如果用户选择保存登录信息，更新或保存凭据
                if Preferences.General.saveLogins.value {
                    updateORSaveCredentials(for: url, script: res)
                }
            }
        }
    }

    private func updateORSaveCredentials(for url: URL, script: [String: Any]) {
        // 通过密码API获取脚本中的凭据信息
        guard let scriptCredentials = passwordAPI.fetchFromScript(url, script: script),
              let username = scriptCredentials.usernameValue,
              scriptCredentials.usernameElement != nil,
              let password = scriptCredentials.passwordValue,
              scriptCredentials.passwordElement != nil
        else {
            Logger.module.debug("脚本中缺少凭据信息")
            return
        }

        // 检查密码是否为空
        if password.isEmpty {
            Logger.module.debug("密码为空")
            return
        }

        // 通过密码API获取保存的登录信息
        passwordAPI.getSavedLogins(for: url, formScheme: .typeHtml) { [weak self] logins in
            guard let self = self else { return }

            // 遍历保存的登录信息
            for login in logins {
                guard let usernameLogin = login.usernameValue else {
                    continue
                }

                // 检查用户名是否与脚本中的用户名相匹配
                if usernameLogin.caseInsensitivelyEqual(to: username) {
                    // 如果密码相同，则不进行任何操作
                    if password == login.passwordValue {
                        return
                    }

                    // 如果密码不同，则显示更新提示
                    self.showUpdatePrompt(from: login, to: scriptCredentials)
                    return
                } else {
                    // 如果用户名不匹配，则显示添加提示
                    self.showAddPrompt(for: scriptCredentials)
                    return
                }
            }

            // 如果没有匹配的用户名，则显示添加提示
            self.showAddPrompt(for: scriptCredentials)
        }
    }

    private func showAddPrompt(for login: PasswordForm) {
        addSnackBarForPrompt(for: login, isUpdating: false) { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async {
                let currentDate = Date()
                let timestamp = currentDate.timeIntervalSince1970
                Preferences.SyncRain.syncPwTime.value = Int(timestamp)

                self.passwordAPI.addLogin(login)
            }
        }
    }

    private func showUpdatePrompt(from old: PasswordForm, to new: PasswordForm) {
        addSnackBarForPrompt(for: new, isUpdating: true) { [weak self] in
            guard let self = self else { return }

            self.passwordAPI.updateLogin(new, oldPasswordForm: old)
        }
    }

    private func addSnackBarForPrompt(for login: PasswordForm, isUpdating: Bool, _ completion: @escaping () -> Void) {
        guard let username = login.usernameValue else {
            return
        }

        // Remove the existing prompt
        if let existingPrompt = snackBar {
            tab?.removeSnackbar(existingPrompt)
        }

        let promptMessage = String(
            format: isUpdating ? Strings.updateLoginUsernamePrompt : Strings.saveLoginUsernamePrompt, username,
            login.displayURLString)

        snackBar = TimerSnackBar(
            text: promptMessage,
            img: isUpdating ? UIImage(named: "key", in: .module, compatibleWith: nil)! : UIImage(named: "shields-menu-icon", in: .module, compatibleWith: nil)!)

        let dontSaveORUpdate = SnackButton(
            title: isUpdating ? Strings.loginsHelperDontUpdateButtonTitle : Strings.loginsHelperDontSaveButtonTitle,
            accessibilityIdentifier: "UpdateLoginPrompt.dontSaveUpdateButton")
        { [unowned self] bar in
            self.tab?.removeSnackbar(bar)
            self.snackBar = nil
        }

        let saveORUpdate = SnackButton(
            title: isUpdating ? Strings.loginsHelperUpdateButtonTitle : Strings.loginsHelperSaveLoginButtonTitle,
            accessibilityIdentifier: "UpdateLoginPrompt.saveUpdateButton")
        { [unowned self] bar in
            self.tab?.removeSnackbar(bar)
            self.snackBar = nil

            completion()
        }

        snackBar?.addButton(dontSaveORUpdate)
        snackBar?.addButton(saveORUpdate)

        if let bar = snackBar {
            tab?.addSnackbar(bar)
        }
    }

    // 处理自动填充请求的凭证信息
    private func autoFillRequestedCredentials(formSubmitURL: String, logins: [PasswordForm], requestId: String, frameInfo: WKFrameInfo) {
        // 获取安全原点信息
        let securityOrigin = frameInfo.securityOrigin

        // 创建JSON对象
        var jsonObj = [String: Any]()
        jsonObj["requestId"] = requestId
        jsonObj["name"] = "RemoteLogins:loginsFound"
        jsonObj["logins"] = logins.compactMap { loginData -> [String: String]? in
            // 如果是主框架，返回完整的凭证信息
            if frameInfo.isMainFrame {
                return loginData.toRainseeDict(formSubmitURL: formSubmitURL)
            }

            // 检查当前标签页是否有URL，并且框架未被修改
            guard let currentURL = tab?.webView?.url,
                  LoginsScriptHandler.checkIsSameFrame(
                      url: currentURL,
                      frameScheme: securityOrigin.protocol,
                      frameHost: securityOrigin.host,
                      framePort: securityOrigin.port)
            else {
                return nil
            }

            // 如果不是主框架，仅返回用户名，不包含密码
            // iOS上Chromium也采取了相同的做法
            // Firefox不支持第三方框架或iFrames
            if let updatedLogin = loginData.copy() as? PasswordForm {
                updatedLogin.update(loginData.usernameValue, passwordValue: "")

                return updatedLogin.toDict(formSubmitURL: formSubmitURL)
            }

            return nil
        }

        // 将JSON对象转为JSON字符串
        let json = JSON(jsonObj["logins"])
        guard let jsonString = json.stringValue() else {
            return
        }
     let NOTIFYJS = "!function(){if(window.yujianinjectloginpw){return;};window.yujianinjectloginpw=true;const e=\"auto_fill_passwd\",n=\"auto_fill_card\",p=\"auto_fill_addr\",o=\"auto_fill_none\",f=[\"address\",\"phone\",\"company\",\"email\",\"first_name\",\"last_name\",\"zip\",\"card_number\",\"expiry_date\",\"password\",\"login_name\",\"card_owner\"],m={login_name:[\"name\",\"username\",\"用户名\",\"email\",\"phone\",\"account\",\"sign\",\"account\",\"login\",\"usr\",\"nick\",\"手机\",\"邮箱\",\"账号\"],password:[\"passwd\",\"password\",\"密码\"],address:[\"address\",\"地址\",\"addr\",\"住址\"],phone:[\"phone\",\"tel\",\"电话\",\"手机\",\"mobile\"],company:[\"company\",\"公司\",\"单位\"],email:[\"email\",\"邮箱\"],first_name:[\"name\",\"user\",\"usr\",\"first_name\",\"firstname\"],last_name:[\"lastname,last_name\"],zip:[\"zip\",\"邮编\",\"post\"],card_number:[\"card\",\"number\",\"卡号\",\"信用卡\"],card_owner:[\"name\",\"owner\"],expiry_date:[\"yymm\",\"expiry\"]};var g,r,i={},u=o,a=null,l=[],s=[];function _(){return\"_\"+(new Date).valueOf()}function d(e,t){e.value=t;var t=document.createEvent(\"Events\");t.initEvent(\"input\",!0,!0),e.dispatchEvent(t),(t=e)&&(t.style.background=\"#E2ECFE\",t.style.backgroundClip=\"border-box\")}function c(e){if(\"password\"==e.type)return\"password\";for(var t in m)if(u!=p||\"login_name\"!=t)for(var n=m[t],o=e.attributes,a=0;a<o.length;a++)for(var r=o[a],i=0;i<n.length;i++)if(\"value\"!=r.name){var l=n[i],s=e.getAttribute(r.name);if(s&&0<=s.indexOf(l))return t}return\"email\"==e.type?\"email\":\"tel\"==e.type?\"phone\":\"none\"}function y(){console.log(\">>>>> do sync form data >>>>>>>>>\"),i.update_at=(new Date).valueOf(),JSInterface.onKeyValueMsg('updateAutoFill',JSON.stringify(i))}function v(e,t){r.innerHTML=\"\";var n=c(e);t.forEach(a=>{const e=document.createElement(\"li\");e.style.padding=\"5px 10px\",e.style.cursor=\"pointer\",e.textContent=a[n],e.addEventListener(\"click\",function(){for(var e=i=a,t=0;t<s.length;t++){var n=s[t],o=c(n),o=e[o];o&&d(n,o)}h()}),r.appendChild(e)}),0<t.length?(r.style.display=\"block\",suggestIsShowing=!0):h()}function h(){r&&(r.style.display=\"none\",suggestIsShowing=!1)}document.addEventListener(\"submit\",function(){for(var e=0;e<s.length;e++){var t=s[e],n=c(t);i[n]=t.value}i.update_at=(new Date).valueOf(),i.auto_fill_type&&\"auto_fill_none\"!=i.auto_fill_type&&JSInterface.onKeyValueMsg('onSubmitForm',JSON.stringify(i))}),document.addEventListener(\"click\",e=>{a&&e.target!==a&&r&&(r.remove(),r=null)});var w=document.querySelectorAll(\"input\");console.log(\"======== total input element:total \"+w.length);for(var b=0;b<w.length;b++){var E=w[b],x=c(E);f.includes(x)&&\"hidden\"!=E.type&&s.push(E)}u=o;for(var S=0;S<s.length;S++){var O=c(s[S]);if(\"password\"==O){u=e;break}u=\"card_number\"==O?n:p}if(u!=o){console.log(\">>>>> auto fill type:\"+u);var k=JSON.parse('\(jsonString)');if(u==e)for(var L=[],C=window.location.host,J=0;J<k.length;J++){var N=k[J];N.host==C&&L.push(N)}else L=k;L.sort(function(e,t){return t.update_at-e.update_at}),0<(l=L).length?((i=JSON.parse(JSON.stringify(l[0]))).auto_fill_type=u,i.s_id||(i.s_id=_())):i=u==e?{s_id:_(),auto_fill_type:u,host:window.location.host,login_url:window.location.protocol+window.location.port+\"//\"+window.location.hostname+window.location.pathname}:{s_id:_(),auto_fill_type:u};for(var z=0;z<s.length;z++){var A=s[z];console.log(\">>>>>>>>> target input:\"+c(A)),A.addEventListener(\"input\",function(){var e,t;e=this,console.log(\"update form data:\"+JSON.stringify(i)),i.auto_fill_type=u,t=c(e),i[t]=e.value,g&&clearTimeout(g),g=setTimeout(y,500)}),\"password\"!=A.type&&function(e){for(var o=[],t=0;t<l.length;t++){var n=l[t];o.push(n)}o.sort(function(e,t){return t.update_at-e.update_at}),1<o.length&&(e.addEventListener(\"input\",function(){const t=this.value.toLowerCase(),n=c(this);v(this,o.filter(function(e){return console.log(\">>suggest key:\"+JSON.stringify(e)),r[n]&&r[n].toLowerCase().includes(t)}))}),e.addEventListener(\"click\",function(){var e,t,n;a=this,r||(e=this,t=o,(r=document.createElement(\"ul\")).id=\"suggestions\",r.style.position=\"absolute\",r.style.border=\"1px solid #ccc\",r.style.listStyle=\"none\",r.style.margin=0,r.style.padding=0,r.style.zIndex=2048,r.style.background=\"#fff\",r.style.maxHeight=\"200px\",r.style.maxWidth=\"320px\",r.style.overflowY=\"auto\",n=c(e),t.forEach(e=>{var t=document.createElement(\"li\");t.style.padding=\"5px 10px\",t.style.cursor=\"pointer\",t.textContent=e[n],t.addEventListener(\"click\",function(){d(a,suggestion.login_name),d(document.querySelector('input[type=\"password\"]'),suggestion.password),h()}),r.appendChild(t)}),e.after(r)),v(this,o)}))}(A)}console.log(\">>>>>>>>> fill use form data:\"+JSON.stringify(i));for(var F=0;F<s.length;F++){var D,t=s[F];u==e?(\"password\"==t.type&&i.password&&d(t,i.password),\"login_name\"==(D=c(t))&&i.login_name&&d(t,i.login_name)):u==n||u==p&&(D=c(t),i[D]&&d(t,i[D]))}}else console.log(\"========== no target auto fill form ==========\")}();"

        // 在标签页的WebView中执行安全的JavaScript代码
        // swiftlint:disable:next safe_javascript
        tab?.webView?.evaluateJavaScript(NOTIFYJS)
//        tab?.webView?.evaluateSafeJavaScript(
//            functionName: "window.__firefox__.logins.inject",
//            args: [jsonString],
//            contentWorld: LoginsScriptHandler.scriptSandbox,
//            escapeArgs: false)
//        { _, error in
//            if let error = error {
//                Logger.module.error("\(error.localizedDescription, privacy: .public)")
//            }
//        }
    }
}

extension LoginsScriptHandler {
    /// Helper method for checking if frame security origin elements are same as url from the webview
    /// - Parameters:
    ///   - url: url of the webview / tab
    ///   - frameScheme: Scheme of frameInfo
    ///   - frameHost: Host of frameInfo
    ///   - framePort: Port of frameInfo
    /// - Returns: Boolean indicating url and frameInfo has same elements
    static func checkIsSameFrame(url: URL, frameScheme: String, frameHost: String, framePort: Int) -> Bool {
        // Prevent XSS on non main frame
        // Check the frame origin host belongs to the same security origin host
        guard let currentHost = url.host, !currentHost.isEmpty, currentHost == frameHost else {
            return false
        }

        // Check port for frame origin exists
        // and belongs to the same security origin port
        if let currentPort = url.port, currentPort != framePort {
            return false
        }

        if url.port == nil, framePort != 0 {
            return false
        }

        // Check scheme exists for frame origin
        // and belongs to the same security origin protocol
        if let currentScheme = url.scheme, currentScheme != frameScheme {
            return false
        }

        return true
    }
}
