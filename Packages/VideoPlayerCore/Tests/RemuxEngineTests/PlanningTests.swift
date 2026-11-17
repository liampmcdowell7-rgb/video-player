import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore

final class SegmentPlannerTests: XCTestCase {
    func kfs(_ seconds: [Double]) -> [VideoKeyframe] { seconds.enumerated().map { VideoKeyframe(timeNs: Int64($1 * 1e9), clusterOffset: Int64(1000 + $0 * 100)) } }
    func starts(_ s: [SegmentSpec]) -> [Double] { s.map { Double($0.startNs) / 1e9 } }
    func ends(_ s: [SegmentSpec]) -> [Double] { s.map { Double($0.endNs) / 1e9 } }
    let sec: Int64 = 1_000_000_000

    func testRegularGOPsAreGroupedToTheTarget() {
        let plan = SegmentPlanner.plan(keyframes: kfs(Array(stride(from: 0.0, to: 20.0, by: 2.0))), mediaEndNs: 20 * sec, targetNs: 6 * sec)
        XCTAssertEqual(starts(plan), [0, 6, 12, 18]); XCTAssertEqual(ends(plan), [6, 12, 18, 20])
        XCTAssertEqual(plan.map { $0.index }, [0, 1, 2, 3])
        XCTAssertEqual(plan.map { $0.clusterStart }, [1000, 1300, 1600, 1900], "reading starts at the cluster of the cut keyframe")
    }

    func testClosestKeyframeToTheTargetIsChosen() {
        let plan = SegmentPlanner.plan(keyframes: kfs([0, 5, 10, 15]), mediaEndNs: 20 * sec, targetNs: 6 * sec)
        XCTAssertEqual(starts(plan), [0, 5, 10])               // 5 s is closer to 6 s than 10 s
        XCTAssertEqual(ends(plan), [5, 10, 20])
    }

    func testMinimumLengthIsRespected() {
        let plan = SegmentPlanner.plan(keyframes: kfs([0, 1, 7]), mediaEndNs: 9 * sec, targetNs: 6 * sec, minNs: 3 * sec)
        XCTAssertEqual(starts(plan), [0, 7])
    }

    func testAGOPLongerThanTheTargetCannotBeSplit() {
        let plan = SegmentPlanner.plan(keyframes: kfs([0, 30]), mediaEndNs: 40 * sec, targetNs: 6 * sec)
        XCTAssertEqual(starts(plan), [0, 30]); XCTAssertEqual(plan[0].durationSeconds, 30)
    }

    func testDegenerateInputs() {
        XCTAssertTrue(SegmentPlanner.plan(keyframes: [], mediaEndNs: 10 * sec, targetNs: 6 * sec).isEmpty)
        let one = SegmentPlanner.plan(keyframes: kfs([3]), mediaEndNs: 10 * sec, targetNs: 6 * sec)
        XCTAssertEqual(starts(one), [3]); XCTAssertEqual(ends(one), [10])
        let messy = SegmentPlanner.plan(keyframes: kfs([4, 0, 0, 2, 8]), mediaEndNs: 10 * sec, targetNs: 4 * sec)
        XCTAssertEqual(starts(messy), [0, 4, 8], "unsorted and duplicate keyframes are normalised")
        let shortMedia = SegmentPlanner.plan(keyframes: kfs([0, 2]), mediaEndNs: 1 * sec, targetNs: 6 * sec)
        XCTAssertEqual(starts(shortMedia), [0], "the 2 s keyframe is inside the minimum length, so it is not a cut")
        XCTAssertEqual(shortMedia.last.map { $0.endNs }, 1 * sec)
        let shortMedia2 = SegmentPlanner.plan(keyframes: kfs([0, 2]), mediaEndNs: 1 * sec, targetNs: 6 * sec, minNs: 0)
        XCTAssertTrue(shortMedia2.allSatisfy { $0.endNs >= $0.startNs }, "a media end before the last keyframe never makes a negative segment")
        XCTAssertEqual(starts(shortMedia2), [0], "a keyframe past the media end is never a cut")
    }

    func testSegmentsAreContiguousAndCoverTheMedia() {
        let times = (0..<500).map { Double($0) * 2.5 }
        let plan = SegmentPlanner.plan(keyframes: kfs(times), mediaEndNs: 1250 * sec, targetNs: 6 * sec)
        for (a, b) in zip(plan, plan.dropFirst()) { XCTAssertEqual(a.endNs, b.startNs) }
        XCTAssertEqual(plan.first?.startNs, 0); XCTAssertEqual(plan.last?.endNs, 1250 * sec)
        XCTAssertTrue(plan.dropLast().allSatisfy { $0.durationSeconds >= 3 && $0.durationSeconds <= 9 })
    }
}

