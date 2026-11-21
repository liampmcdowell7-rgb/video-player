import Foundation
import LibraryIndex
import PlaybackLogic

// R340 (owner decision of 21 Nov 2026 in R338, docs/HIG_AUDIT.md T15 to T19): what the player's info panel and the system
// Up Next card show. The app side is App/Features/Player (PlayerInfoPanels.swift, UpNextProposalController.swift).

/// The Episodes tab of the player's info panel: the episodes of the season that is playing, as the show page lists them.
public enum PlayerEpisodes {
    public struct Content: Equatable, Sendable {
        public var season: SeasonSection
        /// The episode playing now (its card says so and does nothing when chosen).
        public var currentID: Int64
        /// R313: each episode's "S1, E3" (the player's form, `PlayerEpisodeText.code`), by episode id.
        public var codes: [Int64: String] = [:]

        /// The card caption: "S1, E3 · Name", or the name alone when no number is known.
        public func caption(for row: EpisodeRow) -> String {
            guard let code = codes[row.id], !code.isEmpty else { return row.title }
            return code + " · " + row.title
        }
    }

    /// Nil for a film or an item without a series and season (no Episodes tab then). Never throws.
    public static func load(itemID: Int64, store: any LibraryStore) async -> Content? {
        guard let item = try? await store.item(id: itemID), item.kind == .episode, let seriesID = item.seriesID,
              let episodes = try? await store.episodes(ofSeries: seriesID), !episodes.isEmpty else { return nil }
        let season = item.season ?? 1
        guard let section = SeasonsViewModel.content(episodes).seasons.first(where: { $0.season == season }) else { return nil }
        var codes: [Int64: String] = [:]
        for episode in episodes {
            if let code = PlayerEpisodeText.code(season: episode.season, episode: episode.episode, episodeEnd: episode.episodeEnd) {
                codes[episode.id] = code
            }
        }
        return Content(season: section, currentID: itemID, codes: codes)
    }

    /// "Now Playing", the second line of the current episode's card.
    public static let nowPlaying = "Now Playing"
    /// The tab's title (the system uses the view controller's title as the tab name).
    public static let tabTitle = "Episodes"
}

/// The system Up Next (`AVContentProposal`). Apple, `automaticAcceptanceInterval`: "The interval between the time playback
/// ends and automatic acceptance of this content proposal. The content proposal displays a countdown timer to reflect this
/// value. Set this value to nan to disable"; Apple's article "Presenting content proposals in tvOS" sets it to -1.0 (before
/// the end). The playback logic runs in Ask mode (it presents the card and waits); the countdown is the system's.
public enum UpNextCard {
    /// Seconds between the card appearing and the next episode starting by itself (Settings > Playback > Auto-Play Next
    /// Episode on). The same 10 s as before (`NextEpisodeSettings.defaultCountdownSeconds`).
    public static let countdownSeconds = NextEpisodeSettings.defaultCountdownSeconds

    /// The proposal's `automaticAcceptanceInterval` so that acceptance comes `countdownSeconds` after the card appears at
    /// `position`: negative when more than that remains of the file (the credits), NaN when Auto-Play is off.
    public static func acceptanceInterval(autoPlay: Bool, position: TimeInterval, duration: TimeInterval?,
                                          countdownSeconds: Int = countdownSeconds) -> TimeInterval {
        guard autoPlay else { return .nan }
        guard let duration, duration.isFinite, duration > 0, position.isFinite else { return TimeInterval(countdownSeconds) }
        return TimeInterval(countdownSeconds) - max(0, duration - position)
    }

    /// Whole seconds until the system accepts, read from the playhead (so a pause stops it), or nil when nothing is armed.
    public static func remaining(position: TimeInterval, duration: TimeInterval?, interval: TimeInterval) -> Int? {
        guard interval.isFinite, let duration, duration.isFinite, position.isFinite else { return nil }
        return max(0, Int((duration - position + interval).rounded(.up)))
    }

    /// "Playing in 7 seconds", nil at zero or with no countdown.
    public static func countdownText(_ seconds: Int?) -> String? {
        guard let seconds, seconds >= 1 else { return nil }
        return "Playing in \(DisplayText.seconds(seconds))"
    }

    public static let heading = "Up Next"
    public static let playNow = "Play Now"
    public static let cancel = "Cancel"
}

public extension PlayerSessionFactory {
    /// R340: with the system Up Next the playback logic never counts down itself: Ask mode presents the card at the credits
    /// start (or the end) and waits; the system's `automaticAcceptanceInterval` starts the next episode (Auto-Play on) and
    /// the delegate's accept reaches the logic as `.accept`.
    static func systemUpNextSettings() -> NextEpisodeSettings { NextEpisodeSettings(mode: .ask) }
}
