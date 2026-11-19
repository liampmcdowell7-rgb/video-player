import XCTest
@testable import Subtitles

final class ExternalMatcherTests: XCTestCase {

    private func match(_ video: String, _ listing: [String]) -> [ExternalSubtitleCandidate] {
        ExternalSubtitleMatcher.candidates(videoFileName: video, folderListing: listing)
    }

    // MARK: Languages

    func testLanguageCodesAndNames() throws {
        let video = "Movie (2019).mkv"
        let files = [
            "Movie (2019).en.srt", "Movie (2019).eng.srt", "Movie (2019).English.srt", "Movie (2019).fr.srt",
            "Movie (2019).pt-BR.srt", "Movie (2019).zh-Hans.srt", "Movie (2019).zh_TW.srt", "Movie (2019).deu.srt",
            "Movie (2019).Español.srt", "Movie (2019).srt",
        ]
        let r = match(video, files + [video])
        func lang(_ name: String) -> LanguageTag? { r.first { $0.fileName == name }?.language }
        XCTAssertEqual(lang("Movie (2019).en.srt"), LanguageTag(language: "en"))
        XCTAssertEqual(lang("Movie (2019).eng.srt"), LanguageTag(language: "en"))
        XCTAssertEqual(lang("Movie (2019).English.srt"), LanguageTag(language: "en"))
        XCTAssertEqual(lang("Movie (2019).fr.srt"), LanguageTag(language: "fr"))
        XCTAssertEqual(lang("Movie (2019).pt-BR.srt"), LanguageTag(language: "pt", region: "BR"))
        XCTAssertEqual(lang("Movie (2019).zh-Hans.srt"), LanguageTag(language: "zh", script: "Hans"))
        XCTAssertEqual(lang("Movie (2019).zh_TW.srt"), LanguageTag(language: "zh", region: "TW", script: "Hant"))
        XCTAssertEqual(lang("Movie (2019).deu.srt"), LanguageTag(language: "de"))
        XCTAssertEqual(lang("Movie (2019).Español.srt"), LanguageTag(language: "es"))
        XCTAssertNil(lang("Movie (2019).srt"))
        XCTAssertEqual(r.count, files.count)
    }

    func testLanguageTableCodesNamesAndRegions() {
        XCTAssertEqual(LanguageTag("ger"), LanguageTag(language: "de"))      // bibliographic
        XCTAssertEqual(LanguageTag("fre"), LanguageTag(language: "fr"))
        XCTAssertEqual(LanguageTag("fra"), LanguageTag(language: "fr"))
        XCTAssertEqual(LanguageTag("Japanese"), LanguageTag(language: "ja"))
        XCTAssertEqual(LanguageTag("日本語"), LanguageTag(language: "ja"))
        XCTAssertEqual(LanguageTag("pt-br"), LanguageTag(language: "pt", region: "BR"))
        XCTAssertEqual(LanguageTag("en_GB")?.region, "GB")
        XCTAssertEqual(LanguageTag("en-UK")?.region, "GB")
        XCTAssertEqual(LanguageTag("es-419")?.region, "419")
        XCTAssertEqual(LanguageTag("zh-Hant")?.script, "Hant")
        XCTAssertEqual(LanguageTag("cht"), LanguageTag(language: "zh", script: "Hant"))
        XCTAssertEqual(LanguageTag("chs"), LanguageTag(language: "zh", script: "Hans"))
        XCTAssertEqual(LanguageTag("yue"), LanguageTag(language: "yue"))
        XCTAssertNil(LanguageTag("movie"))
        XCTAssertNil(LanguageTag(""))
        XCTAssertNil(LanguageTag("en-ZZZZ"))
        XCTAssertEqual(LanguageTable.displayName(LanguageTag(language: "pt", region: "BR")), "Portuguese (BR)")
        XCTAssertEqual(LanguageTable.displayName(LanguageTag(language: "zh", script: "Hans")), "Chinese (Simplified)")
    }

    func testLanguageMatchScoring() {
        let ptBR = LanguageTag(language: "pt", region: "BR")
        let ptPT = LanguageTag(language: "pt", region: "PT")
        let pt = LanguageTag(language: "pt")
        XCTAssertEqual(ptBR.match(wanted: ptBR), 2)
        XCTAssertEqual(ptPT.match(wanted: ptBR), 1)
        XCTAssertEqual(pt.match(wanted: ptBR), 1)
        XCTAssertEqual(ptBR.match(wanted: pt), 2)
        XCTAssertEqual(LanguageTag(language: "en").match(wanted: pt), 0)
    }

    // MARK: Flags

