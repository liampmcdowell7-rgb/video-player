#if DEBUG
import Foundation
import LibraryIndex

/// A fake synopsis and cast for the sample movies and shows (#21 D, #22 B), so the screenshot job can draw a movie or show page with its synopsis and
/// cast without any online key or network. Debug builds only (this whole file is inside `#if DEBUG`, and the app asks it only in
/// `-UITestFixtures` mode); the Release-string check (`VP_RELEASE_FORBIDDEN_RE`, scripts/ci-inspect-lib.sh) proves none of
/// this text ships. Invented text only: no real title, person or plot.
///
/// - Sample Movie 1, 3 and 5: a three-sentence synopsis and a short cast.
/// - Sample Movie 2: a full cast shelf (`TitleDetails.castLimit` people).
/// - Sample Movie 4: a very long synopsis (the three-line clamp and the "whole synopsis" sheet).
/// - Sample Movie 6 and 7: none (the page without synopsis or cast).
/// - Sample Show 1: the very long synopsis and a short cast; Sample Show 2: none (#22 B, the show page).
public enum UITestFixtureDetails {
    /// Marks every fake text so the Release-string check can find it.
    public static let marker = "Sample synopsis"

    static let short = "Sample synopsis: a fictional story made up for screenshots. A sample character travels to a sample town and meets "
        + "a sample friend. Nothing here describes a real film."

    static let long = "Sample synopsis: this is a deliberately long, invented text for the screenshot of a synopsis that does not fit "
        + "in three lines. " + String(repeating: "A sample character walks through a sample city, talks to sample people about "
        + "sample plans, changes those plans twice and then goes home again, which is all this placeholder needs to say. ", count: 6)
        + "It ends here, still describing no real film."

    static func cast(_ count: Int) -> [TitleDetails.CastMember] {
        (1...count).map { TitleDetails.CastMember(id: $0, name: "Sample Actor \($0)", role: $0 == 3 ? nil : "Sample Role \($0)") }
    }

    /// The fake details of a sample title, or nil (a page with neither synopsis nor cast).
    public static func details(forTitle title: String) -> TitleDetails? {
        switch title {
        case "Sample Movie 1", "Sample Movie 3", "Sample Movie 5": return TitleDetails(overview: short, cast: cast(6))
        case "Sample Movie 2": return TitleDetails(overview: short, cast: cast(TitleDetails.castLimit))
        case "Sample Movie 4": return TitleDetails(overview: long, cast: cast(4))
        // #22 B, the show page: Sample Show 1 has the very long synopsis and a cast, Sample Show 2 (the item with missing
        // data) has neither.
        case "Sample Show 1": return TitleDetails(overview: long, cast: cast(6))
        default: return nil
        }
    }

    /// The same for an artwork key, looked up in the library like the online path does: "item-42" for a movie (not an
    /// episode), "series-7" for a show (its title from its episodes).
    public static func details(key: String, store: any LibraryStore) async -> TitleDetails? {
        switch ArtworkKey(key) {
        case .item(let id)?:
            guard let item = try? await store.item(id: id), item.kind == .movie else { return nil }
            return details(forTitle: item.title)
        case .series(let seriesID)?:
            guard let first = try? await store.episodes(ofSeries: seriesID).first else { return nil }
            return details(forTitle: first.seriesTitle ?? first.title)
        default:
            return nil
        }
    }
}
#endif
