import XCTest
@testable import Subtitles

/// Every input is generated here. Multi-byte encodings are produced with Foundation's encoders (so a
/// Foundation that cannot encode them would make these tests fail, not skip).
final class TextDecodingTests: XCTestCase {

    private let sample = "Hello, world\nSecond line"

    private func bytes(_ s: String, _ enc: String.Encoding) throws -> Data {
        try XCTUnwrap(s.data(using: enc), "could not encode test text")
    }

    // MARK: Unicode forms

    func testUTF8WithoutBOM() throws {
        let r = SubtitleTextDecoder.decode(Data("Café — 日本語".utf8))
        XCTAssertEqual(r.text, "Café — 日本語")
        XCTAssertEqual(r.encoding, .utf8)
        XCTAssertEqual(r.invalidBytes, 0)
    }

    func testUTF8WithBOMIsStripped() {
        let r = SubtitleTextDecoder.decode(Data([0xEF, 0xBB, 0xBF]) + Data("Café".utf8))
        XCTAssertEqual(r.text, "Café")
        XCTAssertEqual(r.encoding, .utf8BOM)
    }

    func testPureASCII() {
        let r = SubtitleTextDecoder.decode(Data(sample.utf8))
        XCTAssertEqual(r.encoding, .ascii)
        XCTAssertEqual(r.text, sample)
    }

    func testEmptyData() {
        let r = SubtitleTextDecoder.decode(Data())
        XCTAssertEqual(r.text, "")
    }

    func testUTF16LittleEndianWithBOM() throws {
        let d = Data([0xFF, 0xFE]) + (try bytes("Привет, мир ☃ 😀", .utf16LittleEndian))
        let r = SubtitleTextDecoder.decode(d)
        XCTAssertEqual(r.text, "Привет, мир ☃ 😀")
        XCTAssertEqual(r.encoding, .utf16LEBOM)
    }

    func testUTF16BigEndianWithBOM() throws {
        let d = Data([0xFE, 0xFF]) + (try bytes("日本語のテキスト 😀", .utf16BigEndian))
        let r = SubtitleTextDecoder.decode(d)
        XCTAssertEqual(r.text, "日本語のテキスト 😀")
        XCTAssertEqual(r.encoding, .utf16BEBOM)
    }

    func testUTF16WithoutBOMGuessedFromZeroBytes() throws {
        let text = "1\n00:00:01,000 --> 00:00:02,000\nHello there\n"
        let le = SubtitleTextDecoder.decode(try bytes(text, .utf16LittleEndian))
        XCTAssertEqual(le.text, text)
        XCTAssertEqual(le.encoding, .utf16LE)
        let be = SubtitleTextDecoder.decode(try bytes(text, .utf16BigEndian))
        XCTAssertEqual(be.text, text)
        XCTAssertEqual(be.encoding, .utf16BE)
    }

    func testUTF32WithAndWithoutBOM() throws {
        let text = "Rare but real 😀 text\nline two"
        let leBOM = Data([0xFF, 0xFE, 0, 0]) + (try bytes(text, .utf32LittleEndian))
        XCTAssertEqual(SubtitleTextDecoder.decode(leBOM).text, text)
        XCTAssertEqual(SubtitleTextDecoder.decode(leBOM).encoding, .utf32LE)
        let beBOM = Data([0, 0, 0xFE, 0xFF]) + (try bytes(text, .utf32BigEndian))
        XCTAssertEqual(SubtitleTextDecoder.decode(beBOM).text, text)
        XCTAssertEqual(SubtitleTextDecoder.decode(beBOM).encoding, .utf32BE)
        let bare = SubtitleTextDecoder.decode(try bytes(text, .utf32LittleEndian))
        XCTAssertEqual(bare.text, text)
        XCTAssertEqual(bare.encoding, .utf32LE)
    }

