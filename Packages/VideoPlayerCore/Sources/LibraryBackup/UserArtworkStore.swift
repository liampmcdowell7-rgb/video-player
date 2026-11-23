import Foundation

/// R449: the folder of pictures the user chose for titles. A file is named by its content (SHA-256, first 32 hex digits, plus
/// the extension), so the same picture is one file on every Apple TV and in the backup (content addressed like the library
/// backup's chunks), and adding it twice stores it once. It lives in Application Support (never Caches), so a system clean-up
/// does not take it. Names are "useredits/<hash>.<ext>" inside the `userArtwork` set.
public struct UserArtworkStore: Sendable {
    public static let prefix = "useredits"
    public let folder: FolderBackupStore

    public init(root: URL) { folder = FolderBackupStore(root: root, prefix: Self.prefix) }

    /// Stores the picture and returns its file name (without the folder prefix), the value of `UDEditArtwork.file`.
    @discardableResult
    public func add(_ data: Data, fileExtension: String) throws -> String {
        let ext = Self.cleanExtension(fileExtension)
        let name = String(BackupSHA256.hex(data).prefix(32)) + "." + ext
        let full = Self.prefix + "/" + name
        if folder.modified(full) == nil { try folder.write(full, data: data, modified: nil) }
        return name
    }

    public func url(for name: String) -> URL? { folder.url(for: Self.prefix + "/" + name) }

    public func exists(_ name: String) -> Bool { folder.modified(Self.prefix + "/" + name) != nil }

    /// Only a short ASCII extension of letters and digits; anything else is "img".
    static func cleanExtension(_ e: String) -> String {
        let t = e.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return (1...5).contains(t.count) && t.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0)) }) ? t : "img"
    }
}
