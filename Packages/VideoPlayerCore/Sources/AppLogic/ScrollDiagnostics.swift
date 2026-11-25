import Foundation

/// R471 (51), PROVISIONAL (owner 25 Nov 2026 Part B item 1): what the owner can photograph on the Apple TV, without a Mac,
/// when a Down press passes over rows or a page scrolls slowly. Kept in memory only (never saved, synced or backed up), and
/// with no titles: a focus step is a screen name of our own, a row and a column number and the page's scroll offset.

/// One move of the focus on a library grid or Home's shelves.
public struct FocusStep: Equatable, Sendable {
    /// Our own screen name ("Movies", "Shows", "Home", "Titles"), never a title of the owner's media.
    public let screen: String
    /// Row and column from 1 (on Home the row is the shelf, the featured area not counted).
    public let row: Int
    public let column: Int
    /// The page's vertical scroll offset at the move, in whole points.
    public let offset: Int

    public init(screen: String, row: Int, column: Int, offset: Int) {
        self.screen = screen
        self.row = row
        self.column = column
        self.offset = offset
    }

    /// Row and column of the card at `index` (from 0) in a grid of `columns` columns.
    public static func cell(index: Int, columns: Int) -> (row: Int, column: Int) {
        let across: Int = max(columns, 1)
        return (row: index / across + 1, column: index % across + 1)
    }
}

/// The last focus moves, newest last, at most `capacity`.
public struct FocusTrail: Equatable, Sendable {
    public static let capacity = 20
    public private(set) var steps: [FocusStep] = []

    public init() {}

    /// Adds a move. A repeat of the last one (the same card reported twice) is not added.
    public mutating func record(_ step: FocusStep) {
        if steps.last == step { return }
        steps.append(step)
        if steps.count > Self.capacity { steps.removeFirst(steps.count - Self.capacity) }
    }

    /// Rows passed over between a step and the one before it on the same screen: 0 for a move to the next row or along a row.
    public static func rowsPassedOver(from previous: FocusStep?, to step: FocusStep) -> Int {
        guard let previous, previous.screen == step.screen else { return 0 }
        return max(abs(step.row - previous.row) - 1, 0)
    }

    /// One row per move, newest first: label "Movies · Row 4, Column 2", value "Offset 1980 pt · 2 rows passed over".
    public var rows: [(label: String, value: String)] {
        steps.indices.reversed().map { (index: Int) -> (label: String, value: String) in
            let step: FocusStep = steps[index]
            let passed: Int = Self.rowsPassedOver(from: index > 0 ? steps[index - 1] : nil, to: step)
            var value = "Offset \(step.offset) pt"
            if passed > 0 { value += " · \(passed) \(passed == 1 ? "row" : "rows") passed over" }
            return (label: "\(step.screen) · Row \(step.row), Column \(step.column)", value: value)
        }
    }

    /// The rows as single lines ("label · value").
    public var lines: [String] { rows.map { "\($0.label) · \($0.value)" } }
}

/// Slow frames while a page scrolls, per screen: a frame counts as slow when it took longer than one and a half of the
/// display's frame time (at least one frame was dropped).
public struct SlowFrames: Equatable, Sendable {
    public struct Screen: Equatable, Sendable {
        public var frames: Int = 0
        public var slow: Int = 0
        /// The longest frame seen, in milliseconds.
        public var worstMilliseconds: Double = 0
    }

    public static let slowFactor = 1.5
    public private(set) var screens: [String: Screen] = [:]

    public init() {}

    /// One frame of `seconds` on a display whose frame time is `frameSeconds`.
    public mutating func record(screen: String, seconds: Double, frameSeconds: Double) {
        guard seconds > 0, frameSeconds > 0 else { return }
        var entry: Screen = screens[screen] ?? Screen()
        entry.frames += 1
        if seconds > frameSeconds * Self.slowFactor { entry.slow += 1 }
        entry.worstMilliseconds = max(entry.worstMilliseconds, seconds * 1000)
        screens[screen] = entry
    }

    /// Adds another count (one scroll's frames) to this one.
    public mutating func merge(_ other: SlowFrames) {
        for (name, add) in other.screens {
            var entry: Screen = screens[name] ?? Screen()
            entry.frames += add.frames
            entry.slow += add.slow
            entry.worstMilliseconds = max(entry.worstMilliseconds, add.worstMilliseconds)
            screens[name] = entry
        }
    }

    /// One row per screen, by name: label "Movies", value "12 slow of 840 frames, longest 48 ms".
    public var rows: [(label: String, value: String)] {
        screens.keys.sorted().map { (name: String) -> (label: String, value: String) in
            let entry: Screen = screens[name] ?? Screen()
            return (label: name, value: "\(entry.slow) slow of \(entry.frames) frames, longest \(Int(entry.worstMilliseconds.rounded())) ms")
        }
    }

    /// The rows as single lines ("label · value").
    public var lines: [String] { rows.map { "\($0.label) · \($0.value)" } }
}

/// Texts of the diagnostics section (Settings > Playback, under Last Playback Problem).
public enum ScrollDiagnosticsText {
    public static let focusSectionTitle = "Focus Moves"
    public static let focusNone = "No focus moves since the app opened."
    public static let focusFooter = "The last 20 moves on the library grids and Home's shelves, newest first. Kept until the app closes."
    public static let framesSectionTitle = "Scrolling Speed"
    public static let framesNone = "No scrolling measured since the app opened."
    public static let framesFooter = "Frames that took too long while a page scrolled, per screen. Kept until the app closes."
}
