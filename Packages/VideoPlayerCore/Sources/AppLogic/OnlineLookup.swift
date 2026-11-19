import Foundation
import MetadataOnline
import UserData

// Online lookup settings: the user's own keys, where they are kept, and the exact words the screens use (docs/ARTWORK_DISCOVER.md).
// Services keep their real names in UI text (user rule of 2026-11-17, replaces R91).

public enum OnlineLookupText {
    public static let settingsTitle = "Online Lookup"

    /// D10 (PROVISIONAL wording, facts read from the request builders on 2026-11-17): what is sent and where, shown above the
    /// key fields. Says the same facts as docs/PRIVACY_POLICY_DRAFT.txt ("Online lookups"). If a request builder changes
    /// (TMDBClient, TMDBDiscover, WikidataClient, IntroDBClient), this text, the policy draft and
    /// `OnlineKeyTests.testThePlainStatement...` must change together.
    /// Facts: search sends the title (and the year when known); details, seasons, collections, similar titles and
    /// where-to-watch send TMDB's own id for a matched title, season numbers (never episode numbers), and the fixed language
    /// code "en-US" (the device language is not used); an IMDb id from an NFO file next to the video is sent to look the
    /// title up; the region is NOT sent (the reply lists every region, the app keeps one on this device). #27: the OMDb key
    /// and client are removed (R211). Needs Review sorting (OnlineSortPass, docs/SORTING.md) sends the parsed title and
    /// year of at most `OnlineSortResolver.perRun` (40) files per launch, only with a TMDB key.
    public static let whatIsSent = "Nothing is sent to any online service until you enter a key or turn on Free Data Sources below. With a TMDB key, the app sends TMDB the title and year it read from your file and folder names, season numbers, TMDB’s own number for a title it already matched, an IMDb number found in an info file next to your video, the language code en-US and your key. To sort video files that are not clearly a movie or an episode (Needs Review), it also sends TMDB the title and year it read from the file and folder names of at most 40 such files each time the app opens. It uses the answers for pictures, Fix Match, Discover and where to watch. Your where-to-watch region is not sent: the app picks it from the answer on this device. Pictures are downloaded from the addresses TMDB returns, including title logos (pictures of a title’s lettering) for the movie and show pages while Show Title Logos is on in Settings > Library. TMDB also sees this device’s network address, like any web service. " + freeSourcesSent + " The app sends nothing else."

    /// #26: what Free Data Sources sends (facts from WikidataClient and IntroDBClient). No key goes to either service.
    public static let freeSourcesSent = "With Free Data Sources on, the app sends Wikidata the title and year it read from your file and folder names, or TMDB’s number for a matched title, to find the cast and the title’s IMDb number. When a video you play has no intro or credits markers of its own, it sends IntroDB that IMDb number with the season and episode number to find where the intro starts. Both services see this device’s network address. No key is sent to them."
    public static let keysAreOptional = "Keys are free from the services themselves. You enter a key once here and it works for every source and library; adding a source never asks for one. Without keys the app still plays everything and uses pictures and details found next to your files."
    public static let storage = "Keys are kept in this device’s protected storage, never in the library backup or the synced library. When you are signed in to iCloud, an encrypted copy is kept in your iCloud account, so another Apple TV signed in to the same account, or this one after a reinstall, gets the key without asking again."

    /// #26 item 3: one row per keyed service, the service's name as text only.
    public static let tmdbLabel = "TMDB"
    public static let keyOn = "On"
    public static let keyNotSet = "Not set"
    public static let enterKey = "Enter Key"
    public static let replaceKey = "Replace Key"
    /// One short footer line per row (rule S1: never cut).
    public static let tmdbHelp = "Pictures, details, Fix Match, Discover and where to watch, for every source."

    /// #26 item 3: Learn More with plain steps, the address as text (no link button, no quotes from TMDB's pages).
    public static let getTMDBKeyTitle = "Get a Free TMDB Key"
    public static let getTMDBKeySteps = """
    1. On a computer or phone, open themoviedb.org and create a free account.
    2. Open your account settings and choose API (www.themoviedb.org/settings/api).
    3. Ask for a developer key for personal use and accept TMDB’s terms of use.
    4. Copy the API key or the API read access token.
    5. Here, under TMDB, choose the key field and type or paste the key.

    The key is yours: it is free for personal, non-commercial use under TMDB’s terms, and you can remove it here at any time.
    """

    /// #26 item 5: Free Data Sources (Wikidata and IntroDB), off until turned on.
    public static let freeSourcesLabel = "Free Data Sources"
    public static let freeSourcesFooter = "Wikidata cast and IntroDB intro times, no key needed. Off: nothing is sent to them."
    public static let freeSourcesTitle = "About Free Data Sources"
    public static let freeSourcesAbout = "Wikidata is a free, open knowledge base; the app takes only facts from it (title, year, cast names and the IMDb number), never pictures. It is used for cast lists when no TMDB key is set, and to find the IMDb number IntroDB needs.\n\nIntroDB is a free, community-made list of where intros, recaps and credits start. The app asks it only for the video you play, and only when the video and its server give no markers of their own. Times it finds for credits are not used, because they cannot be checked against your file’s length.\n\nAnswers are kept on this device (Wikidata 30 days, IntroDB 7 days) so the same question is not asked twice. Neither service gets a key."
    public static let regionLabel = "Where-to-watch region"
    public static let regionHelp = "A two-letter country code, such as US. Only used on this device to pick which region’s services are listed; it is not sent."