    func testBrokenUTF8FallsBackToLegacyNotToGarbageUnicode() {
        // 0xE9 alone is "é" in Windows-1252 and an invalid UTF-8 start byte.
        let r = SubtitleTextDecoder.decode(Data([0x63, 0x61, 0x66, 0xE9]))
        XCTAssertEqual(r.text, "café")
        XCTAssertEqual(r.encoding, .windows1252)
        XCTAssertNotNil(r.note)
    }

    func testOverlongAndSurrogateUTF8AreRejected() {
        XCTAssertFalse(SubtitleTextDecoder.isValidUTF8([0xC0, 0x80]))           // overlong NUL
        XCTAssertFalse(SubtitleTextDecoder.isValidUTF8([0xED, 0xA0, 0x80]))     // surrogate
        XCTAssertFalse(SubtitleTextDecoder.isValidUTF8([0xF4, 0x90, 0x80, 0x80])) // above U+10FFFF
        XCTAssertFalse(SubtitleTextDecoder.isValidUTF8([0xE2, 0x82]))           // truncated
        XCTAssertTrue(SubtitleTextDecoder.isValidUTF8(Array("€😀".utf8)))
    }

    // MARK: Single-byte code pages

    func testWindows1252WithHintAndWithout() throws {
        let data = try bytes("Où est la bibliothèque? “Voilà” – naïve", .windowsCP1252)
        let hinted = SubtitleTextDecoder.decode(data, languageHint: "fr")
        XCTAssertEqual(hinted.text, "Où est la bibliothèque? “Voilà” – naïve")
        XCTAssertEqual(hinted.encoding, .windows1252)
        let bare = SubtitleTextDecoder.decode(data)
        XCTAssertEqual(bare.text, hinted.text)
        XCTAssertEqual(bare.encoding, .windows1252)
    }

    func testWindows1251CyrillicByHintAndByShape() throws {
        let text = "Привет, как дела? Это тестовые субтитры для проверки кодировки."
        let data = try bytes(text, .windowsCP1251)
        XCTAssertEqual(SubtitleTextDecoder.decode(data, languageHint: "ru").text, text)
        XCTAssertEqual(SubtitleTextDecoder.decode(data, languageHint: "ru").encoding, .windows1251)
        let bare = SubtitleTextDecoder.decode(data)
        XCTAssertEqual(bare.encoding, .windows1251)
        XCTAssertEqual(bare.text, text)
    }

    func testCentralEuropeanWindows1250() throws {
        let text = "Zażółć gęślą jaźń — ŠČŘŽ"
        let data = try bytes(text, .windowsCP1250)
        let r = SubtitleTextDecoder.decode(data, languageHint: "pl")
        XCTAssertEqual(r.text, text)
        XCTAssertEqual(r.encoding, .windows1250)
    }

    func testGreekTurkishHebrewArabic() throws {
        let cases: [(String, String.Encoding, String, SubtitleTextEncoding)] = [
            ("Καλημέρα κόσμε", .windowsCP1253, "el", .windows1253),
            ("İstanbul'da çok güzel şeyler", .windowsCP1254, "tr", .windows1254),
        ]
        for (text, enc, hint, expected) in cases {
            let r = SubtitleTextDecoder.decode(try bytes(text, enc), languageHint: hint)
            XCTAssertEqual(r.text, text, hint)
            XCTAssertEqual(r.encoding, expected, hint)
        }
        // Hebrew and Arabic: decode from known bytes (Foundation has no CP1255/1256 encoders here).
        let hebrew = SubtitleTextDecoder.decode(Data([0xE0, 0xE1, 0xE2, 0x20, 0xF9, 0xEC, 0xE5, 0xED]), languageHint: "he")
        XCTAssertEqual(hebrew.text, "אבג שלום")
        XCTAssertEqual(hebrew.encoding, .windows1255)
        let arabic = SubtitleTextDecoder.decode(Data([0xC7, 0xE1, 0xD3, 0xE1, 0xC7, 0xE3]), languageHint: "ar")
        XCTAssertEqual(arabic.text, "السلام")
        XCTAssertEqual(arabic.encoding, .windows1256)
    }

