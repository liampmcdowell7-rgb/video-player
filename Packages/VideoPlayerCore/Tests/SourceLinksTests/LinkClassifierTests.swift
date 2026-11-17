import XCTest
import Foundation
import VideoPlayerCore
@testable import SourceLinks

/// RECORDED-FORMAT TESTS ONLY. The addresses below follow the formats each provider documents or is known to use
/// (written from those formats, not captured from a provider). No provider was contacted, and these tests
/// show that the address is converted as intended, not that the provider then serves the file.
final class LinkClassifierTests: XCTestCase {
    private func classify(_ text: String) -> LinkClassification {
        LinkClassifier.classify(URL(string: text)!)
    }

    func testDirectMediaFiles() {
        for text in ["https://example.com/a/b/Movie.mkv", "http://nas.local:8080/v/clip.MP4?token=abc", "https://x.org/s.srt", "http://10.0.0.2/a%20b.m4v"] {
            let c = classify(text)
            XCTAssertEqual(c.kind, .directMedia, text)
            XCTAssertEqual(c.directURL, URL(string: text), "a direct link is used as it is")
            XCTAssertNil(c.problem)
        }
    }

    func testUnknownAddressIsLeftToTheProbe() {
        let c = classify("https://example.com/download?id=7")
        XCTAssertEqual(c.kind, .unknown)
        XCTAssertEqual(c.directURL?.absoluteString, "https://example.com/download?id=7")
    }

    // MARK: Dropbox (recorded-format only)

    func testDropboxShareBecomesADownload() {
        let cases: [(String, String)] = [
            ("https://www.dropbox.com/s/abc123/Movie.mkv?dl=0", "https://www.dropbox.com/s/abc123/Movie.mkv?dl=1"),
            ("https://www.dropbox.com/s/abc123/Movie.mkv", "https://www.dropbox.com/s/abc123/Movie.mkv?dl=1"),
            ("https://www.dropbox.com/s/abc123/Movie.mkv?raw=1", "https://www.dropbox.com/s/abc123/Movie.mkv?dl=1"),
            ("https://www.dropbox.com/scl/fi/xyz/Movie.mkv?rlkey=KEY&dl=0", "https://www.dropbox.com/scl/fi/xyz/Movie.mkv?rlkey=KEY&dl=1"),
            ("https://dropbox.com/scl/fi/xyz/Movie.mkv?dl=0&rlkey=KEY&st=1", "https://dropbox.com/scl/fi/xyz/Movie.mkv?rlkey=KEY&st=1&dl=1")
        ]
        for (input, expected) in cases {
            let c = classify(input)
            XCTAssertEqual(c.kind, .dropboxShare, input)
            XCTAssertEqual(c.directURL?.absoluteString, expected, input)
            XCTAssertNil(c.problem)
        }
    }

    func testDropboxDirectHostIsKept() {
        let c = classify("https://dl.dropboxusercontent.com/s/abc/Movie.mkv")
        XCTAssertEqual(c.kind, .dropboxShare)
        XCTAssertEqual(c.directURL?.absoluteString, "https://dl.dropboxusercontent.com/s/abc/Movie.mkv")
    }

    func testDropboxFolderIsRefused() {
        for text in ["https://www.dropbox.com/sh/abc/def?dl=0", "https://www.dropbox.com/scl/fo/abc/def?rlkey=k&dl=0"] {
            let c = classify(text)
            XCTAssertNil(c.directURL)
            XCTAssertEqual(c.problem, .folderLink(provider: "Dropbox"), text)
        }
    }

    // MARK: Google Drive (recorded-format only)

    func testGoogleDriveFileLinks() {
        let expected = "https://drive.google.com/uc?export=download&id=1AbCdEfG"
        for text in [
            "https://drive.google.com/file/d/1AbCdEfG/view?usp=sharing",
            "https://drive.google.com/file/d/1AbCdEfG/view",
            "https://drive.google.com/file/u/0/d/1AbCdEfG/edit",
            "https://drive.google.com/open?id=1AbCdEfG",
            "https://drive.google.com/uc?id=1AbCdEfG&export=download"
        ] {
            let c = classify(text)
            XCTAssertEqual(c.kind, .googleDriveFile, text)
            XCTAssertEqual(c.directURL?.absoluteString, expected, text)
            XCTAssertNotNil(c.note, "the large-file confirmation page is mentioned")
        }
    }

