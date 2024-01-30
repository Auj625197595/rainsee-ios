//
//  File.swift
//  
//
//  Created by jinjian on 2024/1/15.
//

import Foundation
import UIKit

enum SettleAdapterType {
    case SELECT
    case SBLIT
}

class SettleActivityBean {
    var pos: Int
    var title: String
    var type: SettleAdapterType
    var icon: String
    var iconNormal: String
    var iconNight: String
    
    init(pos: Int, title: String, type: SettleAdapterType, icon: String, iconNormal: String, iconNight: String) {
        self.pos = pos
        self.title = title
        self.type = type
        self.icon = icon
        self.iconNormal = iconNormal
        self.iconNight = iconNight
    }

}
