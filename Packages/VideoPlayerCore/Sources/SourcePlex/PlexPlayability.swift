import Foundation
import VideoPlayerCore

/// Whether a Plex file can be played without the server converting it (docs/PLEX_SOURCE.md section 5; OPEN_QUESTIONS R305).
///
/// The app plays Plex files the way it plays every other source: MP4, M4V and MOV straight in the system player
/// (direct play, the Part's address with the token in a header), MKV and WebM through the app's own converting player
/// over ranged reads. The server's transcoder is NOT used (R271 keeps it open). A video format the Apple TV cannot decode
/// would need it, so such a file is refused up front with one plain sentence instead of failing inside the player.
///
/// The codec words are the server's `videoCodec` values. Read on the PMS reference (20 Nov 2026): only the sample values
/// ("h264", "hevc") were in the text returned; the other words in `refused` are UNVERIFIED spellings, so an unknown word is
/// never refused (the player gets the file and reports its own error if it cannot play it).
public enum PlexPlayability {
    /// Server codec word -> the name shown in the message.
    public static let refused: [String: String] = [
        "mpeg2video": "MPEG-2 video",
        "mpeg1video": "MPEG-1 video",
        "vc1": "VC-1",
        "wmv1": "an older Windows video format", "wmv2": "an older Windows video format", "wmv3": "an older Windows video format",
        "msmpeg4": "an older Windows video format", "msmpeg4v2": "an older Windows video format", "msmpeg4v3": "an older Windows video format",
        "theora": "Theora",
        "rv40": "RealVideo", "rv30": "RealVideo",
    ]

    /// The name of the video format that would need the server to convert the file, or nil when the app can try it.
    public static func refusal(for media: PlexMedia?) -> String? {
        guard let codec = media?.videoCodec?.lowercased() else { return nil }
        return refused[codec]
    }
}
