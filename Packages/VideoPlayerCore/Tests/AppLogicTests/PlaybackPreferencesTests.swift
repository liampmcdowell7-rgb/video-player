import XCTest
import VideoPlayerCore
import Subtitles
import UserData
@testable import LibraryIndex
@testable import AppLogic

/// R458 (commit B of R457): the rules behind the new Playback, Language, Audio, Library, source and General settings.
/// FIXTURE: synthetic tracks and files; nothing is read from a device.
final class PlaybackPreferencesTests: XCTestCase {
    private let en = LanguageTag("en")!, ja = LanguageTag("ja")!, de = LanguageTag("de")!

    private var audio: [AudioTrackInfo] {
        [AudioTrackInfo(id: "0", language: ja, codec: "", channels: 2, isDefault: true),
         AudioTrackInfo(id: "1", language: en, codec: "", channels: 2)]
    }
    private var subtitles: [SubtitleTrackInfo] {
        [SubtitleTrackInfo(id: "0", language: en, isForced: true),
         SubtitleTrackInfo(id: "1", language: en),
         SubtitleTrackInfo(id: "2", language: de)]
    }

    private func pick(audioLanguage: LanguageTag?, subtitleLanguage: LanguageTag?, mode: SubtitleMode, remembered: SeriesTrackChoice? = nil) -> TrackSelectionResult {
        TrackDefaults.select(audio: audio, subtitles: subtitles, originalLanguage: nil, audioLanguage: audioLanguage,
                             subtitleLanguage: subtitleLanguage, mode: mode, remembered: remembered)
    }

    // MARK: B1 language and subtitles

    func testTheAudioLanguageDefaultPicksThatTrack() {
        XCTAssertEqual(pick(audioLanguage: en, subtitleLanguage: en, mode: .auto).audioTrackID, "1")
        XCTAssertEqual(pick(audioLanguage: ja, subtitleLanguage: en, mode: .auto).audioTrackID, "0")
    }

    func testSubtitlesOffShowsNone() {
        XCTAssertNil(pick(audioLanguage: ja, subtitleLanguage: en, mode: .off).subtitleTrackID)
    }

    func testForcedOnlyShowsOnlyAForcedTrackInTheWishedLanguage() {
        XCTAssertEqual(pick(audioLanguage: ja, subtitleLanguage: en, mode: .forcedOnly).subtitleTrackID, "0")
        XCTAssertNil(pick(audioLanguage: ja, subtitleLanguage: de, mode: .forcedOnly).subtitleTrackID, "no forced German track")
    }

    func testAlwaysOnShowsAFullTrackEvenWithAudioInTheLanguage() {
        let result = pick(audioLanguage: en, subtitleLanguage: en, mode: .alwaysOn)
        XCTAssertEqual(result.subtitleTrackID, "1", "the full English track, not the forced one")
    }

    func testAShowsOwnChoiceBeatsEveryDefault() {
        let ownJapaneseNoSubtitles = SeriesTrackChoice(audioLanguage: ja, subtitlesOff: true)
        let result = pick(audioLanguage: en, subtitleLanguage: en, mode: .alwaysOn, remembered: ownJapaneseNoSubtitles)
        XCTAssertEqual(result.audioTrackID, "0")
        XCTAssertNil(result.subtitleTrackID)
    }

    func testEverythingOnAutoLeavesTheSystemsChoice() {
        XCTAssertTrue(StartTrackRules.usesSystemChoice(audio: nil, subtitleLanguage: nil, mode: .auto))
        XCTAssertTrue(StartTrackRules.usesSystemChoice(audio: "auto", subtitleLanguage: "auto", mode: .auto))
        XCTAssertFalse(StartTrackRules.usesSystemChoice(audio: "de", subtitleLanguage: "auto", mode: .auto))
        XCTAssertFalse(StartTrackRules.usesSystemChoice(audio: "auto", subtitleLanguage: "auto", mode: .forcedOnly))
    }

    func testAutoLanguageFollowsTheAppleTV() {
        XCTAssertEqual(TrackLanguageChoice.tag(stored: "auto", system: ["de-DE"])?.language, "de")
        XCTAssertEqual(TrackLanguageChoice.tag(stored: "fr", system: ["de-DE"])?.language, "fr")
    }

    func testTheShowsRememberedChoiceIsKeptPerShowOnThisDevice() {
        XCTAssertEqual(StartTrackRules.rememberKey(seriesTitle: " Show One "), "vp.trackChoice.show one")
        XCTAssertFalse(AppPreference.synced.contains { $0.hasPrefix("vp.trackChoice") })
    }

    // MARK: B3 resume, speed, inactivity

