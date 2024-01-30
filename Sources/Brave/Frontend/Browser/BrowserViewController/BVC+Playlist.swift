// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import Data
import Shared
import BraveShared
import Preferences
import BraveUI
import UIKit
import Growth
import os.log
import Onboarding
import Playlist

extension BrowserViewController: PlaylistScriptHandlerDelegate, PlaylistFolderSharingScriptHandlerDelegate {
  static var didShowStorageFullWarning = false
    func createPlaylistPopover(item: PlaylistInfo, tab: Tab?) -> PopoverController {
        
        // 获取文件夹名称，如果找不到，则使用默认播放列表标题
        let folderName = PlaylistItem.getItem(uuid: item.tagId)?.playlistFolder?.title ?? Strings.Playlist.defaultPlaylistTitle

        // 创建PopoverController并设置内容为PlaylistPopoverView
        return PopoverController(
          content: PlaylistPopoverView(folderName: folderName) { [weak self] action in
            // 弱引用self以避免循环引用
            guard let self = self,
                  let selectedTab = tab,
                  let item = selectedTab.playlistItem else {
              return
            }
            // 播放触觉反馈
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            
            // 关闭弹出窗口
            self.dismiss(animated: true) {
              // 处理不同的操作
              switch action {
              case .openPlaylist:
                // 打开播放列表，根据情况考虑当前播放时间
                DispatchQueue.main.async {
                  if let webView = tab?.webView {
                    PlaylistScriptHandler.getCurrentTime(webView: webView, nodeTag: item.tagId) { [weak self] currentTime in
                      self?.openPlaylist(tab: tab, item: item, playbackOffset: currentTime)
                    }
                  } else {
                    self.openPlaylist(tab: tab, item: item, playbackOffset: 0.0)
                  }
                }
              case .changeFolders:
                // 打开更改文件夹的视图控制器
                guard let item = PlaylistItem.getItem(uuid: item.tagId) else { return }
                let controller = PlaylistChangeFoldersViewController(item: item)
                self.present(controller, animated: true)
              case .timedOut:
                // 超时情况，仅关闭弹出窗口
                break
              }
            }
          },
          autoLayoutConfiguration: .phoneWidth
        )
    }


