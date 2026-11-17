import Foundation
import RemuxEngine

// The honest error text for a file the converting player cannot handle (docs/PLAYBACK_WIRING.md).
//
// Rules this file keeps:
//  - every failure has a plain sentence for WHAT happened and a separate sentence for WHAT TO DO;
//  - the text never blames the user and never hides the reason behind "something went wrong";
//  - a reason the engine reports in its own words (an unsupported codec id, say) is translated to a name a person knows;
//  - nothing here names a product, a company or a third-party library (the text is shown on screen).
//
// Pure Foundation logic so it is tested on Linux. The app maps what it catches (RemuxError, URLError, a failed player
// item) to `PlaybackFailure` with `PlaybackFailures`, and shows `message` and `advice` in its error screen.

public struct PlaybackFailure: Error, Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case noFile, sourceGone, readFailed
        case notMatroska, damaged
        case unsupportedVideo, noVideo, unsupportedLacing, encrypted, unsupportedCompression, unsupportedStructure
        case unsupportedContainer, localServer, playerRejected, cancelled, other
    }

    public var kind: Kind
    /// What happened, one or two plain sentences.
    public var message: String
    /// What the person can do about it, one sentence.
    public var advice: String

    public init(kind: Kind, message: String, advice: String) {
        self.kind = kind
        self.message = message
        self.advice = advice
    }

    public static let title = "Can’t Play This Title"

    /// Both sentences as one block of text (what a plain text field or a log line shows).
    public var text: String { advice.isEmpty ? message : message + " " + advice }

    /// True for a failure the person caused by leaving (nothing to show).
    public var isSilentByDesign: Bool { kind == .cancelled }
}

/// What the system player reported when its item failed, reduced to what the text needs. The app fills this from the
/// error code (the mapping from codes to hints is in the app target, where the codes exist).
public enum PlayerFailureHint: String, Sendable, CaseIterable {
    case formatNotRecognized, decoderMissing, decodeFailed, network, other
}

public enum PlaybackFailures {
    // MARK: Errors thrown on the way to playback

    /// Maps anything thrown while opening or starting a converted playback.
    public static func map(_ error: Error) -> PlaybackFailure {
        if let remux = error as? RemuxError { return map(remux) }
        if let failure = error as? PlaybackFailure { return failure }
        if let url = error as? URLError { return map(url) }
        if error is CancellationError { return cancelled }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain || ns.domain == NSCocoaErrorDomain {
            return readFailed(detail: nil)
        }
        let described = (error as? LocalizedError)?.errorDescription ?? ""
        return PlaybackFailure(kind: .other,
                               message: described.isEmpty ? "The file could not be opened." : described,
                               advice: "Try again. If it keeps failing, check that the file plays from the server.")
    }

    public static func map(_ error: RemuxError) -> PlaybackFailure {
        switch error {
        case .cancelled:
            return cancelled
        case .unsupported(let reason):
            return mapUnsupported(reason)
        case .malformed(let reason):
            if reason.hasPrefix("not an EBML file") || reason.hasPrefix("no Segment element") {
                return PlaybackFailure(kind: .notMatroska,
                                       message: "This file is not a readable MKV file, even though its name says it is.",
                                       advice: "Check that the file opens in another player, or download it again.")
            }
            return damaged
        case .truncated:
            return damaged
        case .notFound:
            return readFailed(detail: nil)
        case .io(let reason):
            if reason.hasPrefix("source did not report a size") { return readFailed(detail: "The server did not say how big the file is.") }
            if reason.hasPrefix("server already started") || reason.contains("socket()") || reason.contains("bind()")
                || reason.contains("listen()") || reason.contains("getsockname()") || reason == "bad URL" {
                return PlaybackFailure(kind: .localServer,
                                       message: "The player could not open its local connection to hand this file to the video decoder.",
                                       advice: "Close the player and try again. If it keeps failing, restart the app.")
            }
            return readFailed(detail: nil)
        case .reorderDepthExceeded:
            return PlaybackFailure(kind: .unsupportedStructure,
                                   message: "The video in this file reorders its frames in a way this player cannot follow yet.",
                                   advice: "Re-encode the video with fewer B-frames, or play the file with another app.")
        }
    }

