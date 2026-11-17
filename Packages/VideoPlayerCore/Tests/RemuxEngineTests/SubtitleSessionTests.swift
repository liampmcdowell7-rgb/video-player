import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore

// The subtitle half of the session: master playlist content (group, default/forced flags, language, name, characteristics),
// WebVTT rendition playlists and segments (cue placement, time base), PGS kept out of the playlists, the seek map unchanged.
// Files are FIXTURES built by SynthMKV (24 fps, 6 s, a keyframe every second, segments of 2 s, decode delay 2 frames = 0.08333 s).

final class SubtitleSessionTests: XCTestCase {
    func cue(_ ms: Int, _ dur: Int, _ text: String) -> (ms: Int, durMs: Int, payload: [UInt8]) { (ms, dur, Array(text.utf8)) }

    func srtTrack(_ n: Int = 5, zlib: Bool = false) -> SynthSubtitle {
        SynthSubtitle(number: n, language: "eng", name: "English", isDefault: true, zlib: zlib, cues: [
            cue(500, 1000, "Hello <i>world</i>"),
            cue(1500, 2000, "Spans the boundary"),
            cue(2500, 1000, "Second segment"),
            cue(3000, 500, "A"), cue(3000, 500, "B"),
            cue(4200, 800, "Third & last"),
        ])
    }

    func make(_ s: SynthMKV) -> (MatroskaRemuxSession, CountingReader) {
        var o = RemuxOptions(); o.targetSegmentSeconds = 2
        let reader = CountingReader(s.build().data)
        return (MatroskaRemuxSession(reader: reader, options: o), reader)
    }

    func text(_ s: MatroskaRemuxSession, _ path: String) async throws -> String {
        String(decoding: flatten(try await s.resource(path: path)), as: UTF8.self)
    }

