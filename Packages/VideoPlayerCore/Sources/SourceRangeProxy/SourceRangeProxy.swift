import Foundation
import VideoPlayerCore
import RemuxEngine

// Serves one file of a source that has no URL (SMB, NFS, SFTP, FTP) as a plain http://127.0.0.1 resource with byte ranges, so the
// system player can direct-play an MP4 from it. It reuses the remux engine's loopback HTTP server (RemuxEngine/Loopback.swift) and
// its `ByteRangeReader`; it does not change either.
//
// How it answers (PROVISIONAL, alternative in docs/SOURCES_WIRING.md): the loopback server cuts a response body to the asked
// range itself, which would need the whole file in memory. So this handler answers every request with a 206 for a bounded
// window (at most `maxWindow` bytes from the start the player asked for) and its own Content-Range. A player may receive fewer
// bytes than it asked for and asks again; that is allowed for a ranged GET. A request without a Range header gets the first window
// (a 200 when the whole file fits in one window). HEAD is answered like a GET of the first byte: the loopback server computes
// Content-Length from the body it is given, so it cannot announce the real length for a HEAD; the player's usual first
// request is a ranged GET, whose Content-Range carries the real total. NOT verified against AVPlayer (device checklist).

public enum RangeProxyPlan: Equatable, Sendable {
    /// Send `start...end` (inclusive). `partial` is false only when that is the whole file.
    case window(start: Int64, end: Int64, partial: Bool)
    case unsatisfiable
    case empty

    public static func make(rangeHeader: String?, method: String, size: Int64, maxWindow: Int64) -> RangeProxyPlan {
        if size <= 0 { return .empty }
        let window = max(1, maxWindow)
        var parsed = ByteRangeHeader.parse(rangeHeader, length: Int(clamping: size))
        if method == "HEAD" { if case .none = parsed { parsed = .range(start: 0, end: 0) } else if case .range(let s, _) = parsed { parsed = .range(start: s, end: s) } }
        switch parsed {
        case .unsatisfiable: return .unsatisfiable
        case .none:
            let end = min(size, window) - 1
            return .window(start: 0, end: end, partial: end + 1 < size)
        case .range(let start, let end):
            let cappedEnd = min(Int64(end), Int64(start) + window - 1)
            return .window(start: Int64(start), end: cappedEnd, partial: !(start == 0 && cappedEnd == size - 1))
        }
    }
}

public final class SourceRangeProxy: @unchecked Sendable {
    public static let defaultWindow: Int64 = 8 * 1024 * 1024
    private let server: LoopbackServer
    private let maxWindow: Int64

    public init(server: LoopbackServer = POSIXLoopbackServer(), maxWindow: Int64 = SourceRangeProxy.defaultWindow) {
        self.server = server
        self.maxWindow = maxWindow
    }

    /// Starts serving `reader` and returns the address to give the player. The file name's extension is kept in the address.
    public func start(reader: any ByteRangeReader, fileName: String) throws -> URL {
        let size = reader.size
        let type = Self.contentType(forFileName: fileName)
        let window = maxWindow
        let base = try server.start { request in
            let plan = RangeProxyPlan.make(rangeHeader: request.headers["range"], method: request.method, size: size, maxWindow: window)
            switch plan {
            case .empty:
                return LoopbackResponse(status: 200, contentType: type, body: .empty)
            case .unsatisfiable:
                return LoopbackResponse(status: 416, contentType: type, body: .empty, headers: [("Content-Range", "bytes */\(size)")])
            case .window(let start, let end, let partial):
                let data = try await reader.read(ByteRange(offset: start, length: end - start + 1))
                let body = LoopbackBody([UInt8](data))
                if !partial { return LoopbackResponse(status: 200, contentType: type, body: body) }
                let last = start + Int64(data.count) - 1
                return LoopbackResponse(status: 206, contentType: type, body: body, headers: [("Content-Range", "bytes \(start)-\(last)/\(size)")])
            }
        }
        let safeName = fileName.isEmpty ? "video" : fileName
        return base.appendingPathComponent(safeName)
    }

    public func stop() { server.stop() }

    public static func contentType(forFileName name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mkv": return "video/x-matroska"
        case "ts", "m2ts": return "video/mp2t"
        default: return "application/octet-stream"
        }
    }
}
