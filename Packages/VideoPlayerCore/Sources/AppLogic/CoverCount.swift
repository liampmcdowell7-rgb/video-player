/// R362 (compile run of 21 Nov 2026, item 10; made testable by R378): the count of open task covers that the app's one
/// `CoverPresence` (App/Shared/SettingsPane.swift) keeps. Every cover adds one when it appears and takes one away when it
/// disappears; the page behind is hidden from accessibility while the count is above zero. Never below zero, so a
/// disappear without a matching appear cannot leave the page hidden for good.
public struct CoverCount: Equatable, Sendable {
    public private(set) var open: Int = 0

    public init() {}

    /// True while at least one cover is open.
    public var isCovered: Bool { open > 0 }

    public mutating func opened() { open += 1 }

    public mutating func closed() { open = max(0, open - 1) }
}
