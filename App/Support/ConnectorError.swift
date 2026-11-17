import Foundation

/// Shown when a source type cannot be opened by this version of the app. The text is the whole message.
struct ConnectorError: LocalizedError, Equatable {
    enum Reason: Equatable {
        /// The type needs something this build does not contain (a library for this platform, or an app registration).
        case notIncluded(String)
        /// The saved settings are missing something needed to connect.
        case incomplete(String)
    }
    let kindTitle: String
    let reason: Reason

    var errorDescription: String? {
        switch reason {
        case .notIncluded(let why): return "\(kindTitle) servers cannot be opened by this build. \(why)"
        case .incomplete(let what): return "This \(kindTitle) source is missing \(what). Remove it and add it again."
        }
    }
}
