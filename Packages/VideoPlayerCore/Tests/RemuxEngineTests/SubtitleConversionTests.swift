import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore

// WebVTT conversion rules (D1, D5): SRT / ASS / WebVTT block payloads to plain WebVTT cue text, timestamps, cue order,
// escaping, empty tracks and large inputs. Expected strings are written by hand from the rules in SubtitleRendition.swift.

final class WebVTTConversionTests: XCTestCase {
    private func srt(_ s: String) -> String? { WebVTTBuilder.cuePayload(Array(s.utf8), format: .srt) }
    private func ass(_ s: String) -> String? { WebVTTBuilder.cuePayload(Array(s.utf8), format: .ass) }
    private func vtt(_ s: String) -> String? { WebVTTBuilder.cuePayload(Array(s.utf8), format: .webVTT) }

    // MARK: SRT

    func testPlainText() {
        XCTAssertEqual(srt("Hello"), "Hello")
        XCTAssertEqual(srt("Ça va – 日本語 ♪"), "Ça va – 日本語 ♪", "non-ASCII text is kept as it is")
    }

    func testBasicItalicBoldUnderlineAreKept() {
        XCTAssertEqual(srt("Hello <i>world</i>"), "Hello <i>world</i>")
        XCTAssertEqual(srt("<b>Bold</b> and <u>under</u>"), "<b>Bold</b> and <u>under</u>")
        XCTAssertEqual(srt("<b><i>both</i></b>"), "<b><i>both</i></b>")
        XCTAssertEqual(srt("<I>upper</I>"), "<i>upper</i>", "tag names are case-insensitive")
        XCTAssertEqual(srt("<em>e</em> <strong>s</strong>"), "<i>e</i> <b>s</b>")
    }

    func testOtherMarkupIsDroppedAndTextKept() {
        XCTAssertEqual(srt("<font color=\"#ff0000\">Red</font> text"), "Red text", "D5: no colour or font of our own")
        XCTAssertEqual(srt("{\\an8}Top"), "Top", "position overrides are dropped")
        XCTAssertEqual(srt("<span class=x>a</span><br>b"), "a\nb")
    }

    func testAssStyleOverridesInsideSrt() {
        XCTAssertEqual(srt("{\\i1}slanted{\\i0} normal"), "<i>slanted</i> normal")
    }

    func testUnbalancedTagsAreRepaired() {
        XCTAssertEqual(srt("<i>open"), "<i>open</i>")
        XCTAssertEqual(srt("</i>orphan"), "orphan")
        XCTAssertEqual(srt("<b>one <i>two</b> three</i>"), "<b>one </b><b><i>two</i></b><i> three</i>")
    }

    func testEveryLineIsWrappedSeparately() {
        XCTAssertEqual(srt("<i>line one\nline two</i>"), "<i>line one</i>\n<i>line two</i>",
                       "a style tag never spans a line break, so no line is left half styled")
    }

    func testEscaping() {
        XCTAssertEqual(srt("Pip & Wren <3 you > me"), "Pip &amp; Wren &lt;3 you &gt; me")
        XCTAssertEqual(srt("a < b"), "a &lt; b")
        XCTAssertEqual(srt("Fish &amp; chips &lt;3 &#169; &unknown;"), "Fish &amp; chips &lt;3 &#169; &amp;unknown;",
                       "valid entities stay, unknown ones are escaped")
        XCTAssertEqual(srt("a\u{00A0}b"), "a&nbsp;b")
        XCTAssertFalse((srt("x --> y") ?? "").contains("-->"), "the cue separator can never appear inside a cue")
    }

    func testLineEndingsBlankLinesAndBOM() {
        XCTAssertEqual(srt("one\r\ntwo"), "one\ntwo")
        XCTAssertEqual(srt("one\n\n\ntwo"), "one\ntwo", "a blank line would end the cue, so it is removed")
        XCTAssertEqual(srt("a\\Nb"), "a\nb")
        XCTAssertEqual(WebVTTBuilder.cuePayload([0xEF, 0xBB, 0xBF] + Array("Hi".utf8), format: .srt), "Hi")
    }

    func testEmptyCuesGiveNothing() {
        XCTAssertNil(srt(""))
        XCTAssertNil(srt("   "))
        XCTAssertNil(srt("<i> </i>"))
        XCTAssertNil(srt("{\\an8}"))
        XCTAssertNil(WebVTTBuilder.cuePayload([], format: .srt))
    }