    func updatePlaylistURLBar(tab: Tab?, state: PlaylistItemAddedState, item: PlaylistInfo?) {
        // `tab`为空时，表示已关闭，此时状态为`.none`且`item`为nil
        guard let tab = tab else { return }

        // 如果tab是当前选中的tab
        if tab === tabManager.selectedTab {
          // 更新tab的播放列表项状态和内容
          tab.playlistItemState = state
          tab.playlistItem = item

          // 检查是否应该显示播放列表URL按钮
          let shouldShowPlaylistURLBarButton = tab.url?.isPlaylistSupportedSiteURL == true && Preferences.Playlist.enablePlaylistURLBarButton.value

          // 获取所有的浏览器视图控制器
          let browsers = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).compactMap({ $0.browserViewController })
          
          // 遍历每个浏览器
          browsers.forEach { browser in
            // 打开或添加到播放列表活动
            browser.openInPlayListActivity(info: state == .existingItem ? item : nil)
            browser.addToPlayListActivity(info: state == .newItem ? item : nil, itemDetected: state == .newItem)
            
            // 根据状态更新UI
            switch state {
            case .none:
              browser.topToolbar.updatePlaylistButtonState(.none)
              browser.topToolbar.menuButton.removeBadge(.playlist, animated: true)
              browser.toolbar?.menuButton.removeBadge(.playlist, animated: true)
            case .newItem:
              browser.topToolbar.updatePlaylistButtonState(shouldShowPlaylistURLBarButton ? .addToPlaylist : .none)
              if Preferences.Playlist.enablePlaylistMenuBadge.value {
                browser.topToolbar.menuButton.addBadge(.playlist, animated: true)
                browser.toolbar?.menuButton.addBadge(.playlist, animated: true)
              } else {
                browser.topToolbar.menuButton.removeBadge(.playlist, animated: true)
                browser.toolbar?.menuButton.removeBadge(.playlist, animated: true)
              }
            case .existingItem:
              browser.topToolbar.updatePlaylistButtonState(shouldShowPlaylistURLBarButton ? .addedToPlaylist(item) : .none)
              browser.topToolbar.menuButton.removeBadge(.playlist, animated: true)
              browser.toolbar?.menuButton.removeBadge(.playlist, animated: true)
            }
          }
        }
    }


  func showPlaylistPopover(tab: Tab?) {
  }

    // 显示播放列表提示
    func showPlaylistToast(tab: Tab?, state: PlaylistItemAddedState, item: PlaylistInfo?) {
        // 更新播放列表URL栏
        updatePlaylistURLBar(tab: tab, state: state, item: item)

        // 检查当前选中的标签是否支持播放列表，如果不支持则直接返回
        guard let selectedTab = tabManager.selectedTab,
              selectedTab === tab,
              selectedTab.url?.isPlaylistSupportedSiteURL == true
        else {
            return
        }

        // 如果存在待处理的提示且类型是PlaylistToast，则更新其中的项目并返回
        if let toast = pendingToast as? PlaylistToast {
            toast.item = item
            return
        }

        // 创建新的PlaylistToast提示
        pendingToast = PlaylistToast(
            item: item, state: state,
            completion: { [weak self] buttonPressed in
                guard let self = self,
                      let item = (self.pendingToast as? PlaylistToast)?.item
                else { return }

                // 根据不同的状态处理按钮点击事件
                switch state {
                // 需要用户操作才能将项目添加到播放列表
                case .none:
                    if buttonPressed {
                        // 更新播放列表，添加新项目
                        self.addToPlaylist(item: item) { [weak self] didAddItem in
                            guard let self = self else { return }

                            // 记录日志，提示项目已添加到播放列表
                            Logger.module.debug("Playlist Item Added")
                            self.pendingToast = nil

                            // 如果成功添加项目，显示播放列表提示并进行触感反馈
                            if didAddItem {
                                self.showPlaylistToast(tab: tab, state: .existingItem, item: item)
                                UIImpactFeedbackGenerator(style: .medium).bzzt()
                            }
                        }
                    } else {
                        // 用户取消操作，清空待处理的提示
                        self.pendingToast = nil
                    }

                // 项目已经存在于播放列表中，询问用户是否想在播放列表中查看
                // 项目已由用户添加到播放列表，询问用户是否想在播放列表中查看
                case .newItem, .existingItem:
                    if buttonPressed {
                        // 触感反馈
                        UIImpactFeedbackGenerator(style: .medium).bzzt()

                        // 异步操作，根据项目的tagId获取当前时间
                        DispatchQueue.main.async {
                            if let webView = tab?.webView {
                                PlaylistScriptHandler.getCurrentTime(webView: webView, nodeTag: item.tagId) { [weak self] currentTime in
                                    // 打开播放列表，传递项目信息和播放偏移
                                    self?.openPlaylist(tab: tab, item: item, playbackOffset: currentTime)
                                }
                            } else {
                                // 没有webView时，直接打开播放列表
                                self.openPlaylist(tab: tab, item: item, playbackOffset: 0.0)
                            }
                        }
                    }

                    // 清空待处理的提示
                    self.pendingToast = nil
                }
            })

        // 如果存在待处理的提示，则设置显示时间
        if let pendingToast = pendingToast {
            let duration = state == .none ? 10 : 5
            show(toast: pendingToast, afterWaiting: .milliseconds(250), duration: .seconds(duration))
        }
    }


    func showPlaylistAlert(tab: Tab?, state: PlaylistItemAddedState, item: PlaylistInfo?) {
        // 必须执行此操作，否则在选择视频元素后无法播放视频
        UIMenuController.shared.hideMenu()

        // 根据设备类型选择合适的 UIAlertController 样式
        let style: UIAlertController.Style = UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet
        
        // 创建 UIAlertController 对象
        let alert = UIAlertController(
            title: Strings.PlayList.addToPlayListAlertTitle,  // 弹窗标题
            message: Strings.PlayList.addToPlayListAlertDescription,  // 弹窗描述信息
            preferredStyle: style  // 弹窗样式
        )

        // 添加 "添加到播放列表" 的操作
        alert.addAction(
            UIAlertAction(
                title: Strings.PlayList.addToPlayListAlertTitle,  // 操作标题
                style: .default,
                handler: { _ in
                    // 更新播放列表，添加新的项目..

                    guard let item = item else { return }
                    self.addToPlaylist(item: item) { [weak self] addedToPlaylist in
                        guard let self = self else { return }

                        // 触发触觉反馈
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

                        if addedToPlaylist {
                            // 如果成功添加到播放列表，则显示相关提示
                            self.showPlaylistToast(tab: tab, state: .existingItem, item: item)
                        }
                    }
                }
            )
        )
        
        // 添加 "取消" 操作
        alert.addAction(UIAlertAction(title: Strings.cancelButtonTitle, style: .cancel, handler: nil))
        
        // 弹出 UIAlertController
        present(alert, animated: true, completion: nil)
    }


    func showPlaylistOnboarding(tab: Tab?) {
        // 如果当前选项卡不可见，则不显示播放列表引导弹窗
        guard Preferences.Playlist.enablePlaylistURLBarButton.value,
              let selectedTab = tabManager.selectedTab,
              selectedTab === tab,
              selectedTab.playlistItemState != .none
        else {
            return
        }

        // 判断是否应该显示播放列表引导
        let shouldShowOnboarding = tab?.url?.isPlaylistSupportedSiteURL == true

        if shouldShowOnboarding {
            // 检查引导弹窗显示的条件：在本会话中、弹窗未被显示、url栏引导次数小于2次
            if Preferences.Playlist.addToPlaylistURLBarOnboardingCount.value < 2,
                shouldShowPlaylistOnboardingThisSession,
                presentedViewController == nil {
                
                // 增加url栏引导次数
                Preferences.Playlist.addToPlaylistURLBarOnboardingCount.value += 1

                // 立即布局以确保视图准备好显示弹窗
                topToolbar.layoutIfNeeded()
                view.layoutIfNeeded()

                // 弹窗前确保url栏已展开
                toolbarVisibilityViewModel.toolbarState = .expanded

                // 在主队列中异步执行，以确保在界面更新完成后再显示弹窗
                DispatchQueue.main.async {
                    // 创建播放列表引导模型
                    let model = OnboardingPlaylistModel()

                    // 创建弹窗控制器并初始化弹窗内容视图
                    let popover = PopoverController(content: OnboardingPlaylistView(model: model))

                    // 设置弹窗相对于的预览位置
                    popover.previewForOrigin = .init(view: self.topToolbar.locationView.playlistButton, action: { [weak tab] popover in
                        guard let item = tab?.playlistItem else {
                            popover.dismissPopover()
                            return
                        }
                        
                        // 设置弹窗预览位置之后，执行该闭包，用于在预览中添加到播放列表
                        popover.previewForOrigin = nil
                        self.addToPlaylist(item: item) { didAddItem in
                            let folderName = PlaylistItem.getItem(uuid: item.tagId)?.playlistFolder?.title ?? ""
                            model.step = .completed(folderName: folderName)
                        }
                    })

                    // 弹窗显示
                    popover.present(from: self.topToolbar.locationView.playlistButton, on: self)

                    // 设置播放列表引导模型的完成闭包
                    model.onboardingCompleted = { [weak tab, weak popover] in
                        popover?.dismissPopover()
                        self.openPlaylist(tab: tab, item: tab?.playlistItem)
                    }
                }

                // 防止在同一会话中多次显示引导
                shouldShowPlaylistOnboardingThisSession = false
            }
        }
    }


  func openPlaylist(tab: Tab?, item: PlaylistInfo?, folderSharingPageUrl: String? = nil) {
    if let item, let webView = tab?.webView {
      PlaylistScriptHandler.getCurrentTime(webView: webView, nodeTag: item.tagId) { [weak self] currentTime in
        self?.openPlaylist(tab: tab, item: item, playbackOffset: currentTime, folderSharingPageUrl: folderSharingPageUrl)
      }
    } else {
      openPlaylist(tab: tab, item: item, playbackOffset: 0.0, folderSharingPageUrl: folderSharingPageUrl)
    }
  }
  
  private func openPlaylist(tab: Tab?, item: PlaylistInfo?, playbackOffset: Double, folderSharingPageUrl: String? = nil) {
    let playlistController = PlaylistCarplayManager.shared.getPlaylistController(tab: tab,
                                                                                 initialItem: item,
                                                                                 initialItemPlaybackOffset: playbackOffset)
    playlistController.modalPresentationStyle = .fullScreen
    if let folderSharingPageUrl = folderSharingPageUrl {
      playlistController.setFolderSharingUrl(folderSharingPageUrl)
    }

    // Donate Open Playlist Activity for suggestions
    let openPlaylist = ActivityShortcutManager.shared.createShortcutActivity(type: .openPlayList)
    self.userActivity = openPlaylist
    openPlaylist.becomeCurrent()
    PlaylistP3A.recordUsage()
    
    present(playlistController, animated: true) {
      if let folderSharingPageUrl = folderSharingPageUrl {
        playlistController.setFolderSharingUrl(folderSharingPageUrl)
      }
    }
  }

  func addToPlayListActivity(info: PlaylistInfo?, itemDetected: Bool) {
    if info == nil {
      addToPlayListActivityItem = nil
    } else {
      addToPlayListActivityItem = (enabled: itemDetected, item: info)
    }
  }

  func openInPlayListActivity(info: PlaylistInfo?) {
    if info == nil {
      openInPlaylistActivityItem = nil
    } else {
      openInPlaylistActivityItem = (enabled: true, item: info)
    }
  }

    func addToPlaylist(item: PlaylistInfo, folderUUID: String? = nil, completion: ((_ didAddItem: Bool) -> Void)? = nil) {
        // 记录播放列表操作的使用情况
        PlaylistP3A.recordUsage()

        // 检查磁盘空间是否受限，并且还未显示过存储空间警告
        if PlaylistManager.shared.isDiskSpaceEncumbered() && !BrowserViewController.didShowStorageFullWarning {
            BrowserViewController.didShowStorageFullWarning = true

            // 根据设备类型选择警告框或操作表样式
            let style: UIAlertController.Style = UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet

            // 创建警告框
            let alert = UIAlertController(
                title: Strings.PlayList.playlistDiskSpaceWarningTitle, // 警告标题
                message: Strings.PlayList.playlistDiskSpaceWarningMessage, // 警告消息
                preferredStyle: style)

            // 添加“确定”按钮，处理添加到播放列表的操作
            alert.addAction(
                UIAlertAction(
                    title: Strings.OKString, style: .default,
                    handler: { [weak self] _ in
                        guard let self = self else { return }

                        // 设置打开播放列表活动项，将待添加项设为 nil
                        self.openInPlaylistActivityItem = (enabled: true, item: item)
                        self.addToPlayListActivityItem = nil

                        // 处理 App 评价管理的子标准，检查播放列表项数量
                        AppReviewManager.shared.processSubCriteria(for: .numberOfPlaylistItems)

                        // 添加播放列表项
                        PlaylistItem.addItem(item, folderUUID: folderUUID, cachedData: nil) { [weak self] in
                            guard let self = self else { return }

                            // 自动下载播放列表项
                            PlaylistManager.shared.autoDownload(item: item)

                            // 更新播放列表 URL 栏
                            self.updatePlaylistURLBar(
                                tab: self.tabManager.selectedTab,
                                state: .existingItem,
                                item: item)

                            // 执行完成闭包
                            completion?(true)
                        }
                    }))

            // 添加“取消”按钮，处理用户取消添加操作
            alert.addAction(
                UIAlertAction(
                    title: Strings.cancelButtonTitle, style: .cancel,
                    handler: { _ in
                        completion?(false)
                    }))

            // 有时 MENU 控制器正在显示，无法呈现警告框
            // 因此需要要求它来呈现警告
            (presentedViewController ?? self).present(alert, animated: true, completion: nil)
        } else {
            // 如果磁盘空间未受限，或者已经显示了存储空间警告，直接执行添加到播放列表的操作

            // 设置打开播放列表活动项，将待添加项设为 nil
            openInPlaylistActivityItem = (enabled: true, item: item)
            addToPlayListActivityItem = nil

            // 处理 App 评价管理的子标准，检查播放列表项数量
            AppReviewManager.shared.processSubCriteria(for: .numberOfPlaylistItems)

            // 添加播放列表项
            PlaylistItem.addItem(item, folderUUID: folderUUID, cachedData: nil) { [weak self] in
                guard let self = self else { return }

                // 自动下载播放列表项
                PlaylistManager.shared.autoDownload(item: item)

                // 更新播放列表 URL 栏
                self.updatePlaylistURLBar(
                    tab: self.tabManager.selectedTab,
                    state: .existingItem,
                    item: item)

                // 执行完成闭包
                completion?(true)
            }
        }
    }

  
  // MARK: - PlaylistFolderSharingHelperDelegate
  func openPlaylistSharingFolder(with pageUrl: String) {
    openPlaylist(tab: nil, item: nil, playbackOffset: 0.0, folderSharingPageUrl: pageUrl)
  }
}

extension BrowserViewController {
  private static var playlistSyncFoldersTimer: Timer?
  
  func openPlaylistSettingsMenu() {
    let playlistSettings = PlaylistSettingsViewController()
    let navigationController = UINavigationController(rootViewController: playlistSettings)
    self.present(navigationController, animated: true)
  }
  
  func syncPlaylistFolders() {
    if Preferences.Playlist.syncSharedFoldersAutomatically.value {
      BrowserViewController.playlistSyncFoldersTimer?.invalidate()
      
      let lastSyncDate = Preferences.Playlist.lastPlaylistFoldersSyncTime.value ?? Date()
      
      BrowserViewController.playlistSyncFoldersTimer = Timer(fire: lastSyncDate, interval: 4.hours, repeats: true, block: { _ in
        Preferences.Playlist.lastPlaylistFoldersSyncTime.value = Date()
        
        Task {
          try await PlaylistManager.syncSharedFolders()
        }
      })
    }
  }
}
