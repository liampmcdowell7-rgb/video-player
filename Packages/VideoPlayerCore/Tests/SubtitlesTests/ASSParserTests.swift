import XCTest
@testable import Subtitles

final class ASSParserTests: XCTestCase {

    private let script = """
    [Script Info]
    ; a comment
    Title: Test Script
    ScriptType: v4.00+
    WrapStyle: 2
    PlayResX: 1280
    PlayResY: 720
    ScaledBorderAndShadow: yes

    [V4+ Styles]
    Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
    Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,2,1,2,30,40,25,1
    Style: Sign,Impact,36,&H0000FFFF,&H000000FF,&H00000000,&H00000000,0,-1,1,0,90,95,2,0,1,3,0,8,10,10,10,0
    Style: *Alias,Courier New,20,&H00FF0000,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,1,0,5,0,0,0,1

    [Events]
    Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
    Dialogue: 0,0:00:01.00,0:00:03.50,Default,Bob,0,0,0,,Hello, world, with commas
    Comment: 0,0:00:01.00,0:00:03.50,Default,,0,0,0,,this is a comment
    Dialogue: 2,0:00:04.00,0:00:06.00,Sign,,15,16,17,Banner;20,{\\an7}Top left\\Nsecond{\\i1} slanted{\\i0}
    Dialogue: 0,0:00:07.00,0:00:08.00,Default,,0,0,0,,{\\pos(640,100)\\fad(200,300)\\b0\\c&H0000FF&\\fs60\\fnVerdana}Moved{\\r} reset
    """

    private func parsed() -> ParsedSubtitle { ASSParser.parse(script) }

    func testScriptInfo() throws {
        let s = try XCTUnwrap(parsed().ass)
        XCTAssertEqual(s.title, "Test Script")
        XCTAssertEqual(s.playResX, 1280)
        XCTAssertEqual(s.playResY, 720)
        XCTAssertEqual(s.wrapStyle, 2)
        XCTAssertTrue(s.scaledBorderAndShadow)
        XCTAssertFalse(s.isSSA)
        XCTAssertEqual(parsed().format, .ass)
    }

    func testStylesWithAllFields() throws {
        let s = try XCTUnwrap(parsed().ass)
        XCTAssertEqual(s.styleOrder, ["Default", "Sign", "Alias"])
        let d = try XCTUnwrap(s.styles["Default"])
        XCTAssertEqual(d.fontName, "Arial")
        XCTAssertEqual(d.fontSize, 48)
        XCTAssertEqual(d.primaryColor, SubtitleColor(red: 255, green: 255, blue: 255, alpha: 255))
        XCTAssertEqual(d.secondaryColor, SubtitleColor(red: 255, green: 0, blue: 0, alpha: 255))
        XCTAssertEqual(d.backColor.alpha, 127)    // &H80 means half transparent
        XCTAssertTrue(d.bold)
        XCTAssertFalse(d.italic)
        XCTAssertEqual(d.borderStyle, 1)
        XCTAssertEqual(d.outline, 2)
        XCTAssertEqual(d.shadow, 1)
        XCTAssertEqual(d.alignment, .bottomCenter)
        XCTAssertEqual([d.marginL, d.marginR, d.marginV], [30, 40, 25])
        let sign = try XCTUnwrap(s.styles["Sign"])
        XCTAssertEqual(sign.primaryColor, SubtitleColor(red: 255, green: 255, blue: 0))   // &H0000FFFF is BGR: R=FF G=FF B=00
        XCTAssertTrue(sign.italic)
        XCTAssertTrue(sign.underline)
        XCTAssertEqual(sign.scaleX, 90)
        XCTAssertEqual(sign.scaleY, 95)
        XCTAssertEqual(sign.spacing, 2)
        XCTAssertEqual(sign.alignment, SubtitleAlignment(horizontal: .center, vertical: .top))
        XCTAssertEqual(s.styles["Alias"]?.alignment, SubtitleAlignment(horizontal: .center, vertical: .middle))
    }

