import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore

/// R472 (owner's photos of Settings > Playback > Last Playback Problem, build 202611250008): a Plex MKV with HEVC Main 10
/// (hvc1.2.4.L120.90, 1920 x 1080) and E-AC-3 took the Converted path; the file opened (0.3 s), the loopback was ready
/// (0.3 s), the item was created (0.8 s), and the player never became ready; its last event was "HTTP 500" 25 s after it
/// opened. A 500 from the loopback means the session's handler THREW (RemuxHost.start; Loopback.runHandler answers 500).
///
/// This reproduces the start on Linux: a synthetic file of that shape, the session asked for the first resources in the
/// order the player asks for them, each answer timed and logged exactly as `RemuxHost` logs it (`LoopbackServeLog`), with
/// four readers: (a) normal, (b) slow, (c) HTTP-style errors once the file is open, (d) a Plex-style server answering 200
/// instead of 206 once the file is open. It prints how each case ends. It fixes nothing.
final class ConvertedStartR472Tests: XCTestCase {
    /// The first resources of this stream shape, in the player's order (one audio rendition, track 2).
    static let firstResources = ["master.m3u8", "video.m3u8", "audio_2.m3u8", "init_video.mp4", "init_audio_2.mp4",
                                 "seg_video_0.m4s", "seg_audio_2_0.m4s", "seg_video_1.m4s", "seg_audio_2_1.m4s"]

    /// The owner's file's shape: HEVC Main 10, level 4.0 (120), general_profile_compatibility_flags 0x20000000 (so the
    /// codec string is hvc1.2.4.L120.90), 1920 x 1080, one E-AC-3 5.1 track.
    static func ownersShape() -> SynthMKV {
        var hvcc = makeHvcC(profile: 2, level: 120, bitDepth: 10)
        hvcc.replaceSubrange(2..<6, with: [0x20, 0x00, 0x00, 0x00])
        var s = SynthMKV()
        s.hvcC = hvcc
        s.eac3Only = true
        s.width = 1920; s.height = 1080
        s.seconds = 8
        s.reorder = true
        return s
    }

    // MARK: Readers

    /// Counts reads; optionally waits before each, and fails every read once armed (after the file was opened).
    final class ScriptedReader: ByteRangeReader, @unchecked Sendable {
        enum Failure { case none, http(Int), rangesNotSupported, timedOut }
        let inner: DataReader
        let delay: Double
        let failure: Failure
        private let lock = NSLock()
        private var _armed = false
        private var _reads = 0
        init(_ data: Data, delay: Double = 0, failure: Failure = .none) { inner = DataReader(data); self.delay = delay; self.failure = failure }
        var size: Int64 { inner.size }
        var reads: Int { lock.withLock { _reads } }
        func arm() { lock.withLock { _armed = true } }

