import XCTest
@testable import Subtitles

/// Fixed-seed fuzzing: every parser must return (not crash, not hang) on any bytes. Each test also has a time
/// budget so a hang or quadratic blow-up shows as a failure instead of a stuck run.
final class FuzzAndEntryPointTests: XCTestCase {

    // MARK: Seeds

    private let validSRT = "1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>Hello</i> {\\an8}world\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nSecond\r\nline\r\n\r\n"
    private let validVTT = "WEBVTT\n\nSTYLE\n::cue { color: red }\n\nREGION\nid:r1\nwidth:40%\n\nintro\n00:00:01.000 --> 00:00:02.500 line:80% align:start\n<v Bob><b>Hi</b> there</v>\n\n00:03.000 --> 00:04.000\nNext &amp; more\n"
    private let validASS = "[Script Info]\nScriptType: v4.00+\nPlayResX: 1920\nPlayResY: 1080\n\n[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, Bold, Italic, Alignment, MarginL, MarginR, MarginV\nStyle: Default,Arial,48,&H00FFFFFF,0,0,2,10,10,20\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:02.50,Default,,0,0,0,,{\\i1\\c&H0000FF&\\pos(100,200)}Hello{\\r} there\\Nline two\nDialogue: 1,0:00:03.00,0:00:04.00,Default,,0,0,0,,{\\p1}m 0 0 l 10 10{\\p0}\n"

    private func validPGS() -> Data {
        var e = PGSTestEncoder()
        let pal: [(UInt8, UInt8, UInt8, UInt8, UInt8)] = [(0, 16, 128, 128, 0), (1, 235, 128, 128, 255)]
        e.showSet(pts: 1, bitmaps: [(id: 0, x: 100, y: 900, w: 8, h: 4, indices: [UInt8](repeating: 1, count: 32), forced: false)], palette: pal)
        e.clearSet(pts: 2)
        return e.data
    }

    private func randomBytes(_ rng: inout SplitMix64, count: Int) -> Data {
        var d = Data(capacity: count)
        for _ in 0..<count { d.append(UInt8(truncatingIfNeeded: rng.next())) }
        return d
    }

    private func mutate(_ base: Data, _ rng: inout SplitMix64) -> Data {
        var bytes = [UInt8](base)
        if bytes.isEmpty { return base }
        let edits = 1 + Int(rng.next() % 8)
        for _ in 0..<edits {
            let i = Int(rng.next() % UInt64(bytes.count))
            switch rng.next() % 5 {
            case 0: bytes[i] = UInt8(truncatingIfNeeded: rng.next())
            case 1: bytes.remove(at: i); if bytes.isEmpty { return Data() }
            case 2: bytes.insert(UInt8(truncatingIfNeeded: rng.next()), at: i)
            case 3: bytes = Array(bytes[0..<max(1, i)])
            default: bytes[i] ^= UInt8(1 << (rng.next() % 8))
            }
        }
        return Data(bytes)
    }

    private func runAll(_ data: Data, fileName: String? = nil) {
        _ = SubtitleTextDecoder.decode(data)
        _ = SubtitleTextDecoder.decode(data, languageHint: "ja")
        _ = try? SubtitleFileParser.parse(data, fileName: fileName)
        _ = PGSParser.parse(data)
        let text = SubtitleTextDecoder.decode(data).text
        _ = SRTParser.parse(text)
        _ = WebVTTParser.parse(text)
        _ = ASSParser.parse(text)
        _ = VobSubIndexHeader.parse(text)
    }

    private func timed(_ budget: TimeInterval, _ label: String, _ body: () -> Void) {
        let t0 = Date()
        body()
        let dt = Date().timeIntervalSince(t0)
        XCTAssertLessThan(dt, budget, "\(label) took \(dt)s")
    }

    // MARK: Fuzz

    func testRandomBytesNeverCrash() {
        var rng = SplitMix64(seed: 0xF00D)
        timed(60, "random bytes") {
            for i in 0..<400 {
                let n = Int(rng.next() % 4096)
                runAll(randomBytes(&rng, count: n), fileName: i % 3 == 0 ? "x.srt" : nil)
            }
        }
    }

    func testMutatedValidFilesNeverCrash() {
        var rng = SplitMix64(seed: 0xBEEF)
        let seeds: [Data] = [Data(validSRT.utf8), Data(validVTT.utf8), Data(validASS.utf8), validPGS()]
        timed(90, "mutated files") {
            for round in 0..<1500 {
                let base = seeds[round % seeds.count]
                let m = mutate(base, &rng)
                runAll(m)
                // Parsed cues must still be well formed.
                if let parsed = try? SubtitleFileParser.parse(m).parsed {
                    for c in parsed.cues {
                        XCTAssertTrue(c.start.isFinite && c.end.isFinite)
                        XCTAssertGreaterThanOrEqual(c.start, 0)
                        XCTAssertGreaterThan(c.end, c.start)
                    }
                }
            }
        }
    }

