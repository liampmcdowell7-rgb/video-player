import XCTest
import VideoPlayerCore
import PlaybackLogic
import MetadataLocal
import UserData
@testable import AppLogic

/// Chapters read from a real (fixture) Matroska byte stream, sidecars, user marks, merged by `SegmentCollector`.
final class SegmentSourcingTests: XCTestCase {
    private let path = "/TV/Show/Show - S01E01.mkv"
    private let sidecar = "/TV/Show/Show - S01E01.edl"
    private let jsonSidecar = "/TV/Show/Show - S01E01.segments.json"

    private func collector(deadline: TimeInterval = 5) -> SegmentCollector { SegmentCollector(deadline: deadline) }

    private func info(duration: TimeInterval? = 2500) -> SegmentFileInfo { SegmentFileInfo(path: path, size: 5_000, duration: duration) }

    private func source(_ data: Data = FixtureMKV.episode()) -> SegmentFixtureSource {
        let s = SegmentFixtureSource()
        s.put(path, data)
        return s
    }

    private func mark(_ kind: String, _ start: Double, _ end: Double, duration: Double? = 2500) -> UDSegmentMark {
        UDSegmentMark(itemKey: "k", kind: kind, start: start, end: end, fileDuration: duration)
    }

    // MARK: Chapters

    func testSS1_chaptersOfARealByteStreamBecomeIntroAndCredits() async throws {
        let result = await collector().collect(file: info(), source: source(), marks: [])
        XCTAssertEqual(result.segments.map(\.type), [.intro, .credits])
        let intro = try XCTUnwrap(result.resolved.segment(of: .intro))
        XCTAssertEqual(intro.start, 0)
        XCTAssertEqual(intro.end, 90)
        XCTAssertEqual(intro.source, .embeddedChapters)
        XCTAssertEqual(intro.confidence, 0.9)
        let credits = try XCTUnwrap(result.resolved.segment(of: .credits))
        XCTAssertEqual(credits.start, 2400)
        XCTAssertEqual(credits.end, 2500, "the last chapter runs to the end of the file")
        XCTAssertTrue(result.notes.contains { $0.hasPrefix("Chapters: 3 read, 2 recognised") }, "\(result.notes)")
    }

    func testSS2_theLengthComesFromTheFileWhenTheLibraryDoesNotKnowIt() async throws {
        let result = await collector().collect(file: info(duration: nil), source: source(), marks: [])
        XCTAssertEqual(result.file?.duration, 2500)
        XCTAssertEqual(result.segments.count, 2)
    }

    func testSS3_titlesInOtherLanguagesAndAPostCreditsChapter() async throws {
        let data = FixtureMKV.build(duration: 2500, editions: [FixtureMKV.Edition(uid: 7, isDefault: true, chapters: [
            FixtureMKV.Chapter(title: "Prologue", start: 0, end: 40, language: "eng", extraTitles: [("fre", "Précédemment")]),
            FixtureMKV.Chapter(title: "Titre", start: 40, end: 120, language: "ger", extraTitles: [("eng", "Opening")]),
            FixtureMKV.Chapter(title: "Story", start: 120),
            FixtureMKV.Chapter(title: "Générique de fin", start: 2300, language: "fre"),
            FixtureMKV.Chapter(title: "After the credits", start: 2460),
        ])])
        let result = await collector().collect(file: info(), source: source(data), marks: [])
        XCTAssertEqual(result.resolved.segment(of: .recap)?.end, 40, "the French title of the first chapter is recognised")
        XCTAssertEqual(result.resolved.segment(of: .intro)?.start, 40, "any title language of a chapter may match")
        XCTAssertEqual(result.resolved.segment(of: .credits)?.end, 2460, "credits end at the post-credits chapter")
        XCTAssertEqual(result.resolved.postCreditsStart, 2460)
    }

    func testSS4_hiddenEditionsHiddenChaptersAndTheDefaultEdition() async throws {
        let data = FixtureMKV.build(duration: 2500, editions: [
            FixtureMKV.Edition(uid: 1, isDefault: false, chapters: [FixtureMKV.Chapter(title: "Recap", start: 0, end: 50)]),
            FixtureMKV.Edition(uid: 2, isDefault: true, chapters: [
                FixtureMKV.Chapter(title: "Intro", start: 0, end: 60),
                FixtureMKV.Chapter(title: "Credits", start: 2400, hidden: true),
            ]),
            FixtureMKV.Edition(uid: 3, isDefault: true, hidden: true, chapters: [FixtureMKV.Chapter(title: "Opening", start: 0, end: 120)]),
        ])
        let result = await collector().collect(file: info(), source: source(data), marks: [])
        XCTAssertEqual(result.segments.map(\.type), [.intro], "only the default visible edition counts, and its hidden chapter is skipped")
        XCTAssertEqual(result.resolved.segment(of: .intro)?.end, 60)
    }

