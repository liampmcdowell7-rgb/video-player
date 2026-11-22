import Foundation

/// Identity of a library file for saved match choices: its path (forward slashes) and, for information, its size.
/// The choice is keyed by path only; a file that is replaced by another at the same path keeps its choice.
public struct FileIdentity: Codable, Hashable, Sendable {
    public var path: String
    public var size: Int64?

    public init(path: String, size: Int64? = nil) {
        var p = path.replacingOccurrences(of: "\\", with: "/")
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        self.path = p
        self.size = size
    }

    /// The folder holding the file ("" for a file with no folder part).
    public var folderPath: String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        let folder = String(path[..<slash])
        return folder.isEmpty ? "/" : folder
    }
}

/// How far a saved choice reaches.
public enum MatchScope: Codable, Hashable, Sendable {
    /// This file only.
    case file
    /// Every file of this season in the same folder (series only).
    case season(Int)
    /// Every file in this folder and below (series only).
    case folder
}

/// A choice made on the Fix Match screen. It always beats automatic matching.
public struct StoredMatch: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var scope: MatchScope
    /// The file path for `.file`; the folder path for `.season` and `.folder`.
    public var path: String
    public var fileSize: Int64?
    public var tmdbID: Int
    public var kind: TitleKind
    public var title: String
    public var year: Int?
    public var createdAt: Date

    public init(id: UUID = UUID(), scope: MatchScope, path: String, fileSize: Int64? = nil, tmdbID: Int, kind: TitleKind, title: String, year: Int?, createdAt: Date) {
        self.id = id
        self.scope = scope
        self.path = path
        self.fileSize = fileSize
        self.tmdbID = tmdbID
        self.kind = kind
        self.title = title
        self.year = year
        self.createdAt = createdAt
    }

    /// Picks the saved choice that applies to a file: its own, then its season's, then the deepest folder's.
    public static func best(for file: FileIdentity, season: Int?, in matches: [StoredMatch]) -> StoredMatch? {
        if let own = matches.first(where: { $0.scope == .file && $0.path == file.path }) { return own }
        if let season, let s = matches.first(where: { $0.scope == .season(season) && $0.path == file.folderPath }) { return s }
        let prefixOf: (StoredMatch) -> Bool = { m in
            m.scope == .folder && (m.path == "/" ? file.path.hasPrefix("/") : file.path.hasPrefix(m.path + "/"))
        }
        return matches.filter(prefixOf).max { $0.path.count < $1.path.count }
    }
}

public struct MatchStoreError: Error, Equatable, Sendable {
    public var message: String
}

public protocol MatchStore: Sendable {
    /// Saves a choice, replacing an existing one with the same scope and path. Returns the one replaced.
    @discardableResult func save(_ match: StoredMatch) async throws -> StoredMatch?
    @discardableResult func remove(id: UUID) async throws -> StoredMatch?
    func all() async -> [StoredMatch]
}

extension MatchStore {
    public func lookup(file: FileIdentity, season: Int?) async -> StoredMatch? {
        StoredMatch.best(for: file, season: season, in: await all())
    }
}

public actor InMemoryMatchStore: MatchStore {
    private var matches: [StoredMatch] = []
    public init() {}

    @discardableResult public func save(_ match: StoredMatch) -> StoredMatch? {
        var replaced: StoredMatch?
        if let i = matches.firstIndex(where: { $0.scope == match.scope && $0.path == match.path }) {
            replaced = matches.remove(at: i)
        }
        matches.append(match)
        return replaced
    }

    @discardableResult public func remove(id: UUID) -> StoredMatch? {
        guard let i = matches.firstIndex(where: { $0.id == id }) else { return nil }
        return matches.remove(at: i)
    }

    public func all() -> [StoredMatch] { matches }
}

/// Keeps choices in one JSON file, written atomically after each change.
/// A file that cannot be read is renamed to `<name>.corrupt` and the store starts empty (nothing is thrown away silently).
public actor JSONFileMatchStore: MatchStore {
    private struct Document: Codable {
        var version: Int
        var matches: [StoredMatch]
    }

    private let url: URL
    private var matches: [StoredMatch] = []
    private var loaded = false

    public init(url: URL) { self.url = url }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let doc = try? decoder.decode(Document.self, from: data) {
            matches = doc.matches
        } else {
            let aside = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
        }
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(Document(version: 1, matches: matches)).write(to: url, options: .atomic)
        } catch {
            throw MatchStoreError(message: "could not save match choices: \(error.localizedDescription)")
        }
    }

    @discardableResult public func save(_ match: StoredMatch) throws -> StoredMatch? {
        load()
        var replaced: StoredMatch?
        if let i = matches.firstIndex(where: { $0.scope == match.scope && $0.path == match.path }) {
            replaced = matches.remove(at: i)
        }
        matches.append(match)
        try persist()
        return replaced
    }

    @discardableResult public func remove(id: UUID) throws -> StoredMatch? {
        load()
        guard let i = matches.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = matches.remove(at: i)
        try persist()
        return removed
    }

    public func all() -> [StoredMatch] {
        load()
        return matches
    }

    /// R381: replaces every choice at once (the cache rebuilt from the iCloud copy, `CloudMatchStore` in AppLogic).
    public func replaceAll(_ new: [StoredMatch]) throws {
        loaded = true
        matches = new
        try persist()
    }
}
