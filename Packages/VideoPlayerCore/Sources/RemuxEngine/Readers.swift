import Foundation
import VideoPlayerCore

/// Random access to the bytes of one file. The engine only ever reads through this, so tests use memory or a
/// throttled fake and the app uses `MediaSourceReader` over any source type.
public protocol ByteRangeReader: Sendable {
    /// Total size of the file in bytes.
    var size: Int64 { get }
    /// Reads `range`. Returns fewer bytes only at the end of the file.
    func read(_ range: ByteRange) async throws -> Data
}

/// Adapter: one file of a `MediaSource` as a `ByteRangeReader`.
public struct MediaSourceReader: ByteRangeReader {
    public let source: any MediaSource
    public let path: String
    public let size: Int64

    public init(source: any MediaSource, path: String, size: Int64) {
        self.source = source; self.path = path; self.size = size
    }

    /// Looks the size up with `info` first.
    public static func open(source: any MediaSource, path: String) async throws -> MediaSourceReader {
        let entry = try await source.info(path)
        guard let size = entry.size else { throw RemuxError.io("source did not report a size for \(path)") }
        return MediaSourceReader(source: source, path: path, size: size)
    }

    public func read(_ range: ByteRange) async throws -> Data {
        try await source.read(path, range: range)
    }
}

/// A file held in memory (tests, and small files).
public final class DataReader: ByteRangeReader, @unchecked Sendable {
    private let data: Data
    private let lock = NSLock()
    private var _reads = 0
    private var _bytes: Int64 = 0

    public init(_ data: Data) { self.data = data }
    public var size: Int64 { Int64(data.count) }
    /// Number of `read` calls so far and total bytes returned (for tests of read patterns).
    public var readCount: Int { lock.lock(); defer { lock.unlock() }; return _reads }
    public var bytesRead: Int64 { lock.lock(); defer { lock.unlock() }; return _bytes }

    private func record(_ n: Int) {
        lock.lock(); _reads += 1; _bytes += Int64(n); lock.unlock()
    }

    public func read(_ range: ByteRange) async throws -> Data {
        if Task.isCancelled { throw RemuxError.cancelled }
        let start = Int(min(range.offset, Int64(data.count)))
        let end = Int(min(range.offset + range.length, Int64(data.count)))
        record(end - start)
        return data.subdata(in: (data.startIndex + start)..<(data.startIndex + end))
    }
}

/// A read-through cache of aligned blocks, so walking the small headers of a file costs few real reads.
/// Used for the header walk and cluster scans. Large window reads bypass it (`readUncached`).
public actor BlockCachedReader: ByteRangeReader {
    private let base: any ByteRangeReader
    private let blockSize: Int64
    private let maxBlocks: Int
    private var blocks: [Int64: Data] = [:]
    private var order: [Int64] = []
    public nonisolated let size: Int64

    public init(_ base: any ByteRangeReader, blockSize: Int = 128 * 1024, maxBlocks: Int = 16) {
        self.base = base; self.blockSize = Int64(blockSize); self.maxBlocks = maxBlocks; self.size = base.size
    }

    public func read(_ range: ByteRange) async throws -> Data {
        if range.length == 0 || range.offset >= size { return Data() }
        // Large reads are not worth caching and would evict everything.
        if range.length > blockSize * 4 { return try await base.read(range) }
        let end = min(range.offset + range.length, size)
        var out = Data()
        var pos = range.offset
        while pos < end {
            let idx = pos / blockSize
            let block = try await block(idx)
            let blockStart = idx * blockSize
            let from = Int(pos - blockStart)
            let to = Int(min(end - blockStart, Int64(block.count)))
            if to <= from { break }
            out.append(block.subdata(in: (block.startIndex + from)..<(block.startIndex + to)))
            pos = blockStart + Int64(to)
        }
        return out
    }

    private func block(_ idx: Int64) async throws -> Data {
        if let b = blocks[idx] { return b }
        let b = try await base.read(ByteRange(offset: idx * blockSize, length: blockSize))
        blocks[idx] = b
        order.append(idx)
        if order.count > maxBlocks { blocks[order.removeFirst()] = nil }
        return b
    }
}
