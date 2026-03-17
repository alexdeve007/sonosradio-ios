import Foundation

final class LocalUPnPProvider: ControlProvider, @unchecked Sendable {
    private let ssdp = SSDPDiscovery()
    private let soap = SOAPClient()
    private let eventServer = UPnPEventServer()

    // MARK: - Discovery

    func discoverSpeakers() async throws -> [Speaker] {
        let deviceURLs = try await ssdp.discover()
        var speakers: [Speaker] = []

        for url in deviceURLs {
            do {
                var speaker = try await ssdp.parseDeviceDescription(at: url)
                // Fetch initial state
                let vol = try? await getVolume(of: speaker)
                speaker.volume = vol ?? 0
                let state = try? await getCurrentTransportState(of: speaker)
                speaker.transportState = state ?? .stopped
                let isMuted = try? await getMuteState(of: speaker)
                speaker.isMuted = isMuted ?? false
                speakers.append(speaker)
            } catch {
                print("Failed to parse device at \(url): \(error)")
            }
        }

        return speakers
    }

    // MARK: - Playback

    func play(streamURL: String, on speaker: Speaker, metadata: StationMetadata?) async throws {
        let metadataXML = buildDIDLMetadata(metadata)

        _ = try await soap.invoke(
            action: "SetAVTransportURI",
            service: .avTransport,
            on: speaker,
            parameters: [
                ("CurrentURI", streamURL),
                ("CurrentURIMetaData", metadataXML)
            ]
        )

        _ = try await soap.invoke(
            action: "Play",
            service: .avTransport,
            on: speaker,
            parameters: [("Speed", "1")]
        )
    }

    func stop(speaker: Speaker) async throws {
        _ = try await soap.invoke(action: "Stop", service: .avTransport, on: speaker)
    }

    func pause(speaker: Speaker) async throws {
        _ = try await soap.invoke(action: "Pause", service: .avTransport, on: speaker)
    }

    func getCurrentTransportState(of speaker: Speaker) async throws -> TransportState {
        let result = try await soap.invokeAndParse(action: "GetTransportInfo", service: .avTransport, on: speaker)
        let stateStr = result["CurrentTransportState"] ?? "STOPPED"
        return TransportState(rawValue: stateStr) ?? .stopped
    }

    // MARK: - Volume

    func setVolume(_ level: Int, on speaker: Speaker) async throws {
        let clamped = max(0, min(100, level))
        _ = try await soap.invoke(
            action: "SetVolume",
            service: .renderingControl,
            on: speaker,
            parameters: [("Channel", "Master"), ("DesiredVolume", "\(clamped)")]
        )
    }

    func getVolume(of speaker: Speaker) async throws -> Int {
        let result = try await soap.invokeAndParse(
            action: "GetVolume",
            service: .renderingControl,
            on: speaker,
            parameters: [("Channel", "Master")]
        )
        return Int(result["CurrentVolume"] ?? "0") ?? 0
    }

    func mute(_ muted: Bool, on speaker: Speaker) async throws {
        _ = try await soap.invoke(
            action: "SetMute",
            service: .renderingControl,
            on: speaker,
            parameters: [("Channel", "Master"), ("DesiredMute", muted ? "1" : "0")]
        )
    }

    private func getMuteState(of speaker: Speaker) async throws -> Bool {
        let result = try await soap.invokeAndParse(
            action: "GetMute",
            service: .renderingControl,
            on: speaker,
            parameters: [("Channel", "Master")]
        )
        return result["CurrentMute"] == "1"
    }

    // MARK: - Grouping

    func groupSpeakers(_ speakers: [Speaker], coordinator: Speaker) async throws {
        for speaker in speakers where speaker.id != coordinator.id {
            _ = try await soap.invoke(
                action: "SetAVTransportURI",
                service: .avTransport,
                on: speaker,
                parameters: [
                    ("CurrentURI", "x-rincon:\(coordinator.id)"),
                    ("CurrentURIMetaData", "")
                ]
            )
        }
    }

    func ungroupSpeaker(_ speaker: Speaker) async throws {
        _ = try await soap.invoke(
            action: "BecomeCoordinatorOfStandaloneGroup",
            service: .avTransport,
            on: speaker,
            parameters: [("Speed", "1")]
        )
    }

    func getGroupTopology() async throws -> [SpeakerGroup] {
        // ZoneGroupTopology requires any speaker — will be wired during integration
        return []
    }

    // MARK: - Events

    func subscribeToEvents(for speaker: Speaker, handler: @escaping @Sendable (SpeakerEvent) -> Void) async throws {
        let port = try await eventServer.start()
        let localIP = getLocalIPAddress() ?? "0.0.0.0"

        let services: [SOAPClient.Service] = [.avTransport, .renderingControl]

        for service in services {
            let subscribeURL = URL(string: "http://\(speaker.ipAddress):\(speaker.port)\(service.eventPath)")!
            var request = URLRequest(url: subscribeURL)
            request.httpMethod = "SUBSCRIBE"
            request.setValue("<http://\(localIP):\(port)/event>", forHTTPHeaderField: "CALLBACK")
            request.setValue("upnp:event", forHTTPHeaderField: "NT")
            request.setValue("Second-1800", forHTTPHeaderField: "TIMEOUT")

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               let sid = httpResponse.value(forHTTPHeaderField: "SID") {
                await eventServer.register(sid: sid) { eventXML in
                    let events = UPnPEventParser.parse(eventXML)
                    for event in events {
                        handler(event)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func buildDIDLMetadata(_ metadata: StationMetadata?) -> String {
        guard let metadata = metadata else { return "" }

        let artworkTag: String
        if let artworkURL = metadata.artworkURL {
            artworkTag = "<upnp:albumArtURI>\(artworkURL.absoluteString)</upnp:albumArtURI>"
        } else {
            artworkTag = ""
        }

        return """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/"
                   xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"
                   xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
          <item>
            <dc:title>\(metadata.title)</dc:title>
            <upnp:class>object.item.audioItem.audioBroadcast</upnp:class>
            \(artworkTag)
            <res protocolInfo="*:*:*:*">\(metadata.streamURL)</res>
          </item>
        </DIDL-Lite>
        """
    }

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }
}
