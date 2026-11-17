import XCTest
@testable import PlaybackLogic

/// Segment sidecar parsers (docs/SEGMENTS.md). Text is made up in the tests (fixture); the formats are the PROVISIONAL ones of this app.
final class SidecarSegmentsTests: XCTestCase {
    private let file = FileIdentity(path: "/tv/Show/S01E01.mkv", size: 1_000_000, duration: 1000)

    // MARK: Times

    func testSC1_timesInSecondsAndClockForm() {
        let rows: [(String, TimeInterval?)] = [
            ("12.5", 12.5), ("75", 75), ("1:15", 75), ("0:01:15.250", 75.25), ("01:00:00", 3600), (" 7 ", 7),
            ("", nil), ("-3", nil), ("abc", nil), ("1:2:3:4", nil), ("1.5:30", nil), ("inf", nil), ("nan", nil), ("1:-5", nil),
        ]
        for (text, expected) in rows {
            XCTAssertEqual(SidecarSegments.parseTime(text), expected, "\"\(text)\"")
        }
    }

    // MARK: EDL

    func testSC2_edlReadsStartEndAndTheThreeWords() {
        let text = """
        # made by hand
        12.5 95 intro
        0:00:05 0:00:40 RECAP  the previously-on bit
        1500 1600 Credits
        """
        let r = EDLSegmentParser.parse(text)
        XCTAssertEqual(r.warnings, [])
        XCTAssertEqual(r.entries, [
            SidecarEntry(type: .intro, start: 12.5, end: 95),
            SidecarEntry(type: .recap, start: 5, end: 40),
            SidecarEntry(type: .credits, start: 1500, end: 1600),
        ])
    }

    func testSC3_edlSkipsMalformedLinesAndSaysWhy() {
        let text = """
        10 60 intro
        garbage
        5 intro
        x y intro
        60 10 intro
        20 30 0
        20 30 3
        20 30 sing-along
        70 130 intro
        """
        let r = EDLSegmentParser.parse(text)
        XCTAssertEqual(r.entries.map(\.start), [10, 70], "only the two good lines survive")
        XCTAssertEqual(r.warnings.count, 7)
        XCTAssertTrue(r.warnings[0].hasPrefix("Line 2:"), r.warnings[0])
        XCTAssertTrue(r.warnings.contains { $0.contains("cut, mute or marker") }, "numeric actions are never turned into skips")
        XCTAssertTrue(r.warnings.contains { $0.contains("unknown action") })
        XCTAssertTrue(r.warnings.contains { $0.contains("end is not after the start") })
    }

    func testSC4_edlHandlesBinaryJunkEmptyFilesAndOddLineEndings() {
        XCTAssertEqual(EDLSegmentParser.parse(Data()), SidecarParseResult())
        let junk = Data((0..<2000).map { UInt8(truncatingIfNeeded: $0 &* 37) })
        let r = EDLSegmentParser.parse(junk)
        XCTAssertTrue(r.entries.isEmpty, "binary data gives no segment and no crash")
        let crlf = "\u{FEFF}10 60 intro\r\n70 130 recap\r".data(using: .utf8)!
        XCTAssertEqual(EDLSegmentParser.parse(crlf).entries.count, 2, "BOM, CRLF and a lone CR are fine")
    }

    func testSC5_edlStopsAfterTheEntryLimit() {
        let text = (0..<(SidecarSegments.maxEntries + 50)).map { _ in "10 60 intro" }.joined(separator: "\n")
        let r = EDLSegmentParser.parse(text)
        XCTAssertEqual(r.entries.count, SidecarSegments.maxEntries)
        XCTAssertTrue(r.warnings.contains { $0.contains("rest was ignored") })
    }

    // MARK: JSON

    func testSC6_jsonReadsEntriesTimesAsNumbersOrText() throws {
        let json = """
        {"version":1,"referenceDuration":1000,"segments":[
          {"type":"intro","start":12.5,"end":95},
          {"type":"Credits","start":"16:40","end":"0:17:20","referenceDuration":999},
          {"type":"recap","start":0,"end":30,"extra":"ignored"}
        ],"unknownTopLevel":true}
        """
        let r = SegmentsJSONParser.parse(Data(json.utf8))
        XCTAssertEqual(r.warnings, [])
        XCTAssertEqual(r.entries, [
            SidecarEntry(type: .intro, start: 12.5, end: 95, referenceDuration: 1000),
            SidecarEntry(type: .credits, start: 1000, end: 1040, referenceDuration: 999),
            SidecarEntry(type: .recap, start: 0, end: 30, referenceDuration: 1000),
        ])
    }

