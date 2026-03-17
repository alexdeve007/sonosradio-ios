import Foundation

/// Parses Sonos ZoneGroupState XML into SpeakerGroup arrays.
final class ZoneGroupParser: NSObject, XMLParserDelegate {
    private var groups: [SpeakerGroup] = []
    private var currentCoordinatorId: String?
    private var currentMembers: [Speaker] = []

    func parse(_ xml: String) -> [SpeakerGroup] {
        groups = []
        guard let data = xml.data(using: .utf8) else { return [] }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return groups
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if elementName == "ZoneGroup" {
            currentCoordinatorId = attributes["Coordinator"]
            currentMembers = []
        } else if elementName == "ZoneGroupMember" {
            guard let uuid = attributes["UUID"],
                  let zoneName = attributes["ZoneName"],
                  let location = attributes["Location"],
                  let locationURL = URL(string: location) else { return }

            let host = locationURL.host ?? ""
            let port = locationURL.port ?? 1400

            let speaker = Speaker(
                id: uuid,
                name: zoneName,
                ipAddress: host,
                port: port,
                isCoordinator: uuid == currentCoordinatorId,
                groupId: currentCoordinatorId
            )
            currentMembers.append(speaker)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "ZoneGroup", !currentMembers.isEmpty {
            if let coordinator = currentMembers.first(where: { $0.id == currentCoordinatorId }) {
                let others = currentMembers.filter { $0.id != currentCoordinatorId }
                groups.append(SpeakerGroup(coordinator: coordinator, members: others))
            }
        }
    }
}
