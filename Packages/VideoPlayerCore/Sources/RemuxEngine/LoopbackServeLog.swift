import Foundation

/// R390: what the loopback server was asked for and how it answered, for the start report of converted playback. A
/// player that never becomes ready has either not asked for the stream's first resources, or asked and got no answer (a
/// slow source read, a slow audio conversion) or a failure. Only the first request for each resource is kept, and only
/// the ones that matter for the start (playlists, init segments and the first segments), so the log stays small.
public final class LoopbackServeLog: @unchecked Sendable {
    public struct Entry: Equatable, Sendable {
        public var name: String
        /// Seconds since the log started (the server started).
        public var askedAt: Double
        /// Seconds the answer took; nil while there is none.
        public var tookSeconds: Double?
        public var status: Int?
        public var error: String?
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let clock: @Sendable () -> Double
    private let origin: Double
    /// Segments with an index under this count are logged (the start needs the first ones; a resume seek asks for one
    /// further on, which is logged too as the first segment asked for).
    public static let firstSegments = 3
    public static let capacity = 24

    public init(clock: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
        self.origin = clock()
    }

    /// True for a resource worth logging: a playlist, an init segment, or one of the first segments of a track, or the
    /// first segment of any index when no segment of that track was logged yet (a resume start).
    func wanted(_ name: String) -> Bool {
        if name.hasSuffix(".m3u8") || name.hasPrefix("init_") { return true }
        guard name.hasPrefix("seg_video_") || name.hasPrefix("seg_audio_") else { return false }
        if let k = Self.segmentIndex(name), k < Self.firstSegments { return true }
        let track = Self.trackPrefix(name)
        return !entries.contains { $0.name.hasPrefix(track) }
    }

    /// Records a request; returns a token for `answered`/`failed`, nil when it is not logged.
    public func asked(_ path: String) -> Int? {
        let name = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let now = clock() - origin
        return lock.withLock {
            guard entries.count < Self.capacity, !entries.contains(where: { $0.name == name }), wanted(name) else { return nil }
            entries.append(Entry(name: name, askedAt: now))
            return entries.count - 1
        }
    }

    public func answered(_ token: Int?, status: Int) {
        finish(token) { $0.status = status }
    }

    public func failed(_ token: Int?, error: String) {
        let text = Self.redact(error)
        finish(token) { $0.error = text }
    }

    /// R441: the handler threw and the server answered with this status (500); the entry keeps the error text next to it.
    public func failed(_ token: Int?, status: Int, error: String) {
        let text = Self.redact(error)
        finish(token) { $0.status = status; $0.error = text }
    }

    /// An error text for a report: tokens and keys in query strings and headers removed, one line, at most 300 characters.
    public static func redact(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        let pattern = "(?i)((?:x-plex-token|token|api_key|apikey|access_token|authorization)\\s*[=:]\\s*)(?:bearer\\s+)?[^&\\s\"',;)]+"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1<token>")
        }
        return out.count > 300 ? String(out.prefix(299)) + "…" : out
    }

    private func finish(_ token: Int?, _ change: (inout Entry) -> Void) {
        guard let token else { return }
        let now = clock() - origin
        lock.withLock {
            guard entries.indices.contains(token) else { return }
            entries[token].tookSeconds = max(0, now - entries[token].askedAt)
            change(&entries[token])
        }
    }

    public var all: [Entry] { lock.withLock { entries } }

    /// R472: the first resource the server answered with an error status (the handler threw), as "seg_video_1.m4s: <text>",
    /// the text redacted by `redact`; nil when every logged answer was a success or no answer came. For the Last Event row
    /// of Last Playback Problem, so one photo shows which resource failed and why.
    public func firstFailure() -> String? {
        guard let e = all.first(where: { ($0.status ?? 0) >= 500 && $0.error != nil }), let error = e.error else { return nil }
        return Self.redact("\(e.name): \(error)")
    }

    /// One plain line per entry: "seg_video_0.m4s: asked at 3.1 s, answered 200 after 0.4 s" or "..., no answer yet".
    /// `serverStartedAt` moves the times onto the caller's clock (the seconds since the start was asked for).
    public func lines(serverStartedAt offset: Double = 0) -> [String] {
        all.map { e in
            var line = "\(e.name): asked at \(Self.seconds(e.askedAt + offset))"
            if let error = e.error, let status = e.status {
                line += ", answered \(status) after \(Self.seconds(e.tookSeconds ?? 0)): \(error)"
            } else if let error = e.error {
                line += ", failed after \(Self.seconds(e.tookSeconds ?? 0)): \(error)"
            } else if let status = e.status {
                line += ", answered \(status) after \(Self.seconds(e.tookSeconds ?? 0))"
            } else {
                line += ", no answer yet"
            }
            return line
        }
    }

    /// The resources of a start that were never asked for (the player stopped before them), for the report.
    public func missing() -> [String] {
        let names = all.map(\.name)
        var out: [String] = []
        for wanted in ["master.m3u8", "video.m3u8", "init_video.mp4", "seg_video_"] where !names.contains(where: { $0.hasPrefix(wanted) }) {
            out.append(wanted == "seg_video_" ? "no video segment" : wanted)
        }
        return out
    }

    static func segmentIndex(_ name: String) -> Int? {
        guard let dot = name.lastIndex(of: "."), let underscore = name[..<dot].lastIndex(of: "_") else { return nil }
        return Int(name[name.index(after: underscore)..<dot])
    }

    static func trackPrefix(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), let underscore = name[..<dot].lastIndex(of: "_") else { return name }
        return String(name[...underscore])
    }

    static func seconds(_ s: Double) -> String {
        guard s.isFinite else { return "?" }
        return s < 10 ? String(format: "%.1f s", s) : "\(Int(s.rounded())) s"
    }
}
