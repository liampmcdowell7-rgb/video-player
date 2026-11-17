import Foundation

/// Settings of this build that are not the user's. Nothing here is a secret.
enum SourceConfiguration {
    /// The client ID of the Microsoft app registration for OneDrive. NIL on purpose: nothing has been registered,
    /// and no value is invented. While it is nil that kind stays visible but blocked (SourceCatalog.oneDriveBlockedNote).
    /// To turn it on, register the app with Microsoft (Microsoft Entra app registration) and put the public client ID here (docs/SOURCES_WIRING.md).
    static let oneDriveClientID: String? = nil
}
