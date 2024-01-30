// Copyright 2023 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import BraveCore

class LoginListDataSource {
    
  private let passwordAPI: BravePasswordAPI
  
  private(set) var credentialList = [PasswordForm]()
  private(set) var blockedList = [PasswordForm]()
  private var isCredentialsRefreshing = false
  
  var isCredentialsBeingSearched = false
  
  var isDataSourceEmpty: Bool {
    get {
      return credentialList.isEmpty && blockedList.isEmpty
    }
  }

  // MARK: Internal
  
  init(with passwordAPI: BravePasswordAPI) {
    self.passwordAPI = passwordAPI
 }
  
  func fetchLoginInfo(_ searchQuery: String? = nil, completion: @escaping (Bool) -> Void) {
    if !isCredentialsRefreshing {
      isCredentialsRefreshing = true
      
      passwordAPI.getSavedLogins { credentials in
        self.reloadEntries(with: searchQuery, passwordForms: credentials) { editEnabled in
          completion(editEnabled)
        }
      }
    }
  }
  
  func fetchPasswordFormFor(indexPath: IndexPath) -> PasswordForm? {
    if isCredentialsBeingSearched {
      switch indexPath.section {
      case 0:
        return credentialList.isEmpty ? blockedList[safe: indexPath.item] : credentialList[safe: indexPath.item]
      case 1:
        return blockedList[safe: indexPath.item]
      default:
        return nil
      }
    } else {
      switch indexPath.section {
      case 1:
        return credentialList.isEmpty ? blockedList[safe: indexPath.item] : credentialList[safe: indexPath.item]
      case 2:
        return blockedList[safe: indexPath.item]
      default:
        return nil
      }
    }
  }
  
    // 获取section的数量
    func fetchNumberOfSections() -> Int {
        // 默认情况下有三个section：Option - Saved Logins - Never Saved
        var sectionCount = 3
        
        // 如果封锁列表为空，减少section数量
        if blockedList.isEmpty {
            sectionCount -= 1
        }
        
        // 如果凭证列表为空，减少section数量
        if credentialList.isEmpty {
            sectionCount -= 1
        }
        
        // 如果正在搜索证书，减少一个section数量
        return isCredentialsBeingSearched ? sectionCount - 1 : sectionCount
    }

  
    // 获取指定section的行数
    func fetchNumberOfRowsInSection(section: Int) -> Int {
        switch section {
        case 0:
            if !isCredentialsBeingSearched {
                   return 1
                 }
                 
             return credentialList.isEmpty ? blockedList.count : credentialList.count
        case 1:
            // 如果不是正在搜索证书
            if !isCredentialsBeingSearched {
                // 返回凭证列表为空则返回封锁列表的行数，否则返回凭证列表的行数
                return credentialList.isEmpty ? blockedList.count : credentialList.count
            }
            // 如果正在搜索证书，返回封锁列表的行数
            return blockedList.count
        
        case 2:
            // 如果正在搜索证书，返回0；否则返回封锁列表的行数
            return isCredentialsBeingSearched ? 0 : blockedList.count
        
        default:
            // 默认情况下返回0
            return 0
        }
    }


  // MARK: Private
  
  private func reloadEntries(with query: String? = nil, passwordForms: [PasswordForm], completion: @escaping (Bool) -> Void) {
    // Clear the blocklist before new items append
    blockedList.removeAll()
    
    if let query = query, !query.isEmpty {
      credentialList = passwordForms.filter { form in
        if let origin = form.url.origin.url?.absoluteString.lowercased(), origin.contains(query) {
          if form.isBlockedByUser {
            blockedList.append(form)
          }
          return !form.isBlockedByUser
        }
        
        if let username = form.usernameValue?.lowercased(), username.contains(query) {
          if form.isBlockedByUser {
            blockedList.append(form)
          }
          return !form.isBlockedByUser
        }
        
        return false
      }
    } else {
      credentialList = passwordForms.filter { form in
        // Check If the website is blocked by user with Never Save functionality
        if form.isBlockedByUser {
          blockedList.append(form)
        }
        
        return !form.isBlockedByUser
      }
    }
    
    DispatchQueue.main.async {
      self.isCredentialsRefreshing = false
      completion(!self.credentialList.isEmpty)
    }
  }
}
