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

    /// Resolve a TuneIn station ID to an actual stream URL via the Tune.ashx API.
    func resolveStreamURL(stationId: String) async throws -> String {
        guard let url = URL(string: "https://opml.radiotime.com/Tune.ashx?id=\(stationId)&render=json") else {
            throw TuneInError.invalidStationId
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let body = String(data: data, encoding: .utf8) ?? ""
        print("[TuneIn] Tune.ashx response for \(stationId): \(body.prefix(500))")

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let bodyArray = json["body"] as? [[String: Any]],
           let first = bodyArray.first,
           let streamURL = first["url"] as? String, !streamURL.isEmpty {
            return streamURL
        }

        // Fallback: fetch non-JSON to get direct URL (PLS/M3U format)
        guard let plainURL = URL(string: "https://opml.radiotime.com/Tune.ashx?id=\(stationId)") else {
            throw TuneInError.noStreamFound
        }
        let (plainData, _) = try await URLSession.shared.data(from: plainURL)
        let text = String(data: plainData, encoding: .utf8) ?? ""
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                return trimmed
            }
        }

        throw TuneInError.noStreamFound
    }

    enum TuneInError: LocalizedError {
        case invalidStationId
        case noStreamFound

        var errorDescription: String? {
            switch self {
            case .invalidStationId: return "Invalid TuneIn station ID"
            case .noStreamFound: return "Could not resolve TuneIn stream URL"
            }
        }
    }
}
