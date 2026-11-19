import Foundation

/// The UserData target: everything that must survive a system cleanup of Caches. See docs/STORAGE_MODEL.md.
public enum UserDataModule {
    public static let name = "UserData"
    /// The CloudKit container (capability in project.yml). Nothing is registered with Apple by this repository.
    public static let cloudKitContainerIdentifier = "iCloud.com.liamp.videoplayer"
    /// The record zone name used inside the private database.
    public static let zoneName = "UserData"
    /// #27 item 1: the zone that holds source passwords and the app-wide API keys (`CloudKitSecretCloud`), one record per
    /// secret, the value in an encrypted field. Never the library zone above, so no key is ever part of the library sync.
    public static let secretsZoneName = "Secrets"
}
