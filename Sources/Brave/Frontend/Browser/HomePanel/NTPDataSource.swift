// 版权 © 2023 Brave 作者。保留所有权利。
// 本源代码表单受 Mozilla 公共许可证 2.0 版的条款约束。
// 如果未随此文件分发 MPL 的副本，则可以在 http://mozilla.org/MPL/2.0/ 获取一份。

import UIKit
import Shared
import Preferences
import BraveCore
import os.log

// New Tab 页面壁纸类型
enum NTPWallpaper {
  case image(NTPBackgroundImage)
  case sponsoredImage(NTPSponsoredImageBackground)
  case superReferral(NTPSponsoredImageBackground, code: String)
  
  var backgroundImage: UIImage? {
    let imagePath: URL
    switch self {
    case .image(let background):
      imagePath = background.imagePath
    case .sponsoredImage(let background):
      imagePath = background.imagePath
    case .superReferral(let background, _):
      imagePath = background.imagePath
    }
    return UIImage(contentsOfFile: imagePath.path)
  }
  
  var logoImage: UIImage? {
    let imagePath: URL?
    switch self {
    case .image:
      imagePath = nil
    case .sponsoredImage(let background):
      imagePath = background.logo.imagePath
    case .superReferral(let background, _):
      imagePath = background.logo.imagePath
    }
    return imagePath.flatMap { UIImage(contentsOfFile: $0.path) }
  }
  
  var focalPoint: CGPoint? {
    switch self {
    case .image:
      return nil // 将来会返回一个真实的值
    case .sponsoredImage(let background):
      return background.focalPoint
    case .superReferral(let background, _):
      return background.focalPoint
    }
  }
}

// New Tab 数据源类
public class NTPDataSource {
  
  private(set) var privateBrowsingManager: PrivateBrowsingManager

  // 初始化喜欢的站点回调
  var initializeFavorites: ((_ sites: [NTPSponsoredImageTopSite]?) -> Void)?

  /// 自定义主页规范要求:
  /// 如果我们无法获取超级引荐的信息，并且稍后成功获取，将使用超级引荐的默认喜爱站点替换默认的喜爱站点。
  /// 这仅在用户未更改默认喜爱站点的情况下发生。
  var replaceFavoritesIfNeeded: ((_ sites: [NTPSponsoredImageTopSite]?) -> Void)?

  // 数据是静态的，以避免重复加载

  /// 出现背景重复之前必须显示的背景数量。
  /// 因此，如果显示背景 `3`，则在显示此多个背景之前不能再显示 `3`。
  /// 这不适用于赞助的图像。
  /// 这在每次启动时重置，因此如果将应用程序从内存中删除，则可以再次显示 `3`。
  /// 此数字 _必须_ 小于背景图的数量！
  private static let numberOfDuplicateAvoidance = 6
  /// 赞助轮换中图像的数量。
  ///     例如，在显示第 N 张图像之前，将重复此数量的图像。
  ///          如果赞助的图像显示为第 N 张图像，则在到达第 N 张图像之前将显示此数量的常规图像。
  private static let sponsorshipShowRate = 4
  /// 在此值上，将显示赞助的图像。
  private static let sponsorshipShowValue = 2

  /// 表示应该显示哪个背景的计数器，用于确定何时显示新的赞助图像。 (`1` 表示，应该显示循环 N 中的第一个图像)。
  /// 例如，如果轮换是每 4 张图像一次，但赞助的图像应该显示为第 2 张图像，则在达到 4 之后，此计数器将被重置为 `1`，并且在值为 `2` 时将显示赞助的图像。
  /// 这可以轻松转换为偏好设置以进行持久化
  private var backgroundRotationCounter = 1

  let service: NTPBackgroundImagesService

