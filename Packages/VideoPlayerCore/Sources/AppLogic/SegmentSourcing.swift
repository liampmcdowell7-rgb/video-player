import Foundation
import VideoPlayerCore
import PlaybackLogic
import MetadataLocal
import UserData

// Collects the segment candidates of one file from the three sources this version has, then merges them
// (docs/SEGMENTS.md):
//   1. user-marked positions, from the user-data ledger;
//   2. embedded chapters, read from the Matroska file through ranged reads;
//   3. sidecar files next to the video (`<name>.edl`, `<name>.segments.json`).
// Online timestamp lookups and on-device detection are later items on the backlog (items 33 and 34): `SegmentSourceInputs`
// already has empty slots for them.
//
// Never throws. A source that cannot be read gives no candidates and one line in `notes`; the others still count.

/// What `SegmentCollector` needs to know about the file. Plain values, so it can be built from any library row.
public struct SegmentFileInfo: Equatable, Sendable {
    /// Path inside the source (what `MediaSource.read` takes).
    public var path: String
    public var size: Int64?
    /// Length in seconds when the library or the player knows it (the probe, the NFO, the saved watch state).
    public var duration: TimeInterval?

    public init(path: String, size: Int64? = nil, duration: TimeInterval? = nil) {
        self.path = path
        self.size = size
        self.duration = duration
    }

    var name: String { String(path.split(separator: "/").last ?? "") }
    var parentPath: String {
        let parts = path.split(separator: "/").dropLast()
        return parts.isEmpty ? "/" : "/" + parts.joined(separator: "/")
    }
}

/// The result: the merged segments plus what happened, for File Details and for tests.
public struct SegmentCollection: Equatable, Sendable {
    public var resolved: ResolvedSegments
    /// One line per source: what was read, what was skipped and why. Never empty.
    public var notes: [String]
    /// The identity every candidate was made for (nil when the length of the file is unknown).
    public var file: FileIdentity?

    public var segments: [SkipSegment] { resolved.segments }
}

public enum ChapterMarks {
    /// Chapters of the file as the playback logic reads them. Hidden editions are left out; the flagged default edition is marked.
    /// Nested chapters are flattened in start order (`MatroskaEdition.flattenedChapters`).
    public static func marks(from metadata: EmbeddedMetadata) -> [ChapterMark] {
        var out: [ChapterMark] = []
        for (index, edition) in metadata.editions.enumerated() where !edition.isHidden {
            let id = edition.uid ?? UInt64(1_000_000 + index)
            for chapter in edition.flattenedChapters {
                let titles = chapter.displays.map { ChapterMark.Title(language: $0.languages.first, text: $0.title) }
                out.append(ChapterMark(start: chapter.startSeconds, end: chapter.endSeconds, titles: titles, isHidden: chapter.isHidden,
                                       isEnabled: chapter.isEnabled, editionID: id, editionIsDefault: edition.isDefault))
            }
        }
        return out
    }
}

public struct SegmentCollector: Sendable {
    public var limits: SegmentLimits
    /// Longest time the reading of chapters and sidecars may take before the player starts without them. User marks never wait.
    public var deadline: TimeInterval
    /// PROVISIONAL: confidence of a user mark (the highest possible, the user said so).
    public static let userMarkConfidence = 1.0

    public init(limits: SegmentLimits = SegmentLimits(), deadline: TimeInterval = 6) {
        self.limits = limits
        self.deadline = deadline
    }

