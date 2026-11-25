import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore

/// R471 (54), PROVISIONAL (owner 25 Nov 2026 round 5, Part B item 1): the paths that can make a loopback request of the
/// converted path answer 500 for a Plex MKV of the owner's shape (HEVC Main 10, E-AC-3), each with the exact text the
/// serve log keeps and R472's Last Event row shows ("Loopback " + `LoopbackServeLog.firstFailure()`). These tests RECORD
/// what happens today; none of them changes playback.
final class PlexConvertedPathR471Tests: XCTestCase {
    /// The owner's shape, long enough for 8 segments of 2 s (keyframes every second).
    static func shape(seconds: Int = 16) -> SynthMKV {
        var s = ConvertedStartR472Tests.ownersShape()
        s.seconds = seconds
        return s
    }

    static func options(budget: EngineBudget = EngineBudget()) -> RemuxOptions {
        var o = RemuxOptions()
        o.targetSegmentSeconds = 2
        o.budget = budget
        return o
    }

    /// A reader that behaves like the file until `arm()` (the open), then answers every read in one chosen way.
    final class AfterOpenReader: ByteRangeReader, @unchecked Sendable {
        enum Mode {
            /// Throws this error (what PlexClient.read throws for the server's answer).
            case fails(Error)
            /// A 206 with only the first `fraction` of the bytes asked for (reads of more than 64 bytes).
            case short(Double)
            /// Every read waits `seconds`; a read cancelled while it waits throws `onCancel`.
            case slow(seconds: Double, onCancel: Error)
        }
        let inner: DataReader
        let mode: Mode
        private let lock = NSLock()
        private var armed = false
        init(_ data: Data, mode: Mode) { inner = DataReader(data); self.mode = mode }
        var size: Int64 { inner.size }
        func arm() { lock.withLock { armed = true } }

