import Foundation

// R390 (owner's device test of 22 Nov 2026: an episode opened to the black player background, nothing appeared, and after
// about 30 seconds the player closed with a "timed out" error; no sound, no picture). A black screen looks the same whether
// the item never became ready, became ready but never showed a frame, or showed one and then stopped. These checkpoints
// say which: each one is marked reached (with the seconds since the start was asked for) or not reached, and the failure
// screen and Settings > Playback > Last Playback Problem show them.

/// One point a start passes on its way to a moving picture, in the order they are reached.
public enum PlaybackCheckpointKind: String, Codable, CaseIterable, Sendable {
    /// Direct: the source gave the file's link. Converted: the converting player read the file's header.
    case fileOpened
    /// Converted only: the loopback server is listening and serves the stream's playlist.
    case loopbackReady
    /// The system player has its item (`AVPlayerItem`) for the file.
    case itemCreated
    /// The item's status became ready to play.
    case itemReady
    /// A video track was found, with its codec and size.
    case videoTrackFound
    /// The first video frame is ready for display (`AVPlayerViewController.isReadyForDisplay`).
    case firstFrame
    /// An enabled audio track while the playhead moves.
    case audioStarted
    /// The playhead moved 5 seconds past where play was asked for.
    case playheadMoved5
    /// The playhead moved 30 seconds past where play was asked for.
    case playheadMoved30

    public var title: String {
        switch self {
        case .fileOpened: return "File Opened"
        case .loopbackReady: return "Loopback Is Ready"
        case .itemCreated: return "Item Created"
        case .itemReady: return "Item Is Ready to Play"
        case .videoTrackFound: return "Video Track Found"
        case .firstFrame: return "First Frame Presented"
        case .audioStarted: return "Audio Started"
        case .playheadMoved5: return "Playhead at +5 s"
        case .playheadMoved30: return "Playhead at +30 s"
        }
    }

    /// True for a checkpoint that only converted playback has.
    public var isConvertedOnly: Bool { self == .loopbackReady }
}

/// Which way the file reaches the system player.
public enum PlaybackPath: String, Codable, Sendable {
    /// The system player opens the source's link itself.
    case direct
    /// The converting player rewrites the file and serves it on a loopback address.
    case converted
    /// The generated sample clip of fixture mode.
    case sample

    public var title: String {
        switch self {
        case .direct: return "Direct"
        case .converted: return "Converted"
        case .sample: return "Sample Clip"
        }
    }
}

/// One checkpoint: reached or not, when, and what was found there.
public struct PlaybackCheckpoint: Codable, Equatable, Sendable {
    public var kind: PlaybackCheckpointKind
    /// Seconds since the start was asked for; nil while not reached.
    public var seconds: Double?
    /// What was found ("HEVC, 3840 × 2160"), nil when there is nothing to add.
    public var detail: String?

    public init(kind: PlaybackCheckpointKind, seconds: Double? = nil, detail: String? = nil) {
        self.kind = kind
        self.seconds = seconds
        self.detail = detail
    }

    public var isReached: Bool { seconds != nil }

    /// "Reached at 2.4 s · HEVC, 3840 × 2160" or "Not reached".
    public var value: String {
        guard let seconds else { return detail.map { "Not reached · " + $0 } ?? "Not reached" }
        let time = "Reached at " + PlaybackCheckpoints.secondsText(seconds)
        return detail.map { time + " · " + $0 } ?? time
    }
}

/// How far a start got, in the three cases the owner must be able to tell apart, plus "playing".
public enum PlaybackStartVerdict: String, Codable, Sendable {
    case neverReady, readyNoFrame, frameThenStopped, playing

    public var text: String {
        switch self {
        case .neverReady: return "The system player never got the file ready to play."
        case .readyNoFrame: return "The file was ready to play, but no picture was ever shown."
        case .frameThenStopped: return "A picture was shown, then playback stopped."
        case .playing: return "Playback was running."
        }
    }
}

/// Every checkpoint of one start, the path, and notes found on the way (a video track the player cannot show, the
/// loopback requests). Codable and kept in `PlaybackProblem`.
public struct PlaybackCheckpoints: Codable, Equatable, Sendable {
    public var path: PlaybackPath?
    public var entries: [PlaybackCheckpoint]
    /// Plain sentences: a video track the player cannot decode, what the loopback served. Newest last.
    public var notes: [String]

    public init(path: PlaybackPath? = nil) {
        self.path = path
        self.entries = PlaybackCheckpointKind.allCases.map { PlaybackCheckpoint(kind: $0) }
        self.notes = []
    }

    /// The most notes kept, so a report stays readable.
    public static let noteCapacity = 20

    /// Marks `kind` reached at `seconds`. The first time counts; a later call only adds a detail that was missing.
    public mutating func reach(_ kind: PlaybackCheckpointKind, at seconds: Double, detail: String? = nil) {
        guard let i = entries.firstIndex(where: { $0.kind == kind }) else { return }
        if entries[i].seconds == nil { entries[i].seconds = max(0, seconds) }
        if entries[i].detail == nil, let detail, !detail.isEmpty { entries[i].detail = detail }
    }

