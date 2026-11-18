import Foundation

// UI-test launch modes (screenshots in CI, docs/GITHUB_ACTIONS_RUNBOOK.md). This file holds only the switch; the sample library
// itself (UITestFixtures.swift) is compiled only in debug builds (`#if DEBUG`), and the app reads the switch only inside
// `#if DEBUG`, so a Release build can neither turn it on nor contain the sample data (tested in UITestLaunchTests).

public enum UITestLaunch: Equatable, Sendable {
    /// Normal start.
    case off
    /// Start with an empty library and clean settings (no saved state from an earlier launch), no iCloud calls, no scan.
    case empty
    /// As `empty`, then fill the library with the synthetic sample library (no network).
    case fixtures

    public static let emptyArgument = "-UITestEmpty"
    public static let fixturesArgument = "-UITestFixtures"
    /// `-UITestTab <home|movies|shows|files|discover|search|settings>`: the tab selected at start.
    public static let tabArgument = "-UITestTab"
    /// `-UITestOpen <title>`: opens the detail page of the movie, or the page of the show, with exactly this title.
    public static let openArgument = "-UITestOpen"

    /// The mode the arguments ask for. Always `.off` when the build does not allow it (`buildAllowsUITestModes` is false in
    /// every Release build: the app passes `true` only inside `#if DEBUG`).
    public static func mode(arguments: [String], buildAllowsUITestModes: Bool) -> UITestLaunch {
        guard buildAllowsUITestModes else { return .off }
        if arguments.contains(fixturesArgument) { return .fixtures }
        if arguments.contains(emptyArgument) { return .empty }
        return .off
    }

    /// The value after `name` (`-UITestTab movies` gives "movies"), only when a UI-test mode is on.
    public static func value(of name: String, arguments: [String], mode: UITestLaunch) -> String? {
        guard mode != .off, let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        let value = arguments[index + 1]
        return value.hasPrefix("-") ? nil : value
    }
}
