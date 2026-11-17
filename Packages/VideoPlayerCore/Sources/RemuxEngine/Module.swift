import Foundation
import VideoPlayerCore

// RemuxEngine: the pure-Swift parts of the remux engine (see docs/ENGINE_DESIGN.md).
//
// What this target is: Matroska index + demux, segmenter, fragmented-MP4 box writer and checker, HEVC SEI / SPS
// parsing, HLS playlist writer, read-ahead planner, seek map, a loopback HTTP server on a POSIX socket, and the
// session that ties them together. It depends on VideoPlayerCore only. FFmpeg is NOT a dependency: anything that
// needs a decoder (DTS / TrueHD to FLAC) sits behind `AudioTranscoding`, and the Dolby Vision profile 7 conversion
// behind `DolbyVisionConverting`; the app target supplies those later.
//
// Everything here was tested in WSL (Linux) only. Nothing has been compiled for tvOS and nothing has been played by
// AVPlayer (docs/DEVICE_TEST_CHECKLIST.md lists what only an Apple TV can check).

public enum RemuxEngineModule { public static let name = "RemuxEngine" }

/// Errors of the engine. Descriptions are short and safe to show in a debug overlay.
public enum RemuxError: Error, Equatable, CustomStringConvertible {
    case truncated(String)
    case malformed(String)
    case unsupported(String)
    case notFound(String)
    case io(String)
    case cancelled
    /// A video track needs more frame reordering than the decode delay the session was given.
    case reorderDepthExceeded(neededTicks: Int64)

    public var description: String {
        switch self {
        case .truncated(let s): return "truncated: \(s)"
        case .malformed(let s): return "malformed: \(s)"
        case .unsupported(let s): return "unsupported: \(s)"
        case .notFound(let s): return "not found: \(s)"
        case .io(let s): return "io: \(s)"
        case .cancelled: return "cancelled"
        case .reorderDepthExceeded(let t): return "reorder depth exceeded by \(t) ticks"
        }
    }
}
