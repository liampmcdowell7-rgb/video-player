import XCTest
import LibraryIndex
import Subtitles
@testable import AppLogic

/// R471 (38): the Audio and Subtitles rows of a title's actions menu.
final class ItemTrackMenuTests: XCTestCase {
    private let tracks = FileTrackDetails(frameRate: 24, audio: [
        .init(codec: "eac3", channels: 6, language: "eng", name: nil, isDefault: true),
        .init(codec: "aac", channels: 2, language: "fra", name: nil, isDefault: false),
        .init(codec: "aac", channels: 2, language: "eng", name: "Commentary", isDefault: false, isCommentary: true),
    ], subtitles: [
        .init(codec: "subrip", language: "eng", name: nil, isForced: false, isHearingImpaired: false),
        .init(codec: "subrip", language: "eng", name: nil, isForced: false, isHearingImpaired: true),
        .init(codec: "subrip", language: "fra", name: nil, isForced: true, isHearingImpaired: false),
    ])

    private func state(item: SeriesTrackChoice? = nil, series: SeriesTrackChoice? = nil, mode: SubtitleMode = .auto) -> ItemTrackMenuState {
        ItemTrackMenu.state(tracks: tracks, audioLanguage: LanguageTag("en"), subtitleLanguage: nil, mode: mode,
                            itemChoice: item, seriesChoice: series)
    }

    func testTheRowsListEveryTrackOfTheFileAndSubtitlesStartWithOff() {
        let s = state()
        XCTAssertEqual(s.audio.map(\.id), ["0", "1", "2"])
        XCTAssertEqual(s.subtitles.map(\.id), [TrackRow.offID, "0", "1", "2"])
        XCTAssertEqual(s.subtitles.first?.title, "Off")
        XCTAssertEqual(s.audio.filter(\.isSelected).count, 1, "one audio track is current")
        XCTAssertEqual(s.subtitles.filter(\.isSelected).count, 1, "one subtitle row is current (Off counts)")
    }

    func testTheDetailsSayWhatEachTrackIs() {
        let s = state()
        XCTAssertEqual(s.audio[2].detail?.contains("Commentary"), true)
        XCTAssertEqual(s.subtitles[2].detail, "SDH")
        XCTAssertEqual(s.subtitles[3].detail, "Forced")
        XCTAssertEqual(s.subtitles[1].detail, "SubRip (SRT)", "a plain track names its format")
    }

    func testTheValueIsTheCurrentLanguageOrOff() {
        let s = state(mode: .off)
        XCTAssertEqual(s.audioValue, s.audio.first(where: \.isSelected)?.title)
        XCTAssertEqual(s.subtitleValue, "Off")
    }

    func testAPickIsKeptForThisTitleAndWinsOverTheShowsChoice() throws {
        let before = state()
        let french = try XCTUnwrap(ItemTrackMenu.choosingAudio("1", tracks: tracks, current: before))
        XCTAssertEqual(french.audioLanguage?.language, LanguageTag("fra")?.language)
        let englishShow = SeriesTrackChoice(audioLanguage: LanguageTag("en"), audioChannels: 6)
        let after = state(item: french, series: englishShow)
        XCTAssertEqual(after.audio.first(where: \.isSelected)?.id, "1", "this title's own pick wins over the show's")
        XCTAssertEqual(ItemTrackMenu.startChoice(item: french, series: englishShow), french)
        XCTAssertEqual(ItemTrackMenu.startChoice(item: nil, series: englishShow), englishShow)
    }

    func testSubtitlesCanBeTurnedOnAndOff() throws {
        let on = try XCTUnwrap(ItemTrackMenu.choosingSubtitle("1", tracks: tracks, current: state()))
        XCTAssertTrue(on.subtitleIsSDH)
        XCTAssertEqual(state(item: on).subtitles.first(where: \.isSelected)?.id, "1")
        let off = try XCTUnwrap(ItemTrackMenu.choosingSubtitle(TrackRow.offID, tracks: tracks, current: state(item: on)))
        XCTAssertTrue(off.subtitlesOff)
        XCTAssertEqual(state(item: off).subtitleValue, "Off")
    }

    func testAnUnknownIdChangesNothing() {
        XCTAssertNil(ItemTrackMenu.choosingAudio("9", tracks: tracks, current: state()))
        XCTAssertNil(ItemTrackMenu.choosingSubtitle("9", tracks: tracks, current: state()))
    }

    func testTheKeyIsPerTitle() {
        XCTAssertNotEqual(ItemTrackMenu.storeKey(itemID: 1), ItemTrackMenu.storeKey(itemID: 2))
        XCTAssertNotEqual(ItemTrackMenu.storeKey(itemID: 1), StartTrackRules.rememberKey(seriesTitle: "1"))
    }

    func testTheRowsAreListedOnlyOnceTheTracksAreKnown() {
        for kind in [ProductActionContext.Kind.movie, .episode] {
            var c = ProductActionContext(kind: kind)
            c.hasFile = true
            XCTAssertFalse(ProductActions.list(c).contains(.audio), "\(kind)")
            c.hasTracks = true
            XCTAssertEqual(Array(ProductActions.list(c).prefix(2)), [.audio, .subtitles], "\(kind)")
        }
        var show = ProductActionContext(kind: .show)
        show.hasTracks = true
        XCTAssertFalse(ProductActions.list(show).contains(.audio), "a show has no file of its own")
        XCTAssertFalse(ProductActions.cardSupported.contains(.audio), "a card's long press cannot pick a track")
    }
}
