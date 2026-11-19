import XCTest
import VideoPlayerCore
@testable import AppLogic

/// #15 Part 2: the Add a Source texts. Synthetic names only.
final class SourceSetupTextTests: XCTestCase {
    func testAMachineIdentifierBecomesAShortNameAndASecondLine() {
        let raw = "sample12-host34-031c37dd-7a8a-4a78-8e42-fd886d39181e-0A1439CCEA74"
        let n = SourceSetupText.discoveredName(raw, kindTitle: "SMB")
        XCTAssertEqual(n.title, "sample12-host34")
        XCTAssertEqual(n.identifier, raw)
    }

    func testAnOrdinaryNameIsKeptWholeAndAnIdentifierAloneGetsTheKind() {
        let plain = SourceSetupText.discoveredName("Sample NAS", kindTitle: "SMB")
        XCTAssertEqual(plain.title, "Sample NAS")
        XCTAssertNil(plain.identifier)
        let bare = SourceSetupText.discoveredName("0A1439CCEA74F00D", kindTitle: "SFTP")
        XCTAssertEqual(bare.title, "SFTP server")
        XCTAssertEqual(bare.identifier, "0A1439CCEA74F00D")
        XCTAssertEqual(SourceSetupText.discoveredName("  ", kindTitle: "FTP").title, "FTP server")
    }

    /// #15 2.2: screenshots 14 and 15 were identical because the test opened SFTP twice (fixed in c14d4cf); the FTP form
    /// itself is its own: title FTP, port 21 and the encryption choice, which SFTP does not have.
    func testTheFTPFormIsNotTheSFTPForm() {
        let ftp = SourceCatalog.info(for: .ftp), sftp = SourceCatalog.info(for: .sftp)
        XCTAssertEqual(ftp.title, "FTP")
        XCTAssertNotEqual(ftp.title, sftp.title)
        XCTAssertTrue(ftp.fields.contains { $0.kind == .security }, "FTP asks for plain or encrypted FTP")
        XCTAssertFalse(sftp.fields.contains { $0.kind == .security })
        XCTAssertEqual(ftp.fields.first { $0.kind == .port }?.prompt, "21")
    }

    /// #25 B1: one short line per type row, and every type's status, caveat or reason on the Learn More page.
    func testEveryTypeHasOneShortRowLineAndItsNotesAreOnLearnMore() {
        let catalog = SourceCatalog.catalog()
        let page = SourceSetupText.learnMore(catalog)
        for info in catalog {
            let line = SourceSetupText.rowLine(info.kind)
            XCTAssertFalse(line.isEmpty)
            XCTAssertLessThanOrEqual(line.count, 30, "one short line: \(line)")
            XCTAssertTrue(page.contains(info.title + "\n"), info.title)
            if let note = info.unavailableNote { XCTAssertTrue(page.contains(note), info.title) }
            else { XCTAssertTrue(page.contains(info.statusLine), info.title) }
            if let caveat = info.caveat { XCTAssertTrue(page.contains(caveat), info.title) }
        }
    }

    /// #25 B1: placeholders short enough to show in full (at most 24 characters).
    func testEveryPlaceholderIsShort() {
        for info in SourceCatalog.catalog() {
            for field in info.fields where field.choices.isEmpty {
                XCTAssertLessThanOrEqual(field.prompt.count, 24, "\(info.title) \(field.title): \(field.prompt)")
            }
        }
    }

    func testEveryTypeHasAShortBadge() {
        for kind in SourceKind.allCases {
            let badge = SourceSetupText.statusBadge(kind)
            XCTAssertFalse(badge.isEmpty)
            XCTAssertLessThanOrEqual(badge.count, 30, "one short badge line (L9): \(badge)")
        }
    }
}
