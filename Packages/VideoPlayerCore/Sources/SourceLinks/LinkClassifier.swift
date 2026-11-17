import Foundation
import VideoPlayerCore

/// Why a pasted link cannot be played, in words the Settings screen can show as they are.
public enum LinkError: Error, Equatable, Sendable {
    case invalidLink
    case notWebLink
    case credentialsInLink
    case duplicate(existingTitle: String)
    case notFound(String)
    /// An iCloud Drive sharing page. Apple gives no direct file URL for these.
    case iCloudDriveShare
    case folderLink(provider: String)
    case googleDocument
    /// The address answered with a web page instead of the file's bytes.
    case webPage(host: String)
    case needsSignIn(provider: String)
}

extension LinkError: LocalizedError {
    public var errorDescription: String? { message }

    public var message: String {
        switch self {
        case .invalidLink:
            return "That does not look like a web address."
        case .notWebLink:
            return "Only http:// and https:// links can be added."
        case .credentialsInLink:
            return "This link has a user name or password inside it. Remove them from the address; links are saved as plain text."
        case .duplicate(let title):
            return "This link is already in the list as \"\(title)\"."
        case .notFound(let name):
            return "There is no link named \"\(name)\"."
        case .iCloudDriveShare:
            return "This is an iCloud Drive sharing page, not a video file, and Apple offers no direct download address for it. "
                + "To play files from iCloud Drive, put them on a WebDAV server you run (for example an rclone WebDAV bridge to a folder) and add that as a WebDAV source instead."
        case .folderLink(let provider):
            return "This is a \(provider) folder link. A folder cannot be played; share the video file itself, or use a WebDAV bridge to browse folders."
        case .googleDocument:
            return "This is a Google Docs link, not a video file."
        case .webPage(let host):
            return "\(host) answered with a web page instead of the file. The link needs to lead straight to the video file; "
                + "if it is a share page, share the file with a direct download link or use a WebDAV bridge."
        case .needsSignIn(let provider):
            return "\(provider) wants a sign-in for this link, which this source cannot do. Make the file available to anyone with the link, or use a WebDAV bridge."
        }
    }
}

public enum LinkKind: String, Codable, Sendable {
    case directMedia
    case dropboxShare
    case googleDriveFile
    case googleDriveFolder
    case oneDriveShare
    case iCloudDriveShare
    /// Some other web address with no media file extension. Only a probe can tell if it serves bytes.
    case unknown
    case unsupported
}

public struct LinkClassification: Equatable, Sendable {
    public var kind: LinkKind
    /// Where to fetch bytes from (the converted address for share links). Nil when `problem` is set.
    public var directURL: URL?
    public var problem: LinkError?
    /// A caution that does not stop playback, for example "business OneDrive links often need sign-in".
    public var note: String?
}

