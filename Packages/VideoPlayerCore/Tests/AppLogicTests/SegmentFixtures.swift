import Foundation
import VideoPlayerCore

// FIXTURE: hand-built bytes shaped like the start of a Matroska file (EBML header, Segment, Info, Chapters, one Cluster). Written from
// the Matroska specification for these tests, not recorded from any muxer. Real files from real muxers are not covered by anything here.

enum FixtureMKV {
    struct Chapter {
        var title: String
        var start: Double
        var end: Double? = nil
        var language: String = "eng"
        var hidden = false
        var enabled = true
        var extraTitles: [(String, String)] = []
    }

    struct Edition {
        var uid: UInt64
        var isDefault = false
        var hidden = false
        var chapters: [Chapter]
    }

    // MARK: EBML primitives

    static func idBytes(_ id: UInt32) -> [UInt8] {
        var out: [UInt8] = []
        var started = false
        for shift in stride(from: 24, through: 0, by: -8) {
            let byte = UInt8((id >> UInt32(shift)) & 0xFF)
            if byte != 0 || started { out.append(byte); started = true }
        }
        return out
    }

    static func sizeBytes(_ n: Int) -> [UInt8] {
        // Always 4 bytes: 0x10 marker bit in the first byte, value in the remaining 28 bits.
        [UInt8(0x10 | ((n >> 24) & 0x0F)), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
    }

    static func element(_ id: UInt32, _ body: [UInt8]) -> [UInt8] { idBytes(id) + sizeBytes(body.count) + body }

    static func uint(_ id: UInt32, _ value: UInt64) -> [UInt8] {
        var bytes: [UInt8] = []
        var x = value
        repeat { bytes.insert(UInt8(x & 0xFF), at: 0); x >>= 8 } while x > 0
        return element(id, bytes)
    }

    static func string(_ id: UInt32, _ s: String) -> [UInt8] { element(id, Array(s.utf8)) }

    static func float64(_ id: UInt32, _ v: Double) -> [UInt8] {
        let bits = v.bitPattern
        return element(id, (0..<8).map { UInt8((bits >> UInt64(56 - 8 * $0)) & 0xFF) })
    }

    // MARK: File

    static func nanos(_ seconds: Double) -> UInt64 { UInt64((seconds * 1e9).rounded()) }

    static func atom(_ c: Chapter, uid: UInt64) -> [UInt8] {
        var body: [UInt8] = uint(0x73C4, uid) + uint(0x91, nanos(c.start))
        if let end = c.end { body += uint(0x92, nanos(end)) }
        if c.hidden { body += uint(0x98, 1) }
        if !c.enabled { body += uint(0x4598, 0) }
        body += element(0x80, string(0x85, c.title) + string(0x437C, c.language))
        for (lang, text) in c.extraTitles { body += element(0x80, string(0x85, text) + string(0x437C, lang)) }
        return element(0xB6, body)
    }

    /// A Matroska file of `duration` seconds with the given chapter editions. No Tracks and no SeekHead; the reader copes (it only notes it).
    static func build(duration: Double, editions: [Edition]) -> Data {
        let info = element(0x1549A966, uint(0x2AD7B1, 1_000_000) + float64(0x4489, duration * 1000) + string(0x7BA9, "Fixture Title"))
        var chapters: [UInt8] = []
        var uid: UInt64 = 100
        for e in editions {
            var body: [UInt8] = uint(0x45BC, e.uid)
            if e.hidden { body += uint(0x45BD, 1) }
            if e.isDefault { body += uint(0x45DB, 1) }
            for c in e.chapters { uid += 1; body += atom(c, uid: uid) }
            chapters += element(0x45B9, body)
        }
        let chaptersElement = editions.isEmpty ? [] : element(0x1043A770, chapters)
        let cluster = element(0x1F43B675, uint(0xE7, 0) + element(0xA3, [0x81, 0x00, 0x00, 0x80] + [UInt8](repeating: 0x55, count: 200)))
        let header = element(0x1A45DFA3, uint(0x4286, 1) + uint(0x42F7, 1) + uint(0x42F2, 4) + uint(0x42F3, 8) + string(0x4282, "matroska") + uint(0x4287, 4) + uint(0x4285, 2))
        let segmentBody = info + chaptersElement + cluster
        // Segment with an 8-byte size field.
        var size: [UInt8] = [0x01]
        for shift in stride(from: 48, through: 0, by: -8) { size.append(UInt8((segmentBody.count >> shift) & 0xFF)) }
        return Data(header + idBytes(0x18538067) + size + segmentBody)
    }

    /// The usual episode: a 90 s intro, the story, the credits from 2400 s to the end of a 2500 s file.
    static func episode(duration: Double = 2500, extra: [Chapter] = []) -> Data {
        build(duration: duration, editions: [Edition(uid: 1, isDefault: true, chapters: [
            Chapter(title: "Intro", start: 0, end: 90),
            Chapter(title: "Chapter 02", start: 90),
            Chapter(title: "Credits", start: 2400),
        ] + extra)])
    }
}

/// A source with a few files in memory. Switches make it fail, stall or lie, to test what `SegmentCollector` does then.
final class SegmentFixtureSource: MediaSource, @unchecked Sendable {
    let kind: SourceKind = .webdav
    let capabilities = SourceCapabilities(authMethods: [.none], byteRanges: true, changeSignals: [.size])
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var _readError: Error?
    private var _listError: Error?
    private var _stallNanos: UInt64 = 0
    private var _reads: [String] = []

    var readError: Error? {
        get { lock.withLock { _readError } }
        set { lock.withLock { _readError = newValue } }
    }
    var listError: Error? {
        get { lock.withLock { _listError } }
        set { lock.withLock { _listError = newValue } }
    }
    /// Every read waits this long and ignores cancellation (a source that hangs).
    var stallNanos: UInt64 {
        get { lock.withLock { _stallNanos } }
        set { lock.withLock { _stallNanos = newValue } }
    }
    var reads: [String] { lock.withLock { _reads } }

    func put(_ path: String, _ data: Data) { lock.withLock { files[path] = data } }
    func put(_ path: String, text: String) { put(path, Data(text.utf8)) }

    func authenticate() async throws {}
    func info(_ path: String) async throws -> SourceEntry { throw SourceError.notFound }
    func playbackAccess(for path: String) async throws -> PlaybackAccess { .byteReader }

    func list(_ path: String) async throws -> [SourceEntry] {
        if let e = listError { throw e }
        return lock.withLock {
            files.filter { Self.parent($0.key) == path }.map { SourceEntry(path: $0.key, name: Self.name($0.key), isDirectory: false, size: Int64($0.value.count)) }
                .sorted { $0.name < $1.name }
        }
    }

    func read(_ path: String, range: ByteRange) async throws -> Data {
        let stall = stallNanos
        if stall > 0 { _ = try? await Task.sleep(nanoseconds: stall) }
        lock.withLock { _reads.append(path) }
        if let e = readError { throw e }
        guard let data = lock.withLock({ files[path] }) else { throw SourceError.notFound }
        guard range.offset < Int64(data.count) else { throw SourceError.rangeNotSatisfiable }
        let end = min(Int64(data.count), range.offset + range.length)
        return Data(data[Int(range.offset)..<Int(end)])
    }

    static func parent(_ path: String) -> String {
        let parts = path.split(separator: "/").dropLast()
        return parts.isEmpty ? "/" : "/" + parts.joined(separator: "/")
    }
    static func name(_ path: String) -> String { String(path.split(separator: "/").last ?? "") }
}
