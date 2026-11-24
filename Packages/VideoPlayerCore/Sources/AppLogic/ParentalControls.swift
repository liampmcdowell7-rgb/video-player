import Foundation
import LibraryIndex
import LibraryBackup

// R459 (Parental Controls, commit C of R457; PROVISIONAL): the pure part. Which ratings a region has, what a setting allows,
// how the passcode is hashed and checked, and when entry is locked. The library's one rule (`LibraryRestrictions.RatingRule`)
// is built from here; the screens and the Keychain only call this.
//
// What tvOS gives an app for a passcode (Apple's pages, read for this commit): the Keychain stores a small secret
// (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: only while the device is unlocked, and the item does not migrate to
// another device or come back from a backup of another device); the HIG "Entering data" page says to hide secret entry and
// names `TVDigitEntryViewController.isSecureDigitEntry` for digits on tvOS. What tvOS does NOT give an app: the system's own
// Apple TV Restrictions passcode and its content limits are not readable or checkable by an app, so this app keeps its own.

/// The rating system of a region, as ordered tiers from the most to the least restricted.
public struct RatingScale: Equatable, Sendable {
    public struct Tier: Equatable, Sendable {
        public var title: String
        /// The labels this tier adds, as the sources write them (they are normalised when used).
        public var labels: [String]
    }

    public var region: String
    public var movieTiers: [Tier]
    public var episodeTiers: [Tier]
    /// The tiers a setting starts at: one step below the strongest (US films PG-13, US TV TV-14, GB 12, DE 12).
    public var movieDefault: String
    public var episodeDefault: String

    /// US (MPA and TV Parental Guidelines), GB (BBFC), DE (FSK): the systems Online Lookup's region setting names that the app
    /// has labels for. Any other region uses the US scale.
    public static func forRegion(_ code: String?) -> RatingScale {
        switch code?.uppercased() {
        case "GB": return gb
        case "DE": return de
        default: return us
        }
    }

    static let us = RatingScale(
        region: "US",
        movieTiers: [Tier(title: "G", labels: ["G"]), Tier(title: "PG", labels: ["PG"]), Tier(title: "PG-13", labels: ["PG-13"]),
                     Tier(title: "R", labels: ["R"]), Tier(title: "NC-17", labels: ["NC-17"])],
        episodeTiers: [Tier(title: "TV-Y", labels: ["TV-Y"]), Tier(title: "TV-Y7", labels: ["TV-Y7", "TV-Y7-FV"]), Tier(title: "TV-G", labels: ["TV-G"]),
                       Tier(title: "TV-PG", labels: ["TV-PG"]), Tier(title: "TV-14", labels: ["TV-14"]), Tier(title: "TV-MA", labels: ["TV-MA"])],
        movieDefault: "PG-13", episodeDefault: "TV-14")

    static let gb: RatingScale = {
        let tiers = [Tier(title: "U", labels: ["U"]), Tier(title: "PG", labels: ["PG"]), Tier(title: "12", labels: ["12", "12A"]),
                     Tier(title: "15", labels: ["15"]), Tier(title: "18", labels: ["18", "R18"])]
        return RatingScale(region: "GB", movieTiers: tiers, episodeTiers: tiers, movieDefault: "12", episodeDefault: "12")
    }()

    static let de: RatingScale = {
        let tiers = ["0", "6", "12", "16", "18"].map { Tier(title: $0, labels: [$0, "FSK \($0)", "FSK\($0)"]) }
        return RatingScale(region: "DE", movieTiers: tiers, episodeTiers: tiers, movieDefault: "12", episodeDefault: "12")
    }()

    /// The labels (normalised) allowed up to and including the named tier. An unknown or missing name uses the default tier.
    public static func allowed(_ tiers: [Tier], upTo title: String?, defaultTitle: String) -> Set<String> {
        let index = tiers.firstIndex { $0.title == title } ?? tiers.firstIndex { $0.title == defaultTitle } ?? 0
        return Set(tiers[0...index].flatMap(\.labels).map { LibraryRestrictions.RatingRule.normalize($0) })
    }

    public func allowedMovies(upTo title: String?) -> Set<String> { Self.allowed(movieTiers, upTo: title, defaultTitle: movieDefault) }
    public func allowedEpisodes(upTo title: String?) -> Set<String> { Self.allowed(episodeTiers, upTo: title, defaultTitle: episodeDefault) }
}

/// The device-only Parental Controls settings (never part of the synced settings or the backup; see `ParentalKeys`).
public struct ParentalSettings: Equatable, Sendable {
    public var enabled = false
    public var movieTier: String?
    public var episodeTier: String?
    /// Titles with no rating at all. Off: they are hidden while Restrictions are on (PROVISIONAL, R459).
    public var allowUnrated = false

    public init(enabled: Bool = false, movieTier: String? = nil, episodeTier: String? = nil, allowUnrated: Bool = false) {
        self.enabled = enabled
        self.movieTier = movieTier
        self.episodeTier = episodeTier
        self.allowUnrated = allowUnrated
    }

    /// The rule the library applies; nil while Restrictions are off.
    public func rule(region: String?) -> LibraryRestrictions.RatingRule? {
        guard enabled else { return nil }
        let scale = RatingScale.forRegion(region)
        return LibraryRestrictions.RatingRule(movieLabels: scale.allowedMovies(upTo: movieTier),
                                              episodeLabels: scale.allowedEpisodes(upTo: episodeTier),
                                              allowUnrated: allowUnrated)
    }
}

