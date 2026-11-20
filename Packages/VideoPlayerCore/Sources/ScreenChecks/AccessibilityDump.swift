import Foundation

/// #33 B and C: the checks of the screenshot UI tests as plain Swift, so the SAME code runs in the UI tests (the file is
/// compiled into the UI-test target by path, project.yml) and in Linux unit tests on the notes and pictures of a CI run
/// (Tests/ScreenChecksTests). Nothing here imports XCTest, UIKit or CoreGraphics.

/// A rectangle in points, as XCTest prints it: {{x, y}, {width, height}}.
public struct AXRect: Equatable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px < maxX && py >= y && py < maxY
    }

    /// The overlap of two rectangles (empty when they do not overlap).
    public func intersection(_ other: AXRect) -> AXRect {
        let left: Double = max(x, other.x)
        let top: Double = max(y, other.y)
        let right: Double = min(maxX, other.maxX)
        let bottom: Double = min(maxY, other.maxY)
        return AXRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
    }

    /// The rectangle grown by `amount` on every side.
    public func padded(by amount: Double) -> AXRect {
        AXRect(x: x - amount, y: y - amount, width: width + 2 * amount, height: height + 2 * amount)
    }

    public var description: String { "{{\(Self.format(x)), \(Self.format(y))}, {\(Self.format(width)), \(Self.format(height))}}" }

    static func format(_ value: Double) -> String { String(format: "%.1f", value) }
}

/// One element of an accessibility dump.
public struct AXNode: Sendable {
    public let type: String
    public let frame: AXRect?
    public let identifier: String
    public let label: String
    public let isFocused: Bool
    public let depth: Int
    public fileprivate(set) var parent: Int?
    public fileprivate(set) var children: [Int] = []
}

/// The element tree that `XCUIApplication.debugDescription` prints (and that the UI tests keep as "<name>-HIERARCHY"):
/// one element per line, indented by depth, "Type, 0xADDRESS, {{x, y}, {w, h}}, identifier: '…', label: '…', Focused".
/// Lines that are not elements ("Attributes:", "Element subtree:", query chains) are skipped.
public struct AccessibilityDump: Sendable {
    public private(set) var nodes: [AXNode] = []

