import Foundation

enum StationSource: String, Codable, Sendable {
    case tuneIn
    case iHeart
    case directURL
}

struct Station: Identifiable, Sendable {
    let id: String
    var name: String
    var streamURL: String
    var artworkURL: URL?
    var source: StationSource
    var sourceId: String?
    var bitrate: Int?
    var format: String?
    var genre: String?
    var description: String?
}
