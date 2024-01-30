//
//  SwiftUIView.swift
//  
//
//  Created by jinjian on 2024/1/15.
//

import SwiftUI
import Preferences
import BraveStrings


struct ResideHeader: View {
    var onTapButton: ((String) -> Void)

    var body: some View {
        HStack {
            // 1. 圆形头像
           
            if Preferences.User.avator.value == "" {
                Image("reside_headimg_new", bundle: .module)
                    .resizable()
                    .frame(width: 45, height: 45)
                    .onTapGesture {
                        onTapButton("user")
                    }
            } else {
                AsyncImageWithCache(url: URL(string: Preferences.User.avator.value)!).onTapGesture {
                    onTapButton("user")
                }
//                AsyncImage(url: URL(string: Preferences.User.avator.value)) { image in
//                    // 成功加载图片后的视图
//                    image
//                        .resizable()
//                        .clipShape(RoundedRectangle(cornerRadius: 23))
//                        .frame(width: 45, height: 45)
//                        .onTapGesture {
//                            onTapButton("user")
//                        }
//                } placeholder: {
//                    // 加载中时的占位图
//                    Image("reside_headimg_new", bundle: .module)
//                        .resizable()
//                        .frame(width: 45, height: 45)
//                        .onTapGesture {
//                            onTapButton("user")
//                        }
//                }
            }
            // 2. 昵称
            Text(Preferences.User.nickName.value == "" ? Strings.Other.nickname : Preferences.User.nickName.value)
                .onTapGesture {
                    onTapButton("user")
                }

            // 3. 向右的箭头icon
            
            Image("reside_right_arr_new", bundle: .module)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
                .onTapGesture {
                    onTapButton("user")
                }

            Spacer()
            // 4. 设置图标，背景色为白色圆角
            Image("reside_settle_new", bundle: .module)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(6)
                .background(Color("reside_bg", bundle: .module))
                .frame(width: 32, height: 32)
                .cornerRadius(6)
                .onTapGesture {
                    onTapButton("settle")
                }

            // 5. 分享图标，背景色为白色圆角
            Image("reside_share_new", bundle: .module)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(6)
                .background(Color("reside_bg", bundle: .module))
                .frame(width: 32, height: 32)
                .cornerRadius(6)
                .onTapGesture {
                    onTapButton("share")
                }
        }
        .padding()
    }
}
class ImageCache {
    static var shared = ImageCache()

    private var cache = NSCache<NSString, UIImage>()

    func loadImage(url: URL, completion: @escaping (UIImage?) -> ()) {
        if let cachedImage = cache.object(forKey: url.absoluteString as NSString) {
            completion(cachedImage)
        } else {
            URLSession.shared.dataTask(with: url) { data, _, error in
                guard let data = data, let newImage = UIImage(data: data) else {
                    completion(nil)
                    return
                }

                self.cache.setObject(newImage, forKey: url.absoluteString as NSString)
                completion(newImage)
            }.resume()
        }
    }
}

struct AsyncImageWithCache: View {
    private var url: URL

    init(url: URL) {
        self.url = url
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                // Display the downloaded image
                image
                    .resizable()
                    .clipShape(RoundedRectangle(cornerRadius: 23))
                    .frame(width: 45, height: 45)
                  
            @unknown default:
                // Handle any future cases
                Image("reside_headimg_new", bundle: .module)
                    .resizable()
                    .frame(width: 45, height: 45)
            }
        }
        .onAppear {
            // Load image and cache it
            ImageCache.shared.loadImage(url: url) { _ in }
        }
    }
}


#Preview {
    ResideHeader() { tappedId in


    }
}