final class SeekMapTests: XCTestCase {
    func map() -> SeekMap {
        let sec: Int64 = 1_000_000_000
        return SeekMap(SegmentPlanner.plan(keyframes: (0..<5).map { VideoKeyframe(timeNs: Int64($0) * 6 * sec, clusterOffset: Int64($0)) },
                                           mediaEndNs: 27 * sec, targetNs: 6 * sec))
    }

    func testTimesMapToSegments() {
        let m = map()
        XCTAssertEqual(m.segments.count, 5)
        XCTAssertEqual(m.index(containingSeconds: 0), 0)
        XCTAssertEqual(m.index(containingSeconds: 5.999), 0)
        XCTAssertEqual(m.index(containingSeconds: 6), 1)
        XCTAssertEqual(m.index(containingSeconds: 17.5), 2)
        XCTAssertEqual(m.index(containingSeconds: 24), 4)
        XCTAssertEqual(m.index(containingSeconds: 1000), 4)
        XCTAssertEqual(m.index(containingSeconds: -3), 0)
    }

    func testDurationAndTargetDuration() {
        let m = map()
        XCTAssertEqual(m.durationNs, 27_000_000_000)
        XCTAssertEqual(m.targetDurationSeconds, 6)
        XCTAssertTrue(SeekMap([]).isEmpty); XCTAssertEqual(SeekMap([]).index(containingSeconds: 5), 0); XCTAssertEqual(SeekMap([]).targetDurationSeconds, 0)
    }

    func testEstimatorInterpolatesBetweenAnchors() {
        let e = ByteTimeEstimator(anchors: [], fileStart: 1000, fileEnd: 101_000, durationNs: 100_000_000_000)
        XCTAssertEqual(e.offset(forTimeNs: 50_000_000_000), 51_000)
        XCTAssertEqual(e.offset(forTimeNs: 0), 1000)
        XCTAssertEqual(e.offset(forTimeNs: 100_000_000_000), 101_000)
        XCTAssertEqual(e.offset(forTimeNs: 400_000_000_000), 101_000, "clamped to the end")
        let withAnchors = ByteTimeEstimator(anchors: [(40_000_000_000, 90_000), (10_000_000_000, 5_000)], fileStart: 1000, fileEnd: 101_000, durationNs: 100_000_000_000)
        XCTAssertEqual(withAnchors.offset(forTimeNs: 25_000_000_000), 47_500, "halfway between the anchors at 10 s and 40 s")
        XCTAssertEqual(withAnchors.offset(forTimeNs: 40_000_000_000), 90_000)
        XCTAssertGreaterThan(withAnchors.offset(forTimeNs: 70_000_000_000), 90_000)
    }
}

final class EngineBudgetTests: XCTestCase {
    func testSegmentLengthShrinksWithBitrate() {
        let b = EngineBudget()
        XCTAssertEqual(b.targetSegmentSeconds(bitrate: 20e6), 6)                               // plenty of room: the maximum
        XCTAssertEqual(b.targetSegmentSeconds(bitrate: 120e6), 4.474, accuracy: 0.01)          // 192 MiB / (2 windows x 1.5 x 15 MB/s)
        XCTAssertEqual(b.targetSegmentSeconds(bitrate: 400e6), 2)                              // the floor
        XCTAssertEqual(b.targetSegmentSeconds(bitrate: 0), 6)
    }

    func testWindowAndCapacityFormulas() {
        let b = EngineBudget()
        XCTAssertEqual(b.windowBytes(seconds: 4, bitrate: 80e6), 60_000_000)                  // 1.5 x 4 s x 10 MB/s
        XCTAssertEqual(b.windowsThatFit(windowBytes: 60_000_000), 3)
        XCTAssertEqual(b.windowsThatFit(windowBytes: 900_000_000), 1, "never fewer than one window")
        XCTAssertEqual(b.windowsThatFit(windowBytes: 0), 4)
    }

    func testOverBudgetThreshold() {
        let b = EngineBudget()
        XCTAssertFalse(b.isOverBudget(bitrate: 120e6))
        XCTAssertFalse(b.isOverBudget(bitrate: 260e6))
        XCTAssertTrue(b.isOverBudget(bitrate: 280e6))          // 2 windows x 1.5 x 2 s x 35 MB/s > 192 MiB
        XCTAssertFalse(EngineBudget(memoryBytes: 512 * 1024 * 1024).isOverBudget(bitrate: 280e6))
    }

