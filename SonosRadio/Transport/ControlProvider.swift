import Foundation

protocol ControlProvider: Sendable {
    func discoverSpeakers() async throws -> [Speaker]
    func play(streamURL: String, on speaker: Speaker, metadata: StationMetadata?) async throws
    func resume(speaker: Speaker) async throws
    func stop(speaker: Speaker) async throws
    func pause(speaker: Speaker) async throws
    func setVolume(_ level: Int, on speaker: Speaker) async throws
    func getVolume(of speaker: Speaker) async throws -> Int
    func mute(_ muted: Bool, on speaker: Speaker) async throws
    func groupSpeakers(_ speakers: [Speaker], coordinator: Speaker) async throws
    func ungroupSpeaker(_ speaker: Speaker) async throws
    func subscribeToEvents(for speaker: Speaker, handler: @escaping @Sendable (SpeakerEvent) -> Void) async throws
    func getCurrentTransportState(of speaker: Speaker) async throws -> TransportState
    func getMediaInfo(of speaker: Speaker) async throws -> (title: String?, uri: String?)
    func getZoneGroupState(from speaker: Speaker) async throws -> [SpeakerGroup]
    func getMusicServiceSN(serviceId: Int, from speaker: Speaker) async throws -> Int?
}
