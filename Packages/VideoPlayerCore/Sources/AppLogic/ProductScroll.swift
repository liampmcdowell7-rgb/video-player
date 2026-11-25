import Foundation

/// R471 item 1 (owner's frames of the Apple TV app, tvOS 27: episode t02s, show t06s and t12s, movie t02s; PROVISIONAL):
/// how a movie, show or episode page looks once it is scrolled past its first screen.
///
/// - The first screen (the hero) shows the artwork clear at the top, the text block at the bottom left on R470's cover.
/// - Below it, the artwork stays where it is, but as a blurred, dimmed copy: the system material over the whole picture
///   and a uniform cover at the strength R470 proved readable at the text (`ArtReadability.scrimMaxOpacity`).
/// - The first part below the hero starts with the title (the clear logo when there is one) centred at the top, so the
///   page still says whose it is; it scrolls with the content, as in the frames (t04s shows it moving up and off).
///
/// Pure logic; App/Shared/BackdropView.swift and the pages draw it.
public enum ProductScroll {
    /// The share of the hero's height that must be scrolled before the background turns into the blurred copy. Our
    /// choice: Apple publishes none; the frames show the copy as soon as the first row below the hero has the focus, which
    /// scrolls the page by most of the hero.
    public static let belowHeroShare: Double = 0.35

    /// True once the page is scrolled far enough below its hero (`offset` is the scroll view's content offset from its
    /// resting top, `heroHeight` the hero's height; both in points). A page not measured yet (height 0) is never scrolled.
    public static func isBelowHero(offset: Double, heroHeight: Double) -> Bool {
        guard heroHeight > 0, offset.isFinite else { return false }
        return offset >= heroHeight * belowHeroShare
    }

    /// The cover over the blurred copy: one strength, top to bottom, the strongest the hero's cover ever reaches, so any
    /// text below the hero is at least as readable as the hero's own text (ArtReadabilityTests prove that strength).
    public static var belowHeroCoverOpacity: Double { ArtReadability.scrimMaxOpacity }

    /// How long the change from the clear hero to the blurred copy takes (none with Reduce Motion). Our choice.
    public static let crossFadeSeconds: Double = 0.35
}
