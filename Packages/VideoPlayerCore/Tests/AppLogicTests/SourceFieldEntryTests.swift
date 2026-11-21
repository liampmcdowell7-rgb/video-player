import XCTest
import VideoPlayerCore
@testable import AppLogic

/// R320 to R325 (docs/SOURCE_SETUP_DESIGN.md): the source forms as tvOS Settings rows.
final class SourceFieldEntryTests: XCTestCase {
    private func spec(_ kind: SourceKind, _ field: SourceFieldKind) -> SourceFieldSpec {
        SourceCatalog.info(for: kind).fields.first { $0.kind == field }!
    }

    // R323: the keyboard of each field.
    func testKeyboardPerField() {
        XCTAssertEqual(SourceFieldEntry.of(spec(.webdav, .address)).keyboard, .url)
        XCTAssertEqual(SourceFieldEntry.of(spec(.webdav, .address)).content, .url)
        XCTAssertEqual(SourceFieldEntry.of(spec(.smb, .host)).keyboard, .url)
        XCTAssertEqual(SourceFieldEntry.of(spec(.smb, .port)).keyboard, .numberPad)
        XCTAssertEqual(SourceFieldEntry.of(spec(.webdav, .username)).content, .username)
        let password = SourceFieldEntry.of(spec(.webdav, .password))
        XCTAssertTrue(password.isSecret)
        XCTAssertEqual(password.content, .password)
        XCTAssertTrue(SourceFieldEntry.of(spec(.webdav, .name)).capitalizesWords)
    }

    /// Nothing but Name capitalises; nothing autocorrects (addresses, user names and folders are not words).
    func testOnlyNameCapitalisesAndNothingAutocorrects() {
        for info in SourceCatalog.all {
            for field in info.fields {
                let entry = SourceFieldEntry.of(field)
                XCTAssertFalse(entry.autocorrects, "\(info.title) \(field.title)")
                XCTAssertEqual(entry.capitalizesWords, field.kind == .name, "\(info.title) \(field.title)")
                XCTAssertEqual(entry.isSecret, field.isSecret, "\(info.title) \(field.title)")
            }
        }
    }

    // R321, R322: the example is the prompt; "Optional" and "Required" never are.
    func testExamplesNeverOptionalOrRequired() {
        XCTAssertEqual(SourceFormText.example(spec(.webdav, .name)), "Living Room")
        XCTAssertEqual(SourceFormText.example(spec(.webdav, .address)), "https://nas.local")
        XCTAssertNil(SourceFormText.example(spec(.webdav, .username)))
        XCTAssertNil(SourceFormText.example(spec(.sftp, .password)))
        XCTAssertNil(SourceFormText.example(spec(.ftp, .security)), "a picker has answers, not an example")
        for info in SourceCatalog.all {
            for field in info.fields {
                if let example = SourceFormText.example(field) {
                    XCTAssertFalse(SourceFormText.notExamples.contains(example), "\(info.title) \(field.title)")
                }
            }
        }
    }

    // R320, R322: an empty row shows nothing; a password shows eight dots and is spoken as "Entered".
    func testRowValues() {
        let name = spec(.webdav, .name), password = spec(.webdav, .password), security = spec(.ftp, .security)
        XCTAssertEqual(SourceFormText.rowValue(name, ""), "")
        XCTAssertEqual(SourceFormText.rowValue(name, "Den"), "Den")
        XCTAssertEqual(SourceFormText.rowValue(password, ""), "")
        XCTAssertEqual(SourceFormText.rowValue(password, "pw"), String(repeating: "\u{2022}", count: 8))
        XCTAssertEqual(SourceFormText.rowValue(password, "a much longer password"), String(repeating: "\u{2022}", count: 8))
        XCTAssertEqual(SourceFormText.spokenValue(password, "pw"), "Entered")
        XCTAssertEqual(SourceFormText.spokenValue(password, ""), "")
        XCTAssertEqual(SourceFormText.rowValue(security, ""), "None (plain FTP)", "an untouched picker shows its default answer")
        XCTAssertEqual(SourceFormText.rowValue(security, "explicit"), "Explicit TLS (FTPS)")
        for info in SourceCatalog.all {
            for field in info.fields where field.choices.isEmpty {
                XCTAssertEqual(SourceFormText.rowValue(field, ""), "", "\(info.title) \(field.title)")
            }
        }
    }

    // R322: the footer names the optional text fields once.
    func testOptionalLine() {
        XCTAssertEqual(SourceFormText.optionalLine(SourceCatalog.info(for: .webdav).fields), "Optional: Name, User Name and Password.")
        XCTAssertEqual(SourceFormText.optionalLine(SourceCatalog.info(for: .smb).fields), "Optional: Name, Port, User Name and Password.")
        XCTAssertEqual(SourceFormText.optionalLine(SourceCatalog.info(for: .ftp).fields),
                       "Optional: Name, Port, Start Folder, User Name and Password.", "the Encryption picker is not listed")
        XCTAssertEqual(SourceFormText.optionalLine(SourceCatalog.info(for: .directLink).fields), "Optional: Name.")
        XCTAssertNil(SourceFormText.optionalLine([]))
        XCTAssertEqual(SourceFormText.joined(["A"]), "A")
        XCTAssertEqual(SourceFormText.joined(["A", "B"]), "A and B")
    }

    // R325: where the focus starts and when it moves to Connect.
    func testFirstFocus() {
        XCTAssertEqual(SourceFormText.firstFocus(SourceDraft(kind: .webdav)), .field(.address), "the first empty required field")
        var filled = SourceDraft(kind: .webdav)
        filled[.address] = "http://nas.local"
        XCTAssertEqual(SourceFormText.firstFocus(filled), .connect)
        var spaces = SourceDraft(kind: .webdav)
        spaces[.address] = "   "
        XCTAssertEqual(SourceFormText.firstFocus(spaces), .field(.address), "spaces are not a value")
        let found = SourceDraft(discovered: DiscoveredSource(kind: .smb, name: "Den NAS", host: "den.local", port: 445))
        XCTAssertEqual(SourceFormText.firstFocus(found), .field(.share), "a found SMB server still needs its shared folder")
        let upnp = SourceDraft(discovered: DiscoveredSource(kind: .upnp, name: "Box", host: "box.local", address: "http://box.local:8200/desc.xml"))
        XCTAssertEqual(SourceFormText.firstFocus(upnp), .connect)
    }

    func testFocusAfterDone() {
        let empty = SourceDraft(kind: .webdav)
        var named = empty
        named[.name] = "Den"
        XCTAssertNil(SourceFormText.focusAfterDone(before: empty, after: named), "an optional field leaves the focus on its row")
        var addressed = named
        addressed[.address] = "http://nas.local"
        XCTAssertEqual(SourceFormText.focusAfterDone(before: named, after: addressed), .connect)
        var renamed = addressed
        renamed[.name] = "Study"
        XCTAssertNil(SourceFormText.focusAfterDone(before: addressed, after: renamed), "already complete: no move")
    }

    func testEntrySummaryNeverSaysOptional() {
        for info in SourceCatalog.all {
            for field in info.fields {
                let summary = SourceFormText.entrySummary(field)
                XCTAssertFalse(summary.contains("Optional"), summary)
                XCTAssertTrue(summary.hasSuffix(" on the keyboard."), summary)
            }
        }
    }
}