    func testDialogueFieldsCommasAndComments() {
        let p = parsed()
        XCTAssertEqual(p.cues.count, 3, "the Comment line must not become a cue")
        let c = p.cues[0]
        XCTAssertEqual(c.plainText, "Hello, world, with commas")
        XCTAssertEqual(c.start, 1, accuracy: 1e-9)
        XCTAssertEqual(c.end, 3.5, accuracy: 1e-9)
        XCTAssertEqual(c.styleName, "Default")
        XCTAssertEqual(c.speaker, "Bob")
        XCTAssertEqual(c.layer, 0)
        // Zero margins fall back to the style's.
        XCTAssertEqual([c.marginLeft, c.marginRight, c.marginVertical], [30, 40, 25])
        XCTAssertEqual(c.runs.first?.bold, true)   // from the style
    }

    func testOverrideTagsAndLayerAndMargins() {
        let c = parsed().cues[1]
        XCTAssertEqual(c.layer, 2)
        XCTAssertEqual(c.alignment, SubtitleAlignment(horizontal: .left, vertical: .top))   // \an7 beats the style's 8
        XCTAssertEqual([c.marginLeft, c.marginRight, c.marginVertical], [15, 16, 17])
        XCTAssertEqual(c.plainText, "Top left\nsecond slanted")
        // The Sign style is italic, so {\i1} changes nothing and the text stays one run.
        XCTAssertEqual(c.runs.count, 1)
        XCTAssertEqual(c.runs.first?.italic, true)
        XCTAssertEqual(c.runs.first?.underline, true)
    }

    func testPositionFadeColourFontAndReset() throws {
        let c = parsed().cues[2]
        XCTAssertEqual(c.position, SubtitlePosition(x: 640, y: 100, spaceWidth: 1280, spaceHeight: 720))
        XCTAssertEqual(try XCTUnwrap(c.fadeIn), 0.2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(c.fadeOut), 0.3, accuracy: 1e-9)
        XCTAssertEqual(c.runs.count, 2)
        XCTAssertEqual(c.runs[0].text, "Moved")
        XCTAssertEqual(c.runs[0].bold, false)                    // \b0 over a bold style
        XCTAssertEqual(c.runs[0].color, SubtitleColor(red: 255, green: 0, blue: 0))   // &H0000FF& is BGR: red
        XCTAssertEqual(c.runs[0].fontSize, 60)
        XCTAssertEqual(c.runs[0].fontName, "Verdana")
        XCTAssertEqual(c.runs[1].text, " reset")
        XCTAssertEqual(c.runs[1].bold, true)                     // \r back to the style
        XCTAssertNil(c.runs[1].color)
        XCTAssertNil(c.runs[1].fontName)
    }

    func testSSAv4Differences() throws {
        let ssa = """
        [Script Info]
        ScriptType: v4.00

        [V4 Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, TertiaryColour, BackColour, Bold, Italic, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, AlphaLevel, Encoding
        Style: Default,Arial,20,16777215,255,0,0,-1,0,1,2,2,2,10,10,10,0,0
        Style: Top,Arial,20,65280,255,0,0,0,0,1,2,2,6,10,10,10,0,0
        Style: Mid,Arial,20,65280,255,0,0,0,0,1,2,2,10,10,10,10,0,0

        [Events]
        Format: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: Marked=0,0:00:01.00,0:00:02.00,Top,,0,0,0,,SSA text
        Dialogue: Marked=0,0:00:03.00,0:00:04.00,Mid,,0,0,0,,{\\a3}legacy right
        """
        let p = ASSParser.parse(ssa)
        XCTAssertEqual(p.format, .ssa)
        let s = try XCTUnwrap(p.ass)
        XCTAssertTrue(s.isSSA)
        XCTAssertEqual(s.styles["Default"]?.primaryColor, SubtitleColor(red: 255, green: 255, blue: 255))
        XCTAssertEqual(s.styles["Top"]?.primaryColor, SubtitleColor(red: 0, green: 255, blue: 0))     // 65280 = 0x00FF00
        XCTAssertEqual(s.styles["Top"]?.alignment, SubtitleAlignment(horizontal: .center, vertical: .top))    // SSA 6 = top center
        XCTAssertEqual(s.styles["Mid"]?.alignment, SubtitleAlignment(horizontal: .center, vertical: .middle)) // SSA 10 = middle center
        XCTAssertEqual(p.cues.count, 2)
        XCTAssertEqual(p.cues[0].format, .ssa)
        XCTAssertEqual(p.cues[1].alignment, SubtitleAlignment(horizontal: .right, vertical: .bottom))   // \a3
        XCTAssertEqual(p.cues[0].layer, 0)
    }

