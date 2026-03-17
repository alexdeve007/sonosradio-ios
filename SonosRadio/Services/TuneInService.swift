import Foundation

struct TuneInService: Sendable {

    func search(query: String) async throws -> [Station] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://opml.radiotime.com/Search.ashx?query=\(encoded)&render=json") else {
            return []
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        return try parseResponse(data: data)
    }

    func browseCategory(_ categoryId: String? = nil) async throws -> [Station] {
        var urlString = "https://opml.radiotime.com/Browse.ashx?render=json"
        if let categoryId = categoryId {
            urlString += "&c=\(categoryId)"
        }

        guard let url = URL(string: urlString) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try parseResponse(data: data)
    }

    private func parseResponse(data: Data) throws -> [Station] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = json["body"] as? [[String: Any]] else {
            return []
        }

        return body.compactMap { item -> Station? in
            guard let text = item["text"] as? String,
                  let urlString = item["URL"] as? String,
                  item["type"] as? String == "audio" else { return nil }

            let guideId = item["guide_id"] as? String

            return Station(
                id: guideId ?? UUID().uuidString,
                name: text,
                streamURL: urlString,
                artworkURL: (item["image"] as? String).flatMap { URL(string: $0) },
                source: .tuneIn,
                sourceId: guideId,
                bitrate: item["bitrate"] as? Int,
                format: item["formats"] as? String,
                genre: item["subtext"] as? String
            )
        }
    }

    /// Build a Sonos-native TuneIn URI for better metadata display on hardware.
    static func sonosURI(for guideId: String) -> String {
        "x-sonosapi-stream:\(guideId)?sid=254&flags=8224&sn=0"
    }
}
