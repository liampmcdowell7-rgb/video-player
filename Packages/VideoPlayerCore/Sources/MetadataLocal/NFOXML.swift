import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A tolerant element tree for `.nfo` files. Names and attribute keys are lowercased.
final class NFOElement {
    let name: String
    var attributes: [String: String]
    var text = ""
    var children: [NFOElement] = []

    init(name: String, attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
    }

    func first(_ n: String) -> NFOElement? { children.first { $0.name == n } }
    func all(_ n: String) -> [NFOElement] { children.filter { $0.name == n } }

    var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Trimmed text of the first child with this name, nil when absent or empty.
    func string(_ n: String) -> String? {
        guard let value = first(n)?.trimmed, !value.isEmpty else { return nil }
        return value
    }

    /// Trimmed non-empty texts of every child with this name.
    func strings(_ n: String) -> [String] {
        all(n).map(\.trimmed).filter { !$0.isEmpty }
    }
}

private final class NFOTreeBuilder: NSObject, XMLParserDelegate {
    let root = NFOElement(name: "#root")
    private var stack: [NFOElement] = []

    override init() {
        super.init()
        stack = [root]
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        var attributes: [String: String] = [:]
        for (key, value) in attributeDict { attributes[key.lowercased()] = value }
        let element = NFOElement(name: elementName.lowercased(), attributes: attributes)
        stack.last?.children.append(element)
        stack.append(element)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if stack.count > 1 { stack.removeLast() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        stack.last?.text += String(decoding: CDATABlock, as: UTF8.self)
    }
}

enum NFOXML {
    /// Turns raw file bytes into text: handles UTF-8 and UTF-16 byte order marks, UTF-16 without a mark,
    /// and falls back to Windows-1252 then Latin-1 when the bytes are not valid UTF-8.
    static func decode(_ data: Data) -> String {
        let bytes = [UInt8](data)
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            return String(decoding: bytes.dropFirst(3), as: UTF8.self)
        }
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE {
            return String(data: Data(bytes.dropFirst(2)), encoding: .utf16LittleEndian) ?? ""
        }
        if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF {
            return String(data: Data(bytes.dropFirst(2)), encoding: .utf16BigEndian) ?? ""
        }
        if bytes.count >= 4, bytes[0] == 0x3C, bytes[1] == 0x00, bytes[3] == 0x00 {
            return String(data: data, encoding: .utf16LittleEndian) ?? ""
        }
        if bytes.count >= 4, bytes[0] == 0x00, bytes[1] == 0x3C, bytes[2] == 0x00 {
            return String(data: data, encoding: .utf16BigEndian) ?? ""
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .windowsCP1252) { return text }
        return String(data: data, encoding: .isoLatin1) ?? String(decoding: bytes, as: UTF8.self)
    }

    private static let htmlEntities: [String: Int] = [
        "nbsp": 160, "copy": 169, "reg": 174, "laquo": 171, "raquo": 187, "ndash": 8211, "mdash": 8212,
        "lsquo": 8216, "rsquo": 8217, "ldquo": 8220, "rdquo": 8221, "hellip": 8230, "bull": 8226, "trade": 8482,
        "eacute": 233, "egrave": 232, "ecirc": 234, "euml": 235, "aacute": 225, "agrave": 224, "acirc": 226,
        "auml": 228, "aring": 229, "atilde": 227, "ccedil": 231, "iacute": 237, "igrave": 236, "icirc": 238,
        "iuml": 239, "ntilde": 241, "oacute": 243, "ograve": 242, "ocirc": 244, "ouml": 246, "otilde": 245,
        "uacute": 250, "ugrave": 249, "ucirc": 251, "uuml": 252, "yacute": 253, "szlig": 223, "oslash": 248,
        "Eacute": 201, "Agrave": 192, "Aacute": 193, "Auml": 196, "Ouml": 214, "Uuml": 220, "Ntilde": 209,
        "Ccedil": 199, "deg": 176, "middot": 183, "times": 215, "euro": 8364, "pound": 163, "yen": 165,
        "cent": 162, "sect": 167, "para": 182, "frac12": 189, "iexcl": 161, "iquest": 191,
    ]
    private static let xmlEntities: Set<String> = ["amp", "lt", "gt", "quot", "apos"]