    func testSC7_jsonMalformedInputNeverCrashesAndKeepsWhatIsGood() {
        XCTAssertEqual(SegmentsJSONParser.parse(Data("{not json".utf8)).entries, [])
        XCTAssertEqual(SegmentsJSONParser.parse(Data("[1,2,3]".utf8)).warnings, ["The top level must be an object with a \"segments\" list"])
        XCTAssertEqual(SegmentsJSONParser.parse(Data("{}".utf8)).warnings, ["There is no \"segments\" list"])
        XCTAssertEqual(SegmentsJSONParser.parse(Data()).entries, [])
        let mixed = """
        {"segments":[
          5,
          {"type":"intro"},
          {"type":"bogus","start":1,"end":2},
          {"type":"intro","start":-4,"end":9},
          {"type":"intro","start":50,"end":10},
          {"type":"intro","start":"x","end":9},
          {"type":"intro","start":10,"end":60}
        ]}
        """
        let r = SegmentsJSONParser.parse(Data(mixed.utf8))
        XCTAssertEqual(r.entries, [SidecarEntry(type: .intro, start: 10, end: 60)])
        XCTAssertEqual(r.warnings.count, 6)
    }

    func testSC8_jsonNewerVersionReadsWithAWarning() {
        let r = SegmentsJSONParser.parse(Data(#"{"version":7,"segments":[{"type":"intro","start":10,"end":60}]}"#.utf8))
        XCTAssertEqual(r.entries.count, 1)
        XCTAssertEqual(r.warnings.count, 1)
        XCTAssertTrue(r.warnings[0].contains("newer"))
    }

    // MARK: Finding and sizing

    func testSC9_sidecarNamesMatchTheVideoStemCaseInsensitively() {
        let names = ["Show - S01E01.mkv", "show - s01e01.EDL", "Show - S01E01.segments.json", "Show - S01E02.edl", "Show - S01E01.en.srt", "Show - S01E01.edl.bak"]
        let hits = SidecarSegments.matching(videoName: "Show - S01E01.mkv", among: names)
        XCTAssertEqual(hits.map { $0.name }, ["show - s01e01.EDL", "Show - S01E01.segments.json"])
        XCTAssertEqual(hits.map { $0.format }, [.edl, .json])
        XCTAssertTrue(SidecarSegments.matching(videoName: "Other.mkv", among: names).isEmpty)
    }

    func testSC10_aFileOverTheSizeLimitIsNotParsed() {
        let big = Data(repeating: 0x20, count: SidecarSegments.maxBytes + 1)
        let r = SidecarSegments.parse(big, format: .edl)
        XCTAssertTrue(r.entries.isEmpty)
        XCTAssertEqual(r.warnings.count, 1)
    }

    func testSC11_candidatesAreSidecarSourceWithTheDocumentedConfidence() throws {
        let c = SidecarSegments.candidates(from: [SidecarEntry(type: .intro, start: 10, end: 60, referenceDuration: 1000)], file: file)
        let s = try XCTUnwrap(c.first)
        XCTAssertEqual(s.source, .localSidecar)
        XCTAssertEqual(s.confidence, 0.8)
        XCTAssertEqual(s.referenceDuration, 1000)
        XCTAssertEqual(s.file, file)
        // A sidecar made for another cut (reference duration 1100 against a 1000 s file) is rejected by the B1 rule.
        let other = SidecarSegments.candidates(from: [SidecarEntry(type: .intro, start: 10, end: 60, referenceDuration: 1100)], file: file)
        let resolved = SegmentResolver.resolve(file: file, candidates: other)
        XCTAssertTrue(resolved.segments.isEmpty)
        XCTAssertEqual(resolved.rejected.first?.reason, .durationMismatch)
    }
}
