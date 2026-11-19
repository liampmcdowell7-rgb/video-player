import Foundation
import VideoPlayerCore
import AppLogic

/// Turns the artwork key a card carries ("item-42", "series-7", "remote:/abc.jpg") into something to draw: a file read from the
/// source and kept in the purgeable cache, a web address the system image loader fetches, or nothing (the placeholder symbol).
/// Order: a picture next to the video first, then the matched online poster (docs/ARTWORK_DISCOVER.md).
protocol ArtworkResolving: Sendable {
    func resolve(key: String) async -> ArtworkResult
    /// Title-logo pictures to try, strongest source first (#15 Part 9).
    func logoCandidates(key: String, userLanguage: String?) async -> [LogoCandidate]
}

struct EngineArtworkResolver: ArtworkResolving {
    let engine: ArtworkEngine
    func resolve(key: String) async -> ArtworkResult { await engine.resolve(key: key) }
    func logoCandidates(key: String, userLanguage: String?) async -> [LogoCandidate] {
        await engine.logoCandidates(key: key, userLanguage: userLanguage)
    }
}

/// Reads a picture file from a source: the first `maxBytes` bytes only.
struct SourceSidecarReader: SidecarReading {
    /// Looks the source up on the main actor (definitions live there).
    let sourceFor: @Sendable (String) async -> (any MediaSource)?

    func read(sourceID: String, path: String, maxBytes: Int) async throws -> Data {
        guard let source = await sourceFor(sourceID) else { throw SourceError.notFound }
        return try await source.read(path, range: ByteRange(offset: 0, length: Int64(maxBytes)))
    }
}

/// Where cached pictures live. Caches only: the system may clear them at any time and they are fetched again (STORAGE_MODEL.md).
enum ArtworkFolders {
    static var caches: URL { (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory) }
    /// Pictures read from sources (size-limited by `ArtworkDiskCache`, least recently used removed first).
    static var sidecars: URL { caches.appendingPathComponent("artwork", isDirectory: true) }
    /// Online metadata answers (small JSON files with their own expiry).
    static var metadata: URL { caches.appendingPathComponent("online-metadata", isDirectory: true) }
    /// The system image loader's own disk cache for online posters (size-capped below).
    static var remote: URL { caches.appendingPathComponent("remote-artwork", isDirectory: true) }

    /// A URL session whose cache is capped and lives in Caches. Handed to `AsyncImage` through `asyncImageURLSession`.
    /// PROVISIONAL numbers (OPEN_QUESTIONS): 20 MB memory, 100 MB disk.
    static func makeImageSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 20_000_000, diskCapacity: 100_000_000, directory: remote)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }
}
