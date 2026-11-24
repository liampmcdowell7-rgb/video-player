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
    public static let rampFraction: Double = 0.12
    /// Where the cover starts when no text position is known yet (the old fixed share, R349/R350).
    public static let fallbackStart: Double = 0.35
    /// A thin progress bar over a card's art: the same black, smaller, under the bar only.
    public static let progressScrimOpacity: Double = 0.60

    /// Where the cover starts, as a share of the container height: the ramp ends at the first line of text, so it starts one
    /// ramp above it. Clamped to 0...1; without a position, `fallbackStart`.
    public static func coverStart(textTop: Double?, height: Double) -> Double {
        guard let textTop, height > 0 else { return fallbackStart }
        return min(max(textTop / height - rampFraction, 0), 1)
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
