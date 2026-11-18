#if DEBUG
import Foundation

// UI-test launch modes (screenshots in CI, docs/GITHUB_ACTIONS_RUNBOOK.md). Debug builds only: this whole file is inside
// `#if DEBUG`, like the sample library (UITestFixtures.swift) and the app's UITestMode.swift, so a Release build neither
// contains the launch-argument texts nor can turn a mode on (UITestLaunchTests reads the guard; the device-build inspection
// script searches the Release binary for the texts, fourth CI run finding).

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
    /// `-UITestTextSize <name>`: draws the app at this text size (rule 17, Larger Text), one of `textSizes`. Only the app's
    /// own SwiftUI views follow it; the simulator's system setting is not changed.
    public static let textSizeArgument = "-UITestTextSize"
    /// `-UITestBoldText`: draws the app's text bold (rule 17, Bold Text), as the system Bold Text setting would.
    public static let boldTextArgument = "-UITestBoldText"
    /// The sizes `-UITestTextSize` accepts: the larger standard sizes and the accessibility sizes (SwiftUI `DynamicTypeSize`).
    public static let textSizes = ["xLarge", "xxLarge", "xxxLarge", "accessibility1", "accessibility2", "accessibility3",
                                   "accessibility4", "accessibility5"]

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

    /// The text size asked for with `-UITestTextSize`, only when it is one of `textSizes` and a UI-test mode is on.
    public static func textSize(arguments: [String], mode: UITestLaunch) -> String? {
        guard let name = value(of: textSizeArgument, arguments: arguments, mode: mode), textSizes.contains(name) else { return nil }
        return name
    }

    /// True when `-UITestBoldText` is given and a UI-test mode is on.
    public static func boldText(arguments: [String], mode: UITestLaunch) -> Bool {
        mode != .off && arguments.contains(boldTextArgument)
    }
}
#endif
