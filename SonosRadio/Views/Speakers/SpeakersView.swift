import SwiftUI

struct SpeakersView: View {
    @Bindable var viewModel: SpeakersViewModel

    @State private var isGrouping = false
    @State private var groupSelection: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isDiscovering && viewModel.groups.isEmpty {
                    ProgressView("Discovering speakers...")
                }

                if isGrouping {
                    Section("Select speakers to group") {
                        ForEach(viewModel.speakers) { speaker in
                            groupingRow(speaker)
                        }
                    }
                    Section {
                        Button {
                            createGroup()
                        } label: {
                            Label("Group Selected (\(groupSelection.count))", systemImage: "link")
                        }
                        .disabled(groupSelection.count < 2)

                        Button("Cancel", role: .cancel) {
                            isGrouping = false
                            groupSelection.removeAll()
                        }
                    }
                } else {
                    ForEach(viewModel.groups) { group in
                        Section {
                            // Coordinator row with transport controls
                            speakerRow(group.coordinator, isGroupCoordinator: group.members.count > 0)

                            // Member rows (just volume, no transport)
                            ForEach(group.members) { member in
                                memberRow(member)
                            }
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
                    if !isGrouping {
                        Button {
                            isGrouping = true
                            if let id = viewModel.selectedSpeaker?.id {
                                groupSelection = [id]
                            }
                        } label: {
                            Image(systemName: "link")
                        }
                        .disabled(viewModel.speakers.count < 2)
                    }
                }
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

    // MARK: - Coordinator Row (has transport controls)

    @ViewBuilder
    private func speakerRow(_ speaker: Speaker, isGroupCoordinator: Bool) -> some View {
        let isSelected = viewModel.selectedSpeaker?.id == speaker.id

        VStack(spacing: 8) {
            HStack {
                // Play/pause for active speakers
                if speaker.transportState == .playing || speaker.transportState == .paused {
                    Button {
                        Task { await viewModel.togglePlayPause(on: speaker) }
                    } label: {
                        Image(systemName: speaker.transportState == .playing ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .frame(width: 28)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(speaker.name)
                            .font(.headline)
                        if isGroupCoordinator {
                            Image(systemName: "link")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(statusText(for: speaker))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                }
            }

            volumeRow(speaker)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectSpeaker(speaker)
        }
        .listRowBackground(isSelected ? Color.blue.opacity(0.08) : nil)
    }

    // MARK: - Member Row (volume only, no transport)

    @ViewBuilder
    private func memberRow(_ speaker: Speaker) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(speaker.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            volumeRow(speaker)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Volume Row (shared)

    @ViewBuilder
    private func volumeRow(_ speaker: Speaker) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await viewModel.toggleMute(on: speaker) }
            } label: {
                Image(systemName: speaker.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.caption)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)

            Slider(value: Binding(
                get: { Double(speaker.volume) },
                set: { viewModel.setVolume(Int($0), on: speaker) }
            ), in: 0...100)

            Text("\(speaker.volume)")
                .font(.caption).monospacedDigit()
                .frame(width: 28)
        }
    }

    // MARK: - Grouping Row

    @ViewBuilder
    private func groupingRow(_ speaker: Speaker) -> some View {
        let isInGroup = groupSelection.contains(speaker.id)

        Button {
            if groupSelection.contains(speaker.id) {
                groupSelection.remove(speaker.id)
            } else {
                groupSelection.insert(speaker.id)
            }
        } label: {
            HStack {
                Image(systemName: isInGroup ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isInGroup ? .green : .secondary)
                    .font(.title3)
                Text(speaker.name).font(.headline)
                Spacer()
            }
        }
        .listRowBackground(isInGroup ? Color.green.opacity(0.08) : nil)
    }

    // MARK: - Helpers

    private func statusText(for speaker: Speaker) -> String {
        let track = speaker.currentTrackName
        switch speaker.transportState {
        case .playing:
            return track ?? "Playing"
        case .paused:
            if let track { return "Paused — \(track)" }
            return "Paused"
        case .stopped, .noMedia:
            if let track { return track }
            return "Idle"
        case .transitioning:
            return "Loading..."
        }
    }

    private func createGroup() {
        guard let coordinatorId = groupSelection.first,
              let coordinator = viewModel.speakers.first(where: { $0.id == coordinatorId }) else { return }
        let members = viewModel.speakers.filter { groupSelection.contains($0.id) }
        Task {
            await viewModel.groupSpeakers(members, coordinator: coordinator)
            isGrouping = false
            groupSelection.removeAll()
        }
    }
}
