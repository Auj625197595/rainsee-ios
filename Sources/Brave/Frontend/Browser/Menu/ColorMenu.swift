//
//  SwiftUIView.swift
//  
//
//  Created by jinjian on 2024/1/15.
//

import SwiftUI
import BraveStrings


struct ColorMenu: View {
    var onTapButton: ((Int) -> Void)
    var body: some View {
        VStack {
            Spacer()
            
            HStack {
                TabButton(id: 0, imageName: "reside_plug", title: Strings.Menu.scriptManagement, action: onTapButton)
                TabButton(id: 1, imageName: "reside_bookmark", title: Strings.Menu.myBookmarks, action: onTapButton)
                TabButton(id: 2, imageName: "reside_download", title: Strings.Menu.myDownloads, action: onTapButton)
                TabButton(id: 3, imageName: "reside_history", title: Strings.historyMenuItem, action: onTapButton)
            }
         }
    }
}


struct TabButton: View {
    var id: Int
    var imageName: String
    var title: String
    var action: (Int) -> Void // Closure for tap action with id parameter
    
    var body: some View {
        VStack {
            Image( imageName, bundle: .module)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
            Spacer().frame(height: 6)
            Text(title)
                .font(.caption)
                .foregroundColor(.primary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .onTapGesture {
            action(id)
        }
       // .background(Color.secondary.opacity(0.1))
       // .cornerRadius(10)
    }
}


#Preview {
    ColorMenu() { tappedId in
               // 处理点击事件
               print("Tab button with id \(tappedId) tapped")
           }
}
