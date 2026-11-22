import Foundation

/// R388 (PROVISIONAL; owner's device test, item B: at launch the sidebar was expanded and the content started lower, and
/// the first row stayed lower after the sidebar collapsed). Two causes in our code, each fixed where it starts:
///
/// 1. The focus. Home's first frame is `LoadingView` (nothing focusable) while the library loads from the database, so
///    tvOS can only give the focus to the sidebar, which expands; nothing moved it to the page once the page was there.
///    Apple's TV app opens with the focus on Home's featured title. `LaunchFocus` lets Home's featured Play ask for the
///    focus ONCE, and only if the featured title appears soon after Home was first shown (`window`), so the focus never
///    jumps out of the sidebar later, after the person moved it there.
/// 2. The layout. Every launch scans the sources (`scanOnLaunch`), and while any scan ran Home put "Rebuilding your
///    library" ABOVE the page, pushing the featured area and the first row down for as long as the scan took.
///    `HomeScanNotice` shows that line only while Home has nothing to show (a first scan or a rebuilt library, which is what
///    its text describes); a scan under a library already on screen changes no layout, as in Apple's TV app.
public struct LaunchFocus: Equatable, Sendable {
    /// Seconds after Home was first shown during which the featured title may still take the focus. Our choice (Apple
    /// publishes none): long enough for the database to load, short enough that the person has not started moving.
    public static let window: TimeInterval = 10

    /// The uptime when Home was first shown; nil before.
    public private(set) var firstShown: TimeInterval?
    /// True once the one chance to claim the focus is used (claimed or let go).
    public private(set) var settled = false

    public init() {}

    /// Home appeared. Only the first call counts.
    public mutating func homeShown(at uptime: TimeInterval) {
        if firstShown == nil { firstShown = uptime }
    }

    /// The featured title appeared: true (move the focus to its Play) the first time only, and only within `window` of
    /// Home's first appearance. Any call after the first, and a call before Home was shown, is false.
    public mutating func claim(at uptime: TimeInterval) -> Bool {
        guard !settled, let first = firstShown else { return false }
        settled = true
        return uptime - first <= Self.window
    }
}

public enum HomeScanNotice {
    /// Whether Home shows the scanning line above its content: only while a scan runs AND Home has nothing to show.
    public static func shows(isScanning: Bool, hasContent: Bool) -> Bool {
        isScanning && !hasContent
    }
}
