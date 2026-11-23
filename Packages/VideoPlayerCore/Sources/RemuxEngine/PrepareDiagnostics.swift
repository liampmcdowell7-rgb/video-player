import Foundation
import VideoPlayerCore

/// R441: what `prepare()` read and how long each phase took, for the start report of converted playback. One read
/// through a `ByteRangeReader` is one request on a network source, so the read count times the time per read is the cost
/// of a phase. Diagnostics only: nothing here changes what the session does.
public struct PrepareDiagnostics: Equatable, Sendable {
    public struct Phase: Equatable, Sendable {
        public var name: String
        public var seconds: Double
        public var reads: Int
        public var bytes: Int64
    }

    public var phases: [Phase] = []

    public var totalSeconds: Double { phases.reduce(0) { $0 + $1.seconds } }
    public var totalReads: Int { phases.reduce(0) { $0 + $1.reads } }
    public var totalBytes: Int64 { phases.reduce(0) { $0 + $1.bytes } }

    /// One plain line per phase and one for the total: "Prepare, index load: 0.3 s, 6 reads, 410 KB".
    public var lines: [String] {
        guard !phases.isEmpty else { return [] }
        var out = phases.map { "Prepare, \($0.name): \(Self.seconds($0.seconds)), \(Self.reads($0.reads)), \(Self.bytes($0.bytes))" }
        out.append("Prepare, total: \(Self.seconds(totalSeconds)), \(Self.reads(totalReads)), \(Self.bytes(totalBytes))")
        return out
    }

    static func seconds(_ s: Double) -> String {
        guard s.isFinite else { return "? s" }
        return s < 10 ? String(format: "%.2f s", s) : "\(Int(s.rounded())) s"
    }

    static func reads(_ n: Int) -> String { n == 1 ? "1 read" : "\(n) reads" }

    static func bytes(_ n: Int64) -> String {
        if n < 10_000 { return "\(n) B" }
        if n < 10_000_000 { return "\(n / 1000) KB" }
        return "\(n / 1_000_000) MB"
    }
}

/// Counts the reads and bytes that pass through a reader (thread safe).
public final class ReadTally: ByteRangeReader, @unchecked Sendable {
    private let base: any ByteRangeReader
    private let lock = NSLock()
    private var _reads = 0
    private var _bytes: Int64 = 0

    public init(_ base: any ByteRangeReader) { self.base = base }
    public var size: Int64 { base.size }

    public var snapshot: (reads: Int, bytes: Int64) { lock.lock(); defer { lock.unlock() }; return (_reads, _bytes) }

    public func read(_ range: ByteRange) async throws -> Data {
        // Counted when asked, so a read that fails or times out is in the count too.
        lock.withLock { _reads += 1 }
        let data = try await base.read(range)
        lock.withLock { _bytes += Int64(data.count) }
        return data
    }
}

/// Records the phases of one `prepare()`.
struct PrepareRecorder {
    private let tally: ReadTally
    private var mark: (time: Double, reads: Int, bytes: Int64)
    private(set) var diagnostics = PrepareDiagnostics()

    init(tally: ReadTally) {
        self.tally = tally
        let s = tally.snapshot
        mark = (ProcessInfo.processInfo.systemUptime, s.reads, s.bytes)
    }

    /// Closes the phase that ran since the last call.
    mutating func end(_ name: String) {
        let s = tally.snapshot
        let now = ProcessInfo.processInfo.systemUptime
        diagnostics.phases.append(.init(name: name, seconds: max(0, now - mark.time), reads: s.reads - mark.reads, bytes: s.bytes - mark.bytes))
        mark = (now, s.reads, s.bytes)
    }
}
