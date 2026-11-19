import XCTest
@testable import LibraryIndex
import UserData
@testable import AppLogic

final class SettingsModelTests: XCTestCase {
    private func model(_ account: UDAccountStatus = .available, _ secrets: CloudSecretState = .synced,
                       counts: LibraryCounts? = nil, needed: Int = 0) -> StorageStatusModel {
        StorageStatusModel(account: account, secrets: secrets, counts: counts, passwordsNeeded: needed)
    }

    func testEveryAccountStatusHasItsOwnHonestLine() {
        let lines = [UDAccountStatus.available, .noAccount, .restricted, .unknown].map { model($0).accountLine }
        XCTAssertEqual(Set(lines).count, 4)
        XCTAssertTrue(model(.noAccount).accountLine.contains("this Apple TV only"))
        XCTAssertTrue(model(.available).accountLine.contains("sync"))
        XCTAssertTrue(model(.unknown).accountLine.contains("not known"))
    }

    func testThePasswordLinesComeFromTheSharedStorageText() {
        let m = model(.available, .signedOut)
        XCTAssertEqual(m.passwordsLine, CredentialStorageText.summary(.signedOut))
        XCTAssertEqual(m.resetLine, CredentialStorageText.resetNote)
        XCTAssertTrue(m.resetLine.contains("Resetting"))
    }

    func testPasswordsNeededWordingForNoneOneAndMany() {
        XCTAssertNil(model(needed: 0).passwordsNeededLine)
        XCTAssertEqual(model(needed: 1).passwordsNeededLine, "1 source needs its password again.")
        XCTAssertEqual(model(needed: 3).passwordsNeededLine, "3 sources need their password again.")
    }

    func testTheLibraryLineNeedsCountsAndSaysTheIndexIsRebuildable() throws {
        XCTAssertNil(model().libraryLine)
        let counts = LibraryCounts(items: 12, files: 15, folders: 4, series: 2)
        let line = try XCTUnwrap(model(counts: counts).libraryLine)
        XCTAssertTrue(line.hasPrefix("12 titles in 15 files."))
        XCTAssertTrue(line.contains("rebuilt"))
        XCTAssertTrue(line.contains("watch history is not part of it"))
    }

    func testSettingsKeysAreUniqueAndTheDefaultsAreTheDocumentedOnes() {
        let raws = SettingsKey.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count)
        XCTAssertEqual(SettingsKey.allCases.count, 12)
        for key in SettingsKey.allCases where key != .continueWatchingDays && key != .trueHDCompatibilityCore { XCTAssertTrue(key.defaultBool, key.rawValue) }
        // Quality first: the full TrueHD decode is the default; the Dolby Digital core is an opt-in compatibility setting.
        XCTAssertFalse(SettingsKey.trueHDCompatibilityCore.defaultBool)
        XCTAssertEqual(SettingsKey.defaultContinueWatchingDays, 90)
        XCTAssertTrue(SettingsKey.continueWatchingChoices.contains(SettingsKey.defaultContinueWatchingDays))
        XCTAssertEqual(SettingsKey.continueWatchingChoices, SettingsKey.continueWatchingChoices.sorted())
    }

    /// docs/NAMES.md (2026-11-17): the storage texts name iCloud, the service they are about, instead of a generic
    /// "cloud" or "your account"; and no text claims an endorsement or certification.
    func testTheStorageTextsNameICloudAndClaimNothing() {
        let accounts = [model(.available).accountLine, model(.noAccount).accountLine, model(.restricted).accountLine, model(.unknown).accountLine]
        for text in accounts {
            XCTAssertTrue(text.contains("iCloud"), text)
            XCTAssertFalse(text.contains("Cloud sync") || text.contains("cloud sync"), text)
        }
        XCTAssertTrue(model(.noAccount).accountLine.contains("only"), "signed out keeps everything local")
        for text in accounts + [model().passwordsLine, model().resetLine, AboutText.dataNote] {
            for claim in ["Certified", "Endorsed", "Works with", "Official"] {
                XCTAssertFalse(text.contains(claim), "\(claim) in: \(text)")
            }
        }
    }
}
