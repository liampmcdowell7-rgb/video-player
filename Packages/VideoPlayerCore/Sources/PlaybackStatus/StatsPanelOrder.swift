import Foundation

/// R340 (owner decision of 21 Nov 2026 in R338, docs/HIG_AUDIT.md T15, T16): Playback Stats live in the player's info
/// panel, one swipe away, never over the picture. Every stat stays shown, none collapsed, most important first: what the
/// person sees, then what they hear, then whether playback keeps up, then the technical detail.
public extension StatsOverlay {
    static let panelOrder: [String] = [
        "Resolution", "HDR format", "Frame rate", "Video codec",
        "Audio output", "Audio codec", "Audio channels",
        "Bitrate (live)", "Buffer health", "Network throughput", "Dropped frames", "Decode path",
        "Bitrate (average)", "Profile and level", "Container", "Player",
        "Pixel format", "Color primaries", "Transfer function",
    ]

    /// `rows` in `panelOrder`; a row this list does not name keeps its place after them, so nothing is ever left out.
    static func panelRows(_ rows: [StatRow]) -> [StatRow] {
        let rank: [String: Int] = Dictionary(uniqueKeysWithValues: panelOrder.enumerated().map { ($1, $0) })
        return rows.enumerated()
            .sorted { (rank[$0.element.label] ?? panelOrder.count + $0.offset, $0.offset) < (rank[$1.element.label] ?? panelOrder.count + $1.offset, $1.offset) }
            .map(\.element)
    }
}
