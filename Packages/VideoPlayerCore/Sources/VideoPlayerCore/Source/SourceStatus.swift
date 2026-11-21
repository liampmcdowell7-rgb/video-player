import Foundation

/// How far a source has been checked. The Settings screen shows `notVerifiedLabel` for anything
/// below `.realServer`. Update the table below only when a test or device run justifies it.
public enum VerificationLevel: String, Sendable, Codable, Comparable {
    case notVerified        // nothing runs against it yet
    case contractTestsOnly  // recorded responses only, no real server
    case realServer         // integration tests passed against a real server (on Linux)
    case onDevice           // also checked on an Apple TV

    private var rank: Int {
        switch self {
        case .notVerified: return 0
        case .contractTestsOnly: return 1
        case .realServer: return 2
        case .onDevice: return 3
        }
    }
    public static func < (a: VerificationLevel, b: VerificationLevel) -> Bool { a.rank < b.rank }
}

/// Why a source may not be fully available. These are excluded from the release gate and
/// documented with their alternative in docs/SOURCES.md.
public enum SourceLimit: String, Sendable, Codable {
    case none
    /// The platform or the provider does not allow it on a TV (documented alternative exists).
    case platformLimited
    /// Needs an account or registration with a vendor that this project does not use.
    case vendorAccountBlocked
}

public extension SourceKind {
    var verification: VerificationLevel {
        switch self {
        // Linux integration tests against a real server of that kind:
        case .webdav: return .realServer     // rclone
        case .jellyfin: return .realServer   // Jellyfin 12.4.0, 11 live tests
        case .emby: return .realServer       // Emby 4.10.2.0, 11 live tests
        case .ftp: return .realServer        // rclone FTP, 14 live tests (plain FTP only; FTPS untested)
        case .upnp: return .realServer       // rclone DLNA, 10 live tests (one server implementation)
        // Tested only against a stand-in or an unusual server, or not against anything real:
        case .smb: return .contractTestsOnly // impacket (SMB 2.0.2 only) plus a fake; no Samba/Windows
        case .nfs: return .contractTestsOnly // rclone NFS plus real libnfs 5.0.2 on Linux; no NAS, no Apple build
        case .sftp: return .contractTestsOnly // fake backend only; no SSH library chosen yet
        case .directLink: return .contractTestsOnly // direct links live; provider share links recorded-format only
        case .oneDrive: return .contractTestsOnly // hand-written fixtures; Microsoft never contacted
        default: return .notVerified
        }
    }

    var limit: SourceLimit {
        switch self {
        case .dropbox: return .platformLimited      // no TV sign-in exists; use Links or a WebDAV bridge
        case .googleDrive: return .platformLimited  // TV sign-in cannot browse a Drive; shared links only
        case .oneDrive: return .vendorAccountBlocked // client written; needs an app registration (nothing registered)
        default: return .none
        }
    }

    /// Counts toward "every technically possible source type passed its integration tests".
    var gatesPublicRelease: Bool { limit == .none }

    /// Text for the Settings screen. Nil when the source has been checked against a real server.
    var notVerifiedLabel: String? {
        verification >= .realServer ? nil : "Not yet verified against a real server"
    }
}
