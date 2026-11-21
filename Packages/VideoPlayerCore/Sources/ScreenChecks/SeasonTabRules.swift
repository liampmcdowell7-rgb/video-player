import Foundation

/// R339 (owner decision of 21 Nov 2026, docs/HIG_AUDIT.md T10): the show page lists the episodes of ONE season, the one its
/// season tab shows. Before R339 every season had its own shelf.
public extension ScreenRules {
    /// The seasons whose episode cards are on screen, from the cards' labels ("S2 E3, Title"). Passes when there is exactly one.
    static func oneSeasonListed(cardLabels: [String]) -> CheckResult {
        var seasons: [String] = []
        for label in cardLabels {
            guard let code = label.split(separator: ",").first, code.hasPrefix("S"),
                  let space = code.firstIndex(of: " "), code[code.index(after: space)...].hasPrefix("E") else { continue }
            let season = String(code[..<space])
            if !seasons.contains(season) { seasons.append(season) }
        }
        let lines: [String] = ["seasons with episode cards: " + (seasons.isEmpty ? "none" : seasons.joined(separator: ", ")),
                               seasons.count == 1 ? "ONE SEASON OK" : "NOT ONE SEASON: the season tabs should list one season's episodes (R339)"]
        return CheckResult(passed: seasons.count == 1, lines: lines)
    }
}
