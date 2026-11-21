import Foundation

/// An image as 8-bit RGB triples, row by row (alpha dropped). The UI tests fill it from the screenshot with CoreGraphics;
/// the Linux tests from a PNG file (`PNGDecoder`).
public struct RGBImage: Sendable {
    public let width: Int
    public let height: Int
    public var bytes: [UInt8]

    public init(width: Int, height: Int, bytes: [UInt8]) {
        precondition(bytes.count == width * height * 3, "RGBImage: \(bytes.count) bytes for \(width)x\(height)")
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    /// A plain image of one colour.
    public init(width: Int, height: Int, fill: RGB) {
        self.width = width
        self.height = height
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height * 3)
        for _ in 0..<(width * height) { bytes.append(fill.r); bytes.append(fill.g); bytes.append(fill.b) }
        self.bytes = bytes
    }

    public func pixel(_ x: Int, _ y: Int) -> RGB {
        let i: Int = (y * width + x) * 3
        return RGB(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2])
    }

    public mutating func set(_ x: Int, _ y: Int, _ colour: RGB) {
        let i: Int = (y * width + x) * 3
        bytes[i] = colour.r
        bytes[i + 1] = colour.g
        bytes[i + 2] = colour.b
    }

    /// Fills a rectangle given in points (`scale` pixels per point), clipped to the image.
    public mutating func fill(_ rect: AXRect, scale: Double, with colour: RGB) {
        let x0: Int = max(0, Int((rect.x * scale).rounded(.down))), x1: Int = min(width, Int((rect.maxX * scale).rounded(.up)))
        let y0: Int = max(0, Int((rect.y * scale).rounded(.down))), y1: Int = min(height, Int((rect.maxY * scale).rounded(.up)))
        guard x0 < x1, y0 < y1 else { return }
        for y in y0..<y1 { for x in x0..<x1 { set(x, y, colour) } }
    }
}

public struct RGB: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// The largest difference in any one channel.
    public func distance(to other: RGB) -> Int {
        max(abs(Int(r) - Int(other.r)), abs(Int(g) - Int(other.g)), abs(Int(b) - Int(other.b)))
    }

    public var description: String { String(format: "#%02X%02X%02X", r, g, b) }
}

/// #33 B (1): while a cover is open, nothing of the page behind it and no tab bar may be SEEN. The run of 20 Nov showed the
/// Home empty state, the tab bar, the Needs Review list and the movie page through the covers (11 to 19, 66, 74), and no
/// check looked at the pixels.
///
/// Method: the cover's own background is the most common colour of four 40 x 40 pt boxes in the window's corners (outside
/// the tvOS safe area of 60 pt top and bottom and 80 pt at the sides, HIG Layout, where a task page draws nothing). In each
/// sampled region (the tab bar band, y 46 to 114 over the whole width, and every text the page behind had before the cover
/// opened) a pixel is STRAY when one of its channels differs from that background by more than `channelTolerance`, unless
/// it lies inside one of the cover's own elements (`exclude`). A region fails when it has more than
/// max(`minimumStray`, `strayFraction` of its pixels) stray pixels.
///
/// Tolerance, chosen from the run's pictures: an opaque system fill has a channel spread of 0 (one colour); text and
/// tab-bar symbols drawn through the cover differ from the dark backdrop by 100 to 230 in a channel (white and grey glyph
/// cores); the page's own dark backdrop gradient differs from its corners by up to about 20. 24 is above the backdrop
/// gradient and the dither of a fill, and far below any glyph. The count threshold (0.1 % of a region, at least 20 pixels)
/// is far below one tab label (about 1,000 glyph pixels for "Movies" with its symbol) and one line of page text, and above
/// a few anti-aliased pixels at the edge of an excluded element.
public enum CoverPixels {
    public static let channelTolerance: Int = 24
    public static let strayFraction: Double = 0.001
    public static let minimumStray: Int = 20
    /// Where the tab bar is drawn (note 10-add-source-types-HIERARCHY: TabBar {{0, 46}, {1920, 68}}).
    public static let tabBarBand: AXRect = AXRect(x: 0, y: 46, width: 1920, height: 68)