    public static let discoverNeedsKeyTitle = "Discover Needs a Key"
    /// #26 item 4: one short line per feature that needs the key, pointing to Settings > Online Lookup.
    public static let discoverNeedsKey = "Discover needs your TMDB key. Add it in Settings > Online Lookup."
    public static let fixMatchNeedsKey = "Fix Match needs your TMDB key. Add it in Settings > Online Lookup."
    public static let detailsNeedKey = "Synopsis needs your TMDB key. Add it in Settings > Online Lookup."
    public static let keyRejected = "The service did not accept the key. Check it in Settings > Online Lookup."
    public static let removeNote = "Removing a key stops all lookups that need it. Pictures already downloaded stay until the system clears them."

    public static func freeSourcesStatus(_ on: Bool) -> String {
        on ? "Free Data Sources are on." : "Free Data Sources are off."
    }

    public static func status(hasTMDB: Bool) -> String {
        hasTMDB ? "Online lookup is on with a TMDB key." : "Online lookup is off. No key is entered."
    }
}

public enum OnlineLookupPrefs {
    public static let regionKey = "onlineRegion"
    /// #26 item 5 (PROVISIONAL, OPEN_QUESTIONS R209): Free Data Sources (Wikidata and IntroDB) are off until the user turns
    /// them on, so "nothing is sent until you set up lookup" stays true. Alternative: on by default. Kept on this device.
    public static let freeSourcesKey = "onlineFreeSources"
    public static let freeSourcesDefault = false
    /// R37: the region defaults to "US". PROVISIONAL; alternative: the device's region.
    public static let defaultRegion = "US"

    /// Two letters A to Z, upper case; anything else gives the default.
    public static func normalizedRegion(_ text: String?) -> String {
        let t = (text ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        return t.count == 2 && t.unicodeScalars.allSatisfy { $0.value >= 65 && $0.value <= 90 } ? t : defaultRegion
    }
}

public enum OnlineKeyKind: String, CaseIterable, Sendable {
    case tmdb
    /// The id under which the secret is stored (never collides with a source id, which is a UUID).
    public var secretID: String { "online-key." + rawValue }
    /// #27 item 3 (R211): keys of services the app no longer uses. Removed once, here, in the iCloud copy and in the old
    /// source-password items, by `OnlineKeyStore.removeRetiredKeys()`.
    public static let retiredSecretIDs = ["online-key.omdb"]
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

/// #26 item 2: the ONE app-wide key store. One item per keyed service (`OnlineKeyKind`), entered once in Settings > Online
/// Lookup and read by every source, library, Discover, artwork and metadata lookup; no source or library has a key of its own.
/// Stored through `MirroredSecrets`: the app's own Keychain items (service "com.liamp.videoplayer.keys", synchronizable flag
/// set; tvOS ignores it, OPEN_QUESTIONS R207) plus the encrypted iCloud copy, which is what restores the key on another Apple TV
/// on the same iCloud account or after a reinstall. Alternative: local protected storage only (`mirrored: false`).
public struct OnlineKeyStore: Sendable {
    public let secrets: MirroredSecrets
    /// When false the key never goes to the iCloud copy (the local store is used directly).
    public let mirrored: Bool
    /// Before #26 the keys sat in the same Keychain items as source passwords; `migrateLegacy()` moves them once.
    public let legacy: (any CredentialStore)?

    public init(secrets: MirroredSecrets, mirrored: Bool = true, legacy: (any CredentialStore)? = nil) {
        self.secrets = secrets
        self.mirrored = mirrored
        self.legacy = legacy
    }

    /// Moves a key stored by an earlier version (in the source-password items) into the key store, then deletes the old item.
    /// A key already in the key store wins. Never throws; a failed move leaves the old item for the next launch.
    @discardableResult
    public func migrateLegacy() -> [OnlineKeyKind] {
        guard let legacy else { return [] }
        var moved: [OnlineKeyKind] = []
        for kind in OnlineKeyKind.allCases {
            guard let old = ((try? legacy.secret(for: kind.secretID)) ?? nil), !old.isEmpty else { continue }
            if key(kind) == nil {
                guard (try? secrets.local.setSecret(old, for: kind.secretID)) != nil else { continue }
                moved.append(kind)
            }
            try? legacy.removeSecret(for: kind.secretID)
        }
        return moved
    }

    /// Every key value this device holds (key store and any not yet migrated), for the backup's forbidden list.
    public func allValues() -> [String] {
        let ids = OnlineKeyKind.allCases.map(\.secretID) + OnlineKeyKind.retiredSecretIDs
        return ids.flatMap { id -> [String] in
            [secrets.secret(for: id), legacy.flatMap { (try? $0.secret(for: id)) ?? nil }].compactMap { $0 }.filter { !$0.isEmpty }
        }
    }

    /// #27 item 3: deletes keys of retired services (OMDb) from this device, the old source-password items and the iCloud
    /// copy. Safe to run every launch; returns the ids that were found here and removed.
    @discardableResult
    public func removeRetiredKeys() async -> [String] {
        var removed: [String] = []
        for id in OnlineKeyKind.retiredSecretIDs {
            let here = secrets.secret(for: id) != nil || ((legacy.flatMap { try? $0.secret(for: id) }) ?? nil) != nil
            try? legacy?.removeSecret(for: id)
            if mirrored { _ = try? await secrets.remove(sourceID: id) } else { try? secrets.local.removeSecret(for: id) }
            if here { removed.append(id) }
        }
        return removed
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
        migrateLegacy()
        await removeRetiredKeys()
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
