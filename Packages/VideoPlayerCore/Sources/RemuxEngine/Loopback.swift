import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// A small HTTP/1.1 server on a POSIX socket bound to 127.0.0.1 (ephemeral port). AVPlayer reads the HLS playlists and
// fMP4 segments from it. Features: GET / HEAD, byte ranges (206 / 416), keep-alive, a secret path prefix, and
// cancellation of the handler when the client closes the connection. Everything the app needs sits behind
// `LoopbackServer`, so tests can use a fake and the engine never touches sockets directly.

public struct LoopbackRequest: Sendable {
    public var method: String
    /// Path with the secret prefix removed, starting with "/".
    public var path: String
    /// Header names lower-cased.
    public var headers: [String: String]
}

/// A response body made of shared slices, so a segment is sent straight from the window it was read into.
public struct LoopbackBody: Sendable {
    public var chunks: [ArraySlice<UInt8>]
    public var count: Int
    public init(chunks: [ArraySlice<UInt8>]) { self.chunks = chunks; self.count = chunks.reduce(0) { $0 + $1.count } }
    public init(_ bytes: [UInt8]) { self.init(chunks: [bytes[...]]) }
    public init(string: String) { self.init(Array(string.utf8)) }
    public static let empty = LoopbackBody(chunks: [])
}

public struct LoopbackResponse: Sendable {
    public var status: Int
    public var contentType: String
    public var body: LoopbackBody
    public var headers: [(String, String)] = []
    public init(status: Int = 200, contentType: String, body: LoopbackBody, headers: [(String, String)] = []) {
        self.status = status; self.contentType = contentType; self.body = body; self.headers = headers
    }
    public static func notFound() -> LoopbackResponse { LoopbackResponse(status: 404, contentType: "text/plain", body: LoopbackBody(string: "not found\n")) }
}

public typealias LoopbackHandler = @Sendable (LoopbackRequest) async throws -> LoopbackResponse

public protocol LoopbackServer: AnyObject, Sendable {
    /// Starts listening and returns the base URL, e.g. `http://127.0.0.1:49152/<token>/`.
    func start(handler: @escaping LoopbackHandler) throws -> URL
    func stop()
}

/// HTTP byte-range parsing (RFC 9110 14.1.2), single ranges only.
public enum ByteRangeHeader {
    public enum Result: Equatable { case none, range(start: Int, end: Int), unsatisfiable }

    public static func parse(_ header: String?, length: Int) -> Result {
        guard let h = header?.trimmingCharacters(in: .whitespaces), h.lowercased().hasPrefix("bytes=") else { return .none }
        let spec = String(h.dropFirst(6))
        if spec.contains(",") { return .none }            // multi-range: answer with the whole body
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return .none }
        if parts[0].isEmpty {
            guard let n = Int(parts[1]), n > 0 else { return .unsatisfiable }
            if length == 0 { return .unsatisfiable }
            return .range(start: max(0, length - n), end: length - 1)
        }
        guard let start = Int(parts[0]), start >= 0 else { return .none }
        if start >= length { return .unsatisfiable }
        if parts[1].isEmpty { return .range(start: start, end: length - 1) }
        guard let end = Int(parts[1]), end >= start else { return .none }
        return .range(start: start, end: min(end, length - 1))
    }
}

public final class POSIXLoopbackServer: LoopbackServer, @unchecked Sendable {
    private let token: String
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var running = false
    private var handler: LoopbackHandler?
    private var openFDs = Set<Int32>()
    public private(set) var port: UInt16 = 0
    /// Number of requests answered (tests, diagnostics).
    public private(set) var requestCount = 0

    /// `pathPrefix` is a secret path component: other apps on the device can reach loopback ports, so the playlist
    /// URL is not guessable. Pass nil to serve at the root (tests).
    public init(pathPrefix: String? = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()) {
        self.token = pathPrefix ?? ""
    }

    deinit { stop() }

