import Foundation
import AppLogic

/// R311: the last playback that failed, kept on this Apple TV for Settings > Playback > Last Playback Problem (the owner reads
/// it without a Mac). One value in the app's defaults, replaced by each new problem; the text has every token removed
/// before it gets here (`PlaybackStartTracker.problem`). Never synced and never part of a backup.
enum PlaybackProblemLog {
    static func save(_ problem: PlaybackProblem, defaults: UserDefaults = .standard) {
        guard let data = problem.encoded() else { return }
        defaults.set(data, forKey: PlaybackProblem.storageKey)
    }

    static func load(defaults: UserDefaults = .standard) -> PlaybackProblem? {
        PlaybackProblem.decoded(defaults.data(forKey: PlaybackProblem.storageKey))
    }
}
