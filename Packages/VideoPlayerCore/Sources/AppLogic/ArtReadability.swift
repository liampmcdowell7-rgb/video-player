import Foundation

/// R452 (owner's rule of 23 Nov 2026, R312): text, buttons, badges and progress bars over artwork stay readable whatever the
/// picture is. EVERY parameter of the scrim is here, in one place, so the comparison with the owner's recordings of Apple's TV
/// app (spacing, start, strength) is a matter of changing these numbers.
///
/// Why our own gradient: Apple's media catalog sample uses the system regular material under a masked gradient, and its pages
/// state NO darkening for a material (HIG Materials gives no number), so the contrast proof counts none. The system material
/// stays (it is Apple's treatment); this black gradient under it is the part the proof needs.
public enum ArtReadability {
    /// Opacity of the black cover where the text is (its full strength). Raised only as far as the proof needs: 0.75 fails
    /// secondary text over white (4.45:1), 0.80 passes (5.08:1); see `ArtReadabilityTests`.
    public static let scrimMaxOpacity: Double = 0.80
    /// The cover fades in over this share of the container's height, ending at the first line of text. PROVISIONAL (the
    /// owner's recordings decide).
    /// R470 (owner's photo of build 202611250008, episode page): 0.12 (about 130 pt on a 1080 pt screen) with two linear stops
    /// drew a visible step under the title. Now 0.25 (about 270 pt) with eased stops (`coverStops`), so the fade has no edge.
    public static let rampFraction: Double = 0.25
    /// R470: how many stops draw the eased fade. SwiftUI's gradients interpolate linearly between stops (ShapeStyle lists no
    /// eased gradient), so the curve is sampled; nine stops leave no visible corner.
    public static let rampStopCount: Int = 9
    /// Where the cover starts when no text position is known yet (the old fixed share, R349/R350).
    public static let fallbackStart: Double = 0.35
    /// A thin progress bar over a card's art: the same black, smaller, under the bar only.
    public static let progressScrimOpacity: Double = 0.60

    /// Where the cover starts, as a share of the container height: the ramp ends at the first line of text, so it starts one
    /// ramp above it. Without a position, `fallbackStart`.
    /// R470: NOT clamped at 0. A column near the top of the screen (the show page's hero is only `showHeroFraction` of the
    /// page) gives a start above the picture; R452 clamped it to 0, which moved the END of the ramp below the first line, so
    /// the title sat in the fading part. Now the start may be as low as `-rampFraction` (text at the very top: full strength
    /// from the top edge); the part of the ramp above the picture is simply not drawn (`coverStops`).
    public static func coverStart(textTop: Double?, height: Double) -> Double {
        guard let textTop, height > 0 else { return fallbackStart }
        return min(max(textTop / height - rampFraction, -rampFraction), 1)
    }

    /// R470: the eased curve of the fade, 0 at the start of the ramp, 1 at its end (smootherstep: no slope at either end, so
    /// neither the start nor the end of the cover shows as a line).
    public static func ease(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    /// R470: the cover's opacity at `y` (a share of the container's height) for a cover that starts at `start` and is at full
    /// strength (`scrimMaxOpacity`) from `start + rampFraction` down to the bottom edge.
    public static func coverAlpha(at y: Double, start: Double) -> Double {
        guard rampFraction > 0 else { return y >= start ? scrimMaxOpacity : 0 }
        return scrimMaxOpacity * ease((y - start) / rampFraction)
    }

    /// R470: the gradient's stops (location, opacity) for a cover starting at `start`: `rampStopCount` samples of the eased
    /// ramp over the part of it that lies on the picture (0...1), then full strength to the bottom. Every location is in
    /// 0...1, they strictly increase, and each opacity is the curve's own value there (a ramp that starts above the picture
    /// begins part-way up the curve at the top edge, never at 0).
    public static func coverStops(start: Double) -> [(location: Double, alpha: Double)] {
        let n = max(rampStopCount, 2)
        let lo = min(max(start, 0), 1), hi = min(max(start + rampFraction, 0), 1)
        guard hi > lo else {
            // The whole ramp lies above the picture (or below it): one opacity from top to bottom.
            let alpha = coverAlpha(at: lo, start: start)
            return [(location: 0, alpha: alpha), (location: 1, alpha: alpha)]
        }
        var stops: [(location: Double, alpha: Double)] = (0..<n).map { (i: Int) in
            let y = lo + (hi - lo) * Double(i) / Double(n - 1)
            return (location: y, alpha: coverAlpha(at: y, start: start))
        }
        if hi < 1 { stops.append((location: 1, alpha: scrimMaxOpacity)) }
        if lo > 0 { stops.insert((location: 0, alpha: 0), at: 0) }
        return stops
    }

    // MARK: WCAG 2.x contrast (https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio)

    /// Relative luminance of a grey given as an sRGB value 0...1.
    public static func luminance(grey value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    public static func contrast(_ a: Double, _ b: Double) -> Double {
        let hi = max(a, b), lo = min(a, b)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// A backdrop of brightness `backdrop` (sRGB grey, 1 = pure white, the worst case) under the black cover of opacity
    /// `opacity`: the grey the text sits on. No material darkening is counted.
    public static func covered(backdrop: Double, opacity: Double) -> Double { backdrop * (1 - opacity) }

    /// The system's primary text colour on tvOS (white) and the secondary one (about white at 60 %, the system's secondary
    /// label), composited over the covered grey.
    public static func primaryContrast(backdrop: Double, opacity: Double) -> Double {
        contrast(luminance(grey: 1), luminance(grey: covered(backdrop: backdrop, opacity: opacity)))
    }

    public static func secondaryContrast(backdrop: Double, opacity: Double) -> Double {
        let ground = covered(backdrop: backdrop, opacity: opacity)
        let text = 0.6 * 0.94 + 0.4 * ground
        return contrast(luminance(grey: text), luminance(grey: ground))
    }
}
