import Foundation

/// Parse UPnP event NOTIFY XML bodies into SpeakerEvent values.
struct UPnPEventParser {

    static func parse(_ xml: String) -> [SpeakerEvent] {
        var events: [SpeakerEvent] = []

        // The LastChange element contains HTML-encoded XML
        if let lastChange = XMLValueExtractor.extractValue(from: xml, atPath: ["propertyset", "property", "LastChange"]) {
            let decoded = lastChange
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&amp;", with: "&")

            let values = XMLValueExtractor.extractAllValues(from: decoded)

            if let stateStr = values["CurrentTransportState"] ?? extractAttribute(from: decoded, element: "TransportState", attribute: "val"),
               let state = TransportState(rawValue: stateStr) {
                events.append(.transportStateChanged(state))
            }

            if let volStr = values["CurrentVolume"] ?? extractAttribute(from: decoded, element: "Volume", attribute: "val"),
               let vol = Int(volStr) {
                events.append(.volumeChanged(vol))
            }

            if let muteStr = values["CurrentMute"] ?? extractAttribute(from: decoded, element: "Mute", attribute: "val") {
                events.append(.muteChanged(muteStr == "1"))
            }

            let title = values["CurrentTrackMetaData"].flatMap { extractDIDLTitle(from: $0) }
                ?? extractAttribute(from: decoded, element: "CurrentTrackMetaData", attribute: "val").flatMap { extractDIDLTitle(from: $0) }
            if title != nil {
                events.append(.trackChanged(title: title, artworkURL: nil, streamURL: nil))
            }
        }

        // ZoneGroupTopology changes
        if xml.contains("ZoneGroupState") {
            events.append(.groupTopologyChanged)
        }

        return events
    }

    private static func extractAttribute(from xml: String, element: String, attribute: String) -> String? {
        guard let elementRange = xml.range(of: "<\(element) ") else { return nil }
        let remaining = String(xml[elementRange.upperBound...])
        guard let attrRange = remaining.range(of: "\(attribute)=\"") else { return nil }
        let afterAttr = String(remaining[attrRange.upperBound...])
        guard let endQuote = afterAttr.firstIndex(of: "\"") else { return nil }
        return String(afterAttr[..<endQuote])
    }

    private static func extractDIDLTitle(from didl: String) -> String? {
        let decoded = didl
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        return XMLValueExtractor.extractValue(from: decoded, atPath: ["DIDL-Lite", "item", "title"])
    }
}