    func testTextTracksBecomeRenditionsAndPictureTracksDoNot() async throws {
        var synth = SynthMKV()
        synth.subtitles = [
            srtTrack(5),
            SynthSubtitle(number: 6, codecID: "S_TEXT/ASS", language: "fre", name: "Forced", isForced: true, cues: [cue(1000, 500, "1,0,Default,,0,0,0,,Oui")]),
            SynthSubtitle(number: 7, codecID: "S_TEXT/WEBVTT", language: "eng", name: "English SDH", isHearingImpaired: true, cues: [cue(1000, 500, "[door slams]")]),
            SynthSubtitle(number: 8, codecID: "S_HDMV/PGS", language: "jpn", name: "Japanese", cues: [cue(1000, 500, "x")]),
            SynthSubtitle(number: 9, codecID: "S_VOBSUB", language: "spa", cues: []),
        ]
        let (s, _) = make(synth)
        let info = try await s.prepare()
        XCTAssertEqual(info.subtitles.map { $0.trackNumber }, [5, 6, 7])
        XCTAssertEqual(info.pictureSubtitles.map { $0.trackNumber }, [8], "PGS is for the app's own menu")
        XCTAssertEqual(info.pictureSubtitles.first?.language, "jpn")
        XCTAssertEqual(info.skippedSubtitles.map { $0.trackNumber }, [9])
        XCTAssertTrue(info.skippedSubtitles.first?.reason.contains("VobSub") ?? false)

        let master = try await text(s, "master.m3u8")
        let lines = master.components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"English\",LANGUAGE=\"en\",DEFAULT=NO,AUTOSELECT=YES,URI=\"subs_5.m3u8\""), master)
        XCTAssertTrue(lines.contains("#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"Forced\",LANGUAGE=\"fr\",DEFAULT=YES,AUTOSELECT=YES,FORCED=YES,URI=\"subs_6.m3u8\""), master)
        XCTAssertTrue(lines.contains("#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"English SDH\",LANGUAGE=\"en\",DEFAULT=NO,AUTOSELECT=YES,CHARACTERISTICS=\"public.accessibility.transcribes-spoken-dialog,public.accessibility.describes-music-and-sound\",URI=\"subs_7.m3u8\""), master)
        XCTAssertFalse(master.contains("subs_8"), "a PGS track must not be listed as a rendition")
        XCTAssertFalse(master.contains("subs_9"))
        XCTAssertFalse(master.contains("TYPE=CLOSED-CAPTIONS"))
        let inf = try XCTUnwrap(lines.first { $0.hasPrefix("#EXT-X-STREAM-INF") })
        XCTAssertTrue(inf.contains(",SUBTITLES=\"subs\""), inf)
        XCTAssertTrue(inf.contains(",wvtt"), "the variant names the WebVTT codec: \(inf)")
        XCTAssertTrue(inf.contains("AUDIO=\"audio\""))
    }

    func testNoSubtitlesMeansNoSubtitleAttributes() async throws {
        let (s, _) = make(SynthMKV())
        let info = try await s.prepare()
        XCTAssertTrue(info.subtitles.isEmpty); XCTAssertTrue(info.pictureSubtitles.isEmpty)
        let master = try await text(s, "master.m3u8")
        XCTAssertFalse(master.contains("SUBTITLES")); XCTAssertFalse(master.contains("wvtt"))
    }

    func testOnlyPictureSubtitlesLeaveTheMasterWithoutSubtitleGroup() async throws {
        var synth = SynthMKV()
        synth.subtitles = [SynthSubtitle(number: 8, codecID: "S_HDMV/PGS", cues: [])]
        let (s, _) = make(synth)
        _ = try await s.prepare()
        let master = try await text(s, "master.m3u8")
        XCTAssertFalse(master.contains("SUBTITLES"), master)
    }

    func testRenditionPlaylistUsesTheVideoSegmentTimes() async throws {
        var synth = SynthMKV(); synth.subtitles = [srtTrack()]
        let (s, _) = make(synth)
        _ = try await s.prepare()
        let subs = try await text(s, "subs_5.m3u8")
        XCTAssertEqual(subs, """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:2
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXTINF:2.00000,
        seg_subs_5_0.vtt
        #EXTINF:2.00000,
        seg_subs_5_1.vtt
        #EXTINF:2.00000,
        seg_subs_5_2.vtt
        #EXT-X-ENDLIST

        """)
        let video = try await text(s, "video.m3u8")
        XCTAssertEqual(video.components(separatedBy: "#EXTINF").count, subs.components(separatedBy: "#EXTINF").count, "same number of segments")
        let missing = try await s.resource(path: "subs_99.m3u8")
        XCTAssertEqual(missing.status, 404)
        let missingSegment = try await s.resource(path: "seg_subs_5_77.vtt")
        XCTAssertEqual(missingSegment.status, 404)
    }

    func testCuesLandInTheSegmentOfTheirStartOnTheMediaTimeline() async throws {
        var synth = SynthMKV(); synth.subtitles = [srtTrack()]
        let (s, _) = make(synth)
        let info = try await s.prepare()
        XCTAssertEqual(info.timelineOffsetSeconds, 0.08333, accuracy: 0.0001, "the fixture's decode delay (2 frames at 24 fps)")
        let header = "WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:0,LOCAL:00:00:00.000\n"
        let r = try await s.resource(path: "seg_subs_5_0.vtt")
        XCTAssertEqual(r.contentType, "text/vtt")
        XCTAssertEqual(String(decoding: flatten(r), as: UTF8.self), header
            + "\n00:00:00.583 --> 00:00:01.583\nHello <i>world</i>\n"
            + "\n00:00:01.583 --> 00:00:03.583\nSpans the boundary\n")
        let seg1 = try await text(s, "seg_subs_5_1.vtt")
        XCTAssertEqual(seg1, header
            + "\n00:00:02.583 --> 00:00:03.583\nSecond segment\n"
            + "\n00:00:03.083 --> 00:00:03.583\nA\n"
            + "\n00:00:03.083 --> 00:00:03.583\nB\n")
        let seg2 = try await text(s, "seg_subs_5_2.vtt")
        XCTAssertEqual(seg2, header + "\n00:00:04.283 --> 00:00:05.083\nThird &amp; last\n")
    }

    func testEveryCueAppearsExactlyOnceAcrossTheSegments() async throws {
        var synth = SynthMKV()
        var cues: [(ms: Int, durMs: Int, payload: [UInt8])] = []
        for n in 0..<3000 { cues.append(cue(n * 2, 60, "Cue \(n)")) }       // 3000 cues in 6 s, one every 2 ms
        synth.subtitles = [SynthSubtitle(number: 5, cues: cues)]
        let (s, _) = make(synth)
        _ = try await s.prepare()
        var seen: [Int] = []
        for k in 0..<3 {
            let body = try await text(s, "seg_subs_5_\(k).vtt")
            for line in body.components(separatedBy: "\n") where line.hasPrefix("Cue ") { seen.append(Int(line.dropFirst(4))!) }
        }
        XCTAssertEqual(seen.count, 3000)
        XCTAssertEqual(seen, Array(0..<3000), "no cue lost, none twice, in order")
    }

    func testEmptyTrackGivesValidEmptySegments() async throws {
        var synth = SynthMKV(); synth.subtitles = [SynthSubtitle(number: 5, cues: [])]
        let (s, _) = make(synth)
        let info = try await s.prepare()
        XCTAssertEqual(info.subtitles.map { $0.trackNumber }, [5], "an empty track is still offered")
        for k in 0..<3 {
            let body = try await text(s, "seg_subs_5_\(k).vtt")
            XCTAssertEqual(body, "WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:0,LOCAL:00:00:00.000\n")
        }
    }

    func testZlibCompressedTrackGivesTheSameCues() async throws {
        var plain = SynthMKV(); plain.subtitles = [srtTrack(5, zlib: false)]
        var packed = SynthMKV(); packed.subtitles = [srtTrack(5, zlib: true)]
        let (a, _) = make(plain), (b, _) = make(packed)
        _ = try await a.prepare(); _ = try await b.prepare()
        for k in 0..<3 {
            let x = try await text(a, "seg_subs_5_\(k).vtt"), y = try await text(b, "seg_subs_5_\(k).vtt")
            XCTAssertEqual(x, y, "segment \(k)")
        }
        let y1 = try await text(b, "seg_subs_5_1.vtt")
        XCTAssertTrue(y1.contains("Second segment"))
    }

    func testASSAndWebVTTTracksAreConvertedToo() async throws {
        var synth = SynthMKV()
        synth.subtitles = [
            SynthSubtitle(number: 6, codecID: "S_TEXT/ASS", cues: [cue(1000, 500, "7,0,Default,,0,0,0,,{\\i1}Oui{\\i0}\\Nnon")]),
            SynthSubtitle(number: 7, codecID: "S_TEXT/WEBVTT", cues: [cue(1000, 500, "<v Bob>Hi</v>")]),
        ]
        let (s, _) = make(synth)
        _ = try await s.prepare()
        let a = try await text(s, "seg_subs_6_0.vtt"), b = try await text(s, "seg_subs_7_0.vtt")
        XCTAssertTrue(a.contains("00:00:01.083 --> 00:00:01.583\n<i>Oui</i>\nnon\n"), a)
        XCTAssertTrue(b.contains("00:00:01.083 --> 00:00:01.583\nHi\n"), b)
    }

    func testSeekMapAndVideoSegmentsAreUnchangedBySubtitles() async throws {
        var withSubs = SynthMKV(); withSubs.subtitles = [srtTrack(), SynthSubtitle(number: 8, codecID: "S_HDMV/PGS", cues: [cue(1000, 500, "x")])]
        let (a, _) = make(SynthMKV()), (b, _) = make(withSubs)
        let ia = try await a.prepare(), ib = try await b.prepare()
        XCTAssertEqual(ia.segmentCount, ib.segmentCount)
        XCTAssertEqual(ia.durationSeconds, ib.durationSeconds)
        XCTAssertEqual(ia.timelineOffsetSeconds, ib.timelineOffsetSeconds)
        let va = try await text(a, "video.m3u8"), vb = try await text(b, "video.m3u8")
        XCTAssertEqual(va, vb)
        for k in 0..<3 {
            let x = flatten(try await a.resource(path: "seg_video_\(k).m4s")), y = flatten(try await b.resource(path: "seg_video_\(k).m4s"))
            XCTAssertEqual(x, y, "video segment \(k) is byte for byte the same")
            let xa = flatten(try await a.resource(path: "seg_audio_2_\(k).m4s")), ya = flatten(try await b.resource(path: "seg_audio_2_\(k).m4s"))
            XCTAssertEqual(xa, ya, "audio segment \(k)")
        }
        for seconds in [0.0, 0.9, 2.0, 2.1, 5.9, 100] {
            let x = await a.segmentIndex(forSeconds: seconds), y = await b.segmentIndex(forSeconds: seconds)
            XCTAssertEqual(x, y)
        }
    }

    func testPlayerPositionMapsToTheSegmentThroughTheDecodeDelay() async throws {
        let (s, _) = make(SynthMKV())
        let info = try await s.prepare()
        XCTAssertGreaterThan(info.timelineOffsetSeconds, 0)
        // Player time 2.0 s is file time 2.0 - 0.0833 = 1.9167 s: still the first segment. 2.0833 s is the start of the second.
        let a = await s.segmentIndex(forPlayerSeconds: 2.0)
        let b = await s.segmentIndex(forPlayerSeconds: 2.0 + info.timelineOffsetSeconds)
        XCTAssertEqual(a, 0); XCTAssertEqual(b, 1)
        let c = await s.segmentIndex(forPlayerSeconds: -3)
        XCTAssertEqual(c, 0)
    }

    func testSubtitleRequestsDoNotMoveTheReadAheadPlanner() async throws {
        var synth = SynthMKV(); synth.subtitles = [srtTrack()]
        let (s, _) = make(synth)
        _ = try await s.prepare()
        let before = await s.subtitleWindowLoads
        _ = try await text(s, "seg_subs_5_0.vtt")                 // window 0 was read by prepare(): nothing new to load
        let afterFirst = await s.subtitleWindowLoads
        XCTAssertEqual(before, afterFirst)
        _ = try await text(s, "seg_subs_5_2.vtt")                 // a window nobody else asked for
        let afterFar = await s.subtitleWindowLoads
        XCTAssertEqual(afterFar, before + 1)
        // The video of that segment still plays and is the same bytes as in a session that never saw the subtitle request.
        let (clean, _) = make(synth)
        _ = try await clean.prepare()
        let x = flatten(try await s.resource(path: "seg_video_2.m4s")), y = flatten(try await clean.resource(path: "seg_video_2.m4s"))
        XCTAssertEqual(x, y)
    }

    // MARK: Picture subtitles (.sup)

    func testPGSBlocksAreServedAsSupWithMediaTimelineTimestamps() async throws {
        // One block at 1.0 s with two segments: a composition (type 0x16, 3 bytes) and the end marker (0x80, 0 bytes).
        let block: [UInt8] = [0x16, 0, 3, 1, 2, 3, 0x80, 0, 0]
        var synth = SynthMKV()
        synth.subtitles = [SynthSubtitle(number: 8, codecID: "S_HDMV/PGS", language: "jpn", cues: [(1000, 500, block), (2500, 500, block)])]
        let (s, _) = make(synth)
        _ = try await s.prepare()
        let r = try await s.resource(path: "seg_pgs_8_0.sup")
        XCTAssertEqual(r.status, 200)
        // 1.0 s + 0.08333 s = 97500 ticks of 90 kHz = 0x00017CDC.
        let expected: [UInt8] = [0x50, 0x47, 0, 1, 0x7C, 0xDC, 0, 0, 0, 0, 0x16, 0, 3, 1, 2, 3,
                                 0x50, 0x47, 0, 1, 0x7C, 0xDC, 0, 0, 0, 0, 0x80, 0, 0]
        XCTAssertEqual(flatten(r), expected)
        let second = flatten(try await s.resource(path: "seg_pgs_8_1.sup"))
        XCTAssertEqual(Array(second.prefix(6)), [0x50, 0x47, 0, 3, 0x8C, 0x34], "2.5 s + 0.08333 s = 232500 ticks of 90 kHz = 0x00038C34")
        let none = flatten(try await s.resource(path: "seg_pgs_8_2.sup"))
        XCTAssertTrue(none.isEmpty, "a window without PGS blocks is an empty file, not an error")
        let unknown = try await s.resource(path: "seg_pgs_5_0.sup")
        XCTAssertEqual(unknown.status, 404)
    }

    func testTruncatedPGSBlockKeepsTheWholeSegmentsOnly() async throws {
        let block: [UInt8] = [0x16, 0, 3, 1, 2, 3, 0x80, 0, 9]          // the last segment claims 9 bytes but has none
        var synth = SynthMKV()
        synth.subtitles = [SynthSubtitle(number: 8, codecID: "S_HDMV/PGS", cues: [(1000, 500, block)])]
        let (s, _) = make(synth)
        _ = try await s.prepare()
        let r = flatten(try await s.resource(path: "seg_pgs_8_0.sup"))
        XCTAssertEqual(r.count, 13 + 3, "only the complete segment is written")
    }

    // MARK: Track flags

    func testTrackFlagsAreParsed() async throws {
        var synth = SynthMKV()
        synth.subtitles = [SynthSubtitle(number: 5, language: "deu", name: "", isDefault: true, isForced: true, isHearingImpaired: true, cues: [])]
        let (s, _) = make(synth)
        let info = try await s.prepare()
        let t = try XCTUnwrap(info.subtitles.first)
        XCTAssertTrue(t.isForced); XCTAssertTrue(t.isHearingImpaired); XCTAssertTrue(t.isDefault)
        XCTAssertEqual(t.language, "deu")
        XCTAssertFalse(t.name.isEmpty, "a track without a name still gets one")
    }
}