    func testResumePlaybackOffStartsAtTheBeginning() {
        XCTAssertEqual(ResumeRule.startPosition(saved: 600, watched: false, fromStart: false, resume: true), 600)
        XCTAssertEqual(ResumeRule.startPosition(saved: 600, watched: false, fromStart: false, resume: false), 0)
        XCTAssertEqual(ResumeRule.startPosition(saved: 600, watched: false, fromStart: true, resume: true), 0, "Start Over")
        XCTAssertEqual(ResumeRule.startPosition(saved: 600, watched: true, fromStart: false, resume: true), 0)
    }

    func testPlaybackSpeedChoices() {
        XCTAssertEqual(PlaybackSpeed.rate(nil), 1)
        XCTAssertEqual(PlaybackSpeed.rate("1.5"), 1.5)
        XCTAssertEqual(PlaybackSpeed.rate("9"), 1, "an unknown value is normal speed")
        XCTAssertEqual(PlaybackSpeed.title("1.0"), "Normal")
        XCTAssertEqual(PlaybackSpeed.title("2.0"), "2×")
    }

    func testTheInactivityCheckAsksAfterTheChosenNumberOfEpisodesInARow() {
        XCTAssertFalse(InactivityCheck.off.asks(episodesInARow: 50))
        XCTAssertFalse(InactivityCheck.after3.asks(episodesInARow: 2))
        XCTAssertTrue(InactivityCheck.after3.asks(episodesInARow: 3))
        XCTAssertEqual(InactivityCheck.allCases.map(\.title), ["Off", "After 2 Episodes", "After 3 Episodes", "After 4 Episodes"])
        XCTAssertEqual(InactivityCheck.default, .off)
        XCTAssertEqual(InactivityCheck.question, "Are you still watching?")
    }

    func testAPressStartsTheEpisodeCountAgain() {
        var run = EpisodeRun()
        run.episodeFinishedOnItsOwn(); run.episodeFinishedOnItsOwn()
        XCTAssertTrue(InactivityCheck.after2.asks(episodesInARow: run.count))
        run.personActed()
        XCTAssertFalse(InactivityCheck.after2.asks(episodesInARow: run.count))
    }

    // MARK: B6 versions

    private func file(_ id: Int64, height: Int?, bitrate: Int64? = nil, size: Int64? = nil, modified: Double) -> StoredFile {
        var tech = FileTechnicalInfo()
        tech.height = height
        tech.bitrate = bitrate
        return StoredFile(id: id, sourceID: "s", path: "/\(id).mkv", name: "\(id).mkv", parentPath: "/", kind: .video, size: size,
                          modified: Date(timeIntervalSince1970: modified), etag: nil, serverToken: nil, itemID: 1, technical: tech,
                          firstSeen: Date(timeIntervalSince1970: 0), versionLabel: nil)
    }

    func testPlayVersionForEveryChoice() {
        let files = [file(1, height: 1080, modified: 10), file(2, height: 2160, modified: 5), file(3, height: 720, modified: 20)]
        XCTAssertEqual(PlayVersion.pick(files, explicit: nil, mode: .auto)?.id, 1, "Auto: the first file")
        XCTAssertEqual(PlayVersion.pick(files, explicit: nil, mode: .highestQuality)?.id, 2)
        XCTAssertEqual(PlayVersion.pick(files, explicit: nil, mode: .mostRecent)?.id, 3)
        XCTAssertNil(PlayVersion.pick(files, explicit: nil, mode: .ask), "Ask: the page asks")
        for mode in PlayVersion.allCases {
            XCTAssertEqual(PlayVersion.pick(files, explicit: 3, mode: mode)?.id, 3, "a version chosen by hand always wins (\(mode))")
        }
    }

    func testOneFileNeverAsksAndEqualHeightsUseTheBitrateThenTheSize() {
        let one = [file(1, height: 1080, modified: 1)]
        XCTAssertEqual(PlayVersion.pick(one, explicit: nil, mode: .ask)?.id, 1)
        XCTAssertFalse(PlayVersion.asks(mode: .ask, versionCount: 1, hasExplicitChoice: false))
        let same = [file(1, height: 1080, bitrate: 5, modified: 1), file(2, height: 1080, bitrate: 9, modified: 1)]
        XCTAssertEqual(PlayVersion.pick(same, explicit: nil, mode: .highestQuality)?.id, 2)
        XCTAssertTrue(PlayVersion.asks(mode: .ask, versionCount: 2, hasExplicitChoice: false))
        XCTAssertFalse(PlayVersion.asks(mode: .ask, versionCount: 2, hasExplicitChoice: true))
        XCTAssertFalse(PlayVersion.asks(mode: .auto, versionCount: 2, hasExplicitChoice: false))
    }

