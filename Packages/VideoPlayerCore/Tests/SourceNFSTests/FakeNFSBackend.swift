import Foundation
import SourceNFS

/// In-memory NFS server for unit tests. Deterministic content: byte at offset k = (k*7+3) % 251.
final class FakeNFSBackend: NFSBackend, @unchecked Sendable {
    struct Node {
        var kind: NFSFileKind
        var size: UInt64 = 0
        var modified: Date? = Date(timeIntervalSince1970: 1_700_000_000)
        var linkTarget: String?
    }

    private let lock = NSLock()
    private var nodes: [String: Node]
    private(set) var mountCalls = 0
    private(set) var unmountCalls = 0
    private(set) var readCalls: [(path: String, offset: UInt64, count: Int)] = []
    private(set) var lastConfiguration: NFSConfiguration?

    /// Next N calls (mount counts too) throw this, then work again.
    var failNext: [NFSBackendError] = []
    /// Largest piece returned per read, to imitate servers with a small rsize.
    var maxBytesPerRead = Int.max
    var mountError: NFSBackendError?

    init(nodes: [String: Node]) { self.nodes = nodes }

    static func standard() -> FakeNFSBackend {
        FakeNFSBackend(nodes: [
            "/": Node(kind: .directory),
            "/Movies": Node(kind: .directory),
            "/Movies/Test Movie (2020).mkv": Node(kind: .file, size: 10_000),
            "/Movies/Test Movie (2020).en.srt": Node(kind: .file, size: 120),
            "/Odd Names": Node(kind: .directory),
            "/Odd Names/Café – 100% [test] #1.mp4": Node(kind: .file, size: 77),
            "/notes.txt": Node(kind: .file, size: 12),
            "/big.mkv": Node(kind: .file, size: 40_000_000),
            "/link-to-movies": Node(kind: .symlink, linkTarget: "/Movies"),
            "/link-to-file": Node(kind: .symlink, linkTarget: "/notes.txt"),
            "/dead-link": Node(kind: .symlink, linkTarget: "/gone"),
            "/pipe": Node(kind: .other)
        ])
    }

    static func byte(at k: UInt64) -> UInt8 { UInt8((k &* 7 &+ 3) % 251) }

    private func takeFailure() -> NFSBackendError? {
        lock.lock(); defer { lock.unlock() }
        return failNext.isEmpty ? nil : failNext.removeFirst()
    }

    func mount(_ configuration: NFSConfiguration) async throws {
        lock.lock(); mountCalls += 1; lastConfiguration = configuration; lock.unlock()
        if let error = mountError { throw error }
        if let failure = takeFailure() { throw failure }
    }

    func unmount() async { lock.lock(); unmountCalls += 1; lock.unlock() }

    private func resolve(_ path: String) -> Node? {
        guard var node = nodes[path] else { return nil }
        var hops = 0
        while node.kind == .symlink, let target = node.linkTarget, hops < 8 {
            guard let next = nodes[target] else { return nil }
            node = next; hops += 1
        }
        return node
    }

    func readDirectory(_ path: String) async throws -> [NFSDirectoryEntry] {
        if let failure = takeFailure() { throw failure }
        guard let node = nodes[path] else { throw NFSBackendError.notFound }
        guard node.kind == .directory else { throw NFSBackendError.notDirectory }
        var result = [
            NFSDirectoryEntry(name: ".", kind: .directory, size: 0),
            NFSDirectoryEntry(name: "..", kind: .directory, size: 0)
        ]
        let prefix = path == "/" ? "/" : path + "/"
        for (key, value) in nodes where key != path && key.hasPrefix(prefix) {
            let rest = key.dropFirst(prefix.count)
            if rest.contains("/") { continue }
            result.append(NFSDirectoryEntry(name: String(rest), kind: value.kind, size: value.size, modified: value.modified))
        }
        return result
    }

    func status(_ path: String) async throws -> NFSFileStatus {
        if let failure = takeFailure() { throw failure }
        guard let node = resolve(path) else { throw NFSBackendError.notFound }
        return NFSFileStatus(kind: node.kind, size: node.size, modified: node.modified)
    }

    func read(_ path: String, offset: UInt64, count: Int) async throws -> Data {
        lock.lock(); readCalls.append((path, offset, count)); lock.unlock()
        if let failure = takeFailure() { throw failure }
        guard let node = resolve(path) else { throw NFSBackendError.notFound }
        if node.kind == .directory { throw NFSBackendError.isDirectory }
        guard offset < node.size else { return Data() }
        let n = min(count, maxBytesPerRead, Int(node.size - offset))
        return Data((0..<n).map { Self.byte(at: offset + UInt64($0)) })
    }
}
