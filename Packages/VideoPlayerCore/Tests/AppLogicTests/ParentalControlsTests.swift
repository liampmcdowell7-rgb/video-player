import XCTest
import UserData
import LibraryIndex
@testable import AppLogic

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var now = Date(timeIntervalSince1970: 1_700_000_000)
    func read() -> Date { lock.withLock { now } }
    func advance(_ seconds: TimeInterval) { lock.withLock { now = now.addingTimeInterval(seconds) } }
}

private final class FakePINStore: PINRecordStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var record: PINRecord?
    func load() -> PINRecord? { lock.withLock { record } }
    func save(_ record: PINRecord) throws { lock.withLock { self.record = record } }
    func delete() { lock.withLock { record = nil } }
}

private final class Tick: @unchecked Sendable {
    private let lock = NSLock()
    private var t = 1_700_000_000.0
    func next() -> Date { lock.withLock { t += 1; return Date(timeIntervalSince1970: t) } }
}

/// R459: the rating scales, what a setting allows, the passcode's hash and lockout, and the rule that none of it travels.
/// FIXTURE: invented digits; a fake store stands in for the Keychain; nothing is contacted.
final class ParentalControlsTests: XCTestCase {
    private func make(_ clock: Clock = Clock(), _ store: FakePINStore = FakePINStore()) -> ParentalPIN {
        ParentalPIN(store: store, clock: { clock.read() }, iterations: 20)
    }

    // MARK: Ratings

    func testTheRegionPicksTheRatingSystemAndOtherRegionsUseTheUSOne() {
        XCTAssertEqual(RatingScale.forRegion("GB").region, "GB")
        XCTAssertEqual(RatingScale.forRegion("de").region, "DE")
        XCTAssertEqual(RatingScale.forRegion("BR").region, "US")
        XCTAssertEqual(RatingScale.forRegion(nil).region, "US")
    }

    func testAllowedLabelsAreEveryTierUpToTheChosenOne() {
        let us = RatingScale.us
        XCTAssertEqual(us.allowedMovies(upTo: "PG"), ["G", "PG"])
        XCTAssertEqual(us.allowedMovies(upTo: "PG-13"), ["G", "PG", "PG13"])
        XCTAssertEqual(us.allowedEpisodes(upTo: "TV-14"), ["TVY", "TVY7", "TVY7FV", "TVG", "TVPG", "TV14"])
        XCTAssertEqual(us.allowedMovies(upTo: nil), us.allowedMovies(upTo: "PG-13"), "the default tier")
        XCTAssertEqual(us.allowedMovies(upTo: "nonsense"), us.allowedMovies(upTo: "PG-13"))
        XCTAssertEqual(us.allowedEpisodes(upTo: nil), us.allowedEpisodes(upTo: "TV-14"))
        XCTAssertTrue(RatingScale.gb.allowedMovies(upTo: "12").isSuperset(of: ["U", "PG", "12", "12A"]))
        XCTAssertFalse(RatingScale.gb.allowedMovies(upTo: "12").contains("15"))
        XCTAssertTrue(RatingScale.de.allowedMovies(upTo: "12").isSuperset(of: ["0", "6", "12", "FSK12"]))
        XCTAssertFalse(RatingScale.de.allowedMovies(upTo: "12").contains("16"))
    }

    func testTheRuleExistsOnlyWhileRestrictionsAreOn() {
        XCTAssertNil(ParentalSettings().rule(region: "US"))
        let rule = ParentalSettings(enabled: true, movieTier: "PG", episodeTier: "TV-PG", allowUnrated: true).rule(region: "US")
        XCTAssertEqual(rule?.movieLabels, ["G", "PG"])
        XCTAssertEqual(rule?.episodeLabels, ["TVY", "TVY7", "TVY7FV", "TVG", "TVPG"])
        XCTAssertEqual(rule?.allowUnrated, true)
        XCTAssertEqual(ParentalSettings(enabled: true).rule(region: "US")?.allowUnrated, false, "unrated hidden by default")
    }

    func testRatingTextIsReadTheSameWhateverTheSourceWroteIt() {
        for text in ["PG-13", "Rated PG-13", "US:PG-13", "pg 13", "  PG13 "] {
            XCTAssertEqual(LibraryRestrictions.RatingRule.normalize(text), "PG13", text)
        }
        XCTAssertEqual(LibraryRestrictions.RatingRule.normalize("Unrated"), "UN")
        XCTAssertTrue(LibraryRestrictions.RatingRule.noRating.contains(LibraryRestrictions.RatingRule.normalize("Not Rated")))
        XCTAssertTrue(LibraryRestrictions.RatingRule.noRating.contains(LibraryRestrictions.RatingRule.normalize("Unrated")))
        XCTAssertTrue(LibraryRestrictions.RatingRule.noRating.contains(LibraryRestrictions.RatingRule.normalize(nil)))
    }

    // MARK: Passcode

    func testOnlyFourDigitsAreAPasscode() {
        for good in ["0000", "1234", "9999"] { XCTAssertTrue(ParentalPIN.isValid(good), good) }
        for bad in ["", "123", "12345", "12a4", "١٢٣٤", " 123", "12 4"] { XCTAssertFalse(ParentalPIN.isValid(bad), bad) }
        XCTAssertThrowsError(try make().set("12")) { XCTAssertEqual($0 as? ParentalPIN.PINError, .notFourDigits) }
    }

