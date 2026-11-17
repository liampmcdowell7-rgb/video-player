import XCTest
@testable import Subtitles

final class WebVTTParserTests: XCTestCase {

    private let full = """
    WEBVTT - a title
    Kind: captions
    Language: en

    NOTE this is a comment
    that spans lines

    STYLE
    ::cue { color: lime }

    REGION
    id:fred
    width:40%
    lines:3

    intro
    00:00:01.000 --> 00:00:03.500 position:20% line:10% align:start size:50% region:fred
    <v Alice>Hello <i>there</i>
    second line

    00:04.000 --> 00:05.000 vertical:rl line:-1
    short timestamp, no id

    2
    01:00:00.000 --> 01:00:02.000
    <c.yellow>yellow</c> <00:01:00.500>inline <b>b</b> &amp; text
    """

    func testHeaderBlocksAndCues() {
        let p = WebVTTParser.parse(full)
        XCTAssertEqual(p.format, .webVTT)
        XCTAssertEqual(p.cues.count, 3)
        XCTAssertEqual(p.vttStyleBlocks, ["::cue { color: lime }"])
        XCTAssertEqual(p.vttRegions["fred"]?["width"], "40%")
        XCTAssertTrue(p.warnings.isEmpty, "\(p.warnings)")
    }

    func testFirstCueDetails() throws {
        let c = try XCTUnwrap(WebVTTParser.parse(full).cues.first)
        XCTAssertEqual(c.identifier, "intro")
        XCTAssertEqual(c.start, 1.0, accuracy: 1e-9)
        XCTAssertEqual(c.end, 3.5, accuracy: 1e-9)
        XCTAssertEqual(c.speaker, "Alice")
        XCTAssertEqual(c.plainText, "Hello there\nsecond line")
        XCTAssertEqual(c.runs.map(\.italic), [false, true, false])
        let v = try XCTUnwrap(c.vtt)
        XCTAssertEqual(v.positionPercent, 20)
        XCTAssertEqual(v.line, 10)
        XCTAssertTrue(v.lineIsPercent)
        XCTAssertEqual(v.sizePercent, 50)
        XCTAssertEqual(v.align, .start)
        XCTAssertEqual(v.region, "fred")
        XCTAssertEqual(c.alignment, SubtitleAlignment(horizontal: .left, vertical: .top))
    }

    func testTimestampWithoutHoursAndVerticalSetting() throws {
        let c = WebVTTParser.parse(full).cues[1]
        XCTAssertEqual(c.start, 4.0, accuracy: 1e-9)
        XCTAssertEqual(c.end, 5.0, accuracy: 1e-9)
        XCTAssertNil(c.identifier)
        XCTAssertEqual(c.vtt?.direction, .verticalRightToLeft)
        XCTAssertEqual(c.vtt?.line, -1)
        XCTAssertEqual(c.vtt?.lineIsPercent, false)
        XCTAssertEqual(c.alignment?.vertical, .bottom)
    }

    func testInlineTimestampsAreIgnoredAndClassColourApplied() {
        let c = WebVTTParser.parse(full).cues[2]
        XCTAssertEqual(c.start, 3600, accuracy: 1e-9)
        XCTAssertEqual(c.identifier, "2")
        XCTAssertEqual(c.plainText, "yellow inline b & text")
        XCTAssertEqual(c.runs.first?.color, SubtitleColor(red: 255, green: 255, blue: 0))
        XCTAssertEqual(c.runs.first(where: { $0.text == "b" })?.bold, true)
    }

    func testMissingHeaderStillParsesWithWarning() {
        let p = WebVTTParser.parse("00:01.000 --> 00:02.000\nHi\n")
        XCTAssertEqual(p.cues.map(\.plainText), ["Hi"])
        XCTAssertTrue(p.warnings.contains { $0.contains("WEBVTT") })
    }

    func testHeaderOnlyAndEmpty() {
        XCTAssertEqual(WebVTTParser.parse("WEBVTT\n\n").cues.count, 0)
        XCTAssertEqual(WebVTTParser.parse("").cues.count, 0)
        XCTAssertEqual(WebVTTParser.parse("WEBVTT").cues.count, 0)
    }

    func testBOMAndCRLF() {
        let text = "\u{FEFF}WEBVTT\r\n\r\n00:00:01.000 --> 00:00:02.000\r\nA\r\n\r\n00:00:03.000 --> 00:00:04.000\r\nB\r\n"
        XCTAssertEqual(WebVTTParser.parse(text).cues.map(\.plainText), ["A", "B"])
    }

    func testMissingBlankLineBetweenCuesAndZeroDuration() {
        let p = WebVTTParser.parse("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nOne\n00:00:03.000 --> 00:00:04.000\nTwo\n\n00:00:05.000 --> 00:00:05.000\nzero\n")
        XCTAssertEqual(p.cues.map(\.plainText), ["One", "Two"])
        XCTAssertTrue(p.warnings.contains { $0.contains("end was not after") })
    }

    func testCueSettingsParserRejectsBadValues() {
        let s = WebVTTParser.parseSettings("position:150% line:abc size:-5% align:diagonal vertical:up region:")
        XCTAssertNil(s.positionPercent)
        XCTAssertNil(s.line)
        XCTAssertNil(s.sizePercent)
        XCTAssertEqual(s.align, .center)
        XCTAssertEqual(s.direction, .horizontal)
        XCTAssertNil(s.region)
        let t = WebVTTParser.parseSettings("position:50%,line-left line:3,start align:right")
        XCTAssertEqual(t.positionPercent, 50)
        XCTAssertEqual(t.line, 3)
        XCTAssertEqual(t.align, .right)
    }

    func testOverlappingAndUnorderedCues() {
        let p = WebVTTParser.parse("WEBVTT\n\n00:00:05.000 --> 00:00:09.000\nb\n\n00:00:01.000 --> 00:00:06.000\na\n")
        XCTAssertEqual(p.cues.map(\.plainText), ["a", "b"])
        XCTAssertEqual(SubtitleTrack(parsed: p).activeCues(at: 5.5).map(\.plainText), ["a", "b"])
    }

    func testDetectsFormatThroughEntryPoint() throws {
        let parsed = try SubtitleFileParser.parse(text: "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nx\n")
        XCTAssertEqual(parsed.format, .webVTT)
        let noHeader = try SubtitleFileParser.parse(text: "00:00:01.000 --> 00:00:02.000\nx\n", fileExtension: "vtt")
        XCTAssertEqual(noHeader.format, .webVTT)
    }
}
