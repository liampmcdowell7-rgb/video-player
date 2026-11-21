import Foundation

/// R345 (compile run of 21 Nov 2026 on a0ae4a6): a FOCUSED ROW must be drawn whole. On every Settings and Files page the
/// focused row (the white platter of the system focus effect) was cut flat on its left side at x 990, the left edge of the
/// list column (31, 32, 33, 35 to 38, 41, 64, 69, 71 to 73, 105, 109 and their Larger Text and Bold Text twins): the system
/// focus effect grows the row a few points on each side, and the list clipped the growth to its own bounds.
///
/// Method, on the picture alone (no tree needed): a focused row is a block of at least `minimumHeight` pixel rows in which
/// one run of near-white pixels (`white`: every channel at or above it; gaps of up to `gap` pixels are the row's own dark
/// text) is at least `minimumWidth` wide and mostly white. For each block, `flat` counts the pixel rows that reach the
/// block's leftmost (and rightmost) column. A rounded corner reaches the extreme only in the middle rows, the same number
/// on both sides; a side cut by a straight edge reaches it in many more rows (31: 38 on the left, 20 on the right). The
/// block FAILS when one side has more than `flatTolerance` rows more than the other ("CUT FLAT"), or when it touches the
/// picture's or the given container's edge ("OUTSIDE THE VISIBLE CONTAINER").
///
/// Tolerances, from the run's pictures: an intact focused row has the same count on both sides (10-add-source-types: 38
/// and 38; difference 0 to 2 on every whole row of the run); every cut row of the run has 18 or more extra on the cut side
/// (31: 38 left, 20 right). 8 is between the two.
public enum FocusRoom {
    public static let white: UInt8 = 238
    public static let gap: Int = 60
    public static let minimumWidth: Int = 300
    public static let minimumHeight: Int = 40
    public static let flatTolerance: Int = 8
    /// The share of the run that must be white, so a long white line of text is not taken for a platter.
    public static let minimumFill: Double = 0.6

    public struct Platter: Equatable, Sendable {
        public var top: Int
        public var bottom: Int
        public var left: Int
        public var right: Int
        public var flatLeft: Int
        public var flatRight: Int
    }

    static func isWhite(_ image: RGBImage, _ x: Int, _ y: Int) -> Bool {
        let i: Int = (y * image.width + x) * 3
        return image.bytes[i] >= white && image.bytes[i + 1] >= white && image.bytes[i + 2] >= white
    }

    /// The longest white run of one pixel row (gaps up to `gap` allowed), with its white-pixel count. Sampled every
    /// `stride` pixels, then each end is found to the pixel.
    static func run(_ image: RGBImage, y: Int, stride step: Int = 4) -> (start: Int, end: Int, filled: Int)? {
        var best: (start: Int, end: Int, filled: Int)? = nil
        var start: Int? = nil, last: Int = 0, filled: Int = 0
        func close() {
            guard let s = start else { return }
            if best == nil || last - s > best!.end - best!.start { best = (s, last, filled) }
        }
        var x: Int = 0
        while x < image.width {
            if isWhite(image, x, y) {
                if start == nil || x - last > gap {
                    close()
                    start = x
                    filled = 0
                }
                last = x
                filled += step
            }
            x += step
        }
        close()
        guard var found = best else { return nil }
        while found.start > 0, isWhite(image, found.start - 1, y) { found.start -= 1 }
        while found.end < image.width - 1, isWhite(image, found.end + 1, y) { found.end += 1 }
        return found
    }

    /// Every focused-row platter of the picture, top to bottom.
    public static func platters(in image: RGBImage) -> [Platter] {
        var rows: [Int: (start: Int, end: Int)] = [:]
        for y in 0..<image.height {
            guard let r = run(image, y: y), r.end - r.start >= minimumWidth,
                  Double(r.filled) / Double(r.end - r.start + 1) >= minimumFill else { continue }
            rows[y] = (r.start, r.end)
        }
        var blocks: [[Int]] = []
        var current: [Int] = []
        for y in rows.keys.sorted() {
            if let previous = current.last, y != previous + 1 || abs(rows[y]!.start - rows[previous]!.start) > 40 {
                blocks.append(current)
                current = []
            }
            current.append(y)
        }
        if !current.isEmpty { blocks.append(current) }
        return blocks.filter { $0.count >= minimumHeight }.map { (block: [Int]) -> Platter in
            let left: Int = block.map { rows[$0]!.start }.min()!
            let right: Int = block.map { rows[$0]!.end }.max()!
            return Platter(top: block.first!, bottom: block.last!, left: left, right: right,
                           flatLeft: block.filter { rows[$0]!.start <= left + 1 }.count,
                           flatRight: block.filter { rows[$0]!.end >= right - 1 }.count)
        }
    }

    /// The verdict for one picture. `container` (pixels) is the visible container the row must stay inside; nil is the
    /// whole picture. A picture with no focused-row platter passes with "not measured".
    public static func check(_ image: RGBImage, container: AXRect? = nil) -> CheckResult {
        let found: [Platter] = platters(in: image)
        guard !found.isEmpty else {
            return CheckResult(passed: true, lines: ["no focused row platter in the picture: not measured"])
        }
        let bounds: AXRect = container ?? AXRect(x: 0, y: 0, width: Double(image.width), height: Double(image.height))
        var lines: [String] = []
        var passed: Bool = true
        for platter in found {
            var problems: [String] = []
            if platter.flatLeft - platter.flatRight > flatTolerance { problems.append("CUT FLAT ON THE LEFT") }
            if platter.flatRight - platter.flatLeft > flatTolerance { problems.append("CUT FLAT ON THE RIGHT") }
            if Double(platter.left) <= bounds.x || Double(platter.right) >= bounds.maxX - 1
                || Double(platter.top) <= bounds.y || Double(platter.bottom) >= bounds.maxY - 1 {
                problems.append("OUTSIDE THE VISIBLE CONTAINER")
            }
            if !problems.isEmpty { passed = false }
            lines.append("focused row x \(platter.left) to \(platter.right), y \(platter.top) to \(platter.bottom): "
                         + "rows at the left edge \(platter.flatLeft), at the right edge \(platter.flatRight): "
                         + (problems.isEmpty ? "corners intact" : problems.joined(separator: ", ")))
        }
        lines.append(passed ? "PASS: every focused row is whole" : "FAIL: A FOCUSED ROW IS CLIPPED")
        return CheckResult(passed: passed, lines: lines)
    }
}
