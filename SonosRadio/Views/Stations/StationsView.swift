import SwiftUI
import SwiftData

struct StationsView: View {
    @Bindable var viewModel: StationsViewModel
    var nowPlayingViewModel: NowPlayingViewModel
    var speakersVM: SpeakersViewModel

    @Query(sort: \StationPreset.sortOrder) private var presets: [StationPreset]
    @Environment(\.modelContext) private var modelContext

    private var targetSpeaker: Speaker? { speakersVM.selectedSpeaker }

    private var searchPlaceholder: String {
        switch viewModel.selectedSource {
        case .directURL: return "Enter URL"
        case .tuneIn:    return "Search stations..."
        }
    }

    private var selectedSpeakerId: Binding<String> {
        Binding(
            get: { speakersVM.selectedSpeaker?.id ?? "" },
            set: { id in
                if let speaker = speakersVM.groups.first(where: { $0.coordinator.id == id })?.coordinator {
                    speakersVM.selectSpeaker(speaker)
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                // Target speaker/group picker
                Section {
                    Picker(selection: selectedSpeakerId) {
                        ForEach(speakersVM.groups) { group in
                            Text(groupLabel(group)).tag(group.coordinator.id)
                        }
                    } label: {
                        Label("Playing to", systemImage: "hifispeaker.fill")
                    }
                }

                // Search
                Section("Search") {
                    Picker("Source", selection: $viewModel.selectedSource) {
                        ForEach(SearchSource.allCases, id: \.self) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.selectedSource) {
                        viewModel.searchQuery = ""
                        viewModel.searchResults = []
                    }

                    HStack {
                        TextField(searchPlaceholder, text: $viewModel.searchQuery)
                            .textInputAutocapitalization(.never)
                            .keyboardType(viewModel.selectedSource == .directURL ? .URL : .default)
                            .onSubmit { Task { await viewModel.search() } }
                        if !viewModel.searchQuery.isEmpty {
                            Button {
                                viewModel.searchQuery = ""
                                viewModel.searchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        if viewModel.isSearching {
                            ProgressView()
                        } else {
                            Button {
                                Task { await viewModel.search() }
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .disabled(viewModel.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    ForEach(viewModel.searchResults) { station in
                        StationRowView(station: station) {
                            playStation(station)
                        } onSave: {
                            viewModel.addToPresets(station, context: modelContext)
                        }
                        .disabled(targetSpeaker == nil)
                    }
                }

                // Recent
                if !nowPlayingViewModel.recentStations.isEmpty {
                    Section {
                        ForEach(nowPlayingViewModel.recentStations) { station in
                            Button {
                                playStation(station)
                            } label: {
                                HStack {
                                    AsyncImage(url: station.artworkURL) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Image(systemName: "radio").foregroundStyle(.secondary)
                                    }
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(station.name).font(.body)
                                        Text(station.source.rawValue)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(targetSpeaker == nil)
                        }
                    } header: {
                        HStack {
                            Text("Past Played")
                            Spacer()
                            Button {
                                nowPlayingViewModel.clearRecents()
                            } label: {
                                Text("Clear")
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .textCase(nil)
                        }
                    }
                }

                // Presets
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
                            .disabled(targetSpeaker == nil)
                            .contextMenu {
                                Button(role: .destructive) {
                                    modelContext.delete(preset)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if nowPlayingViewModel.isLoading {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Connecting...")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .navigationTitle("Stations")
            .alert("Playback Error", isPresented: .init(
                get: { nowPlayingViewModel.errorMessage != nil },
                set: { if !$0 { nowPlayingViewModel.errorMessage = nil } }
            )) {
                Button("OK") { nowPlayingViewModel.errorMessage = nil }
            } message: {
                Text(nowPlayingViewModel.errorMessage ?? "")
            }
        }
    }

    private func playPreset(_ preset: StationPreset) {
        guard let speaker = targetSpeaker else {
            print("[Stations] No target speaker selected, can't play preset")
            return
        }
        let station = Station(
            id: preset.id.uuidString, name: preset.name,
            streamURL: preset.streamURL, artworkURL: preset.artworkURL,
            source: preset.stationSource, sourceId: preset.sourceId
        )
        print("[Stations] Playing preset '\(preset.name)' on \(speaker.name)")
        Task { await nowPlayingViewModel.play(station: station, on: speaker) }
    }

    private func groupLabel(_ group: SpeakerGroup) -> String {
        if group.members.isEmpty {
            return group.coordinator.name
        }
        return "\(group.coordinator.name) +\(group.members.count)"
    }

    private func playStation(_ station: Station) {
        guard let speaker = targetSpeaker else {
            print("[Stations] No target speaker selected, can't play station")
            return
        }
        print("[Stations] Playing station '\(station.name)' on \(speaker.name)")
        Task { await nowPlayingViewModel.play(station: station, on: speaker) }
    }
}