        func read(_ range: ByteRange) async throws -> Data {
            guard lock.withLock({ armed }) else { return try await inner.read(range) }
            switch mode {
            case .fails(let error):
                throw error
            case .short(let fraction):
                let data = try await inner.read(range)
                guard data.count > 64 else { return data }
                return data.prefix(Int(Double(data.count) * fraction))
            case .slow(let seconds, let onCancel):
                do { try await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) } catch { throw onCancel }
                return try await inner.read(range)
            }
        }
    }

    /// The first resources in the player's order, answered as `RemuxHost.start`'s handler answers them; returns the serve
    /// log's first failure (the text after "Loopback " in the Last Event row) and each answer.
    static func serve(_ reader: AfterOpenReader, _ names: [String] = ConvertedStartR472Tests.firstResources)
        async throws -> (firstFailure: String?, answers: [(name: String, status: Int, error: String?)]) {
        let session = MatroskaRemuxSession(reader: reader, options: options())
        _ = try await session.prepare()
        reader.arm()
        let log = LoopbackServeLog()
        var answers: [(name: String, status: Int, error: String?)] = []
        for name in names {
            let token = log.asked(name)
            do {
                let response = try await session.resource(path: name)
                log.answered(token, status: response.status)
                answers.append((name, response.status, nil))
            } catch {
                log.failed(token, status: 500, error: String(describing: error))
                answers.append((name, 500, String(describing: error)))
            }
        }
        await session.cancel()
        return (log.firstFailure(), answers)
    }

    // MARK: Read errors once the file is open (PlexClient.read: 200, 416, other statuses; PlexHTTP.send: transport)

    /// Each answer of the server to a ranged read after the open, and the Last Event text it gives. The playlists, the
    /// init segments and segment 0 read nothing (segment 0's window was read by the open), so the first resource that
    /// fails is always seg_video_1.m4s, at once.
    func testEachServerAnswerAfterTheOpenAndItsLastEventText() async throws {
        let data = Self.shape().build().data
        let timedOut = String(describing: URLError(.timedOut))
        let cases: [(error: Error, text: String)] = [
            (SourceError.rangesNotSupported, "seg_video_1.m4s: rangesNotSupported"),          // the server answered 200
            (SourceError.rangeNotSatisfiable, "seg_video_1.m4s: rangeNotSatisfiable"),        // the server answered 416
            (SourceError.httpStatus(500), "seg_video_1.m4s: httpStatus(500)"),                 // any other status
            (SourceError.httpStatus(503), "seg_video_1.m4s: httpStatus(503)"),
            (SourceError.notFound, "seg_video_1.m4s: notFound"),                               // 404 (PlexHTTP.check)
            (SourceError.unauthorized, "seg_video_1.m4s: unauthorized"),                       // 401
            // 30 s with no byte: URLSession throws URLError .timedOut, which PlexHTTP.send turns into transport(text).
            (SourceError.transport(timedOut), "seg_video_1.m4s: transport(\(String(reflecting: timedOut)))"),
        ]
        for (error, text) in cases {
            let (failure, answers) = try await Self.serve(AfterOpenReader(data, mode: .fails(error)))
            print("R471 (54) read error | \(error) | Last Event: Loopback \(failure ?? "nil")")
            XCTAssertEqual(failure, LoopbackServeLog.redact(text), "\(error)")
            XCTAssertEqual(answers.prefix(7).map(\.status), Array(repeating: 200, count: 7), "nothing before segment 1 reads")
            XCTAssertEqual(answers.filter { $0.status == 500 }.map(\.name), ["seg_video_1.m4s", "seg_audio_2_1.m4s"])
        }
    }

    /// A 206 that carries fewer bytes than asked for (not at the end of the file). PlexClient.read passes it on; the window
    /// parser stops at the cut cluster without an error. What the segment then answers is recorded here.
    func testAShort206IsPassedOnAndWhatTheSegmentAnswers() async throws {
        let data = Self.shape().build().data
        for fraction in [0.5, 0.05] {
            let (failure, answers) = try await Self.serve(AfterOpenReader(data, mode: .short(fraction)))
            for a in answers { print("R471 (54) short 206 (\(fraction)) | \(a.name) | \(a.status)" + (a.error.map { " | \($0)" } ?? "")) }
            print("R471 (54) short 206 (\(fraction)) | Last Event: Loopback \(failure ?? "nil")")
            let seg1 = try XCTUnwrap(answers.first { $0.name == "seg_video_1.m4s" })
            if fraction == 0.05 {
                XCTAssertEqual(seg1.status, 500)
                XCTAssertEqual(failure?.hasPrefix("seg_video_1.m4s: "), true, failure ?? "nil")
            }
        }
    }

    // MARK: The codec private (hvcC)

    /// An empty or cut CodecPrivate fails the OPEN, before the loopback starts: it never gives a 500, and the text is in the
    /// Error row (Step: opening the file), not in Last Event.
    func testAnEmptyOrCutCodecPrivateFailsTheOpenNotALoopbackRequest() async throws {
        for (label, hvcc) in [("empty", [UInt8]()), ("cut to 10 bytes", Array(makeHvcC(profile: 2, level: 120, bitDepth: 10).prefix(10)))] {
            var s = Self.shape()
            s.hvcC = hvcc
            let session = MatroskaRemuxSession(reader: DataReader(s.build().data), options: Self.options())
            do {
                _ = try await session.prepare()
                XCTFail("\(label): the file opened")
            } catch {
                print("R471 (54) hvcC \(label) | the open fails: \(error)")
                XCTAssertNotNil(error as? RemuxError, "\(label): \(error)")
            }
        }
    }

    // MARK: Read-ahead cancelling a window that another request waits for

    /// The player asks for video and audio on two connections, and the audio segment it asks for can lag the video one.
    /// An audio request BEHIND the video playhead counts as a seek for the read-ahead planner, which cancels the windows in
    /// flight that are far from it, including the window the video request is waiting for. The video request then fails
    /// although the player never closed it. With a small read-ahead budget (capacity 1) a lag of two segments is enough.
    /// RECORDED here as found (see the bug fix in the next commit, R471 (55)).
    func testAnAudioRequestBehindTheVideoCancelsTheWindowTheVideoRequestWaitsFor() async throws {
        let data = Self.shape(seconds: 24).build().data
        // What PlexClient.read throws when its read is cancelled mid-request: URLSession's URLError .cancelled, made
        // transport(text) by PlexHTTP.send (it is not a CancellationError).
        let cancelledText = String(describing: URLError(.cancelled))
        let reader = AfterOpenReader(data, mode: .slow(seconds: 0.4, onCancel: SourceError.transport(cancelledText)))
        var small = EngineBudget(memoryBytes: 1)
        small.minimumWindows = 2
        let session = MatroskaRemuxSession(reader: reader, options: Self.options(budget: small))
        _ = try await session.prepare()
        reader.arm()
        _ = try await session.resource(path: "seg_video_0.m4s")
        let log = LoopbackServeLog()
        let video = Task { () -> (status: Int, error: String?) in
            let token = log.asked("seg_video_4.m4s")
            do {
                let r = try await session.resource(path: "seg_video_4.m4s")
                log.answered(token, status: r.status)
                return (r.status, nil)
            } catch {
                let text = String(describing: error)
                let cancelled = error is CancellationError || (error as? RemuxError) == .cancelled
                if cancelled { log.failed(token, error: text) } else { log.failed(token, status: 500, error: text) }
                return (500, text)
            }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let audioToken = log.asked("seg_audio_2_2.m4s")
        do {
            let r = try await session.resource(path: "seg_audio_2_2.m4s")
            log.answered(audioToken, status: r.status)
        } catch {
            log.failed(audioToken, status: 500, error: String(describing: error))
        }
        let videoAnswer = await video.value
        await session.cancel()
        print("R471 (54) read-ahead cancel | seg_video_4.m4s | \(videoAnswer.status)" + (videoAnswer.error.map { " | \($0)" } ?? ""))
        print("R471 (54) read-ahead cancel | Last Event: Loopback \(log.firstFailure() ?? "nil")")
        XCTAssertEqual(videoAnswer.status, 500, "today: the video request fails")
        XCTAssertEqual(log.firstFailure(), LoopbackServeLog.redact("seg_video_4.m4s: transport(\(String(reflecting: cancelledText)))"))
    }
}
