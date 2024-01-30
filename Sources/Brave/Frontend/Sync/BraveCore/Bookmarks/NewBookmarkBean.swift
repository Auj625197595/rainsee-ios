import Foundation

class NewBookmarkBean: Codable {
    init(_ title: String) {
        self.title = title
    }
    var dateAdded: Int64 = 0
    var url: String = ""
    var dateGroupModified: Int64 = 0
    var id: String = ""
    var index: Int = 0
    var parentId: String = ""
    var title: String?
    var children: [NewBookmarkBean] = []
    var type: String = "bookmark"
    var uuid: String = ""
}

