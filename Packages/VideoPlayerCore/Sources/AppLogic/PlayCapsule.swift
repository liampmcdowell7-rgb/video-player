import Foundation

/// R471 item 3 (owner's request R471, Part 2 (d); frames: episode t00s, show t08s and t10s, movie t00s; PROVISIONAL): what
/// the capsule Play button of a product page shows. Partly watched: the play glyph, a mini progress bar and the time left
/// in the short form ("18m"); otherwise the play glyph and "Play". VoiceOver hears "Resume, 18 min left" or "Play".
/// The button's look (light fill when focused, dark material when not) is the system's bordered tvOS button.
public struct PlayCapsule: Equatable, Sendable {
    /// The visible word when there is no progress.
    public var title: String
    /// 0 < progress < 1 when partly watched; nil otherwise.
    public var progress: Double?
    /// "18m" when partly watched and the duration is known.
    public var timeLeft: String?
    public var spoken: String

    public static func make(progress: Double?, durationSeconds: Double?) -> PlayCapsule {
        guard let p = progress, p > 0, p < 1 else {
            return PlayCapsule(title: "Play", progress: nil, timeLeft: nil, spoken: "Play")
        }
        guard let d = durationSeconds, d > 0, let left = ShortDuration.left(d * (1 - p)) else {
            // Progress without a known duration: the bar alone, no invented time.
            return PlayCapsule(title: "Resume", progress: p, timeLeft: nil, spoken: "Resume")
        }
        return PlayCapsule(title: "Resume", progress: p, timeLeft: left, spoken: "Resume, " + DisplayText.remaining(d * (1 - p)))
    }
}

/// R471 item 3: the round "+" of the movie page (frames: movie t00s), our library's watchlist (UserData `UDWatchlist`,
/// TMDB-keyed, the same list Discover fills). A title not matched to TMDB has no entry, so no button.
public enum WatchlistButton {
    public static func symbol(onList: Bool) -> String { onList ? "checkmark" : "plus" }
    public static func label(onList: Bool) -> String { onList ? "Remove from Watchlist" : "Add to Watchlist" }
}
