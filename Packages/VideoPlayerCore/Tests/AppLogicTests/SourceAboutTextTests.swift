import XCTest
import VideoPlayerCore
@testable import AppLogic

/// R329 (docs/SOURCE_SETUP_DESIGN.md): one About page per source type.
final class SourceAboutTextTests: XCTestCase {
    func testAvailableTypeSaysWhatWasTestedAndWhatWasNot() {
        let ftp: SourceKindInfo = SourceCatalog.info(for: .ftp)
        XCTAssertEqual(SourceAboutText.title(ftp), "About FTP")
        let sections: [SourceAboutSection] = SourceAboutText.sections(ftp)
        XCTAssertEqual(sections.map(\.header), ["Tested", "Not Tested"])
        XCTAssertEqual(sections[0].text, ftp.statusLine + ".")
        XCTAssertEqual(sections[1].text, ftp.caveat)
        XCTAssertEqual(SourceAboutText.sections(SourceCatalog.info(for: .directLink)).map(\.header), ["Tested"], "no caveat: no section")
    }

    func testUnavailableTypeSaysWhyWithoutTheMachinePrefix() {
        for info in SourceCatalog.all where !info.isAvailable {
            let sections: [SourceAboutSection] = SourceAboutText.sections(info)
            XCTAssertEqual(sections.map(\.header), ["Not Available Yet"], info.title)
            XCTAssertFalse(sections[0].text.hasPrefix("blocked"), sections[0].text)
            XCTAssertEqual(sections[0].text.first.map { String($0) }, sections[0].text.first.map { String($0).uppercased() }, info.title)
        }
        XCTAssertEqual(SourceAboutText.reason("blocked: needs a key."), "Needs a key.")
        XCTAssertEqual(SourceAboutText.reason("Already fine."), "Already fine.")
        XCTAssertEqual(SourceAboutText.reason(""), "")
    }

    /// Nothing is lost against the one-page text it replaces: every type's summary and caveat are on its page.
    func testEveryTypeKeepsItsWords() {
        for info in SourceCatalog.all {
            let page: String = ([info.summary] + SourceAboutText.sections(info).map(\.text)).joined(separator: " ")
            if let caveat = info.caveat, info.isAvailable { XCTAssertTrue(page.contains(caveat), info.title) }
            XCTAssertTrue(page.contains(info.summary), info.title)
        }
    }
}