    // MARK: B5 library and source

    private func definition(_ options: String = "") -> UDSourceDefinition {
        UDSourceDefinition(id: "a", kind: SourceKind.webdav.rawValue, name: "Disk", options: options)
    }

    func testHideRenameAndTheOtherOptionsOfASourceStayApart() {
        let hidden = HideSourceOption.setting(true, on: definition("sortByFilename=1"))
        XCTAssertTrue(HideSourceOption.isHidden(hidden))
        XCTAssertEqual(SourceOptions.parse(hidden.options)["sortByFilename"], "1", "the other options stay")
        XCTAssertFalse(HideSourceOption.isHidden(HideSourceOption.setting(false, on: hidden)))
        XCTAssertEqual(HideSourceOption.hiddenIDs([hidden, definition()]), ["a"])
        XCTAssertEqual(SourceRename.setting("  New Name ", on: definition()).name, "New Name")
        XCTAssertEqual(SourceRename.setting("   ", on: definition()).name, "Disk", "an empty name keeps the old one")
        XCTAssertTrue(ForgetSourceText.message(name: "Disk").contains("The files on the server are not touched."))
    }

    func testSpeedTestReadsAtMost8MBAndShowsMegabits() throws {
        XCTAssertEqual(SpeedTest.range(fileSize: 100_000_000), 0..<8_388_608)
        XCTAssertEqual(SpeedTest.range(fileSize: 1_000), 0..<1_000)
        XCTAssertNil(SpeedTest.range(fileSize: nil))
        XCTAssertNil(SpeedTest.range(fileSize: 0))
        XCTAssertEqual(try XCTUnwrap(SpeedTest.megabitsPerSecond(bytes: 12_500_000, seconds: 1)), 100, accuracy: 0.001)
        XCTAssertNil(SpeedTest.megabitsPerSecond(bytes: 10, seconds: 0))
        XCTAssertEqual(SpeedTest.text(94.26), "94.3 Mbps")
        XCTAssertEqual(SpeedTest.text(250.4), "250 Mbps")
        XCTAssertEqual(SpeedTest.text(nil), "No result")
    }

    func testRefreshMetadataNamesTheKeptAnswersOfOneOnlineIDInBothKinds() {
        XCTAssertEqual(MetadataRefresh.prefixes(tmdbIDs: [603, 12]), ["tmdb/movie/12/", "tmdb/tv/12/", "tmdb/movie/603/", "tmdb/tv/603/"])
        XCTAssertTrue(MetadataRefresh.prefixes(tmdbIDs: []).isEmpty)
    }

    func testLastScanSaysNeverOrTheTime() {
        XCTAssertEqual(LastScan.text(nil), "Never")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let text = LastScan.text(now.addingTimeInterval(-3_600), now: now, locale: Locale(identifier: "en_US"), calendar: calendar)
        XCTAssertTrue(text.hasPrefix("Today, "), text)
        XCTAssertFalse(LastScan.text(now.addingTimeInterval(-3 * 86_400), now: now, locale: Locale(identifier: "en_US"), calendar: calendar).hasPrefix("Today"))
    }

    // MARK: B7 metadata order

    func testPreferLocalMetadataOrdersTheLayersAndTheRating() {
        XCTAssertEqual(MetadataPrecedence.order(preferLocal: true), [.source, .wikidata, .tmdb])
        XCTAssertEqual(MetadataPrecedence.order(preferLocal: false), [.wikidata, .tmdb, .source])
        XCTAssertNotEqual(MetadataPrecedence.footer(preferLocal: true), MetadataPrecedence.footer(preferLocal: false))
    }

    private func details(_ overview: String?, rating: String?) -> TitleDetails {
        var d = TitleDetails(overview: overview, cast: [])
        d.contentRating = rating
        return d
    }

