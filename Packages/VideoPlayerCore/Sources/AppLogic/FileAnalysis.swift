import Foundation
import VideoPlayerCore
import LibraryIndex
import PlaybackLogic

/// R471 (19), PROVISIONAL: Analyze File for one movie or episode. Two steps, for the file the player opens (the preferred
/// version): the file's streams are read again (the header reader of Media Info, `MediaTrackProbe`; the result replaces the
/// kept one), then, for an episode, its intro and credits are found again (the audio comparison of R316, run even when the
/// file was analysed before; the new record replaces the old one in its season). Nothing else is read or changed. Words ours.
public enum FileAnalysis {
    public enum Step: Int, CaseIterable, Sendable {
        case streams, introAndCredits

        public var title: String {
            switch self {
            case .streams: return "Reading the file's streams"
            case .introAndCredits: return "Finding the intro and credits"
            }
        }
    }

    public enum StreamsOutcome: Equatable, Sendable {
        case read(audio: Int, subtitles: Int)
        /// A container the header reader does not read (MP4, MOV, TS): the player still reads it when it plays.
        case notReadable
        case failed
    }

    public enum SegmentsOutcome: Equatable, Sendable {
        /// A movie: intro and credits are found for episodes only.
        case notAnEpisode
        case found(intro: Bool, credits: Bool)
        /// The audio was read, and nothing shared with another episode of the season yet.
        case noneYet
        case failed
    }

    public struct Report: Equatable, Sendable {
        public var streams: StreamsOutcome
        public var segments: SegmentsOutcome
        public init(streams: StreamsOutcome, segments: SegmentsOutcome) { self.streams = streams; self.segments = segments }
    }

    public static let title = "Analyze File"
    public static let done = "Analysis Finished"
    public static let noFile = "This title has no file to analyze."

    /// The result, one line per step.
    public static func lines(_ report: Report) -> [String] {
        var out: [String] = []
        switch report.streams {
        case let .read(audio, subtitles):
            out.append("Streams read: \(count(audio, "audio track")), \(count(subtitles, "subtitle track")).")
        case .notReadable:
            out.append("The streams of this kind of file are read when it plays, not here.")
        case .failed:
            out.append("The file's streams could not be read. Check that the source is reachable.")
        }
        switch report.segments {
        case .notAnEpisode:
            break
        case let .found(intro, credits):
            let parts = [intro ? "the intro" : nil, credits ? "the credits" : nil].compactMap { $0 }
            out.append("Found \(parts.joined(separator: " and ")). The skip buttons use it from the next playback.")
        case .noneYet:
            out.append("No intro or credits found yet. They are found by comparing episodes of the same season, so analyze or play another episode of this season.")
        case .failed:
            out.append("The intro and credits could not be looked for: the file's audio could not be read or its length is not known.")
        }
        return out
    }

    static func count(_ n: Int, _ noun: String) -> String { n == 1 ? "1 \(noun)" : "\(n) \(noun)s" }
}

/// Runs Analyze File; the readers are handed in (the audio reader uses the system's media framework in the app).
public struct FileAnalyzer: Sendable {
    public let store: any LibraryStore
    public let provider: SegmentProvider
    public let readTracks: @Sendable (StoredFile) async -> FileTrackDetails?
    /// Reads the audio of the target's windows and stores the record (true when a record was stored).
    public let analyseAudio: @Sendable (SegmentProvider.AnalysisTarget) async -> Bool

    public init(store: any LibraryStore, provider: SegmentProvider, readTracks: @escaping @Sendable (StoredFile) async -> FileTrackDetails?,
                analyseAudio: @escaping @Sendable (SegmentProvider.AnalysisTarget) async -> Bool) {
        self.store = store; self.provider = provider; self.readTracks = readTracks; self.analyseAudio = analyseAudio
    }

    /// Nil when the item or its file is gone.
    public func run(itemID: Int64, progress: @Sendable (FileAnalysis.Step) async -> Void = { _ in }) async -> FileAnalysis.Report? {
        guard let item = try? await store.item(id: itemID), let file = await provider.playbackFile(of: item) else { return nil }
        await progress(.streams)
        let streams: FileAnalysis.StreamsOutcome
        if !MediaTrackProbe.canRead(file) {
            streams = .notReadable
        } else if let details = await readTracks(file) {
            try? await store.setTrackDetails(fileID: file.id, details)
            streams = .read(audio: details.audio.count, subtitles: details.subtitles.count)
        } else {
            streams = .failed
        }
        guard item.kind == .episode else { return FileAnalysis.Report(streams: streams, segments: .notAnEpisode) }
        await progress(.introAndCredits)
        guard let target = await provider.analysisTarget(forItem: itemID, force: true), await analyseAudio(target) else {
            return FileAnalysis.Report(streams: streams, segments: .failed)
        }
        let found = await provider.segments(forItem: itemID)
        let intro = found.contains { $0.type == .intro }, credits = found.contains { $0.type == .credits }
        return FileAnalysis.Report(streams: streams, segments: intro || credits ? .found(intro: intro, credits: credits) : .noneYet)
    }
}
