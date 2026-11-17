import Foundation

// Small types every screen's view model shares. Pure Swift, Foundation only, Sendable. The SwiftUI views in the
// app target only read these and call the view models' methods.

/// Shown instead of content when a screen has nothing to list. Text is final user-facing wording (docs/HIG_AUDIT.md:
/// plain, no jargon, says what to do).
public struct EmptyState: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        /// No source has been added yet.
        case noSources
        /// Sources exist but nothing is indexed yet (first scan not finished, or nothing matched).
        case nothingIndexed
        /// A filter or search matches nothing.
        case noMatches
        /// A folder with no entries.
        case emptyFolder
        /// The search field is empty (nothing was searched yet).
        case noQuery
    }
    public var reason: Reason
    public var title: String
    public var message: String
    /// Label of the one button to offer, if any ("Add a Source", "Clear Filters").
    public var actionTitle: String?

    public init(reason: Reason, title: String, message: String, actionTitle: String? = nil) {
        self.reason = reason
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
    }
}

public struct ErrorState: Equatable, Sendable {
    public var title: String
    public var message: String
    public var retryTitle: String

    public init(title: String, message: String, retryTitle: String = "Try Again") {
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
    }

    /// Turns any thrown error into one calm sentence (no type names, no codes).
    public static func from(_ error: Error, doing what: String) -> ErrorState {
        let detail = (error as? LocalizedError)?.errorDescription
        let message = detail.map { "\($0)" } ?? "Something went wrong. Check the connection and try again."
        return ErrorState(title: "Couldn’t \(what)", message: message)
    }
}

/// What a screen shows right now. A screen is in exactly one of these.
public enum ViewState<Content: Equatable & Sendable>: Equatable, Sendable {
    /// Nothing requested yet.
    case idle
    case loading
    case loaded(Content)
    case empty(EmptyState)
    case failed(ErrorState)

    public var content: Content? {
        if case .loaded(let c) = self { return c }
        return nil
    }
    public var isLoading: Bool { if case .loading = self { return true } else { return false } }
}

/// Text helpers shared by the view models (kept in one place so wording is consistent and testable).
public enum DisplayText {
    /// "41 min left", "1 h 5 min left", "Less than a minute left". `seconds` is what remains.
    public static func remaining(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "Finished" }
        if seconds < 60 { return "Less than a minute left" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "\(minutes) min left" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h left" : "\(h) h \(m) min left"
    }

    /// "1 h 52 min", "41 min".
    public static func runtime(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(max(minutes, 1)) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// "S2 E5", or "S1 E1-E2" for a double episode.
    public static func episodeCode(season: Int?, episode: Int?, episodeEnd: Int? = nil) -> String? {
        guard let season, let episode else { return nil }
        if let end = episodeEnd, end > episode { return "S\(season) E\(episode)-E\(end)" }
        return "S\(season) E\(episode)"
    }

    /// "12.4 MB", "3.1 GB". Decimal units, like Finder and the Apple TV settings.
    public static func fileSize(_ bytes: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var value = Double(max(bytes, 0))
        var unit = 0
        while value >= 1000, unit < units.count - 1 { value /= 1000; unit += 1 }
        if unit == 0 { return "\(Int(value)) bytes" }
        return String(format: "%.1f", value) + " " + units[unit]
    }

    /// "1 second", "7 seconds".
    public static func seconds(_ n: Int) -> String { n == 1 ? "1 second" : "\(n) seconds" }
}
