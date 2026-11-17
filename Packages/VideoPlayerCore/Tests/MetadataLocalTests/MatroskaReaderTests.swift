import XCTest
import Foundation
import VideoPlayerCore
@testable import MetadataLocal

// All files here are built by the test-side writer in MatroskaWriter.swift from the Matroska specification.
// They are hand-written test data, not recordings of any real muxer.

private let sec: UInt64 = 1_000_000_000

/// A file with HDR + Dolby Vision video, three audio tracks, three subtitle tracks, two editions, tags and attachments.
func richFile() -> TFile {
    var f = TFile()
    f.info = TInfo(title: "Test Movie", muxingApp: "test-writer 1.0", writingApp: "test-writer app", timecodeScale: 1_000_000, duration: 5_400_000, dateUTC: 0)
    f.tracks = [
        TTrack(number: 1, uid: 1001, type: 1, codec: "V_MPEGH/ISO/HEVC", name: "Main", isDefault: true, defaultDuration: 41_708_333,
               codecPrivate: [1, 2, 3], video: (3840, 2160, 3840, 2160),
               colour: TColour(matrix: 9, transfer: 16, primaries: 9, range: 1, bits: 10, maxCLL: 1000, maxFALL: 400, mastering: true),
               dolbyVision: MKVBuilder.dolbyVisionRecord(profile: 8, level: 6, compat: 1)),
        TTrack(number: 2, uid: 1002, type: 2, codec: "A_EAC3", name: "English Dolby Atmos 7.1", language: "eng", isDefault: true,
               audio: (48000, 8, nil)),
        TTrack(number: 3, uid: 1003, type: 2, codec: "A_TRUEHD", language: "jpn", isDefault: false, audio: (48000, 8, 24)),
        TTrack(number: 4, uid: 1004, type: 2, codec: "A_AAC", name: "Atmos?", language: "fre", isDefault: false, audio: (44100, 2, nil)),
        TTrack(number: 5, uid: 1005, type: 0x11, codec: "S_HDMV/PGS", language: "eng", isDefault: false, isForced: true),
        TTrack(number: 6, uid: 1006, type: 0x11, codec: "S_TEXT/UTF8", name: "Español (Latinoamérica)", language: "spa", bcp47: "es-419", isDefault: false),
        TTrack(number: 7, uid: 1007, type: 0x11, codec: "S_TEXT/ASS", language: "jpn", isDefault: true, isHearingImpaired: true),
    ]
    f.editions = [
        TEdition(uid: 100, hidden: false, isDefault: true, ordered: false, atoms: [
            TAtom(uid: 1, start: 0, end: 90 * sec, displays: [TDisplay(title: "Intro", languages: ["eng"]), TDisplay(title: "Générique", languages: ["fre"])]),
            TAtom(uid: 2, start: 90 * sec, displays: [TDisplay(title: "Act 1", languages: ["eng"])], children: [
                TAtom(uid: 21, start: 90 * sec, displays: [TDisplay(title: "Scene A")]),
                TAtom(uid: 22, start: 300 * sec, displays: [TDisplay(title: "Scene B")]),
            ]),
            TAtom(uid: 3, start: 4000 * sec, hidden: true, displays: [TDisplay(title: "Secret")]),
            TAtom(uid: 4, start: 5000 * sec, enabled: false, displays: [TDisplay(title: "Credits", languages: ["eng"], bcp47: ["en-US"], countries: ["US"])]),
        ]),
        TEdition(uid: 200, hidden: true, isDefault: false, ordered: true, atoms: [
            TAtom(uid: 5, start: 0, displays: [TDisplay(title: "Director's Cut Start")]),
        ]),
    ]
    f.tags = [
        TTag(targetValue: 50, targetType: "MOVIE", simple: [
            TSimple(name: "TITLE", string: "Test Movie"),
            TSimple(name: "ACTOR", string: "A. Person", children: [TSimple(name: "CHARACTER", string: "Lead")]),
        ]),
        TTag(targetValue: 30, trackUID: 1001, simple: [TSimple(name: "BPS", string: "12345678")]),
    ]
    f.attachments = [
        TAttachment(name: "font.ttf", mime: "application/x-truetype-font", data: [UInt8](repeating: 7, count: 300)),
        TAttachment(name: "cover.jpg", mime: "image/jpeg", data: [UInt8](repeating: 9, count: 100)),
    ]
    return f
}

func readMKV(_ built: BuiltMKV, reader: MatroskaReader = MatroskaReader(), log: ReadLog = ReadLog(), beyondEnd: BeyondEnd = .throwError) async throws -> EmbeddedMetadata {
    try await reader.read(using: memoryReader(built.bytes, log: log, beyondEnd: beyondEnd))
}

func assertSameContent(_ a: EmbeddedMetadata, _ b: EmbeddedMetadata, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.docType, b.docType, file: file, line: line)
    XCTAssertEqual(a.info, b.info, file: file, line: line)
    XCTAssertEqual(a.tracks, b.tracks, file: file, line: line)
    XCTAssertEqual(a.editions, b.editions, file: file, line: line)
    XCTAssertEqual(a.tags, b.tags, file: file, line: line)
    XCTAssertEqual(a.attachments, b.attachments, file: file, line: line)
}

final class MatroskaReaderTests: XCTestCase {
    // MARK: Info

