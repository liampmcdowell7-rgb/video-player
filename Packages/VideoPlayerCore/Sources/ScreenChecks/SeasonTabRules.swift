import Foundation

/// R339 (owner decision of 21 Nov 2026, docs/HIG_AUDIT.md T10): the show page lists the episodes of ONE season, the one its
/// season tab shows. Before R339 every season had its own shelf.
public extension ScreenRules {
    /// The seasons whose episode cards are on screen, from the cards' labels ("S2, E3, Title" since R358; "S2 E3, Title" in
    /// older runs). Passes when there is exactly one.
    static func oneSeasonListed(cardLabels: [String]) -> CheckResult {
        var seasons: [String] = []
        for label in cardLabels {
            guard let season = episodeCardSeason(label) else { continue }
            if !seasons.contains(season) { seasons.append(season) }
        }
        let lines: [String] = ["seasons with episode cards: " + (seasons.isEmpty ? "none" : seasons.joined(separator: ", ")),
                               seasons.count == 1 ? "ONE SEASON OK" : "NOT ONE SEASON: the season tabs should list one season's episodes (R339)"]
        return CheckResult(passed: seasons.count == 1, lines: lines)
    }

    /// R358: the season ("S2") of an episode card's label, "S2, E3, Title" or the older "S2 E3, Title"; nil for any other
    /// label.
    static func episodeCardSeason(_ label: String) -> String? {
        guard let match = episodeCardPattern.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              let range = Range(match.range(at: 1), in: label) else { return nil }
        return String(label[range])
    }

    /// R358: an episode card's label starts with its code, in the app's form ("S2, E3, ", "S1, E1–E2, ") or the older one
    /// ("S2 E3, ", "S1 E1-E2, ").
    static let episodeCardPattern: NSRegularExpression = try! NSRegularExpression(pattern: "^(S[0-9]+),? E[0-9]+(?:[-\u{2013}]E[0-9]+)?, ")
}