    func testPlayResDefaults() throws {
        let onlyX = try XCTUnwrap(ASSParser.parse("[Script Info]\nPlayResX: 640\n").ass)
        XCTAssertEqual(onlyX.playResY, 480)
        let onlyY = try XCTUnwrap(ASSParser.parse("[Script Info]\nPlayResY: 600\n").ass)
        XCTAssertEqual(onlyY.playResX, 800)
        let none = try XCTUnwrap(ASSParser.parse("[Script Info]\nTitle: x\n").ass)
        XCTAssertEqual([none.playResX, none.playResY], [384, 288])
        XCTAssertFalse(none.playResGiven)
    }

    func testIgnoredTagsDoNotChangeText() {
        let text = "{\\fscx120\\fscy80\\fsp3\\frz30\\fax0.2\\bord4\\shad2\\be1\\blur2\\2c&H00FF00&\\3c&H0000FF&\\4c&H112233&\\2a&H80&\\clip(0,0,100,100)\\iclip(1,1,2,2)\\org(10,10)\\q2\\fe0\\k20\\kf30\\ko40\\fade(255,0,255,0,100,200,300)\\t(0,500,\\fs80\\c&HFF&)}Plain"
        let p = ASSParser.parse(wrapEvents(text))
        XCTAssertEqual(p.cues.first?.plainText, "Plain")
        XCTAssertEqual(p.cues.first?.runs.count, 1)
        XCTAssertNil(p.cues.first?.runs.first?.fontSize, "\\fs inside \\t( ) is an animation and must not apply")
        XCTAssertNil(p.cues.first?.runs.first?.color)
        XCTAssertNil(p.cues.first?.fadeIn)
    }

    func testDrawingModeIsDroppedAndDrawingOnlyCueRemoved() {
        let mixed = ASSParser.parse(wrapEvents("Before{\\p1}m 0 0 l 100 0 100 100{\\p0}After"))
        XCTAssertEqual(mixed.cues.first?.plainText, "BeforeAfter")
        let only = ASSParser.parse(wrapEvents("{\\p1}m 0 0 l 10 10{\\p0}"))
        XCTAssertEqual(only.cues.count, 0)
        XCTAssertTrue(only.warnings.contains { $0.contains("drawings") })
    }

    func testEscapesNewlineHardSpaceAndSoftBreak() {
        let wrap0 = ASSParser.parse(wrapEvents("a\\Nb\\nc\\hd"))
        XCTAssertEqual(wrap0.cues.first?.plainText, "a\nb c\u{00A0}d")
        let wrap2 = ASSParser.parse("[Script Info]\nWrapStyle: 2\n" + eventsOnly("a\\nb"))
        XCTAssertEqual(wrap2.cues.first?.plainText, "a\nb")
    }

    func testUnclosedBraceAndCommentBraceAreText() {
        XCTAssertEqual(ASSParser.parse(wrapEvents("open { brace")).cues.first?.plainText, "open { brace")
        XCTAssertEqual(ASSParser.parse(wrapEvents("a{just a comment}b")).cues.first?.plainText, "ab")
    }

    func testFormatLineOrderIsHonoured() {
        let s = """
        [Script Info]
        ScriptType: v4.00+

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, Bold, Alignment
        Style: Default,Arial,30,&H00FFFFFF,0,2

        [Events]
        Format: Start, End, Text, Style, Layer, Name
        Dialogue: 0:00:01.00,0:00:02.00,Text first, with comma,Default,5,Eve
        """
        // Text is not last here, which the standard forbids; the line is read with Text at its position and the
        // remaining commas end up in the last field. This pins the (documented) behaviour: no crash, one cue.
        let p = ASSParser.parse(s)
        XCTAssertEqual(p.cues.count, 1)
        XCTAssertEqual(p.cues.first?.start ?? 0, 1, accuracy: 1e-9)
    }

