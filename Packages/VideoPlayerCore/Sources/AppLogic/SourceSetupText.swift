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

    /// #25 B1 (OPEN_QUESTIONS R202): the ONE short line under a type's name in the Add a Source list. Short enough to show in
    /// full in the sheet at every text size (it scales, rule S1). What was tested and why a type is not available are on the
    /// Learn More page (`learnMore`), one press away, so nothing is hidden.
    public static func rowLine(_ kind: SourceKind) -> String {
        switch kind {
        case .webdav: return "Web folder, as on a NAS"
        case .smb: return "Shared folder"
        case .nfs: return "Exported folder"
        case .sftp: return "Folder over SSH"
        case .ftp: return "Folder on an FTP server"
        case .upnp: return "Media server on your network"
        case .jellyfin: return "Jellyfin media server"
        case .emby: return "Emby media server"
        case .directLink: return "Link to one video file"
        case .plex: return "Needs a Plex sign-in"
        case .oneDrive: return "Needs an app registration"
        case .dropbox, .googleDrive: return "No sign-in for TVs"
        }
    }

    public static let learnMoreTitle = "About Source Types"

    /// #25 B1: the Learn More page of the Add a Source list: per type, what it is, how it was tested and what was not, or why
    /// it cannot be set up yet. Built from the catalog, so it always matches the forms.
    public static func learnMore(_ catalog: [SourceKindInfo]) -> String {
        catalog.map { info in
            var parts = [info.summary]
            if let note = info.unavailableNote {
                parts.append("Not available yet: " + note)
            } else {
                parts.append(info.statusLine + ".")
                if let caveat = info.caveat { parts.append(caveat) }
            }
            return info.title + "\n" + parts.joined(separator: " ")
        }.joined(separator: "\n\n")
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
