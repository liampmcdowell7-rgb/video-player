import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore
import SourcePlex

/// R471 (63), PROVISIONAL (owner 25 Nov 2026 round 7, Part B item 1): the converted path end to end. A synthetic MKV of the
/// owner's shape (HEVC Main 10, E-AC-3) on a fake Plex server, read through the real `PlexClient` and `MediaSourceReader`
/// (as `SourceFactory.byteReader` does), served by `RemuxHost.start`'s handler, driven in the order a player asks: the
/// playlists, both init segments, then video and audio segments at the same time and out of order, a seek forwards and
/// backwards, read-ahead cancelled while a request waits, the library listing expiring (the clock jumps 5 minutes and the
/// server stops answering lists), and a request the player closes. Every request the player did not close must answer 200
/// with the same bytes a session over the file in memory gives.
final class ConvertedPathEndToEndR471Tests: XCTestCase {
    /// A Plex server with one movie library holding the synthetic file. Part reads wait `partDelay` (so requests overlap);
    /// after `failLists()` every library request answers 503 (only the file's bytes are still served).
    final class MKVPlexServer: HTTPTransport, @unchecked Sendable {
        let file: Data
        let partDelay: Double
        private let lock = NSLock()
        private var listsFail = false
        private var _listRequests = 0
        private var _partReads = 0
        private var _cancelledReads = 0
        init(file: Data, partDelay: Double) { self.file = file; self.partDelay = partDelay }
        /// File reads cancelled while they waited (read-ahead or a closed request).
        var cancelledReads: Int { lock.withLock { _cancelledReads } }
        func failLists() { lock.withLock { listsFail = true } }
        var listRequests: Int { lock.withLock { _listRequests } }
        var partReads: Int { lock.withLock { _partReads } }

        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            let path = request.url.path
            if path.hasPrefix("/library/parts/") {
                lock.withLock { _partReads += 1 }
                if partDelay > 0 {
                    do { try await Task.sleep(nanoseconds: UInt64(partDelay * 1e9)) } catch {
                        lock.withLock { _cancelledReads += 1 }
                        throw error
                    }
                }
                return part(request)
            }
            let failing: Bool = lock.withLock { _listRequests += 1; return listsFail }
            if failing { return HTTPResponse(statusCode: 503) }
            if path == "/library/sections" {
                return json(["MediaContainer": ["size": 1, "Directory": [
                    ["key": "1", "type": "movie", "title": "Movies", "Location": [["id": 1, "path": "/media/movies"]]]]]])
            }
            if path == "/library/sections/1/all" {
                let movie: [String: Any] = [
                    "ratingKey": "7001", "type": "movie", "title": "Synthetic Film", "year": 2020,
                    "Media": [["container": "mkv", "videoCodec": "hevc", "audioCodec": "eac3",
                               "Part": [["id": 7001, "key": "/library/parts/7001/1/file.mkv", "file": "/media/movies/Synthetic Film (2020).mkv",
                                         "size": file.count, "container": "mkv"]]]]]
                return json(["MediaContainer": ["size": 1, "totalSize": 1, "offset": 0, "Metadata": [movie]]])
            }
            return HTTPResponse(statusCode: 404)
        }

        private func part(_ request: HTTPRequest) -> HTTPResponse {
            let size = Int64(file.count)
            guard let header = request.headers["Range"], header.hasPrefix("bytes=") else { return HTTPResponse(statusCode: 200, body: file) }
            let parts = header.dropFirst(6).split(separator: "-").compactMap { Int64($0) }
            guard parts.count == 2, parts[0] < size else { return HTTPResponse(statusCode: 416) }
            let last = min(parts[1], size - 1)
            return HTTPResponse(statusCode: 206, headers: ["Content-Range": "bytes \(parts[0])-\(last)/\(size)"],
                                body: file.subdata(in: Int(parts[0])..<Int(last + 1)))
        }

