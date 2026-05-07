import Foundation
import SwiftData

enum SearchSource: String, CaseIterable {
    case tuneIn = "TuneIn"
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
    private let streamResolver = StreamResolver()

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
}
