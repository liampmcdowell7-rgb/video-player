import XCTest
import Foundation
import VideoPlayerCore
import RemuxEngine
@testable import SourceRangeProxy
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// FIXTURE: an in-memory file served through the real loopback server on 127.0.0.1; no network beyond loopback.
final class SourceRangeProxyTests: XCTestCase {
    private func pattern(_ n: Int) -> Data { Data((0..<n).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) }) }

    private func fetch(_ url: URL, method: String = "GET", range: String? = nil) async throws -> (Data, HTTPURLResponse) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let range { request.setValue(range, forHTTPHeaderField: "Range") }
        let (d, r) = try await URLSession(configuration: cfg).data(for: request)
        return (d, try XCTUnwrap(r as? HTTPURLResponse))
    }

    func testPlanForAShortRangeAWholeFileAndOutOfRange() {
        XCTAssertEqual(RangeProxyPlan.make(rangeHeader: "bytes=10-19", method: "GET", size: 1000, maxWindow: 100), .window(start: 10, end: 19, partial: true))
        XCTAssertEqual(RangeProxyPlan.make(rangeHeader: nil, method: "GET", size: 50, maxWindow: 100), .window(start: 0, end: 49, partial: false))
        XCTAssertEqual(RangeProxyPlan.make(rangeHeader: nil, method: "GET", size: 500, maxWindow: 100), .window(start: 0, end: 99, partial: true))
        XCTAssertEqual(RangeProxyPlan.make(rangeHeader: "bytes=900-", method: "GET", size: 1000, maxWindow: 100), .window(start: 900, end: 999, partial: true))
        XCTAssertEqual(RangeProxyPlan.make(rangeHeader: "bytes=0-", method: "GET", size: 1000, maxWindow: 100), .window(start: 0, end: 99, partial: true))
        XCTAssertEqual(RangeProxyPlan.make(rangeHeader: "bytes=1000-", method: "GET", size: 1000, maxWindow: 100), .unsatisfiable)
        XCTAssertEqual(RangeProxyPlan.make(rangeHeader: nil, method: "GET", size: 0, maxWindow: 100), .empty)
        XCTAssertEqual(RangeProxyPlan.make(rangeHeader: nil, method: "HEAD", size: 1000, maxWindow: 100), .window(start: 0, end: 0, partial: true))
    }

    func testAByteRangeIsServedWithTheRealTotalInContentRange() async throws {
        let data = pattern(100_000)
        let proxy = SourceRangeProxy(maxWindow: 4096)
        defer { proxy.stop() }
        let url = try proxy.start(reader: DataReader(data), fileName: "film.mp4")
        XCTAssertEqual(url.lastPathComponent, "film.mp4")
        let (body, response) = try await fetch(url, range: "bytes=1000-1999")
        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(body, data.subdata(in: 1000..<2000))
        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Range"), "bytes 1000-1999/100000")
        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), "video/mp4")
    }

    func testAnOpenEndedRangeIsCutToTheWindowAndReportsWhatWasSent() async throws {
        let data = pattern(100_000)
        let proxy = SourceRangeProxy(maxWindow: 4096)
        defer { proxy.stop() }
        let url = try proxy.start(reader: DataReader(data), fileName: "a.mp4")
        let (body, response) = try await fetch(url, range: "bytes=50000-")
        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(body.count, 4096)
        XCTAssertEqual(body, data.subdata(in: 50000..<54096))
        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Range"), "bytes 50000-54095/100000")
    }

    func testTheTailEndsAtTheLastByteAndPastTheEndIsRefused() async throws {
        let data = pattern(10_000)
        let proxy = SourceRangeProxy(maxWindow: 4096)
        defer { proxy.stop() }
        let url = try proxy.start(reader: DataReader(data), fileName: "a.mp4")
        let (tail, tailResponse) = try await fetch(url, range: "bytes=9990-")
        XCTAssertEqual(tail, data.suffix(10))
        XCTAssertEqual(tailResponse.value(forHTTPHeaderField: "Content-Range"), "bytes 9990-9999/10000")
        let (_, beyond) = try await fetch(url, range: "bytes=10000-")
        XCTAssertEqual(beyond.statusCode, 416)
    }

    func testASmallFileWithoutARangeIsServedWhole() async throws {
        let data = pattern(1000)
        let proxy = SourceRangeProxy(maxWindow: 4096)
        defer { proxy.stop() }
        let url = try proxy.start(reader: DataReader(data), fileName: "a.mov")
        let (body, response) = try await fetch(url)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(body, data)
        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), "video/quicktime")
    }

    func testReadsAreOnlyWhatWasAsked() async throws {
        let reader = DataReader(pattern(1_000_000))
        let proxy = SourceRangeProxy(maxWindow: 8192)
        defer { proxy.stop() }
        let url = try proxy.start(reader: reader, fileName: "a.mp4")
        _ = try await fetch(url, range: "bytes=500000-500099")
        XCTAssertEqual(reader.bytesRead, 100, "a 100-byte range reads 100 bytes from the source, not the whole file")
    }

    func testContentTypes() {
        XCTAssertEqual(SourceRangeProxy.contentType(forFileName: "x.M4V"), "video/mp4")
        XCTAssertEqual(SourceRangeProxy.contentType(forFileName: "x.mkv"), "video/x-matroska")
        XCTAssertEqual(SourceRangeProxy.contentType(forFileName: "x.bin"), "application/octet-stream")
    }
}
