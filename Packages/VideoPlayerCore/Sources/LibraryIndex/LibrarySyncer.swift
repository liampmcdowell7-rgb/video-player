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
/// - Every video is sorted on its own (docs/SORTING.md): `MediaSorter` reads the file name, the other files in the same
///   folder and, for media servers, the server's item type; an override from the user-data ledger replaces all of that.
///   Unchanged files are sorted again only when the rules, their override, the server type or the source setting changed,
///   or when they are in Needs Review and the folder now says more about them.
public struct LibrarySyncer: Sendable {
    public let store: any LibraryScanStore
    public let source: any MediaSource
    public let sourceID: String
    public let annotator: any FileAnnotator
    public let clock: @Sendable () -> Date
    public let overrides: any SortOverrideProviding
    /// The source setting "Sort by filename instead of server library types" (PROVISIONAL, default off).
    public let preferFilename: Bool
    /// Receives one line per sorted file: path, outcome, signal and the reason.
    public let sortLog: (@Sendable (_ path: String, _ outcome: SortOutcome, _ signal: SortSignal, _ note: String) -> Void)?

    public init(
        store: any LibraryScanStore, source: any MediaSource, sourceID: String,
        annotator: any FileAnnotator = FilenameAnnotator(), clock: @escaping @Sendable () -> Date = { Date() },
        overrides: any SortOverrideProviding = NoSortOverrides(), preferFilename: Bool = false,
        sortLog: (@Sendable (_ path: String, _ outcome: SortOutcome, _ signal: SortSignal, _ note: String) -> Void)? = nil
    ) {
        self.store = store
        self.source = source
        self.sourceID = sourceID
        self.annotator = annotator
        self.clock = clock
        self.overrides = overrides
        self.preferFilename = preferFilename
        self.sortLog = sortLog
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
        let overrideMap = overrides.overrides(sourceID: sourceID)
        let excluded = overrides.excludedPaths(sourceID: sourceID)

        do {
            while let pending = try await store.nextFolder(scanID: ticket.scanID) {
                if Task.isCancelled {
                    status = .cancelled
                    break
                }
                p.currentFolder = pending.path
                do {
                    let result = try await scanFolder(pending, scanID: ticket.scanID, overrides: overrideMap, excluded: excluded, progress: &p)
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

    private func scanFolder(_ pending: PendingFolder, scanID: Int64, overrides: [String: SortOverride], excluded: Set<String> = [],
                            progress p: inout ScanProgress) async throws -> FolderApplyResult {
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
        // The folder names, parsed once for every file of this folder (addendum #19 A).
        let ancestorInfos = ancestors.map(FilenameParser.parseFolderName)
        // The other videos in this folder, read only when a file needs sorting.
        var siblingCache: SiblingIndex?
        func siblings() -> SiblingIndex {
            if let s = siblingCache { return s }
            let s = SiblingIndex(names: entries.filter { !$0.isDirectory && FileClassifier.kind(forName: $0.name, isDirectory: false) == .video }.map(\.name))
            siblingCache = s
            return s
        }

        for e in entries {
            if e.isDirectory {
                children.append(ListedFolder(path: e.path, name: e.name, version: e.version))
                continue
            }
            let kind = FileClassifier.kind(forName: e.name, isDirectory: false)
            if kind == .other { continue }
            // R471 (15): deleted from the library by the user: left out like a file that is not there.
            if excluded.contains(e.path) { continue }
            filesSeen += 1
            seen.insert(e.path)
            // R471 (24): a trailer or bonus video gets no item and is not sorted; its title's page lists it. A file
            // stored as a title before (an item, a sort record) is written once more, which takes it off that item.
            if kind == .video, overrides[e.path] == nil, ExtraVideo.role(name: e.name, parentPath: pending.path) != nil {
                let old = byPath[e.path]
                if let old, old.version.isSame(as: e.version) == true, old.itemID == nil, old.sort == nil {
                    unchanged += 1
                    continue
                }
                upserts.append(FileUpsert(
                    path: e.path, name: e.name, kind: kind, size: e.size, modified: e.modified, etag: e.etag,
                    serverToken: e.serverToken, technical: old?.technical, seed: nil, sort: nil
                ))
                continue
            }
            let inputs = kind == .video ? sortInputs(override: overrides[e.path], serverType: e.serverItemType) : ""
            if let old = byPath[e.path], old.version.isSame(as: e.version) == true {
                guard kind == .video, Self.mayNeedSorting(old.sort, inputs: inputs) else {
                    unchanged += 1
                    continue
                }
                let sorted = sortFile(e, override: overrides[e.path], inputs: inputs, ancestors: ancestors, ancestorInfos: ancestorInfos, siblings: siblings)
                if let before = old.sort, before.needsReview, sorted.record.needsReview, before.revision == sorted.record.revision, before.inputs == inputs {
                    unchanged += 1   // still in Needs Review: nothing to write
                    continue
                }
                upserts.append(FileUpsert(
                    path: e.path, name: e.name, kind: kind, size: e.size, modified: e.modified, etag: e.etag, serverToken: e.serverToken,
                    technical: old.technical ?? annotator.technicalInfo(for: e, parsed: sorted.parsed), seed: sorted.seed, sort: sorted.record
                ))
                continue
            }
            var seed: ItemSeed?
            var tech: FileTechnicalInfo?
            var sort: FileSortRecord?
            if kind == .video {
                let sorted = sortFile(e, override: overrides[e.path], inputs: inputs, ancestors: ancestors, ancestorInfos: ancestorInfos, siblings: siblings)
                seed = sorted.seed
                sort = sorted.record
                tech = annotator.technicalInfo(for: e, parsed: sorted.parsed)
            }
            upserts.append(FileUpsert(
                path: e.path, name: e.name, kind: kind, size: e.size, modified: e.modified, etag: e.etag,
                serverToken: e.serverToken, technical: tech, seed: seed, sort: sort
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

    // MARK: Sorting (docs/SORTING.md)

    /// Everything besides the file that decided its place, as stored with the file.
    func sortInputs(override: SortOverride?, serverType: ServerItemType?) -> String {
        var parts: [String] = []
        if let override { parts.append("o:" + override.fingerprint) }
        if let serverType { parts.append("s:" + serverType.rawValue + (preferFilename ? ":name" : "")) }
        return parts.joined(separator: "|")
    }

    /// An unchanged file is looked at again when it was sorted by older rules or other inputs, or is in Needs Review.
    /// A file waiting because two shows share its name is the exception: its file name already said episode, and only the
    /// show-year pass (SQLiteLibraryStore+ShowYears) can take it out, so sorting it again would only rewrite it each scan.
    static func mayNeedSorting(_ old: FileSortRecord?, inputs: String) -> Bool {
        guard let old else { return true }
        if old.waitsForSharedName { return old.revision < MediaSorter.revision || old.inputs != inputs }
        return old.revision < MediaSorter.revision || old.inputs != inputs || old.needsReview
    }

    func sortFile(_ e: SourceEntry, override: SortOverride?, inputs: String, ancestors: [String], ancestorInfos: [FilenameParser.FolderInfo]? = nil, siblings: () -> SiblingIndex)
        -> (seed: ItemSeed, record: FileSortRecord, parsed: ParsedMedia) {
        let decision = override.map { MediaSorter.apply($0, to: e.name, folders: ancestors) }
            ?? MediaSorter.decide(fileName: e.name, context: SortContext(folders: ancestors, folderInfos: ancestorInfos, siblings: siblings(), serverType: e.serverItemType, preferFilename: preferFilename))
        var outcome = decision.outcome
        var note = decision.note
        var seed = ItemGrouping.seed(parsed: decision.parsed, fileName: e.name)
        if outcome == .episode, seed.kind != .episode {
            outcome = .needsReview
            note += " There is no show name or episode number to file it under."
        } else if outcome == .movie, seed.kind != .movie || seed.key.hasPrefix("f|") {
            outcome = .needsReview
            note += " There is no title to file it under."
        }
        if outcome == .needsReview { seed = ItemGrouping.reviewSeed(sourceID: sourceID, path: e.path, fileName: e.name, parsed: decision.parsed) }
        let signal = outcome == .needsReview ? SortSignal.undecided : decision.signal
        sortLog?(e.path, outcome, signal, note)
        return (seed, FileSortRecord(signal: signal, note: note, inputs: inputs, needsReview: outcome == .needsReview), decision.parsed)
    }
}