    public init(_ text: String) {
        var stack: [(depth: Int, index: Int)] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let node = Self.parse(String(rawLine)) else { continue }
            while let last = stack.last, last.depth >= node.depth { stack.removeLast() }
            var element = node
            element.parent = stack.last?.index
            let index: Int = nodes.count
            nodes.append(element)
            if let parent = element.parent { nodes[parent].children.append(index) }
            stack.append((node.depth, index))
        }
    }

    private static let elementLine: NSRegularExpression = try! NSRegularExpression(pattern: "^( *)→?([A-Za-z]+)(?: \\([^)]*\\))?, 0x[0-9a-fA-F]+")
    private static let framePattern: NSRegularExpression = try! NSRegularExpression(pattern: "\\{\\{(-?[0-9.]+), (-?[0-9.]+)\\}, \\{(-?[0-9.]+), (-?[0-9.]+)\\}\\}")
    private static let identifierPattern: NSRegularExpression = try! NSRegularExpression(pattern: "identifier: '([^']*)'")
    private static let labelPattern: NSRegularExpression = try! NSRegularExpression(pattern: "label: '(.*?)'(?=, [A-Za-z]+: |, Focused|, Selected|, Disabled|$)")

    static func parse(_ line: String) -> AXNode? {
        let whole = NSRange(line.startIndex..., in: line)
        guard let head = elementLine.firstMatch(in: line, range: whole),
              let indentRange = Range(head.range(at: 1), in: line),
              let typeRange = Range(head.range(at: 2), in: line) else { return nil }
        var frame: AXRect?
        if let match = framePattern.firstMatch(in: line, range: whole) {
            let numbers: [Double] = (1...4).compactMap { (group: Int) -> Double? in
                guard let range = Range(match.range(at: group), in: line) else { return nil }
                return Double(line[range])
            }
            if numbers.count == 4 { frame = AXRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]) }
        }
        return AXNode(type: String(line[typeRange]), frame: frame,
                      identifier: capture(identifierPattern, in: line) ?? "",
                      label: capture(labelPattern, in: line) ?? "",
                      isFocused: line.hasSuffix(", Focused") || line.contains(", Focused,"),
                      depth: line[indentRange].count)
    }

    private static func capture(_ pattern: NSRegularExpression, in line: String) -> String? {
        guard let match = pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[range])
    }

    // MARK: Queries

    /// The first Window (the app's main window).
    public var window: Int? { nodes.firstIndex { $0.type == "Window" } }

    public func first(identifier: String) -> Int? { nodes.firstIndex { $0.identifier == identifier } }

    public func indices(identifier: String) -> [Int] { nodes.indices.filter { nodes[$0].identifier == identifier } }

    /// Parent, grandparent, … up to the root.
    public func ancestors(of index: Int) -> [Int] {
        var result: [Int] = []
        var current: Int? = nodes[index].parent
        while let value = current {
            result.append(value)
            current = nodes[value].parent
        }
        return result
    }

    /// Every element below `index`, depth first.
    public func descendants(of index: Int) -> [Int] {
        var result: [Int] = []
        var stack: [Int] = nodes[index].children.reversed()
        while let next = stack.popLast() {
            result.append(next)
            stack.append(contentsOf: nodes[next].children.reversed())
        }
        return result
    }

    /// The element's own label, or (tvOS menu items, list rows) the label of its first StaticText descendant: in the run of
    /// 20 Nov a menu item was a Cell with NO label, found only by "cells containing label == …" (#33 C).
    public func text(of index: Int) -> String {
        if !nodes[index].label.isEmpty { return nodes[index].label }
        for child in descendants(of: index) where nodes[child].type == "StaticText" && !nodes[child].label.isEmpty {
            return nodes[child].label
        }
        return ""
    }

    /// True when `index` lies inside the tab bar.
    public func isInTabBar(_ index: Int) -> Bool {
        nodes[index].type == "TabBar" || ancestors(of: index).contains { nodes[$0].type == "TabBar" }
    }

    /// The window's top-level subtrees. The page with its tab bar is one; a full-screen cover is a LATER one that does not
    /// hold the tab bar (notes 10-add-source-types-HIERARCHY and 74-file-details-HIERARCHY of the run of 20 Nov). #33 B (2):
    /// once the page is hidden from accessibility the cover may be the ONLY subtree; a lone subtree without a tab bar is
    /// then the cover (a page always holds the tab bar).
    public var coverRoot: Int? {
        guard let window else { return nil }
        let top: [Int] = nodes[window].children
        let withoutTabBar: (Int) -> Bool = { (root: Int) -> Bool in
            !self.descendants(of: root).contains { self.nodes[$0].type == "TabBar" }
        }
        if top.count == 1 { return withoutTabBar(top[0]) ? top[0] : nil }
        return top.dropFirst().last(where: withoutTabBar)
    }

    /// The top-level subtree with the tab bar and the page (the content behind a cover).
    public var pageRoot: Int? {
        guard let window else { return nil }
        return nodes[window].children.first { (root: Int) -> Bool in
            descendants(of: root).contains { nodes[$0].type == "TabBar" }
        } ?? nodes[window].children.first
    }

    /// Frames of the text-carrying elements below `root` (static texts, fields, images), outside the tab bar.
    public func textFrames(under root: Int) -> [AXRect] {
        let kinds: Set<String> = ["StaticText", "TextField", "SecureTextField", "Image"]
        return descendants(of: root).compactMap { (index: Int) -> AXRect? in
            let node: AXNode = nodes[index]
            guard kinds.contains(node.type), !isInTabBar(index), let frame = node.frame, !frame.isEmpty else { return nil }
            return frame
        }
    }
}
