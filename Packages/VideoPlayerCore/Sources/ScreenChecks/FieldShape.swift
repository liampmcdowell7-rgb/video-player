import Foundation

/// OPEN_QUESTIONS R273 (PROVISIONAL): a text or secure field that does not have the focus must still show a shape, so a
/// form never reads as a list of labels. The owner's TestFlight build of 20 Nov 2026 (main at 8e347e0) showed the WebDAV
/// form with no text entry fields at all; no screenshot run had drawn the R265 field style before, so nothing caught it.
///
/// What counts as a shape (pixels only, no knowledge of the style that drew it): EITHER the field's fill differs from the
/// page (the dominant colour of two strips inside the field, near its top and bottom edges, against the dominant colour of
/// the page), OR at least half of a thin ring along the field's own edge differs from the page (an outline without a fill).
/// The page colour: when the field's ROW frame is known (the Form cell around label and field), strips just left and right
/// of the row (then above and below it if those are off the picture), so a field drawn on the system row platter compares
/// against the page and not against the platter (R273 build: the row background is back, and a strip just outside the
/// field would be platter colour); the platter itself counts as the field's shape. Without a row frame, strips just above
/// and below the field (the first R273 form). "Differs" is a WCAG contrast ratio of at least
/// `fieldShapeMinimumRatio`. The strips stay clear of the field's middle, so a prompt or typed text alone never counts as a
/// shape. A field with the focus is skipped (the system draws its focused look); a field with no frame fails.
public extension ScreenRules {
    /// The smallest contrast between a field and the page around it that counts as a visible shape. 1.0 means equal, so
    /// 1.1 only says "not the same colour": the check is for a field that is INVISIBLE at rest, not a contrast floor.
    /// PROVISIONAL (R273): the alternative is WCAG 2.1 SC 1.4.11's 3:1 for user-interface components.
    static let fieldShapeMinimumRatio: Double = 1.1
    /// How much of the edge ring must differ from the outside for an outline to count.
    static let fieldEdgeFraction: Double = 0.5

    struct FieldAtRest: Sendable {
        public var name: String
        public var frame: AXRect?
        public var isFocused: Bool
        /// The row (Form cell) that holds the field, when known; the page colour is then sampled outside the row.
        public var row: AXRect?

        public init(name: String, frame: AXRect?, isFocused: Bool, row: AXRect? = nil) {
            self.name = name
            self.frame = frame
            self.isFocused = isFocused
            self.row = row
        }
    }

    /// `scale` is pixels per point of the picture.
    static func fieldShapeAtRest(_ image: RGBImage, fields: [FieldAtRest], scale: Double) -> CheckResult {
        var lines: [String] = ["a field without the focus needs a fill or an outline of at least "
                               + String(format: "%.2f", fieldShapeMinimumRatio) + ":1 against the page around it"]
        var invisible: [String] = []
        var checked: Int = 0
        for field in fields {
            guard let frame = field.frame, frame.width > 24, frame.height > 24 else {
                lines.append("\u{201C}\(field.name)\u{201D}: no frame on screen")
                invisible.append("\u{201C}\(field.name)\u{201D} not on screen")
                continue
            }
            if field.isFocused {
                lines.append("\u{201C}\(field.name)\u{201D} \(frame): has the focus, skipped")
                continue
            }
            checked += 1
            let inside: [AXRect] = [
                AXRect(x: frame.x + 12, y: frame.y + 4, width: frame.width - 24, height: 6),
                AXRect(x: frame.x + 12, y: frame.maxY - 10, width: frame.width - 24, height: 6),
            ]
            guard let fill = dominant(image, inside, scale: scale), let page = pageColour(image, field: frame, row: field.row, scale: scale) else {
                lines.append("\u{201C}\(field.name)\u{201D} \(frame): outside the picture")
                invisible.append("\u{201C}\(field.name)\u{201D} outside the picture")
                continue
            }
            let fillRatio: Double = Contrast.ratio(fill, page)
            let edge: Double = edgeFraction(image, frame: frame, page: page, scale: scale)
            let visible: Bool = fillRatio >= fieldShapeMinimumRatio || edge >= fieldEdgeFraction
            lines.append("\u{201C}\(field.name)\u{201D} \(frame): fill \(fill) on page \(page), "
                         + String(format: "%.2f:1", fillRatio) + ", edge " + String(format: "%.0f%%", edge * 100)
                         + (visible ? ", visible" : ", NO SHAPE"))
            if !visible { invisible.append("\u{201C}\(field.name)\u{201D}") }
        }
        if checked == 0 && invisible.isEmpty {
            lines.append("NO FIELD WITHOUT THE FOCUS TO CHECK")
            return CheckResult(passed: false, lines: lines)
        }
        lines.append(invisible.isEmpty ? "FIELDS VISIBLE AT REST OK" : "FIELD WITHOUT A VISIBLE SHAPE AT REST: " + invisible.joined(separator: "; "))
        return CheckResult(passed: invisible.isEmpty, lines: lines)
    }