    func testTheStoredRecordHoldsASaltedHashAndNeverTheDigits() throws {
        let store = FakePINStore()
        let pin = make(Clock(), store)
        try pin.set("4821")
        let record = try XCTUnwrap(store.load())
        XCTAssertEqual(record.salt.count, 32)
        XCTAssertEqual(record.hash.count, 64)
        let text = String(data: try JSONEncoder().encode(record), encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("4821"))
        // A second device or a second set gets another salt, so equal digits give different hashes.
        let other = FakePINStore()
        try make(Clock(), other).set("4821")
        XCTAssertNotEqual(other.load()?.salt, record.salt)
        XCTAssertNotEqual(other.load()?.hash, record.hash)
        XCTAssertEqual(PINHash.hash(pin: "4821", salt: record.salt, iterations: 20), record.hash, "the same input hashes the same")
        XCTAssertNotEqual(PINHash.hash(pin: "4822", salt: record.salt, iterations: 20), record.hash)
    }

    func testTheRightDigitsOpenAndTheWrongOnesCountDown() throws {
        let pin = make()
        XCTAssertEqual(pin.check("1111"), .notSet)
        try pin.set("2468")
        XCTAssertTrue(pin.isSet)
        XCTAssertEqual(pin.check("2468"), .accepted)
        XCTAssertEqual(pin.check("0000"), .wrong(attemptsLeft: 4))
        XCTAssertEqual(pin.check("0001"), .wrong(attemptsLeft: 3))
        XCTAssertEqual(pin.check("2468"), .accepted, "a right entry clears the count")
        XCTAssertEqual(pin.check("0000"), .wrong(attemptsLeft: 4))
    }

    func testFiveWrongTriesLockEntryEvenForTheRightDigitsUntilTheTimeIsUp() throws {
        let clock = Clock()
        let pin = make(clock)
        try pin.set("2468")
        for left in [4, 3, 2, 1] { XCTAssertEqual(pin.check("0000"), .wrong(attemptsLeft: left)) }
        guard case let .locked(until) = pin.check("0000") else { return XCTFail("locked on the fifth") }
        XCTAssertEqual(until.timeIntervalSince(clock.read()), ParentalPIN.lockSeconds, accuracy: 0.5)
        XCTAssertNotNil(pin.lockedUntil())
        XCTAssertEqual(pin.check("2468"), .locked(until: until), "the right digits are not even compared")
        clock.advance(ParentalPIN.lockSeconds - 1)
        XCTAssertEqual(pin.check("2468"), .locked(until: until))
        clock.advance(2)
        XCTAssertNil(pin.lockedUntil())
        XCTAssertEqual(pin.check("2468"), .accepted)
        XCTAssertEqual(ParentalText.locked(until: until, now: until.addingTimeInterval(-290)), "Too many tries. Try again in 5 minutes.")
        XCTAssertEqual(ParentalText.locked(until: until, now: until.addingTimeInterval(-20)), "Too many tries. Try again in 1 minute.")
    }

    func testTheLockSurvivesAnotherObjectOnTheSameStore() throws {
        let clock = Clock(), store = FakePINStore()
        let first = make(clock, store)
        try first.set("2468")
        for _ in 0..<5 { _ = first.check("0000") }
        XCTAssertNotNil(make(clock, store).lockedUntil(), "a new object (a restart) reads the lock from the store")
    }

    func testClearRemovesThePasscode() throws {
        let pin = make()
        try pin.set("2468")
        pin.clear()
        XCTAssertFalse(pin.isSet)
        XCTAssertEqual(pin.check("2468"), .notSet)
    }

    // MARK: Never synced, never backed up

    func testNoParentalKeyIsASyncedSetting() {
        for key in ParentalKeys.all {
            XCTAssertFalse(AppPreference.synced.contains(key), key)
            XCTAssertNil(AppPreference(rawValue: key), key)
        }
        XCTAssertFalse(AppPreference.synced.contains { $0.lowercased().contains("restrict") || $0.lowercased().contains("rating") })
    }

    func testTheRealSyncAndExportCarryNeitherTheSwitchesNorTheRecord() throws {
        let store = FakePINStore()
        let pin = make(Clock(), store)
        try pin.set("4821")
        let record = try XCTUnwrap(store.load())
        let device = UserDefaults(suiteName: "parental-test-\(UUID().uuidString)")!
        device.set(true, forKey: ParentalKeys.enabled)
        device.set("PG", forKey: ParentalKeys.movieTier)
        device.set("4821", forKey: "parentalPIN")   // what a careless future change might do: even then it cannot travel
        device.set(record.hash, forKey: "passcodeHash")
        let stored: (String) -> UDValue? = { key in
            if let b = device.object(forKey: key) as? Bool { return .bool(b) }
            if let s = device.string(forKey: key) { return .string(s) }
            return nil
        }
        let tick = Tick()
        let ledger = UserDataLedger(deviceID: "A", clock: { tick.next() })
        _ = PreferenceSync.push(to: ledger, stored: stored, baseline: PreferenceBaseline())
        XCTAssertTrue(Set(ledger.settingValues().keys).isSubset(of: Set(AppPreference.synced).union([AppPreference.schemaKey])))
        // The user-data export is what the backup and the file export carry.
        let exported = String(data: try UDExport.export(ledger), encoding: .utf8) ?? ""
        for forbidden in [ParentalKeys.enabled, ParentalKeys.movieTier, "parentalPIN", "passcodeHash", record.hash, record.salt, "4821"] {
            XCTAssertFalse(exported.contains(forbidden), forbidden)
        }
        // And the other direction: a record that names those keys sets nothing here.
        XCTAssertTrue(PreferenceSync.importable([ParentalKeys.enabled: .bool(true), "parentalPIN": .string("1234")]).isEmpty)
    }
}
