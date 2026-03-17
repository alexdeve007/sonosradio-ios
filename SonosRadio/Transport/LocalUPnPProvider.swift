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
        let metadataXML = metadata.map { buildDIDLMetadata($0, streamURL: streamURL) } ?? ""
        print("[UPnP] SetAVTransportURI: \(streamURL)")
        if !metadataXML.isEmpty {
            print("[UPnP] Metadata: \(metadataXML.prefix(300))")
        }

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

    func resume(speaker: Speaker) async throws {
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

    func getMediaInfo(of speaker: Speaker) async throws -> (title: String?, uri: String?) {
        let result = try await soap.invokeAndParse(
            action: "GetMediaInfo",
            service: .avTransport,
            on: speaker
        )
        let uri = result["CurrentURI"]
        // Title is embedded in CurrentURIMetaData as DIDL-Lite XML
        var title: String?
        if let metaXML = result["CurrentURIMetaData"], !metaXML.isEmpty {
            let decoded = metaXML
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
            title = XMLValueExtractor.extractValue(from: decoded, atPath: ["DIDL-Lite", "item", "title"])
        }
        return (title: title, uri: uri)
    }


    func getZoneGroupState(from speaker: Speaker) async throws -> [SpeakerGroup] {
        let result = try await soap.invoke(
            action: "GetZoneGroupState",
            service: .zoneGroupTopology,
            on: speaker
        )
        return parseZoneGroupState(result)
    }

    func getMusicServiceSN(serviceId: Int, from speaker: Speaker) async throws -> Int? {
        let body = try await soap.invoke(
            action: "ListAvailableServices",
            service: .musicServices,
            on: speaker
        )
        print("[MusicServices] ListAvailableServices response length: \(body.count)")

        // The response contains AvailableServiceDescriptorList (HTML-encoded XML)
        // and AvailableServiceTypeList (comma-separated "sid:typeNum" pairs).
        // We need to find the account SN for the requested service.

        // First, try to find the SN by scanning all speakers' current URIs
        // for an x-sonosapi-stream URI with the matching sid.
        // This is the most reliable since it shows the actual sn in use.

        // Decode the descriptor list to find service accounts
        let allValues = XMLValueExtractor.extractAllValues(from: body)
        if let descriptorList = allValues["AvailableServiceDescriptorList"] {
            let decoded = descriptorList
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
            print("[MusicServices] Decoded descriptors (first 500): \(decoded.prefix(500))")

            // Parse Service elements to find the one with our Id
            // Look for SerialNum or SN attribute
            let snPattern = "Id=\"\(serviceId)\"[^>]*SerialNum=\"(\\d+)\""
            if let regex = try? NSRegularExpression(pattern: snPattern),
               let match = regex.firstMatch(in: decoded, range: NSRange(decoded.startIndex..., in: decoded)),
               let snRange = Range(match.range(at: 1), in: decoded) {
                return Int(decoded[snRange])
            }
        }

        // Fallback: scan AvailableServiceTypeList for the service type number
        // Format: "sid1:typeNum1,sid2:typeNum2,..."
        if let typeList = allValues["AvailableServiceTypeList"] {
            print("[MusicServices] AvailableServiceTypeList: \(typeList)")
        }

        print("[MusicServices] Could not find SN for service \(serviceId)")
        return nil
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

    private func parseZoneGroupState(_ xml: String) -> [SpeakerGroup] {
        let allValues = XMLValueExtractor.extractAllValues(from: xml)
        guard var groupStateXML = allValues["ZoneGroupState"] else { return [] }
        groupStateXML = groupStateXML
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
        let parser = ZoneGroupParser()
        return parser.parse(groupStateXML)
    }

    private func buildDIDLMetadata(_ metadata: StationMetadata?, streamURL: String) -> String {
        guard let metadata = metadata else { return "" }

        // Sonos music service URIs — need Rincon service descriptors
        if streamURL.hasPrefix("x-sonosapi-stream:") {
            if streamURL.contains("sid=6") {
                return buildMusicServiceDIDL(metadata, streamURL: streamURL, rincon: "SA_RINCON1543_X_#Svc1543-0-Token")
            }
            return buildMusicServiceDIDL(metadata, streamURL: streamURL, rincon: "SA_RINCON65031_")
        }

        // Direct HTTP/HTTPS streams
        return buildDirectStreamDIDL(metadata, streamURL: streamURL)
    }

    private func buildMusicServiceDIDL(_ metadata: StationMetadata, streamURL: String, rincon: String) -> String {
        let title = escapeXMLValue(metadata.title)
        // Extract item ID from x-sonosapi-stream:ITEMID?...
        let itemId: String
        if let qIdx = streamURL.firstIndex(of: "?") {
            itemId = String(streamURL[streamURL.index(after: streamURL.firstIndex(of: ":")!)..<qIdx])
        } else {
            itemId = String(streamURL.dropFirst("x-sonosapi-stream:".count))
        }

        return """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"><item id="10092064\(itemId)" parentID="0" restricted="true"><dc:title>\(title)</dc:title><upnp:class>object.item.audioItem.audioBroadcast</upnp:class><desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">\(rincon)</desc></item></DIDL-Lite>
        """
    }

    private func buildDirectStreamDIDL(_ metadata: StationMetadata, streamURL: String) -> String {
        let title = escapeXMLValue(metadata.title)
        let escapedURL = escapeXMLValue(streamURL)

        return """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"><item id="-1" parentID="-1" restricted="true"><dc:title>\(title)</dc:title><upnp:class>object.item.audioItem.audioBroadcast</upnp:class><res protocolInfo="http-get:*:*:*">\(escapedURL)</res></item></DIDL-Lite>
        """
    }

    private func escapeXMLValue(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
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
                    if let nullIndex = hostname.firstIndex(of: 0) {
                        address = String(decoding: hostname[..<nullIndex].map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    }
                }
            }
        }
        return address
    }
}