    /// The most common colour of the four corner boxes (points; `scale` pixels per point).
    public static func background(of image: RGBImage, scale: Double) -> RGB {
        let box: Double = 40
        let widthPoints: Double = Double(image.width) / scale, heightPoints: Double = Double(image.height) / scale
        let corners: [AXRect] = [AXRect(x: 0, y: 0, width: box, height: box),
                                 AXRect(x: widthPoints - box, y: 0, width: box, height: box),
                                 AXRect(x: 0, y: heightPoints - box, width: box, height: box),
                                 AXRect(x: widthPoints - box, y: heightPoints - box, width: box, height: box)]
        var counts: [RGB: Int] = [:]
        for corner in corners {
            forEachPixel(in: corner, image: image, scale: scale) { x, y in counts[image.pixel(x, y), default: 0] += 1 }
        }
        return counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key.description > $1.key.description) }?.key ?? RGB(r: 0, g: 0, b: 0)
    }

    /// Checks `regions` (name and rectangle in points) against the cover's background, skipping `exclude` (the cover's own
    /// elements, in points). One line per region and a final verdict.
    public static func check(_ image: RGBImage, scale: Double, regions: [(String, AXRect)], exclude: [AXRect]) -> CheckResult {
        let background: RGB = background(of: image, scale: scale)
        var lines: [String] = ["cover background \(background) (most common colour of the four corners), tolerance \(channelTolerance) per channel"]
        var passed: Bool = true
        var measuredTexts: Int = 0
        var unmeasuredTexts: Int = 0
        for (name, region) in regions {
            var sampled: Int = 0
            var stray: Int = 0
            var firstStray: (Int, Int)?
            forEachPixel(in: region, image: image, scale: scale) { x, y in
                let px: Double = Double(x) / scale, py: Double = Double(y) / scale
                if exclude.contains(where: { $0.contains(x: px, y: py) }) { return }
                sampled += 1
                if image.pixel(x, y).distance(to: background) > channelTolerance {
                    stray += 1
                    if firstStray == nil { firstStray = (Int(px), Int(py)) }
                }
            }
            let limit: Int = max(minimumStray, Int(Double(sampled) * strayFraction))
            // R292: a region with no pixel left to sample proves nothing (fourth run of 20 Nov, 21-search-your-network-
            // server-details: "0 of 0 pixels" in all four page texts, the scrolled form's rows over them, and the check
            // passed). One such region is reported NOT MEASURED (the cover's own text often sits where a page text was);
            // when EVERY page-text region is unmeasured, the check fails (below).
            if sampled == 0 {
                lines.append("\(name) \(region): 0 pixels sampled (all under the cover's own elements): NOT MEASURED")
                if name.hasPrefix("page text") { unmeasuredTexts += 1 }
                continue
            }
            if name.hasPrefix("page text") { measuredTexts += 1 }
            let ok: Bool = stray <= limit
            if !ok { passed = false }
            let at: String = firstStray.map { " (first at \($0.0), \($0.1))" } ?? ""
            lines.append("\(name) \(region): \(stray) of \(sampled) pixels differ from the background, limit \(limit)\(at): \(ok ? "clear" : "SOMETHING SHOWS THROUGH")")
        }
        if unmeasuredTexts > 0 && measuredTexts == 0 {
            passed = false
            lines.append("none of the \(unmeasuredTexts) page-text regions could be sampled: PAGE TEXT NOT MEASURED")
        }
        lines.append(passed ? "COVER OPAQUE OK" : "PAGE OR TAB BAR VISIBLE THROUGH THE COVER, OR NOT MEASURED")
        return CheckResult(passed: passed, lines: lines)
    }

    /// The regions of `check` for a cover: the tab bar band and each text frame the page behind had (clipped to the window).
    public static func regions(pageTexts: [AXRect], window: AXRect) -> [(String, AXRect)] {
        var regions: [(String, AXRect)] = [("tab bar band", tabBarBand.intersection(window))]
        for (n, frame) in pageTexts.enumerated() {
            let clipped: AXRect = frame.intersection(window)
            if !clipped.isEmpty { regions.append(("page text \(n + 1)", clipped)) }
        }
        return regions
    }

    /// What `check` excludes: the cover's own elements, each grown by 4 pt for anti-aliasing; the focused element grown by
    /// 40 pt (the tvOS focus lift and its shadow reach past the element's frame).
    public static func coverElements(in dump: AccessibilityDump) -> [AXRect] {
        guard let cover = dump.coverRoot else { return [] }
        // Not "Other": its section containers span the column's whole width, over the tab bar band (74-file-details).
        let kinds: Set<String> = ["StaticText", "TextField", "SecureTextField", "Image", "Switch", "Button", "Cell"]
        return dump.descendants(of: cover).compactMap { (index: Int) -> AXRect? in
            let node: AXNode = dump.nodes[index]
            guard let frame = node.frame, !frame.isEmpty, kinds.contains(node.type) else { return nil }
            // R292: a row (Cell) is excluded only while it has the focus (its lifted white platter). An unfocused row is
            // measured: its system platter is within the tolerance of the cover background, and page text behind a
            // see-through row would show up as stray pixels instead of being skipped.
            if node.type == "Cell" && !node.isFocused { return nil }
            // Full-window containers would exclude everything: only elements smaller than half the window count.
            if let window = dump.window, let full = dump.nodes[window].frame, frame.width * frame.height > full.width * full.height / 2 { return nil }
            return frame.padded(by: node.isFocused ? 40 : 4)
        }
    }

    static func forEachPixel(in rect: AXRect, image: RGBImage, scale: Double, _ body: (Int, Int) -> Void) {
        let x0: Int = max(0, Int((rect.x * scale).rounded(.down))), x1: Int = min(image.width, Int((rect.maxX * scale).rounded(.up)))
        let y0: Int = max(0, Int((rect.y * scale).rounded(.down))), y1: Int = min(image.height, Int((rect.maxY * scale).rounded(.up)))
        guard x0 < x1, y0 < y1 else { return }
        for y in y0..<y1 { for x in x0..<x1 { body(x, y) } }
    }
}
