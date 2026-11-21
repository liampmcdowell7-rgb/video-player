import Foundation

/// R315: one intro or credits marker a media server keeps for a file (Plex detects them on the server). Times in seconds
/// from the start of the file.
public struct ServerSegmentMarker: Equatable, Sendable {
    /// "intro" or "credits" (other kinds are dropped by the reader).
    public var kind: String
    public var start: TimeInterval
    public var end: TimeInterval
    /// The server says this is the last credits marker (after it only the end of the file).
    public var isFinal: Bool

    public init(kind: String, start: TimeInterval, end: TimeInterval, isFinal: Bool = false) {
        self.kind = kind
        self.start = start
        self.end = end
        self.isFinal = isFinal
    }
}

/// A source whose server keeps intro and credits markers (Plex; R315). The app's segment collector asks it once per
/// playback; it never needs to know which server kind it is. Read only.
public protocol ServerSegmentSource: Sendable {
    /// The markers of the file at `path`, empty when the server has none or does not list the file.
    func serverMarkers(at path: String) async throws -> [ServerSegmentMarker]
}
