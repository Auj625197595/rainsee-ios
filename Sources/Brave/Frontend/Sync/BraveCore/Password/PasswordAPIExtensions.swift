// Copyright 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import Data
import BraveCore
import BraveShared
import CoreData
import Shared

typealias Credential = (username: String, password: String)

extension PasswordForm {
  func toDict(formSubmitURL: String, httpRealm: String = "") -> [String: String] {
    return [
      "hostname": signOnRealm,
      "formSubmitURL": formSubmitURL,
      "httpRealm": httpRealm,
      "username": usernameValue ?? "",
      "password": passwordValue ?? "",
      "usernameField": usernameElement ?? "",
      "passwordField": passwordElement ?? "",
    ]
  }
   func toRainseeDict(formSubmitURL: String, httpRealm: String = "") -> [String: String] {

      return [
        "auto_fill_type": "auto_fill_passwd",
        "host": url.host ?? "",
        "login_url": signOnRealm,
        "login_name": usernameValue ?? "",
        "password": passwordValue ?? "",
      ]
  }
    
    func toRainseeNetDict() -> [String: String] {
        var origin = ""
        if let scheme = url.scheme, let host = url.host {
            origin = "\(scheme)://\(host)"
        }
       return [
         "o": origin,
         "u": usernameValue ?? "",
         "p": passwordValue ?? "",
       ]
   }
  var displayURLString: String {
    return signOnRealm
  }

}

extension BravePasswordAPI {
  func fetchFromScript(_ url: URL, script: [String: Any]) -> PasswordForm? {
    let origin = url.origin
    guard !origin.isOpaque,
      let originURL = origin.url,
      let username = script["username"] as? String,
      let usernameElement = script["usernameField"] as? String,
      let password = script["password"] as? String,
      let passwordElement = script["passwordField"] as? String
    else {
      return nil
    }

    let loginForm = PasswordForm(
      url: originURL,
      signOnRealm: originURL.absoluteString,
      dateCreated: Date(),
      dateLastUsed: Date(),
      datePasswordChanged: Date(),
      usernameElement: usernameElement,
      usernameValue: username,
      passwordElement: passwordElement,
      passwordValue: password,
      isBlockedByUser: false,
      scheme: .typeHtml)

    return loginForm
  }
}
