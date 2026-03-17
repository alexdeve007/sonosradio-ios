import Foundation

struct IHeartService: Sendable {

    func search(query: String) async throws -> [Station] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.iheart.com/api/v3/search/all?keywords=\(encoded)&maxRows=20&bundle=false&station=true") else {
            return []
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        return try parseSearchResponse(data: data)
    }

    func resolveStreamURL(stationId: Int) async throws -> String {
        guard let url = URL(string: "https://api.iheart.com/api/v3/live-meta/stream/\(stationId)/") else {
            throw IHeartError.invalidStationId
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = json["streams"] as? [String: Any] else {
            throw IHeartError.noStreamsFound
        }

        let preferredKeys = ["secure_hls_stream", "hls_stream", "secure_shoutcast_stream", "shoutcast_stream"]
        for key in preferredKeys {
            if let streamURL = streams[key] as? String, !streamURL.isEmpty {
                return streamURL
            }
        }

        for (_, value) in streams {
            if let streamURL = value as? String, !streamURL.isEmpty {
                return streamURL
            }
        }

        throw IHeartError.noStreamsFound
    }

    private func parseSearchResponse(data: Data) throws -> [Station] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let stations = results["stations"] as? [[String: Any]] else {
            return []
        }

        return stations.compactMap { item -> Station? in
            guard let id = item["id"] as? Int,
                  let name = item["name"] as? String else { return nil }

            let callSign = item["callLetters"] as? String
            let displayName = callSign.map { "\($0) - \(name)" } ?? name

            return Station(
                id: "\(id)",
                name: displayName,
                streamURL: "",
                artworkURL: (item["logo"] as? String).flatMap { URL(string: $0) },
                source: .iHeart,
                sourceId: "\(id)",
                genre: item["genres"] as? String,
                description: item["description"] as? String
            )
        }
    }

    enum IHeartError: LocalizedError {
        case invalidStationId
        case noStreamsFound

        var errorDescription: String? {
            switch self {
            case .invalidStationId: return "Invalid iHeart station ID"
            case .noStreamsFound: return "No streams found for this station"
            }
        }
    }
}
