import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// R441: what `prepare()` reads and how long it takes, and the error text of a loopback 500 (diagnostics only).
final class PrepareDiagnosticsTests: XCTestCase {
    /// Adds a fixed delay to every read, like one HTTP request per read on a network source.
    final class DelayedReader: ByteRangeReader, @unchecked Sendable {
        let inner: DataReader
        let delayNanoseconds: UInt64
        init(_ data: Data, delayNanoseconds: UInt64) { inner = DataReader(data); self.delayNanoseconds = delayNanoseconds }
        var size: Int64 { inner.size }
        func read(_ range: ByteRange) async throws -> Data {
            try await Task.sleep(nanoseconds: delayNanoseconds)
            return try await inner.read(range)
        }
    }

    /// Reads normally until `failing` is switched on, then throws an error that carries a token.
    final class FlakyReader: ByteRangeReader, @unchecked Sendable {
        let inner: DataReader
        private let lock = NSLock()
        private var _failing = false
        init(_ data: Data) { inner = DataReader(data) }
        var size: Int64 { inner.size }
        var failing: Bool { get { lock.withLock { _failing } } set { lock.withLock { _failing = newValue } } }
        func read(_ range: ByteRange) async throws -> Data {
            if failing { throw RemuxError.io("GET http://server.invalid/part/1?X-Plex-Token=SECRET1234 answered HTTP 500") }
            return try await inner.read(range)
        }
    }

    func testAFileWithoutCuesCostsOneReadPerClusterAndTheReportSaysSo() async throws {
        // 4 frames per second, every frame a keyframe in its own cluster: 2400 cluster headers, thousands of reads.
        var f = SynthMKV(); f.fps = 4; f.gopFrames = 1; f.seconds = 600; f.withCues = false; f.audio = false
        let built = f.build()
        let delay: UInt64 = 300_000                                   // 0.3 ms per read
        let reader = DelayedReader(built.data, delayNanoseconds: delay)
        var o = RemuxOptions(); o.targetSegmentSeconds = 60
        let session = MatroskaRemuxSession(reader: reader, options: o)
        let info = try await session.prepare()
        XCTAssertTrue(info.usedClusterScan)
        let diagnostics = try XCTUnwrap(info.prepareDiagnostics)
        let scan = try XCTUnwrap(diagnostics.phases.first { $0.name.hasPrefix("cluster scan") })
        XCTAssertEqual(built.clusterOffsets.count, 2400)
        XCTAssertGreaterThanOrEqual(scan.reads, 2400, "one raw read per cluster header")
        XCTAssertLessThanOrEqual(scan.reads, 2402)
        XCTAssertGreaterThanOrEqual(scan.seconds, Double(scan.reads) * Double(delay) / 1e9 * 0.9, "the delay of every read is in the phase time")
        XCTAssertEqual(diagnostics.totalReads, reader.inner.readCount, "the tally and the reader agree on every read")
        XCTAssertEqual(diagnostics.totalBytes, reader.inner.bytesRead)
        XCTAssertTrue(diagnostics.phases.map(\.name).contains("index load"))
        XCTAssertTrue(diagnostics.phases.map(\.name).contains("first window"))
        let lines = diagnostics.lines
        XCTAssertTrue(lines.contains { $0.hasPrefix("Prepare, cluster scan (2400 clusters): ") && $0.contains(" reads, ") }, "\(lines)")
        XCTAssertTrue(lines.last?.hasPrefix("Prepare, total: ") == true)
    }

    func testAFileWithCuesDoesNoScan() async throws {
        let built = SynthMKV().build()
        let reader = DelayedReader(built.data, delayNanoseconds: 0)
        let session = MatroskaRemuxSession(reader: reader)
        let info = try await session.prepare()
        let names = try XCTUnwrap(info.prepareDiagnostics).phases.map(\.name)
        XCTAssertFalse(names.contains { $0.hasPrefix("cluster scan") })
        XCTAssertTrue(names.contains { $0.hasPrefix("cues") })
        XCTAssertEqual(try XCTUnwrap(info.prepareDiagnostics).totalReads, reader.inner.readCount)
    }

    func testTheReportLinesFormat() {
        let d = PrepareDiagnostics(phases: [.init(name: "index load", seconds: 0.31, reads: 1, bytes: 131_072),
                                            .init(name: "cluster scan (10 clusters)", seconds: 12.4, reads: 10, bytes: 40_960)])
        XCTAssertEqual(d.lines, ["Prepare, index load: 0.31 s, 1 read, 131 KB",
                                 "Prepare, cluster scan (10 clusters): 12 s, 10 reads, 40 KB",
                                 "Prepare, total: 13 s, 11 reads, 172 KB"])
        XCTAssertEqual(PrepareDiagnostics().lines, [])
    }

    func testTheRedactionRemovesTokensAndKeepsTheRest() {
        let text = "GET http://server.invalid/part/1?X-Plex-Token=SECRET1234&x=1 failed; Authorization: Bearer abc.def\nsecond line"
        let out = LoopbackServeLog.redact(text)
        XCTAssertFalse(out.contains("SECRET1234")); XCTAssertFalse(out.contains("abc.def")); XCTAssertFalse(out.contains("\n"))
        XCTAssertTrue(out.contains("X-Plex-Token=<token>&x=1"))
        XCTAssertLessThanOrEqual(LoopbackServeLog.redact(String(repeating: "a", count: 1000)).count, 300)
    }

    func testAnEntryShowsTheStatusAndTheErrorTextTogether() {
        let log = LoopbackServeLog()
        let t = log.asked("/seg_video_1.m4s")
        log.failed(t, status: 500, error: "io: token=SECRET1234 refused")
        XCTAssertEqual(log.all.first?.status, 500)
        XCTAssertEqual(log.all.first?.error, "io: token=<token> refused")
        XCTAssertTrue(log.lines().first?.contains("answered 500 after ") == true)
        XCTAssertTrue(log.lines().first?.hasSuffix(": io: token=<token> refused") == true)
    }

    func testAReadThatThrowsGivesA500WhoseEntryCarriesTheErrorText() async throws {
        let built = SynthMKV().build()
        let reader = FlakyReader(built.data)
        var o = RemuxOptions(); o.targetSegmentSeconds = 2
        let host = RemuxHost(reader: reader, options: o, server: POSIXLoopbackServer(pathPrefix: nil))
        let base = try await host.start()
        defer { Task { await host.stop() } }
        reader.failing = true
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]
        let url = base.deletingLastPathComponent().appendingPathComponent("seg_video_1.m4s")
        let (_, response) = try await URLSession(configuration: cfg).data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 500)
        let log = try XCTUnwrap(host.serveLog)
        let entry = try XCTUnwrap(log.all.first { $0.name == "seg_video_1.m4s" })
        XCTAssertEqual(entry.status, 500)
        let error = try XCTUnwrap(entry.error)
        XCTAssertTrue(error.contains("HTTP 500"), error)
        XCTAssertTrue(error.contains("X-Plex-Token=<token>"), error)
        XCTAssertFalse(error.contains("SECRET1234"))
        XCTAssertTrue(log.lines().contains { $0.hasPrefix("seg_video_1.m4s: ") && $0.contains("answered 500 after ") })
    }
}
