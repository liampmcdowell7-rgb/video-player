import XCTest
import Subtitles
import PlaybackStatus
@testable import AppLogic

final class TrackPickerTests: XCTestCase {
    private let en = LanguageTag(language: "en")
    private let ja = LanguageTag(language: "ja")

    private var audio: [AudioTrackInfo] {
        [
            AudioTrackInfo(id: "a1", language: en, codec: "E-AC-3", channels: 6, isAtmos: true, isDefault: true),
            AudioTrackInfo(id: "a2", language: ja, codec: "TrueHD", channels: 8),
            AudioTrackInfo(id: "a3", language: en, codec: "AC-3", channels: 2, isCommentary: true),
        ]
    }
    private var subs: [SubtitleTrackInfo] {
        [
            SubtitleTrackInfo(id: "s1", language: en, codec: "subrip", isExternal: true),
            SubtitleTrackInfo(id: "s2", language: en, codec: "hdmv_pgs_subtitle", isForced: true),
            SubtitleTrackInfo(id: "s3", language: ja, codec: "ass", isSDH: true),
        ]
    }
    private func model(remembered: SeriesTrackChoice? = nil) -> TrackPickerModel {
        TrackPickerModel(audio: audio, subtitles: subs, originalLanguage: ja,
                         preferences: TrackPreferences(preferredAudioLanguages: [en]), remembered: remembered)
    }

    func testAudioPickerListsEveryTrackWithLanguageContentAndBadges() {
        let m = model()
        let p = m.audioPicker
        XCTAssertEqual(p.title, "Audio")
        XCTAssertEqual(p.rows.map(\.id), ["a1", "a2", "a3"])
        XCTAssertEqual(p.rows.map(\.title), ["English", "Japanese", "English"])
        XCTAssertTrue(p.rows[0].subtitle?.contains("Atmos") == true, p.rows[0].subtitle ?? "nil")
        XCTAssertEqual(p.rows[0].badges, ["Default"])
        XCTAssertEqual(p.rows[2].badges, ["Commentary"])
        XCTAssertEqual(p.rows.filter(\.isSelected).count, 1, "exactly one row is selected")
        XCTAssertEqual(p.selectedRow?.id, m.selectedAudioID)
        XCTAssertEqual(p.selectedRow?.id, "a1", "English is wished and Atmos is preferred")
    }

    func testSubtitlePickerHasOffFirstAndGroupsEmbeddedFromExternal() {
        let m = model()
        let p = m.subtitlePicker
        XCTAssertEqual(p.title, "Subtitles")
        XCTAssertEqual(p.sections.map(\.title), [nil, "In the File", "External Files"])
        XCTAssertEqual(p.sections[0].rows.map(\.id), [TrackRow.offID])
        XCTAssertTrue(p.sections[0].rows[0].isOff)
        XCTAssertEqual(p.sections[1].rows.map(\.id), ["s2", "s3"])
        XCTAssertEqual(p.sections[2].rows.map(\.id), ["s1"])
        XCTAssertEqual(p.sections[1].rows[0].subtitle, "PGS (picture)")
        XCTAssertEqual(p.sections[1].rows[0].badges, ["Forced"])
        XCTAssertEqual(p.sections[1].rows[1].badges, ["SDH"])
        XCTAssertEqual(p.sections[2].rows[0].subtitle, "SubRip (SRT)")
        XCTAssertEqual(p.rows.filter(\.isSelected).count, 1)
    }

    func testPickingAudioChangesTheSelectionAndProducesTheChoiceToRemember() throws {
        var m = model()
        let change = try XCTUnwrap(m.selectAudio(id: "a2"))
        XCTAssertEqual(change.kind, .audio)
        XCTAssertEqual(change.trackID, "a2")
        XCTAssertEqual(change.remember.audioLanguage, ja)
        XCTAssertEqual(m.audioPicker.selectedRow?.id, "a2")
        XCTAssertNil(m.audioPicker.reason, "a manual pick has no 'because' sentence")
        XCTAssertNil(m.selectAudio(id: "nope"))
        XCTAssertEqual(m.selectedAudioID, "a2", "unknown ids change nothing")
    }

    func testPickingSubtitlesAndOff() throws {
        var m = model()
        let on = try XCTUnwrap(m.selectSubtitle(id: "s3"))
        XCTAssertEqual(on.kind, .subtitle)
        XCTAssertEqual(on.trackID, "s3")
        XCTAssertFalse(on.remember.subtitlesOff)
        XCTAssertEqual(m.subtitlePicker.selectedRow?.id, "s3")
        let off = try XCTUnwrap(m.selectSubtitle(id: TrackRow.offID))
        XCTAssertNil(off.trackID)
        XCTAssertTrue(off.remember.subtitlesOff)
        XCTAssertEqual(m.subtitlePicker.selectedRow?.id, TrackRow.offID)
        XCTAssertNil(m.selectedSubtitleID)
        XCTAssertNil(m.selectSubtitle(id: "nope"))
        XCTAssertNil(m.selectedSubtitleID, "unknown ids change nothing")
    }