    func testFlags() throws {
        let r = match("Show.S01E01.mkv", [
            "Show.S01E01.mkv",
            "Show.S01E01.en.srt", "Show.S01E01.en.forced.srt", "Show.S01E01.en.sdh.srt", "Show.S01E01.en.hi.srt",
            "Show.S01E01.en.cc.srt", "Show.S01E01.fr.default.srt", "Show.S01E01.sdh.srt", "Show.S01E01.hi.srt",
        ])
        func get(_ n: String) throws -> ExternalSubtitleCandidate { try XCTUnwrap(r.first { $0.fileName == n }, n) }
        let plain = try get("Show.S01E01.en.srt")
        XCTAssertFalse(plain.isForced || plain.isSDH || plain.isHI || plain.isCC || plain.isDefault)
        XCTAssertTrue(try get("Show.S01E01.en.forced.srt").isForced)
        XCTAssertTrue(try get("Show.S01E01.en.sdh.srt").isSDH)
        let hi = try get("Show.S01E01.en.hi.srt")
        XCTAssertTrue(hi.isHI)
        XCTAssertEqual(hi.language, LanguageTag(language: "en"))
        XCTAssertTrue(hi.isHearingImpairedVariant)
        XCTAssertTrue(try get("Show.S01E01.en.cc.srt").isCC)
        XCTAssertTrue(try get("Show.S01E01.fr.default.srt").isDefault)
        // "sdh" alone has no language; "hi" alone is Hindi.
        XCTAssertNil(try get("Show.S01E01.sdh.srt").language)
        XCTAssertTrue(try get("Show.S01E01.sdh.srt").isSDH)
        let hindi = try get("Show.S01E01.hi.srt")
        XCTAssertEqual(hindi.language, LanguageTag(language: "hi"))
        XCTAssertFalse(hindi.isHI)
    }

    // MARK: Which files belong

    func testOnlyFilesWithTheVideosNameStartMatchWhenSeveralVideosShareTheFolder() {
        let r = match("Movie A.mkv", ["Movie A.mkv", "Movie B.mkv", "Movie A.en.srt", "Movie B.en.srt", "Movie AB.en.srt", "Other.srt", "Movie A.txt"])
        XCTAssertEqual(r.map(\.fileName), ["Movie A.en.srt"])
        XCTAssertEqual(r.first?.tier, .sameName)
    }

    func testNameMatchIsCaseAndAccentInsensitive() {
        let r = match("café.MKV", ["café.mkv", "CAFÉ.EN.SRT", "Cafe\u{0301}.fr.srt"])
        XCTAssertEqual(Set(r.map(\.fileName)), ["CAFÉ.EN.SRT", "Cafe\u{0301}.fr.srt"])
    }

    func testEpisodeNumberMatchesDifferentlyWordedNames() {
        let r = match("Show Name - S02E05 - Title.1080p.WEB.mkv", [
            "Show Name - S02E05 - Title.1080p.WEB.mkv", "Show Name - S02E06 - Title.1080p.WEB.mkv",
            "Show.Name.S02E05.en.srt", "Show.Name.S02E06.en.srt", "Different.Show.S02E05.en.srt",
        ])
        XCTAssertEqual(r.map(\.fileName), ["Show.Name.S02E05.en.srt"])
        XCTAssertEqual(r.first?.tier, .sameEpisode)
        XCTAssertEqual(r.first?.language, LanguageTag(language: "en"))
    }

    func testSingleVideoFolderTakesEverySubtitleIncludingSubsFolder() {
        let r = match("Film.mkv", ["Film.mkv", "Subs/2_English.srt", "Subs/3_French.srt", "Subs/4_Chinese (Simplified).srt", "readme.nfo"])
        XCTAssertEqual(r.count, 3)
        XCTAssertTrue(r.allSatisfy { $0.tier == .onlyVideoInFolder })
        XCTAssertEqual(r.first { $0.fileName.contains("English") }?.language, LanguageTag(language: "en"))
        XCTAssertEqual(r.first { $0.fileName.contains("French") }?.language, LanguageTag(language: "fr"))
        XCTAssertEqual(r.first { $0.fileName.contains("Chinese") }?.language, LanguageTag(language: "zh"))
    }

    func testTwoVideosMeansNoFallbackToAnySubtitle() {
        XCTAssertTrue(match("A.mkv", ["A.mkv", "B.mkv", "English.srt"]).isEmpty)
    }

    func testHiddenAppleDoubleFilesAndOtherExtensionsAreIgnored() {
        let r = match("M.mkv", ["M.mkv", "._M.en.srt", ".M.en.srt", "M.en.srt.bak", "M.en.txt", "M.en.srt"])
        XCTAssertEqual(r.map(\.fileName), ["M.en.srt"])
    }