    func testTruncationAtEveryByteNeverCrashes() {
        for base in [Data(validSRT.utf8), Data(validVTT.utf8), Data(validASS.utf8), validPGS()] {
            timed(30, "truncation") {
                for n in 0...base.count { runAll(base.prefix(n)) }
            }
        }
    }

    func testRandomTextWithTimingPunctuationNeverCrashes() {
        var rng = SplitMix64(seed: 77)
        let atoms = ["-->", "00:00:01,000", "1:2:3.4", "\n", "\r\n", "\r", "<i>", "</i>", "<b", "{\\an8}", "{\\", "}", "[Events]", "Dialogue:", "Format:", "WEBVTT", "&amp;", "&#x41;", "&#", ",", ".", ":", " ", "\t", "\u{FEFF}", "é", "日本", "𝄞", "\0", "1", "-1", "99999999999999999999", "0:00:00.00", "NOTE", "STYLE", "REGION", "\\N", "\\h", "&H00FF00FF&"]
        timed(60, "punctuation soup") {
            for _ in 0..<1500 {
                var s = ""
                for _ in 0..<(Int(rng.next() % 120)) { s += atoms[Int(rng.next() % UInt64(atoms.count))] }
                runAll(Data(s.utf8))
                runAll(Data(s.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }))
            }
        }
    }

    func testMatcherAndLanguageParsersNeverCrash() {
        var rng = SplitMix64(seed: 11)
        let pieces = ["Movie", ".", "en", "eng", "forced", "sdh", "hi", "zh", "Hans", "-", "_", " ", "(2020)", "S01E02", "mkv", "srt", "sup", "idx", "sub", "ass", "vtt", "é", "日本語", "\u{0}", "/", "..", "CC", "default"]
        timed(30, "names") {
            for _ in 0..<3000 {
                var name = ""
                for _ in 0..<(1 + Int(rng.next() % 8)) { name += pieces[Int(rng.next() % UInt64(pieces.count))] }
                _ = SubtitleTextDecoder.languageHint(fromFileName: name)
                _ = LanguageTag(name)
                _ = ExternalSubtitleMatcher.candidates(videoFileName: name + ".mkv", folderListing: [name, name + ".srt", "Movie.mkv", "Movie.en.srt", "Movie.sup"])
            }
        }
    }

    // MARK: Huge inputs

    private func srtTime(_ t: Double) -> String {
        let ms = Int((t * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }

    func testHundredThousandCuesParseAndSearch() throws {
        var srt = ""
        srt.reserveCapacity(10_000_000)
        for i in 0..<100_000 {
            let s = Double(i) * 0.5
            srt += "\(i + 1)\n\(srtTime(s)) --> \(srtTime(s + 3))\nLine \(i)\n\n"
        }
        let t0 = Date()
        let parsed = try SubtitleFileParser.parse(text: srt, format: .srt)
        XCTAssertEqual(parsed.cues.count, 100_000)
        let track = SubtitleTrack(cues: parsed.cues, format: .srt)
        XCTAssertEqual(track.activeCues(at: 25_000.1).count, 6)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 30)
    }

    private let assHead = "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,"

    func testHugeLineInSRT() {
        let big = String(repeating: "a", count: 5_000_000)
        timed(30, "5 MB line in SRT") {
            let p = SRTParser.parse("1\n00:00:01,000 --> 00:00:02,000\n\(big)\n")
            XCTAssertEqual(p.cues.count, 1)
        }
    }

    func testHugeLineInASS() {
        let big = String(repeating: "a", count: 5_000_000)
        timed(30, "5 MB line in ASS") {
            let p = ASSParser.parse(assHead + big + "\n")
            XCTAssertEqual(p.cues.count, 1)
        }
    }

    func testManyUnclosedTagsInSRT() {
        timed(30, "unclosed SRT tags") {
            _ = SRTParser.parse("1\n00:00:01,000 --> 00:00:02,000\n\(String(repeating: "<i><b>", count: 200_000))x\n")
        }
    }

    func testManyOverrideBlocksInASS() {
        timed(30, "unclosed ASS braces") {
            _ = ASSParser.parse(assHead + String(repeating: "{\\i1", count: 200_000) + "text\n")
            _ = ASSParser.parse(assHead + String(repeating: "{\\i1}a", count: 100_000) + "\n")
        }
    }

    func testManyTagsInVTT() {
        timed(30, "VTT tags") {
            _ = WebVTTParser.parse("WEBVTT\n\n00:01.000 --> 00:02.000\n\(String(repeating: "<c.a>", count: 200_000))x\n")
        }
    }

    func testFiveMegabytesWithoutNewlines() {
        timed(30, "no newlines, 4.5 MB of timestamps") {
            _ = SRTParser.parse(String(repeating: "00:00:01,000 --> 00:00:02,000 ", count: 150_000))
        }
    }

    func testHugeBinaryThroughDecoder() {
        var rng = SplitMix64(seed: 5)
        let data = randomBytes(&rng, count: 8_000_000)
        timed(60, "8 MB random through decoder") { _ = SubtitleTextDecoder.decode(data) }
    }

    func testManyOverlappingCues() {
        // 20,000 cues that all overlap one another.
        var cues: [SubtitleCue] = []
        for i in 0..<20_000 { cues.append(SubtitleCue(start: Double(i) * 0.001, end: 100 + Double(i) * 0.001, runs: [SubtitleRun("c\(i)")], format: .srt)) }
        let track = SubtitleTrack(cues: cues, format: .srt)
        timed(10, "overlap queries") {
            for q in stride(from: 0.0, to: 120.0, by: 0.5) { _ = track.activeCues(at: q) }
        }
        XCTAssertEqual(track.activeCues(at: 50).count, 20_000)
    }

    // MARK: Entry point

    func testEntryPointDetectsEachTextFormat() throws {
        let srt = try SubtitleFileParser.parse(Data(validSRT.utf8), fileName: "a.srt")
        XCTAssertEqual(srt.parsed.format, .srt)
        XCTAssertEqual(srt.parsed.cues.count, 2)
        let vtt = try SubtitleFileParser.parse(Data(validVTT.utf8), fileName: "a.vtt")
        XCTAssertEqual(vtt.parsed.format, .webVTT)
        XCTAssertEqual(vtt.parsed.cues.count, 2)
        let ass = try SubtitleFileParser.parse(Data(validASS.utf8), fileName: "a.ass")
        XCTAssertEqual(ass.parsed.format, .ass)
        XCTAssertEqual(ass.parsed.cues.count, 1, "the drawing-only line is dropped")
    }

    func testEntryPointDetectsFormatWhenTheExtensionLies() throws {
        let p = try SubtitleFileParser.parse(Data(validVTT.utf8), fileName: "movie.srt")
        XCTAssertEqual(p.parsed.format, .webVTT)
        let q = try SubtitleFileParser.parse(Data(validSRT.utf8), fileName: "movie.ass")
        XCTAssertEqual(q.parsed.format, .srt)
    }

    func testEntryPointThrowsForUnrecognisedAndImageFormats() {
        XCTAssertThrowsError(try SubtitleFileParser.parse(Data("just some words".utf8), fileName: "a.txt")) {
            XCTAssertEqual($0 as? SubtitleParseError, .unrecognizedFormat)
        }
        XCTAssertThrowsError(try SubtitleFileParser.parse(Data(), fileName: nil)) {
            XCTAssertEqual($0 as? SubtitleParseError, .unrecognizedFormat)
        }
        XCTAssertThrowsError(try SubtitleFileParser.parse(validPGS(), fileName: "a.sup")) {
            XCTAssertEqual($0 as? SubtitleParseError, .unsupportedFormat(.pgs))
        }
        XCTAssertThrowsError(try SubtitleFileParser.parse(validPGS(), fileName: nil)) {
            XCTAssertEqual($0 as? SubtitleParseError, .unsupportedFormat(.pgs)) // recognised by the "PG" magic
        }
        XCTAssertThrowsError(try SubtitleFileParser.parse(Data("# VobSub index file".utf8), fileName: "a.idx")) {
            XCTAssertEqual($0 as? SubtitleParseError, .unsupportedFormat(.vobSub))
        }
        XCTAssertThrowsError(try SubtitleFileParser.parse(Data([1, 2, 3]), fileName: "a.sub")) {
            XCTAssertEqual($0 as? SubtitleParseError, .unsupportedFormat(.vobSub))
        }
    }

    func testEntryPointDecodesOddEncodings() throws {
        let text = "1\n00:00:01,000 --> 00:00:02,000\nCafé naïve\n"
        var variants: [(String, Data)] = []
        variants.append(("utf8 bom", Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)))
        variants.append(("utf16le bom", Data([0xFF, 0xFE]) + text.data(using: .utf16LittleEndian)!))
        variants.append(("utf16be bom", Data([0xFE, 0xFF]) + text.data(using: .utf16BigEndian)!))
        variants.append(("utf16le no bom", text.data(using: .utf16LittleEndian)!))
        variants.append(("latin1", text.data(using: .isoLatin1)!))
        variants.append(("cp1252", text.data(using: .windowsCP1252)!))
        for (name, data) in variants {
            let r = try SubtitleFileParser.parse(data, fileName: "x.srt")
            XCTAssertEqual(r.parsed.cues.count, 1, name)
            XCTAssertEqual(r.parsed.cues.first?.plainText, "Café naïve", name)
        }
    }
}