    func testTheRememberedChoiceDecidesTheNextEpisode() throws {
        var first = model()
        let change = try XCTUnwrap(first.selectAudio(id: "a2"))
        let next = model(remembered: change.remember)
        XCTAssertEqual(next.selectedAudioID, "a2", "same language as last time")
    }

    func testDelayStepsAreFiftyMillisecondsClampedAndResettable() {
        var m = model()
        XCTAssertEqual(m.audioPicker.sync.valueText, "0 ms")
        XCTAssertFalse(m.audioPicker.sync.canReset)
        XCTAssertEqual(m.stepAudioDelay(5), 0.25, accuracy: 1e-9)
        XCTAssertEqual(m.audioPicker.sync.valueText, "+250 ms")
        XCTAssertTrue(m.audioPicker.sync.canReset)
        XCTAssertEqual(m.stepAudioDelay(-8), -0.15, accuracy: 1e-9)
        XCTAssertEqual(m.audioPicker.sync.valueText, "-150 ms")
        for _ in 0..<400 { m.stepSubtitleDelay(1) }
        XCTAssertEqual(m.subtitleDelay, SyncModel.maxUserDelay, accuracy: 1e-9)
        XCTAssertFalse(m.subtitlePicker.sync.canIncrease)
        XCTAssertTrue(m.subtitlePicker.sync.canDecrease)
        for _ in 0..<800 { m.stepSubtitleDelay(-1) }
        XCTAssertEqual(m.subtitleDelay, -SyncModel.maxUserDelay, accuracy: 1e-9)
        XCTAssertFalse(m.subtitlePicker.sync.canDecrease)
        m.resetSubtitleDelay()
        m.resetAudioDelay()
        XCTAssertEqual(m.subtitleDelay, 0)
        XCTAssertEqual(m.audioDelay, 0)
        XCTAssertEqual(m.audioPicker.sync.label, "Audio Delay")
        XCTAssertEqual(m.subtitlePicker.sync.label, "Subtitle Delay")
    }

    func testDelayTextFormats() {
        XCTAssertEqual(TrackPickerModel.delayText(0), "0 ms")
        XCTAssertEqual(TrackPickerModel.delayText(0.25), "+250 ms")
        XCTAssertEqual(TrackPickerModel.delayText(-0.05), "-50 ms")
        XCTAssertEqual(TrackPickerModel.delayText(1), "+1 s")
        XCTAssertEqual(TrackPickerModel.delayText(-1.5), "-1.5 s")
        XCTAssertEqual(TrackPickerModel.delayText(2.25), "+2.25 s")
    }

    func testStartingDelaysAreClamped() {
        let m = TrackPickerModel(audio: audio, subtitles: [], originalLanguage: nil, preferences: TrackPreferences(),
                                 audioDelay: 99, subtitleDelay: -99)
        XCTAssertEqual(m.audioDelay, SyncModel.maxUserDelay, accuracy: 1e-9)
        XCTAssertEqual(m.subtitleDelay, -SyncModel.maxUserDelay, accuracy: 1e-9)
    }

    func testAFileWithNoTracksStillGivesUsablePickers() {
        let m = TrackPickerModel(audio: [], subtitles: [], originalLanguage: nil, preferences: TrackPreferences())
        XCTAssertTrue(m.audioPicker.sections.isEmpty)
        XCTAssertNil(m.audioPicker.selectedRow)
        XCTAssertEqual(m.subtitlePicker.rows.map(\.id), [TrackRow.offID])
        XCTAssertTrue(m.subtitlePicker.rows[0].isSelected)
    }

    func testUnknownCodecsAndLanguagesGetPlainFallbacks() {
        let odd = AudioTrackInfo(id: "x", language: nil, codec: "Speex", channels: 2)
        XCTAssertEqual(TrackLabels.language(nil), "Unknown language")
        XCTAssertTrue(TrackLabels.audioDescription(odd).hasPrefix("Speex"))
        XCTAssertNil(TrackLabels.audioKind(of: "speex"))
        // Vorbis is decoded now (docs/AUDIO_PIPELINE.md), so it has a kind of its own.
        XCTAssertEqual(TrackLabels.audioKind(of: "vorbis"), .vorbis)
        XCTAssertEqual(TrackLabels.audioKind(of: "DTS-HD HRA"), .dtsHDHRA)
        XCTAssertEqual(TrackLabels.audioKind(of: "E-AC-3"), .eac3)
        XCTAssertEqual(TrackLabels.audioKind(of: "DTS-HD MA"), .dtsHDMA)
        XCTAssertEqual(TrackLabels.audioKind(of: "TrueHD"), .trueHD)
        XCTAssertNil(TrackLabels.subtitleFormat(""))
        XCTAssertEqual(TrackLabels.subtitleFormat("dvdsub"), "VobSub (picture)")
        XCTAssertEqual(TrackLabels.subtitleFormat("weird"), "WEIRD")
    }
}
