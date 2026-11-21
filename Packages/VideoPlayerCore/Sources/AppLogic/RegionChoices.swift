import Foundation

/// One answer of Settings > Online Lookup's Region picker.
public struct RegionOption: Identifiable, Equatable, Sendable {
    /// The ISO 3166-1 alpha-2 code that is stored and matched ("US", "DE").
    public let code: String
    /// What the picker shows: the country's name in the device language, or the code when the system has no name.
    public let title: String
    public var id: String { code }

    public init(code: String, title: String) {
        self.code = code
        self.title = title
    }
}

/// R334 (PROVISIONAL): Region is a system `Picker`, not a typed field. The app only uses the region to pick one entry of
/// TMDB's answers, which are keyed by `iso_3166_1` (where to watch: TMDBDiscover; age ratings: TMDBMapper), and
/// `OnlineLookupPrefs.normalizedRegion` accepts only two letters A to Z. So Region has a fixed list of answers: the ISO 3166-1
/// alpha-2 country codes. The app passes the system's list (`Locale.Region.isoRegions(ofCategory: .territory)`, tvOS 26.0+)
/// and the system's names (`Locale.localizedString(forRegionCode:)`); this pure part is tested on Linux.
public enum RegionChoices {
    /// The picker's answers: every two-letter code once, sorted by name; the current region is always one of them, so a
    /// stored code the system list lacks is still shown and kept.
    public static func options(codes: [String], current: String, name: (String) -> String?) -> [RegionOption] {
        var seen: Set<String> = []
        var out: [RegionOption] = []
        let selected: String = OnlineLookupPrefs.normalizedRegion(current)
        for raw in codes + [selected] {
            let code: String = raw.uppercased()
            guard isCountryCode(code), !seen.contains(code) else { continue }
            seen.insert(code)
            let title: String = name(code).flatMap { $0.isEmpty ? nil : $0 } ?? code
            out.append(RegionOption(code: code, title: title))
        }
        return out.sorted { (a: RegionOption, b: RegionOption) -> Bool in
            let order: ComparisonResult = a.title.localizedStandardCompare(b.title)
            return order == .orderedSame ? a.code < b.code : order == .orderedAscending
        }
    }

    /// Two letters A to Z: an ISO 3166-1 alpha-2 code, not a UN M.49 number such as "001" or "150".
    public static func isCountryCode(_ code: String) -> Bool {
        code.count == 2 && code.unicodeScalars.allSatisfy { $0.value >= 65 && $0.value <= 90 }
    }
}
