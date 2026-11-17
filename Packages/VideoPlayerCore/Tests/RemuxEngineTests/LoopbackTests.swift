import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

final class ByteRangeHeaderTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(ByteRangeHeader.parse(nil, length: 100), .none)
        XCTAssertEqual(ByteRangeHeader.parse("bytes=0-9", length: 100), .range(start: 0, end: 9))
        XCTAssertEqual(ByteRangeHeader.parse("bytes=90-", length: 100), .range(start: 90, end: 99))
        XCTAssertEqual(ByteRangeHeader.parse("bytes=-10", length: 100), .range(start: 90, end: 99))
        XCTAssertEqual(ByteRangeHeader.parse("bytes=-500", length: 100), .range(start: 0, end: 99))
        XCTAssertEqual(ByteRangeHeader.parse("bytes=50-5000", length: 100), .range(start: 50, end: 99))
        XCTAssertEqual(ByteRangeHeader.parse("bytes=100-", length: 100), .unsatisfiable)
        XCTAssertEqual(ByteRangeHeader.parse("bytes=-0", length: 100), .unsatisfiable)
        XCTAssertEqual(ByteRangeHeader.parse("bytes=0-1,5-6", length: 100), .none, "multi-range requests get the whole body")
        XCTAssertEqual(ByteRangeHeader.parse("bytes=9-3", length: 100), .none)
        XCTAssertEqual(ByteRangeHeader.parse("items=0-9", length: 100), .none)
        XCTAssertEqual(ByteRangeHeader.parse("bytes=0-0", length: 0), .unsatisfiable)
    }
}

final class LoopbackServerTests: XCTestCase {
    static func pattern(_ n: Int, seed: Int = 0) -> [UInt8] { (0..<n).map { UInt8(truncatingIfNeeded: ($0 &* 31) &+ seed) } }

