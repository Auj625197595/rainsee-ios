![Build](https://github.com/brave/brave-ios/workflows/Build/badge.svg?branch=development)

雨见浏览器 for iOS 
===============

从 [App Store]下载([https://apps.apple.com/app/brave-web-browser/id1052879175](https://apps.apple.com/cn/app/%E9%9B%A8%E8%A7%81%E6%B5%8F%E8%A7%88%E5%99%A8/id6476767964)).

前言
-----------
作者是个纯正的安卓开发，正常上班，业余维护雨见浏览器安卓版，由于公司降本增效，逼着我学习ios开发， 于是我也是边学边做搞出了这个版本。很多地方写的不好欢迎指正。目前功能比较单一，就是简单的完成了浏览器的基础功能，跟进安卓版本完成了ai的融合及脚本的应用。我会陆续进行完善。
安卓版本下载地址 https://club.yujianpay.com/index.php/archives/13/

注意
-----------
书签、密码、主页图标等三者的云服务，涉及加密信息，已从源代码中脱敏。如果这个开源可能对用户的数据造成风险，对此带来的不便非常抱歉。

构建代码
-----------------

1. 从Apple安装最新的Xcode开发人员工具（需要Xcode 14.0及以上版本）。
1. 安装Xcode命令行工具
    ```shell
    xcode-select --install
    ```
1. 确保已安装npm，推荐使用node版本16。
1. 安装SwiftLint（版本0.50.0或更高）：
    ```shell
    brew update
    brew install swiftlint
    ```
1. 克隆存储库：
    ```shell
    git clone https://github.com/Auj625197595/rainsee-ios.git
    ```
1. 拉取项目依赖项：
    ```shell
    cd brave-ios
    sh ./bootstrap.sh --ci
    ```
1. 为npm添加符号链接（M1 Macs）
    ```shell
    sudo ln -s $(which npm) /usr/local/bin/npm
    sudo ln -s $(which node) /usr/local/bin/node
    ```
1. 在Xcode中打开App/Client.xcodeproj。
1. 在Xcode中构建Debug方案。

### 贡献
此存储库是[Firebase iOS浏览器] [Firefox iOS Browser](https://github.com/mozilla-mobile/firefox-ios)
此存储库是[Brave iOS浏览器] [Brave iOS Browser](https://github.com/brave/brave-ios)
