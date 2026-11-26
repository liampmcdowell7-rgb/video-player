import Foundation
import UserData
import VideoPlayerCore

/// R471 (65), PROVISIONAL (finding P1 of the player-side review, owner 25 Nov 2026 round 7): the live object of a saved
/// source, kept while its definition and secret stay the same, for the kinds whose object holds what is worth keeping.
/// A Plex client keeps the server's library listing (R305: reused for 300 s, so "browsing, scanning and starting playback
/// within this time cost no new library requests"); built anew for every call, each start of playback walked the whole
/// library twice (the server check, then the converter's reader), every section page and one request per show.
/// Every other kind is built each time, as before (their connections are not kept here).
public final class LiveSourceCache<Source>: @unchecked Sendable {
    private struct Held {
        var definition: UDSourceDefinition
        var secret: String?
        var source: Source
    }

    private let lock = NSLock()
    private var held: [String: Held] = [:]

    public init() {}

    /// Whether a source of this definition's kind is kept.
    public static func keeps(_ definition: UDSourceDefinition) -> Bool { definition.sourceKind == .plex }

    /// The kept object when the definition and the secret are the same as when it was built; otherwise a new one from
    /// `build` (kept when its kind is). A build that throws keeps nothing.
    public func source(for definition: UDSourceDefinition, secret: String?, build: () throws -> Source) rethrows -> Source {
        guard Self.keeps(definition) else { return try build() }
        if let kept = lock.withLock({ held[definition.id] }), kept.definition == definition, kept.secret == secret {
            return kept.source
        }
        let made = try build()
        lock.withLock { held[definition.id] = Held(definition: definition, secret: secret, source: made) }
        return made
    }

    /// Drops the kept object of a source (removed, or its connection must be made again).
    public func forget(id: String) {
        lock.withLock { held[id] = nil }
    }

    /// Whether an object of this source is kept now (for tests and checks).
    public func isHolding(id: String) -> Bool { lock.withLock { held[id] != nil } }
}

/// R471 (68), PROVISIONAL (owner 25 Nov 2026 round 8, Part B item 2): saving a source's definition (an edit, a new
/// certificate trusted, a rename or an option) drops its kept live object, so nothing built from the old definition is
/// held after the edit. The save is passed on unchanged; a save that fails drops nothing (the definition is unchanged).
public struct ForgettingDefinitionSaver: SourceDefinitionSaving {
    private let inner: any SourceDefinitionSaving
    private let forget: @Sendable (String) -> Void

    public init(inner: any SourceDefinitionSaving, forget: @escaping @Sendable (String) -> Void) {
        self.inner = inner
        self.forget = forget
    }

    public func saveDefinition(_ definition: UDSourceDefinition) async throws {
        try await inner.saveDefinition(definition)
        forget(definition.id)
    }
}