    func testNameWithRegexLikeCharactersAndDotsInTitle() {
        let r = match("Dr. Oddly (2016) [1080p].mkv", ["Dr. Oddly (2016) [1080p].mkv", "Other.mkv", "Dr. Oddly (2016) [1080p].en.srt", "Dr. Oddly (2016) [1080p]ENG.srt"])
        XCTAssertEqual(r.count, 1, "'ENG' glued to the name without a separator is not a language suffix")
    }

    // MARK: Formats and VobSub pairs

    func testAllFormatsAreRecognised() {
        let names = ["V.srt", "V.ass", "V.ssa", "V.vtt", "V.sup"].map { $0 }
        let r = match("V.mkv", ["V.mkv"] + names)
        XCTAssertEqual(Set(r.map(\.format)), [.srt, .ass, .ssa, .webVTT, .pgs])
    }

    func testVobSubPairAndOrphans() throws {
        let r = match("V.mkv", ["V.mkv", "V.en.idx", "V.en.sub", "V.fr.sub", "V.de.idx"])
        let en = try XCTUnwrap(r.first { $0.fileName == "V.en.idx" })
        XCTAssertEqual(en.format, .vobSub)
        XCTAssertEqual(en.companionFileName, "V.en.sub")
        XCTAssertTrue(en.isUsable)
        XCTAssertNil(r.first { $0.fileName == "V.en.sub" }, "the pair is listed once, as the .idx")
        let fr = try XCTUnwrap(r.first { $0.fileName == "V.fr.sub" })
        XCTAssertFalse(fr.isUsable, "a lone .sub may be MicroDVD text, which is not supported")
        let de = try XCTUnwrap(r.first { $0.fileName == "V.de.idx" })
        XCTAssertFalse(de.isUsable)
        XCTAssertNil(de.companionFileName)
    }

    // MARK: Ordering

    func testOrdering() {
        let r = match("Show.S01E01.mkv", [
            "Show.S01E01.mkv",
            "Show.S01E01.fr.srt", "Show.S01E01.en.sdh.srt", "Show.S01E01.en.forced.srt", "Show.S01E01.en.srt", "Show.S01E01.en.ass", "Show.S01E01.srt",
        ])
        XCTAssertEqual(r.map(\.fileName), [
            "Show.S01E01.en.srt", "Show.S01E01.en.ass", "Show.S01E01.en.sdh.srt", "Show.S01E01.en.forced.srt",
            "Show.S01E01.fr.srt", "Show.S01E01.srt",
        ])
    }

    func testOrderingPutsCloserNamesFirstAcrossTiers() {
        let r = match("Show.S01E01.mkv", ["Show.S01E01.mkv", "Show.S01E01.en.srt", "Other.Title.S01E01.fr.srt"])
        // The second file has a different title: it is not a same-episode match and, with one video in the folder,
        // is accepted at the weakest tier.
        XCTAssertEqual(r.map(\.tier), [.sameName, .onlyVideoInFolder])
        XCTAssertEqual(r.map(\.fileName), ["Show.S01E01.en.srt", "Other.Title.S01E01.fr.srt"])
    }

    func testEmptyInputs() {
        XCTAssertTrue(match("", []).isEmpty)
        XCTAssertTrue(match("x.mkv", []).isEmpty)
        XCTAssertTrue(match("x.mkv", ["x.mkv"]).isEmpty)
    }

    // MARK: .idx header

    func testIdxHeader() {
        let idx = """
        # VobSub index file, v7 (do not modify this line!)
        size: 720x480
        org: 0, 0
        palette: 000000, ffffff, 808080, ff0000, 00ff00, 0000ff, ffff00, 00ffff, ff00ff, c0c0c0, 800000, 008000, 000080, 808000, 800080, 008080
        langidx: 0

        id: en, index: 0
        timestamp: 00:00:01:000, filepos: 000000000
        timestamp: 00:00:03:500, filepos: 000000800

        id: fr, index: 1
        timestamp: 00:00:05:000, filepos: 000001000
        """
        let h = VobSubIndexHeader.parse(idx)
        XCTAssertEqual([h.width, h.height], [720, 480])
        XCTAssertEqual(h.palette.count, 16)
        XCTAssertEqual(h.palette[1], SubtitleColor(red: 255, green: 255, blue: 255))
        XCTAssertEqual(h.palette[3], SubtitleColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(h.tracks, [VobSubIndexHeader.Track(language: "en", index: 0), VobSubIndexHeader.Track(language: "fr", index: 1)])
        XCTAssertEqual(h.timestampCount, 3)
    }

    func testIdxHeaderToleratesGarbage() {
        let h = VobSubIndexHeader.parse("size: bad\npalette: zz, 12\nid:\n\u{0}\u{1}\u{2}")
        XCTAssertNil(h.width)
        XCTAssertTrue(h.palette.isEmpty)
        XCTAssertEqual(VobSubIndexHeader.parse("").tracks.count, 0)
    }
}