    func testMissingStyleUsesDefaultAndWarns() {
        let p = ASSParser.parse("[V4+ Styles]\nFormat: Name, Fontsize\nStyle: Default,33\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:02.00,Nope,,0,0,0,,x")
        XCTAssertEqual(p.cues.count, 1)
        XCTAssertEqual(p.cues.first?.styleName, "Default")
        XCTAssertTrue(p.warnings.contains { $0.contains("style") })
    }

    func testEmbeddedFontsSectionIsSkipped() throws {
        let s = """
        [Script Info]
        Title: with fonts

        [Fonts]
        fontname: Foo_0.ttf
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!
        Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,looks like a line but is font data

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:03.00,0:00:04.00,Default,,0,0,0,,real
        """
        let p = ASSParser.parse(s)
        XCTAssertEqual(p.cues.map(\.plainText), ["real"])
        XCTAssertEqual(p.ass?.hasEmbeddedData, true)
    }

    func testDialogueWithoutEventsHeaderAndBadTimes() {
        let p = ASSParser.parse("Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,no header\nDialogue: 0,bad,0:00:02.00,Default,,0,0,0,,bad time\nDialogue: 0,0:00:05.00,0:00:04.00,Default,,0,0,0,,backwards\nDialogue: 0,0:00:06.00\n")
        XCTAssertEqual(p.cues.map(\.plainText), ["no header"])
        XCTAssertFalse(p.warnings.isEmpty)
    }

    func testOverlappingLayersSortAndStack() {
        let s = eventsOnly("one", layer: 1, start: "0:00:01.00", end: "0:00:05.00") + "\n" + eventLine("two", layer: 0, start: "0:00:01.00", end: "0:00:03.00")
        let t = SubtitleTrack(parsed: ASSParser.parse(s))
        XCTAssertEqual(t.activeCues(at: 2).map(\.plainText), ["two", "one"], "same start: lower layer first")
        XCTAssertEqual(t.activeCues(at: 4).map(\.plainText), ["one"])
    }

    func testColourParsing() {
        XCTAssertEqual(SubtitleText.assColor("&H00FF0000"), SubtitleColor(red: 0, green: 0, blue: 255, alpha: 255))
        XCTAssertEqual(SubtitleText.assColor("&HFF0000FF")?.alpha, 0)
        XCTAssertEqual(SubtitleText.assColor("&HFF&"), SubtitleColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(SubtitleText.assColor("-1")?.alpha, 0)      // 0xFFFFFFFF: fully transparent white
        XCTAssertEqual(SubtitleText.assColor("16711680"), SubtitleColor(red: 0, green: 0, blue: 255))
        XCTAssertNil(SubtitleText.assColor("nonsense"))
        XCTAssertNil(SubtitleText.assColor(""))
    }

    func testAlphaOverrideAppliesToColour() {
        let p = ASSParser.parse(wrapEvents("{\\alpha&H80&}half"))
        XCTAssertEqual(p.cues.first?.runs.first?.color?.alpha, 127)
        XCTAssertEqual(p.cues.first?.runs.first?.color?.red, 255)   // style primary is white
    }

    func testEntryPointDetectsAssAndSsa() throws {
        XCTAssertEqual(try SubtitleFileParser.parse(text: script).format, .ass)
        XCTAssertEqual(try SubtitleFileParser.parse(text: "[Script Info]\nScriptType: v4.00\n\n[V4 Styles]\nFormat: Name\nStyle: Default\n").format, .ssa)
        XCTAssertThrowsError(try SubtitleFileParser.parse(text: "just some words"))
    }

    // MARK: Helpers

    private func eventLine(_ text: String, layer: Int = 0, start: String = "0:00:01.00", end: String = "0:00:02.00") -> String {
        "Dialogue: \(layer),\(start),\(end),Default,,0,0,0,,\(text)"
    }

    private func eventsOnly(_ text: String, layer: Int = 0, start: String = "0:00:01.00", end: String = "0:00:02.00") -> String {
        "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n" + eventLine(text, layer: layer, start: start, end: end)
    }

    private func wrapEvents(_ text: String) -> String {
        "[Script Info]\nPlayResX: 100\nPlayResY: 100\n\n[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, Bold, Alignment\nStyle: Default,Arial,20,&H00FFFFFF,-1,2\n\n" + eventsOnly(text)
    }
}