    /// The page colour around a field: outside its row when the row frame is known and larger than the field (left and right
    /// of the row first, then above and below), otherwise just above and below the field. Nil if nothing is on the picture.
    internal static func pageColour(_ image: RGBImage, field frame: AXRect, row: AXRect?, scale: Double) -> RGB? {
        if let row, row.width >= frame.width, row.height >= frame.height, row.height > frame.height || row.width > frame.width {
            let sides: [AXRect] = [
                AXRect(x: row.x - 10, y: row.y + 4, width: 6, height: max(1, row.height - 8)),
                AXRect(x: row.maxX + 4, y: row.y + 4, width: 6, height: max(1, row.height - 8)),
            ]
            if let colour = dominant(image, sides, scale: scale) { return colour }
            let ends: [AXRect] = [
                AXRect(x: row.x + 12, y: row.y - 10, width: max(1, row.width - 24), height: 6),
                AXRect(x: row.x + 12, y: row.maxY + 4, width: max(1, row.width - 24), height: 6),
            ]
            if let colour = dominant(image, ends, scale: scale) { return colour }
        }
        let outside: [AXRect] = [
            AXRect(x: frame.x + 12, y: frame.y - 10, width: frame.width - 24, height: 6),
            AXRect(x: frame.x + 12, y: frame.maxY + 4, width: frame.width - 24, height: 6),
        ]
        return dominant(image, outside, scale: scale)
    }

    /// The most common colour (16-level bins, averaged) of the pixels inside `rects` (points); nil if none is on the picture.
    internal static func dominant(_ image: RGBImage, _ rects: [AXRect], scale: Double) -> RGB? {
        var bins: [Int: [RGB]] = [:]
        for rect in rects {
            forEachPixel(image, rect, scale: scale) { (p: RGB) in
                bins[(Int(p.r) / 16) << 8 | (Int(p.g) / 16) << 4 | (Int(p.b) / 16), default: []].append(p)
            }
        }
        guard let biggest = bins.values.max(by: { $0.count < $1.count }) else { return nil }
        let n: Int = biggest.count
        return RGB(r: UInt8(biggest.reduce(0) { $0 + Int($1.r) } / n),
                   g: UInt8(biggest.reduce(0) { $0 + Int($1.g) } / n),
                   b: UInt8(biggest.reduce(0) { $0 + Int($1.b) } / n))
    }

    /// The share of a 3 pt ring along the inside of the frame's edge whose pixels differ from `page`.
    internal static func edgeFraction(_ image: RGBImage, frame: AXRect, page: RGB, scale: Double) -> Double {
        let ring: [AXRect] = [
            AXRect(x: frame.x, y: frame.y, width: frame.width, height: 3),
            AXRect(x: frame.x, y: frame.maxY - 3, width: frame.width, height: 3),
            AXRect(x: frame.x, y: frame.y + 3, width: 3, height: frame.height - 6),
            AXRect(x: frame.maxX - 3, y: frame.y + 3, width: 3, height: frame.height - 6),
        ]
        var total: Int = 0
        var differ: Int = 0
        for rect in ring {
            forEachPixel(image, rect, scale: scale) { (p: RGB) in
                total += 1
                if Contrast.ratio(p, page) >= fieldShapeMinimumRatio { differ += 1 }
            }
        }
        return total == 0 ? 0 : Double(differ) / Double(total)
    }

    private static func forEachPixel(_ image: RGBImage, _ rect: AXRect, scale: Double, _ body: (RGB) -> Void) {
        let x0: Int = max(0, Int((rect.x * scale).rounded(.down)))
        let y0: Int = max(0, Int((rect.y * scale).rounded(.down)))
        let x1: Int = min(image.width, Int((rect.maxX * scale).rounded(.up)))
        let y1: Int = min(image.height, Int((rect.maxY * scale).rounded(.up)))
        guard x1 > x0, y1 > y0 else { return }
        for y in y0..<y1 { for x in x0..<x1 { body(image.pixel(x, y)) } }
    }
}
