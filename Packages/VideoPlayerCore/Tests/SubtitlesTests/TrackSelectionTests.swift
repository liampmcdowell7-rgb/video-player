import XCTest
@testable import Subtitles

final class TrackSelectionTests: XCTestCase {

    private func L(_ s: String) -> LanguageTag { LanguageTag(language: s) }

    private func a(_ id: String, _ lang: String?, ch: Int = 2, codec: String = "AAC", atmos: Bool = false, def: Bool = false, commentary: Bool = false, ad: Bool = false) -> AudioTrackInfo {
        AudioTrackInfo(id: id, language: lang.map(L), codec: codec, channels: ch, isAtmos: atmos, isDefault: def, isCommentary: commentary, isAudioDescription: ad)
    }

    private func s(_ id: String, _ lang: String?, forced: Bool = false, def: Bool = false, sdh: Bool = false, commentary: Bool = false) -> SubtitleTrackInfo {
        SubtitleTrackInfo(id: id, language: lang.map(L), isForced: forced, isDefault: def, isSDH: sdh, isCommentary: commentary)
    }

    private struct Case {
        var name: String
        var audio: [AudioTrackInfo]
        var subs: [SubtitleTrackInfo]
        var original: String?
        var prefs: TrackPreferences
        var remembered: SeriesTrackChoice? = nil
        var wantAudio: String?
        var wantSub: String?
        /// Words that must appear (case-insensitive) in the audio / subtitle reason.
        var audioWords: [String] = []
        var subWords: [String] = []
    }

    private func prefs(audio: [String] = [], subs: [String] = [], original: Bool = false, highest: Bool = true, atmos: Bool = true, sdh: SDHPreference = .noPreference, always: Bool = false) -> TrackPreferences {
        TrackPreferences(
            preferredAudioLanguages: audio.map(L), preferredSubtitleLanguages: subs.map(L),
            originalLanguagePlusForcedSubtitles: original, preferHighestChannelCount: highest, preferAtmos: atmos,
            sdh: sdh, alwaysShowSubtitles: always
        )
    }

