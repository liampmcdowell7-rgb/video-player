import XCTest
import VideoPlayerCore
@testable import AppLogic

/// R326, R328 (docs/SOURCE_SETUP_DESIGN.md): discovery first on each form, and the search page's footer.
final class SourceDiscoveryTextTests: XCTestCase {
    func testOnlyTypesTheSearchFindsGetTheRow() {
        for kind in [SourceKind.webdav, .smb, .nfs, .sftp, .ftp] {
            XCTAssertTrue(SourceDiscoveryText.searches(kind), "\(kind)")
        }
        XCTAssertFalse(SourceDiscoveryText.searches(.upnp), "the network search does not find UPnP/DLNA devices")
        XCTAssertFalse(SourceDiscoveryText.searches(.directLink))
        for info in SourceCatalog.all where SourceDiscoveryText.searches(info.kind) {
            XCTAssertTrue(info.canDiscover, "\(info.title): the row appears only for a type the catalog says can be found")
        }
    }

    func testShownFiltersByTheFormsType() {
        let smb = DiscoveredSource(kind: .smb, name: "Den", host: "den.local", port: 445)
        let dav = DiscoveredSource(kind: .webdav, name: "Box", host: "box.local")
        XCTAssertEqual(SourceDiscoveryText.shown([smb, dav], kind: nil), [smb, dav])
        XCTAssertEqual(SourceDiscoveryText.shown([smb, dav], kind: .smb), [smb])
        XCTAssertEqual(SourceDiscoveryText.shown([smb, dav], kind: .nfs), [])
    }

    func testFooterSaysWhatIsLookedForThenWhatToDo() {
        let all: String = SourceDiscoveryText.footer(kind: nil, foundAny: false)
        XCTAssertTrue(all.hasPrefix("Looking for WebDAV, SMB, NFS, SFTP and FTP servers on your network."), all)
        XCTAssertTrue(all.contains("UPnP/DLNA"), all)
        XCTAssertEqual(SourceDiscoveryText.footer(kind: .smb, foundAny: false),
                       "Looking for SMB servers on your network. If yours is not listed, go back and type its address.")
        XCTAssertEqual(SourceDiscoveryText.footer(kind: .smb, foundAny: true), "If yours is not listed, go back and type its address.")
        XCTAssertEqual(SourceDiscoveryText.footer(kind: nil, foundAny: true), "If yours is not listed, go back and type its address.")
    }

    func testMergedKeepsWhatTheSearchDoesNotKnow() {
        var typed = SourceDraft(kind: .smb)
        typed[.username] = "guest"
        typed[.share] = "Videos"
        typed[.host] = "old.local"
        let found = DiscoveredSource(kind: .smb, name: "Den NAS", host: "den.local", port: 445)
        let merged: SourceDraft = SourceDiscoveryText.merged(typed, with: found)
        XCTAssertEqual(merged[.host], "den.local", "the found server replaces a typed one")
        XCTAssertEqual(merged[.port], "445")
        XCTAssertEqual(merged[.username], "guest")
        XCTAssertEqual(merged[.share], "Videos")
        XCTAssertEqual(merged[.name], "Den NAS", "no Name typed: the found name")
        typed[.name] = "Study"
        XCTAssertEqual(SourceDiscoveryText.merged(typed, with: found)[.name], "Study", "a typed Name is the person's label")
        XCTAssertEqual(SourceFormText.firstFocus(merged), .connect, "Share filled: everything required is there")
        let fresh: SourceDraft = SourceDiscoveryText.merged(SourceDraft(kind: .smb), with: found)
        XCTAssertEqual(SourceFormText.firstFocus(fresh), .field(.share), "a found SMB server still needs its shared folder")
    }
}
