import Foundation

/// R471 (90), PROVISIONAL: the texts of Settings > Playback > Loopback Requests (the rows come from RemuxEngine's
/// `LoopbackRequestTrail`). Our own wording.
public enum LoopbackRequestsText {
    public static let sectionTitle = "Loopback Requests"
    public static let none = "No converted playback since the app opened."
    public static let footer = "The last 20 requests of the last converted play, newest first: status, time to answer, time since the request before. Kept until the app closes."
}
