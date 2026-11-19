import Foundation
import VideoPlayerCore

/// Texts of the Add a Source sheet (#15 Part 2, PROVISIONAL, OPEN_QUESTIONS R188).
public enum SourceSetupText {
    public static let listSummary = "Choose how to reach your server. Search Your Network finds servers that announce themselves."

    /// L9: the one badge line of a type row. The full status sentence and any caveat are on the type's form.
    public static func statusBadge(_ kind: SourceKind) -> String {
        switch kind.verification {
        case .notVerified: return "Not verified yet"
        case .contractTestsOnly: return "Recorded replies only"
        case .realServer: return "Tested with a real server"
        case .onDevice: return "Tested on device"
        }
    }

    /// 2.3: a found server's name for one line, and its technical identifier for a second line when the announced name is
    /// a machine identifier ("host-<UUID>-<hex>"). The title is the readable part before the identifier, or "SMB server"
    /// (by kind) when there is none. An ordinary name ("Living Room NAS") is kept whole, with no second line.
    public static func discoveredName(_ raw: String, kindTitle: String) -> (title: String, identifier: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let range = identifierRange(in: trimmed) else {
            return (trimmed.isEmpty ? "\(kindTitle) server" : trimmed, nil)
        }
        let readable = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " -_."))
        return (readable.isEmpty ? "\(kindTitle) server" : readable, trimmed)
    }

    /// Where a UUID (8-4-4-4-12 hex digits) or a run of 12 or more hex digits starts.
    static func identifierRange(in text: String) -> Range<String.Index>? {
        let patterns = ["[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}", "[0-9A-Fa-f]{12,}"]
        return patterns.compactMap { text.range(of: $0, options: .regularExpression) }.min { $0.lowerBound < $1.lowerBound }
    }
}