    func testInvalidUTF8DoesNotCrash() {
        let result = WebVTTBuilder.cuePayload([0x48, 0xFF, 0xFE, 0x69], format: .srt)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.hasPrefix("H") ?? false)
    }

    // MARK: ASS

    func testAssTextAfterTheEighthComma() {
        XCTAssertEqual(ass("0,0,Default,,0,0,0,,Hello, world"), "Hello, world")
        XCTAssertNil(ass("0,0,Default,,0,0,0"), "a block with too few fields has no text")
        XCTAssertNil(ass("0,0,Default,,0,0,0,,"), "an empty dialogue line")
    }

    func testAssLineBreaksAndSpaces() {
        XCTAssertEqual(ass("12,0,Default,,0,0,0,,Line one\\NLine two"), "Line one\nLine two")
        XCTAssertEqual(ass("1,0,Default,,0,0,0,,a\\nb"), "a b", "the soft break is a space")
        XCTAssertEqual(ass("1,0,Default,,0,0,0,,a\\hb"), "a&nbsp;b")
    }

    func testAssItalicAndBoldOverridesOnly() {
        XCTAssertEqual(ass("1,0,Default,,0,0,0,,{\\i1}Italic{\\i0} plain"), "<i>Italic</i> plain")
        XCTAssertEqual(ass("1,0,Default,,0,0,0,,{\\b1}Bold{\\b0}"), "<b>Bold</b>")
        XCTAssertEqual(ass("1,0,Default,,0,0,0,,{\\b700}Heavy"), "<b>Heavy</b>", "a weight of 1 or more is bold")
        XCTAssertEqual(ass("1,0,Default,,0,0,0,,{\\bord2\\shad1\\blur3}Not bold"), "Not bold", "\\bord and friends are not the bold flag")
        XCTAssertEqual(ass("1,0,Default,,0,0,0,,{\\an8\\pos(10,20)\\fad(100,200)\\c&HFF&}Moved"), "Moved")
        XCTAssertEqual(ass("1,0,Default,,0,0,0,,{\\i1}A{\\r}B"), "<i>A</i>B", "\\r ends the override")
        XCTAssertEqual(ass("1,0,Default,,0,0,0,,{\\i1\\b1}Both{\\i0}{\\b0} none"), "<b><i>Both</i></b> none")
    }

    func testAssDrawingsAreDropped() {
        XCTAssertNil(ass("1,0,Default,,0,0,0,,{\\p1}m 0 0 l 100 0 100 100{\\p0}"))
        XCTAssertEqual(ass("1,0,Default,,0,0,0,,Text{\\p1}m 0 0 l 1 1{\\p0} after"), "Text after")
    }

    // MARK: WebVTT payloads

    func testWebVTTPayloadKeepsOnlyItalicBoldUnderline() {
        XCTAssertEqual(vtt("<v Joe>Hello <c.yellow>there</c></v> <00:00:01.000>now"), "Hello there now")
        XCTAssertEqual(vtt("<i>slant</i> &amp; <b>bold</b>"), "<i>slant</i> &amp; <b>bold</b>")
        XCTAssertEqual(vtt("<ruby>漢<rt>kan</rt></ruby>"), "漢kan", "ruby is flattened to plain text")
    }

    // MARK: Timestamps and segments

    func testTimestamps() {
        XCTAssertEqual(WebVTTBuilder.timestamp(0), "00:00:00.000")
        XCTAssertEqual(WebVTTBuilder.timestamp(3661.5), "01:01:01.500")
        XCTAssertEqual(WebVTTBuilder.timestamp(59.9996), "00:01:00.000", "rounding carries")
        XCTAssertEqual(WebVTTBuilder.timestamp(36000.123), "10:00:00.123")
        XCTAssertEqual(WebVTTBuilder.timestamp(-5), "00:00:00.000", "never negative")
        XCTAssertEqual(WebVTTBuilder.timestamp(0.0121), "00:00:00.012")
    }

    func testEmptySegmentIsAValidHeaderOnly() {
        XCTAssertEqual(WebVTTBuilder.segment(cues: []), "WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:0,LOCAL:00:00:00.000\n")
    }

    func testCuesAreOrderedByStartAndStableOnTies() {
        let s = WebVTTBuilder.segment(cues: [VTTCue(start: 5, end: 6, text: "B"), VTTCue(start: 1, end: 2, text: "A"), VTTCue(start: 5, end: 7, text: "C")])
        XCTAssertEqual(s, """
        WEBVTT
        X-TIMESTAMP-MAP=MPEGTS:0,LOCAL:00:00:00.000

        00:00:01.000 --> 00:00:02.000
        A

        00:00:05.000 --> 00:00:06.000
        B

        00:00:05.000 --> 00:00:07.000
        C

        """)
    }

    func testCueEndNeverBeforeStart() {
        let s = WebVTTBuilder.segment(cues: [VTTCue(start: 2, end: 1, text: "X")])
        XCTAssertTrue(s.contains("00:00:02.000 --> 00:00:02.001"), s)
    }

    func testManyCuesAreConvertedQuickly() {
        var cues: [VTTCue] = []
        for n in 0..<50_000 { cues.append(VTTCue(start: Double(n) * 0.1, end: Double(n) * 0.1 + 0.08, text: "Line \(n) <i>x</i>")) }
        let t0 = Date()
        let s = WebVTTBuilder.segment(cues: cues)
        let elapsed = Date().timeIntervalSince(t0)
        XCTAssertEqual(s.components(separatedBy: " --> ").count - 1, 50_000)
        XCTAssertLessThan(elapsed, 20, "50,000 cues took \(elapsed) s")
        // Cue lines: blank line count equals cue count (every cue is followed by a blank line).
        XCTAssertEqual(s.components(separatedBy: "\n\n").count - 1, 50_000)
    }

    func testLongCueTextAndManyConversions() {
        let long = String(repeating: "word <i>it</i> & more ", count: 2000)
        let r = srt(long)
        XCTAssertNotNil(r)
        XCTAssertTrue((r ?? "").contains("&amp;"))
        var count = 0
        for n in 0..<5000 { if WebVTTBuilder.cuePayload(Array("0,0,D,,0,0,0,,{\\i1}Cue \(n){\\i0}".utf8), format: .ass) != nil { count += 1 } }
        XCTAssertEqual(count, 5000)
    }

    // MARK: Frames to cues (time base, compression)

    private func track(_ n: Int, zlib: Bool = false) -> MKVTrack {
        var t = MKVTrack(number: n, uid: 1, type: .subtitle, codecID: "S_TEXT/UTF8", codecPrivate: [], name: "", language: "eng",
                         isDefault: false, isEnabled: true, defaultDurationNs: nil, codecDelayNs: 0, seekPreRollNs: 0,
                         pixelWidth: 0, pixelHeight: 0, displayWidth: nil, displayHeight: nil, colour: nil, dolbyVision: nil,
                         sampleRate: 0, channels: 0, bitDepth: 0, strippedHeader: [])
        t.zlibCompressed = zlib
        return t
    }

    func testFramesBecomeCuesOnTheMediaTimeline() {
        let frames = [
            MKVFrame(track: 5, timeNs: 10_000_000_000, isKeyframe: true, durationNs: 2_000_000_000, data: ArraySlice(Array("later".utf8))),
            MKVFrame(track: 5, timeNs: 9_000_000_000, isKeyframe: true, durationNs: nil, data: ArraySlice(Array("no duration".utf8))),
            MKVFrame(track: 6, timeNs: 9_500_000_000, isKeyframe: true, durationNs: 1_000_000_000, data: ArraySlice(Array("other track".utf8))),
            MKVFrame(track: 5, timeNs: 20_000_000_000, isKeyframe: true, durationNs: 1_000_000_000, data: ArraySlice(Array("outside".utf8))),
        ]
        // File time 8 s is the first keyframe (origin); the video decode delay is 0.5 s.
        let cues = WebVTTBuilder.cues(frames: frames, track: track(5), format: .srt, lo: 8_000_000_000, hi: 15_000_000_000,
                                      originNs: 8_000_000_000, delaySeconds: 0.5)
        XCTAssertEqual(cues.map { $0.text }, ["later", "no duration"], "only this track and this time range, in file order")
        XCTAssertEqual(cues[0].start, 2.5, accuracy: 1e-9); XCTAssertEqual(cues[0].end, 4.5, accuracy: 1e-9)
        XCTAssertEqual(cues[1].start, 1.5, accuracy: 1e-9); XCTAssertEqual(cues[1].end, 4.5, accuracy: 1e-9, "no duration: 3 s (PROVISIONAL)")
    }

    func testCueBeforeTheStartIsClampedOrDropped() {
        let early = MKVFrame(track: 5, timeNs: 7_000_000_000, isKeyframe: true, durationNs: 2_000_000_000, data: ArraySlice(Array("clamped".utf8)))
        let gone = MKVFrame(track: 5, timeNs: 1_000_000_000, isKeyframe: true, durationNs: 1_000_000_000, data: ArraySlice(Array("gone".utf8)))
        let cues = WebVTTBuilder.cues(frames: [early, gone], track: track(5), format: .srt, lo: Int64.min, hi: Int64.max,
                                      originNs: 8_000_000_000, delaySeconds: 0)
        XCTAssertEqual(cues.map { $0.text }, ["clamped"])
        XCTAssertEqual(cues[0].start, 0); XCTAssertEqual(cues[0].end, 1, accuracy: 1e-9)
    }

    func testZlibTrackIsInflatedAndADamagedBlockIsSkipped() {
        let good = MKVFrame(track: 5, timeNs: 1_000_000_000, isKeyframe: true, durationNs: 1_000_000_000, data: ArraySlice(zlibStored(Array("packed".utf8))))
        let bad = MKVFrame(track: 5, timeNs: 2_000_000_000, isKeyframe: true, durationNs: 1_000_000_000, data: ArraySlice([0x78, 0x01, 0xFF, 0xFF]))
        let cues = WebVTTBuilder.cues(frames: [good, bad], track: track(5, zlib: true), format: .srt, lo: Int64.min, hi: Int64.max, originNs: 0, delaySeconds: 0)
        XCTAssertEqual(cues.map { $0.text }, ["packed"], "the damaged block is skipped, the others still play")
    }

    func testClassifier() {
        XCTAssertEqual(SubtitleClassifier.classify(codecID: "S_TEXT/UTF8"), .text(.srt))
        XCTAssertEqual(SubtitleClassifier.classify(codecID: "S_TEXT/ASS"), .text(.ass))
        XCTAssertEqual(SubtitleClassifier.classify(codecID: "S_TEXT/SSA"), .text(.ass))
        XCTAssertEqual(SubtitleClassifier.classify(codecID: "S_TEXT/WEBVTT"), .text(.webVTT))
        XCTAssertEqual(SubtitleClassifier.classify(codecID: "S_HDMV/PGS"), .picture)
        if case .unsupported(let why) = SubtitleClassifier.classify(codecID: "S_VOBSUB") { XCTAssertTrue(why.contains("VobSub")) } else { XCTFail("VobSub must be reported") }
        if case .unsupported = SubtitleClassifier.classify(codecID: "S_SOMETHING") {} else { XCTFail("unknown codecs are reported, not ignored") }
    }
}