    private static let entityRegex = try? NSRegularExpression(pattern: "&([A-Za-z][A-Za-z0-9]*);")
    private static let bareAmpersand = try? NSRegularExpression(pattern: "&(?!(?:amp|lt|gt|quot|apos|#[0-9]+|#[xX][0-9a-fA-F]+);)")
    private static let xmlDeclaration = try? NSRegularExpression(pattern: "<\\?xml[^>]*\\?>", options: [.caseInsensitive])
    private static let doctype = try? NSRegularExpression(pattern: "<!DOCTYPE[^>]*>", options: [.caseInsensitive])

    /// Makes text safe for XMLParser: removes the XML declaration and DOCTYPE, drops characters XML forbids,
    /// turns HTML named entities into numeric ones, and escapes ampersands that start no entity.
    static func sanitize(_ input: String) -> String {
        var text = input
        for regex in [xmlDeclaration, doctype] {
            guard let regex else { continue }
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        text = String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            let v = scalar.value
            if v == 0x09 || v == 0x0A || v == 0x0D { return true }
            if v < 0x20 || v == 0xFFFE || v == 0xFFFF { return false }
            return true
        }))
        if let regex = entityRegex {
            let ns = text as NSString
            var out = ""
            var last = 0
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                let name = ns.substring(with: match.range(at: 1))
                if xmlEntities.contains(name) {
                    out += "&\(name);"
                } else if let code = htmlEntities[name] {
                    out += "&#\(code);"
                } else {
                    out += "&amp;\(name);"
                }
                last = match.range.location + match.range.length
            }
            out += ns.substring(from: last)
            text = out
        }
        if let regex = bareAmpersand {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "&amp;")
        }
        return text
    }

    /// Parses possibly broken XML into a tree under a synthetic root. A file with several top-level
    /// elements (multi-episode nfo) is fine. When the XML is malformed the elements read so far are kept.
    static func tree(from text: String) -> (root: NFOElement, wellFormed: Bool) {
        let clean = sanitize(text)
        let builder = NFOTreeBuilder()
        let wrapped = "<nfo-wrapper>" + clean + "</nfo-wrapper>"
        let parser = XMLParser(data: Data(wrapped.utf8))
        parser.delegate = builder
        let ok = parser.parse()
        // The wrapper is the only child of the synthetic root.
        let wrapper = builder.root.children.first ?? builder.root
        return (wrapper, ok)
    }

    /// Decodes HTML entities (named and numeric) in already-parsed text.
    static func decodeEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        var text = input
        let named: [(String, String)] = [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'")]
        if let regex = try? NSRegularExpression(pattern: "&(#[0-9]+|#[xX][0-9a-fA-F]+|[A-Za-z][A-Za-z0-9]*);") {
            let ns = text as NSString
            var out = ""
            var last = 0
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                let body = ns.substring(with: match.range(at: 1))
                var replacement: String?
                if body.hasPrefix("#x") || body.hasPrefix("#X") {
                    if let v = UInt32(body.dropFirst(2), radix: 16), let s = Unicode.Scalar(v) { replacement = String(Character(s)) }
                } else if body.hasPrefix("#") {
                    if let v = UInt32(body.dropFirst()), let s = Unicode.Scalar(v) { replacement = String(Character(s)) }
                } else if let pair = named.first(where: { $0.0 == "&\(body);" }) {
                    replacement = pair.1
                } else if body == "amp" {
                    replacement = "&"
                } else if let code = htmlEntities[body], let s = Unicode.Scalar(UInt32(code)) {
                    replacement = String(Character(s))
                }
                out += replacement ?? ns.substring(with: match.range)
                last = match.range.location + match.range.length
            }
            out += ns.substring(from: last)
            text = out
        }
        return text
    }

    /// Plain text from a plot or outline that may contain HTML line breaks, tags and entities.
    static func plainText(_ input: String) -> String {
        var text = decodeEntities(input)
        let breaks: [(String, String)] = [
            ("<br\\s*/?>", "\n"), ("</p\\s*>", "\n\n"), ("</div\\s*>", "\n"), ("<li[^>]*>", "\n- "),
        ]
        for (pattern, replacement) in breaks {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
            }
        }
        if let tag = try? NSRegularExpression(pattern: "</?[A-Za-z][A-Za-z0-9]*(?:\\s[^<>]*)?/?>") {
            text = tag.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        if let blank = try? NSRegularExpression(pattern: "\\n{3,}") {
            text = blank.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\n\n")
        }
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