/// UserDefaults keys of the settings above. They are NOT in `AppPreference`, so they are never written to the user data, the
/// sync or the backup: the passcode is only on this device, and a switch that travelled without it would lock a second device.
public enum ParentalKeys {
    public static let enabled = "vp.restrict.on"
    public static let movieTier = "vp.restrict.movie"
    public static let episodeTier = "vp.restrict.episode"
    public static let allowUnrated = "vp.restrict.unrated"
    public static var all: [String] { [enabled, movieTier, episodeTier, allowUnrated] }

    public static func read(_ defaults: UserDefaults = .standard) -> ParentalSettings {
        ParentalSettings(enabled: defaults.bool(forKey: enabled), movieTier: defaults.string(forKey: movieTier),
                         episodeTier: defaults.string(forKey: episodeTier), allowUnrated: defaults.bool(forKey: allowUnrated))
    }
}

// MARK: Passcode

/// What the Keychain holds: the salt, the hash and the lockout count. Never the digits.
public struct PINRecord: Codable, Equatable, Sendable {
    public var salt: String
    public var hash: String
    public var iterations: Int
    public var failures: Int
    /// Seconds since 1970 until which entry is locked.
    public var lockedUntil: Double?
}

/// Where the record lives. The app's implementation is the Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and
/// no synchronisation; tests use a fake.
public protocol PINRecordStoring: Sendable {
    func load() -> PINRecord?
    func save(_ record: PINRecord) throws
    func delete()
}

public enum PINHash {
    public static let iterations = 10_000

    public static func randomSalt<G: RandomNumberGenerator>(using generator: inout G) -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }.joined()
    }

    /// SHA-256 over the salt and the digits, repeated `iterations` times, each round over the last digest and the salt (slows a
    /// guess; the lockout is the main defence, since only four digits exist).
    public static func hash(pin: String, salt: String, iterations: Int = PINHash.iterations) -> String {
        var digest = BackupSHA256.digest(Data((salt + ":" + pin).utf8))
        for _ in 1..<max(1, iterations) { digest = BackupSHA256.digest(Data(digest) + Data(salt.utf8)) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Compares every character, so the time does not say how many were right.
    static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in x.indices { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}

public enum PINCheck: Equatable, Sendable {
    case accepted
    case wrong(attemptsLeft: Int)
    case locked(until: Date)
    case notSet
}

/// The passcode and its lockout. Five wrong tries lock entry for five minutes (PROVISIONAL, R459); a locked entry is not even
/// compared, so waiting is the only way on.
public final class ParentalPIN: @unchecked Sendable {
    public static let length = 4
    public static let maxFailures = 5
    public static let lockSeconds: TimeInterval = 300

    private let store: any PINRecordStoring
    private let clock: @Sendable () -> Date
    private let iterations: Int
    private let lock = NSLock()

    public init(store: any PINRecordStoring, clock: @escaping @Sendable () -> Date = { Date() }, iterations: Int = PINHash.iterations) {
        self.store = store
        self.clock = clock
        self.iterations = iterations
    }

    public static func isValid(_ digits: String) -> Bool {
        digits.count == length && digits.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    public var isSet: Bool { store.load() != nil }

    /// Sets (or changes) the passcode. Not valid digits: nothing is stored.
    public func set(_ digits: String) throws {
        guard Self.isValid(digits) else { throw PINError.notFourDigits }
        var generator = SystemRandomNumberGenerator()
        let salt = PINHash.randomSalt(using: &generator)
        try lock.withLock {
            try store.save(PINRecord(salt: salt, hash: PINHash.hash(pin: digits, salt: salt, iterations: iterations),
                                     iterations: iterations, failures: 0, lockedUntil: nil))
        }
    }

    public func check(_ digits: String) -> PINCheck {
        lock.withLock {
            guard var record = store.load() else { return .notSet }
            let now = clock()
            if let until = record.lockedUntil, until > now.timeIntervalSince1970 { return .locked(until: Date(timeIntervalSince1970: until)) }
            if PINHash.same(PINHash.hash(pin: digits, salt: record.salt, iterations: record.iterations), record.hash) {
                record.failures = 0
                record.lockedUntil = nil
                try? store.save(record)
                return .accepted
            }
            record.failures += 1
            if record.failures >= Self.maxFailures {
                record.failures = 0
                let until = now.addingTimeInterval(Self.lockSeconds)
                record.lockedUntil = until.timeIntervalSince1970
                try? store.save(record)
                return .locked(until: until)
            }
            try? store.save(record)
            return .wrong(attemptsLeft: Self.maxFailures - record.failures)
        }
    }

    /// When entry is locked, until when; nil otherwise.
    public func lockedUntil() -> Date? {
        guard let until = store.load()?.lockedUntil, until > clock().timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: until)
    }

    /// Removes the passcode. The caller has checked the old one first.
    public func clear() { lock.withLock { store.delete() } }

    public enum PINError: Error, Equatable { case notFourDigits }
}

/// The words of the Parental Controls page, in one place so the page and the tests say the same.
public enum ParentalText {
    public static let title = "Parental Controls"
    public static let restrictions = "Restrictions"
    public static let footer = "While on, titles above the allowed ratings are not shown anywhere in the app, and Discover is off. The passcode stays on this device."
    public static let unratedFooter = "Titles with no rating found are hidden unless this is on. Ratings are read from the server or the title's information file."
    public static func locked(until: Date, now: Date = Date()) -> String {
        let minutes = max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
        return "Too many tries. Try again in \(minutes) minute" + (minutes == 1 ? "." : "s.")
    }
}
