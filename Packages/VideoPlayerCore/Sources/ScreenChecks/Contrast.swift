import Foundation

/// #33 K (OPEN_QUESTIONS R240, PROVISIONAL): the contrast of a text on a screenshot.
///
/// Method:
/// 1. The pixels inside the text's frame (points × scale) are read.
/// 2. Background: the most frequent colour, after grouping the pixels in bins of 16 per channel; its value is the average of
///    the pixels in that bin.
/// 3. Foreground: the pixels farthest in luminance from the background (the top `inkFraction`, the glyph cores); its value is
///    their median luminance.
/// 4. The ratio is WCAG 2's (L1 + 0.05) / (L2 + 0.05), with the relative luminance of sRGB colours.
///
/// Limits (why it is a measurement, not proof):
/// - Anti-aliased glyph edges are mixed with the background; only the cores are used, so a very thin or small text that has
///   no full-colour core reads lower than its real colour.
/// - The screenshot is the composited picture: translucent material, vibrancy and gradients behind the text are measured as
///   they were drawn at that moment, not as the colours the code asked for.
/// - It assumes the glyphs cover at least `inkFraction` of the frame; a frame much wider than its text lowers the result
///   (fewer ink pixels in the top fraction).
/// - It does not know the text's size or weight, so the target (4.5:1 or 3:1 in the HIG's table) is chosen by the caller.
public enum Contrast {
    public static let inkFraction: Double = 0.03

    public struct Measurement: Equatable, Sendable, CustomStringConvertible {
        public var foreground: RGB
        public var background: RGB
        public var ratio: Double
        public var description: String {
            String(format: "%.2f:1 (text %@ on %@)", ratio, foreground.description, background.description)
        }
    }

    /// WCAG 2 relative luminance of an sRGB colour.
    public static func luminance(_ c: RGB) -> Double {
        func channel(_ v: UInt8) -> Double {
            let s: Double = Double(v) / 255
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    /// WCAG 2 contrast ratio, from 1 (equal) to 21 (black on white).
    public static func ratio(_ a: RGB, _ b: RGB) -> Double {
        let la: Double = luminance(a)
        let lb: Double = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The contrast of the text inside `frame` (points; `scale` pixels per point). Nil for an empty or off-picture frame.
    public static func measure(_ image: RGBImage, frame: AXRect, scale: Double) -> Measurement? {
        let x0: Int = max(0, Int((frame.x * scale).rounded(.down)))
        let y0: Int = max(0, Int((frame.y * scale).rounded(.down)))
        let x1: Int = min(image.width, Int((frame.maxX * scale).rounded(.up)))
        let y1: Int = min(image.height, Int((frame.maxY * scale).rounded(.up)))
        guard x1 > x0, y1 > y0 else { return nil }
        var pixels: [RGB] = []
        pixels.reserveCapacity((x1 - x0) * (y1 - y0))
        for y in y0..<y1 { for x in x0..<x1 { pixels.append(image.pixel(x, y)) } }

        var bins: [Int: [RGB]] = [:]
        for p in pixels { bins[(Int(p.r) / 16) << 8 | (Int(p.g) / 16) << 4 | (Int(p.b) / 16), default: []].append(p) }
        guard let biggest = bins.values.max(by: { $0.count < $1.count }) else { return nil }
        let background: RGB = average(biggest)
        let lb: Double = luminance(background)

        let sorted: [RGB] = pixels.sorted { abs(luminance($0) - lb) > abs(luminance($1) - lb) }
        let ink: [RGB] = Array(sorted.prefix(max(1, Int(Double(sorted.count) * inkFraction))))
        let foreground: RGB = ink.sorted { luminance($0) < luminance($1) }[ink.count / 2]
        return Measurement(foreground: foreground, background: background, ratio: ratio(foreground, background))
    }

    static func average(_ colours: [RGB]) -> RGB {
        let n: Int = max(1, colours.count)
        let r: Int = colours.reduce(0) { $0 + Int($1.r) } / n
        let g: Int = colours.reduce(0) { $0 + Int($1.g) } / n
        let b: Int = colours.reduce(0) { $0 + Int($1.b) } / n
        return RGB(r: UInt8(r), g: UInt8(g), b: UInt8(b))
    }
}