    public static func map(_ error: URLError) -> PlaybackFailure {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut:
            return readFailed(detail: "The server could not be reached.")
        case .cancelled:
            return cancelled
        default:
            return readFailed(detail: nil)
        }
    }

    /// The system player rejected the item after the converting player handed it over.
    public static func playerFailure(_ hint: PlayerFailureHint) -> PlaybackFailure {
        switch hint {
        case .formatNotRecognized:
            return PlaybackFailure(kind: .playerRejected,
                                   message: "The video decoder did not recognise the stream this player produced from the file.",
                                   advice: "Try another version of this title. Please report this file if it keeps happening.")
        case .decoderMissing:
            return PlaybackFailure(kind: .playerRejected,
                                   message: "This device has no decoder for the video or audio in this file.",
                                   advice: "Try another version of this title, or convert the file to H.264 or HEVC video.")
        case .decodeFailed:
            return PlaybackFailure(kind: .playerRejected,
                                   message: "The video decoder stopped because it could not decode part of this file.",
                                   advice: "Try another version of this title. If the file is damaged, download it again.")
        case .network:
            return readFailed(detail: "The server could not be reached.")
        case .other:
            return PlaybackFailure(kind: .playerRejected,
                                   message: "The video decoder could not play this file.",
                                   advice: "Try again, or try another version of this title.")
        }
    }

    // MARK: Library level failures

    public static let noFile = PlaybackFailure(kind: .noFile, message: "There is no playable file for this title.",
                                               advice: "Rescan the source, or add the title again.")

    public static let sourceGone = PlaybackFailure(kind: .sourceGone,
                                                   message: "The source this file is on is not set up any more.",
                                                   advice: "Add the source again in Settings, then scan it.")

    public static let cancelled = PlaybackFailure(kind: .cancelled, message: "Playback was cancelled.", advice: "")

    public static func readFailed(detail: String?) -> PlaybackFailure {
        PlaybackFailure(kind: .readFailed,
                        message: "The file could not be read from its source." + (detail.map { " " + $0 } ?? ""),
                        advice: "Check that the server is on and reachable, then try again.")
    }

    public static let damaged = PlaybackFailure(kind: .damaged,
                                                message: "This file looks damaged or incomplete, so it cannot be played.",
                                                advice: "Download or copy the file again, or check that it plays in another player.")

    /// A container the converting player does not open (and the system player does not either).
    public static func unsupportedContainer(fileExtension: String) -> PlaybackFailure {
        let shown = fileExtension.isEmpty ? "This file type" : fileExtension.uppercased() + " files"
        return PlaybackFailure(kind: .unsupportedContainer,
                               message: "\(shown) cannot be played yet. This version plays MKV, MP4, M4V and MOV files.",
                               advice: "Convert the file to MKV or MP4 without re-encoding the video, then scan the source again.")
    }

    // MARK: Containers

    /// Extensions the converting player opens (Matroska family). Anything else is refused up front with `unsupportedContainer`.
    public static let remuxExtensions: Set<String> = ["mkv", "mk3d", "webm"]

    public static func canRemux(fileName: String) -> Bool {
        remuxExtensions.contains((fileName as NSString).pathExtension.lowercased())
    }

    // MARK: Engine reasons

    private static func mapUnsupported(_ reason: String) -> PlaybackFailure {
        if reason == "no video track" {
            return PlaybackFailure(kind: .noVideo, message: "This file has no video, so there is nothing to show.",
                                   advice: "If it is a music or audio file, play it from a music app instead.")
        }
        if reason.hasPrefix("video codec ") {
            let id = String(reason.dropFirst("video codec ".count))
            return PlaybackFailure(kind: .unsupportedVideo,
                                   message: "The video in this file uses \(videoCodecName(id)), which this player cannot play yet.",
                                   advice: "Convert the video to H.264 or HEVC, or look for another version of this title.")
        }
        if reason.hasPrefix("laced Matroska block") {
            return PlaybackFailure(kind: .unsupportedLacing,
                                   message: "This file stores its audio in a packed layout (laced blocks without durations) that this player cannot read yet.",
                                   advice: "Re-mux the file with a current MKV tool, or look for another version of this title.")
        }
        if reason.contains("encrypted") {
            return PlaybackFailure(kind: .encrypted, message: "This file is encrypted, so it cannot be played.",
                                   advice: "Use an unencrypted copy of the file.")
        }
        if reason.hasPrefix("Matroska content compression") {
            return PlaybackFailure(kind: .unsupportedCompression,
                                   message: "This file compresses its video or audio in a way this player cannot read yet.",
                                   advice: "Re-mux the file with a current MKV tool, or look for another version of this title.")
        }
        if reason.hasPrefix("unknown-size") || reason.hasPrefix("header element too large") || reason.hasPrefix("seek target size") {
            return PlaybackFailure(kind: .unsupportedStructure,
                                   message: "This file is laid out in a way this player cannot seek in yet, for example a recording that was never finished.",
                                   advice: "Re-mux the file with a current MKV tool, which adds the missing index.")
        }
        if reason.hasPrefix("hvcC") || reason.hasPrefix("avcC") {
            return PlaybackFailure(kind: .unsupportedVideo, message: "The video settings stored in this file are of a kind this player does not understand.",
                                   advice: "Re-mux the file with a current MKV tool, or look for another version of this title.")
        }
        if reason.hasPrefix("AC-3") || reason.hasPrefix("E-AC-3") {
            return PlaybackFailure(kind: .unsupportedStructure, message: "The audio in this file uses a Dolby Digital variant this player cannot play yet.",
                                   advice: "Pick another audio track, or look for another version of this title.")
        }
        return PlaybackFailure(kind: .unsupportedStructure, message: "This file uses a feature this player cannot handle yet.",
                               advice: "Look for another version of this title, or play it with another app.")
    }

    /// "V_MPEG2" becomes "MPEG-2". Unknown ids are shown as written, because naming something wrongly would be worse.
    public static func videoCodecName(_ codecID: String) -> String {
        let id = codecID.uppercased()
        if id.hasPrefix("V_MPEG2") { return "MPEG-2 video" }
        if id.hasPrefix("V_MPEG4/ISO/ASP") || id.hasPrefix("V_MPEG4/ISO/SP") || id.hasPrefix("V_MPEG4/MS") { return "MPEG-4 Part 2 video" }
        if id.hasPrefix("V_MS/VFW/FOURCC") { return "an older Windows video format" }
        if id.hasPrefix("V_VP8") { return "VP8" }
        if id.hasPrefix("V_VP9") { return "VP9" }
        if id.hasPrefix("V_AV1") { return "AV1" }
        if id.hasPrefix("V_THEORA") { return "Theora" }
        if id.hasPrefix("V_REAL") { return "RealVideo" }
        if id.hasPrefix("V_MPEG1") { return "MPEG-1 video" }
        if id.hasPrefix("V_MPEGH/ISO/HEVC") { return "HEVC" }
        if id.hasPrefix("V_MPEG4/ISO/AVC") { return "H.264" }
        if id.hasPrefix("V_PRORES") { return "ProRes" }
        return "the format “\(codecID)”"
    }
}
