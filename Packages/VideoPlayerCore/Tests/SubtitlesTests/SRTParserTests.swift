import XCTest
@testable import Subtitles

final class SRTParserTests: XCTestCase {

    private func parse(_ s: String) -> ParsedSubtitle { SRTParser.parse(s) }

    func testBasicCue() {
        let p = parse("1\n00:00:01,000 --> 00:00:02,500\nHello\n\n")
        XCTAssertEqual(p.cues.count, 1)
        XCTAssertEqual(p.cues[0].start, 1.0, accuracy: 1e-9)
        XCTAssertEqual(p.cues[0].end, 2.5, accuracy: 1e-9)
        XCTAssertEqual(p.cues[0].plainText, "Hello")
        XCTAssertEqual(p.cues[0].identifier, "1")
        XCTAssertEqual(p.format, .srt)
        XCTAssertTrue(p.warnings.isEmpty)
    }

    func testMultiLineTextKeepsLineBreaks() {
        let p = parse("1\n00:00:01,000 --> 00:00:02,000\nFirst line\nSecond line\n\n2\n00:00:03,000 --> 00:00:04,000\nThird\n")
        XCTAssertEqual(p.cues.map(\.plainText), ["First line\nSecond line", "Third"])
    }

    func testLineEndingsCRLFLFAndCR() {
        let body = ["1", "00:00:01,000 --> 00:00:02,000", "A", "", "2", "00:00:03,000 --> 00:00:04,000", "B", ""]
        for eol in ["\r\n", "\n", "\r"] {
            let p = parse(body.joined(separator: eol))
            XCTAssertEqual(p.cues.map(\.plainText), ["A", "B"], "eol \(eol.debugDescription)")
        }
        let mixed = parse("1\r\n00:00:01,000 --> 00:00:02,000\rA\n\r\n2\n00:00:03,000 --> 00:00:04,000\r\nB")
        XCTAssertEqual(mixed.cues.map(\.plainText), ["A", "B"])
    }

    func testTimestampVariants() {
        let p = parse("""
        1
        00:00:01.250 --> 00:00:02.500
        dot milliseconds

        2
        1:02:03,5 --> 1:02:04,25
        short fractions and one digit hour

        3
        01:30,000 --> 01:31,000
        no hours

        4
        00:00:05 --> 00:00:06
        no fraction
        """)
        XCTAssertEqual(p.cues.count, 4)
        // Sorted by start time, not in file order.
        XCTAssertEqual(p.cues.map(\.plainText), ["dot milliseconds", "no fraction", "no hours", "short fractions and one digit hour"])
        XCTAssertEqual(p.cues[0].start, 1.25, accuracy: 1e-9)
        XCTAssertEqual(p.cues[1].start, 5, accuracy: 1e-9)
        XCTAssertEqual(p.cues[2].start, 90, accuracy: 1e-9)
        XCTAssertEqual(p.cues[3].start, 3723.5, accuracy: 1e-9)
        XCTAssertEqual(p.cues[3].end, 3724.25, accuracy: 1e-9)
    }

    func testBadAndMissingNumbering() {
        let p = parse("""
        7
        00:00:01,000 --> 00:00:02,000
        wrong number

        abc
        00:00:03,000 --> 00:00:04,000
        non numeric number

        00:00:05,000 --> 00:00:06,000
        no number at all
        """)
        XCTAssertEqual(p.cues.map(\.plainText), ["wrong number", "non numeric number", "no number at all"])
        XCTAssertEqual(p.cues[0].identifier, "7")
    }

    func testMissingBlankLinesBetweenCues() {
        let p = parse("1\n00:00:01,000 --> 00:00:02,000\nOne\n2\n00:00:03,000 --> 00:00:04,000\nTwo\n3\n00:00:05,000 --> 00:00:06,000\nThree")
        XCTAssertEqual(p.cues.map(\.plainText), ["One", "Two", "Three"])
        // And without even the numbers:
        let q = parse("00:00:01,000 --> 00:00:02,000\nOne\n00:00:03,000 --> 00:00:04,000\nTwo")
        XCTAssertEqual(q.cues.map(\.plainText), ["One", "Two"])
    }

    func testOverlappingAndOutOfOrderCuesAreKeptAndSorted() {
        let p = parse("""
        1
        00:00:05,000 --> 00:00:09,000
        late

        2
        00:00:01,000 --> 00:00:06,000
        early

        3
        00:00:02,000 --> 00:00:03,000
        inside
        """)
        XCTAssertEqual(p.cues.map(\.plainText), ["early", "inside", "late"])
        XCTAssertEqual(SubtitleTrack(parsed: p).activeCues(at: 2.5).map(\.plainText), ["early", "inside"])
    }

    func testZeroAndNegativeDurationDropped() {
        let p = parse("""
        1
        00:00:01,000 --> 00:00:01,000
        zero

        2
        00:00:05,000 --> 00:00:03,000
        negative

        3
        00:00:06,000 --> 00:00:07,000
        fine
        """)
        XCTAssertEqual(p.cues.map(\.plainText), ["fine"])
        XCTAssertTrue(p.warnings.contains { $0.contains("end was not after") })
    }

    func testNegativeStartClampedToZero() {
        let p = parse("1\n-00:00:01,000 --> 00:00:02,000\nhead\n")
        XCTAssertEqual(p.cues.count, 1)
        XCTAssertEqual(p.cues[0].start, 0)
        XCTAssertEqual(p.cues[0].end, 2, accuracy: 1e-9)
    }