    func testInfoFields() async throws {
        let m = try await readMKV(MKVBuilder.build(richFile()))
        XCTAssertEqual(m.docType, "matroska")
        XCTAssertEqual(m.info?.title, "Test Movie")
        XCTAssertEqual(m.info?.muxingApp, "test-writer 1.0")
        XCTAssertEqual(m.info?.writingApp, "test-writer app")
        XCTAssertEqual(m.info?.timecodeScale, 1_000_000)
        XCTAssertEqual(try XCTUnwrap(m.durationSeconds), 5400, accuracy: 0.0001)
        XCTAssertEqual(m.info?.dateUTC, Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(m.warnings, [])
    }

    func testDurationUsesTimecodeScale() async throws {
        var f = TFile()
        f.tracks = [TTrack(video: (640, 360, nil, nil))]
        f.info = TInfo(title: nil, timecodeScale: 500_000, duration: 20_000)
        let m = try await readMKV(MKVBuilder.build(f))
        XCTAssertEqual(try XCTUnwrap(m.durationSeconds), 10.0, accuracy: 1e-9)
        XCTAssertNil(m.info?.title)
    }

    func testDateUTCNonZero() async throws {
        var f = TFile()
        f.tracks = [TTrack(video: (640, 360, nil, nil))]
        f.info.dateUTC = 86_400 * 1_000_000_000 // one day after 2001-01-01
        let m = try await readMKV(MKVBuilder.build(f))
        XCTAssertEqual(m.info?.dateUTC, Date(timeIntervalSinceReferenceDate: 86_400))
    }

    func testWebMDocType() async throws {
        var f = richFile()
        f.docType = "webm"
        let m = try await readMKV(MKVBuilder.build(f))
        XCTAssertEqual(m.docType, "webm")
        XCTAssertEqual(m.detailRows.first, FileDetailRow(label: "Container", value: "WebM"))
    }

    // MARK: Video

    func testVideoTrackAndFrameRate() async throws {
        let m = try await readMKV(MKVBuilder.build(richFile()))
        let v = try XCTUnwrap(m.videoTracks.first)
        XCTAssertEqual(v.number, 1)
        XCTAssertEqual(v.uid, 1001)
        XCTAssertEqual(v.type, .video)
        XCTAssertEqual(v.codecID, "V_MPEGH/ISO/HEVC")
        XCTAssertEqual(v.videoCodecLabel, "HEVC")
        XCTAssertEqual(v.name, "Main")
        XCTAssertEqual(v.pixelWidth, 3840)
        XCTAssertEqual(v.pixelHeight, 2160)
        XCTAssertEqual(v.displayWidth, 3840)
        XCTAssertEqual(v.codecPrivate, Data([1, 2, 3]))
        XCTAssertEqual(try XCTUnwrap(v.frameRate), 23.976, accuracy: 0.0005)
        XCTAssertEqual(v.language, "eng", "Language defaults to eng when the file omits it, as the spec says")
    }

    func testHDRColourMetadata() async throws {
        let m = try await readMKV(MKVBuilder.build(richFile()))
        let c = try XCTUnwrap(m.videoTracks.first?.colour)
        XCTAssertEqual(c.matrixCoefficients, 9)
        XCTAssertEqual(c.transferCharacteristics, 16)
        XCTAssertEqual(c.transfer, .pq)
        XCTAssertEqual(c.primaries, 9)
        XCTAssertEqual(c.range, 1)
        XCTAssertEqual(c.bitsPerChannel, 10)
        XCTAssertEqual(c.maxCLL, 1000)
        XCTAssertEqual(c.maxFALL, 400)
        let md = try XCTUnwrap(c.mastering)
        XCTAssertEqual(try XCTUnwrap(md.redX), 0.68, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(md.greenY), 0.69, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(md.whiteY), 0.329, accuracy: 1e-9)
        XCTAssertEqual(md.luminanceMax, 1000)
        XCTAssertEqual(try XCTUnwrap(md.luminanceMin), 0.0001, accuracy: 1e-9)
    }

    func testTransferClassification() {
        var c = ColourInfo()
        XCTAssertEqual(c.transfer, .unknown)
        c.transferCharacteristics = 16
        XCTAssertEqual(c.transfer, .pq)
        c.transferCharacteristics = 18
        XCTAssertEqual(c.transfer, .hlg)
        c.transferCharacteristics = 1
        XCTAssertEqual(c.transfer, .sdr)
    }

    func testHLGVideo() async throws {
        var f = TFile()
        f.tracks = [TTrack(video: (1920, 1080, nil, nil), colour: TColour(matrix: 9, transfer: 18, primaries: 9, bits: 10))]
        let m = try await readMKV(MKVBuilder.build(f))
        XCTAssertEqual(m.videoTracks.first?.colour?.transfer, .hlg)
        XCTAssertNil(m.videoTracks.first?.dolbyVision)
        XCTAssertTrue(try XCTUnwrap(m.videoTracks.first).summary.contains("HDR (HLG)"))
    }

    // MARK: Dolby Vision

    func testDolbyVisionProfile81() async throws {
        let m = try await readMKV(MKVBuilder.build(richFile()))
        let dv = try XCTUnwrap(m.videoTracks.first?.dolbyVision)
        XCTAssertEqual(dv.profile, 8)
        XCTAssertEqual(dv.level, 6)
        XCTAssertEqual(dv.baseLayerCompatibilityID, 1)
        XCTAssertTrue(dv.rpuPresent)
        XCTAssertFalse(dv.elPresent)
        XCTAssertTrue(dv.blPresent)
        XCTAssertEqual(dv.boxType, "dvvC")
        XCTAssertEqual(dv.label, "8.1")
        XCTAssertEqual(dv.versionMajor, 1)
    }

    func testDolbyVisionProfile5AndDvcCBox() async throws {
        var f = TFile()
        var t = TTrack(video: (3840, 2160, nil, nil))
        t.dolbyVision = MKVBuilder.dolbyVisionRecord(profile: 5, level: 9, compat: 0)
        t.dolbyVisionBox = 0x6476_6343
        f.tracks = [t]
        let read = try await readMKV(MKVBuilder.build(f))
        let dv = try XCTUnwrap(read.videoTracks.first?.dolbyVision)
        XCTAssertEqual(dv.profile, 5)
        XCTAssertEqual(dv.level, 9)
        XCTAssertEqual(dv.boxType, "dvcC")
        XCTAssertEqual(dv.label, "5")
    }

    func testDolbyVisionProfile7WithEnhancementLayerAndHighLevel() async throws {
        var f = TFile()
        var t = TTrack(video: (3840, 2160, nil, nil))
        // Level 42 needs the 6th bit that is stored in byte 2.
        t.dolbyVision = MKVBuilder.dolbyVisionRecord(profile: 7, level: 42, rpu: true, el: true, bl: true, compat: 6)
        f.tracks = [t]
        let read = try await readMKV(MKVBuilder.build(f))
        let dv = try XCTUnwrap(read.videoTracks.first?.dolbyVision)
        XCTAssertEqual(dv.profile, 7)
        XCTAssertEqual(dv.level, 42)
        XCTAssertTrue(dv.elPresent)
        XCTAssertEqual(dv.baseLayerCompatibilityID, 6)
    }

    func testDolbyVisionRecordTooShortIsIgnoredWithWarning() async throws {
        var f = TFile()
        var t = TTrack(video: (3840, 2160, nil, nil))
        t.dolbyVision = [1, 0, 16]
        f.tracks = [t]
        let m = try await readMKV(MKVBuilder.build(f))
        XCTAssertNil(m.videoTracks.first?.dolbyVision)
        XCTAssertTrue(m.warnings.contains { $0.contains("shorter than 5 bytes") })
        XCTAssertNil(DolbyVisionConfig(record: [1, 0], boxType: "dvcC"))
    }

    func testUnknownBlockAdditionMappingTypeIsIgnored() async throws {
        var f = TFile()
        var t = TTrack(video: (1920, 1080, nil, nil))
        t.dolbyVision = [1, 0, 16, 9, 16]
        t.dolbyVisionBox = 0x1234_5678
        f.tracks = [t]
        let m = try await readMKV(MKVBuilder.build(f))
        XCTAssertNil(m.videoTracks.first?.dolbyVision)
    }

    // MARK: Audio

    func testAudioTracks() async throws {
        let m = try await readMKV(MKVBuilder.build(richFile()))
        XCTAssertEqual(m.audioTracks.count, 3)
        let eac3 = m.audioTracks[0]
        XCTAssertEqual(eac3.audioCodec, .eac3)
        XCTAssertEqual(eac3.channels, 8)
        XCTAssertEqual(eac3.samplingFrequency, 48000)
        XCTAssertEqual(eac3.language, "eng")
        XCTAssertTrue(eac3.isDefault)
        let thd = m.audioTracks[1]
        XCTAssertEqual(thd.audioCodec, .truehd)
        XCTAssertEqual(thd.bitDepth, 24)
        XCTAssertFalse(thd.isDefault)
        XCTAssertEqual(thd.language, "jpn")
        let aac = m.audioTracks[2]
        XCTAssertEqual(aac.audioCodec, .aac)
        XCTAssertEqual(aac.samplingFrequency, 44100)
        XCTAssertEqual(aac.channels, 2)
    }

    func testAtmosIsOnlyEverAHintFromTheName() async throws {
        let m = try await readMKV(MKVBuilder.build(richFile()))
        XCTAssertEqual(m.audioTracks[0].atmos, .nameSuggests, "E-AC-3 named Atmos: a hint, not proof")
        XCTAssertEqual(m.audioTracks[1].atmos, .unknown, "TrueHD with no name: the header cannot say")
        XCTAssertEqual(m.audioTracks[2].atmos, .unknown, "AAC cannot carry Atmos even if the name says so")
    }

    func testAudioCodecMapping() {
        func kind(_ id: String) -> AudioCodecKind? {
            var t = MatroskaTrack(number: 1, type: .audio, codecID: id)
            t.language = "eng"
            return t.audioCodec
        }
        XCTAssertEqual(kind("A_AC3"), .ac3)
        XCTAssertEqual(kind("A_EAC3"), .eac3)
        XCTAssertEqual(kind("A_TRUEHD"), .truehd)
        XCTAssertEqual(kind("A_MLP"), .mlp)
        XCTAssertEqual(kind("A_DTS"), .dts)
        XCTAssertEqual(kind("A_DTS/EXPRESS"), .dts)
        XCTAssertEqual(kind("A_DTS/LOSSLESS"), .dts)
        XCTAssertEqual(kind("A_AAC/MPEG4/LC"), .aac)
        XCTAssertEqual(kind("A_FLAC"), .flac)
        XCTAssertEqual(kind("A_OPUS"), .opus)
        XCTAssertEqual(kind("A_VORBIS"), .vorbis)
        XCTAssertEqual(kind("A_PCM/INT/LIT"), .pcm)
        XCTAssertEqual(kind("A_PCM/FLOAT/IEEE"), .pcm)
        XCTAssertEqual(kind("A_MPEG/L3"), .mp3)
        XCTAssertEqual(kind("A_ALAC"), .alac)
        XCTAssertEqual(kind("A_SOMETHING"), .other)
        XCTAssertNil(MatroskaTrack(number: 1, type: .video, codecID: "A_AC3").audioCodec)
    }

    // MARK: Subtitles

    func testSubtitleTracks() async throws {
        let m = try await readMKV(MKVBuilder.build(richFile()))
        XCTAssertEqual(m.subtitleTracks.count, 3)
        let pgs = m.subtitleTracks[0]
        XCTAssertEqual(pgs.subtitleFormat, .pgs)
        XCTAssertTrue(try XCTUnwrap(pgs.subtitleFormat).isImageBased)
        XCTAssertTrue(pgs.isForced)
        XCTAssertFalse(pgs.isDefault)
        let srt = m.subtitleTracks[1]
        XCTAssertEqual(srt.subtitleFormat, .srt)
        XCTAssertFalse(try XCTUnwrap(srt.subtitleFormat).isImageBased)
        XCTAssertEqual(srt.languageBCP47, "es-419")
        XCTAssertEqual(srt.name, "Español (Latinoamérica)")
        let ass = m.subtitleTracks[2]
        XCTAssertEqual(ass.subtitleFormat, .ass)
        XCTAssertTrue(ass.isHearingImpaired)
        XCTAssertTrue(ass.isDefault)
    }

    func testSubtitleCodecMapping() {
        func fmt(_ id: String) -> SubtitleFormat? { MatroskaTrack(number: 1, type: .subtitle, codecID: id).subtitleFormat }
        XCTAssertEqual(fmt("S_TEXT/UTF8"), .srt)
        XCTAssertEqual(fmt("S_TEXT/ASS"), .ass)
        XCTAssertEqual(fmt("S_TEXT/SSA"), .ssa)
        XCTAssertEqual(fmt("S_TEXT/WEBVTT"), .webvtt)
        XCTAssertEqual(fmt("S_HDMV/PGS"), .pgs)
        XCTAssertEqual(fmt("S_VOBSUB"), .vobsub)
        XCTAssertEqual(fmt("S_DVBSUB"), .dvb)
        XCTAssertEqual(fmt("S_WHATEVER"), .other)
        XCTAssertTrue(SubtitleFormat.vobsub.isImageBased)
        XCTAssertFalse(SubtitleFormat.webvtt.isImageBased)
    }

    func testTrackFlagDefaults() async throws {
        var f = TFile()
        f.tracks = [TTrack(number: 1, uid: 5, type: 0x11, codec: "S_TEXT/UTF8")]
        let read = try await readMKV(MKVBuilder.build(f))
        let t = try XCTUnwrap(read.tracks.first)
        XCTAssertTrue(t.isEnabled)
        XCTAssertTrue(t.isDefault)
        XCTAssertFalse(t.isForced)
        XCTAssertFalse(t.isHearingImpaired)
        XCTAssertEqual(t.language, "eng")
    }

    func testTrackEnabledFlagFalse() async throws {
        var f = TFile()
        f.tracks = [TTrack(number: 1, uid: 5, type: 0x11, codec: "S_TEXT/UTF8", isEnabled: false)]
        let read = try await readMKV(MKVBuilder.build(f))
        XCTAssertFalse(try XCTUnwrap(read.tracks.first).isEnabled)
    }

    func testTrackWithoutNumberIsIgnoredWithWarning() throws {
        let noNumber = W.master(MKV.trackEntry, [W.uint(MKV.trackType, 1), W.string(MKV.codecID, "V_AV1")])
        let withNumber = W.master(MKV.trackEntry, [W.uint(MKV.trackNumber, 2), W.uint(MKV.trackType, 1), W.string(MKV.codecID, "V_AV1")])
        let m = try ingestTop(W.master(MKV.tracks, [noNumber, withNumber]))
        XCTAssertEqual(m.tracks.map(\.number), [2])
        XCTAssertTrue(m.warnings.contains { $0.contains("without a track number") })
    }

    func testUnknownTrackTypeAndLanguageOverride() throws {
        let entry = W.master(MKV.trackEntry, [
            W.uint(MKV.trackNumber, 4), W.uint(MKV.trackType, 99), W.string(MKV.codecID, "X_FUTURE"),
            W.element(MKV.language, Array("ger".utf8) + [0, 0]),
        ])
        let t = try XCTUnwrap(try ingestTop(W.master(MKV.tracks, [entry])).tracks.first)
        XCTAssertEqual(t.type, .unknown)
        XCTAssertEqual(t.language, "ger", "NUL padding is removed")
        XCTAssertNil(t.audioCodec)
    }

    func testContentEncodingIsFlagged() throws {
        let entry = W.master(MKV.trackEntry, [
            W.uint(MKV.trackNumber, 1), W.uint(MKV.trackType, 1), W.string(MKV.codecID, "V_MPEG4/ISO/AVC"),
            W.master(MKV.contentEncodings, []),
        ])
        XCTAssertTrue(try XCTUnwrap(try ingestTop(W.master(MKV.tracks, [entry])).tracks.first).hasContentEncoding)
    }

    // MARK: Chapters

    func testEditionsAndChaptersInHead() async throws {
        let m = try await readMKV(MKVBuilder.build(richFile()))
        XCTAssertEqual(m.editions.count, 2)
        let e1 = m.editions[0]
        XCTAssertEqual(e1.uid, 100)
        XCTAssertFalse(e1.isHidden)
        XCTAssertTrue(e1.isDefault)
        XCTAssertFalse(e1.isOrdered)
        XCTAssertEqual(e1.chapters.count, 4)
        let e2 = m.editions[1]
        XCTAssertTrue(e2.isHidden)
        XCTAssertTrue(e2.isOrdered)
        XCTAssertEqual(e2.chapters.first?.displays.first?.title, "Director's Cut Start")
    }

    func testChapterTimesFlagsAndNesting() async throws {
        let m = try await readMKV(MKVBuilder.build(richFile()))
        let chapters = m.editions[0].chapters
        let intro = chapters[0]
        XCTAssertEqual(intro.uid, 1)
        XCTAssertEqual(intro.startNanos, 0)
        XCTAssertEqual(intro.endNanos, Int64(90 * sec))
        XCTAssertEqual(intro.endSeconds, 90)
        XCTAssertFalse(intro.isHidden)
        XCTAssertTrue(intro.isEnabled, "FlagEnabled defaults to 1")
        let act = chapters[1]
        XCTAssertEqual(act.children.map { $0.displays.first?.title }, ["Scene A", "Scene B"])
        XCTAssertEqual(act.children[1].startSeconds, 300)
        XCTAssertNil(act.endNanos)
        XCTAssertTrue(chapters[2].isHidden)
        XCTAssertFalse(chapters[3].isEnabled)
    }

    func testChapterTitlesInSeveralLanguages() async throws {
        let m = try await readMKV(MKVBuilder.build(richFile()))
        let intro = m.editions[0].chapters[0]
        XCTAssertEqual(intro.displays.count, 2)
        XCTAssertEqual(intro.title(language: "eng"), "Intro")
        XCTAssertEqual(intro.title(language: "fre"), "Générique")
        XCTAssertEqual(intro.title(language: "ger"), "Intro", "Falls back to the first title")
        XCTAssertEqual(intro.title(), "Intro")
        let credits = m.editions[0].chapters[3]
        XCTAssertEqual(credits.displays.first?.languagesBCP47, ["en-US"])
        XCTAssertEqual(credits.displays.first?.countries, ["US"])
        XCTAssertEqual(credits.title(language: "en"), "Credits", "BCP 47 prefix match")
    }

    func testFlattenedChaptersAndPreferredEdition() async throws {
        let m = try await readMKV(MKVBuilder.build(richFile()))
        let flat = m.editions[0].flattenedChapters
        XCTAssertEqual(flat.compactMap { $0.displays.first?.title }, ["Intro", "Act 1", "Scene A", "Scene B", "Secret", "Credits"])
        XCTAssertEqual(m.preferredEdition?.uid, 100)
        var reversed = m
        reversed.editions = m.editions.reversed()
        XCTAssertEqual(reversed.preferredEdition?.uid, 100, "The default visible edition wins even when it is not first")
    }

    func testChapterWithoutDisplayHasNoTitle() async throws {
        var f = TFile()
        f.tracks = [TTrack(video: (640, 360, nil, nil))]
        f.editions = [TEdition(uid: 1, atoms: [TAtom(uid: 9, start: 5 * sec)])]
        let m = try await readMKV(MKVBuilder.build(f))
        XCTAssertNil(m.editions[0].chapters[0].title())
        XCTAssertEqual(m.editions[0].chapters[0].startSeconds, 5)
    }

    /// Feeds one hand-built top-level element straight to the parser.
    private func ingestTop(_ element: [UInt8]) throws -> EmbeddedMetadata {
        let id = try XCTUnwrap(EBMLView.readID(element, at: 0, limit: element.count))
        let size = try XCTUnwrap(EBMLView.readSize(element, at: id.length, limit: element.count))
        let parser = MatroskaParser()
        parser.ingest(id: id.id, view: EBMLView(bytes: element, base: 0), body: (id.length + size.length)..<element.count, fileOffset: 0, truncated: false)
        return parser.result()
    }

    func testStringUIDOfChapter() throws {
        let atom = W.master(MKV.chapterAtom, [W.uint(MKV.chapterUID, 3), W.string(MKV.chapterStringUID, "intro-1"), W.uint(MKV.chapterTimeStart, 0)])
        let chapters = W.master(MKV.chapters, [W.master(MKV.editionEntry, [W.uint(MKV.editionUID, 1), atom])])
        let m = try ingestTop(chapters)
        XCTAssertEqual(m.editions.first?.chapters.first?.stringUID, "intro-1")
        XCTAssertEqual(m.editions.first?.chapters.first?.uid, 3)
    }

    func testChapterWithoutStartTimeIsKeptAtZeroWithWarning() throws {
        let atom = W.master(MKV.chapterAtom, [W.uint(MKV.chapterUID, 3)])
        let m = try ingestTop(W.master(MKV.chapters, [W.master(MKV.editionEntry, [atom])]))
        XCTAssertEqual(m.editions.first?.chapters.first?.startNanos, 0)
        XCTAssertTrue(m.warnings.contains { $0.contains("without a start time") })
    }

    func testDeeplyNestedChaptersAreCutOffNotCrashed() async throws {
        var f = TFile()
        f.tracks = [TTrack(video: (640, 360, nil, nil))]
        var atom = TAtom(uid: 1, start: 0, displays: [TDisplay(title: "leaf")])
        for i in 0..<300 { atom = TAtom(uid: UInt64(i + 2), start: 0, displays: [TDisplay(title: "n\(i)")], children: [atom]) }
        f.editions = [TEdition(uid: 1, atoms: [atom])]
        let m = try await readMKV(MKVBuilder.build(f))
        XCTAssertTrue(m.warnings.contains { $0.contains("nested deeper") })
        var depth = 0
        var cursor = m.editions[0].chapters.first
        while let c = cursor { depth += 1; cursor = c.children.first }
        XCTAssertLessThanOrEqual(depth, 12)
        XCTAssertGreaterThan(depth, 1)
    }

    // MARK: Tags

    func testGlobalAndTrackTags() async throws {
        let m = try await readMKV(MKVBuilder.build(richFile()))
        XCTAssertEqual(m.tags.count, 2)
        let global = m.tags[0]
        XCTAssertTrue(global.isGlobal)
        XCTAssertEqual(global.targetTypeValue, 50)
        XCTAssertEqual(global.targetType, "MOVIE")
        XCTAssertEqual(global.simpleTags.map(\.name), ["TITLE", "ACTOR"])
        XCTAssertEqual(global.simpleTags[1].children.first?.name, "CHARACTER")
        XCTAssertEqual(global.simpleTags[1].children.first?.string, "Lead")
        let perTrack = m.tags[1]
        XCTAssertFalse(perTrack.isGlobal)
        XCTAssertEqual(perTrack.trackUIDs, [1001])
        XCTAssertEqual(perTrack.targetTypeValue, 30)
        XCTAssertEqual(perTrack.simpleTags.first?.string, "12345678")
        XCTAssertEqual(m.globalTagValues["TITLE"], "Test Movie")
        XCTAssertEqual(m.globalTagValues["CHARACTER"], "Lead")
        XCTAssertNil(m.globalTagValues["BPS"], "Per-track tags are not global")
    }

    // MARK: Attachments

    func testAttachmentsNamesOnly() async throws {
        let m = try await readMKV(MKVBuilder.build(richFile()))
        XCTAssertEqual(m.attachments.map(\.fileName), ["font.ttf", "cover.jpg"])
        XCTAssertEqual(m.attachments[0].mediaType, "application/x-truetype-font")
        XCTAssertEqual(m.attachments[0].dataSize, 300)
        XCTAssertEqual(m.attachments[1].dataSize, 100)
    }

    // MARK: Layout of the file

    func testChaptersAndTagsAfterClustersAreFoundThroughSeekHeadWithoutReadingClusters() async throws {
        var f = richFile()
        f.chaptersAtEnd = true
        f.tagsAtEnd = true
        f.headPadding = 6000
        f.clusterCount = 3
        f.clusterBytes = 50_000
        let built = MKVBuilder.build(f)
        XCTAssertGreaterThan(built.firstClusterOffset, 4096, "The test needs the clusters outside the head window")
        let log = ReadLog()
        let m = try await readMKV(built, reader: MatroskaReader(headBytes: 4096), log: log)
        XCTAssertEqual(m.editions.count, 2)
        XCTAssertEqual(m.tags.count, 2)
        XCTAssertEqual(m.warnings, [])
        XCTAssertEqual(m.layout.chaptersOffset, Int64(try XCTUnwrap(built.chaptersOffset)))
        XCTAssertEqual(m.layout.tagsOffset, Int64(try XCTUnwrap(built.tagsOffset)))
        XCTAssertEqual(m.layout.firstClusterOffset, Int64(built.firstClusterOffset))
        XCTAssertGreaterThan(try XCTUnwrap(m.layout.cuesOffset), m.layout.tagsOffset ?? 0)
        // One read for the head, one each for Chapters and Tags; nothing else.
        XCTAssertEqual(log.ranges.count, 3, "reads: \(log.ranges)")
        for r in log.ranges {
            for cluster in built.clusterRanges {
                let readEnd = Int(r.offset + r.length)
                let overlaps = Int(r.offset) < cluster.upperBound && readEnd > cluster.lowerBound
                XCTAssertFalse(overlaps, "A read of \(r) touched a cluster at \(cluster)")
            }
        }
        XCTAssertLessThan(log.totalBytes, Int64(built.bytes.count / 10))
        // Same content as when everything fits in the head window.
        let all = try await readMKV(built, reader: MatroskaReader(headBytes: built.bytes.count + 10))
        assertSameContent(m, all)
    }

    func testResultDoesNotDependOnHeadWindowSize() async throws {
        var f = richFile()
        f.chaptersAtEnd = true
        f.tagsAtEnd = true
        f.voidBetweenElements = true
        f.crc = true
        let built = MKVBuilder.build(f)
        let baseline = try await readMKV(built)
        for window in [64, 80, 100, 150, 300, 700, 1500, 3000] {
            let m = try await readMKV(built, reader: MatroskaReader(headBytes: window))
            assertSameContent(m, baseline)
        }
    }

    func testUnknownSizeSegmentAndClusters() async throws {
        var f = richFile()
        f.unknownSizeSegment = true
        f.unknownSizeClusters = true
        f.chaptersAtEnd = true
        f.tagsAtEnd = true
        let built = MKVBuilder.build(f)
        let m = try await readMKV(built)
        let baseline = try await readMKV(MKVBuilder.build(richFile()))
        assertSameContent(m, baseline)
        XCTAssertEqual(m.editions.count, 2)
        XCTAssertEqual(m.tags.count, 2)
    }

    func testVoidAndCRC32ElementsAreSkipped() async throws {
        var f = richFile()
        f.voidBetweenElements = true
        f.crc = true
        f.headPadding = 500
        let m = try await readMKV(MKVBuilder.build(f))
        let baseline = try await readMKV(MKVBuilder.build(richFile()))
        assertSameContent(m, baseline)
        XCTAssertEqual(m.warnings, [])
    }

    func testGarbageBetweenElementsIsSkipped() async throws {
        var f = richFile()
        f.garbageAfterInfo = 23
        let m = try await readMKV(MKVBuilder.build(f))
        XCTAssertEqual(m.tracks.count, 7, "Tracks come after the garbage and are found again")
        XCTAssertEqual(m.editions.count, 2)
        XCTAssertTrue(m.warnings.contains { $0.contains("damaged data") })
    }

    func testNoSeekHeadMeansTailElementsAreNotFoundAndSaysSo() async throws {
        var f = richFile()
        f.seekHead = false
        f.chaptersAtEnd = true
        f.tagsAtEnd = true
        let m = try await readMKV(MKVBuilder.build(f))
        XCTAssertEqual(m.tracks.count, 7)
        XCTAssertTrue(m.editions.isEmpty)
        XCTAssertTrue(m.tags.isEmpty)
        XCTAssertTrue(m.warnings.contains { $0.contains("no SeekHead") })
    }

    func testFileWithoutSeekHeadStillReadsEverythingBeforeTheFirstCluster() async throws {
        var f = richFile()
        f.seekHead = false
        let m = try await readMKV(MKVBuilder.build(f))
        XCTAssertEqual(m.editions.count, 2)
        XCTAssertEqual(m.tags.count, 2)
        XCTAssertEqual(m.attachments.count, 2)
    }

    func testReadsBeyondTheEndOfAFileThatLostItsTail() async throws {
        var f = richFile()
        f.chaptersAtEnd = true
        f.tagsAtEnd = true
        f.headPadding = 3000
        let built = MKVBuilder.build(f)
        let cut = BuiltMKV(bytes: Array(built.bytes[0..<built.firstClusterOffset]), clusterRanges: [], segmentDataStart: built.segmentDataStart,
                           chaptersOffset: nil, tagsOffset: nil, firstClusterOffset: built.firstClusterOffset)
        for mode in [BeyondEnd.throwError, BeyondEnd.empty] {
            let m = try await readMKV(cut, reader: MatroskaReader(headBytes: 4096), beyondEnd: mode)
            XCTAssertEqual(m.tracks.count, 7)
            XCTAssertTrue(m.editions.isEmpty)
            XCTAssertTrue(m.warnings.contains { $0.contains("could not be read") }, "\(m.warnings)")
        }
    }

    func testOversizedElementIsSkippedWithWarningAndLimitsReadSize() async throws {
        var f = richFile()
        f.attachments = [TAttachment(name: "big.bin", mime: "application/octet-stream", data: [UInt8](repeating: 1, count: 300_000))]
        f.headPadding = 0
        let built = MKVBuilder.build(f)
        let log = ReadLog()
        let m = try await readMKV(built, reader: MatroskaReader(headBytes: 8192, maxElementBytes: 100_000), log: log)
        XCTAssertEqual(m.tracks.count, 7, "Elements before the big one are unaffected")
        XCTAssertEqual(m.attachments.map(\.fileName), ["big.bin"], "The part inside the head window is still used")
        XCTAssertNil(m.attachments.first?.dataSize, "A cut-off data element has no trustworthy size")
        XCTAssertTrue(m.warnings.contains { $0.contains("byte limit") }, "\(m.warnings)")
        XCTAssertLessThanOrEqual(log.ranges.map(\.length).max() ?? 0, 100_000)
    }

    func testAttachmentCutByTheHeadWindowKeepsWhatWasRead() async throws {
        var f = richFile()
        f.attachments = [TAttachment(name: "small.txt", mime: "text/plain", data: [UInt8](repeating: 1, count: 9000))]
        let built = MKVBuilder.build(f)
        // The attachment starts in the window but its data runs past it, and fetching is not allowed (maxFetches 0).
        let m = try await readMKV(built, reader: MatroskaReader(headBytes: 4096, maxFetches: 0))
        XCTAssertEqual(m.tracks.count, 7)
        XCTAssertTrue(m.warnings.contains { $0.contains("cut off") || $0.contains("Stopped after") }, "\(m.warnings)")
    }

    func testMaxFetchesBoundsTheNumberOfExtraReads() async throws {
        var f = richFile()
        f.chaptersAtEnd = true
        f.tagsAtEnd = true
        f.headPadding = 6000
        let built = MKVBuilder.build(f)
        let log = ReadLog()
        let m = try await readMKV(built, reader: MatroskaReader(headBytes: 4096, maxFetches: 1), log: log)
        XCTAssertLessThanOrEqual(log.ranges.count, 2)
        XCTAssertTrue(m.warnings.contains { $0.contains("Stopped after 1 extra reads") }, "\(m.warnings)")
    }

    func testSeekHeadPointingAtTheWrongElementIsRejected() async throws {
        var f = richFile()
        f.chaptersAtEnd = true
        f.headPadding = 6000
        var built = MKVBuilder.build(f)
        // Corrupt the first byte of the Chapters element so the SeekHead target is a different thing.
        let at = try XCTUnwrap(built.chaptersOffset)
        built.bytes[at] = 0x1F
        let m = try await readMKV(built, reader: MatroskaReader(headBytes: 4096))
        XCTAssertTrue(m.editions.isEmpty)
        XCTAssertFalse(m.warnings.isEmpty)
    }

    // MARK: Errors

    private func expect(_ matches: (MatroskaError) -> Bool, _ bytes: [UInt8], file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await MatroskaReader().read(using: memoryReader(bytes))
            XCTFail("Expected an error", file: file, line: line)
        } catch let e as MatroskaError {
            XCTAssertTrue(matches(e), "Unexpected error: \(e)", file: file, line: line)
        } catch {
            XCTFail("Expected a MatroskaError, got \(error)", file: file, line: line)
        }
    }

