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

/// R471 (120), PROVISIONAL (owner's report and timing table of 26 Nov 2026, measured on a 30 fps video of the Apple TV
/// app; contact sheets motion-1 to motion-4): the motion between a product page's hero and the part below it, driven by
/// `ProductScroll.isBelowHero`. Opacity and vertical offsets only; the page's own scroll (the focus engine's) moves
/// everything as before, these come on top of it. Each part has its own delay, length and curve per direction, so the
/// hero group leaves fast (about 0.15 s) while the header lands slowly (about 0.55 s). With Reduce Motion: the same fades,
/// every offset 0. The backdrop's blur and dim keep `ProductScroll.crossFadeSeconds` (owner: "the existing 0.35 s
/// crossfade stays").
///
/// Two title instances: the hero's (left) and the header's (centred, `BelowHeroHeader`), which scrolls with the content,
/// never pinned. Exactly one of them carries the accessibility label at a time (`Frame.heroTitleIsAccessible`).
public enum HeroMotion {
    /// The page's title: a logo (show page; a movie with a logo: the owner's A, B, D) or text (episode page; a movie
    /// without a logo: the owner's C).
    public enum Title: Equatable, Sendable {
        case logo
        case text
    }

    /// The parts that move, each with its own timing.
    public enum Part: Equatable, Sendable, CaseIterable {
        /// The hero text group: title, kind line, description, facts, buttons, Starring.
        case heroGroup
        case headerFade
        case headerOffset
        /// The part below the hero (rows and columns) and the top-edge fade.
        case section
    }

    /// One part's animation: a delay, a length (seconds) and a cubic Bezier curve (the control points of SwiftUI's
    /// `timingCurve`).
    public struct Timing: Equatable, Sendable {
        public let delay: Double
        public let duration: Double
        public let curve: Curve

        /// How far along the part is (0 to 1) `time` seconds after the press.
        public func progress(at time: Double) -> Double {
            guard duration > 0 else { return time >= delay ? 1 : 0 }
            return curve.value(at: min(1, max(0, (time - delay) / duration)))
        }
    }

    /// A cubic Bezier from (0, 0) to (1, 1) through two control points.
    public struct Curve: Equatable, Sendable {
        public let c1x: Double, c1y: Double, c2x: Double, c2y: Double

        /// The curve's height at `x` (0 to 1), found by bisection on x.
        public func value(at x: Double) -> Double {
            func bezier(_ p1: Double, _ p2: Double, _ t: Double) -> Double {
                let u = 1 - t
                return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
            }
            var low = 0.0, high = 1.0
            for _ in 0..<40 {
                let mid = (low + high) / 2
                if bezier(c1x, c2x, mid) < x { low = mid } else { high = mid }
            }
            return bezier(c1y, c2y, (low + high) / 2)
        }
    }

    /// The system's ease-out and ease-in curves (the CSS values SwiftUI's `easeOut` and `easeIn` use).
    public static let easeOut = Curve(c1x: 0, c1y: 0, c2x: 0.58, c2y: 1)
    public static let easeIn = Curve(c1x: 0.42, c1y: 0, c2x: 1, c2y: 1)
    /// The header's landing, a strong ease-out: fitted to the owner's measured positions of the show logo (A3) and the
    /// episode title (C3) at once; within 3.3 % of the screen's height of every measured point (the table is +/- 5 %).
    public static let landing = Curve(c1x: 0.3, c1y: 0.8, c2x: 0.55, c2y: 1)

    /// The timing of `part` for the change INTO the given state (`belowHero` true: Down; false: Up).
    public static func timing(_ part: Part, title: Title, belowHero: Bool) -> Timing {
        if belowHero {
            switch (part, title) {
            // A1: the show's hero group gone by t+0.15 (from t+0.03); C1: the episode's from t+0.02 to t+0.20.
            case (.heroGroup, .logo): return Timing(delay: 0.03, duration: 0.12, curve: easeOut)
            case (.heroGroup, .text): return Timing(delay: 0.02, duration: 0.18, curve: easeOut)
            // A3: faint at t+0.16, at rest by about t+0.70; C3: faint at t+0.22, at rest by t+0.85.
            case (.headerFade, .logo), (.headerOffset, .logo): return Timing(delay: 0.16, duration: 0.54, curve: landing)
            case (.headerFade, .text), (.headerOffset, .text): return Timing(delay: 0.22, duration: 0.63, curve: landing)
            // A1: the rows in from t+0.06, in place by t+0.30; C1: from t+0.15, in place by t+0.55.
            case (.section, .logo): return Timing(delay: 0.06, duration: 0.24, curve: easeOut)
            case (.section, .text): return Timing(delay: 0.15, duration: 0.40, curve: easeOut)
            }
        }
        switch part {
        // B2: the hero enters from the top from t+0.20 to t+0.60, ease-out.
        case .heroGroup: return Timing(delay: 0.20, duration: 0.40, curve: easeOut)
        // B1: the header faded out by t+0.22 ...
        case .headerFade: return Timing(delay: 0.02, duration: 0.20, curve: easeIn)
        // ... and dropping, accelerating, from 14 % to about 45 % by then (31 of its 46 % of travel at t+0.22).
        case .headerOffset: return Timing(delay: 0.02, duration: 0.25, curve: easeIn)
        // B2: the rows slide down and out from t+0.15 to t+0.30.
        case .section: return Timing(delay: 0.15, duration: 0.15, curve: easeIn)
        }
    }

