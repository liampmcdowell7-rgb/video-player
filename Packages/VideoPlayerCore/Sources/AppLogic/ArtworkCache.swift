import Foundation

/// Where artwork that has no web address (a picture sitting next to a video on a file server) is kept after it was read.
/// docs/STORAGE_MODEL.md: artwork is a REBUILDABLE CACHE, lives in Caches only, and never takes the whole cache space.
/// One file per key, named by a hash of the key; least recently used files go first when the folder passes `maxBytes`.
/// Pictures that do have a web address are NOT stored here (D-DS5: the system image loader and a size-capped URL cache do that).
public final class ArtworkDiskCache: @unchecked Sendable {
    public enum CacheError: Error, Equatable, Sendable { case tooLarge, writeFailed }

    public let directory: URL
    public let maxBytes: Int
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    /// PROVISIONAL size: 150 MB (about 1,500 posters at 100 KB). Apple asks apps not to use the whole cache space and gives no number.
    public static let defaultMaxBytes = 150_000_000

    public init(directory: URL, maxBytes: Int = ArtworkDiskCache.defaultMaxBytes, fileManager: FileManager = .default, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.maxBytes = max(1, maxBytes)
        self.fileManager = fileManager
        self.now = now
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// FNV-1a, 64 bit, as 16 hex digits. A file name, not a security feature.
    public static func name(forKey key: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in key.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        let hex = String(h, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex + ".img"
    }

    private func file(forKey key: String) -> URL { directory.appendingPathComponent(Self.name(forKey: key)) }

    /// The stored file for the key, marked as just used. nil when absent (or empty).
    public func url(forKey key: String) -> URL? {
        lock.withLock {
            let url = file(forKey: key)
            guard let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber, size.intValue > 0 else { return nil }
            try? fileManager.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
            return url
        }
    }

    /// Writes the bytes, then removes the least recently used files until the folder fits. A single picture larger than the whole
    /// cache is refused.
    @discardableResult
    public func store(_ data: Data, key: String) throws -> URL {
        guard data.count <= maxBytes else { throw CacheError.tooLarge }
        return try lock.withLock {
            let url = file(forKey: key)
            do { try data.write(to: url, options: .atomic) } catch { throw CacheError.writeFailed }
            try? fileManager.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
            trimLocked(keeping: url)
            return url
        }
    }

    public var totalBytes: Int { lock.withLock { entriesLocked().reduce(0) { $0 + $1.size } } }
    public var fileCount: Int { lock.withLock { entriesLocked().count } }

    public func trim() { lock.withLock { trimLocked(keeping: nil) } }

    public func removeAll() {
        lock.withLock { for e in entriesLocked() { try? fileManager.removeItem(at: e.url) } }
    }

    private struct Entry { var url: URL; var size: Int; var used: Date }

    private func entriesLocked() -> [Entry] {
        let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "img" }.compactMap { url in
            guard let attrs = try? fileManager.attributesOfItem(atPath: url.path), let size = attrs[.size] as? NSNumber else { return nil }
            return Entry(url: url, size: size.intValue, used: (attrs[.modificationDate] as? Date) ?? .distantPast)
        }
    }

    private func trimLocked(keeping keep: URL?) {
        var entries = entriesLocked()
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }
        entries.sort { $0.used != $1.used ? $0.used < $1.used : $0.url.lastPathComponent < $1.url.lastPathComponent }
        for e in entries where total > maxBytes {
            if let keep, e.url.lastPathComponent == keep.lastPathComponent { continue }
            if (try? fileManager.removeItem(at: e.url)) != nil { total -= e.size }
        }
    }
}
