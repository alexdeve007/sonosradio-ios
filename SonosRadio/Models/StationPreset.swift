import Foundation
import SwiftData

@Model
final class StationPreset {
    var id: UUID
    var name: String
    var streamURL: String
    var artworkURLString: String?
    var source: String   // StationSource raw value
    var sourceId: String?
    var sortOrder: Int
    var dateAdded: Date

    init(name: String, streamURL: String, source: StationSource, artworkURL: URL? = nil, sourceId: String? = nil, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.streamURL = streamURL
        self.artworkURLString = artworkURL?.absoluteString
        self.source = source.rawValue
        self.sourceId = sourceId
        self.sortOrder = sortOrder
        self.dateAdded = Date()
    }

    var artworkURL: URL? {
        artworkURLString.flatMap { URL(string: $0) }
    }

    var stationSource: StationSource {
        StationSource(rawValue: source) ?? .directURL
    }
}
