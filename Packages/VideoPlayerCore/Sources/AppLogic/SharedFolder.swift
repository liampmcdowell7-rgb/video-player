import Foundation

/// The App Group folder the app shares with the Top Shelf extension, checked before use (launch safety, docs/API_USAGE.md).
/// Apple's page for `containerURL(forSecurityApplicationGroupIdentifier:)` says the result is nil for a group the app does
/// not belong to (iOS wording; tvOS is not named) and that on macOS a URL is returned even then, so "test that you can access
/// the underlying directory before attempting to use it". Both cases end here as nil: nothing is written, nothing crashes.
public enum SharedFolder {
    public static let appGroup = "group.com.liamp.videoplayer"

    /// `base` when it is (or can be made) a writable folder; nil otherwise.
    public static func usable(_ base: URL?, fileManager: FileManager = .default) -> URL? {
        guard let base, base.isFileURL else { return nil }
        var isFolder: ObjCBool = false
        if !fileManager.fileExists(atPath: base.path, isDirectory: &isFolder) {
            guard (try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)) != nil else { return nil }
            isFolder = true
        }
        guard isFolder.boolValue, fileManager.isWritableFile(atPath: base.path) else { return nil }
        return base
    }
}
