import XCTest
import MetadataOnline
import UserData
@testable import AppLogic

// FIXTURE: key values below are placeholder text, not keys. A fake secrets store and a fake cloud are used; nothing is contacted.

final class OnlineKeyStoreTests: XCTestCase {
    private func make(mirrored: Bool = true) -> (OnlineKeyStore, InMemoryCredentialStore, InMemorySecretCloud) {
        let local = InMemoryCredentialStore(), cloud = InMemorySecretCloud()
        return (OnlineKeyStore(secrets: MirroredSecrets(local: local, cloud: cloud), mirrored: mirrored), local, cloud)
    }

    func testNoKeysMeansNoKeys() {
        let (store, _, _) = make()
        XCTAssertNil(store.key(.tmdb))
        XCTAssertFalse(store.has(.omdb))
        XCTAssertEqual(OnlineLookupText.status(hasTMDB: store.has(.tmdb), hasOMDb: store.has(.omdb)), "Online lookup is off. No keys are entered.")
    }

    func testSavingTrimsStoresLocallyAndMirrorsToTheCloudCopy() async throws {
        let (store, local, cloud) = make()
        let state = try await store.save("  abcd1234efgh5678\n", for: .tmdb)
        XCTAssertEqual(state, .synced)
        XCTAssertEqual(store.key(.tmdb), "abcd1234efgh5678")
        XCTAssertEqual(try local.secret(for: "online-key.tmdb"), "abcd1234efgh5678")
        XCTAssertEqual(cloud.snapshot["online-key.tmdb"], "abcd1234efgh5678")
        XCTAssertFalse(store.has(.omdb), "the other key is untouched")
    }

    func testSignedOutOfTheCloudStillKeepsTheKeyOnThisDevice() async throws {
        let (store, _, cloud) = make()
        cloud.setSignedIn(false)
        let state = try await store.save("abcd1234efgh5678", for: .omdb)
        XCTAssertEqual(state, .signedOut)
        XCTAssertEqual(store.key(.omdb), "abcd1234efgh5678")
    }

    func testRemoveDeletesLocalAndCloudCopy() async throws {
        let (store, _, cloud) = make()
        try await store.save("abcd1234efgh5678", for: .tmdb)
        try await store.remove(.tmdb)
        XCTAssertNil(store.key(.tmdb))
        XCTAssertNil(cloud.snapshot["online-key.tmdb"])
    }

    func testLocalOnlyModeNeverTouchesTheCloud() async throws {
        let (store, _, cloud) = make(mirrored: false)
        try await store.save("abcd1234efgh5678", for: .tmdb)
        XCTAssertTrue(cloud.snapshot.isEmpty)
        XCTAssertEqual(store.key(.tmdb), "abcd1234efgh5678")
        try await store.remove(.tmdb)
        XCTAssertNil(store.key(.tmdb))
    }

    func testReconcileRestoresAKeyOnANewDevice() async throws {
        let (first, _, cloud) = make()
        try await first.save("abcd1234efgh5678", for: .tmdb)
        let freshLocal = InMemoryCredentialStore()
        let second = OnlineKeyStore(secrets: MirroredSecrets(local: freshLocal, cloud: cloud))
        XCTAssertNil(second.key(.tmdb))
        await second.reconcile()
        XCTAssertEqual(second.key(.tmdb), "abcd1234efgh5678")
    }

    func testBadInputIsRefusedWithAPlainReasonAndNothingIsStored() async {
        let (store, local, _) = make()
        for (input, expected) in [("   ", OnlineKeyError.empty), ("two words", .containsSpaces), (String(repeating: "x", count: 2001), .tooLong), ("caf\u{E9}key", .containsSpaces)] {
            do { try await store.save(input, for: .tmdb); XCTFail("accepted \(input.count) chars") } catch { XCTAssertEqual(error as? OnlineKeyError, expected) }
        }
        XCTAssertNil(try? local.secret(for: "online-key.tmdb"))
        XCTAssertNotNil(OnlineKeyError.empty.errorDescription)
    }

    func testMaskingNeverShowsTheWholeKey() {
        XCTAssertEqual(OnlineKeyStore.masked("abcd1234efgh5678"), "••••5678")
        XCTAssertEqual(OnlineKeyStore.masked("short"), "•••••")
        XCTAssertFalse(OnlineKeyStore.masked("abcd1234efgh5678").contains("abcd"))
    }

    func testAKeyIsNeverPrintedByTheCredentialDescription() {
        let c = OnlineKeyStore.tmdbCredentials("abcd1234efgh5678abcd1234efgh5678")
        XCTAssertFalse("\(c)".contains("abcd"))
        XCTAssertFalse(String(reflecting: c).contains("abcd"))
    }

    func testAnApiKeyAndAReadTokenAreTellApartByShape() {
        if case .apiKey = OnlineKeyStore.tmdbCredentials("0123456789abcdef0123456789abcdef") {} else { XCTFail("v3 key") }
        if case .readAccessToken = OnlineKeyStore.tmdbCredentials("eyJhbGciOi.eyJzdWIi.sig") {} else { XCTFail("v4 token") }
    }

    func testRegionAcceptsTwoLettersAndFallsBackToUS() {
        XCTAssertEqual(OnlineLookupPrefs.normalizedRegion(" de "), "DE")
        for bad in [nil, "", "USA", "1A", "é"] { XCTAssertEqual(OnlineLookupPrefs.normalizedRegion(bad), "US") }
    }

    func testThePlainStatementSaysWhatIsSentAndThatNothingIsSentBeforeKeys() {
        let text = OnlineLookupText.whatIsSent
        XCTAssertTrue(text.hasPrefix("Nothing is sent to any online service until you enter a key"))
        // The facts the request builders send (TMDBClient / TMDBDiscover), and the facts docs/PRIVACY_POLICY_DRAFT.txt states.
        for needle in ["sends TMDB the title and year", "season numbers", "TMDB’s own number for a title it already matched",
                       "IMDb number found in an info file", "the language code en-US", "and your key",
                       "region is not sent", "nothing is sent to OMDb", "network address", "sends nothing else"] {
            XCTAssertTrue(text.contains(needle), needle)
        }
        // Episode numbers are never sent (the season list comes back whole and the episode is picked on the device), so the
        // text must not claim they are.
        XCTAssertFalse(text.contains("episode numbers"))
        XCTAssertFalse(text.contains("your language setting"), "the language is fixed to en-US in TMDBClient, not the device setting")
    }

    /// Honest states: the OMDb key is stored but never used, and the texts say so.
    func testStatusAndHelpSayTheOMDbKeyIsNotUsedYet() {
        XCTAssertEqual(OnlineLookupText.status(hasTMDB: true, hasOMDb: false), "Online lookup is on with a TMDB key.")
        XCTAssertEqual(OnlineLookupText.status(hasTMDB: false, hasOMDb: true),
                       "Only an OMDb key is entered. Pictures, Fix Match and Discover need a TMDB key, so online lookup is off.")
        XCTAssertEqual(OnlineLookupText.status(hasTMDB: true, hasOMDb: true), "Online lookup is on with a TMDB key. The OMDb key is saved but not used yet.")
        XCTAssertTrue(OnlineLookupText.omdbHelp.contains("nothing is sent to OMDb"))
        XCTAssertFalse(OnlineLookupText.omdbHelp.hasPrefix("Optional. Adds"), "must not claim scores are added")
        XCTAssertTrue(OnlineLookupText.regionHelp.contains("it is not sent"))
    }
}
