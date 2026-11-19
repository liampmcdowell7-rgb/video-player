import Foundation
import MetadataOnline
import UserData

// Online lookup settings: the user's own keys, where they are kept, and the exact words the screens use (docs/ARTWORK_DISCOVER.md).
// Services keep their real names in UI text (user rule of 2026-11-17, replaces R91).

public enum OnlineLookupText {
    public static let settingsTitle = "Online Lookup"

    /// D10 (PROVISIONAL wording, facts read from the request builders on 2026-11-17): what is sent and where, shown above the
    /// key fields. Says the same facts as docs/PRIVACY_POLICY_DRAFT.txt ("Online lookups"). If a request builder changes
    /// (TMDBClient, TMDBDiscover, OMDbClient) or the OMDb key starts being used, this text, the policy draft and
    /// `OnlineKeyTests.testThePlainStatement...` must change together.
    /// Facts: search sends the title (and the year when known); details, seasons, collections, similar titles and
    /// where-to-watch send TMDB's own id for a matched title, season numbers (never episode numbers), and the fixed language
    /// code "en-US" (the device language is not used); an IMDb id from an NFO file next to the video is sent to look the
    /// title up; the region is NOT sent (the reply lists every region, the app keeps one on this device); the OMDb key is
    /// stored but no code path calls OMDb. Needs Review sorting (OnlineSortPass, docs/SORTING.md) sends the parsed title and
    /// year of at most `OnlineSortResolver.perRun` (40) files per launch, only with a TMDB key.
    public static let whatIsSent = "Nothing is sent to any online service until you enter a key below. With a TMDB key, the app sends TMDB the title and year it read from your file and folder names, season numbers, TMDB’s own number for a title it already matched, an IMDb number found in an info file next to your video, the language code en-US and your key. To sort video files that are not clearly a movie or an episode (Needs Review), it also sends TMDB the title and year it read from the file and folder names of at most 40 such files each time the app opens. It uses the answers for pictures, Fix Match, Discover and where to watch. Your where-to-watch region is not sent: the app picks it from the answer on this device. Pictures are downloaded from the addresses TMDB returns. TMDB also sees this device’s network address, like any web service. The OMDb key is saved but this version does not use it yet, so nothing is sent to OMDb. The app sends nothing else."
    public static let keysAreOptional = "Both keys are free from the services themselves. Without them the app still plays everything and uses pictures and details found next to your files."
    public static let storage = "Keys are kept in this device’s protected storage. When you are signed in to iCloud, an encrypted copy is kept in your iCloud account, the same way as source passwords."

    public static let tmdbLabel = "TMDB key"
    public static let omdbLabel = "OMDb key"
    public static let tmdbHelp = "Needed for pictures, Fix Match, Discover and where to watch. Paste the API key or the read access token from your TMDB account settings."
    /// Honest: no code path uses this key yet (no scores are fetched or shown).
    public static let omdbHelp = "Optional. Meant for IMDb, Rotten Tomatoes and Metacritic scores, which this version does not show yet. The key is kept, but nothing is sent to OMDb."
    public static let regionLabel = "Where-to-watch region"
    public static let regionHelp = "A two-letter country code, such as US. Only used on this device to pick which region’s services are listed; it is not sent."

    public static let discoverNeedsKeyTitle = "Discover Needs a Key"
    public static let discoverNeedsKey = "Discover uses your own TMDB key. Enter it in Settings > Online Lookup. Until then nothing is sent anywhere."
    public static let fixMatchNeedsKey = "Fix Match uses your own TMDB key to search. Enter it in Settings > Online Lookup. Until then nothing is sent anywhere."
    public static let keyRejected = "The service did not accept the key. Check it in Settings > Online Lookup."
    public static let removeNote = "Removing a key stops all lookups that need it. Pictures already downloaded stay until the system clears them."

    public static func status(hasTMDB: Bool, hasOMDb: Bool) -> String {
        switch (hasTMDB, hasOMDb) {
        case (false, false): return "Online lookup is off. No keys are entered."
        case (true, false): return "Online lookup is on with a TMDB key."
        case (false, true): return "Only an OMDb key is entered. Pictures, Fix Match and Discover need a TMDB key, so online lookup is off."
        case (true, true): return "Online lookup is on with a TMDB key. The OMDb key is saved but not used yet."
        }
    }
}

