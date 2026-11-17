import Foundation
import VideoPlayerCore
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Local part of an XML name: "dc:title" -> "title".
private func localName(_ qualified: String) -> String {
    if let index = qualified.lastIndex(of: ":") { return String(qualified[qualified.index(after: index)...]) }
    return qualified
}

// MARK: Device description

public struct UPnPService: Equatable, Sendable {
    public var serviceType: String
    public var controlURL: String
}

/// What the device description XML (`/rootDesc.xml`) tells us.
public struct UPnPDeviceDescription: Equatable, Sendable {
    public var deviceType: String?
    public var friendlyName: String?
    public var manufacturer: String?
    public var modelName: String?
    public var udn: String?
    public var urlBase: String?
    public var services: [UPnPService]

    /// The ContentDirectory service (any version).
    public var contentDirectory: UPnPService? {
        services.first { $0.serviceType.contains(":service:ContentDirectory:") }
    }

    public var isMediaServer: Bool { deviceType?.contains(":device:MediaServer:") ?? false }

    public static func parse(_ data: Data) throws -> UPnPDeviceDescription {
        let delegate = DescriptionDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.sawRoot else { throw SourceError.malformedResponse }
        return UPnPDeviceDescription(
            deviceType: delegate.deviceType, friendlyName: delegate.friendlyName,
            manufacturer: delegate.manufacturer, modelName: delegate.modelName,
            udn: delegate.udn, urlBase: delegate.urlBase, services: delegate.services
        )
    }

    private final class DescriptionDelegate: NSObject, XMLParserDelegate {
        var sawRoot = false
        var deviceType, friendlyName, manufacturer, modelName, udn, urlBase: String?
        var services: [UPnPService] = []
        private var path: [String] = []
        private var text = ""
        private var serviceType = ""
        private var controlURL = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            let name = localName(elementName)
            if path.isEmpty, name == "root" { sawRoot = true }
            path.append(name)
            text = ""
            if name == "service" { serviceType = ""; controlURL = "" }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let name = localName(elementName)
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let inService = path.contains("service")
            // The first device in the document is the root device; embedded devices come later.
            switch name {
            case "URLBase": if urlBase == nil, !value.isEmpty { urlBase = value }
            case "deviceType": if deviceType == nil { deviceType = value }
            case "friendlyName": if friendlyName == nil { friendlyName = value }
            case "manufacturer": if manufacturer == nil { manufacturer = value }
            case "modelName": if modelName == nil { modelName = value }
            case "UDN": if udn == nil { udn = value }
            case "serviceType": if inService { serviceType = value }
            case "controlURL": if inService { controlURL = value }
            case "service":
                if !serviceType.isEmpty, !controlURL.isEmpty {
                    services.append(UPnPService(serviceType: serviceType, controlURL: controlURL))
                }
            default: break
            }
            text = ""
            _ = path.popLast()
        }
    }
}

// MARK: SOAP response

/// A parsed ContentDirectory `BrowseResponse` (or a SOAP fault).
struct BrowseResponse: Equatable {
    var didl: String
    var numberReturned: Int
    var totalMatches: Int
    var updateID: String?
}

enum SOAPParser {
    /// Throws a mapped `SourceError` when the body is a UPnP fault.
    static func parseBrowse(_ data: Data) throws -> BrowseResponse {
        let delegate = SOAPDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        let ok = parser.parse()
        if let code = delegate.errorCode { throw map(code: code, description: delegate.errorDescription) }
        guard ok, delegate.sawBrowseResponse else { throw SourceError.malformedResponse }
        return BrowseResponse(
            didl: delegate.result, numberReturned: delegate.numberReturned,
            totalMatches: delegate.totalMatches, updateID: delegate.updateID
        )
    }

    /// UPnP ContentDirectory error codes: 701 no such object, 710 no such container; 401/501 etc. are other failures.
    static func map(code: Int, description: String?) -> SourceError {
        switch code {
        case 701, 710: return .notFound
        default: return .transport("UPnP error \(code)" + (description.map { ": \($0)" } ?? ""))
        }
    }

    private final class SOAPDelegate: NSObject, XMLParserDelegate {
        var sawBrowseResponse = false
        var result = ""
        var numberReturned = 0
        var totalMatches = 0
        var updateID: String?
        var errorCode: Int?
        var errorDescription: String?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            if localName(elementName) == "BrowseResponse" { sawBrowseResponse = true }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            text += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch localName(elementName) {
            case "Result": result = text
            case "NumberReturned": numberReturned = Int(text.trimmingCharacters(in: .whitespaces)) ?? 0
            case "TotalMatches": totalMatches = Int(text.trimmingCharacters(in: .whitespaces)) ?? 0
            case "UpdateID": updateID = text.trimmingCharacters(in: .whitespaces)
            case "errorCode": errorCode = Int(text.trimmingCharacters(in: .whitespaces))
            case "errorDescription": errorDescription = text.trimmingCharacters(in: .whitespacesAndNewlines)
            default: break
            }
            text = ""
        }
    }
}

// MARK: DIDL-Lite

public struct DIDLResource: Equatable, Sendable {
    public var url: String
    public var protocolInfo: String
    public var size: Int64?

    /// The content type: the third field of `protocolInfo` ("http-get:*:video/x-matroska:...").
    public var mimeType: String? {
        let parts = protocolInfo.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3, !parts[2].isEmpty, parts[2] != "*" else { return nil }
        return String(parts[2])
    }
}

public struct DIDLObject: Equatable, Sendable {
    public var id: String
    public var parentID: String
    public var isContainer: Bool
    public var title: String
    public var upnpClass: String
    public var date: String?
    public var childCount: Int?
    public var resources: [DIDLResource]
}

enum DIDLParser {
    static func parse(_ didl: String) throws -> [DIDLObject] {
        if didl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        let delegate = DIDLDelegate()
        let parser = XMLParser(data: Data(didl.utf8))
        parser.delegate = delegate
        guard parser.parse() else { throw SourceError.malformedResponse }
        return delegate.objects
    }

    static func parseDate(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = format
            if let date = f.date(from: text) { return date }
        }
        return nil
    }

    private final class DIDLDelegate: NSObject, XMLParserDelegate {
        var objects: [DIDLObject] = []
        private var current: DIDLObject?
        private var text = ""
        private var resProtocol = ""
        private var resSize: Int64?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            let name = localName(elementName)
            text = ""
            switch name {
            case "container", "item":
                current = DIDLObject(
                    id: attributeDict["id"] ?? "", parentID: attributeDict["parentID"] ?? "",
                    isContainer: name == "container", title: "", upnpClass: "", date: nil,
                    childCount: attributeDict["childCount"].flatMap { Int($0) }, resources: []
                )
            case "res":
                resProtocol = attributeDict["protocolInfo"] ?? ""
                resSize = attributeDict["size"].flatMap { Int64($0) }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let name = localName(elementName)
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "title": current?.title = value
            case "class": current?.upnpClass = value
            case "date": current?.date = value
            case "res":
                if current != nil, !value.isEmpty {
                    current?.resources.append(DIDLResource(url: value, protocolInfo: resProtocol, size: resSize))
                }
            case "container", "item":
                if let done = current { objects.append(done) }
                current = nil
            default: break
            }
            text = ""
        }
    }
}