    func testSelectionTable() {
        let cases: [Case] = [
            Case(
                name: "anime: Japanese audio with forced English signs, original-language mode",
                audio: [a("a1", "en", ch: 2), a("a2", "ja", ch: 2)],
                subs: [s("s1", "en"), s("s2", "en", forced: true)],
                original: "ja", prefs: prefs(audio: ["en"], subs: ["en"], original: true),
                wantAudio: "a2", wantSub: "s2", audioWords: ["original"], subWords: ["forced"]
            ),
            Case(
                name: "anime: original-language mode, no forced track in the file, subtitles stay off",
                audio: [a("a1", "ja")], subs: [s("s1", "en")],
                original: "ja", prefs: prefs(audio: ["en"], original: true),
                wantAudio: "a1", wantSub: nil, subWords: ["off"]
            ),
            Case(
                name: "anime: Japanese audio wanted with full English subtitles (always show)",
                audio: [a("a1", "ja")], subs: [s("s1", "en", forced: true), s("s2", "en")],
                original: "ja", prefs: prefs(audio: ["ja"], subs: ["en"], always: true),
                wantAudio: "a1", wantSub: "s2", subWords: ["always"]
            ),
            Case(
                name: "foreign film: French audio only, English wished, full track beats forced",
                audio: [a("a1", "fr", ch: 6)],
                subs: [s("s1", "en", forced: true), s("s2", "fr"), s("s3", "en")],
                original: "fr", prefs: prefs(audio: ["en"], subs: ["en"]),
                wantAudio: "a1", wantSub: "s3", audioWords: ["none of your preferred"], subWords: ["not in your languages"]
            ),
            Case(
                name: "foreign film: the first wished subtitle language that exists is used",
                audio: [a("a1", "fr")], subs: [s("s1", "de"), s("s2", "es")],
                original: "fr", prefs: prefs(audio: ["en"], subs: ["es", "de"]),
                wantAudio: "a1", wantSub: "s2"
            ),
            Case(
                name: "English film with English audio: subtitles off",
                audio: [a("a1", "en", ch: 6)], subs: [s("s1", "en"), s("s2", "es")],
                original: "en", prefs: prefs(audio: ["en"], subs: ["en"]),
                wantAudio: "a1", wantSub: nil, subWords: ["off"]
            ),
            Case(
                name: "English audio and a forced English track: forced one shows",
                audio: [a("a1", "en")], subs: [s("s1", "en"), s("s2", "en", forced: true)],
                original: "en", prefs: prefs(audio: ["en"], subs: ["en"]),
                wantAudio: "a1", wantSub: "s2", subWords: ["forced"]
            ),
            Case(
                name: "commentary track is skipped even when it is the file's default",
                audio: [a("a1", "en", ch: 2, def: true, commentary: true), a("a2", "en", ch: 6)],
                subs: [], original: "en", prefs: prefs(audio: ["en"]),
                wantAudio: "a2", wantSub: nil
            ),
            Case(
                name: "audio description track is skipped when a regular track exists",
                audio: [a("a1", "en", ch: 6, ad: true), a("a2", "en", ch: 2)],
                subs: [], original: "en", prefs: prefs(audio: ["en"]),
                wantAudio: "a2", wantSub: nil
            ),
            Case(
                name: "audio description is used when it is the only audio",
                audio: [a("a1", "en", ch: 2, ad: true)],
                subs: [], original: "en", prefs: prefs(audio: ["en"]),
                wantAudio: "a1", wantSub: nil
            ),
            Case(
                name: "commentary subtitle track is never picked",
                audio: [a("a1", "fr")], subs: [s("s1", "en", commentary: true), s("s2", "en")],
                original: "fr", prefs: prefs(audio: ["en"], subs: ["en"]),
                wantAudio: "a1", wantSub: "s2"
            ),
            Case(
                name: "several English tracks: the most channels win",
                audio: [a("a1", "en", ch: 2, def: true), a("a2", "en", ch: 8, codec: "DTS-HD MA"), a("a3", "en", ch: 6)],
                subs: [], original: "en", prefs: prefs(audio: ["en"]),
                wantAudio: "a2", wantSub: nil, audioWords: ["7.1"]
            ),
            Case(
                name: "channel count switched off: the file's default track wins",
                audio: [a("a1", "en", ch: 2, def: true), a("a2", "en", ch: 8)],
                subs: [], original: "en", prefs: prefs(audio: ["en"], highest: false),
                wantAudio: "a1", wantSub: nil
            ),
            Case(
                name: "Atmos (5.1 bed) beats 7.1 DTS-HD when Atmos is wanted",
                audio: [a("a1", "en", ch: 8, codec: "DTS-HD MA"), a("a2", "en", ch: 6, codec: "E-AC-3", atmos: true)],
                subs: [], original: "en", prefs: prefs(audio: ["en"]),
                wantAudio: "a2", wantSub: nil, audioWords: ["atmos"]
            ),
            Case(
                name: "Atmos switched off: 7.1 DTS-HD wins on channels",
                audio: [a("a1", "en", ch: 6, codec: "E-AC-3", atmos: true), a("a2", "en", ch: 8, codec: "DTS-HD MA")],
                subs: [], original: "en", prefs: prefs(audio: ["en"], atmos: false),
                wantAudio: "a2", wantSub: nil
            ),
            Case(
                name: "SDH preferred: the SDH track is chosen",
                audio: [a("a1", "fr")], subs: [s("s1", "en"), s("s2", "en", sdh: true)],
                original: "fr", prefs: prefs(audio: ["en"], subs: ["en"], sdh: .prefer),
                wantAudio: "a1", wantSub: "s2", subWords: ["sdh"]
            ),
            Case(
                name: "SDH avoided: the plain track is chosen even if SDH comes first",
                audio: [a("a1", "fr")], subs: [s("s1", "en", sdh: true), s("s2", "en")],
                original: "fr", prefs: prefs(audio: ["en"], subs: ["en"], sdh: .avoid),
                wantAudio: "a1", wantSub: "s2", subWords: ["not sdh"]
            ),
            Case(
                name: "SDH avoided but only an SDH track exists: it is used",
                audio: [a("a1", "fr")], subs: [s("s1", "en", sdh: true)],
                original: "fr", prefs: prefs(audio: ["en"], subs: ["en"], sdh: .avoid),
                wantAudio: "a1", wantSub: "s1"
            ),
            Case(
                name: "SDH no preference: the file's default flag decides, then order",
                audio: [a("a1", "fr")], subs: [s("s1", "en"), s("s2", "en", def: true, sdh: true)],
                original: "fr", prefs: prefs(audio: ["en"], subs: ["en"]),
                wantAudio: "a1", wantSub: "s2"
            ),
            Case(
                name: "no preferred language in the file: the default audio track is used",
                audio: [a("a1", "fr"), a("a2", "es", def: true)],
                subs: [], original: "fr", prefs: prefs(audio: ["de"]),
                wantAudio: "a2", wantSub: nil, audioWords: ["default"]
            ),
            Case(
                name: "no preferred language and no default: the first track is used",
                audio: [a("a1", "fr"), a("a2", "es")],
                subs: [], original: nil, prefs: prefs(audio: ["de"]),
                wantAudio: "a1", wantSub: nil, audioWords: ["first"]
            ),
            Case(
                name: "no wishes at all: first audio track, subtitles off",
                audio: [a("a1", "ja"), a("a2", "en")], subs: [s("s1", "en")],
                original: "ja", prefs: prefs(),
                wantAudio: "a1", wantSub: nil
            ),
            Case(
                name: "preferred languages are tried in order",
                audio: [a("a1", "de"), a("a2", "es"), a("a3", "fr")],
                subs: [], original: nil, prefs: prefs(audio: ["fr", "es"]),
                wantAudio: "a3", wantSub: nil
            ),
            Case(
                name: "audio language unknown counts as understood: no full subtitles",
                audio: [a("a1", nil)], subs: [s("s1", "en")],
                original: nil, prefs: prefs(audio: ["en"], subs: ["en"]),
                wantAudio: "a1", wantSub: nil
            ),
            Case(
                name: "foreign audio and no subtitle in a wished language: off with a reason",
                audio: [a("a1", "ja")], subs: [s("s1", "ko")],
                original: "ja", prefs: prefs(audio: ["en"], subs: ["en"]),
                wantAudio: "a1", wantSub: nil, subWords: ["no subtitles in your languages"]
            ),
            Case(
                name: "foreign audio with only a forced track in a wished language: forced as last resort",
                audio: [a("a1", "ja")], subs: [s("s1", "en", forced: true)],
                original: "ja", prefs: prefs(audio: ["en"], subs: ["en"]),
                wantAudio: "a1", wantSub: "s1"
            ),
            Case(
                name: "no tracks at all",
                audio: [], subs: [], original: nil, prefs: prefs(audio: ["en"]),
                wantAudio: nil, wantSub: nil, audioWords: ["no audio"], subWords: ["no subtitles"]
            ),
            Case(
                name: "region match wins inside a language: pt-BR wanted",
                audio: [
                    AudioTrackInfo(id: "a1", language: LanguageTag(language: "pt", region: "PT"), codec: "AAC", channels: 6),
                    AudioTrackInfo(id: "a2", language: LanguageTag(language: "pt", region: "BR"), codec: "AAC", channels: 2),
                ],
                subs: [], original: nil,
                prefs: TrackPreferences(preferredAudioLanguages: [LanguageTag(language: "pt", region: "BR")]),
                wantAudio: "a2", wantSub: nil
            ),
        ]

        for c in cases {
            let r = TrackSelector.select(audio: c.audio, subtitles: c.subs, originalLanguage: c.original.map(L), preferences: c.prefs, remembered: c.remembered)
            XCTAssertEqual(r.audioTrackID, c.wantAudio, "audio: \(c.name)")
            XCTAssertEqual(r.subtitleTrackID, c.wantSub, "subtitle: \(c.name)")
            XCTAssertFalse(r.audioReason.isEmpty, "audio reason empty: \(c.name)")
            XCTAssertFalse(r.subtitleReason.isEmpty, "subtitle reason empty: \(c.name)")
            for w in c.audioWords { XCTAssertTrue(r.audioReason.lowercased().contains(w), "audio reason '\(r.audioReason)' lacks '\(w)': \(c.name)") }
            for w in c.subWords { XCTAssertTrue(r.subtitleReason.lowercased().contains(w), "subtitle reason '\(r.subtitleReason)' lacks '\(w)': \(c.name)") }
        }
    }