  public init(service: NTPBackgroundImagesService, privateBrowsingManager: PrivateBrowsingManager) {
    self.service = service
    self.privateBrowsingManager = privateBrowsingManager
    
    // 观察主题的更改
    Preferences.NewTabPage.selectedCustomTheme.observe(from: self)
      // 延迟 3 秒后执行
      DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
          self.sponsorComponentUpdated()
      }

     
  }
  
  deinit {
    self.service.sponsoredImageDataUpdated = nil
  }

  // 用于防止显示相同少数背景的功能。
  // 它将跟踪最后 N 张已显示的图片，并在它们变得“旧”并从此数组中删除之前，防止它们显示。
  // 目前仅支持普通背景，因为赞助的图像不应重复。
  // 这可以通过切换到 String 并使用 filePath 来标识唯一性，“容易地”调整以支持两组。
  private var lastBackgroundChoices = [Int]()

  // 图像轮换策略
  private enum ImageRotationStrategy {
    /// 赞助图像的特殊策略，使用内存中的属性跟踪要显示的图像。
    case sponsoredRotation
    /// 使用随机图像，保留最近查看的图像的内存列表，以避免显示它太频繁。
    case randomOrderAvoidDuplicates
  }

  // 获取新的背景
  func newBackground() -> NTPWallpaper? {
    if !Preferences.NewTabPage.backgroundImages.value { return nil }

    // 识别要使用的背景数组
    let (backgroundSet, strategy) = {
      () -> ([NTPWallpaper], ImageRotationStrategy) in

      if let theme = service.superReferralImageData,
         case let refCode = service.superReferralCode,
         !refCode.isEmpty,
        Preferences.NewTabPage.selectedCustomTheme.value != nil {
        return (theme.campaigns.flatMap(\.backgrounds).map { NTPWallpaper.superReferral($0, code: refCode) }, .randomOrderAvoidDuplicates)
      }

      if let sponsor = service.sponsoredImageData {
        let attemptSponsored =
          Preferences.NewTabPage.backgroundSponsoredImages.value
          && backgroundRotationCounter == NTPDataSource.sponsorshipShowValue
          && !privateBrowsingManager.isPrivateBrowsing

        if attemptSponsored {
          // 随机选择活动
          let campaignIndex: Int = Int.random(in: 0..<sponsor.campaigns.count)

          if let campaign = sponsor.campaigns[safe: campaignIndex] {
            return (campaign.backgrounds.map(NTPWallpaper.sponsoredImage), .sponsoredRotation)
          }
        }
      }

      if service.backgroundImages.isEmpty {
        return ([NTPWallpaper.image(.fallback)], .randomOrderAvoidDuplicates)
      }
      return (service.backgroundImages.map(NTPWallpaper.image), .randomOrderAvoidDuplicates)
    }()

    if backgroundSet.isEmpty { return nil }

    // 选择要使用的实际索引 / 项目
    let backgroundIndex = { () -> Int in
      switch strategy {
      case .sponsoredRotation:
        return Int.random(in: 0..<backgroundSet.count)

      case .randomOrderAvoidDuplicates:
        let availableRange = 0..<backgroundSet.count
        // 这将获取所有索引并过滤掉最近显示的索引
        let availableBackgroundIndeces = availableRange.filter {
          !self.lastBackgroundChoices.contains($0)
        }
        // 由于当前存在许多显示模式，因此可能在较小的子集上使用背景避免计数。
        // 这可以通过在普通背景和超级引荐之间切换来复制，其中所有可用的索引都被挤压出去，导致一个空集。
        // 为了避免问题，第一个回退结果在完整集合中。
        
        // 选择要使用的新随机索引
        let chosenIndex = availableBackgroundIndeces.randomElement() ?? availableRange.randomElement() ?? -1
        assert(chosenIndex >= 0, "NTP 索引为 nil，这是糟糕的。")
        assert(chosenIndex < backgroundSet.count, "NTP 索引过大，不好！")

        // 此索引现在添加到 'past' 跟踪列表以防止重复
        self.lastBackgroundChoices.append(chosenIndex)
        // 裁剪到固定长度以释放较旧的背景

        self.lastBackgroundChoices = self.lastBackgroundChoices
          .suffix(min(backgroundSet.count - 1, NTPDataSource.numberOfDuplicateAvoidance))
        return chosenIndex
      }
    }()

    // 如果在末尾，则强制返回 `0`
    backgroundRotationCounter %= NTPDataSource.sponsorshipShowRate
    // 无论如何递增，这是一个计数器，而不是一个索引，因此最小应为 `1`
    backgroundRotationCounter += 1

    guard let bgWithIndex = backgroundSet[safe: backgroundIndex] else { return nil }
    return bgWithIndex
  }
  
  // 赞助组件更新回调
  func sponsorComponentUpdated() {
    if let superReferralImageData = service.superReferralImageData, superReferralImageData.isSuperReferral {
      if Preferences.NewTabPage.preloadedFavoritiesInitialized.value {
        replaceFavoritesIfNeeded?(superReferralImageData.topSites)
      } else {
        initializeFavorites?(superReferralImageData.topSites)
      }
    } else {
      // 强制设置基本喜爱站点，如果尚未完成。
      initializeFavorites?(nil)
    }
  }
}

// 实现 PreferencesObserver 协议
extension NTPDataSource: PreferencesObserver {
  public func preferencesDidChange(for key: String) {
    let customThemePref = Preferences.NewTabPage.selectedCustomTheme
    let installedThemesPref = Preferences.NewTabPage.installedCustomThemes

    switch key {
    case customThemePref.key:
      let installedThemes = installedThemesPref.value
      if let theme = customThemePref.value, !installedThemes.contains(theme) {
        installedThemesPref.value = installedThemesPref.value + [theme]
      }
    default:
      break
    }
  }
}

// 扩展 NTPSponsoredImageTopSite，将其转换为 FavoriteSite
extension NTPSponsoredImageTopSite {
  var asFavoriteSite: FavoriteSite? {
    guard let url = destinationURL else {
      return nil
    }
    return FavoriteSite(url, name)
  }
}

// 扩展 NTPBackgroundImage，提供一个备用的 NTPBackgroundImage 实例
extension NTPBackgroundImage {
  static let fallback: NTPBackgroundImage = .init(
    imagePath: Bundle.module.url(forResource: "corwin-prescott-3", withExtension: "jpg")!,
    author: "Corwin Prescott",
    link: URL(string: "https://www.brave.com")!
  )
}
