import Foundation
import VideoPlayerCore

public struct ScanProgress: Equatable, Sendable {
    public var foldersDone = 0
    public var foldersPending = 0
    public var filesSeen = 0
    public var added = 0
    public var changed = 0
    public var removed = 0
    public var unchanged = 0
    public var foldersFailed = 0
    public var currentFolder = ""
}

public struct ScanFailure: Equatable, Sendable {
    public var folder: String
    public var message: String
}

public struct ScanSummary: Equatable, Sendable {
    public var scanID: Int64
    public var status: ScanStatus
    public var resumed: Bool
    public var progress: ScanProgress
    public var failures: [ScanFailure]
    public var seconds: Double
}

/// Walks a `MediaSource` and keeps the index in step with it.
///
/// - Memory stays flat: one folder's listing is held at a time; the list of folders still to do lives in the database.
/// - Resumable: each folder is stored in one transaction together with its place in the queue, so a scan that dies
///   at any moment continues with the next folder (`sync(resume: true)`) and ends with the same index as an
///   uninterrupted one.
/// - Cancellable: cancelling the surrounding Task stops after the current folder and keeps the queue for a resume.
/// - Unchanged files (same server token, ETag, or date and size) cost no writes. Files whose version cannot be
///   compared are rewritten every scan.
/// - A folder that cannot be listed keeps every row it had; the error is recorded and the scan goes on.
/// - A folder that suddenly lists as empty (it had content) is believed only the second time in a row, so a server
///   glitch or an unmounted share does not wipe a library.
public struct LibrarySyncer: Sendable {
    public let store: any LibraryScanStore
    public let source: any MediaSource
    public let sourceID: String
    public let annotator: any FileAnnotator
    public let clock: @Sendable () -> Date

    public init(
        store: any LibraryScanStore, source: any MediaSource, sourceID: String,
        annotator: any FileAnnotator = FilenameAnnotator(), clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.source = source
        self.sourceID = sourceID
        self.annotator = annotator
        self.clock = clock
    }

    /// Scans `roots` (the whole source by default).
    @discardableResult
    public func sync(
        roots: [String] = ["/"], options: ScanOptions = ScanOptions(), resume: Bool = true,
        progress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws -> ScanSummary {
        let started = clock()
        let wallStart = DispatchTime.now().uptimeNanoseconds
        let ticket = try await store.beginScan(sourceID: sourceID, roots: roots, options: options, resume: resume, now: started)
        var p = ScanProgress()
        p.foldersPending = ticket.pendingFolders
        var failures: [ScanFailure] = []
        var status = ScanStatus.completed

        do {
            while let pending = try await store.nextFolder(scanID: ticket.scanID) {
                if Task.isCancelled {
                    status = .cancelled
                    break
                }
                p.currentFolder = pending.path
                do {
                    let result = try await scanFolder(pending, scanID: ticket.scanID, progress: &p)
                    p.added += result.added
                    p.changed += result.changed
                    p.removed += result.removed
                    p.foldersPending += result.queuedFolders
                } catch is CancellationError {
                    status = .cancelled
                    break
                } catch let error as SourceError where Self.isFatal(error) {
                    throw error
                } catch let error as LibraryIndexError {
                    throw error
                } catch {
                    if Task.isCancelled { status = .cancelled; break }
                    let message = String(describing: error)
                    try await store.recordFailure(scanID: ticket.scanID, sourceID: sourceID, folder: pending.path, message: message, now: clock())
                    failures.append(ScanFailure(folder: pending.path, message: message))
                    p.foldersFailed += 1
                }
                p.foldersDone += 1
                p.foldersPending = max(0, p.foldersPending - 1)
                progress?(p)
            }
        } catch {
            try? await store.finishScan(scanID: ticket.scanID, status: .interrupted, now: clock())
            throw error
        }
        try await store.finishScan(scanID: ticket.scanID, status: status, now: clock())
        progress?(p)
        return ScanSummary(scanID: ticket.scanID, status: status, resumed: ticket.resumed, progress: p, failures: failures, seconds: Double(DispatchTime.now().uptimeNanoseconds - wallStart) / 1_000_000_000)
    }

    /// Re-reads one folder (and, with `recursive`, everything below it).
    @discardableResult
    public func refresh(folder: String, recursive: Bool = false, progress: (@Sendable (ScanProgress) -> Void)? = nil) async throws -> ScanSummary {
        try await sync(roots: [folder], options: ScanOptions(recursive: recursive), resume: false, progress: progress)
    }

    private static func isFatal(_ error: SourceError) -> Bool {
        switch error {
        case .unauthorized, .unsupportedAuthentication, .insecureBasicAuthentication: return true
        default: return false
        }
    }

    private func scanFolder(_ pending: PendingFolder, scanID: Int64, progress p: inout ScanProgress) async throws -> FolderApplyResult {
        let entries = try await source.list(pending.path)
        let stored = try await store.storedFiles(sourceID: sourceID, folder: pending.path)
        var byPath: [String: StoredFile] = [:]
        byPath.reserveCapacity(stored.count)
        for f in stored { byPath[f.path] = f }

        var seen = Set<String>()
        seen.reserveCapacity(entries.count)
        var upserts: [FileUpsert] = []
        var children: [ListedFolder] = []
        var unchanged = 0
        var filesSeen = 0
        let ancestors = LibraryPath.ancestorNames(of: pending.path + "/x")

        for e in entries {
            if e.isDirectory {
                children.append(ListedFolder(path: e.path, name: e.name, version: e.version))
                continue
            }
            let kind = FileClassifier.kind(forName: e.name, isDirectory: false)
            if kind == .other { continue }
            filesSeen += 1
            seen.insert(e.path)
            if let old = byPath[e.path], old.version.isSame(as: e.version) == true {
                unchanged += 1
                continue
            }
            var seed: ItemSeed?
            var tech: FileTechnicalInfo?
            if kind == .video {
                let parsed = FilenameParser.parse(fileName: e.name, folders: ancestors)
                seed = ItemGrouping.seed(parsed: parsed, fileName: e.name)
                tech = annotator.technicalInfo(for: e, parsed: parsed)
            }
            upserts.append(FileUpsert(
                path: e.path, name: e.name, kind: kind, size: e.size, modified: e.modified, etag: e.etag,
                serverToken: e.serverToken, technical: tech, seed: seed
            ))
        }

        let listedFolders = Set(children.map(\.path))
        let storedFolders = pending.storedEntryCount > 0 ? try await store.storedChildFolders(sourceID: sourceID, folder: pending.path) : []
        let removedFiles = stored.map(\.path).filter { !seen.contains($0) }
        let removedFolders = storedFolders.filter { !listedFolders.contains($0) }

        // An empty listing of a folder that had content is held back once.
        let listedNothing = entries.isEmpty
        let hadContent = pending.storedEntryCount > 0
        let hold = listedNothing && hadContent && pending.emptyStrikes < 1
        let strikes = listedNothing && hadContent ? pending.emptyStrikes + 1 : 0

        p.filesSeen += filesSeen
        p.unchanged += unchanged
        let change = FolderChange(
            sourceID: sourceID, path: pending.path, scannedVersion: pending.observed, childFolders: children, upserts: upserts,
            removedFilePaths: removedFiles, removedFolderPaths: removedFolders, holdRemovals: hold, emptyStrikes: strikes, now: clock()
        )
        return try await store.apply(change, scanID: scanID)
    }
}
