import SwiftUI
import SwiftData

struct StationsView: View {
    @Bindable var viewModel: StationsViewModel
    var nowPlayingViewModel: NowPlayingViewModel
    var speakers: [Speaker]

    @Query(sort: \StationPreset.sortOrder) private var presets: [StationPreset]
    @Environment(\.modelContext) private var modelContext

    @State private var showImportSheet = false
    @State private var importURL = ""

    var body: some View {
        NavigationStack {
            List {
                if !presets.isEmpty {
                    Section("Presets") {
                        ForEach(presets) { preset in
                            Button {
                                playPreset(preset)
                            } label: {
                                HStack {
                                    AsyncImage(url: preset.artworkURL) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Image(systemName: "radio").foregroundStyle(.secondary)
                                    }
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                    VStack(alignment: .leading) {
                                        Text(preset.name).font(.body)
                                        Text(preset.stationSource.rawValue)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    modelContext.delete(preset)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section("Search") {
                    Picker("Source", selection: $viewModel.selectedSource) {
                        ForEach(SearchSource.allCases, id: \.self) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.isSearching {
                        ProgressView("Searching...")
                    }

                    ForEach(viewModel.searchResults) { station in
                        StationRowView(station: station) {
                            playStation(station)
                        } onSave: {
                            viewModel.addToPresets(station, context: modelContext)
                        }
                    }
                }
            }
            .searchable(text: $viewModel.searchQuery, prompt: "Search stations...")
            .onSubmit(of: .search) { Task { await viewModel.search() } }
            .navigationTitle("Stations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImportSheet = true } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $showImportSheet) {
                NavigationStack {
                    Form {
                        TextField("JSON URL", text: $importURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                        Button("Import") {
                            Task {
                                await viewModel.importFromURL(importURL, context: modelContext)
                                showImportSheet = false
                            }
                        }
                    }
                    .navigationTitle("Import Presets")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium])
            }
        }
    }

    private func playPreset(_ preset: StationPreset) {
        guard let speaker = speakers.first else { return }
        let station = Station(
            id: preset.id.uuidString, name: preset.name,
            streamURL: preset.streamURL, artworkURL: preset.artworkURL,
            source: preset.stationSource, sourceId: preset.sourceId
        )
        Task { await nowPlayingViewModel.play(station: station, on: speaker) }
    }

    private func playStation(_ station: Station) {
        guard let speaker = speakers.first else { return }
        Task { await nowPlayingViewModel.play(station: station, on: speaker) }
    }
}
