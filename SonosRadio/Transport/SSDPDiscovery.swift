import Foundation

final class SSDPDiscovery: Sendable {
    private static let multicastAddress = "239.255.255.250"
    private static let multicastPort: UInt16 = 1900
    private static let searchTarget = "urn:schemas-upnp-org:device:ZonePlayer:1"

    private static var searchMessage: String {
        "M-SEARCH * HTTP/1.1\r\nHOST: \(multicastAddress):\(multicastPort)\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: \(searchTarget)\r\n\r\n"
    }

    /// Discover Sonos speakers on the local network. Returns unique device description URLs.
    func discover(timeout: TimeInterval = 3.0) async throws -> [URL] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let urls = try self.performDiscovery(timeout: timeout)
                    continuation.resume(returning: urls)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performDiscovery(timeout: TimeInterval) throws -> [URL] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw SSDPError.socketCreationFailed }
        defer { close(fd) }

        // Allow address reuse
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Set receive timeout
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Build multicast destination
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = Self.multicastPort.bigEndian
        inet_pton(AF_INET, Self.multicastAddress, &addr.sin_addr)

        // Send M-SEARCH
        let message = Self.searchMessage
        let sent = message.withCString { ptr in
            withUnsafePointer(to: addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    sendto(fd, ptr, strlen(ptr), 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent > 0 else { throw SSDPError.sendFailed }

        // Receive responses
        var discoveredURLs = Set<URL>()
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: 4096)
        defer { buffer.deallocate() }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let received = recv(fd, buffer, 4096, 0)
            if received <= 0 { break }

            buffer[received] = 0  // null-terminate
            let response = String(cString: buffer)
            if let locationURL = Self.extractLocation(from: response) {
                discoveredURLs.insert(locationURL)
            }
        }

        return Array(discoveredURLs)
    }

    /// Parse the LOCATION header from an SSDP response.
    private static func extractLocation(from response: String) -> URL? {
        for line in response.components(separatedBy: "\r\n") {
            if line.uppercased().hasPrefix("LOCATION:") {
                let value = line.dropFirst("LOCATION:".count).trimmingCharacters(in: .whitespaces)
                return URL(string: value)
            }
        }
        return nil
    }

    /// Fetch and parse a UPnP device description XML to create a Speaker.
    func parseDeviceDescription(at url: URL) async throws -> Speaker {
        let (data, _) = try await URLSession.shared.data(from: url)
        let xml = String(data: data, encoding: .utf8) ?? ""

        guard let udn = XMLValueExtractor.extractValue(from: xml, atPath: ["root", "device", "UDN"]) else {
            throw SSDPError.invalidDeviceDescription
        }

        let friendlyName = XMLValueExtractor.extractValue(from: xml, atPath: ["root", "device", "friendlyName"]) ?? "Unknown"
        let roomName = XMLValueExtractor.extractValue(from: xml, atPath: ["root", "device", "roomName"]) ?? friendlyName
        let modelName = XMLValueExtractor.extractValue(from: xml, atPath: ["root", "device", "modelName"]) ?? ""

        // UDN format: "uuid:RINCON_xxxxxxxxxxxx01400"
        let id = udn.replacingOccurrences(of: "uuid:", with: "")

        guard let host = url.host else { throw SSDPError.invalidDeviceDescription }
        let port = url.port ?? 1400

        return Speaker(
            id: id,
            name: roomName,
            ipAddress: host,
            port: port,
            modelName: modelName
        )
    }

    enum SSDPError: LocalizedError {
        case socketCreationFailed
        case sendFailed
        case invalidDeviceDescription

        var errorDescription: String? {
            switch self {
            case .socketCreationFailed: return "Failed to create UDP socket for SSDP"
            case .sendFailed: return "Failed to send SSDP M-SEARCH"
            case .invalidDeviceDescription: return "Invalid UPnP device description"
            }
        }
    }
}