        func read(_ range: ByteRange) async throws -> Data {
            let armed: Bool = lock.withLock { _reads += 1; return _armed }
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1e9)) }
            if armed {
                switch failure {
                case .none: break
                // What PlexClient.read throws for these answers (SourcePlex/PlexClient.swift).
                case .http(let code): throw SourceError.httpStatus(code)
                case .rangesNotSupported: throw SourceError.rangesNotSupported
                // What URLSessionTransport throws when the 30 s request timeout passes (URLError .timedOut).
                case .timedOut: throw URLError(.timedOut)
                }
            }
            return try await inner.read(range)
        }
    }

    struct Answer { var resource: String; var status: Int; var seconds: Double; var reads: Int; var error: String? }

    /// Runs the first resources the way `RemuxHost.start`'s handler does: the answer's status, or 500 with the thrown text.
    static func run(_ reader: ScriptedReader, label: String, armAfterOpen: Bool = true) async throws -> (answers: [Answer], log: [String]) {
        var options = RemuxOptions()
        options.targetSegmentSeconds = 2
        let session = MatroskaRemuxSession(reader: reader, options: options)
        let opened = Date()
        let info = try await session.prepare()
        print("R472 \(label) | prepare | ok in \(fmt(Date().timeIntervalSince(opened))) s, \(reader.reads) reads | \(info.videoCodecString), "
              + "\(info.width)x\(info.height), audio \(info.audio.map(\.codecString)), segments \(info.segmentCount)")
        if armAfterOpen { reader.arm() }
        let log = LoopbackServeLog()
        var answers: [Answer] = []
        for name in firstResources {
            let token = log.asked(name)
            let before = reader.reads, t0 = Date()
            do {
                let response = try await session.resource(path: name)
                log.answered(token, status: response.status)
                answers.append(Answer(resource: name, status: response.status, seconds: Date().timeIntervalSince(t0), reads: reader.reads - before))
            } catch {
                log.failed(token, status: 500, error: String(describing: error))
                answers.append(Answer(resource: name, status: 500, seconds: Date().timeIntervalSince(t0), reads: reader.reads - before,
                                      error: String(describing: error)))
            }
        }
        await session.cancel()
        for a in answers {
            print("R472 \(label) | \(a.resource) | \(a.status) | \(fmt(a.seconds)) s | \(a.reads) reads" + (a.error.map { " | \($0)" } ?? ""))
        }
        let lines = log.lines()
        for line in lines { print("R472 \(label) | report line | Loopback \(line)") }
        return (answers, lines)
    }

    static func fmt(_ s: Double) -> String { String((s * 1000).rounded() / 1000) }

    // MARK: The four cases

    /// (a) A normal reader: every first resource answers, quickly. The shape alone (Main 10, level 4.0, E-AC-3 passed
    /// through) makes no resource throw.
    func testANormalReaderServesEveryFirstResource() async throws {
        let file = Self.ownersShape().build()
        let (answers, _) = try await Self.run(ScriptedReader(file.data), label: "a normal")
        XCTAssertEqual(answers.map(\.status), Array(repeating: 200, count: Self.firstResources.count))
        let session = MatroskaRemuxSession(reader: DataReader(file.data))
        let info = try await session.prepare()
        XCTAssertEqual(info.videoCodecString, "hvc1.2.4.L120.90", "the owner's codec string")
        XCTAssertEqual(info.audio.map(\.codecString), ["ec-3"])
        XCTAssertEqual(info.audio.first?.transcoded, false, "E-AC-3 is passed through")
    }

    /// (b) A slow reader (every read waits): nothing fails; a resource's time is its number of reads times the wait. The
    /// playlists and init segments read nothing; segment 0 reads nothing (the window was read by prepare); segment 1 needs
    /// the 32-byte head of the next cluster and its window. To reach 25 s on segment 1, each read would have to take about
    /// 12 s, which is a stalled server, not a slow one.
    func testASlowReaderIsSlowButNeverFails() async throws {
        let delay = 0.05
        let (answers, _) = try await Self.run(ScriptedReader(Self.ownersShape().build().data, delay: delay), label: "b slow (0.05 s per read)")
        XCTAssertEqual(answers.map(\.status), Array(repeating: 200, count: Self.firstResources.count))
        for a in answers where a.resource.hasSuffix(".m3u8") || a.resource.hasPrefix("init_") { XCTAssertEqual(a.reads, 0, a.resource) }
        let seg0 = try XCTUnwrap(answers.first { $0.resource == "seg_video_0.m4s" })
        XCTAssertEqual(seg0.reads, 0, "segment 0 comes from the window prepare read")
    }

    /// (c) The server fails every read once the file is open (HTTP 500 from Plex): the playlists, the init segments and
    /// segment 0 still answer (nothing to read); the first segment that needs a read answers 500 at once, with the text
    /// "httpStatus(500)" in the serve log only.
    func testServerErrorsAfterTheOpenAnswer500OnTheFirstSegmentThatReads() async throws {
        let (answers, lines) = try await Self.run(ScriptedReader(Self.ownersShape().build().data, failure: .http(500)), label: "c server 500")
        let failed = answers.filter { $0.status == 500 }
        XCTAssertEqual(failed.first?.resource, "seg_video_1.m4s")
        XCTAssertTrue(failed.first?.error?.contains("httpStatus(500)") ?? false)
        XCTAssertTrue(lines.contains { $0.hasPrefix("seg_video_1.m4s") && $0.contains("answered 500") })
        XCTAssertTrue(answers.prefix(7).allSatisfy { $0.status == 200 }, "nothing before segment 1 reads the file")
    }

    /// (d) A Plex-style server that answers 200 (the whole file) instead of 206: PlexClient.read throws
    /// rangesNotSupported. If that happens from the first read, the file never opens (the photo shows it opened); once the
    /// file is open, the first segment that reads answers 500 at once with "rangesNotSupported".
    func testAPlexServerAnswering200InsteadOf206() async throws {
        let data = Self.ownersShape().build().data
        do {
            let reader = ScriptedReader(data, failure: .rangesNotSupported); reader.arm()
            _ = try await MatroskaRemuxSession(reader: reader).prepare()
            XCTFail("the file opened although every read answered 200")
        } catch {
            print("R472 d 200 from the first read | prepare | fails at once: \(error)")
            XCTAssertEqual(error as? SourceError, .rangesNotSupported)
        }
        let (answers, _) = try await Self.run(ScriptedReader(data, failure: .rangesNotSupported), label: "d 200 after the open")
        XCTAssertEqual(answers.first { $0.status == 500 }?.resource, "seg_video_1.m4s")
        XCTAssertTrue(answers.first { $0.status == 500 }?.error?.contains("rangesNotSupported") ?? false)
    }

    // MARK: The report change (R472 step 3: nothing above reproduces the photo, so the failure is made readable)

    /// The serve log names the FIRST resource answered with 500 and the session's text, ready for the Last Event row.
    func testTheFirstFailureNamesTheResourceAndTheText() async throws {
        let (_, lines) = try await Self.run(ScriptedReader(Self.ownersShape().build().data, failure: .http(500)), label: "c again, for the row")
        XCTAssertTrue(lines.contains { $0.contains("answered 500") })
        let log = LoopbackServeLog()
        XCTAssertNil(log.firstFailure(), "nothing asked yet")
        let ok = log.asked("seg_video_0.m4s"); log.answered(ok, status: 200)
        XCTAssertNil(log.firstFailure(), "a success is no failure")
        let pending = log.asked("seg_audio_2_0.m4s")
        _ = pending
        XCTAssertNil(log.firstFailure(), "no answer yet is no failure")
        let cancelled = log.asked("seg_video_1.m4s"); log.failed(cancelled, error: "cancelled")
        XCTAssertNil(log.firstFailure(), "a request the player closed is no 500")
        let first = log.asked("seg_video_2.m4s")
        log.failed(first, status: 500, error: "io: GET http://10.0.0.2:32400/library/parts/1/file.mkv?X-Plex-Token=abcdef123456 failed")
        let second = log.asked("seg_audio_2_1.m4s"); log.failed(second, status: 500, error: "httpStatus(500)")
        let failure = try XCTUnwrap(log.firstFailure())
        print("R472 row | " + failure)
        XCTAssertTrue(failure.hasPrefix("seg_video_2.m4s: io: GET "), failure)
        XCTAssertFalse(failure.contains("abcdef123456"), "the token is removed")
        XCTAssertTrue(failure.contains("X-Plex-Token=<token>"), failure)
    }

    /// The URLSession case: a request that sends nothing for 30 s fails with URLError .timedOut (the transport's
    /// `timeoutIntervalForRequest`). Scaled here to 0.2 s: the resource that needed the read answers 500 after the wait.
    /// This is the only case in which a 500 comes LATE; on the device it would come about 30 s after the request.
    func testAStalledRequestAnswers500AfterTheTimeout() async throws {
        let reader = ScriptedReader(Self.ownersShape().build().data, delay: 0.2, failure: .timedOut)
        let (answers, _) = try await Self.run(reader, label: "e stalled read (timeout scaled to 0.2 s)")
        let failed = try XCTUnwrap(answers.first { $0.status == 500 })
        XCTAssertEqual(failed.resource, "seg_video_1.m4s")
        XCTAssertGreaterThanOrEqual(failed.seconds, 0.2)
    }
}
