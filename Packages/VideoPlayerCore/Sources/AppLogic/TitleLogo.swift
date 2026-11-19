import Foundation
import MetadataOnline

// Title logos ("clear logos": a transparent picture of a title's lettering), #15 Part 9. PROVISIONAL, OPEN_QUESTIONS R179.
// Shown in place of the text title on the movie page and the show page when one is found and the setting is on; otherwise
// the text title stays. Never on grid cards.
//
// Sources, in order: the server's own logo (not built: the Jellyfin and Emby modules have no image code yet), a local file
// next to the media (clearlogo.png, logo.png; `SidecarImageFinder`), then TMDB's logos for the matched title, only with the
// user's own key (they come with the title details the app already requests: no extra request). Otherwise the text title.

/// Where a logo candidate comes from, strongest first.
public enum TitleLogoSource: Int, Comparable, Sendable {
    case server = 0, localFile = 1, online = 2
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// What the app measured in a decoded logo picture.
public struct LogoPixels: Equatable, Sendable {
    public var width: Int
    public var height: Int
    /// True when some pixels are see-through (alpha below 250). A logo without any is a picture with a background.
    public var hasTransparency: Bool
    /// Mean relative luminance (0 black ... 1 white) of the visible pixels (alpha 128 and up), weighted by alpha.
    public var meanLuminance: Double
    /// Share of the visible pixels in the whole picture; nearly empty pictures are rejected.
    public var coverage: Double

    public init(width: Int, height: Int, hasTransparency: Bool, meanLuminance: Double, coverage: Double) {
        self.width = width; self.height = height; self.hasTransparency = hasTransparency
        self.meanLuminance = meanLuminance; self.coverage = coverage
    }

    /// Measures an RGBA buffer (8 bits per channel, not premultiplied, row after row). Returns nil for a wrong size.
    public static func measure(rgba: [UInt8], width: Int, height: Int) -> LogoPixels? {
        guard width > 0, height > 0, rgba.count == width * height * 4 else { return nil }
        var transparent = false
        var weighted = 0.0, weight = 0.0, visible = 0
        var i = 0
        while i < rgba.count {
            let a = Double(rgba[i + 3]) / 255
            if rgba[i + 3] < 250 { transparent = true }
            if rgba[i + 3] >= 128 {
                visible += 1
                let l = relativeLuminance(r: rgba[i], g: rgba[i + 1], b: rgba[i + 2])
                weighted += l * a
                weight += a
            }
            i += 4
        }
        return LogoPixels(width: width, height: height, hasTransparency: transparent,
                          meanLuminance: weight > 0 ? weighted / weight : 0, coverage: Double(visible) / Double(width * height))
    }

    /// WCAG relative luminance of an sRGB colour.
    public static func relativeLuminance(r: UInt8, g: UInt8, b: UInt8) -> Double {
        func lin(_ c: UInt8) -> Double {
            let s = Double(c) / 255
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// WCAG contrast ratio of two luminances (1 ... 21).
    public static func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

public enum TitleLogoRules {
    /// The box a logo is scaled to fit, in points. PROVISIONAL (#15 9.3).
    public static let boxWidth = 640.0
    public static let boxHeight = 200.0
    /// A logo narrower than this (pixels) is too small to read at 10 feet. PROVISIONAL.
    public static let minimumWidth = 300
    /// The scrim behind the logo area is dark; its luminance, for the contrast check. PROVISIONAL.
    public static let scrimLuminance = 0.02
    /// Minimum WCAG contrast between the logo's mean colour and the scrim: 3:1, WCAG's figure for large text. PROVISIONAL.
    public static let minimumContrast = 3.0
    /// Less than this share of visible pixels: an empty or nearly empty picture.
    public static let minimumCoverage = 0.02

    /// Candidate order within one source (#15 9.3): language (the user's, then English, then no language, then any), then the
    /// higher vote, then the wider picture. Pictures known to be narrower than `minimumWidth` are left out.
    public static func ordered(_ refs: [ImageRef], userLanguage: String?) -> [ImageRef] {
        let user = userLanguage.map { String($0.prefix(2)).lowercased() }
        func rank(_ r: ImageRef) -> Int {
            let lang = r.language?.lowercased()
            if let user, lang == user { return 0 }
            if lang == "en" { return 1 }
            if lang == nil { return 2 }
            return 3
        }
        return refs.enumerated()
            .filter { ($0.element.width ?? minimumWidth) >= minimumWidth }
            .sorted { a, b in
                let (ra, rb) = (rank(a.element), rank(b.element))
                if ra != rb { return ra < rb }
                let (va, vb) = (a.element.voteAverage ?? 0, b.element.voteAverage ?? 0)
                if va != vb { return va > vb }
                let (wa, wb) = (a.element.width ?? 0, b.element.width ?? 0)
                if wa != wb { return wa > wb }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    /// Why a decoded picture is not used, or nil when it is accepted.
    public enum Rejection: String, Equatable, Sendable {
        case notTransparent, tooSmall, nearlyEmpty, tooDark, tooLight
    }

    /// The checks of #15 9.3 on a decoded picture. "Too dark": a dark logo on the dark scrim (contrast below 3:1). "Too light"
    /// applies only when the scrim is light (`scrimLuminance` above 0.5); with the dark scrim a white logo is the best case.
    public static func check(_ p: LogoPixels, scrimLuminance: Double = scrimLuminance) -> Rejection? {
        if !p.hasTransparency { return .notTransparent }
        if p.width < minimumWidth { return .tooSmall }
        if p.coverage < minimumCoverage { return .nearlyEmpty }
        if LogoPixels.contrast(p.meanLuminance, scrimLuminance) < minimumContrast {
            return scrimLuminance > 0.5 ? .tooLight : .tooDark
        }
        return nil
    }

    /// The drawn size: fits the box, keeps the aspect ratio, never larger than the picture itself at `scale` pixels per point
    /// (never enlarged beyond 1x), never cropped.
    public static func fittedSize(pixelWidth: Int, pixelHeight: Int, scale: Double) -> (width: Double, height: Double) {
        guard pixelWidth > 0, pixelHeight > 0, scale > 0 else { return (0, 0) }
        let w = Double(pixelWidth) / scale, h = Double(pixelHeight) / scale
        let factor = min(1, boxWidth / w, boxHeight / h)
        return (w * factor, h * factor)
    }
}
