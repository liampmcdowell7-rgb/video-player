import Foundation
import MetadataOnline
import UserData

/// R471 (22), PROVISIONAL: a season's own text on the show page, above its episodes. The title is the user's edited season
/// title, else the season's online name, else the library's name for it ("Season 2", "Specials"). The synopsis is the user's
/// edited one, else the online one; none when neither holds text. Nothing of our own is written about a season.
public struct SeasonHeader: Equatable, Sendable {
    public var title: String
    public var overview: String?

    public init(title: String, overview: String?) {
        self.title = title
        self.overview = overview
    }

    public static func make(libraryTitle: String, online: SeasonMetadata?, edits: UDEditValues) -> SeasonHeader {
        let title: String = clean(edits[.title]?.text) ?? clean(online?.name) ?? libraryTitle
        let overview: String? = clean(edits[.overview]?.text) ?? clean(online?.overview)
        return SeasonHeader(title: title, overview: overview)
    }

    /// The header is drawn only when it says more than the season picker above it: a synopsis, a poster, or a title that
    /// differs from the library's name.
    public func isWorthShowing(libraryTitle: String, hasPoster: Bool) -> Bool {
        overview != nil || hasPoster || title != libraryTitle
    }

    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
