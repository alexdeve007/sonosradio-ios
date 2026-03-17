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
        guard let url = URL(string: "https://api.iheart.com/api/v2/content/liveStations/\(stationId)") else {
            throw IHeartError.invalidStationId
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let body = String(data: data, encoding: .utf8) ?? ""
        print("[iHeart] API response for station \(stationId): \(body.prefix(500))")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IHeartError.noStreamsFound
        }

        // Try v2 response: hits > 0 > streams
        if let hits = json["hits"] as? [[String: Any]],
           let first = hits.first,
           let streams = first["streams"] as? [String: Any] {
            if let url = findBestStream(in: streams) { return url }
        }

        // Try flat response: streams at top level
        if let streams = json["streams"] as? [String: Any] {
            if let url = findBestStream(in: streams) { return url }
        }

        // Try v3 endpoint as fallback
        if let fallbackURL = try? await resolveViaV3(stationId: stationId) {
            return fallbackURL
        }

        throw IHeartError.noStreamsFound
    }

    private func resolveViaV3(stationId: Int) async throws -> String {
        guard let url = URL(string: "https://api.iheart.com/api/v3/live-meta/stream/\(stationId)/") else {
            throw IHeartError.invalidStationId
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let body = String(data: data, encoding: .utf8) ?? ""
        print("[iHeart] v3 API response for station \(stationId): \(body.prefix(500))")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IHeartError.noStreamsFound
        }

        // Check for streams at any level
        if let streams = json["streams"] as? [String: Any] {
            if let url = findBestStream(in: streams) { return url }
        }

        throw IHeartError.noStreamsFound
    }

    private func findBestStream(in streams: [String: Any]) -> String? {
        // Prefer HTTP shoutcast — Sonos UPnP can't do HTTPS (error 714) or HLS.
        let preferredKeys = [
            "shoutcast_stream",
            "pls_stream",
            "stw_stream",
            "secure_shoutcast_stream",
            "secure_pls_stream",
            "hls_stream",
            "secure_hls_stream"
        ]
        for key in preferredKeys {
            if let streamURL = streams[key] as? String, !streamURL.isEmpty {
                print("[iHeart] Found stream [\(key)]: \(streamURL)")
                return streamURL
            }
        }
        // Fallback: any non-empty string value
        for (key, value) in streams {
            if let streamURL = value as? String, !streamURL.isEmpty {
                print("[iHeart] Found stream [\(key)]: \(streamURL)")
                return streamURL
            }
        }
        print("[iHeart] No streams found in: \(streams.keys.sorted())")
        return nil
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
