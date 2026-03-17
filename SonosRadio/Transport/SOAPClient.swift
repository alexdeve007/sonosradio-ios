import Foundation

struct SOAPClient: Sendable {

    // MARK: - Service Endpoints

    enum Service: String, Sendable {
        case avTransport = "AVTransport"
        case renderingControl = "RenderingControl"
        case zoneGroupTopology = "ZoneGroupTopology"
        case groupRenderingControl = "GroupRenderingControl"

        var controlPath: String {
            switch self {
            case .avTransport: return "/MediaRenderer/AVTransport/Control"
            case .renderingControl: return "/MediaRenderer/RenderingControl/Control"
            case .zoneGroupTopology: return "/ZoneGroupTopology/Control"
            case .groupRenderingControl: return "/MediaRenderer/GroupRenderingControl/Control"
            }
        }

        var eventPath: String {
            switch self {
            case .avTransport: return "/MediaRenderer/AVTransport/Event"
            case .renderingControl: return "/MediaRenderer/RenderingControl/Event"
            case .zoneGroupTopology: return "/ZoneGroupTopology/Event"
            case .groupRenderingControl: return "/MediaRenderer/GroupRenderingControl/Event"
            }
        }

        var serviceType: String {
            "urn:schemas-upnp-org:service:\(rawValue):1"
        }
    }

    // MARK: - Errors

    enum SOAPError: LocalizedError {
        case httpError(statusCode: Int, body: String)
        case soapFault(faultCode: String, faultString: String)
        case invalidResponse
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .httpError(let code, let body): return "HTTP \(code): \(body)"
            case .soapFault(_, let string): return "SOAP Fault: \(string)"
            case .invalidResponse: return "Invalid SOAP response"
            case .networkError(let error): return "Network error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Envelope Builder

    func buildEnvelope(action: String, service: Service, parameters: [(name: String, value: String)] = []) -> String {
        var params = ""
        for (name, value) in parameters {
            params += "<\(name)>\(escapeXML(value))</\(name)>"
        }

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
                    s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:\(action) xmlns:u="\(service.serviceType)">
              <InstanceID>0</InstanceID>
              \(params)
            </u:\(action)>
          </s:Body>
        </s:Envelope>
        """
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    // MARK: - HTTP Execution

    func invoke(action: String, service: Service, on speaker: Speaker, parameters: [(name: String, value: String)] = []) async throws -> String {
        let envelope = buildEnvelope(action: action, service: service, parameters: parameters)
        let urlString = "http://\(speaker.ipAddress):\(speaker.port)\(service.controlPath)"

        guard let url = URL(string: urlString) else {
            throw SOAPError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\(service.serviceType)#\(action)", forHTTPHeaderField: "SOAPAction")
        request.httpBody = envelope.data(using: .utf8)
        request.timeoutInterval = 5

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SOAPError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SOAPError.invalidResponse
        }

        let body = String(data: data, encoding: .utf8) ?? ""

        if httpResponse.statusCode == 500 {
            let faultCode = XMLValueExtractor.extractValue(from: body, atPath: ["Envelope", "Body", "Fault", "faultcode"]) ?? "unknown"
            let faultString = XMLValueExtractor.extractValue(from: body, atPath: ["Envelope", "Body", "Fault", "faultstring"]) ?? "Unknown SOAP fault"
            throw SOAPError.soapFault(faultCode: faultCode, faultString: faultString)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SOAPError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return body
    }

    /// Invoke a SOAP action and parse the response body into a flat key-value dictionary.
    func invokeAndParse(action: String, service: Service, on speaker: Speaker, parameters: [(name: String, value: String)] = []) async throws -> [String: String] {
        let body = try await invoke(action: action, service: service, on: speaker, parameters: parameters)
        return XMLValueExtractor.extractAllValues(from: body)
    }
}
