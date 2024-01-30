import Preferences
import SwiftUI

struct ResideSimpleGridView: View {
    let listArray: [Residemenu] = residemenus
    var onTapButton: ((Int) -> Void)?
    var isDesktopSite: Bool = false
    var browserViewController: BrowserViewController

//    init(browserViewController: BrowserViewController, onTapButton: @escaping ((Int) -> Void)) {
//        self.browserViewController = browserViewController
//        self.onTapButton = onTapButton
//    }
    init(onTapButton: @escaping (Int) -> Void, _ browserViewController: BrowserViewController) {
        self.onTapButton = onTapButton
        self.browserViewController = browserViewController

        self.isDesktopSite = browserViewController.tabManager.selectedTab?.isDesktopSite == true
    }

    @Environment(\.colorScheme) var colorScheme
    @State private var currentPage = 0

    let itemsPerRow = 4
    let itemsPerPage = 8 // 两行四列，总共8个图标

    @State private var bookmarkItme: Bookmarkv2? = nil // 两行四列，总共8个图标

    var body: some View {
        VStack(spacing: 0) {
            Text("常用功能").bold()
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 分页内容
            TabView(selection: $currentPage) {
                ForEach(0..<numberOfPages()) { pageIndex in
                    pageView(pageIndex: pageIndex)
                        .tag(pageIndex)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .onChange(of: currentPage, perform: { value in
                // 当页面改变时更新 currentPage
                currentPage = value
            })

            // 分页指示器
            PageControl(numberOfPages: numberOfPages(), currentPage: currentPage)
                .padding()
        }
        .background(Color("reside_bg", bundle: .module))
        .cornerRadius(10)
        .padding(15)
        .frame(height: 251)
        .onAppear {
            // 在后台队列中异步执行任务
            //  DispatchQueue.global(qos: .background).async {
            if let currentUrl = browserViewController.tabManager.selectedTab?.url?.absoluteString {
                browserViewController.bookmarkManager.checkHave(with: currentUrl) { have in
                    print("标签状态\(have)")
                    if have != nil {
                        //    DispatchQueue.main.async {
                        // 在这里写你想要在主线程中执行的代码
                        bookmarkItme = have
                        //  }
                    }
                }
            }

            //   }
        }
    }

    func pageView(pageIndex: Int) -> some View {
        let startIndex = pageIndex * itemsPerPage
        let endIndex = min(startIndex + itemsPerPage, listArray.count)

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: itemsPerRow), spacing: 15, content: {
            ForEach(startIndex..<endIndex, id: \.self) { index in
                let isLight = (listArray[index].id == 5 && (colorScheme == .dark || Preferences.General.nightModeEnabled.value)) ||
                    (listArray[index].id == 11 && self.isDesktopSite) || (listArray[index].id == 0 && $bookmarkItme.wrappedValue != nil)

                VStack(spacing: 0) {
                    if isLight {
                        Image(listArray[index].active!, bundle: .module)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(listArray[index].icon, bundle: .module)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    }
                    Spacer().frame(height: 6)
                    Text(listArray[index].title).font(.caption)
                }.onTapGesture {
                    // 处理点击事件
                    if listArray[index].id == 0 {
                        // 书签
                        if( bookmarkItme != nil){
                            browserViewController.bookmarkManager.delete(bookmarkItme!)
                            bookmarkItme = nil
                        } else {
                            self.onTapButton!(listArray[index].id)
                        }

                    } else {
                        self.onTapButton!(listArray[index].id)
                    }
                }
            }
        })
    }

    func numberOfPages() -> Int {
        return (listArray.count + itemsPerPage - 1) / itemsPerPage
    }
}

struct PageControl: View {
    var numberOfPages: Int
    var currentPage: Int

    var body: some View {
        HStack {
            ForEach(0..<numberOfPages) { page in
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundColor(page == currentPage ? Color("circle_page_switcher", bundle: .module) : .gray)
            }
        }
    }
}