    func testGoogleDriveResourceKeyIsKept() {
        let c = classify("https://drive.google.com/file/d/1AbCdEfG/view?resourcekey=0-xyz")
        XCTAssertEqual(c.directURL?.absoluteString, "https://drive.google.com/uc?export=download&id=1AbCdEfG&resourcekey=0-xyz")
    }

    func testGoogleDriveFoldersAndDocsAreRefused() {
        XCTAssertEqual(classify("https://drive.google.com/drive/folders/1AbC?usp=sharing").problem, .folderLink(provider: "Google Drive"))
        XCTAssertEqual(classify("https://drive.google.com/drive/u/0/folders/1AbC").problem, .folderLink(provider: "Google Drive"))
        XCTAssertEqual(classify("https://docs.google.com/document/d/1AbC/edit").problem, .googleDocument)
        XCTAssertNotNil(classify("https://drive.google.com/drive/my-drive").problem)
    }

    // MARK: OneDrive (recorded-format only)

    func testOneDrivePersonalShareUsesTheSharesAPI() throws {
        let input = "https://1drv.ms/v/s!AbCdEf"
        let c = classify(input)
        XCTAssertEqual(c.kind, .oneDriveShare)
        // base64url of the sharing URL, "u!" prefix, no padding
        let encoded = Data(input.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(c.directURL?.absoluteString, "https://api.onedrive.com/v1.0/shares/u!\(encoded)/root/content")
        XCTAssertFalse(encoded.contains("=") || encoded.contains("+") || encoded.contains("/"))
        XCTAssertNotNil(c.note)
        XCTAssertEqual(classify("https://onedrive.live.com/?cid=1&id=2&authkey=k").kind, .oneDriveShare)
    }

    func testOneDriveDownloadLinkIsKept() {
        let c = classify("https://onedrive.live.com/download?cid=ABC&resid=ABC%21123&authkey=K")
        XCTAssertEqual(c.directURL?.absoluteString, "https://onedrive.live.com/download?cid=ABC&resid=ABC%21123&authkey=K")
    }

    func testSharePointGetsDownloadFlagAndAWarning() {
        let c = classify("https://contoso-my.sharepoint.com/:v:/g/personal/me_contoso_com/EabC?e=xyz")
        XCTAssertEqual(c.kind, .oneDriveShare)
        XCTAssertEqual(c.directURL?.absoluteString, "https://contoso-my.sharepoint.com/:v:/g/personal/me_contoso_com/EabC?e=xyz&download=1")
        XCTAssertNotNil(c.note)
    }

    // MARK: iCloud Drive

    func testICloudDriveIsExplainedWithTheWebDAVAlternative() {
        for text in ["https://www.icloud.com/iclouddrive/0abcDEF#Movies", "https://share.icloud.com/photos/xyz", "https://www.icloud.com/shared/abc"] {
            let c = classify(text)
            XCTAssertEqual(c.kind, .iCloudDriveShare, text)
            XCTAssertNil(c.directURL)
            XCTAssertEqual(c.problem, .iCloudDriveShare)
        }
        let message = LinkError.iCloudDriveShare.message
        XCTAssertTrue(message.contains("iCloud Drive"))
        XCTAssertTrue(message.contains("WebDAV"), "points to the WebDAV bridge alternative")
    }

    func testEveryProblemHasAReadableMessage() {
        let all: [LinkError] = [
            .invalidLink, .notWebLink, .credentialsInLink, .duplicate(existingTitle: "A"), .notFound("A"),
            .iCloudDriveShare, .folderLink(provider: "Dropbox"), .googleDocument, .webPage(host: "x.com"), .needsSignIn(provider: "OneDrive")
        ]
        for error in all {
            XCTAssertFalse(error.message.isEmpty)
            XCTAssertEqual(error.errorDescription, error.message)
        }
        XCTAssertTrue(LinkError.needsSignIn(provider: "OneDrive").message.contains("sign-in"))
    }
}

final class LinkStoreTests: XCTestCase {
    func testValidate() throws {
        XCTAssertEqual(try LinkStore.validate("  https://example.com/a.mkv \n").get().absoluteString, "https://example.com/a.mkv")
        XCTAssertEqual(LinkStore.validate("").error, .invalidLink)
        XCTAssertEqual(LinkStore.validate("not a url").error, .invalidLink)
        XCTAssertEqual(LinkStore.validate("example.com/a.mkv").error, .invalidLink)
        XCTAssertEqual(LinkStore.validate("ftp://example.com/a.mkv").error, .notWebLink)
        XCTAssertEqual(LinkStore.validate("file:///etc/passwd").error, .invalidLink)
        XCTAssertEqual(LinkStore.validate("https://user:secret@example.com/a.mkv").error, .credentialsInLink)
        XCTAssertEqual(LinkStore.validate("https://example.com/a b.mkv").error, .invalidLink)
    }

