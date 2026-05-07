import Foundation

// MARK: - Transport State

enum TransportState: String, Sendable {
    case playing = "PLAYING"
    case paused = "PAUSED_PLAYBACK"
    case stopped = "STOPPED"
    case transitioning = "TRANSITIONING"
    case noMedia = "NO_MEDIA_PRESENT"
}

// MARK: - Speaker

struct Speaker: Identifiable, Hashable, Sendable {
    let id: String          // RINCON UUID e.g. "RINCON_xxxxxxxxxxxx01400"
    var name: String
    var ipAddress: String
    var port: Int = 1400
    var modelName: String = ""
    var firmwareVersion: String = ""

    var volume: Int = 0
    var isMuted: Bool = false
    var transportState: TransportState = .stopped

    var currentTrackName: String?
    var currentTrackArtworkURL: URL?
    var currentStreamURL: String?

    var isCoordinator: Bool = true
    var groupId: String?

    /// False for bonded secondaries — subs, stereo pair partners, surround satellites.
    /// These devices are physically real but should not appear in the user-facing speaker list,
    /// and they reject grouping commands.
    var isVisible: Bool = true
}

// MARK: - Speaker Group

struct SpeakerGroup: Identifiable, Sendable, Equatable {
    var id: String { coordinator.id }
    var coordinator: Speaker
    var members: [Speaker]

    var allSpeakers: [Speaker] {
        [coordinator] + members.filter { $0.id != coordinator.id }
    }
}

// MARK: - Station Metadata (for playback)

struct StationMetadata: Sendable {
    var title: String
    var artworkURL: URL?
    var streamURL: String
}

// MARK: - Speaker Event

enum SpeakerEvent: Sendable {
    case transportStateChanged(TransportState)
    case volumeChanged(Int)
    case muteChanged(Bool)
    case trackChanged(title: String?, artworkURL: URL?, streamURL: String?)
    case groupTopologyChanged
}
