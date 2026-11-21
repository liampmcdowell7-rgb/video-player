import Foundation

/// R337 (PROVISIONAL, docs/HIG_AUDIT.md T11): the Search tab's suggestions under the system search field. HIG Searching:
/// "display a person's recent searches before they start typing or offer predictive search suggestions"
/// (`searchSuggestions(_:)`). Presentation only: the suggestions are the titles the library search ALREADY found for what is
/// typed; nothing is requested or stored. Choosing one puts the whole title in the field, which runs the same library search.
/// Recent searches need storage and are left to the owner (R338).
public enum SearchSuggestions {
    /// At most `limit` titles, in result order, each once (case-insensitive), without the one that equals the typed text.
    /// Empty when nothing is typed.
    public static func titles(_ titles: [String], query: String, limit: Int = 5) -> [String] {
        let typed: String = query.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty, limit > 0 else { return [] }
        var seen: Set<String> = [typed.lowercased()]
        var out: [String] = []
        for title in titles {
            let key: String = title.lowercased()
            guard !title.isEmpty, seen.insert(key).inserted else { continue }
            out.append(title)
            if out.count == limit { break }
        }
        return out
    }
}
