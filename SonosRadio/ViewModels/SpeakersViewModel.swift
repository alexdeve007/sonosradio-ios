import Foundation
import SwiftData

@MainActor
@Observable
final class SpeakersViewModel {
    var speakers: [Speaker] = []
    var groups: [SpeakerGroup] = []
    var isDiscovering = false
    var errorMessage: String?

    private let provider: any ControlProvider
    private var pollingTask: Task<Void, Never>?

    init(provider: any ControlProvider) {
        self.provider = provider
    }

    func discover() async {
        isDiscovering = true
        errorMessage = nil
        do {
            speakers = try await provider.discoverSpeakers()
            groups = try await provider.getGroupTopology()
            startPolling()
        } catch {
            errorMessage = error.localizedDescription
        }
        isDiscovering = false
    }

    func setVolume(_ level: Int, on speaker: Speaker) async {
        do {
            try await provider.setVolume(level, on: speaker)
            if let idx = speakers.firstIndex(where: { $0.id == speaker.id }) {
                speakers[idx].volume = level
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleMute(on speaker: Speaker) async {
        do {
            let newMute = !speaker.isMuted
            try await provider.mute(newMute, on: speaker)
            if let idx = speakers.firstIndex(where: { $0.id == speaker.id }) {
                speakers[idx].isMuted = newMute
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func groupSpeakers(_ selected: [Speaker], coordinator: Speaker) async {
        do {
            try await provider.groupSpeakers(selected, coordinator: coordinator)
            groups = try await provider.getGroupTopology()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func ungroupSpeaker(_ speaker: Speaker) async {
        do {
            try await provider.ungroupSpeaker(speaker)
            groups = try await provider.getGroupTopology()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                await refreshSpeakerStates()
            }
        }
    }

    private func refreshSpeakerStates() async {
        for (index, speaker) in speakers.enumerated() {
            do {
                let state = try await provider.getCurrentTransportState(of: speaker)
                let volume = try await provider.getVolume(of: speaker)
                speakers[index].transportState = state
                speakers[index].volume = volume
            } catch {
                // Speaker may be offline
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