    func testEmptyFile() async throws {
        await expect({ $0 == .emptyFile }, [])
        // A source that answers with zero bytes instead of an error behaves the same.
        do {
            _ = try await MatroskaReader().read(using: memoryReader([], beyondEnd: .empty))
            XCTFail("Expected an error")
        } catch let e as MatroskaError {
            XCTAssertEqual(e, .emptyFile)
        }
    }

    func testNotMatroska() async {
        await expect({ if case .notMatroska = $0 { return true } else { return false } }, [0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46])
        await expect({ if case .notMatroska = $0 { return true } else { return false } }, Array("hello world".utf8))
    }

    func testOtherEBMLDocType() async {
        var f = TFile()
        f.docType = "ogg"
        f.tracks = [TTrack()]
        await expect({ $0 == .unsupportedDocType("ogg") }, MKVBuilder.build(f).bytes)
    }

    func testCutOffInTheHeader() async {
        let bytes = MKVBuilder.build(richFile()).bytes
        await expect({ if case .truncated = $0 { return true } else { return false } }, Array(bytes[0..<10]))
        await expect({ if case .truncated = $0 { return true } else { return false } }, Array(bytes[0..<45]))
    }

    func testNoSegmentAfterHeader() async {
        let header = W.master(MKV.ebmlHeader, [W.string(MKV.docType, "matroska")])
        await expect({ if case .notMatroska = $0 { return true } else { return false } }, header + W.master(MKV.cues, []))
    }

