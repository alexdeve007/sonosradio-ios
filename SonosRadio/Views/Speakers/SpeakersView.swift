import SwiftUI
import SwiftData

struct SpeakersView: View {
    @Bindable var viewModel: SpeakersViewModel

    @Query(sort: \GroupPreset.dateCreated) private var groupPresets: [GroupPreset]
    @Environment(\.modelContext) private var modelContext

    @State private var showSaveGroupSheet = false
    @State private var newGroupName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Speakers") {
                    if viewModel.isDiscovering {
                        ProgressView("Discovering speakers...")
                    }

                    ForEach(viewModel.speakers) { speaker in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(speaker.name).font(.headline)
                                HStack(spacing: 4) {
                                    Image(systemName: stateIcon(speaker.transportState))
                                        .font(.caption)
                                    if let track = speaker.currentTrackName {
                                        Text(track).font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text(speaker.transportState.rawValue.capitalized)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            Button {
                                Task { await viewModel.toggleMute(on: speaker) }
                            } label: {
                                Image(systemName: speaker.isMuted ? "speaker.slash" : "speaker.wave.2")
                                    .font(.caption)
                            }

                            Slider(value: Binding(
                                get: { Double(speaker.volume) },
                                set: { val in
                                    Task { await viewModel.setVolume(Int(val), on: speaker) }
                                }
                            ), in: 0...100)
                            .frame(width: 100)

                            Text("\(speaker.volume)")
                                .font(.caption).monospacedDigit()
                                .frame(width: 28)
                        }
                    }
                }

                if !groupPresets.isEmpty {
                    Section("Group Presets") {
                        ForEach(groupPresets) { preset in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(preset.name).font(.body)
                                    Text("\(preset.memberIds.count) speakers")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Activate") {
                                    activateGroupPreset(preset)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets { modelContext.delete(groupPresets[i]) }
                        }
                    }
                }
            }
            .navigationTitle("Speakers")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await viewModel.discover() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSaveGroupSheet = true } label: {
                        Image(systemName: "plus.rectangle.on.rectangle")
                    }
                }
            }
            .alert("Save Group Preset", isPresented: $showSaveGroupSheet) {
                TextField("Group Name", text: $newGroupName)
                Button("Save") { saveCurrentGrouping() }
                Button("Cancel", role: .cancel) { }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private func stateIcon(_ state: TransportState) -> String {
        switch state {
        case .playing: return "play.fill"
        case .paused: return "pause.fill"
        case .stopped: return "stop.fill"
        case .transitioning: return "arrow.triangle.2.circlepath"
        case .noMedia: return "minus.circle"
        }
    }

    private func activateGroupPreset(_ preset: GroupPreset) {
        guard let coordinator = viewModel.speakers.first(where: { $0.id == preset.coordinatorId }) else { return }
        let members = viewModel.speakers.filter { preset.memberIds.contains($0.id) }
        Task { await viewModel.groupSpeakers(members, coordinator: coordinator) }
    }

    private func saveCurrentGrouping() {
        guard !newGroupName.isEmpty, !viewModel.speakers.isEmpty else { return }
        let coordinator = viewModel.speakers.first!
        let preset = GroupPreset(
            name: newGroupName,
            coordinatorId: coordinator.id,
            memberIds: viewModel.speakers.map(\.id)
        )
        modelContext.insert(preset)
        newGroupName = ""
    }
}