public enum LinkClassifier {
    public static let mediaExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "mov", "avi", "webm", "ts", "m2ts", "mts", "mpg", "mpeg", "wmv", "flv", "ogv", "3gp",
        "mp3", "m4a", "flac", "aac", "ogg", "opus", "wav", "srt", "ass", "ssa", "vtt", "sub"
    ]

    public static func classify(_ url: URL) -> LinkClassification {
        let host = (url.host ?? "").lowercased()
        func isHost(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        if isHost("dropbox.com") { return dropbox(url, parts: parts) }
        if host == "dl.dropboxusercontent.com" { return direct(.dropboxShare, url) }

        if host == "drive.google.com" { return googleDrive(url, parts: parts) }
        if host == "docs.google.com" { return failure(.unsupported, .googleDocument) }
        if host == "drive.usercontent.google.com", url.path == "/download" { return direct(.googleDriveFile, url) }

        if isHost("icloud.com") { return failure(.iCloudDriveShare, .iCloudDriveShare) }

        if host == "1drv.ms" || host == "onedrive.live.com" || isHost("sharepoint.com") || host == "onedrive.com" {
            return oneDrive(url, host: host)
        }

        let ext = (url.path as NSString).pathExtension.lowercased()
        if mediaExtensions.contains(ext) { return direct(.directMedia, url) }
        return direct(.unknown, url)
    }

    // MARK: Providers

    private static func dropbox(_ url: URL, parts: [String]) -> LinkClassification {
        if parts.first == "sh" || (parts.count >= 2 && parts[0] == "scl" && parts[1] == "fo") {
            return failure(.dropboxShare, .folderLink(provider: "Dropbox"))
        }
        guard parts.first == "s" || (parts.count >= 2 && parts[0] == "scl" && parts[1] == "fi") else {
            return failure(.unsupported, .webPage(host: url.host ?? "dropbox.com"))
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return failure(.unsupported, .invalidLink) }
        var items = (components.queryItems ?? []).filter { $0.name != "dl" && $0.name != "raw" }
        items.append(URLQueryItem(name: "dl", value: "1"))
        components.queryItems = items
        guard let converted = components.url else { return failure(.unsupported, .invalidLink) }
        return LinkClassification(kind: .dropboxShare, directURL: converted, problem: nil, note: nil)
    }

    private static func googleDrive(_ url: URL, parts: [String]) -> LinkClassification {
        if parts.contains("folders") { return failure(.googleDriveFolder, .folderLink(provider: "Google Drive")) }
        var fileID: String?
        if let d = parts.firstIndex(of: "d"), parts.index(after: d) < parts.endIndex, parts.first == "file" {
            fileID = parts[parts.index(after: d)]
        } else if parts.first == "open" || parts.first == "uc" {
            fileID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value
        }
        guard let id = fileID, !id.isEmpty else { return failure(.unsupported, .webPage(host: "drive.google.com")) }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "drive.google.com"
        components.path = "/uc"
        var items = [URLQueryItem(name: "export", value: "download"), URLQueryItem(name: "id", value: id)]
        if let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "resourcekey" })?.value {
            items.append(URLQueryItem(name: "resourcekey", value: key))
        }
        components.queryItems = items
        guard let converted = components.url else { return failure(.unsupported, .invalidLink) }
        return LinkClassification(
            kind: .googleDriveFile, directURL: converted, problem: nil,
            note: "Google shows a confirmation page instead of the file for large files; those cannot be played from a link."
        )
    }

    private static func oneDrive(_ url: URL, host: String) -> LinkClassification {
        if host == "onedrive.live.com", url.path.hasPrefix("/download") { return direct(.oneDriveShare, url) }
        if host == "1drv.ms" || host == "onedrive.live.com" {
            // Public personal shares can be read without signing in through the shares API:
            // the sharing URL is base64url-encoded and prefixed with "u!".
            let encoded = Data(url.absoluteString.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            guard let converted = URL(string: "https://api.onedrive.com/v1.0/shares/u!\(encoded)/root/content") else {
                return failure(.oneDriveShare, .invalidLink)
            }
            return LinkClassification(
                kind: .oneDriveShare, directURL: converted, problem: nil,
                note: "Works only when the link is open to anyone; a link that needs sign-in is reported as needing sign-in."
            )
        }
        // SharePoint / OneDrive for work or school: an "anyone" link downloads with download=1; others need sign-in.
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return failure(.oneDriveShare, .invalidLink) }
        var items = (components.queryItems ?? []).filter { $0.name != "download" }
        items.append(URLQueryItem(name: "download", value: "1"))
        components.queryItems = items
        guard let converted = components.url else { return failure(.oneDriveShare, .invalidLink) }
        return LinkClassification(
            kind: .oneDriveShare, directURL: converted, problem: nil,
            note: "Work and school links usually need sign-in; the app reports that when the server asks for it."
        )
    }

    private static func direct(_ kind: LinkKind, _ url: URL) -> LinkClassification {
        LinkClassification(kind: kind, directURL: url, problem: nil, note: nil)
    }

    private static func failure(_ kind: LinkKind, _ error: LinkError) -> LinkClassification {
        LinkClassification(kind: kind, directURL: nil, problem: error, note: nil)
    }
}