// MARK: Inflate

final class InflateTests: XCTestCase {
    private func bytes(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex { let j = hex.index(i, offsetBy: 2); out.append(UInt8(hex[i..<j], radix: 16)!); i = j }
        return out
    }

    // FIXTURE: zlib streams made by Python's zlib module (levels 0, 1, 9) for the plain texts below.
    func testStoredFixedAndRepeatedBlocks() throws {
        let hello = Array("Hello, subtitle world!".utf8)
        XCTAssertEqual(try Inflate.zlib(bytes("7801011600e9ff48656c6c6f2c207375627469746c6520776f726c64215d130816")), hello, "stored block")
        XCTAssertEqual(try Inflate.zlib(bytes("7801f348cdc9c9d751282e4d2ac92cc9495528cf2fca495104005d130816")), hello, "fixed Huffman, level 1")
        XCTAssertEqual(try Inflate.zlib(bytes("78daf348cdc9c9d751282e4d2ac92cc9495528cf2fca495104005d130816")), hello, "fixed Huffman, level 9")
        XCTAssertEqual(try Inflate.zlib(bytes("78da4b4c4a4e240201002ab40eef")), Array(String(repeating: "abc", count: 13).utf8), "back references")
        XCTAssertEqual(try Inflate.zlib(bytes("7801030000000001")), [], "empty input")
        XCTAssertEqual(try Inflate.zlib(bytes("7801010000ffff00000001")), [], "empty stored block")
    }

