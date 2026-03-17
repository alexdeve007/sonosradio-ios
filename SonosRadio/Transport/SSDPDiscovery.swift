import Foundation
import Network

final class SSDPDiscovery: Sendable {

    /// Discover Sonos speakers on the local network.
    /// Phase 1: Use Bonjour to find and resolve Sonos services to IPv4 addresses.
    /// Phase 2: Probe resolved IPs on port 1400 for device descriptions.
    /// Fallback: Subnet scan if Bonjour finds nothing.
    func discover(timeout: TimeInterval = 5.0) async throws -> [URL] {
        // Phase 1: Bonjour discovery + resolution
        print("[SSDP] Phase 1: Bonjour discovery...")
        let bonjourIPs = await BonjourResolver.findSonosIPs(timeout: 3.0)
        print("[SSDP] Bonjour resolved \(bonjourIPs.count) IP(s): \(bonjourIPs)")

        if !bonjourIPs.isEmpty {
            // Phase 2: Probe only the known IPs on port 1400
            var urls: [URL] = []
            for ip in bonjourIPs {
                let urlStr = "http://\(ip):1400/xml/device_description.xml"
                guard let url = URL(string: urlStr) else { continue }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 3.0
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if let httpResponse = response as? HTTPURLResponse,
                       httpResponse.statusCode == 200 {
                        let body = String(data: data, encoding: .utf8) ?? ""
                        if body.contains("Sonos") || body.contains("ZonePlayer") || body.contains("RINCON") {
                            print("[SSDP] Confirmed Sonos device at \(ip)")
                            urls.append(url)
                        }
                    }
                } catch {
                    print("[SSDP] Failed to probe \(ip): \(error.localizedDescription)")
                }
            }
            if !urls.isEmpty {
                print("[SSDP] Discovery complete: found \(urls.count) device(s)")
                return urls
            }
        }

        // Fallback: subnet scan
        print("[SSDP] Bonjour found no devices, falling back to subnet scan...")
        guard let localIP = Self.getLocalIPAddress() else {
            print("[SSDP] Could not determine local WiFi IP address")
            return []
        }

        let prefix = localIP.components(separatedBy: ".").prefix(3).joined(separator: ".")
        print("[SSDP] Scanning subnet \(prefix).0/24 on port 1400...")
        return await scanSubnet(prefix: prefix, timeout: timeout)
    }

    /// Scan all 254 addresses on the subnet for Sonos speakers (port 1400).
    private func scanSubnet(prefix: String, timeout: TimeInterval) async -> [URL] {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 2
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let batchSize = 50
        var allURLs: [URL] = []

        for batchStart in stride(from: 1, through: 254, by: batchSize) {
            let batchEnd = min(batchStart + batchSize - 1, 254)
            let batchURLs = await withTaskGroup(of: URL?.self) { group in
                for i in batchStart...batchEnd {
                    group.addTask {
                        let urlStr = "http://\(prefix).\(i):1400/xml/device_description.xml"
                        guard let url = URL(string: urlStr) else { return nil }
                        var request = URLRequest(url: url)
                        request.httpMethod = "GET"
                        request.timeoutInterval = timeout
                        do {
                            let (data, response) = try await session.data(for: request)
                            if let httpResponse = response as? HTTPURLResponse,
                               httpResponse.statusCode == 200 {
                                let body = String(data: data, encoding: .utf8) ?? ""
                                if body.contains("Sonos") || body.contains("ZonePlayer") || body.contains("RINCON") {
                                    print("[SSDP] Found Sonos device at \(prefix).\(i)")
                                    return url
                                }
                            }
                        } catch {
                            // Host unreachable, connection refused, timeout — skip
                        }
                        return nil
                    }
                }

                var urls: [URL] = []
                for await url in group {
                    if let url { urls.append(url) }
                }
                return urls
            }
            allURLs.append(contentsOf: batchURLs)
        }

        print("[SSDP] Subnet scan complete: found \(allURLs.count) device(s)")
        return allURLs
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

    /// Get the local WiFi IPv4 address.
    static func getLocalIPAddress() -> String? {
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
                        return String(decoding: hostname[..<nullIndex].map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    }
                }
            }
        }
        return nil
    }

    enum SSDPError: LocalizedError {
        case socketCreationFailed
        case sendFailed(errno: Int32)
        case invalidDeviceDescription

        var errorDescription: String? {
            switch self {
            case .socketCreationFailed: return "Failed to create UDP socket for SSDP"
            case .sendFailed(let err):
                if let ptr = strerror(err) {
                    return "SSDP send failed: \(String(cString: ptr)) (errno \(err))"
                }
                return "SSDP send failed (errno \(err))"
            case .invalidDeviceDescription: return "Invalid UPnP device description"
            }
        }
    }
}

// MARK: - Bonjour Resolver using NetService

/// Resolves Sonos Bonjour services to IPv4 addresses using NetServiceBrowser.
private final class BonjourResolver: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    private var browser: NetServiceBrowser?
    private var pendingServices: [NetService] = []
    private var resolvedIPs: Set<String> = []
    private var completion: (([String]) -> Void)?

    static func findSonosIPs(timeout: TimeInterval) async -> [String] {
        await withCheckedContinuation { continuation in
            let resolver = BonjourResolver()
            resolver.start(timeout: timeout) { ips in
                continuation.resume(returning: ips)
            }
        }
    }

    private func start(timeout: TimeInterval, completion: @escaping ([String]) -> Void) {
        self.completion = completion

        // NetServiceBrowser must run on a thread with a RunLoop
        let thread = Thread {
            self.browser = NetServiceBrowser()
            self.browser?.delegate = self
            self.browser?.searchForServices(ofType: "_sonos._tcp.", inDomain: "local.")

            // Run the run loop for the timeout duration
            let deadline = Date(timeIntervalSinceNow: timeout)
            while Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
            }

            self.browser?.stop()
            self.finish()
        }
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    private func finish() {
        let ips = Array(resolvedIPs)
        completion?(ips)
        completion = nil
    }

    // MARK: - NetServiceBrowserDelegate

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("[Bonjour] Found service: \(service.name)")
        pendingServices.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        print("[Bonjour] Search failed: \(errorDict)")
    }

    // MARK: - NetServiceDelegate

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses else { return }
        for data in addresses {
            if data.count == MemoryLayout<sockaddr_in>.size {
                data.withUnsafeBytes { ptr in
                    let sin = ptr.load(as: sockaddr_in.self)
                    if sin.sin_family == sa_family_t(AF_INET) {
                        var addr = sin.sin_addr
                        var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        inet_ntop(AF_INET, &addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
                        let ip: String
                        if let nullIndex = ipBuf.firstIndex(of: 0) {
                            ip = String(decoding: ipBuf[..<nullIndex].map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        } else {
                            ip = String(decoding: ipBuf.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        }
                        print("[Bonjour] Resolved \(sender.name) -> \(ip)")
                        resolvedIPs.insert(ip)
                    }
                }
            }
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("[Bonjour] Failed to resolve \(sender.name): \(errorDict)")
    }
}
