import Foundation
import UIKit
import PlaybackLogic
import AppLogic

/// What the player coordinator calls to turn segment data into the skip button, the Up Next card and the Mark menu
/// (docs/SEGMENTS.md "How the player uses it"). Nothing here starts playback; the coordinator keeps every decision about the player.
@MainActor
enum SegmentsWiring {

    /// Builds the overlay controller for one playback. Returns nil when the length of the file is not known yet: skip ranges and the
    /// credits start cannot be checked without it. Call again when the length is known, and after marks changed (`onMarksChanged`).
    ///
    /// - Parameters:
    ///   - segments: `ResolvedPlayback.segments`, from `SegmentService.segments(forItem:)`.
    ///   - sink: receives the effects of the overlay on the playback thread. Hop to the main actor inside it.
    static func makeOverlay(itemID: Int64, segments: [Segment], duration: TimeInterval?, services: AppServices,
                            upNextPresenter: any UpNextProposalPresenting, skipPresenter: any SkipButtonPresenting,
                            sink: @escaping @Sendable ([PlayerOverlayEffect]) -> Void) async -> PlayerOverlayController? {
        guard let duration, duration > 0, duration.isFinite else { return nil }
        let feed = await NextEpisodeFeed.resolve(itemID: itemID, store: services.store)
        return PlayerSessionFactory.controller(
            segments: segments, duration: duration,
            // R314: Skip Intros / Skip Credits Automatically; an automatic skip offers "Watch Intro" for 5 s.
            skip: PlayerSessionFactory.skipSettings(showSkipButtons: flag(.showSkipButtons), skipIntros: flag(.skipIntrosAutomatically),
                                                    skipCredits: flag(.skipCreditsAutomatically)),
            // R340: the logic presents and waits; the system's Up Next counts down (ProposalPresenter).
            nextEpisode: PlayerSessionFactory.systemUpNextSettings(),
            feed: feed, clock: MonotonicClock(), upNextPresenter: upNextPresenter, skipPresenter: skipPresenter, sink: sink)
    }

    /// The library item to play for an `.advance` effect, nil when the reference is not one of ours.
    static func itemID(for effect: PlayerOverlayEffect) -> Int64? {
        if case .advance(let ref) = effect { return NextEpisodeFeed.libraryItemID(for: ref) }
        return nil
    }

    /// The mark controller for this playback. `playhead` and `length` are read when a mark is made.
    static func makeMarkController(itemID: Int64, services: AppServices, playhead: @escaping () -> TimeInterval?,
                                   length: @escaping () -> TimeInterval?) -> PlayerMarkController {
        PlayerMarkController(itemID: itemID, services: services, playhead: playhead, length: length)
    }

    /// The entry for `AVPlayerViewController.transportBarCustomMenuItems`; build it again in `onMenuChanged`.
    static func markMenuItems(for controller: PlayerMarkController) -> [UIMenuElement] {
        [PlayerMarkMenu.menu(for: controller)]
    }

    /// Settings > Playback > Auto-Play Next Episode (on by default): the system Up Next accepts by itself.
    static var autoPlayNextEpisode: Bool { flag(.autoPlayNextEpisode) }

    private static func flag(_ key: SettingsKey) -> Bool {
        UserDefaults.standard.object(forKey: key.rawValue) as? Bool ?? key.defaultBool
    }
}