    static let dynamicText = "Subtitle files hold timed lines of dialogue. Each cue has a start time, an end time and some text, "
        + "and a player shows the text while the clock sits between the two times. Some cues carry markup for "
        + "italic or bold, and a few carry positions on the screen. ??? Music plays softly in the background ??? "
        + "She whispers: \"We should leave before the storm arrives, because the road will flood by midnight.\" "
        + "He nods, picks up the lantern, and walks toward the door without another word. Outside, the wind "
        + "pulls at the shutters and the first heavy drops of rain strike the old tin roof.\n"
    static let dynamicHex = "78da35523baedc300cec738ac1ab173e409aad02a409526c919a96e41561ad6888d4d3dbdb87b6928e9fe17046d4a3afc65612362e4991a54418bf5244e1ea05d910998a3c7b5af0834246e809991404356a76a16fa08a54e7a8c7112a1e58fab2db95128e42efd4a05986c2f26c62645f7ba5a148d8a16c8a35d948a94ed4908b54173c4e4adfae08d4da1b2f6a7b3fb049031b150ef0687503ff576e69fc831ee2c42cd5fd4c5a0dcd372cb8dfeff8d5d5674f7deab2372b6ff044ad14f66793ee6c27f0e12517ac476afa1d1f7fd2e9a6fb8395449f8e4e2e659a5193f682afe6cfa437ef04ea3a5b4d28627029d88a48c4ea4638567e665b3ef033a14af49183c3ae707be74ca16aa9d5e96b50f18ec9a016af6e14f73dd85c8b3942bce6b9b4b8e07737e5e8e73971837dfae8a5f8ed6ccaccdd9c582fdeb3b0715343763b6fc426c775ff46fe1c6a8df7e9607e91ea4e645bbefd050eeecdee"

