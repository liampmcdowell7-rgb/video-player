import Foundation
import VideoPlayerCore
#if canImport(FoundationXML)
import FoundationXML
#endif

/// One `<response>` element from a 207 Multi-Status body.
struct PropfindResponse: Equatable {
    var href: String
    var isCollection = false
    var contentLength: Int64?
    var lastModified: Date?
    var contentType: String?
    var displayName: String?
    var etag: String?
}

enum PropfindParser {
    static func parse(_ data: Data) throws -> [PropfindResponse] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.sawMultistatus else { throw SourceError.malformedResponse }
        return delegate.responses
    }

    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "GMT")
            f.dateFormat = format
            if let d = f.date(from: trimmed) { return d }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: trimmed)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var responses: [PropfindResponse] = []
        var sawMultistatus = false

        private var current: PropfindResponse?
        private var pending = PropfindResponse(href: "")
        private var propstatStatus: String?
        private var text = ""
        private var inResourceType = false

        private func local(_ name: String) -> String {
            (name.split(separator: ":").last.map(String.init) ?? name).lowercased()
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            text = ""
            switch local(elementName) {
            case "multistatus": sawMultistatus = true
            case "response": current = PropfindResponse(href: "")
            case "propstat": pending = PropfindResponse(href: ""); propstatStatus = nil
            case "resourcetype": inResourceType = true
            case "collection": if inResourceType { pending.isCollection = true }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch local(elementName) {
            case "href": if current != nil, current?.href.isEmpty == true { current?.href = value }
            case "resourcetype": inResourceType = false
            case "getcontentlength": pending.contentLength = Int64(value)
            case "getlastmodified": pending.lastModified = PropfindParser.parseDate(value)
            case "getcontenttype": if !value.isEmpty { pending.contentType = value }
            case "displayname": if !value.isEmpty { pending.displayName = value }
            case "getetag": if !value.isEmpty { pending.etag = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            case "status": propstatStatus = value
            case "propstat":
                let ok = propstatStatus.map { $0.contains(" 200") } ?? true
                if ok, var c = current {
                    if pending.isCollection { c.isCollection = true }
                    c.contentLength = pending.contentLength ?? c.contentLength
                    c.lastModified = pending.lastModified ?? c.lastModified
                    c.contentType = pending.contentType ?? c.contentType
                    c.displayName = pending.displayName ?? c.displayName
                    c.etag = pending.etag ?? c.etag
                    current = c
                }
            case "response":
                if let c = current, !c.href.isEmpty { responses.append(c) }
                current = nil
            default: break
            }
            text = ""
        }
    }
}