    func testAddNamesAndDeduplicates() throws {
        var store = LinkStore()
        let a = try store.add("https://example.com/v/Movie%20One.mkv")
        XCTAssertEqual(a.title, "Movie One.mkv")
        let b = try store.add("https://other.org/Movie%20One.mkv")
        XCTAssertEqual(b.title, "Movie One (2).mkv")
        let c = try store.add("https://example.com/", title: "  My / Link ")
        XCTAssertEqual(c.title, "My \u{2215} Link")
        XCTAssertEqual(try store.add("https://example.com/other", title: "movie one.mkv").title, "movie one (3).mkv")
        XCTAssertThrowsError(try store.add("HTTPS://EXAMPLE.com/v/Movie%20One.mkv")) {
            XCTAssertEqual($0 as? LinkError, .duplicate(existingTitle: "Movie One.mkv"))
        }
        XCTAssertThrowsError(try store.add("nope")) { XCTAssertEqual($0 as? LinkError, .invalidLink) }
        XCTAssertEqual(store.links.count, 4)
    }

    func testDefaultTitleFallsBackToTheHost() throws {
        var store = LinkStore()
        XCTAssertEqual(try store.add("https://media.example.com/").title, "media.example.com")
    }

    func testRenameAndRemove() throws {
        var store = LinkStore()
        let a = try store.add("https://example.com/a.mkv", title: "A")
        let b = try store.add("https://example.com/b.mkv", title: "B")
        try store.rename(id: a.id, to: "Renamed")
        XCTAssertEqual(store.link(id: a.id)?.title, "Renamed")
        try store.rename(id: b.id, to: "renamed")
        XCTAssertEqual(store.link(id: b.id)?.title, "renamed (2)")
        try store.rename(id: a.id, to: "Renamed")   // its own name is not a clash
        XCTAssertEqual(store.link(id: a.id)?.title, "Renamed")
        try store.rename(id: a.id, to: "   ")       // blank keeps the old name
        XCTAssertEqual(store.link(id: a.id)?.title, "Renamed")
        XCTAssertThrowsError(try store.rename(id: UUID(), to: "x"))
        store.remove(id: a.id)
        XCTAssertNil(store.link(id: a.id))
        XCTAssertEqual(store.link(titled: "RENAMED (2)")?.id, b.id)
        XCTAssertEqual(store.links.count, 1)
    }

    func testJSONRoundTrip() throws {
        var store = LinkStore()
        try store.add("https://example.com/a.mkv?token=T", title: "A")
        try store.add("https://www.dropbox.com/s/x/y.mp4?dl=0")
        let data = try store.encoded()
        let back = try LinkStore.decode(data)
        XCTAssertEqual(back, store)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"urlString\""))
        XCTAssertThrowsError(try LinkStore.decode(Data("{\"links\": 3}".utf8)))
    }
}

private extension Result {
    var error: Failure? { if case .failure(let e) = self { return e } else { return nil } }
}
