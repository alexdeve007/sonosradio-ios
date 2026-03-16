import Foundation
import SwiftData

@Model
final class ImportSource {
    var id: UUID
    var name: String
    var urlString: String
    var lastImported: Date?

    init(name: String, urlString: String) {
        self.id = UUID()
        self.name = name
        self.urlString = urlString
    }

    var url: URL? {
        URL(string: urlString)
    }
}
