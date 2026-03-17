import Foundation

@MainActor
@Observable
final class SpeakersViewModel {
    var speakers: [Speaker] = []
    var groups: [SpeakerGroup] = []
    var selectedSpeaker: Speaker?
    var isDiscovering = false
    var errorMessage: String?

    private let provider: any ControlProvider
    private var pollingTask: Task<Void, Never>?
    private let volumeDebouncer = Debouncer(interval: .milliseconds(200))

    init(provider: any ControlProvider) {
        self.provider = provider
    }

    func discover() async {
        isDiscovering = true
        errorMessage = nil
        do {
            speakers = try await provider.discoverSpeakers()

            // Fetch zone group topology to know which speakers are grouped
            if let anySpeaker = speakers.first {
                let topology = (try? await provider.getZoneGroupState(from: anySpeaker)) ?? []
                applyGroupTopology(topology)
            }

            speakers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            rebuildGroups()

            if selectedSpeaker == nil, let first = speakers.first {
                selectedSpeaker = first
            }
            startPolling()
        } catch {
            errorMessage = error.localizedDescription
        }
        isDiscovering = false
    }

    func selectSpeaker(_ speaker: Speaker) {
        selectedSpeaker = speaker
    }

    func togglePlayPause(on speaker: Speaker) async {
        do {
            switch speaker.transportState {
            case .playing:
                try await provider.pause(speaker: speaker)
                if let idx = speakers.firstIndex(where: { $0.id == speaker.id }) {
                    speakers[idx].transportState = .paused
                }
            case .paused:
                try await provider.resume(speaker: speaker)
                if let idx = speakers.firstIndex(where: { $0.id == speaker.id }) {
                    speakers[idx].transportState = .playing
                }
            default:
                break
            }
            rebuildGroups()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setVolume(_ level: Int, on speaker: Speaker) {
        if let idx = speakers.firstIndex(where: { $0.id == speaker.id }) {
            speakers[idx].volume = level
        }
        if selectedSpeaker?.id == speaker.id {
            selectedSpeaker?.volume = level
        }
        let provider = self.provider
        Task {
            await volumeDebouncer.debounce {
                try? await provider.setVolume(level, on: speaker)
            }
        }
    }

    func toggleMute(on speaker: Speaker) async {
        let newMute = !speaker.isMuted
        if let idx = speakers.firstIndex(where: { $0.id == speaker.id }) {
            speakers[idx].isMuted = newMute
        }
        if selectedSpeaker?.id == speaker.id {
            selectedSpeaker?.isMuted = newMute
        }
        do {
            try await provider.mute(newMute, on: speaker)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func groupSpeakers(_ selected: [Speaker], coordinator: Speaker) async {
        do {
            try await provider.groupSpeakers(selected, coordinator: coordinator)
            // Re-fetch topology after grouping
            if let anySpeaker = speakers.first {
                try? await Task.sleep(for: .seconds(1))
                let topology = (try? await provider.getZoneGroupState(from: anySpeaker)) ?? []
                applyGroupTopology(topology)
                rebuildGroups()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func ungroupSpeaker(_ speaker: Speaker) async {
        do {
            try await provider.ungroupSpeaker(speaker)
            if let anySpeaker = speakers.first {
                try? await Task.sleep(for: .seconds(1))
                let topology = (try? await provider.getZoneGroupState(from: anySpeaker)) ?? []
                applyGroupTopology(topology)
                rebuildGroups()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Group Topology

    /// Apply zone group topology to discovered speakers (set groupId/isCoordinator).
    private func applyGroupTopology(_ topology: [SpeakerGroup]) {
        for group in topology {
            let coordinatorId = group.coordinator.id
            for member in group.allSpeakers {
                if let idx = speakers.firstIndex(where: { $0.id == member.id }) {
                    speakers[idx].groupId = coordinatorId
                    speakers[idx].isCoordinator = (member.id == coordinatorId)
                }
            }
        }
    }

    /// Build display groups from the flat speaker list using groupId.
    private func rebuildGroups() {
        var groupMap: [String: SpeakerGroup] = [:]
        for speaker in speakers {
            let gid = speaker.groupId ?? speaker.id
            if speaker.isCoordinator || groupMap[gid] == nil {
                if var existing = groupMap[gid] {
                    if speaker.isCoordinator {
                        existing.members.insert(existing.coordinator, at: 0)
                        existing.members.removeAll { $0.id == speaker.id }
                        existing.coordinator = speaker
                    } else {
                        existing.members.append(speaker)
                    }
                    groupMap[gid] = existing
                } else {
                    groupMap[gid] = SpeakerGroup(coordinator: speaker, members: [])
                }
            } else {
                groupMap[gid]!.members.append(speaker)
            }
        }
        groups = groupMap.values.sorted {
            $0.coordinator.name.localizedCaseInsensitiveCompare($1.coordinator.name) == .orderedAscending
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                await refreshSpeakerStates()
            }
        }
    }

    private func refreshSpeakerStates() async {
        // Only poll coordinators for transport state + media info.
        // Poll all speakers for volume (each speaker has independent volume).
        let coordinatorIds = Set(groups.map(\.coordinator.id))

        await withTaskGroup(of: (Int, TransportState?, Int?, String?, String?)?.self) { group in
            for (index, speaker) in speakers.enumerated() {
                let isCoord = coordinatorIds.contains(speaker.id)
                group.addTask { [provider] in
                    let volume = try? await provider.getVolume(of: speaker)
                    if isCoord {
                        let state = try? await provider.getCurrentTransportState(of: speaker)
                        let media = try? await provider.getMediaInfo(of: speaker)
                        return (index, state, volume, media?.title, media?.uri)
                    } else {
                        return (index, nil, volume, nil, nil)
                    }
                }
            }
            for await result in group {
                guard let (index, state, volume, trackName, streamURI) = result, index < speakers.count else { continue }
                if let state, speakers[index].transportState != state {
                    speakers[index].transportState = state
                }
                if let volume, speakers[index].volume != volume {
                    speakers[index].volume = volume
                }
                if let trackName, speakers[index].currentTrackName != trackName {
                    speakers[index].currentTrackName = trackName
                }
                if let streamURI, speakers[index].currentStreamURL != streamURI {
                    speakers[index].currentStreamURL = streamURI
                }
            }
        }
        rebuildGroups()
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