public enum OnlineLookupPrefs {
    public static let regionKey = "onlineRegion"
    /// R37: the region defaults to "US". PROVISIONAL; alternative: the device's region.
    public static let defaultRegion = "US"

    /// Two letters A to Z, upper case; anything else gives the default.
    public static func normalizedRegion(_ text: String?) -> String {
        let t = (text ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        return t.count == 2 && t.unicodeScalars.allSatisfy { $0.value >= 65 && $0.value <= 90 } ? t : defaultRegion
    }
}

public enum OnlineKeyKind: String, CaseIterable, Sendable {
    case tmdb, omdb
    /// The id under which the secret is stored (never collides with a source id, which is a UUID).
    public var secretID: String { "online-key." + rawValue }
}

public enum OnlineKeyError: Error, Equatable, Sendable {
    case empty
    case containsSpaces
    case tooLong
}

extension OnlineKeyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .empty: return "Enter a key first."
        case .containsSpaces: return "A key has no spaces or line breaks. Paste it again."
        case .tooLong: return "That is too long to be a key. Paste only the key."
        }
    }
}

/// The user's keys. PROVISIONAL: stored through `MirroredSecrets` (protected local storage plus the encrypted iCloud copy), the
/// same path as source passwords. Alternative: local protected storage only (change `OnlineKeyStore.mirrored` to false).
public struct OnlineKeyStore: Sendable {
    public let secrets: MirroredSecrets
    /// When false the key never goes to the iCloud copy (the local store is used directly).
    public let mirrored: Bool

    public init(secrets: MirroredSecrets, mirrored: Bool = true) {
        self.secrets = secrets
        self.mirrored = mirrored
    }

    public func key(_ kind: OnlineKeyKind) -> String? {
        guard let value = secrets.secret(for: kind.secretID)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    public func has(_ kind: OnlineKeyKind) -> Bool { key(kind) != nil }

    public static func validate(_ raw: String) throws -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw OnlineKeyError.empty }
        guard t.rangeOfCharacter(from: .whitespacesAndNewlines) == nil, t.unicodeScalars.allSatisfy({ $0.value >= 0x21 && $0.value < 0x7F }) else { throw OnlineKeyError.containsSpaces }
        guard t.count <= 2000 else { throw OnlineKeyError.tooLong }
        return t
    }

    @discardableResult
    public func save(_ raw: String, for kind: OnlineKeyKind) async throws -> CloudSecretState {
        let value = try Self.validate(raw)
        if mirrored { return try await secrets.set(value, for: kind.secretID) }
        try secrets.local.setSecret(value, for: kind.secretID)
        return .signedOut
    }

    public func remove(_ kind: OnlineKeyKind) async throws {
        if mirrored { _ = try await secrets.remove(sourceID: kind.secretID) } else { try secrets.local.removeSecret(for: kind.secretID) }
    }

    /// Run at start-up: restores a key from the iCloud copy on a new device and uploads one that is only here.
    public func reconcile() async {
        guard mirrored else { return }
        _ = await secrets.reconcile(sourceIDs: OnlineKeyKind.allCases.map(\.secretID))
    }

    /// "••••1a2b": never the whole key. Keys shorter than 8 characters show only dots.
    public static func masked(_ key: String) -> String {
        guard key.count >= 8 else { return String(repeating: "•", count: max(key.count, 4)) }
        return "••••" + key.suffix(4)
    }

    /// A v4 read access token is a long dotted token; a v3 API key is a short hex string. PROVISIONAL guess by shape.
    public static func tmdbCredentials(_ key: String) -> TMDBCredentials {
        (key.count > 40 || key.contains(".")) ? .readAccessToken(key) : .apiKey(key)
    }
}

/// The watchlist backed by the ledger (synced like every other user record).
public struct LedgerWatchlist: WatchlistStoring {
    public let ledger: UserDataLedger
    public init(ledger: UserDataLedger) { self.ledger = ledger }
    public func entries() -> [UDWatchlistEntry] { ledger.watchlist() }
    public func add(_ entry: UDWatchlistEntry) { ledger.addToWatchlist(entry) }
    public func remove(kind: TitleKind, tmdbID: Int) { ledger.removeFromWatchlist(kind: kind.rawValue, tmdbID: tmdbID) }
}