    func testEveryDefinedByteOfEveryTableDecodesToItsTableValue() {
        let all: [SubtitleTextEncoding] = SubtitleTextEncoding.allCases.filter { $0.table != nil }
        XCTAssertEqual(all.count, 15)
        for enc in all {
            guard let table = enc.table else { continue }
            XCTAssertEqual(table.count, 128, "\(enc)")
            for b in 0x80...0xFF {
                let r = SubtitleTextDecoder.decode(Data([UInt8(b)]), as: enc)
                let expected = table[b - 0x80]
                if expected == 0xFFFD {
                    XCTAssertEqual(r.invalidBytes, 1, "\(enc) 0x\(String(b, radix: 16))")
                } else {
                    XCTAssertEqual(r.text.unicodeScalars.first?.value, UInt32(expected), "\(enc) 0x\(String(b, radix: 16))")
                    XCTAssertEqual(r.invalidBytes, 0)
                }
            }
        }
    }

    func testKnownCodePageValues() {
        func scalar(_ enc: SubtitleTextEncoding, _ byte: UInt8) -> UInt32? {
            SubtitleTextDecoder.decode(Data([byte]), as: enc).text.unicodeScalars.first?.value
        }
        XCTAssertEqual(scalar(.windows1252, 0x80), 0x20AC)
        XCTAssertEqual(scalar(.windows1252, 0x93), 0x201C)
        XCTAssertEqual(scalar(.iso8859_1, 0xE9), 0xE9)
        XCTAssertEqual(scalar(.iso8859_15, 0xA4), 0x20AC)
        XCTAssertEqual(scalar(.iso8859_2, 0xA1), 0x0104)
        XCTAssertEqual(scalar(.windows1250, 0x8A), 0x0160)
        XCTAssertEqual(scalar(.windows1251, 0xC0), 0x0410)
        XCTAssertEqual(scalar(.windows1253, 0xC1), 0x0391)
        XCTAssertEqual(scalar(.windows1254, 0xDD), 0x0130)
        XCTAssertEqual(scalar(.windows1255, 0xE0), 0x05D0)
        XCTAssertEqual(scalar(.windows1256, 0xC7), 0x0627)
        XCTAssertEqual(scalar(.windows874, 0xA1), 0x0E01)
        XCTAssertEqual(scalar(.cp437, 0x80), 0x00C7)
        XCTAssertEqual(scalar(.cp850, 0x9B), 0x00F8)
    }

    // MARK: CJK

    func testShiftJISDetectedWithoutHint() throws {
        let text = "こんにちは、世界。これは字幕のテストです。\nありがとうございます"
        let r = SubtitleTextDecoder.decode(try bytes(text, .shiftJIS))
        XCTAssertEqual(r.encoding, .shiftJIS)
        XCTAssertEqual(r.text, text)
    }

    func testShiftJISWithHint() throws {
        let text = "字幕テスト"
        let r = SubtitleTextDecoder.decode(try bytes(text, .shiftJIS), languageHint: "ja")
        XCTAssertEqual(r.text, text)
        XCTAssertEqual(r.encoding, .shiftJIS)
    }

    func testEUCKRWithHintAndDetected() throws {
        let text = "안녕하세요. 자막 테스트입니다. 감사합니다."
        let data = try XCTUnwrap(text.data(using: String.Encoding(rawValue: 0x8000_0940)))
        let hinted = SubtitleTextDecoder.decode(data, languageHint: "ko")
        XCTAssertEqual(hinted.text, text)
        XCTAssertEqual(hinted.encoding, .eucKR)
        let bare = SubtitleTextDecoder.decode(data)
        XCTAssertEqual(bare.encoding, .eucKR)
        XCTAssertEqual(bare.text, text)
    }