    func testTrailingGarbageAndLeadingGarbageSkipped() {
        let p = parse("""
        garbage before
        1
        00:00:01,000 --> 00:00:02,000
        Real

        this is not a cue
        0xFFFF
        """)
        XCTAssertEqual(p.cues.map(\.plainText), ["Real"])
        XCTAssertTrue(p.warnings.contains { $0.hasPrefix("Skipped") })
    }

    func testBOMCharacterIsIgnored() {
        let p = parse("\u{FEFF}1\n00:00:01,000 --> 00:00:02,000\nHi\n")
        XCTAssertEqual(p.cues.map(\.plainText), ["Hi"])
    }

    func testEmptyTextCueDropped() {
        let p = parse("1\n00:00:01,000 --> 00:00:02,000\n\n2\n00:00:03,000 --> 00:00:04,000\nx\n")
        XCTAssertEqual(p.cues.map(\.plainText), ["x"])
        XCTAssertTrue(p.warnings.contains { $0.contains("no text") })
    }

    func testCoordinatesAfterTimingAreIgnored() {
        let p = parse("1\n00:00:01,000 --> 00:00:02,000  X1:100 X2:200 Y1:10 Y2:20\nText\n")
        XCTAssertEqual(p.cues.first?.plainText, "Text")
        XCTAssertEqual(p.cues.first?.end ?? 0, 2, accuracy: 1e-9)
    }

    func testIndexLikeTextBeforeTimingIsTreatedAsNumber() {
        // Documented ambiguity: a text line of only digits right before a timing line is the next cue's number.
        let p = parse("1\n00:00:01,000 --> 00:00:02,000\nCount to\n42\n00:00:03,000 --> 00:00:04,000\nnext")
        XCTAssertEqual(p.cues.map(\.plainText), ["Count to", "next"])
        XCTAssertEqual(p.cues[1].identifier, "42")
    }

    // MARK: Markup

    func testItalicBoldUnderlineAndNesting() {
        let p = parse("1\n00:00:01,000 --> 00:00:02,000\nplain <i>italic <b>both</b></i> <u>under</u> end\n")
        let runs = p.cues[0].runs
        XCTAssertEqual(runs.map(\.text), ["plain ", "italic ", "both", " ", "under", " end"])
        XCTAssertEqual(runs.map(\.italic), [false, true, true, false, false, false])
        XCTAssertEqual(runs.map(\.bold), [false, false, true, false, false, false])
        XCTAssertEqual(runs.map(\.underline), [false, false, false, false, true, false])
    }

    func testFontColorAndFace() {
        let p = parse("1\n00:00:01,000 --> 00:00:02,000\n<font color=\"#ff0000\" face=\"Courier\">red</font> <font color=lime>green</font> <font color='#0f0'>g2</font>\n")
        let runs = p.cues[0].runs
        XCTAssertEqual(runs[0].color, SubtitleColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(runs[0].fontName, "Courier")
        XCTAssertEqual(runs[2].color, SubtitleColor(red: 0, green: 255, blue: 0))
        XCTAssertEqual(runs[4].color, SubtitleColor(red: 0, green: 255, blue: 0))
        XCTAssertEqual(p.cues[0].plainText, "red green g2")
    }

    func testAssStyleBraceTagsInSRT() {
        let p = parse("1\n00:00:01,000 --> 00:00:02,000\n{\\an8}Top text {\\i1}slanted{\\i0} done\n")
        XCTAssertEqual(p.cues[0].alignment, SubtitleAlignment(horizontal: .center, vertical: .top))
        XCTAssertEqual(p.cues[0].plainText, "Top text slanted done")
        XCTAssertEqual(p.cues[0].runs.map(\.italic), [false, true, false])
    }

    func testLiteralAngleBracketsAndUnknownTagsStayText() {
        let p = parse("1\n00:00:01,000 --> 00:00:02,000\nif a < b and c > d then <laughs> yes\n")
        XCTAssertEqual(p.cues[0].plainText, "if a < b and c > d then <laughs> yes")
    }

    func testUnclosedAndStrayClosingTagsDoNotLeak() {
        let p = parse("1\n00:00:01,000 --> 00:00:02,000\n<i>never closed\n\n2\n00:00:03,000 --> 00:00:04,000\nstray </b> close\n")
        XCTAssertEqual(p.cues.map(\.plainText), ["never closed", "stray  close"])
        XCTAssertEqual(p.cues[0].runs.first?.italic, true)
        XCTAssertEqual(p.cues[1].runs.allSatisfy { !$0.bold }, true)
    }

    func testEntitiesAndBreakTag() {
        let p = parse("1\n00:00:01,000 --> 00:00:02,000\nTom &amp; Jerry &lt;3 &#233;&#x41;&nbsp;x<br>next &bogus; &\n")
        XCTAssertEqual(p.cues[0].plainText, "Tom & Jerry <3 éA\u{00A0}x\nnext &bogus; &")
    }

    func testTrailingAndLeadingBlankSpaceTrimmed() {
        let p = parse("1\n00:00:01,000 --> 00:00:02,000\n   spaced   \n")
        XCTAssertEqual(p.cues[0].plainText, "spaced")
    }

    func testUnicodeTextSurvives() {
        let p = parse("1\n00:00:01,000 --> 00:00:02,000\n日本語 😀 العربية\n")
        XCTAssertEqual(p.cues[0].plainText, "日本語 😀 العربية")
    }

    func testTimestampHelperRejectsGarbage() {
        for bad in ["", "abc", "1:2:3:4", "00:00:aa,000", "::", "1.2.3", "99999999999:00:00", "00:00:01,0000000000"] {
            XCTAssertNil(SubtitleText.timestamp(Substring(bad)), bad)
        }
        XCTAssertEqual(SubtitleText.timestamp("00:00:01,5") ?? -1, 1.5, accuracy: 1e-9)
    }
}
