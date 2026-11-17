import Foundation
import LibraryIndex
import PlaybackLogic

// Feeds the Up Next proposal from the library (docs/SEGMENTS.md, "Next episode feed").
//
// `NextEpisodeMachine` never sees the library; it takes a `NextEpisodeDecision`. This file turns library rows into
// `EpisodeRef`s, asks `LibraryNextEpisodeProvider` (rules R36/R49/R54 are in `EpisodeOrder`), and gathers the text the proposal shows,
// so the player layer gets one value to hand to `PlayerSessionFactory`.

public enum NextEpisodeFeed {
    /// What the player layer needs about "what comes next".
    public struct Outcome: Equatable, Sendable {
        /// The current item as an episode reference, nil when it is not an episode (a film, or a file without series data).
        public var current: EpisodeRef?
        public var decision: NextEpisodeDecision
        /// The next episode as the library knows it, for the proposal text and for opening it.
        public var nextItem: NextItemInfo?

        public var describer: PreloadedEpisodeDescriber {
            var table: [EpisodeRef: EpisodeDescription] = [:]
            if case .next(let ref) = decision, let info = nextItem { table[ref] = EpisodeDescription(title: info.title, previewKey: info.artworkKey) }
            return PreloadedEpisodeDescriber(table)
        }

        public static let notAnEpisode = Outcome(current: nil, decision: .none(.notAnEpisode), nextItem: nil)
    }

    public struct NextItemInfo: Equatable, Sendable {
        public var itemID: Int64
        public var title: String?
        public var artworkKey: String
    }

    /// The reference the next-episode rules work on. The file id is the library item id as text, so `libraryItemID(for:)` gets it back.
    /// Nil for films and for items without a series, season or episode number.
    public static func ref(for item: LibraryItem) -> EpisodeRef? {
        guard item.kind == .episode, let series = item.seriesID, let season = item.season, let episode = item.episode else { return nil }
        let last = item.episodeEnd.flatMap { $0 > episode ? $0 : nil }
        return EpisodeRef(seriesID: String(series), season: season, episode: episode, lastEpisode: last, fileID: String(item.id))
    }

    /// The library item a reference opens (the inverse of `ref(for:)`).
    public static func libraryItemID(for ref: EpisodeRef) -> Int64? { Int64(ref.fileID) }

    /// Looks the next episode up. Never throws: a library that cannot be read gives "no next episode".
    public static func resolve(itemID: Int64, store: any LibraryStore) async -> Outcome {
        guard let item = try? await store.item(id: itemID), let current = ref(for: item) else { return .notAnEpisode }
        let provider = LibraryNextEpisodeProvider { seriesText in
            guard let seriesID = Int64(seriesText), let items = try? await store.episodes(ofSeries: seriesID) else { return [] }
            return items.compactMap { ref(for: $0) }
        }
        let decision = await provider.nextEpisode(after: current)
        guard case .next(let next) = decision, let nextID = libraryItemID(for: next), let nextItem = try? await store.item(id: nextID) else {
            return Outcome(current: current, decision: decision, nextItem: nil)
        }
        let title = nextItem.title.trimmingCharacters(in: .whitespaces)
        return Outcome(current: current, decision: decision,
                      nextItem: NextItemInfo(itemID: nextID, title: title.isEmpty ? nil : title, artworkKey: CardBuilder.card(nextItem).artworkKey))
    }
}

/// An `EpisodeDescribing` over text that was loaded before playback (the proposal is built synchronously).
public struct PreloadedEpisodeDescriber: EpisodeDescribing {
    private let table: [EpisodeRef: EpisodeDescription]
    public init(_ table: [EpisodeRef: EpisodeDescription] = [:]) { self.table = table }
    public func describe(_ ref: EpisodeRef) -> EpisodeDescription { table[ref] ?? EpisodeDescription(title: nil) }
}

/// Builds the player's skip and Up Next state from segments and the next-episode decision.
public enum PlayerSessionFactory {
    /// Settings > Playback > Show Skip Buttons is one switch for the three kinds. On: each kind is Ask (the default of B9).
    /// Off: each kind is Off (no button, no jump). PROVISIONAL: the per-kind Ask / Automatic / Off settings of B9 have no
    /// Settings rows yet; `SkipSettings` supports them, so the rows only need to build one.
    public static func skipSettings(showSkipButtons: Bool) -> SkipSettings {
        showSkipButtons ? SkipSettings() : SkipSettings(recap: .off, intro: .off, credits: .off)
    }

    /// The Next Episode settings the old toggle "Play Next Episode Automatically" stands for: on is When Credits Begin (the default),
    /// off is Ask (NES-M, docs/PLAYBACK_LOGIC.md "Differences", item 1).
    public static func nextEpisodeSettings(autoPlay: Bool, countdownSeconds: Int = NextEpisodeSettings.defaultCountdownSeconds) -> NextEpisodeSettings {
        NextEpisodeSettings(mode: autoPlay ? .whenCreditsBegin : .ask, countdownSeconds: countdownSeconds)
    }

    /// Segments that were already merged (`SegmentService`) go in as they are; they are not validated a second time.
    public static func session(segments: [SkipSegment], duration: TimeInterval, skip: SkipSettings, nextEpisode: NextEpisodeSettings,
                               next: NextEpisodeDecision, clock: any PlaybackClock, dismissedBefore: Bool = false) -> PlaybackSession {
        PlaybackSession(resolved: ResolvedSegments(merged: segments), duration: duration, settings: skip, next: next,
                        policy: NextEpisodePolicy(settings: nextEpisode), clock: clock, dismissedBefore: dismissedBefore)
    }

    /// The controller the coordinator feeds with playhead updates. Presenters are the platform's (skip button, Up Next card).
    public static func controller(segments: [SkipSegment], duration: TimeInterval, skip: SkipSettings, nextEpisode: NextEpisodeSettings,
                                  feed: NextEpisodeFeed.Outcome, clock: any PlaybackClock, upNextPresenter: any UpNextProposalPresenting,
                                  skipPresenter: (any SkipButtonPresenting)?, sink: @escaping @Sendable ([PlayerOverlayEffect]) -> Void) -> PlayerOverlayController {
        let session = session(segments: segments, duration: duration, skip: skip, nextEpisode: nextEpisode, next: feed.decision, clock: clock)
        return PlayerOverlayController(session: session, clock: clock, upNextPresenter: upNextPresenter, skipPresenter: skipPresenter,
                                       describer: feed.describer, sink: sink)
    }
}