    func testSimplifiedChineseGBKWithHint() throws {
        let text = "你好，世界。这是字幕测试。谢谢大家。"
        let data = try XCTUnwrap(text.data(using: String.Encoding(rawValue: 0x8000_0632)))
        for hint in ["zh", "zh-Hans", "chs", "zh-CN"] {
            let r = SubtitleTextDecoder.decode(data, languageHint: hint)
            XCTAssertEqual(r.text, text, hint)
            XCTAssertEqual(r.encoding, .gb18030, hint)
        }
    }

    func testTraditionalChineseBig5WithScriptHint() throws {
        let text = "你好，世界。這是字幕測試。謝謝大家。"
        let data = try XCTUnwrap(text.data(using: String.Encoding(rawValue: 0x8000_0A03)))
        for hint in ["zh-Hant", "cht", "zh-TW", "big5"] {
            let r = SubtitleTextDecoder.decode(data, languageHint: hint)
            XCTAssertEqual(r.text, text, hint)
            XCTAssertEqual(r.encoding, .big5, hint)
        }
    }

    // MARK: Hints from file names

    func testLanguageHintFromFileName() {
        XCTAssertEqual(SubtitleTextDecoder.languageHint(fromFileName: "Movie.en.srt"), "en")
        XCTAssertEqual(SubtitleTextDecoder.languageHint(fromFileName: "Movie (2019).fr.forced.srt"), "fr")
        XCTAssertEqual(SubtitleTextDecoder.languageHint(fromFileName: "Movie.en.sdh.srt"), "en")
        XCTAssertEqual(SubtitleTextDecoder.languageHint(fromFileName: "Movie.en.hi.srt"), "en")
        XCTAssertEqual(SubtitleTextDecoder.languageHint(fromFileName: "Movie.pt-BR.srt"), "pt-BR")
        XCTAssertEqual(SubtitleTextDecoder.languageHint(fromFileName: "Movie.zh-Hans.ass"), "zh-Hans")
        XCTAssertEqual(SubtitleTextDecoder.languageHint(fromFileName: "Movie.hi.srt"), "hi")
        XCTAssertEqual(SubtitleTextDecoder.languageHint(fromFileName: "en.srt"), "en")
        XCTAssertEqual(SubtitleTextDecoder.languageHint(fromFileName: "Subs/2_English.srt"), "English")
        XCTAssertNil(SubtitleTextDecoder.languageHint(fromFileName: "It.srt"))
        XCTAssertNil(SubtitleTextDecoder.languageHint(fromFileName: "Movie.sdh.srt"))
        XCTAssertNil(SubtitleTextDecoder.languageHint(fromFileName: "Movie.srt"))
    }

    func testFileNameHintSelectsCodePageThroughTheParserEntryPoint() throws {
        let srt = "1\n00:00:01,000 --> 00:00:02,000\nПривет\n"
        let data = try bytes(srt, .windowsCP1251)
        let (parsed, decoding) = try SubtitleFileParser.parse(data, fileName: "Film.ru.srt")
        XCTAssertEqual(decoding.encoding, .windows1251)
        XCTAssertEqual(parsed.cues.first?.plainText, "Привет")
    }

    // MARK: Robustness

    func testDecodeNeverFailsOnRandomBytes() {
        var rng = SplitMix64(seed: 0xDEC0DE)
        for length in [1, 2, 3, 5, 8, 33, 100, 1000, 5000] {
            for _ in 0..<20 {
                let d = Data((0..<length).map { _ in UInt8(truncatingIfNeeded: rng.next()) })
                for hint in [nil, "ja", "ko", "zh", "ru", "xx"] {
                    let r = SubtitleTextDecoder.decode(d, languageHint: hint)
                    XCTAssertGreaterThanOrEqual(r.invalidBytes, 0)
                }
            }
        }
    }
}

/// Small deterministic generator for fuzz-style tests.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ upper: Int) -> Int { Int(next() % UInt64(max(1, upper))) }
}
