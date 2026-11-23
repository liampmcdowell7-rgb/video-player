import XCTest
import Foundation
import UserData
@testable import LibraryBackup

/// R449: the user's own pictures are content addressed, are their own backup set, follow their own switch and come back on an
/// empty Apple TV; a backup of a newer format is not restored.
final class UserArtworkBackupTests: XCTestCase {
    var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("userart-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testAPictureIsNamedByItsContentAndStoredOnce() throws {
        let store = UserArtworkStore(root: dir.appendingPathComponent("art"))
        let a = try store.add(bytes(500, seed: 1), fileExtension: "JPG")
        let b = try store.add(bytes(500, seed: 1), fileExtension: "jpg")
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.hasSuffix(".jpg"))
        XCTAssertEqual(a.count, 32 + 4)
        XCTAssertEqual(store.folder.files().count, 1)
        XCTAssertNotEqual(try store.add(bytes(500, seed: 2), fileExtension: "png"), a)
        XCTAssertTrue(try store.add(bytes(5, seed: 3), fileExtension: "../x").hasSuffix(".img"), "an odd extension becomes img")
        XCTAssertNil(store.url(for: "../../etc/passwd"))
    }

    func testTheSwitchAndTheSetAreSeparateFromArtworkCache() async throws {
        let cloud = InMemoryBackupCloud(), files = MemoryFiles()
        files.put(.userArtwork, "useredits/abc.png", bytes(300, seed: 9))
        files.put(.artwork, "art/cached.jpg", bytes(300, seed: 8))
        let e = BackupEngine(cloud: cloud, content: files, staging: dir.appendingPathComponent("st"), clock: { Date(timeIntervalSince1970: 2_000_000_000) },
                             forbidden: { [] }, sleep: { _ in })
        _ = await e.backUp(settings: BackupSettings(library: false, artwork: false, edits: true))
        let userManifest = try await e.currentManifest(.userArtwork)
        let cacheManifest = try await e.currentManifest(.artwork)
        XCTAssertNotNil(userManifest)
        XCTAssertNil(cacheManifest, "the cache set stayed off")
        files.clear()
        let r = try await e.restore(.userArtwork, into: files, replaceLibrary: false)
        XCTAssertEqual(r.restoredFiles, 1)
        XCTAssertEqual(files.get(.userArtwork, "useredits/abc.png"), bytes(300, seed: 9), "an empty Apple TV gets the picture back")
    }

    func testABackupOfANewerFormatIsNotRestored() async throws {
        let cloud = InMemoryBackupCloud(), files = MemoryFiles()
        files.put(.userArtwork, "useredits/abc.png", bytes(100, seed: 4))
        let e = BackupEngine(cloud: cloud, content: files, staging: dir.appendingPathComponent("st"), clock: { Date(timeIntervalSince1970: 2_000_000_000) },
                             forbidden: { [] }, sleep: { _ in })
        _ = try await e.backUp(.userArtwork)
        var m = try await e.currentManifest(.userArtwork)!
        m.format = BackupFormat.current + 1
        cloud.replaceManifest(.userArtwork, generation: m.generation + 1, data: try m.encoded())
        files.clear()
        do {
            _ = try await e.restore(.userArtwork, into: files, replaceLibrary: false)
            XCTFail("a newer format must not be restored")
        } catch BackupError.newerBackup {}
        XCTAssertNil(files.get(.userArtwork, "useredits/abc.png"))
    }

    func testOldStoredSettingsWithoutTheNewKeyDecodeAsOn() throws {
        let old = Data(#"{"library":true,"artwork":false,"artworkLibraryOnly":false,"userData":true}"#.utf8)
        let s = try JSONDecoder().decode(BackupSettings.self, from: old)
        XCTAssertTrue(s.edits)
        XCTAssertFalse(s.artwork)
    }
}
