import Foundation

@MainActor
@Observable
final class NowPlayingViewModel {
    var currentStation: Station?
    var activeSpeaker: Speaker?
    var transportState: TransportState = .stopped
    var volume: Int = 0
    var isMuted: Bool = false
    var isLoading: Bool = false
    var errorMessage: String?
    var recentStations: [Station] = []

    private let provider: any ControlProvider
    private let volumeDebouncer = Debouncer(interval: .milliseconds(150))
    private let streamResolver = StreamResolver()
    private let tuneInService = TuneInService()
    private var tuneInSN: Int?

    private static let recentsKey = "recentStations.v1"
    private static let recentsCap = 20

    init(provider: any ControlProvider) {
        self.provider = provider
        // Restore persisted recents
        if let data = UserDefaults.standard.data(forKey: Self.recentsKey),
           let decoded = try? JSONDecoder().decode([Station].self, from: data) {
            self.recentStations = decoded
        }
    }

    func play(station: Station, on speaker: Speaker) async {
        isLoading = true
        errorMessage = nil
        print("[Play] Starting: '\(station.name)' (source=\(station.source), sourceId=\(station.sourceId ?? "nil")) on \(speaker.name) (\(speaker.ipAddress))")
        do {
            // Resolve the actual stream URL based on source
            var resolvedURL: String
            if station.source == .tuneIn, let guideId = station.sourceId {
                // Use Sonos-native TuneIn music service URI
                if tuneInSN == nil {
                    print("[Play] Discovering TuneIn service SN...")
                    tuneInSN = try await provider.getMusicServiceSN(serviceId: 254, from: speaker)
                    print("[Play] Discovered TuneIn SN: \(tuneInSN?.description ?? "nil, using default 1")")
                }
                let sn = tuneInSN ?? 1
                resolvedURL = "x-sonosapi-stream:\(guideId)?sid=254&flags=8232&sn=\(sn)"
                print("[Play] Using Sonos TuneIn URI: \(resolvedURL)")
            } else {
                print("[Play] Resolving stream URL: \(station.streamURL)")
                resolvedURL = try await streamResolver.resolve(url: station.streamURL)
            }
            // Wrap direct HTTP/HTTPS streams with x-rincon-mp3radio://
            // This tells Sonos to treat it as a radio stream (handles both protocols)
            if !resolvedURL.hasPrefix("x-sonosapi-stream:") && !resolvedURL.hasPrefix("x-rincon-") {
                resolvedURL = "x-rincon-mp3radio://\(resolvedURL)"
                print("[Play] Wrapped as Sonos radio URI: \(resolvedURL)")
            }

            print("[Play] Final stream URL: \(resolvedURL)")

            // Always pass metadata so Sonos knows the station name and content type
            let metadata = StationMetadata(title: station.name, streamURL: resolvedURL)

            print("[Play] Sending to speaker...")
            try await provider.play(streamURL: resolvedURL, on: speaker, metadata: metadata)
            print("[Play] Success!")
            addToRecents(station)
            currentStation = station
            activeSpeaker = speaker
            transportState = .playing
            volume = speaker.volume
            isMuted = speaker.isMuted
        } catch {
            print("[Play] ERROR: \(error)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
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

    func clearRecents() {
        recentStations = []
        persistRecents()
    }

    private func addToRecents(_ station: Station) {
        recentStations.removeAll { $0.id == station.id }
        recentStations.insert(station, at: 0)
        if recentStations.count > Self.recentsCap {
            recentStations = Array(recentStations.prefix(Self.recentsCap))
        }
        persistRecents()
    }

    private func persistRecents() {
        if let data = try? JSONEncoder().encode(recentStations) {
            UserDefaults.standard.set(data, forKey: Self.recentsKey)
        }
    }
}