    func testVoidBeforeSegmentIsAllowed() async throws {
        let built = MKVBuilder.build(richFile())
        let headerEnd = try XCTUnwrap(built.bytes.firstIndex(of: 0x18)) // start of the Segment ID 18 53 80 67
        var bytes = Array(built.bytes[0..<headerEnd]) + W.void(total: 20)
        bytes += built.bytes[headerEnd...]
        let m = try await MatroskaReader().read(using: memoryReader(bytes))
        XCTAssertEqual(m.tracks.count, 7)
    }

    struct Boom: Error {}

    func testFirstReadFailureBecomesReadFailed() async {
        do {
            _ = try await MatroskaReader().read { _ in throw Boom() }
            XCTFail("Expected an error")
        } catch let e as MatroskaError {
            if case .readFailed = e {} else { XCTFail("Unexpected \(e)") }
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testCancellationIsPropagated() async {
        do {
            _ = try await MatroskaReader().read { _ in throw CancellationError() }
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testReaderReturningMoreThanAskedIsClamped() async throws {
        let bytes = MKVBuilder.build(richFile()).bytes
        let m = try await MatroskaReader(headBytes: 4096).read { _ in Data(bytes) }
        XCTAssertEqual(m.tracks.count, 7)
    }

    func testMissingInfoAndTracksAreWarnings() async throws {
        let header = W.master(MKV.ebmlHeader, [W.string(MKV.docType, "matroska")])
        let body = W.master(MKV.cues, [])
        let bytes = header + W.id(MKV.segment) + W.size(body.count, minLength: 8) + body
        let m = try await MatroskaReader().read(using: memoryReader(bytes))
        XCTAssertNil(m.info)
        XCTAssertTrue(m.warnings.contains { $0.contains("No Info") })
        XCTAssertTrue(m.warnings.contains { $0.contains("No Tracks") })
    }

    // MARK: ReadingFromAMediaSource-shaped closure

    func testReaderRequestsStartAtZeroAndAskForTheConfiguredHead() async throws {
        let log = ReadLog()
        _ = try await readMKV(MKVBuilder.build(richFile()), reader: MatroskaReader(headBytes: 100_000), log: log)
        XCTAssertEqual(log.ranges.first?.offset, 0)
        XCTAssertEqual(log.ranges.first?.length, 100_000)
        XCTAssertEqual(log.ranges.count, 1, "A small file needs exactly one read")
    }

    // MARK: Summary

    func testDetailRows() async throws {
        let m = try await readMKV(MKVBuilder.build(richFile()))
        let rows = m.detailRows
        func value(_ label: String) -> String? { rows.first { $0.label == label }?.value }
        XCTAssertEqual(value("Container"), "Matroska")
        XCTAssertEqual(value("Title"), "Test Movie")
        XCTAssertEqual(value("Duration"), "1:30:00")
        let video = try XCTUnwrap(value("Video"))
        XCTAssertTrue(video.hasPrefix("HEVC 3840×2160 · 23.976 fps · HDR (PQ) · 10-bit · Dolby Vision 8.1"), video)
        XCTAssertEqual(value("Audio 1"), "English · E-AC-3 · 7.1 · 48 kHz · Atmos (from the track name) · “English Dolby Atmos 7.1” · default")
        XCTAssertEqual(value("Audio 2"), "Japanese · TrueHD · 7.1 · 48 kHz · 24-bit")
        XCTAssertEqual(value("Subtitle 1"), "English · PGS (image) · forced")
        XCTAssertEqual(value("Subtitle 2"), "Spanish · SubRip · “Español (Latinoamérica)”")
        XCTAssertEqual(value("Chapters"), "6 chapters (2 editions)")
        XCTAssertEqual(value("Muxed with"), "test-writer 1.0")
        XCTAssertEqual(value("Written by"), "test-writer app")
        XCTAssertEqual(value("Attachments"), "font.ttf, cover.jpg")
        XCTAssertNil(value("Notes"))
    }

    func testClockFormatting() {
        XCTAssertEqual(EmbeddedMetadata.clock(0), "0:00")
        XCTAssertEqual(EmbeddedMetadata.clock(59.4), "0:59")
        XCTAssertEqual(EmbeddedMetadata.clock(61), "1:01")
        XCTAssertEqual(EmbeddedMetadata.clock(3600), "1:00:00")
        XCTAssertEqual(EmbeddedMetadata.clock(-5), "0:00")
        XCTAssertEqual(EmbeddedMetadata.clock(.nan), "0:00")
    }

    func testLanguageNames() {
        XCTAssertEqual(MatroskaTrack.languageName(for: "eng"), "English")
        XCTAssertEqual(MatroskaTrack.languageName(for: "fra"), "French")
        XCTAssertEqual(MatroskaTrack.languageName(for: "fre"), "French")
        XCTAssertEqual(MatroskaTrack.languageName(for: "pt-BR"), "Portuguese")
        XCTAssertEqual(MatroskaTrack.languageName(for: "xyz"), "xyz")
    }

    func testFrameRateEdgeCases() {
        var t = MatroskaTrack(number: 1, type: .video, codecID: "V_AV1")
        XCTAssertNil(t.frameRate)
        t.defaultDurationNanos = 0
        XCTAssertNil(t.frameRate)
        t.defaultDurationNanos = 40_000_000
        XCTAssertEqual(t.frameRate, 25)
        t.defaultDurationNanos = 33_366_667
        XCTAssertEqual(try XCTUnwrap(t.frameRate), 29.97, accuracy: 0.0005)
    }

    func testEmbeddedMetadataIsCodable() async throws {
        let m = try await readMKV(MKVBuilder.build(richFile()))
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(EmbeddedMetadata.self, from: data)
        XCTAssertEqual(back, m)
    }

    // MARK: EBML primitives

    func testVariableLengthSizes() {
        func size(_ bytes: [UInt8]) -> (UInt64?, Int)? {
            EBMLView.readSize(bytes, at: 0, limit: bytes.count).map { ($0.value, $0.length) }
        }
        XCTAssertEqual(size([0x80])?.0, 0)
        XCTAssertEqual(size([0xFE])?.0, 126)
        XCTAssertNil(size([0xFF])?.0, "0xFF is the reserved unknown size")
        XCTAssertEqual(size([0xFF])?.1, 1)
        XCTAssertEqual(size([0x40, 0x7F])?.0, 127)
        XCTAssertEqual(size([0x40, 0x00])?.0, 0)
        XCTAssertNil(size([0x7F, 0xFF])?.0)
        XCTAssertEqual(size([0x7F, 0xFF])?.1, 2)
        XCTAssertEqual(size([0x01, 0, 0, 0, 0, 0, 0, 0x2A])?.0, 42)
        XCTAssertNil(size([0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])?.0)
        XCTAssertEqual(size([0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])?.1, 8)
        XCTAssertEqual(size([0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE])?.0, (1 << 56) - 2)
        XCTAssertNil(size([0x00]), "A zero first byte is not a valid length marker")
        XCTAssertNil(size([0x40]), "Truncated multi-byte size")
        XCTAssertNil(size([]))
    }

    func testElementIDs() {
        func id(_ bytes: [UInt8]) -> UInt32? { EBMLView.readID(bytes, at: 0, limit: bytes.count)?.id }
        XCTAssertEqual(id([0xEC]), 0xEC)
        XCTAssertEqual(id([0x42, 0x82]), 0x4282)
        XCTAssertEqual(id([0x2A, 0xD7, 0xB1]), 0x2AD7B1)
        XCTAssertEqual(id([0x1A, 0x45, 0xDF, 0xA3]), MKV.ebmlHeader)
        XCTAssertNil(id([0x0F, 0, 0, 0, 0]), "IDs longer than 4 bytes are invalid")
        XCTAssertNil(id([0x1A, 0x45]), "Truncated ID")
        XCTAssertNil(id([]))
    }

    func testWriterSizeEncodingRoundTrips() {
        for n in [0, 1, 126, 127, 128, 16382, 16383, 16384, 2_000_000, 300_000_000] {
            let bytes = W.size(n)
            let parsed = EBMLView.readSize(bytes, at: 0, limit: bytes.count)
            XCTAssertEqual(parsed?.value, UInt64(n), "size \(n)")
            XCTAssertEqual(parsed?.length, bytes.count)
        }
    }

    func testNumberDecoding() {
        let v = EBMLView(bytes: [0xFF, 0xFE, 0x3F, 0x80, 0x00, 0x00], base: 0)
        XCTAssertEqual(v.int(EBMLChild(id: 0, start: 0, end: 1, truncated: false)), -1)
        XCTAssertEqual(v.int(EBMLChild(id: 0, start: 0, end: 2, truncated: false)), -2)
        XCTAssertEqual(v.uint(EBMLChild(id: 0, start: 0, end: 2, truncated: false)), 0xFFFE)
        XCTAssertEqual(v.float(EBMLChild(id: 0, start: 2, end: 6, truncated: false)), 1.0)
        XCTAssertNil(v.float(EBMLChild(id: 0, start: 2, end: 5, truncated: false)))
        XCTAssertNil(v.uint(EBMLChild(id: 0, start: 0, end: 2, truncated: true)))
        XCTAssertEqual(v.uint(EBMLChild(id: 0, start: 0, end: 0, truncated: false)), 0)
    }

    func testStringsStopAtNulPadding() {
        let v = EBMLView(bytes: Array("eng".utf8) + [0, 0, 0], base: 0)
        XCTAssertEqual(v.string(EBMLChild(id: 0, start: 0, end: 6, truncated: false)), "eng")
    }
}