    // MARK: Remembered choice

    func testRememberedAudioAndSubtitlesOffWinOverPreferences() {
        let audio = [a("a1", "en", ch: 6), a("a2", "ja", ch: 2)]
        let subs = [s("s1", "en")]
        let choice = SeriesTrackChoice(audio: audio[1], subtitle: nil)
        let r = TrackSelector.select(audio: audio, subtitles: subs, originalLanguage: L("ja"), preferences: prefs(audio: ["en"], subs: ["en"]), remembered: choice)
        XCTAssertEqual(r.audioTrackID, "a2")
        XCTAssertNil(r.subtitleTrackID)
        XCTAssertTrue(r.audioReason.lowercased().contains("earlier choice"))
        XCTAssertTrue(r.subtitleReason.lowercased().contains("off"))
    }

    func testRememberedSubtitleKindIsMatchedOnAnotherEpisode() {
        // Episode 1: the user picked English SDH. Episode 2 has the tracks in another order and other ids.
        let chosen = s("ep1-s3", "en", sdh: true)
        let choice = SeriesTrackChoice(audio: a("x", "en", ch: 6), subtitle: chosen)
        let audio = [a("b1", "en", ch: 2), a("b2", "en", ch: 6)]
        let subs = [s("t1", "en", forced: true), s("t2", "en"), s("t3", "en", sdh: true), s("t4", "fr")]
        let r = TrackSelector.select(audio: audio, subtitles: subs, originalLanguage: L("en"), preferences: prefs(audio: ["fr"]), remembered: choice)
        XCTAssertEqual(r.audioTrackID, "b2", "same language, closest channel count")
        XCTAssertEqual(r.subtitleTrackID, "t3")
    }