    /// - Parameters:
    ///   - source: where the file lives, nil when it cannot be opened (then only the user marks count).
    ///   - marks: the user marks of this item, already read from the ledger.
    public func collect(file: SegmentFileInfo, source: (any MediaSource)?, marks: [UDSegmentMark]) async -> SegmentCollection {
        var notes: [String] = []
        var chapterCandidates: [SkipSegment] = []
        var sidecarCandidates: [SkipSegment] = []
        var postCredits: TimeInterval?

        // 1. Chapters and sidecars, under one deadline.
        var duration = file.duration.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        var metadata: EmbeddedMetadata?
        var sidecarFiles: [(name: String, format: SidecarFormat, data: Data)] = []
        if let source {
            let isMatroska = ["mkv", "webm"].contains(FileClassifier.fileExtension(of: file.name))
            let work = await Deadline.run(seconds: deadline) { () -> ([String], EmbeddedMetadata?, [(name: String, format: SidecarFormat, data: Data)]) in
                var local: [String] = []
                var meta: EmbeddedMetadata?
                if isMatroska {
                    do { meta = try await MatroskaReader().read(from: source, path: file.path) } catch is CancellationError {
                        local.append("Chapters: reading was cancelled")
                    } catch {
                        local.append("Chapters: the file could not be read as Matroska (\(error))")
                    }
                } else {
                    local.append("Chapters: only Matroska files are read in this version")
                }
                let (found, sideNotes) = await Self.readSidecars(for: file, source: source)
                return (local + sideNotes, meta, found)
            }
            if let work {
                notes += work.0
                metadata = work.1
                sidecarFiles = work.2
            } else {
                notes.append("Chapters and sidecar files: reading did not finish within \(deadline) seconds and was skipped")
            }
        } else {
            notes.append("Chapters and sidecar files: the source of this file is not connected")
        }

        if duration == nil, let fromFile = metadata?.durationSeconds, fromFile > 0, fromFile.isFinite { duration = fromFile }
        guard let length = duration else {
            notes.append("The length of the file is not known, so no segment can be checked and none is used")
            return SegmentCollection(resolved: ResolvedSegments(merged: []), notes: notes, file: nil)
        }
        let identity = FileIdentity(path: file.path, size: file.size ?? 0, duration: length)

        if let metadata {
            let marksFromFile = ChapterMarks.marks(from: metadata)
            let extraction = ChapterSegmentExtractor.extract(chapters: marksFromFile, file: identity)
            chapterCandidates = extraction.candidates
            postCredits = extraction.postCreditsStart
            notes.append("Chapters: \(marksFromFile.count) read, \(chapterCandidates.count) recognised as recap, intro or credits"
                         + (postCredits != nil ? ", with a post-credits chapter" : ""))
            notes += metadata.warnings.map { "Chapters: \($0)" }
        }
        for side in sidecarFiles {
            let parsed = SidecarSegments.parse(side.data, format: side.format)
            sidecarCandidates += SidecarSegments.candidates(from: parsed.entries, file: identity)
            notes.append("Sidecar \(side.name): \(parsed.entries.count) segment(s)" + (parsed.warnings.isEmpty ? "" : ", \(parsed.warnings.count) skipped"))
            notes += parsed.warnings.prefix(5).map { "Sidecar \(side.name): \($0)" }
        }

        // 2. User marks, kept only when they were made on a file of the same length.
        var markCandidates: [SkipSegment] = []
        let tolerance = limits.durationTolerance(for: length)
        for mark in marks {
            guard let type = SegmentType(rawValue: mark.kind) else {
                notes.append("User mark \"\(mark.kind)\" is of a kind this version does not know; kept, not used")
                continue
            }
            if let marked = mark.fileDuration, abs(marked - length) > tolerance {
                notes.append("User mark \(mark.kind) was made on a file of another length (\(Int(marked)) s, this one \(Int(length)) s); not used")
                continue
            }
            markCandidates.append(SkipSegment(type: type, start: mark.start, end: mark.end, source: .userMarked,
                                              confidence: Self.userMarkConfidence, file: identity))
        }
        if !markCandidates.isEmpty { notes.append("User marks: \(markCandidates.count)") }

        // 3. Merge.
        let resolved = SegmentMerger.merge(
            file: identity,
            inputs: SegmentSourceInputs(userMarked: markCandidates, localSidecar: sidecarCandidates, embeddedChapters: chapterCandidates,
                                        postCreditsStart: postCredits),
            limits: limits)
        for rejected in resolved.rejected where !isOutranked(rejected.reason) {
            notes.append("Not used: \(rejected.segment.type.rawValue) from \(rejected.segment.source.rawValue) (\(rejected.reason))")
        }
        return SegmentCollection(resolved: resolved, notes: notes, file: identity)
    }

    private func isOutranked(_ reason: SegmentRejection) -> Bool {
        if case .outranked = reason { return true }
        return false
    }

    // MARK: Sidecar reading

    /// Finds `<name>.edl` and `<name>.segments.json` in the video's folder and reads them (at most `SidecarSegments.maxBytes` each).
    static func readSidecars(for file: SegmentFileInfo, source: any MediaSource) async -> ([(name: String, format: SidecarFormat, data: Data)], [String]) {
        var notes: [String] = []
        let entries: [SourceEntry]
        do { entries = try await source.list(file.parentPath) } catch {
            return ([], ["Sidecar files: the folder could not be listed (\(error))"])
        }
        let wanted = SidecarSegments.matching(videoName: file.name, among: entries.filter { !$0.isDirectory }.map(\.name))
        var out: [(name: String, format: SidecarFormat, data: Data)] = []
        for hit in wanted {
            guard let entry = entries.first(where: { $0.name == hit.name }) else { continue }
            if let size = entry.size, size > Int64(SidecarSegments.maxBytes) {
                notes.append("Sidecar \(hit.name): \(size) bytes, over the \(SidecarSegments.maxBytes) byte limit; not read")
                continue
            }
            do {
                let data = try await source.read(entry.path, range: ByteRange(offset: 0, length: Int64(SidecarSegments.maxBytes + 1)))
                out.append((hit.name, hit.format, data))
            } catch {
                notes.append("Sidecar \(hit.name): could not be read (\(error))")
            }
        }
        return (out, notes)
    }
}

// MARK: Deadline

/// Runs async work and gives up waiting after `seconds`. Work that ignores cancellation keeps running in the background and its
/// result is dropped; the caller never waits for it.
enum Deadline {
    static func run<T: Sendable>(seconds: TimeInterval, _ work: @escaping @Sendable () async -> T) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let gate = Gate<T>(continuation)
            let worker = Task {
                let value = await work()
                gate.finish(value)
            }
            let timer = Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                if !Task.isCancelled { gate.finish(nil) }
            }
            gate.attach(worker: worker, timer: timer)
        }
    }

    private final class Gate<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T?, Never>?
        private var worker: Task<Void, Never>?
        private var timer: Task<Void, Never>?
        private var done = false

        init(_ continuation: CheckedContinuation<T?, Never>) { self.continuation = continuation }

        func attach(worker: Task<Void, Never>, timer: Task<Void, Never>) {
            let finished = lock.withLock { () -> Bool in
                self.worker = worker
                self.timer = timer
                return done
            }
            // Finished before the tasks were attached: stop the leftovers.
            if finished { worker.cancel(); timer.cancel() }
        }

        func finish(_ value: T?) {
            let (c, w, t): (CheckedContinuation<T?, Never>?, Task<Void, Never>?, Task<Void, Never>?) = lock.withLock {
                guard !done else { return (nil, nil, nil) }
                done = true
                let c = continuation
                continuation = nil
                return (c, worker, timer)
            }
            guard let c else { return }
            // The timer is always stopped; the worker only when the deadline won (a worker that finished needs no cancel).
            t?.cancel()
            if value == nil { w?.cancel() }
            c.resume(returning: value)
        }
    }
}