    func testChosenSegmentLengthNeverExceedsTheBudget() {
        let b = EngineBudget()
        for mbps in stride(from: 5.0, through: 260.0, by: 5.0) {
            let seconds = b.targetSegmentSeconds(bitrate: mbps * 1e6)
            let need = Int64(b.minimumWindows) * b.windowBytes(seconds: seconds, bitrate: mbps * 1e6)
            XCTAssertLessThanOrEqual(need, b.memoryBytes, "\(mbps) Mbps at \(seconds) s")
        }
    }
}

final class PlaylistTests: XCTestCase {
    func video(supplemental: String? = nil, range: VideoRange = .pq) -> PlaylistVideo {
        PlaylistVideo(codecs: "hvc1.2.4.L120.B0", supplementalCodecs: supplemental, range: range, width: 3840, height: 2160, frameRate: 23.976,
                      averageBandwidth: 60_000_000, bandwidth: 75_000_000)
    }
    func audio(_ n: Int, _ lang: String, _ codecs: String, def: Bool) -> PlaylistAudio {
        PlaylistAudio(trackNumber: n, name: "Track \"\(n)\"", language: lang, codecs: codecs, channels: 6, isDefault: def, uri: "audio_\(n).m3u8")
    }

    func testMasterPlaylist() {
        let m = PlaylistWriter.master(video: video(supplemental: "dvh1.08.06/db1p"),
                                      audio: [audio(2, "eng", "ec-3", def: true), audio(3, "fre", "ec-3", def: false), audio(4, "und", "mp4a.40.2", def: false)])
        let lines = m.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "#EXTM3U")
        XCTAssertTrue(lines.contains("#EXT-X-VERSION:7"))
        XCTAssertTrue(m.contains("NAME=\"Track '2'\",LANGUAGE=\"en\",DEFAULT=YES,AUTOSELECT=YES,CHANNELS=\"6\",URI=\"audio_2.m3u8\""), m)
        XCTAssertTrue(m.contains("LANGUAGE=\"fr\",DEFAULT=NO"), m)
        XCTAssertFalse(m.contains("LANGUAGE=\"und\""), "undetermined language is omitted")
        let infIndex = lines.firstIndex { $0.hasPrefix("#EXT-X-STREAM-INF") }
        let inf = infIndex.map { lines[$0] }
        XCTAssertEqual(inf, "#EXT-X-STREAM-INF:BANDWIDTH=75000000,AVERAGE-BANDWIDTH=60000000,CODECS=\"hvc1.2.4.L120.B0,ec-3,mp4a.40.2\",SUPPLEMENTAL-CODECS=\"dvh1.08.06/db1p\",RESOLUTION=3840x2160,FRAME-RATE=23.976,VIDEO-RANGE=PQ,AUDIO=\"audio\"")
        XCTAssertEqual(infIndex.map { lines[$0 + 1] }, "video.m3u8")
    }

    func testMasterWithoutAudioOrDolbyVision() {
        let m = PlaylistWriter.master(video: video(range: .sdr), audio: [])
        XCTAssertFalse(m.contains("AUDIO="))
        XCTAssertFalse(m.contains("SUPPLEMENTAL-CODECS"))
        XCTAssertTrue(m.contains("VIDEO-RANGE=SDR"))
    }

    func testMediaPlaylist() {
        let p = PlaylistWriter.media(initURI: "init_video.mp4", segments: [("seg_video_0.m4s", 6.0), ("seg_video_1.m4s", 4.3333333)], targetDuration: 6)
        XCTAssertEqual(p, """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MAP:URI="init_video.mp4"
        #EXTINF:6.00000,
        seg_video_0.m4s
        #EXTINF:4.33333,
        seg_video_1.m4s
        #EXT-X-ENDLIST

        """)
    }

    func testLanguageMapping() {
        XCTAssertEqual(PlaylistWriter.bcp47("fre"), "fr"); XCTAssertEqual(PlaylistWriter.bcp47("ENG"), "en")
        XCTAssertNil(PlaylistWriter.bcp47("und")); XCTAssertNil(PlaylistWriter.bcp47(""))
        XCTAssertEqual(PlaylistWriter.bcp47("xyz"), "xyz")
    }
}