    /// Where the header starts and rests, as shares of the screen's height from the top (A3: 60 % to 14 %; C3: 50 % to
    /// 12 %); its offset at the hero is the difference times the page's height.
    public static func headerStart(_ title: Title) -> Double { title == .logo ? 0.60 : 0.50 }
    public static func headerRest(_ title: Title) -> Double { title == .logo ? 0.14 : 0.12 }
    public static func headerTravel(_ title: Title) -> Double { headerStart(title) - headerRest(title) }

    /// The header logo's width over the hero logo's (A3: about 530 pt against 400 pt).
    public static let headerLogoWidthRatio: Double = 1.3
    /// The header text title's width over the hero's (C3). NOT applied: the system text styles end at Large Title and
    /// the design rules allow no fixed font size; the header text uses the largest style that fits on one line.
    public static let headerTextWidthRatio: Double = 1.5

    /// How far above its place the hero group waits below the hero, as a share of the page's height, so on Up it
    /// "enters from the top edge" (B2). Our reading of motion-2 (the hero logo at rest at about 55 to 60 % of the screen);
    /// not in the owner's table.
    public static let heroEntry: Double = 0.5

    /// How far below its place the part below the hero waits at the hero (points). Our choice: the owner's table gives
    /// the rows' timing, not a distance beyond the page's scroll.
    public static let sectionRise: Double = 40

    /// The band at the page's top edge in which content passing under it fades out, below the hero only (points; D).
    /// Our choice: motion-4 shows the fade, not its height.
    public static let topFadeHeight: Double = 90

    /// Everything the motion moves, for one state of the page (points and opacities).
    public struct Frame: Equatable, Sendable {
        public var heroOpacity: Double
        /// The hero text group's vertical offset (negative is up).
        public var heroOffset: Double
        public var headerOpacity: Double
        /// The header title's offset INSIDE the part below the hero, which itself moves by `sectionOffset`.
        public var headerOffset: Double
        public var sectionOffset: Double
        /// The opacity of the plain (no fade) layer of the top-edge mask: 1 at the hero (no fade), 0 below it.
        public var topFadeOff: Double
        /// Which title instance carries the accessibility label and header trait: the hero's, or (false) the header's.
        public var heroTitleIsAccessible: Bool
    }

    /// The state of the page at the hero (`belowHero` false) or below it. `pageHeight` is the page's scroll view height
    /// (0 until measured: then no share-based offset). `hasHeader` false: no header title is drawn, so the hero's title
    /// keeps the accessibility label even below the hero.
    public static func frame(belowHero: Bool, title: Title, reduceMotion: Bool, pageHeight: Double,
                             hasHeader: Bool = true) -> Frame {
        let move: Double = reduceMotion ? 0 : 1
        let height: Double = pageHeight.isFinite ? max(0, pageHeight) : 0
        if belowHero {
            return Frame(heroOpacity: 0, heroOffset: -heroEntry * height * move, headerOpacity: 1, headerOffset: 0,
                         sectionOffset: 0, topFadeOff: 0, heroTitleIsAccessible: !hasHeader)
        }
        let section: Double = sectionRise * move
        let header: Double = max(0, headerTravel(title) * height * move - section)
        return Frame(heroOpacity: 1, heroOffset: 0, headerOpacity: 0, headerOffset: header, sectionOffset: section,
                     topFadeOff: 1, heroTitleIsAccessible: true)
    }

    /// The header's whole offset (its own plus the section's) in a frame.
    public static func headerTotalOffset(_ frame: Frame) -> Double { frame.headerOffset + frame.sectionOffset }
}