    func testSS5_chapterMappingKeepsTitlesLanguagesAndEditionFlags() async throws {
        let data = FixtureMKV.episode(extra: [FixtureMKV.Chapter(title: "Hidden bit", start: 100, hidden: true, enabled: false, extraTitles: [("fre", "Caché")])])
        let parsed = try await MatroskaReader().read { range in
            Data(data[Int(min(range.offset, Int64(data.count)))..<Int(min(Int64(data.count), range.offset + range.length))])
        }
        let marks = ChapterMarks.marks(from: parsed)
        XCTAssertEqual(marks.count, 4)
        XCTAssertEqual(marks.first?.titles.first?.text, "Intro")
        XCTAssertEqual(marks.first?.titles.first?.language, "eng")
        XCTAssertTrue(marks.allSatisfy { $0.editionIsDefault && $0.editionID == 1 })
        let hidden = try XCTUnwrap(marks.first { $0.titles.first?.text == "Hidden bit" })
        XCTAssertTrue(hidden.isHidden)
        XCTAssertFalse(hidden.isEnabled)
        XCTAssertEqual(hidden.titles.map { $0.text }, ["Hidden bit", "Caché"])
    }

    // MARK: Reader failures

    func testSS6_aReaderThatFailsGivesNoChapterSegmentsAndNeverThrows() async throws {
        let s = source()
        s.readError = SourceError.transport("connection reset")
        let result = await collector().collect(file: info(), source: s, marks: [mark("intro", 100, 160)])
        XCTAssertEqual(result.segments.map(\.type), [.intro])
        XCTAssertEqual(result.segments.first?.source, .userMarked, "the user's own marks do not need the server")
        XCTAssertTrue(result.notes.contains { $0.hasPrefix("Chapters: the file could not be read") }, "\(result.notes)")
    }

    func testSS7_garbageThatIsNotMatroskaIsReportedNotTrusted() async throws {
        let s = source(Data((0..<4000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }))
        let result = await collector().collect(file: info(), source: s, marks: [])
        XCTAssertTrue(result.segments.isEmpty)
        XCTAssertTrue(result.notes.contains { $0.hasPrefix("Chapters: the file could not be read") })
        // A truncated real file: only the first 60 bytes.
        let truncated = source(FixtureMKV.episode().prefix(60))
        let r2 = await collector().collect(file: info(), source: truncated, marks: [])
        XCTAssertTrue(r2.segments.isEmpty)
    }

    func testSS8_aFolderThatCannotBeListedStillGivesChapters() async throws {
        let s = source()
        s.listError = SourceError.transport("timeout")
        let result = await collector().collect(file: info(), source: s, marks: [])
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertTrue(result.notes.contains { $0.hasPrefix("Sidecar files: the folder could not be listed") })
    }

    func testSS9_noSourceMeansOnlyUserMarks() async throws {
        let result = await collector().collect(file: info(), source: nil, marks: [mark("credits", 2400, 2500)])
        XCTAssertEqual(result.segments.map(\.type), [.credits])
        XCTAssertTrue(result.notes.contains { $0.contains("not connected") })
    }

    func testSS10_aSourceThatHangsDoesNotHoldBackThePlayer() async throws {
        let s = source()
        s.stallNanos = 2_000_000_000
        let start = Date()
        let result = await collector(deadline: 0.2).collect(file: info(), source: s, marks: [mark("intro", 100, 160)])
        let waited = Date().timeIntervalSince(start)
        XCTAssertLessThan(waited, 1.5, "the collector gave up after its deadline instead of waiting for the hanging read")
        XCTAssertEqual(result.segments.map(\.type), [.intro])
        XCTAssertTrue(result.notes.contains { $0.contains("did not finish within") })
    }

    func testSS11_aNonMatroskaFileIsNotReadForChaptersButItsSidecarIs() async throws {
        let s = SegmentFixtureSource()
        s.put("/TV/Show/Show - S01E01.mp4", Data(repeating: 0, count: 100))
        s.put("/TV/Show/Show - S01E01.edl", text: "10 70 intro\n")
        let result = await collector().collect(file: SegmentFileInfo(path: "/TV/Show/Show - S01E01.mp4", size: 100, duration: 2500), source: s, marks: [])
        XCTAssertEqual(result.resolved.segment(of: .intro)?.source, .localSidecar)
        XCTAssertFalse(s.reads.contains("/TV/Show/Show - S01E01.mp4"), "the video itself is never read")
        XCTAssertTrue(result.notes.contains { $0.hasPrefix("Chapters: only Matroska") })
    }

    // MARK: Sidecars

