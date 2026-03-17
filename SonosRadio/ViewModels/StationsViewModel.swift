import Foundation
import SwiftData

enum SearchSource: String, CaseIterable {
    case tuneIn = "TuneIn"
    case iHeart = "iHeart"
    case directURL = "Direct URL"
}

@MainActor
@Observable
final class StationsViewModel {
    var searchResults: [Station] = []
    var searchQuery = ""
    var selectedSource: SearchSource = .tuneIn
    var isSearching = false
    var errorMessage: String?

    private let tuneIn = TuneInService()
    private let iHeart = IHeartService()
    private let streamResolver = StreamResolver()
    private let presetImporter = PresetImporter()

    func search() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            switch selectedSource {
            case .tuneIn:
                searchResults = try await tuneIn.search(query: query)
            case .iHeart:
                searchResults = try await iHeart.search(query: query)
            case .directURL:
                if query.hasPrefix("http://") || query.hasPrefix("https://") {
                    let resolved = try await streamResolver.resolve(url: query)
                    searchResults = [Station(
                        id: UUID().uuidString,
                        name: "Custom Stream",
                        streamURL: resolved,
                        source: .directURL
                    )]
                } else {
                    searchResults = []
                    errorMessage = "Enter a valid HTTP/HTTPS URL"
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            searchResults = []
        }

        isSearching = false
    }

    func resolveStreamURL(for station: Station) async throws -> String {
        if station.source == .iHeart, let sourceId = station.sourceId, let id = Int(sourceId) {
            return try await iHeart.resolveStreamURL(stationId: id)
        }
        return try await streamResolver.resolve(url: station.streamURL)
    }

    func addToPresets(_ station: Station, context: ModelContext) {
        let preset = StationPreset(
            name: station.name,
            streamURL: station.streamURL,
            source: station.source,
            artworkURL: station.artworkURL,
            sourceId: station.sourceId
        )
        context.insert(preset)
        try? context.save()
    }

    func importFromURL(_ urlString: String, context: ModelContext) async {
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL"
            return
        }

        do {
            let result = try await presetImporter.importPresets(from: url, into: context)
            if result.added > 0 {
                errorMessage = nil
            }
            if !result.errors.isEmpty {
                errorMessage = "Imported \(result.added) stations with \(result.errors.count) errors"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
