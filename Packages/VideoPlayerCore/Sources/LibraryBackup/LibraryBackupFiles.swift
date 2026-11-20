import Foundation
import LibraryIndex

/// What the backup reads and writes on this Apple TV (docs/BACKUP.md "What is backed up"):
///  - library set: `library.sqlite` (a consistent copy of the open index, made with SQLite's backup API), every file of
///    the `libraryFolders` (the online-metadata answers), and the `libraryFiles` (the Fix Match choices);
///  - artwork set: every file of the `artwork` folder (pictures read from the sources).
/// Nothing else is listed, so nothing else can be uploaded: not the media, not the Keychain, not UserDefaults.
public struct LibraryBackupFiles: BackupContent, BackupRestoreTarget {
    public let store: SQLiteLibraryStore
    /// A folder for the temporary database copies (Caches; removed after use).
    public let workDir: URL
    public let libraryFolders: [FolderBackupStore]
    /// Single files: name inside the set -> location (for example "matches.json" in Application Support).
    public let libraryFiles: [String: URL]
    public let artwork: FolderBackupStore?
    /// For "Only artwork for items in your library": the names (in the set) of the pictures that belong to an item or a
    /// series of the library, read once per backup. nil = cannot tell, so every picture is kept.
    public let artworkNamesInLibrary: @Sendable () async -> Set<String>?

    public init(store: SQLiteLibraryStore, workDir: URL, libraryFolders: [FolderBackupStore], libraryFiles: [String: URL],
                artwork: FolderBackupStore?, artworkNamesInLibrary: @escaping @Sendable () async -> Set<String>? = { nil }) {
        self.store = store
        self.workDir = workDir
        self.libraryFolders = libraryFolders
        self.libraryFiles = libraryFiles
        self.artwork = artwork
        self.artworkNamesInLibrary = artworkNamesInLibrary
    }

    // MARK: BackupContent

    public func files(for set: BackupSet, settings: BackupSettings) async throws -> (files: [BackupFile], skipped: [BackupSkip]) {
        switch set {
        case .library:
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            let copy = workDir.appendingPathComponent("backup-\(UUID().uuidString).sqlite")
            try await store.exportSnapshot(to: copy)
            let data = try Data(contentsOf: copy)
            for suffix in ["", "-wal", "-shm", "-journal"] { try? FileManager.default.removeItem(atPath: copy.path + suffix) }
            var out = [BackupFile(name: backupLibraryDatabaseName, size: data.count, modified: Date()) { data }]
            for folder in libraryFolders { out += folder.files() }
            for (name, url) in libraryFiles.sorted(by: { $0.key < $1.key }) {
                guard let values = try? Self.freshValues(url, [.fileSizeKey, .contentModificationDateKey]) else { continue }
                out.append(BackupFile(name: name, size: values.fileSize ?? 0, modified: values.contentModificationDate ?? Date(timeIntervalSince1970: 0)) {
                    try Data(contentsOf: url)
                })
            }
            return (out, [])
        case .artwork:
            guard let artwork else { return ([], []) }
            var keep: [BackupFile] = []
            var skipped: [BackupSkip] = []
            let inLibrary = settings.artworkLibraryOnly ? await artworkNamesInLibrary() : nil
            for f in artwork.files() {
                if let inLibrary, !inLibrary.contains(f.name) {
                    skipped.append(BackupSkip(name: f.name, size: f.size, reason: .notInLibrary))
                } else {
                    keep.append(f)
                }
            }
            return (keep, skipped)
        }
    }

    public func librarySchema() async -> Int { (try? await store.schemaVersion()) ?? 0 }

    // MARK: BackupRestoreTarget

    public var supportedLibrarySchema: Int { SQLiteLibraryStore.supportedSchemaVersion }

    public func libraryIsEmpty() async -> Bool { (try? await store.isEmptyLibrary()) ?? true }

    public func localModified(_ set: BackupSet, name: String) async -> Date? {
        if set == .library, let url = libraryFiles[name] {
            return (try? Self.freshValues(url, [.contentModificationDateKey]))?.contentModificationDate
        }
        return folder(for: set, name: name)?.modified(name)
    }

    public func write(_ set: BackupSet, name: String, data: Data, modified: Date) async throws {
        if set == .library && name == backupLibraryDatabaseName {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            let copy = workDir.appendingPathComponent("restore-\(UUID().uuidString).sqlite")
            defer { for suffix in ["", "-wal", "-shm", "-journal"] { try? FileManager.default.removeItem(atPath: copy.path + suffix) } }
            try data.write(to: copy, options: .atomic)
            try await store.importSnapshot(from: copy)
            return
        }
        if set == .library, let url = libraryFiles[name] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
            return
        }
        guard let folder = folder(for: set, name: name) else { throw BackupError.local("no place for \(name)") }
        try folder.write(name, data: data, modified: modified)
    }

    /// #33 H: the values as they are on disk NOW. `URL.resourceValues(forKeys:)` "first checks if the URL instance already
    /// caches the specified resource values. If so, it returns the cached resource values" (Apple's reference page); off
    /// the main thread nothing clears that cache. `libraryFiles` keeps ONE URL per file, so after Fix Match's file was
    /// deleted the restore still read its old modification date. The backed-up date went through `secondsSince1970` in the
    /// manifest, which loses the last bit about half the time, so the cached date was sometimes "newer" than the backup's:
    /// the merge rule kept a local file that no longer existed (PurgeBackupRestoreTests.swift: 3 files restored instead of 4,
    /// matches.json missing, macOS only: Foundation on Linux does not cache, which is why test-core never failed there).
    static func freshValues(_ url: URL, _ keys: Set<URLResourceKey>) throws -> URLResourceValues {
        var fresh: URL = url
        fresh.removeAllCachedResourceValues()
        return try fresh.resourceValues(forKeys: keys)
    }

    private func folder(for set: BackupSet, name: String) -> FolderBackupStore? {
        switch set {
        case .library: return libraryFolders.first { name.hasPrefix($0.prefix + "/") }
        case .artwork: return artwork.flatMap { name.hasPrefix($0.prefix + "/") ? $0 : nil }
        }
    }
}
