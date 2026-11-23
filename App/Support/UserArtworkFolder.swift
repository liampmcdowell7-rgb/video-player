import Foundation
import LibraryBackup

/// R449: where the pictures the user chose live. Application Support, never Caches (a system clean-up must not take them);
/// the backup's `userArtwork` set carries them to iCloud.
enum UserArtworkFolder {
    static var root: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("UserArtwork", isDirectory: true)
    }

    static var store: UserArtworkStore { UserArtworkStore(root: root) }

    /// A picture from a typed web address (http or https only, at most 20 MB, an image content type): stored by its content;
    /// returns the file name, or nil with the reason in the second value.
    static func download(_ text: String) async -> (name: String?, problem: String?) {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return (nil, "That is not a web address.")
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else { return (nil, "The server did not return a picture.") }
            guard data.count <= 20_000_000 else { return (nil, "The picture is larger than 20 MB.") }
            let type = response.mimeType ?? ""
            guard type.hasPrefix("image/") else { return (nil, "The address is not a picture.") }
            let ext = type == "image/png" ? "png" : "jpg"
            return (try store.add(data, fileExtension: ext), nil)
        } catch {
            return (nil, "The picture could not be loaded.")
        }
    }
}
