import Foundation
import VideoPlayerCore
import LibraryIndex
import MetadataLocal

/// Reads the frame rate, the audio tracks and the embedded subtitles of one file for the Media Info section (#21 C,
/// OPEN_QUESTIONS R192, PROVISIONAL). It uses the same header reader the player uses for a file's chapters
/// (`MatroskaReader`, a few ranged reads of the file's start, never the video data), when the detail page opens; the
/// result is kept in the library index (`LibraryStore.setTrackDetails`), so each file is read once.
///
/// Matroska and WebM only in this version. Other containers (MP4, MOV, TS) are not read, and their rows keep saying
/// "Not checked yet" (#25 B6); reading them would need the system player's asset loading, which the package cannot use (no AVFoundation
/// on Linux, where it is tested).
public enum MediaTrackProbe {
    /// Longest wait for the header (a slow server must not hold the page).
    public static let deadlineSeconds: Double = 8

    public static func canRead(_ file: StoredFile) -> Bool { canRead(name: file.name) }

    public static func canRead(name: String) -> Bool {
        ["mkv", "webm"].contains(FileClassifier.fileExtension(of: name))
    }

    /// Reads the file's header through `source`. Nil when the container is not read here, the read fails or takes too long.
    public static func read(_ file: StoredFile, from source: any MediaSource) async -> FileTrackDetails? {
        guard canRead(file) else { return nil }
        let meta = await Deadline.run(seconds: deadlineSeconds) { () -> EmbeddedMetadata? in
            try? await MatroskaReader().read(from: source, path: file.path)
        }
        return (meta ?? nil).map(details)
    }

    /// The details of a parsed header: the first video track's frame rate, then every audio and subtitle track in file order.
    public static func details(_ meta: EmbeddedMetadata) -> FileTrackDetails {
        let audio = meta.audioTracks.map { t in
            FileTrackDetails.Audio(codec: (t.audioCodec ?? .other) == .other ? t.codecID : t.audioCodec!.rawValue,
                                   channels: t.channels, language: t.languageBCP47 ?? t.language, name: t.name,
                                   isDefault: t.isDefault, isCommentary: t.isCommentary)
        }
        let subtitles = meta.subtitleTracks.map { t in
            FileTrackDetails.Subtitle(codec: subtitleCodec(t.codecID), language: t.languageBCP47 ?? t.language, name: t.name,
                                      isForced: t.isForced, isHearingImpaired: t.isHearingImpaired)
        }
        return FileTrackDetails(frameRate: meta.videoTracks.first?.frameRate, audio: audio, subtitles: subtitles)
    }

    /// "SRT", "ASS", "PGS", "VobSub", "WebVTT", or the CodecID itself.
    static func subtitleCodec(_ id: String) -> String {
        switch id.uppercased() {
        case "S_TEXT/UTF8", "S_TEXT/ASCII": return "SRT"
        case "S_TEXT/ASS", "S_ASS": return "ASS"
        case "S_TEXT/SSA", "S_SSA": return "SSA"
        case "S_HDMV/PGS": return "PGS"
        case "S_VOBSUB": return "VobSub"
        case "S_TEXT/WEBVTT", "D_WEBVTT/SUBTITLES": return "WebVTT"
        case "S_DVBSUB": return "DVB"
        default: return id
        }
    }
}
