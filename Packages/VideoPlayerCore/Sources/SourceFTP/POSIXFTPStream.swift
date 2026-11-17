#if canImport(Glibc) || canImport(Musl)
import Foundation
#if canImport(Glibc)
import Glibc
#else
import Musl
#endif

// Free-function wrappers: inside the stream class the names send/close/connect would resolve to its own methods.
private func sysConnect(_ fd: Int32, _ addr: UnsafePointer<sockaddr>?, _ len: socklen_t) -> Int32 { connect(fd, addr, len) }
private func sysClose(_ fd: Int32) { _ = close(fd) }
private func sysShutdown(_ fd: Int32) { _ = shutdown(fd, 2) }   // 2 == SHUT_RDWR
private func sysRecv(_ fd: Int32, _ buf: UnsafeMutableRawPointer, _ n: Int) -> Int { recv(fd, buf, n, 0) }
private func sysSend(_ fd: Int32, _ buf: UnsafeRawPointer, _ n: Int) -> Int { send(fd, buf, n, Int32(MSG_NOSIGNAL)) }

/// Plain-TCP transport for Linux (tests, WSL, servers). No TLS: FTPS on Apple platforms uses
/// Network.framework; asking this transport for TLS throws `.tlsUnavailable`.
public struct POSIXFTPConnector: FTPConnector {
    public var timeout: TimeInterval
    public init(timeout: TimeInterval = 15) { self.timeout = timeout }

    public func connect(host: String, port: Int, tls: Bool, allowUpgrade: Bool) async throws -> FTPStream {
        if tls || allowUpgrade { throw FTPStreamError.tlsUnavailable("The POSIX transport has no TLS. Use Network.framework on Apple platforms.") }
        let seconds = timeout
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<FTPStream, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do { cont.resume(returning: try POSIXFTPStream(host: host, port: port, timeout: seconds)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }
}

final class POSIXFTPStream: FTPStream, @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32 = -1

    init(host: String, port: Int, timeout: TimeInterval) throws {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &result) == 0, let first = result else {
            throw FTPStreamError.failed("Cannot resolve \(host)")
        }
        defer { freeaddrinfo(result) }
        var lastError = "no address"
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let ai = cursor {
            let s = socket(ai.pointee.ai_family, ai.pointee.ai_socktype, ai.pointee.ai_protocol)
            if s >= 0 {
                var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
                let size = socklen_t(MemoryLayout<timeval>.size)
                setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, size)
                setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, size)
                if sysConnect(s, ai.pointee.ai_addr, ai.pointee.ai_addrlen) == 0 { fd = s; return }
                lastError = String(cString: strerror(errno))
                sysClose(s)
            }
            cursor = ai.pointee.ai_next
        }
        throw FTPStreamError.failed("Cannot connect to \(host):\(port): \(lastError)")
    }

    private func currentFD() -> Int32 { lock.lock(); defer { lock.unlock() }; return fd }

    func send(_ data: Data) async throws {
        let s = currentFD()
        guard s >= 0 else { throw FTPStreamError.closed }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var sent = 0
                let total = data.count
                var failure: Error?
                data.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    while sent < total {
                        let n = sysSend(s, base + sent, total - sent)
                        if n > 0 { sent += n; continue }
                        if n < 0 && errno == EINTR { continue }
                        failure = (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) ? FTPStreamError.timedOut : FTPStreamError.closed
                        return
                    }
                }
                if let failure { cont.resume(throwing: failure) } else { cont.resume() }
            }
        }
    }

    func receive(maxLength: Int) async throws -> Data {
        let s = currentFD()
        guard s >= 0 else { throw FTPStreamError.closed }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer = [UInt8](repeating: 0, count: max(1, maxLength))
                while true {
                    let n = buffer.withUnsafeMutableBytes { sysRecv(s, $0.baseAddress!, $0.count) }
                    if n > 0 { cont.resume(returning: Data(buffer[0..<n])); return }
                    if n == 0 { cont.resume(returning: Data()); return }
                    if errno == EINTR { continue }
                    if errno == EAGAIN || errno == EWOULDBLOCK { cont.resume(throwing: FTPStreamError.timedOut); return }
                    cont.resume(throwing: FTPStreamError.closed)
                    return
                }
            }
        }
    }

    func startTLS(serverName: String) async throws {
        throw FTPStreamError.tlsUnavailable("The POSIX transport has no TLS")
    }

    private func takeFD() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        let s = fd
        fd = -1
        return s
    }

    func close() async {
        let s = takeFD()
        if s >= 0 { sysShutdown(s); sysClose(s) }
    }

    deinit {
        if fd >= 0 { sysShutdown(fd); sysClose(fd) }
    }
}
#endif
