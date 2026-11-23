import Foundation
import UserData

// R458 (Settings > Library and the source pages; PROVISIONAL): the rules behind Hide, Edit, Forget, Speed Test, Refresh
// Metadata and Last Scan. The screens and the app's services only call these.

/// Hide: a hidden source stays connected and scanned, but its titles are left out of every list (the library's one
/// restriction rule, `LibraryRestrictions`). The flag is an option of the source's own definition, so it travels with it.
public enum HideSourceOption {
    public static let key = "hidden"
    public static let title = "Hide Source"
    public static let footer = "A hidden source stays connected, but its titles are not shown. Titles that exist in another source stay."

    public static func isHidden(_ definition: UDSourceDefinition) -> Bool {
        SourceOptions.parse(definition.options)[key] == "1"
    }

    public static func hiddenIDs(_ definitions: [UDSourceDefinition]) -> Set<String> {
        Set(definitions.filter(isHidden).map(\.id))
    }

    public static func setting(_ hidden: Bool, on definition: UDSourceDefinition) -> UDSourceDefinition {
        var options = SourceOptions.parse(definition.options)
        options[key] = hidden ? "1" : nil
        var d = definition
        d.options = SourceOptions.format(options)
        return d
    }
}

/// Edit: the source's name. The address and the password stay as they are (a new address is a new source).
public enum SourceRename {
    /// The name with its ends trimmed; nil when nothing is left (the old name stays).
    public static func cleaned(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    public static func setting(_ text: String, on definition: UDSourceDefinition) -> UDSourceDefinition {
        guard let name = cleaned(text) else { return definition }
        var d = definition
        d.name = name
        return d
    }
}

/// Forget: what the confirmation names, so the person sees what goes and what stays.
public enum ForgetSourceText {
    public static func message(name: String) -> String {
        "“\(name)” and its titles are removed from this library, and its saved password is deleted. The files on the server are not touched."
    }
}

/// Speed Test: reads one bounded range of one file of the source and says how fast it came. Read-only.
public enum SpeedTest {
    /// 8 MB.
    public static let rangeBytes: Int64 = 8 * 1024 * 1024

    public static func megabitsPerSecond(bytes: Int64, seconds: Double) -> Double? {
        guard bytes > 0, seconds > 0 else { return nil }
        return Double(bytes) * 8 / seconds / 1_000_000
    }

    public static func text(_ mbps: Double?) -> String {
        guard let mbps else { return "No result" }
        return mbps >= 100 ? String(format: "%.0f Mbps", mbps) : String(format: "%.1f Mbps", mbps)
    }

    /// The read range for a file of `size` bytes: the first 8 MB, or all of a smaller file.
    public static func range(fileSize: Int64?) -> Range<Int64>? {
        guard let size = fileSize, size > 0 else { return nil }
        return 0..<min(size, rangeBytes)
    }

    public static let footer = "Reads 8 MB of one video file. Nothing is saved or changed."
}

/// Refresh Metadata: the online answers kept for the titles are fetched again the next time each is shown. Edits and choices
/// of the person live in the user data and are never part of the cache, so they stay.
public enum MetadataRefresh {
    public static let confirmTitle = "Refresh Metadata?"
    public static let message = "Online descriptions and picture lists are fetched again. Your own edits and choices stay."
    public static let needsKeyLine = "Refreshing needs Online Lookup. Turn it on under Metadata and Artwork."

    /// The cache key prefixes of the given online ids (a film and a show share the id space only by number, so both kinds).
    public static func prefixes(tmdbIDs: Set<Int>) -> [String] {
        tmdbIDs.sorted().flatMap { ["tmdb/movie/\($0)/", "tmdb/tv/\($0)/"] }
    }
}

/// Last Scan: "Today at 9:41 AM" as the system formats it, or "Never".
public enum LastScan {
    public static let key = "vp.lastScan"
    public static let never = "Never"

    public static func text(_ date: Date?, now: Date = Date(), locale: Locale = .current, calendar: Calendar = .current) -> String {
        guard let date else { return never }
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        let sameDay = calendar.isDate(date, inSameDayAs: now)
        f.dateStyle = sameDay ? .none : .medium
        f.timeStyle = .short
        return (sameDay ? "Today, " : "") + f.string(from: date)
    }
}