    // FIXTURE: made by Python's zlib at level 9; its first block is a dynamic Huffman block (BTYPE 2, checked below).
    func testDynamicHuffmanBlock() throws {
        let z = bytes(Self.dynamicHex)
        XCTAssertEqual((z[2] >> 1) & 3, 2, "the fixture really is a dynamic block")
        let out = try Inflate.zlib(z)
        XCTAssertEqual(String(decoding: out, as: UTF8.self), Self.dynamicText)
    }

    func testBadInputThrowsInsteadOfCrashing() {
        XCTAssertThrowsError(try Inflate.zlib([])) { XCTAssertEqual($0 as? Inflate.Failure, .truncated) }
        XCTAssertThrowsError(try Inflate.zlib([0x78, 0x00, 0x03, 0x00])) { XCTAssertEqual($0 as? Inflate.Failure, .badHeader) }
        XCTAssertThrowsError(try Inflate.zlib([0x00, 0x00, 0x03, 0x00])) { XCTAssertEqual($0 as? Inflate.Failure, .badHeader) }
        XCTAssertThrowsError(try Inflate.zlib(Array(bytes(Self.dynamicHex).prefix(40)))) { XCTAssertEqual($0 as? Inflate.Failure, .truncated) }
        XCTAssertThrowsError(try Inflate.zlib([0x78, 0x01, 0x07])) { XCTAssertEqual($0 as? Inflate.Failure, .badBlock) }     // reserved block type
        // Stored block whose length and its complement do not match.
        XCTAssertThrowsError(try Inflate.zlib([0x78, 0x01, 0x01, 0x05, 0x00, 0x00, 0x00, 1, 2, 3, 4, 5])) { XCTAssertEqual($0 as? Inflate.Failure, .badBlock) }
        // Fixed block that starts with a back reference (nothing to copy from yet).
        XCTAssertThrowsError(try Inflate.deflate([0x03, 0x02, 0x00])) { XCTAssertEqual($0 as? Inflate.Failure, .badDistance) }
    }

    func testOutputIsCapped() {
        XCTAssertThrowsError(try Inflate.zlib(bytes("78da4b4c4a4e240201002ab40eef"), maxOutput: 10)) { XCTAssertEqual($0 as? Inflate.Failure, .tooLarge) }
        XCTAssertThrowsError(try Inflate.zlib(zlibStored([UInt8](repeating: 1, count: 100)), maxOutput: 50)) { XCTAssertEqual($0 as? Inflate.Failure, .tooLarge) }
    }

    func testRandomBytesNeverCrash() {
        var seed: UInt64 = 0x1234_5678
        func next() -> UInt8 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return UInt8(truncatingIfNeeded: seed >> 33) }
        for round in 0..<400 {
            let n = 1 + round % 64
            let data: [UInt8] = [0x78, 0x9C] + (0..<n).map { _ in next() }
            _ = try? Inflate.zlib(data, maxOutput: 100_000)
        }
    }
}
