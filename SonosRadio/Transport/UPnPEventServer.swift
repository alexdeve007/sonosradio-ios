import Foundation
import Network

/// Lightweight HTTP server that receives UPnP NOTIFY event callbacks from Sonos speakers.
actor UPnPEventServer {
    private var listener: NWListener?
    private var handlers: [String: @Sendable (String) -> Void] = [:]  // SID -> handler
    private var port: UInt16 = 0

    /// Start the event server on a random available port. Returns the port number.
    func start() throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener

        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("UPnPEventServer listener failed: \(error)")
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleConnection(connection) }
        }

        listener.start(queue: .global(qos: .userInitiated))

        // Wait briefly for the listener to bind
        if let actualPort = listener.port?.rawValue {
            self.port = actualPort
            return actualPort
        }

        return 0 // caller should retry or handle
    }

    func stop() {
        listener?.cancel()
        listener = nil
        handlers.removeAll()
    }

    func register(sid: String, handler: @escaping @Sendable (String) -> Void) {
        handlers[sid] = handler
    }

    func unregister(sid: String) {
        handlers[sid] = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let data = data, let self = self else {
                connection.cancel()
                return
            }

            let raw = String(data: data, encoding: .utf8) ?? ""
            Task { await self.processNotify(raw, connection: connection) }
        }
    }

    private func processNotify(_ raw: String, connection: NWConnection) {
        // Send HTTP 200 OK response
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })

        // Extract SID from headers
        guard let sid = extractHeader("SID", from: raw) else { return }
        // Extract body (after blank line)
        guard let bodyRange = raw.range(of: "\r\n\r\n") else { return }
        let body = String(raw[bodyRange.upperBound...])

        handlers[sid]?(body)
    }

    private func extractHeader(_ name: String, from raw: String) -> String? {
        for line in raw.components(separatedBy: "\r\n") {
            if line.uppercased().hasPrefix(name.uppercased() + ":") {
                return line.dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
