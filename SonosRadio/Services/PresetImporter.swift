import Foundation
import SwiftData

struct PresetImporter: Sendable {

    struct ImportResult: Sendable {
        var added: Int = 0
        var skipped: Int = 0
        var errors: [String] = []
    }

    @MainActor
    func importPresets(from url: URL, into context: ModelContext) async throws -> ImportResult {
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ImportError.invalidJSON
        }

        let descriptor = FetchDescriptor<StationPreset>()
        let existing = try context.fetch(descriptor)
        let existingURLs = Set(existing.map(\.streamURL))
        let maxOrder = existing.map(\.sortOrder).max() ?? -1

        var result = ImportResult()

        for (index, entry) in entries.enumerated() {
            guard let name = entry["name"] as? String,
                  let streamURL = entry["streamUrl"] as? String ?? entry["streamURL"] as? String else {
                result.errors.append("Entry \(index): missing name or streamUrl")
                continue
            }

            if existingURLs.contains(streamURL) {
                result.skipped += 1
                continue
            }

            let preset = StationPreset(
                name: name,
                streamURL: streamURL,
                source: .directURL,
                artworkURL: (entry["artworkUrl"] as? String ?? entry["artworkURL"] as? String).flatMap { URL(string: $0) },
                sortOrder: maxOrder + 1 + index
            )
            context.insert(preset)
            result.added += 1
        }

        try context.save()
        return result
    }

    enum ImportError: LocalizedError {
        case invalidJSON
        var errorDescription: String? { "Invalid JSON format. Expected an array of station objects." }
    }
}
