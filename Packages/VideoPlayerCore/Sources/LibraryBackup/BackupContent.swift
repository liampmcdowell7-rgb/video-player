import Foundation

/// One file of a set, read only when the engine gets to it (artwork can be thousands of files).
public struct BackupFile: Sendable {
    public var name: String
    public var size: Int
    public var modified: Date
    public var load: @Sendable () async throws -> Data
    public init(name: String, size: Int, modified: Date, load: @escaping @Sendable () async throws -> Data) {
        self.name = name
        self.size = size
        self.modified = modified
        self.load = load
    }
}

/// Where the files of each set come from (the app: the library store's snapshot, the metadata and artwork folders).
public protocol BackupContent: Sendable {
    /// The files of `set` as they are now, plus files the content left out on purpose (for example pictures that belong
    /// to no item when "Only artwork for items in your library" is on).
    func files(for set: BackupSet, settings: BackupSettings) async throws -> (files: [BackupFile], skipped: [BackupSkip])
    /// The schema number of the library database the snapshot holds.
    func librarySchema() async -> Int
}

/// Where restored files go. The library database is handed to the open store (SQLite's backup API copies it in), every
/// other file is written into its folder.
public protocol BackupRestoreTarget: Sendable {
    /// The newest library database schema this app can open.
    var supportedLibrarySchema: Int { get }
    /// True when this Apple TV's library index holds no items (after a purge, a reinstall, a new Apple TV).
    func libraryIsEmpty() async -> Bool
    /// The modification time of the local copy of a file, or nil when there is none.
    func localModified(_ set: BackupSet, name: String) async -> Date?
    /// `modified` is the backed-up modification time (set on the written file, so the merge rule compares like with like).
    func write(_ set: BackupSet, name: String, data: Data, modified: Date) async throws
}

/// The name of the library database inside the `library` set. Restored first, and only into an empty library unless the
/// user chose "Restore from iCloud".
public let backupLibraryDatabaseName = "library.sqlite"

/// A folder of files as backup content and restore target (the artwork cache, the online-metadata cache). Plain
/// FileManager calls, so it is tested in WSL. Names are paths relative to the folder; nothing outside it is read or written.
public struct FolderBackupStore: Sendable {
    public let root: URL
    public let prefix: String
    public init(root: URL, prefix: String) {
        self.root = root
        self.prefix = prefix
    }

    /// Every regular file under the folder, as "prefix/relative/path".
    public func files() -> [BackupFile] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]) else { return [] }
        let base = root.standardizedFileURL.path
        var out: [BackupFile] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            let relative = String(path.dropFirst(base.count + 1))
            out.append(BackupFile(name: prefix + "/" + relative, size: values?.fileSize ?? 0, modified: values?.contentModificationDate ?? Date(timeIntervalSince1970: 0)) {
                try Data(contentsOf: url)
            })
        }
        return out.sorted { $0.name < $1.name }
    }

    /// The URL for a name of this store, or nil when the name is not inside the folder (no "..", no other prefix).
    public func url(for name: String) -> URL? {
        guard name.hasPrefix(prefix + "/") else { return nil }
        let relative = String(name.dropFirst(prefix.count + 1))
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !relative.isEmpty, !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        return root.appendingPathComponent(relative)
    }

    public func modified(_ name: String) -> Date? {
        guard let url = url(for: name) else { return nil }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Writes the file and sets its modification time to the backed-up one, so the merge rule compares like with like.
    public func write(_ name: String, data: Data, modified: Date?) throws {
        guard let url = url(for: name) else { throw BackupError.local("not a file of \(prefix): \(name)") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        if let modified { try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
    }
}
