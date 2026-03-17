import Foundation

@MainActor
@Observable
final class NowPlayingViewModel {
    var currentStation: Station?
    var activeSpeaker: Speaker?
    var transportState: TransportState = .stopped
    var volume: Int = 0
    var isMuted: Bool = false
    var errorMessage: String?

    private let provider: any ControlProvider
    private let volumeDebouncer = Debouncer(interval: .milliseconds(150))

    init(provider: any ControlProvider) {
        self.provider = provider
    }

    func play(station: Station, on speaker: Speaker) async {
        do {
            let metadata = StationMetadata(
                title: station.name,
                artworkURL: station.artworkURL,
                streamURL: station.streamURL
            )
            try await provider.play(streamURL: station.streamURL, on: speaker, metadata: metadata)
            currentStation = station
            activeSpeaker = speaker
            transportState = .playing
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() async {
        guard let speaker = activeSpeaker else { return }
        do {
            try await provider.stop(speaker: speaker)
            transportState = .stopped
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pause() async {
        guard let speaker = activeSpeaker else { return }
        do {
            try await provider.pause(speaker: speaker)
            transportState = .paused
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePlayPause() async {
        if transportState == .playing {
            await pause()
        } else {
            guard let speaker = activeSpeaker, let station = currentStation else { return }
            await play(station: station, on: speaker)
        }
    }

    func setVolume(_ level: Int) {
        volume = level
        guard let speaker = activeSpeaker else { return }
        let provider = self.provider
        Task {
            await volumeDebouncer.debounce {
                try? await provider.setVolume(level, on: speaker)
            }
        }
    }

    func toggleMute() async {
        guard let speaker = activeSpeaker else { return }
        do {
            isMuted.toggle()
            try await provider.mute(isMuted, on: speaker)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