    func testSS12_edlAndJsonSidecarsAreReadAndMalformedLinesAreReported() async throws {
        let s = source(FixtureMKV.build(duration: 2500, editions: []))
        s.put(sidecar, text: "# fixture\n40 100 intro\nbroken line\n0 30 recap\n")
        s.put(jsonSidecar, text: #"{"segments":[{"type":"credits","start":2400,"end":2500,"referenceDuration":2500}]}"#)
        let result = await collector().collect(file: info(), source: s, marks: [])
        XCTAssertEqual(result.segments.map(\.type), [.recap, .intro, .credits])
        XCTAssertTrue(result.segments.allSatisfy { $0.source == .localSidecar && $0.confidence == 0.8 })
        XCTAssertTrue(result.notes.contains { $0.contains("Sidecar Show - S01E01.edl") && $0.contains("1 skipped") }, "\(result.notes)")
    }

    func testSS13_aSidecarForAnotherCutIsRejectedAndDamagedOnesGiveNothing() async throws {
        let s = source(FixtureMKV.build(duration: 2500, editions: []))
        s.put(sidecar, Data((0..<500).map { UInt8(truncatingIfNeeded: $0) }))
        s.put(jsonSidecar, text: #"{"segments":[{"type":"intro","start":10,"end":70,"referenceDuration":2800}]}"#)
        let result = await collector().collect(file: info(), source: s, marks: [])
        XCTAssertTrue(result.segments.isEmpty, "a 2800 s timing list does not fit a 2500 s file")
        XCTAssertTrue(result.notes.contains { $0.contains("Not used: intro from localSidecar") }, "\(result.notes)")
    }

    func testSS14_aHugeSidecarIsNotRead() async throws {
        let s = source(FixtureMKV.build(duration: 2500, editions: []))
        s.put(sidecar, Data(repeating: 0x20, count: SidecarSegments.maxBytes + 10))
        let result = await collector().collect(file: info(), source: s, marks: [])
        XCTAssertTrue(result.notes.contains { $0.contains("over the") && $0.contains("limit") })
        XCTAssertFalse(s.reads.contains(sidecar))
    }

    // MARK: Precedence end to end

    func testSS15_userMarkBeatsChaptersBeatsSidecarForTheSameType() async throws {
        let s = source()
        s.put(sidecar, text: "20 100 intro\n0 40 recap\n")
        let marks = [mark("intro", 5, 70)]
        let result = await collector().collect(file: info(), source: s, marks: marks)
        XCTAssertEqual(result.resolved.segment(of: .intro)?.source, .userMarked)
        XCTAssertEqual(result.resolved.segment(of: .intro)?.start, 5)
        XCTAssertEqual(result.resolved.segment(of: .intro)?.confidence, 1.0)
        // The sidecar recap 0...40 overlaps the user intro 5...70 and ranks lower: dropped, with its reason.
        XCTAssertNil(result.resolved.segment(of: .recap))
        XCTAssertTrue(result.resolved.rejected.contains { $0.reason == .overlapsHigherRanked(.intro) })
        XCTAssertEqual(result.resolved.segment(of: .credits)?.source, .embeddedChapters)
        // Without the user mark the chapter intro (0...90) wins over the sidecar intro, and the recap is dropped for overlapping it.
        let plain = await collector().collect(file: info(), source: s, marks: [])
        XCTAssertEqual(plain.resolved.segment(of: .intro)?.source, .embeddedChapters)
    }

    // MARK: User marks

    func testSS16_aMarkMadeOnAnotherCutOrOfAnUnknownKindIsNotUsed() async throws {
        let marks = [mark("intro", 100, 160, duration: 2100), mark("montage", 5, 50), mark("recap", 0, 40, duration: nil)]
        let result = await collector().collect(file: info(), source: nil, marks: marks)
        XCTAssertEqual(result.segments.map(\.type), [.recap], "no stored length means no way to doubt it")
        XCTAssertTrue(result.notes.contains { $0.contains("another length") })
        XCTAssertTrue(result.notes.contains { $0.contains("\"montage\"") })
    }

    func testSS17_aMarkBreakingTheLimitsIsNotUsedEvenThoughTheUserMadeIt() async throws {
        let result = await collector().collect(file: info(), source: nil, marks: [mark("credits", 600, 2500)])
        XCTAssertTrue(result.segments.isEmpty, "credits must start in the last 40 percent (SEG-9, SEG-13)")
        XCTAssertTrue(result.notes.contains { $0.contains("creditsStartTooEarly") })
    }

    func testSS18_anUnknownLengthMeansNoSegmentsAndSaysSo() async throws {
        let s = source(FixtureMKV.build(duration: 0, editions: []))
        let result = await collector().collect(file: info(duration: nil), source: s, marks: [mark("intro", 100, 160)])
        XCTAssertTrue(result.segments.isEmpty)
        XCTAssertNil(result.file)
        XCTAssertTrue(result.notes.contains { $0.contains("length of the file is not known") })
    }
}