    public func start(handler: @escaping LoopbackHandler) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        guard !running else { throw RemuxError.io("server already started") }
        let fd = socket(AF_INET, Self.streamType, 0)
        guard fd >= 0 else { throw RemuxError.io("socket() failed: errno \(errno)") }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        let bindResult = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bindResult == 0 else { close(fd); throw RemuxError.io("bind() failed: errno \(errno)") }
        guard listen(fd, 16) == 0 else { close(fd); throw RemuxError.io("listen() failed: errno \(errno)") }
        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        guard nameResult == 0 else { close(fd); throw RemuxError.io("getsockname() failed") }
        port = UInt16(bigEndian: bound.sin_port)
        listenFD = fd
        running = true
        self.handler = handler
        let acceptor = Thread { [weak self] in self?.acceptLoop(fd: fd) }
        acceptor.name = "remux.loopback.accept"
        acceptor.start()
        let prefix = token.isEmpty ? "" : "\(token)/"
        guard let url = URL(string: "http://127.0.0.1:\(port)/\(prefix)") else { throw RemuxError.io("bad URL") }
        return url
    }

    public func stop() {
        lock.lock()
        let fd = listenFD
        let wasRunning = running
        running = false
        listenFD = -1
        let fds = openFDs
        openFDs.removeAll()
        handler = nil
        lock.unlock()
        guard wasRunning else { return }
        shutdown(fd, Int32(SHUT_RDWR)); close(fd)
        for c in fds { shutdown(c, Int32(SHUT_RDWR)) }
    }

    // MARK: Accept and serve

    private static var streamType: Int32 {
        #if canImport(Glibc)
        return Int32(SOCK_STREAM.rawValue)
        #else
        return SOCK_STREAM
        #endif
    }

    private var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    private func acceptLoop(fd: Int32) {
        while isRunning {
            let c = accept(fd, nil, nil)
            if c < 0 { if !isRunning { return }; if errno == EINTR { continue }; return }
            #if canImport(Darwin)
            var on: Int32 = 1
            setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            #endif
            var nodelay: Int32 = 1
            setsockopt(c, Int32(IPPROTO_TCP), TCP_NODELAY, &nodelay, socklen_t(MemoryLayout<Int32>.size))
            lock.lock(); openFDs.insert(c); lock.unlock()
            let t = Thread { [weak self] in
                self?.serve(connection: c)
                self?.lock.lock(); self?.openFDs.remove(c); self?.lock.unlock()
                close(c)
            }
            t.name = "remux.loopback.conn"
            t.start()
        }
    }

    private func serve(connection fd: Int32) {
        var buffer = [UInt8]()
        while isRunning {
            guard let head = readHead(fd: fd, buffer: &buffer) else { return }
            guard let request = Self.parseRequest(head) else {
                _ = send(fd, status: 400, contentType: "text/plain", body: LoopbackBody(string: "bad request\n"), head: true, extra: [], close: true)
                return
            }
            lock.lock(); requestCount += 1; let h = handler; lock.unlock()
            guard let handler = h else { return }
            let keepAlive = (request.headers["connection"]?.lowercased() != "close")
            var routed = request
            if !token.isEmpty {
                let p = "/\(token)/"
                if request.path.hasPrefix(p) { routed.path = "/" + request.path.dropFirst(p.count) }
                else { _ = send(fd, status: 404, contentType: "text/plain", body: LoopbackBody(string: "not found\n"), head: request.method != "HEAD", extra: [], close: !keepAlive); if !keepAlive { return }; continue }
            }
            guard request.method == "GET" || request.method == "HEAD" else {
                _ = send(fd, status: 405, contentType: "text/plain", body: LoopbackBody(string: "method not allowed\n"), head: true, extra: [("Allow", "GET, HEAD")], close: !keepAlive)
                if !keepAlive { return }
                continue
            }
            let outcome = runHandler(handler, request: routed, fd: fd)
            switch outcome {
            case .peerClosed: return
            case .failed:
                _ = send(fd, status: 500, contentType: "text/plain", body: LoopbackBody(string: "internal error\n"), head: request.method != "HEAD", extra: [], close: !keepAlive)
                if !keepAlive { return }
            case .response(let r):
                let ok = respond(fd: fd, request: routed, response: r, keepAlive: keepAlive)
                if !ok || !keepAlive { return }
            }
        }
    }

    private enum Outcome { case response(LoopbackResponse), failed, peerClosed }

    private final class Box: @unchecked Sendable { var value: Outcome? }

    /// Runs the async handler and waits; polls the socket so a closed client cancels the handler's task.
    private func runHandler(_ handler: @escaping LoopbackHandler, request: LoopbackRequest, fd: Int32) -> Outcome {
        let semaphore = DispatchSemaphore(value: 0)
        let box = Box()
        let task = Task {
            do { box.value = .response(try await handler(request)) } catch { box.value = .failed }
            semaphore.signal()
        }
        while semaphore.wait(timeout: .now() + .milliseconds(40)) == .timedOut {
            if peerClosed(fd) { task.cancel(); _ = semaphore.wait(timeout: .now() + .seconds(5)); return .peerClosed }
            if !isRunning { task.cancel(); _ = semaphore.wait(timeout: .now() + .seconds(5)); return .peerClosed }
        }
        return box.value ?? .failed
    }

    private func peerClosed(_ fd: Int32) -> Bool {
        var b: UInt8 = 0
        let n = recv(fd, &b, 1, Int32(MSG_PEEK) | Int32(MSG_DONTWAIT))
        if n == 0 { return true }
        if n < 0 { return errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR }
        return false
    }

    private func respond(fd: Int32, request: LoopbackRequest, response: LoopbackResponse, keepAlive: Bool) -> Bool {
        let total = response.body.count
        var status = response.status
        var extra = response.headers + [("Accept-Ranges", "bytes")]
        var from = 0, to = total - 1
        if status == 200 {
            switch ByteRangeHeader.parse(request.headers["range"], length: total) {
            case .none: break
            case .unsatisfiable:
                return send(fd, status: 416, contentType: "text/plain", body: .empty, head: true, extra: extra + [("Content-Range", "bytes */\(total)")], close: !keepAlive)
            case .range(let s, let e):
                status = 206; from = s; to = e
                extra.append(("Content-Range", "bytes \(s)-\(e)/\(total)"))
            }
        }
        let length = status == 206 ? to - from + 1 : total
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\nContent-Type: \(response.contentType)\r\nContent-Length: \(length)\r\n"
        for (k, v) in extra { head += "\(k): \(v)\r\n" }
        head += keepAlive ? "Connection: keep-alive\r\n\r\n" : "Connection: close\r\n\r\n"
        guard writeAll(fd, Array(head.utf8)[...]) else { return false }
        if request.method == "HEAD" || length == 0 { return true }
        // Walk the chunks and write the requested window.
        var offset = 0
        for chunk in response.body.chunks {
            let chunkEnd = offset + chunk.count
            defer { offset = chunkEnd }
            if chunkEnd <= from { continue }
            if offset > to { break }
            let lo = chunk.startIndex + max(0, from - offset)
            let hi = chunk.startIndex + min(chunk.count, to + 1 - offset)
            if hi > lo, !writeAll(fd, chunk[lo..<hi]) { return false }
        }
        return true
    }

    private func send(_ fd: Int32, status: Int, contentType: String, body: LoopbackBody, head: Bool, extra: [(String, String)], close: Bool) -> Bool {
        var s = "HTTP/1.1 \(status) \(Self.reason(status))\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n"
        for (k, v) in extra { s += "\(k): \(v)\r\n" }
        s += close ? "Connection: close\r\n\r\n" : "Connection: keep-alive\r\n\r\n"
        guard writeAll(fd, Array(s.utf8)[...]) else { return false }
        if head { for c in body.chunks { if !writeAll(fd, c) { return false } } }
        return true
    }

    private func writeAll(_ fd: Int32, _ bytes: ArraySlice<UInt8>) -> Bool {
        var sent = 0
        let count = bytes.count
        return bytes.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            while sent < count {
                #if canImport(Glibc)
                let n = Glibc.send(fd, base + sent, count - sent, Int32(MSG_NOSIGNAL))
                #else
                let n = Darwin.send(fd, base + sent, count - sent, 0)
                #endif
                if n < 0 { if errno == EINTR { continue }; return false }
                if n == 0 { return false }
                sent += n
            }
            return true
        }
    }

    /// Reads up to the end of the request head; keeps leftover bytes (pipelining) in `buffer`.
    private func readHead(fd: Int32, buffer: inout [UInt8]) -> String? {
        let terminator: [UInt8] = [13, 10, 13, 10]
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            if let r = buffer.firstRange(of: terminator) {
                let head = String(decoding: buffer[..<r.lowerBound], as: UTF8.self)
                buffer.removeSubrange(..<r.upperBound)
                return head
            }
            if buffer.count > 16 * 1024 { return nil }
            let n = chunk.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { return nil }
            buffer.append(contentsOf: chunk[0..<n])
        }
    }

    static func parseRequest(_ head: String) -> LoopbackRequest? {
        let lines = head.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return nil }
        var headers: [String: String] = [:]
        for l in lines.dropFirst() {
            guard let i = l.firstIndex(of: ":") else { continue }
            headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        var path = String(parts[1])
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        return LoopbackRequest(method: String(parts[0]), path: path, headers: headers)
    }

    static func reason(_ s: Int) -> String {
        switch s {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 416: return "Range Not Satisfiable"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Status"
        }
    }
}