        private func json(_ object: Any) -> HTTPResponse {
            HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"],
                         body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
        }
    }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var t = Date(timeIntervalSince1970: 1_800_000_000)
        var now: Date { lock.withLock { t } }
        func advance(_ s: TimeInterval) { lock.withLock { t = t.addingTimeInterval(s) } }
    }

    struct Answer { var name: String; var status: Int; var bytes: [UInt8]; var error: String? }

    /// What the player gets for `name`: the handler's answer, or 500 for a thrown error (as `Loopback.runHandler` does).
    private static func ask(_ handler: LoopbackHandler, _ name: String) async -> Answer {
        do {
            let r = try await handler(LoopbackRequest(method: "GET", path: "/" + name, headers: [:]))
            return Answer(name: name, status: r.status, bytes: r.body.chunks.flatMap { $0 }, error: nil)
        } catch {
            return Answer(name: name, status: 500, bytes: [], error: String(describing: error))
        }
    }

    private static func askTogether(_ handler: @escaping LoopbackHandler, _ names: [String]) async -> [Answer] {
        await withTaskGroup(of: (Int, Answer).self) { group in
            for (i, name) in names.enumerated() { group.addTask { (i, await ask(handler, name)) } }
            var out = [Answer?](repeating: nil, count: names.count)
            for await (i, a) in group { out[i] = a }
            return out.compactMap { $0 }
        }
    }

    private func run(budget: EngineBudget, partDelay: Double, mustCancel: Bool = false, label: String) async throws {
        let file = PlexConvertedPathR471Tests.shape(seconds: 24).build().data
        let options = PlexConvertedPathR471Tests.options(budget: budget)
        // The reference: the same file in memory, asked one resource at a time.
        let reference = MatroskaRemuxSession(reader: DataReader(file), options: options)
        _ = try await reference.prepare()

        let server = MKVPlexServer(file: file, partDelay: partDelay)
        let clock = Clock()
        let plex = PlexClient(baseURL: URL(string: "https://192-168-1-20.machine0001.plex.direct:32400")!, token: "server-token-placeholder",
                              identity: PlexClientIdentity(clientIdentifier: "install-1234", version: "0.1.0"), transport: server,
                              now: { clock.now })
        let path = try await plex.list("/Movies")[0].path
        let reader = try await MediaSourceReader.open(source: plex, path: path)
        let loopback = LastEventCancelledR471Tests.CapturingServer()
        let host = RemuxHost(reader: reader, options: options, server: loopback)
        _ = try await host.start()
        let handler = try XCTUnwrap(loopback.handler)

        var answers: [Answer] = []
        // The playlists and both init segments, in the player's order.
        for name in ["master.m3u8", "video.m3u8", "audio_2.m3u8", "init_video.mp4", "init_audio_2.mp4"] {
            answers.append(await Self.ask(handler, name))
        }
        // Video and audio at the same time, out of order.
        answers += await Self.askTogether(handler, ["seg_audio_2_1.m4s", "seg_video_1.m4s", "seg_video_0.m4s", "seg_audio_2_0.m4s"])
        // A seek forwards, then backwards (each a seek for the read-ahead planner, which cancels the windows it no longer wants).
        answers += await Self.askTogether(handler, ["seg_video_8.m4s", "seg_audio_2_8.m4s"])
        answers += await Self.askTogether(handler, ["seg_video_2.m4s", "seg_audio_2_2.m4s"])
        // Read-ahead cancelled while a request waits: the video request for 5 is in flight when the audio request behind it
        // (2, below the video playhead) moves the planner, and a seek to 10 comes while both still wait.
        async let v5 = Self.ask(handler, "seg_video_5.m4s")
        try await Task.sleep(nanoseconds: 20_000_000)
        async let a3 = Self.ask(handler, "seg_audio_2_3.m4s")
        try await Task.sleep(nanoseconds: 20_000_000)
        async let v10 = Self.ask(handler, "seg_video_10.m4s")
        answers += [await v5, await a3, await v10]
        // The library listing expires: 5 minutes later and the server answers no list; the file's bytes still come.
        clock.advance(301)
        server.failLists()
        answers += await Self.askTogether(handler, ["seg_video_4.m4s", "seg_audio_2_4.m4s", "seg_audio_2_5.m4s"])
        // A request the player closes (the loopback cancels its task), then the same segment asked again.
        // Segment 11 is far from every segment asked so far, so its window is still being read when the player closes it.
        let cancelledBefore = server.cancelledReads
        let closed = Task { await Self.ask(handler, "seg_video_11.m4s") }
        try await Task.sleep(nanoseconds: UInt64(partDelay * 0.5e9))
        closed.cancel()
        _ = await closed.value
        let closedRead = server.cancelledReads > cancelledBefore
        answers.append(await Self.ask(handler, "seg_video_11.m4s"))
        answers += await Self.askTogether(handler, ["seg_audio_2_11.m4s", "seg_video_6.m4s", "seg_audio_2_6.m4s", "seg_video_7.m4s", "seg_audio_2_7.m4s"])

        var wrong: [String] = []
        for a in answers {
            let expected = try await reference.resource(path: a.name)
            let expectedBytes: [UInt8] = expected.body.chunks.flatMap { $0 }
            if a.status != 200 || a.bytes != expectedBytes {
                wrong.append("\(a.name): \(a.status) \(a.error ?? "") bytes \(a.bytes.count)/\(expectedBytes.count)")
            }
        }
        let windowLoads = await host.session.windowLoads
        print("R471 (63) | \(label) | \(answers.count) answers | part reads \(server.partReads), cancelled \(server.cancelledReads)"
              + " | closed request stopped a read: \(closedRead) | window loads \(windowLoads) | list requests \(server.listRequests)"
              + " | Last Event: Loopback \(host.serveLog?.firstFailure() ?? "none") | wrong: \(wrong)")
        XCTAssertEqual(wrong, [], "every request the player did not close answers 200 with the file's bytes (\(label))")
        XCTAssertNil(host.serveLog?.firstFailure(), "no 500 in the serve log (\(label))")
        if mustCancel {
            // The seeks cancel read-ahead windows still being read (R471 (55) leaves the ones a request waits for).
            XCTAssertGreaterThan(server.cancelledReads, 0, "read-ahead was cancelled while file reads were in flight (\(label))")
        }
        // A request the player closes leaves its window loading for the next request of it (R471 (57) review): no read of
        // its own is stopped, no 500 is logged, and the same segment asked again answers 200 (checked above).
        await host.stop()
        await reference.cancel()
    }

    /// The engine's own read-ahead budget, reads of a fast local network.
    func testThePlayersRequestPatternOverPlexWithTheDefaultBudget() async throws {
        try await run(budget: EngineBudget(), partDelay: 0.005, label: "default budget")
    }

    /// The engine's own budget, slow reads (a remote server): the seeks cancel read-ahead windows still being read.
    func testThePlayersRequestPatternOverASlowPlexServer() async throws {
        try await run(budget: EngineBudget(), partDelay: 0.2, mustCancel: true, label: "default budget, slow reads")
    }

    /// A small budget (one window ahead), slow reads: requests wait on windows the planner lets go of.
    func testThePlayersRequestPatternOverPlexWithASmallBudget() async throws {
        var small = EngineBudget(memoryBytes: 1)
        small.minimumWindows = 2
        try await run(budget: small, partDelay: 0.3, label: "small budget")
    }
}
