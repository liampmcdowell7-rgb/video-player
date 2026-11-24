import Foundation

/// R456: Metadata and Artwork > Clear All Metadata. The online data kept on this Apple TV: the answers of the online sources
/// (descriptions, cast, picture lists) and the online pictures. Never the user's own edits and chosen pictures (they live in
/// Application Support and the user layer), never a picture next to the user's files and never the library.
enum OnlineDataCache {
    static var folders: [URL] { [ArtworkFolders.metadata, ArtworkFolders.remote] }

    static func bytes() -> Int64 {
        var total: Int64 = 0
        for folder in folders {
            guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { continue }
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
            }
        }
        return total
    }

    static func clear() {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
    }

    static func sizeText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