    /// Adds what was found at a checkpoint that was not reached ("no video track in the file").
    public mutating func describe(_ kind: PlaybackCheckpointKind, detail: String) {
        guard let i = entries.firstIndex(where: { $0.kind == kind }), !detail.isEmpty else { return }
        entries[i].detail = detail
    }

    public mutating func note(_ text: String) {
        guard !text.isEmpty, !notes.contains(text) else { return }
        notes.append(text)
        if notes.count > Self.noteCapacity { notes.removeFirst(notes.count - Self.noteCapacity) }
    }

    public func isReached(_ kind: PlaybackCheckpointKind) -> Bool {
        entries.first(where: { $0.kind == kind })?.isReached ?? false
    }

    public func entry(_ kind: PlaybackCheckpointKind) -> PlaybackCheckpoint? { entries.first(where: { $0.kind == kind }) }

    /// The checkpoints that apply to this path (the loopback only in converted playback).
    public var shown: [PlaybackCheckpoint] {
        entries.filter { !$0.kind.isConvertedOnly || path == .converted }
    }

    /// Never ready, ready without a frame, a frame then stopped, or playing. Nil when the player never got the file (the
    /// failure was before the item existed: the step says where).
    public var verdict: PlaybackStartVerdict? {
        guard isReached(.itemCreated) else { return nil }
        guard isReached(.itemReady) else { return .neverReady }
        guard isReached(.firstFrame) else { return .readyNoFrame }
        return isReached(.playheadMoved30) ? .playing : .frameThenStopped
    }

    /// Rows for Settings and the full report: "Path", then one per checkpoint, then the notes.
    public var rows: [(label: String, value: String)] {
        var out: [(label: String, value: String)] = []
        if let path { out.append(("Path", path.title)) }
        if let verdict { out.append(("Start Result", verdict.text)) }
        out += shown.map { ($0.kind.title, $0.value) }
        return out
    }

    /// Short lines for the failure screen: the result, then each checkpoint in one line.
    public var screenLines: [String] {
        var out: [String] = []
        if let verdict { out.append("Result: " + verdict.text) }
        if let path { out.append("Path: " + path.title) }
        out += shown.map { $0.kind.title + ": " + $0.value }
        out += notes.map { "Note: " + $0 }
        return out
    }

    /// Every string passed through `clean` (the redaction of the tracker).
    public func mapped(_ clean: (String) -> String) -> PlaybackCheckpoints {
        var out = self
        for i in out.entries.indices { out.entries[i].detail = out.entries[i].detail.map(clean) }
        out.notes = out.notes.map(clean)
        return out
    }

    /// "2.4 s" (one decimal under 10 s, whole seconds above).
    public static func secondsText(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "?" }
        if seconds < 10 { return String(format: "%.1f s", seconds) }
        return "\(Int(seconds.rounded())) s"
    }

    /// The video track in plain words: codec, size, and when the system says so, that it cannot be decoded or played
    /// here (AVAssetTrack `isDecodable`, `isPlayable`). `codec` is the four-character code or a name.
    public static func videoTrackText(codec: String?, width: Int?, height: Int?, decodable: Bool?, playable: Bool?) -> String {
        var parts: [String] = []
        if let codec, !codec.isEmpty { parts.append(codec) }
        if let width, let height, width > 0, height > 0 { parts.append("\(width) × \(height)") }
        if decodable == false { parts.append("the Apple TV cannot decode this video") }
        if playable == false { parts.append("the system player cannot play this track") }
        return parts.isEmpty ? "No details reported" : parts.joined(separator: ", ")
    }

    /// The codec name for a four-character code, with the code itself for one this list does not name.
    public static func codecName(fourCC: String) -> String {
        switch fourCC {
        case "hvc1", "hev1": return "HEVC (\(fourCC))"
        case "dvh1", "dvhe": return "Dolby Vision HEVC (\(fourCC))"
        case "avc1", "avc3": return "H.264 (\(fourCC))"
        case "dva1", "dvav": return "Dolby Vision H.264 (\(fourCC))"
        case "av01": return "AV1 (av01)" // design-lint:allow a four-character codec code the system reports, not a name
        case "vp09": return "VP9 (vp09)" // design-lint:allow a four-character codec code the system reports, not a name
        case "mp4v": return "MPEG-4 Part 2 (mp4v)" // design-lint:allow a four-character codec code the system reports, not a name
        case "ac-3": return "Dolby Digital (ac-3)" // design-lint:allow a four-character codec code the system reports, not a name
        case "ec-3": return "Dolby Digital Plus (ec-3)" // design-lint:allow a four-character codec code the system reports, not a name
        case "aac ": return "AAC"
        case "fLaC": return "FLAC (fLaC)"
        case "lpcm": return "PCM (lpcm)"
        default: return fourCC.trimmingCharacters(in: .whitespaces).isEmpty ? "Unknown codec" : "Codec \(fourCC)"
        }
    }

    /// The four characters of a FourCC number (`CMFormatDescriptionGetMediaSubType`), "????" for bytes that are not text.
    public static func fourCC(_ code: UInt32) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return "????" }
        return String(decoding: bytes, as: UTF8.self)
    }
}
