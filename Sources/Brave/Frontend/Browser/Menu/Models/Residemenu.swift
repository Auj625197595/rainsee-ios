//
//  File.swift
//  
//
//  Created by jinjian on 2024/1/15.
//

import Foundation
import CoreLocation
import Preferences
import Shared
import BraveCore

struct Residemenu: Identifiable {
    var id: Int
    var title: String
    var icon: String
    var active: String?
}

let residemenus = [

    Residemenu(id: 0, title: Strings.Menu.bookmark, icon: "bar_collect", active: "bar_collect_yellow"),
    Residemenu(id: 1, title: Strings.Menu.aiTxt, icon: "bar_txtai"),
    Residemenu(id: 2, title: Strings.Menu.readMode, icon: "bar_book"),
    Residemenu(id: 3, title: Strings.Menu.translate, icon: "bar_translate"),
    Residemenu(id: 4, title: Strings.Menu.refresh, icon: "bar_fresh"),
    Residemenu(id: 5, title: Strings.Menu.nightMode, icon: "bar_moon", active: "bar_moon_yellow"),
  
    Residemenu(id: 15, title: Strings.Menu.playlist, icon: "bar_playlist"),
    Residemenu(id: 18, title: Strings.Menu.adBlock, icon: "bar_ad"),


    Residemenu(id: 11, title: Strings.Menu.desktop, icon: "bar_pc", active: "bar_pc_yellow"),
    Residemenu(id: 10, title: Strings.Menu.pdf, icon: "bar_pdf"),
    Residemenu(id: 12, title: Strings.Menu.zoom, icon: "bar_large_txt"),
    Residemenu(id: 13, title: Strings.displayCertificate, icon: "bar_websearch"),  //安全认证
//    Residemenu(id: 14, title: Strings.Menu.share, icon: "bar_share"),
    Residemenu(id: 9, title: Strings.Menu.search, icon: "bar_search"),
    Residemenu(id: 16, title: Strings.Menu.devTool, icon: "bar_source"),
   // Residemenu(id: 17, title: "我要捐赠", icon: "bar_donate"),


//    Residemenu(id: 6, title: "历史", icon: "bar_history"),
//    Residemenu(id: 7, title: "下载", icon: "bar_download"),
//    Residemenu(id: 8, title: "书签", icon: "bar_bookmark"),
    
//    Residemenu(id: 0, title: "工具箱", icon: "bar_more"),
//    Residemenu(id: 0, title: "权限管理", icon: "bar_power"),
//    Residemenu(id: 0, title: "关闭", icon: "bar_collect"),
//    Residemenu(id: 0, title: "单手模式", icon: "bar_hand"),
//    Residemenu(id: 0, title: "截长图", icon: "bar_capture"),
//    Residemenu(id: 0, title: "放大文字", icon: "bar_collect"),
//    Residemenu(id: 0, title: "窗口化", icon: "bar_collect"),
//    Residemenu(id: 0, title: "无痕模式", icon: "bar_collect"),
//    Residemenu(id: 0, title: "屏幕常亮", icon: "bar_collect"),
//
//    Residemenu(id: 0, title: "朗读", icon: "bar_collect"),
//    Residemenu(id: 0, title: "自动化", icon: "bar_collect"),
//    Residemenu(id: 0, title: "源代码", icon: "bar_source"),
//    Residemenu(id: 0, title: "检测更新", icon: "bar_collect"),
//    Residemenu(id: 0, title: "互联服务", icon: "bar_collect"),
//    Residemenu(id: 0, title: "语音助手", icon: "bar_collect"),
//    Residemenu(id: 0, title: "扫码", icon: "bar_collect"),
//    Residemenu(id: 0, title: "游戏模式", icon: "bar_full"),
//    Residemenu(id: 0, title: "设置", icon: "bar_settle"),

    
]
