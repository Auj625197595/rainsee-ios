// 版权 2023 The Brave Authors。保留所有权利。
// 此源代码形式受 Mozilla Public License, v. 2.0 的条款约束。
// 如果未与此文件一起分发 MPL 的副本，
// 您可以在 http://mozilla.org/MPL/2.0/ 处获得一份。

import Foundation

/// 生成 Leo 设计系统资源的资源目录
///
/// 目前仅根据目标的资源目录中找到的 `symbolsets` 添加 SF Symbols 到资源目录
@main
struct LeoAssetCatalogGenerator {
  // 参数：./LeoAssetCatalogGenerator asset_catalog1[, asset_catalog2, ...] leo_symbols_directory output_directory
  static func main() throws {
    var arguments = ProcessInfo.processInfo.arguments
    if arguments.count < 4 {
      exit(EXIT_FAILURE)
    }
    let outputDirectory = URL(fileURLWithPath: arguments.popLast()!)
    let leoSymbolsDirectory = URL(fileURLWithPath: arguments.popLast()!)
    let assetCatalogs = arguments.dropFirst().map { URL(fileURLWithPath: $0) }
    
    let generator = LeoAssetCatalogGenerator(
      assetCatalogs: assetCatalogs,
      leoSymbolsDirectory: leoSymbolsDirectory,
      outputDirectory: outputDirectory
    )
    
    try generator.createAssetCatalog()
  }
  
  var assetCatalogs: [URL]
  var leoSymbolsDirectory: URL
  var outputDirectory: URL
  let fileManager = FileManager.default
  
  init(
    assetCatalogs: [URL],
    leoSymbolsDirectory: URL,
    outputDirectory: URL
  ) {
    self.assetCatalogs = assetCatalogs
    self.leoSymbolsDirectory = leoSymbolsDirectory
    self.outputDirectory = outputDirectory
  }
  
  // 创建资源目录
  func createAssetCatalog() throws {
    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try assetCatalogContentsJSON.write(
      to: outputDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8
    )
    try createSymbolSets()
  }
  
  // Asset Catalog 的 Contents.json 内容
  private var assetCatalogContentsJSON: String {
    """
    {
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
  }
  
  // MARK: - SF Symbols
  
  // 创建 SF Symbols 集合
  func createSymbolSets() throws {
    for catalog in assetCatalogs {
      for symbol in symbolSets(in: catalog) {
        let symbolName = symbol.deletingPathExtension().lastPathComponent
        if try fileManager.contentsOfDirectory(atPath: symbol.path).contains(where: { $0.hasSuffix(".svg") }) {
          // 我们已经为某种原因明确覆盖了此图标，因此暂时跳过
          print("Skipped copying Leo SF Symbol \"\(symbolName)\" from leo-sf-symbols. Using local version")
          continue
        }
        let symbolSetOutputDirectory = outputDirectory.appendingPathComponent("\(symbolName).symbolset")
        try fileManager.createDirectory(at: symbolSetOutputDirectory, withIntermediateDirectories: true)
        let leoSymbolSVGPath = leoSymbolsDirectory.appendingPathComponent("symbols/\(symbolName).svg").path
        print("leo symbol svg path: \(leoSymbolSVGPath)")
        if !fileManager.fileExists(atPath: leoSymbolSVGPath) {
          print("Couldn't find a Leo icon named \(symbolName).svg")
          exit(EXIT_FAILURE)
        }
        try symbolSetContentsJSON(filename: symbolName).write(
          to: symbolSetOutputDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8
        )
        let svgOutputDirectory = symbolSetOutputDirectory.appendingPathComponent("\(symbolName).svg")
        if fileManager.fileExists(atPath: svgOutputDirectory.path) {
          try fileManager.removeItem(at: svgOutputDirectory)
        }
        try fileManager.copyItem(at: URL(fileURLWithPath: leoSymbolSVGPath), to: svgOutputDirectory)
      }
    }
  }
  
  // 获取资源目录中的 symbolsets
  private func symbolSets(in catalog: URL) -> [URL] {
    var symbols: [URL] = []
    guard let enumerator = fileManager.enumerator(
      at: catalog,
      includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
      options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
    ) else { return [] }
    while let fileURL = enumerator.nextObject() as? URL {
      guard
        let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .nameKey]),
        let isDirectory = values.isDirectory,
        let name = values.name,
        isDirectory,
        name.hasPrefix("leo"),
        name.hasSuffix(".symbolset") else {
        continue
      }
      symbols.append(fileURL)
    }
    return symbols
  }
  
  // symbolset 的 Contents.json 内容
  private func symbolSetContentsJSON(filename: String) -> String {
    """
    {
      "info" : {
        "author" : "xcode",
        "version" : 1
      },
      "symbols" : [
        {
          "filename" : "\(filename).svg",
          "idiom" : "universal"
        }
      ]
    }
    """
  }
}
