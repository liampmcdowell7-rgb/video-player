import Foundation

/// R471 (90), PROVISIONAL (owner 25 Nov 2026 round 10, item 1): the last requests the player sent to the loopback server
/// during one converted play, for Settings > Playback > Loopback Requests, so a photo of that page shows how far the audio
/// requests run behind the video ones (R471 (82) assumes a few segments at most; UNVERIFIED without a device).
///
/// In memory only, never saved. Resource names only ("seg_video_12.m4s"): no title, no address, no query, no token. The
/// loopback handler records each request (one lock and one array write); nothing runs while no play runs.
public final class LoopbackRequestTrail: @unchecked Sendable {
    public struct Entry: Equatable, Sendable {
        public var name: String
        public var status: Int?
        /// Milliseconds the answer took; nil while there is none (or the player closed the request).
        public var tookMs: Int?
        /// Milliseconds since the previous request was asked for; nil for the first one.
        public var sincePreviousMs: Int?
    }

    public static let capacity = 20
    /// The name shown for a path that is not a plain resource name.
    public static let otherName = "(other)"

    private let lock = NSLock()
    /// Oldest first; `serial` counts every request so a token survives older entries being dropped.
    private var entries: [(serial: Int, askedAt: Double, entry: Entry)] = []
    private var serial = 0
    private var lastAskedAt: Double?
    private let clock: @Sendable () -> Double

    public init(clock: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
    }

    /// Records a request; the token goes to `answered`.
    public func asked(_ path: String) -> Int {
        let name = Self.resourceName(path)
        let now = clock()
        return lock.withLock {
            serial += 1
            let since = lastAskedAt.map { Self.ms(now - $0) }
            lastAskedAt = now
            entries.append((serial, now, Entry(name: name, status: nil, tookMs: nil, sincePreviousMs: since)))
            if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
            return serial
        }
    }

    public func answered(_ token: Int, status: Int) {
        let now = clock()
        lock.withLock {
            guard let i = entries.lastIndex(where: { $0.serial == token }) else { return }
            entries[i].entry.status = status
            entries[i].entry.tookMs = Self.ms(now - entries[i].askedAt)
        }
    }

    /// Newest first, at most `capacity`.
    public var newestFirst: [Entry] { lock.withLock { entries.reversed().map(\.entry) } }

    /// One row per request, newest first: the resource name, then "200 · 12 ms · +250 ms" (status or "no answer", the
    /// time to answer, the time since the request before it).
    public var rows: [(label: String, value: String)] {
        newestFirst.map { e in
            var parts: [String] = [e.status.map(String.init) ?? "no answer"]
            if let took = e.tookMs { parts.append("\(took) ms") }
            if let since = e.sincePreviousMs { parts.append("+\(since) ms") }
            return (e.name, parts.joined(separator: " · "))
        }
    }

    /// The last path component without a query or fragment, kept only when it is a plain resource name (letters, digits,
    /// "_", "-", ".", at most 64 characters); anything else is `otherName`, so no address or token can reach the page.
    public static func resourceName(_ path: String) -> String {
        var p = Substring(path)
        if let cut = p.firstIndex(where: { $0 == "?" || $0 == "#" }) { p = p[..<cut] }
        let last = p.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? ""
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.")
        guard !last.isEmpty, last.count <= 64, last.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return otherName }
        return last
    }

    static func ms(_ seconds: Double) -> Int {
        guard seconds.isFinite else { return 0 }
        return max(0, Int((seconds * 1000).rounded()))
    }
}