    func testRememberedAudioDescriptionIsHonouredButNotChosenOtherwise() {
        let audio = [a("a1", "en", ch: 6), a("a2", "en", ch: 2, ad: true)]
        let choice = SeriesTrackChoice(audioLanguage: L("en"), audioChannels: 2, audioIsAudioDescription: true)
        let withChoice = TrackSelector.select(audio: audio, subtitles: [], originalLanguage: nil, preferences: prefs(audio: ["en"]), remembered: choice)
        XCTAssertEqual(withChoice.audioTrackID, "a2")
        let without = TrackSelector.select(audio: audio, subtitles: [], originalLanguage: nil, preferences: prefs(audio: ["en"]))
        XCTAssertEqual(without.audioTrackID, "a1")
    }

    func testRememberedChoiceThatNoLongerExistsFallsBackToRules() {
        let choice = SeriesTrackChoice(audioLanguage: L("ko"), subtitleLanguage: L("ko"))
        let r = TrackSelector.select(audio: [a("a1", "en", ch: 6)], subtitles: [s("s1", "en")], originalLanguage: L("en"), preferences: prefs(audio: ["en"]), remembered: choice)
        XCTAssertEqual(r.audioTrackID, "a1")
        XCTAssertNil(r.subtitleTrackID)
    }

    func testSeriesChoiceCodableRoundTrip() throws {
        let choice = SeriesTrackChoice(audio: a("x", "ja", ch: 2), subtitle: s("y", "en", forced: true, sdh: false))
        let data = try JSONEncoder().encode(choice)
        XCTAssertEqual(try JSONDecoder().decode(SeriesTrackChoice.self, from: data), choice)
    }

    func testSelectionIsDeterministic() {
        let audio = (0..<20).map { a("a\($0)", ["en", "fr", "ja"][$0 % 3], ch: [2, 6, 8][$0 % 3], def: $0 == 5) }
        let subs = (0..<20).map { s("s\($0)", ["en", "fr", "ja"][$0 % 3], forced: $0 % 4 == 0, sdh: $0 % 5 == 0) }
        let p = prefs(audio: ["fr"], subs: ["en"], sdh: .prefer)
        let first = TrackSelector.select(audio: audio, subtitles: subs, originalLanguage: L("ja"), preferences: p)
        for _ in 0..<20 {
            XCTAssertEqual(TrackSelector.select(audio: audio, subtitles: subs, originalLanguage: L("ja"), preferences: p), first)
        }
        XCTAssertNotNil(first.audioTrackID)
    }
}
