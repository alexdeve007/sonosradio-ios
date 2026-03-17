import Foundation

/// Simple XML value extractor using XMLParser.
/// Usage: XMLValueExtractor.extractValue(from: xmlString, atPath: ["Envelope", "Body", "GetVolumeResponse", "CurrentVolume"])
final class XMLValueExtractor: NSObject, XMLParserDelegate {
    private let targetPath: [String]
    private var currentPath: [String] = []
    private var result: String?
    private var currentText = ""

    private init(targetPath: [String]) {
        self.targetPath = targetPath
    }

    static func extractValue(from xml: String, atPath path: [String]) -> String? {
        guard let data = xml.data(using: .utf8) else { return nil }
        let extractor = XMLValueExtractor(targetPath: path)
        let parser = XMLParser(data: data)
        parser.delegate = extractor
        parser.parse()
        return extractor.result
    }

    /// Extract all leaf element values from XML into a flat dictionary.
    /// Keys are local element names (without namespace prefix).
    static func extractAllValues(from xml: String) -> [String: String] {
        guard let data = xml.data(using: .utf8) else { return [:] }
        let extractor = XMLAllValuesExtractor()
        let parser = XMLParser(data: data)
        parser.delegate = extractor
        parser.parse()
        return extractor.values
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        currentPath.append(localName)
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if currentPath == targetPath {
            result = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        currentPath.removeLast()
    }
}

private final class XMLAllValuesExtractor: NSObject, XMLParserDelegate {
    var values: [String: String] = [:]
    private var currentText = ""
    private var currentElement = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        currentElement = elementName.components(separatedBy: ":").last ?? elementName
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let localName = elementName.components(separatedBy: ":").last ?? elementName
            values[localName] = text
        }
    }
}
