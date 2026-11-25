import Foundation
import UserData

/// R471 (20), PROVISIONAL: the words of Play History (ours). Each row: when the playback started (the system's date and time
/// style), and how far it went ("Finished", or "Stopped at 30:30 of 1:40:00").
public enum PlayHistoryText {
    public static let title = "Play History"
    public static let summary = "Each time this title was played, newest first, on this device and your other devices."
    public static let empty = "This title has not been played yet."
    public static let clear = "Clear Play History"
    public static let clearTitle = "Clear Play History?"
    public static let clearMessage = "The list of plays of this title is removed here and on your other devices. Whether it is watched, its progress and its play count stay."

    public static func progress(_ entry: UDPlayRecord) -> String {
        if entry.finished { return "Finished" }
        let at = "Stopped at " + MarkText.clock(entry.position)
        guard let duration = entry.duration, duration > 0 else { return at }
        return at + " of " + MarkText.clock(duration)
    }

    public static func started(_ entry: UDPlayRecord, locale: Locale = .current) -> String {
        entry.startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
    }
}