    func testEveryCombinationOfLocalAndOnlineLayers() {
        let local = details("From the file.", rating: "PG")
        let online = details("From online.", rating: "PG-13")
        // On: the layers are given source first, the rating follows source, then TMDB.
        let on = LayeredDetails.merge([(.source, local), (.tmdb, online)], preferLocal: true)
        XCTAssertEqual(on.details?.overview, "From the file.")
        XCTAssertEqual(on.details?.contentRating, "PG")
        // Off: the layers are given online first.
        let off = LayeredDetails.merge([(.tmdb, online), (.source, local)], preferLocal: false)
        XCTAssertEqual(off.details?.overview, "From online.")
        XCTAssertEqual(off.details?.contentRating, "PG-13")
        // Only one side has an answer: it is used in both orders.
        for prefer in [true, false] {
            XCTAssertEqual(LayeredDetails.merge([(.source, local), (.tmdb, nil)], preferLocal: prefer).details?.overview, "From the file.")
            XCTAssertEqual(LayeredDetails.merge([(.tmdb, online), (.source, nil)], preferLocal: prefer).details?.overview, "From online.")
        }
        // A rating only the source has, and a description only online: each fills its own gap in both orders.
        let ratingOnly = details(nil, rating: "R")
        let overviewOnly = details("Online text.", rating: nil)
        for prefer in [true, false] {
            let layers: [(DetailsLayer, TitleDetails?)] = prefer ? [(.source, ratingOnly), (.tmdb, overviewOnly)] : [(.tmdb, overviewOnly), (.source, ratingOnly)]
            let merged = LayeredDetails.merge(layers, preferLocal: prefer)
            XCTAssertEqual(merged.details?.overview, "Online text.")
            XCTAssertEqual(merged.details?.contentRating, "R")
        }
    }

    // MARK: B8 general, B4 audio

    func testThePosterCaptionIsTheTitleOrTheFileName() {
        XCTAssertEqual(PosterCaption.text(title: "Film", fileName: "Film.2001.mkv", showFilenames: true), "Film.2001.mkv")
        XCTAssertEqual(PosterCaption.text(title: "Film", fileName: "Film.2001.mkv", showFilenames: false), "Film")
        XCTAssertEqual(PosterCaption.text(title: "Film", fileName: nil, showFilenames: true), "Film", "no name known yet")
    }

    func testVolumeBoostLevelsAndDefault() {
        XCTAssertEqual(VolumeBoost.default, .off)
        XCTAssertEqual(VolumeBoost.off.factor, 1)
        XCTAssertEqual(VolumeBoost.low.factor, 1.4125, accuracy: 0.001)
        XCTAssertEqual(VolumeBoost.high.factor, 1.9953, accuracy: 0.001)
        XCTAssertEqual(VolumeBoost.stored("nonsense"), .off)
    }

    func testTheNewSettingsHaveTheirDefaultsAndTravelWithTheRest() {
        XCTAssertEqual(AppPreference.audioLanguage.defaultValue, .string("auto"))
        XCTAssertEqual(AppPreference.subtitleLanguage.defaultValue, .string("auto"))
        XCTAssertEqual(AppPreference.subtitleMode.defaultValue, .string("auto"))
        XCTAssertEqual(AppPreference.resumePlayback.defaultValue, .bool(true))
        XCTAssertEqual(AppPreference.playbackSpeed.defaultValue, .string("1.0"))
        XCTAssertEqual(AppPreference.inactivityCheck.defaultValue, .string("off"))
        XCTAssertEqual(AppPreference.playVersion.defaultValue, .string("auto"))
        XCTAssertEqual(AppPreference.volumeBoost.defaultValue, .string("off"))
        XCTAssertEqual(AppPreference.showPosterTitles.defaultValue, .bool(true))
        XCTAssertEqual(AppPreference.watchedIndicators.defaultValue, .bool(true))
        XCTAssertEqual(AppPreference.showFilenames.defaultValue, .bool(false))
        XCTAssertEqual(AppPreference.listView.defaultValue, .bool(false))
        XCTAssertEqual(AppPreference.preferLocalMetadata.defaultValue, .bool(true))
        for key in ["subtitleMode", "subtitleLanguage", "audioLanguage", "playVersion", "volumeBoost", "inactivityCheck", "playbackSpeed",
                    "resumePlayback", "showPosterTitles", "watchedIndicators", "showFilenames", "listView", "preferLocalMetadata"] {
            XCTAssertTrue(AppPreference.synced.contains(key), key)
        }
        // The stored defaults match the pure rules' own constants.
        XCTAssertEqual(SubtitleMode.key, AppPreference.subtitleMode.rawValue)
        XCTAssertEqual(PlaybackSpeed.key, AppPreference.playbackSpeed.rawValue)
        XCTAssertEqual(InactivityCheck.key, AppPreference.inactivityCheck.rawValue)
        XCTAssertEqual(PlayVersion.key, AppPreference.playVersion.rawValue)
        XCTAssertEqual(ResumeRule.key, AppPreference.resumePlayback.rawValue)
        XCTAssertEqual(TrackLanguageChoice.audioKey, AppPreference.audioLanguage.rawValue)
        XCTAssertEqual(TrackLanguageChoice.subtitleKey, AppPreference.subtitleLanguage.rawValue)
    }
}