    func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }

    func get(_ url: URL, method: String = "GET", headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (d, r) = try await session().data(for: req)
        return (d, try XCTUnwrap(r as? HTTPURLResponse))
    }

    /// A server that answers /small, /chunks, /big and /boom.
    func makeServer(prefix: String? = "tok123") throws -> (POSIXLoopbackServer, URL) {
        let server = POSIXLoopbackServer(pathPrefix: prefix)
        let small = Self.pattern(1000)
        let chunks = [Self.pattern(300, seed: 1)[...], Self.pattern(400, seed: 2)[...], Self.pattern(300, seed: 3)[...]]
        let big = Self.pattern(8 * 1024 * 1024, seed: 9)
        let url = try server.start { request in
            switch request.path {
            case "/small": return LoopbackResponse(contentType: "application/octet-stream", body: LoopbackBody(small))
            case "/chunks": return LoopbackResponse(contentType: "video/mp4", body: LoopbackBody(chunks: chunks))
            case "/big": return LoopbackResponse(contentType: "video/mp4", body: LoopbackBody(big))
            case "/boom": throw RemuxError.io("boom")
            default: return .notFound()
            }
        }
        return (server, url)
    }

    func testBindsToLoopbackOnlyOnAnEphemeralPort() throws {
        let (server, url) = try makeServer()
        defer { server.stop() }
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertGreaterThan(server.port, 1023)
        XCTAssertTrue(url.path.hasPrefix("/tok123"))
        #if os(Linux)
        // The kernel's own view: the listening socket's local address is 127.0.0.1:<port> (0100007F), not 0.0.0.0.
        let table = try String(contentsOfFile: "/proc/net/tcp", encoding: .utf8)
        let hexPort = String(format: "%04X", server.port)
        let listening = table.split(separator: "\n").filter { $0.contains(":" + hexPort + " ") && $0.contains(" 0A ") }
        XCTAssertEqual(listening.count, 1, "one listening socket on the port")
        XCTAssertTrue(listening.first?.contains("0100007F:" + hexPort) ?? false, String(listening.first ?? "none"))
        #endif
    }

    func testServesBodyWithHeaders() async throws {
        let (server, base) = try makeServer(); defer { server.stop() }
        let (data, resp) = try await get(base.appendingPathComponent("small"))
        XCTAssertEqual(resp.statusCode, 200)
        XCTAssertEqual([UInt8](data), Self.pattern(1000))
        XCTAssertEqual(resp.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
        XCTAssertEqual(resp.value(forHTTPHeaderField: "Accept-Ranges"), "bytes")
        XCTAssertEqual(resp.value(forHTTPHeaderField: "Content-Length"), "1000")
    }

    func testRanges() async throws {
        let (server, base) = try makeServer(); defer { server.stop() }
        let url = base.appendingPathComponent("small")
        let full = Self.pattern(1000)
        var (d, r) = try await get(url, headers: ["Range": "bytes=10-19"])
        XCTAssertEqual(r.statusCode, 206); XCTAssertEqual([UInt8](d), Array(full[10...19]))
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Range"), "bytes 10-19/1000")
        (d, r) = try await get(url, headers: ["Range": "bytes=990-"])
        XCTAssertEqual(r.statusCode, 206); XCTAssertEqual([UInt8](d), Array(full[990...]))
        (d, r) = try await get(url, headers: ["Range": "bytes=-5"])
        XCTAssertEqual([UInt8](d), Array(full.suffix(5))); XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Range"), "bytes 995-999/1000")
        (d, r) = try await get(url, headers: ["Range": "bytes=2000-"])
        XCTAssertEqual(r.statusCode, 416); XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Range"), "bytes */1000")
        XCTAssertEqual(d.count, 0, "416 carries no body")
    }

    func testRangeAcrossChunkBoundaries() async throws {
        let (server, base) = try makeServer(); defer { server.stop() }
        var all = Self.pattern(300, seed: 1); all += Self.pattern(400, seed: 2); all += Self.pattern(300, seed: 3)
        let url = base.appendingPathComponent("chunks")
        for (a, b) in [(250, 749), (0, 299), (300, 699), (299, 300), (699, 700), (600, 999)] {
            let (d, r) = try await get(url, headers: ["Range": "bytes=\(a)-\(b)"])
            XCTAssertEqual(r.statusCode, 206, "\(a)-\(b)")
            XCTAssertEqual([UInt8](d), Array(all[a...b]), "range \(a)-\(b)")
        }
        let (whole, _) = try await get(url)
        XCTAssertEqual([UInt8](whole), all)
    }

    func testHeadHasLengthButNoBody() async throws {
        let (server, base) = try makeServer(); defer { server.stop() }
        let (d, r) = try await get(base.appendingPathComponent("small"), method: "HEAD")
        XCTAssertEqual(r.statusCode, 200); XCTAssertEqual(d.count, 0)
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Length"), "1000")
    }

    func testWrongTokenAndUnknownPathsAre404() async throws {
        let (server, base) = try makeServer(); defer { server.stop() }
        let root = try XCTUnwrap(URL(string: "http://127.0.0.1:\(server.port)/"))
        var (_, r) = try await get(root.appendingPathComponent("small"))
        XCTAssertEqual(r.statusCode, 404, "no token")
        (_, r) = try await get(root.appendingPathComponent("wrong").appendingPathComponent("small"))
        XCTAssertEqual(r.statusCode, 404, "wrong token")
        (_, r) = try await get(base.appendingPathComponent("nothing-here"))
        XCTAssertEqual(r.statusCode, 404)
    }

    func testHandlerErrorBecomes500AndServerKeepsWorking() async throws {
        let (server, base) = try makeServer(); defer { server.stop() }
        var (_, r) = try await get(base.appendingPathComponent("boom"))
        XCTAssertEqual(r.statusCode, 500)
        (_, r) = try await get(base.appendingPathComponent("small"))
        XCTAssertEqual(r.statusCode, 200)
    }

    func testEightMegabytesAndParallelRequests() async throws {
        let (server, base) = try makeServer(); defer { server.stop() }
        let expected = Self.pattern(8 * 1024 * 1024, seed: 9)
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for i in 0..<6 {
                group.addTask {
                    let from = i * 1_000_000
                    let (d, r) = try await self.get(base.appendingPathComponent("big"), headers: ["Range": "bytes=\(from)-\(from + 999_999)"])
                    return r.statusCode == 206 && [UInt8](d) == Array(expected[from..<(from + 1_000_000)])
                }
            }
            group.addTask {
                let (d, r) = try await self.get(base.appendingPathComponent("big"))
                return r.statusCode == 200 && d.count == expected.count && [UInt8](d) == expected
            }
            for try await ok in group { XCTAssertTrue(ok) }
        }
    }

    func testCurlKeepAliveAndRanges() throws {
        let curl = try TestMedia.curl()
        let (server, base) = try makeServer(); defer { server.stop() }
        // One curl process, two URLs: the second transfer reuses the connection (num_connects 0).
        let r = try runProcess(curl, ["-s", "--noproxy", "*", "-o", "/dev/null", "-o", "/dev/null", "-w", "%{http_code} %{num_connects} %{size_download}\\n",
                                      base.appendingPathComponent("small").absoluteString, base.appendingPathComponent("chunks").absoluteString])
        XCTAssertEqual(r.out.split(separator: "\n").map(String.init), ["200 1 1000", "200 0 1000"], r.err)
        let ranged = try runProcess(curl, ["-s", "--noproxy", "*", "-r", "5-14", "-o", "/dev/null", "-w", "%{http_code} %{size_download}", base.appendingPathComponent("small").absoluteString])
        XCTAssertEqual(ranged.out, "206 10", ranged.err)
        let closeRequest = try runProcess(curl, ["-s", "--noproxy", "*", "-H", "Connection: close", "-o", "/dev/null", "-w", "%{http_code}", base.appendingPathComponent("small").absoluteString])
        XCTAssertEqual(closeRequest.out, "200")
    }

    func testMalformedAndUnsupportedRequests() throws {
        let (server, base) = try makeServer(); defer { server.stop() }
        let bad = try rawExchange(port: server.port, request: "NOT A REQUEST\r\n\r\n")
        XCTAssertTrue(bad.hasPrefix("HTTP/1.1 400"), bad)
        let post = try rawExchange(port: server.port, request: "POST /\(base.pathComponents.dropFirst().first ?? "")/small HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        XCTAssertTrue(post.hasPrefix("HTTP/1.1 405"), post)
        XCTAssertTrue(post.contains("Allow: GET, HEAD"))
    }

    func testPeerClosingCancelsTheHandler() throws {
        let server = POSIXLoopbackServer(pathPrefix: nil)
        final class Flags: @unchecked Sendable { let lock = NSLock(); var started = false; var cancelled = false }
        let flags = Flags()
        _ = try server.start { _ in
            flags.lock.lock(); flags.started = true; flags.lock.unlock()
            while !Task.isCancelled { do { try await Task.sleep(nanoseconds: 10_000_000) } catch { break } }
            flags.lock.lock(); flags.cancelled = Task.isCancelled; flags.lock.unlock()
            throw RemuxError.cancelled
        }
        defer { server.stop() }
        let fd = try connectClient(port: server.port)
        let req = Array("GET /slow HTTP/1.1\r\nHost: x\r\n\r\n".utf8)
        _ = req.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline { flags.lock.lock(); let s = flags.started; flags.lock.unlock(); if s { break }; Thread.sleep(forTimeInterval: 0.01) }
        close(fd)
        var cancelled = false
        while Date() < deadline { flags.lock.lock(); cancelled = flags.cancelled; flags.lock.unlock(); if cancelled { break }; Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertTrue(flags.started); XCTAssertTrue(cancelled, "closing the connection must cancel the running handler")
    }

    func testStopRefusesNewConnectionsAndRestartIsRejected() throws {
        let (server, _) = try makeServer()
        XCTAssertThrowsError(try server.start { _ in .notFound() })
        let port = server.port
        server.stop()
        XCTAssertThrowsError(try connectClient(port: port))
        server.stop()                                                        // idempotent
    }

    // MARK: raw client helpers

    func connectClient(port: UInt16) throws -> Int32 {
        #if canImport(Glibc)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard fd >= 0 else { throw RemuxError.io("socket") }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET); addr.sin_port = port.bigEndian; addr.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        let r = withUnsafePointer(to: &addr) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard r == 0 else { close(fd); throw RemuxError.io("connect refused") }
        return fd
    }

    func rawExchange(port: UInt16, request: String) throws -> String {
        let fd = try connectClient(port: port)
        defer { close(fd) }
        let bytes = Array(request.utf8)
        _ = bytes.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var out: [UInt8] = []
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = buf.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            if n <= 0 { break }
            out += buf[0..<n]
            if out.count > 200 { break }
        }
        return String(decoding: out, as: UTF8.self)
    }
}
