import XCTest
import Foundation
import VideoPlayerCore
import MetadataOnline
@testable import AppLogic

// Pins the provider notices and ties the Settings "what is sent" text to what the request builders really send.
// The notices live in App/Support/Attribution.swift, which no package target can import, so the test reads that file's text. It is found next to this package (#filePath, as in a checkout) or through
// VP_PROJECT_ROOT (scripts/test-core.sh sets it, because it copies only the package before building).
// FIXTURE: the recording transport below answers every request with 404 and an empty body; nothing is contacted.

final class AttributionNoticeTests: XCTestCase {
    /// The provider's API terms of use, section 3 "Attribution" (https://www.themoviedb.org/api-terms-of-use, last updated
    /// 2023-10-20, read 2026-11-17), with "application" chosen from its "[website, program, service, application, product]".
    static let requiredCatalogueNotice = "This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB."
    /// The watch-provider endpoint page (https://developer.themoviedb.org/reference/movie-watch-providers): the source of the
    /// data must be attributed as JustWatch.
    static let requiredWhereToWatchNotice = "Where-to-watch data is provided by JustWatch."

    private func attributionSource() throws -> String {
        var candidates: [URL] = []
        if let root = ProcessInfo.processInfo.environment["VP_PROJECT_ROOT"], !root.isEmpty {
            candidates.append(URL(fileURLWithPath: root).appendingPathComponent("App/Support/Attribution.swift"))
        }
        // Tests/AppLogicTests/<this file> -> package root -> Packages -> project root
        let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(projectRoot.appendingPathComponent("App/Support/Attribution.swift"))
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return try String(contentsOf: url, encoding: .utf8)
        }
        #if os(Linux)
        XCTFail("App/Support/Attribution.swift not found (tried \(candidates.map(\.path))). Set VP_PROJECT_ROOT to the project folder.")
        return ""
        #else
        // In a tvOS Simulator run the checkout may not be readable (xcodebuild passes only TEST_RUNNER_-prefixed
        // variables to the tests, so CI sets TEST_RUNNER_VP_PROJECT_ROOT). Reported as skipped, never as passed.
        throw XCTSkip("App/Support/Attribution.swift is not readable from this test host (tried \(candidates.map(\.path))).")
        #endif
    }

    /// The string literal assigned to `static let <name>` in the file, or nil.
    private func constant(_ name: String, in text: String) -> String? {
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("static let \(name) = \"") else { continue }
            let rest = t.dropFirst("static let \(name) = \"".count)
            guard let end = rest.lastIndex(of: "\"") else { return nil }
            return String(rest[..<end])
        }
        return nil
    }

    func testTheAppShowsTheCatalogueNoticeWordForWord() throws {
        let text = try attributionSource()
        XCTAssertEqual(constant("catalogueNotice", in: text), Self.requiredCatalogueNotice)
    }

    func testTheAppNamesTheWhereToWatchSource() throws {
        let text = try attributionSource()
        XCTAssertEqual(constant("whereToWatchNotice", in: text), Self.requiredWhereToWatchNotice)
    }

    func testTheScreensReadTheNoticesFromThisFile() throws {
        let text = try attributionSource()
        XCTAssertTrue(text.contains("enum Attribution"))
        XCTAssertNotNil(constant("aboutHeading", in: text))
    }

    func testThePackageCopyMatchesTheAppCopy() throws {
        let text = try attributionSource()
        XCTAssertEqual(MetadataAttribution.tmdbNotice, constant("catalogueNotice", in: text))
        XCTAssertEqual(MetadataAttribution.justWatchNotice, constant("whereToWatchNotice", in: text))
    }

    /// The TMDB logo is the one logo exception (OPEN_QUESTIONS R148) and is shown only by AboutView, so this file, which other
    /// screens also read, must never reference an image.
    func testNoLogoImageIsReferencedInTheAttributionFile() throws {
        let text = try attributionSource()
        XCTAssertFalse(text.contains("Image("))
        XCTAssertFalse(text.contains("UIImage"))
    }

    // MARK: the TMDB logo exception (R148) and the bundled licence texts (R149)

    private func projectRoot() -> URL? {
        var candidates: [URL] = []
        if let root = ProcessInfo.processInfo.environment["VP_PROJECT_ROOT"], !root.isEmpty {
            candidates.append(URL(fileURLWithPath: root))
        }
        candidates.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("App").path) }
    }

    /// The project root, or a failure on Linux / a skip on Apple platforms when the checkout cannot be read (see above).
    private func requireProjectRoot() throws -> URL {
        if let root = projectRoot() { return root }
        #if os(Linux)
        return try XCTUnwrap(projectRoot(), "project root not found; set VP_PROJECT_ROOT")
        #else
        throw XCTSkip("The project checkout is not readable from this test host; set TEST_RUNNER_VP_PROJECT_ROOT.")
        #endif
    }

    private func swiftFiles(under dir: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    func testTheTMDBLogoIsReferencedOnlyOnceAndOnlyInTheAboutScreen() throws {
        let root = try requireProjectRoot()
        var hits: [String] = []
        for dirName in ["App", "TopShelf"] {
            for file in swiftFiles(under: root.appendingPathComponent(dirName)) {
                let text = try String(contentsOf: file, encoding: .utf8)
                let n = text.components(separatedBy: "Image(\"TMDBAttributionLogo\")").count - 1
                for _ in 0..<n { hits.append(file.lastPathComponent) }
            }
        }
        XCTAssertEqual(hits, ["AboutView.swift"])
        let set = root.appendingPathComponent("App/Assets.xcassets/TMDBAttributionLogo.imageset")
        // Hidden files (a Finder .DS_Store in a local checkout) are not part of the asset.
        let files = try FileManager.default.contentsOfDirectory(atPath: set.path).filter { !$0.hasPrefix(".") }.sorted()
        XCTAssertEqual(files, ["Contents.json", "TMDBAttributionLogo.svg"])
    }

    func testEveryBundledLicenceTextExistsAndIsNotEmpty() throws {
        let root = try requireProjectRoot()
        let dir = root.appendingPathComponent("App/Licenses")
        let onDisk = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".txt") })
        let listed = Set(LicenseNotices.texts.map { $0.fileName + ".txt" })
        XCTAssertEqual(onDisk, listed, "every file in App/Licenses is listed, and every listed file exists")
        for name in listed {
            let size = (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(name).path)[.size] as? Int) ?? 0
            XCTAssertGreaterThan(size, 200, name)
        }
        XCTAssertEqual(Set(LicenseNotices.texts.map(\.fileName)).count, LicenseNotices.texts.count)
    }

    func testTheSourceOfferCoversEveryLGPLLibraryWithAVersionAndAnUpstreamLink() {
        let libraries = LicenseNotices.sourceLinks.map(\.library).joined(separator: " | ")
        for name in ["FFmpeg 8.1.3", "libzvbi 0.2.46", "libnfs 5.0.2", "libsmb2", "AMSMB2 4.0.3"] {
            XCTAssertTrue(libraries.contains(name), name)
        }
        for link in LicenseNotices.sourceLinks {
            XCTAssertTrue(link.upstream.hasPrefix("https://github.com/"), link.library)
            XCTAssertTrue(link.upstream.contains("/tree/"), "pinned to an exact tree: \(link.library)")
        }
        XCTAssertTrue(LicenseNotices.sourceOffer.contains("three years"))
        XCTAssertTrue(LicenseNotices.repositoryLine.hasSuffix(LicenseNotices.repositoryURL))
        let lgpl = LicenseNotices.all.filter { $0.license.contains("LGPL") }.map(\.name)
        XCTAssertEqual(lgpl.count, 4, "FFmpeg, libzvbi, libnfs, AMSMB2/libsmb2: \(lgpl)")
    }

    // MARK: artwork quality defaults (R98)

    func testArtworkDefaultsAreTheHighQualityChoices() {
        let builder = ImageURLBuilder()   // the fallback configuration, as used before /configuration is read
        XCTAssertEqual(builder.url(path: "/p.jpg", kind: .poster)?.lastPathComponent, "p.jpg")
        XCTAssertTrue(builder.url(path: "/p.jpg", kind: .poster)?.absoluteString.contains("/w780/") ?? false, "poster at least 640 px wide")
        XCTAssertTrue(builder.url(path: "/b.jpg", kind: .backdrop)?.absoluteString.contains("/original/") ?? false)
        XCTAssertGreaterThanOrEqual(ArtworkEngine.maxSidecarBytes, 3840 * 2160 * 4, "a full 4K RGBA picture next to a video is not skipped")
    }

    // MARK: the "what is sent" facts, checked against the real request builders

    private final class RecordingTransport: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var _urls: [URL] = []
        private var _headers: [[String: String]] = []
        var urls: [URL] { lock.withLock { _urls } }
        var headers: [[String: String]] { lock.withLock { _headers } }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            lock.withLock { _urls.append(request.url); _headers.append(request.headers) }
            return HTTPResponse(statusCode: 404)
        }
    }

    private func query(_ url: URL) -> [String: String] {
        var out: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] { out[item.name] = item.value ?? "" }
        return out
    }

    func testRequestsSendTitleYearSeasonNumberIdsFixedLanguageAndTheKeyButNoRegionAndNoEpisodeNumber() async throws {
        let transport = RecordingTransport()
        // The app builds its client like this (App/Support/OnlineServices.swift): a region is passed, language is left default.
        let client = TMDBClient(credentials: .apiKey("fixture-key"), transport: transport, region: "DE")
        _ = try? await client.searchMovies(query: "Hexfall", year: 1995)
        _ = try? await client.season(seriesID: 1399, number: 2)
        _ = try? await client.watchProviders(kind: .movie, id: 949)
        _ = try? await client.find(imdbID: "tt0113277")
        let urls = transport.urls
        XCTAssertEqual(urls.count, 4)
        guard urls.count == 4 else { return }

        let search = query(urls[0])
        XCTAssertEqual(search["query"], "Hexfall")
        XCTAssertEqual(search["year"], "1995")
        XCTAssertEqual(search["language"], "en-US", "the text says the fixed language code en-US is sent")
        XCTAssertEqual(search["api_key"], "fixture-key")

        XCTAssertTrue(urls[1].path.hasSuffix("/tv/1399/season/2"), urls[1].path)
        XCTAssertFalse(urls[1].path.contains("episode"))
        XCTAssertTrue(urls[2].path.hasSuffix("/movie/949/watch/providers"), urls[2].path)
        XCTAssertTrue(urls[3].path.hasSuffix("/find/tt0113277"), urls[3].path)

        for url in urls {
            let q = query(url)
            XCTAssertNil(q["region"], "the region is not sent: \(url)")
            XCTAssertNil(q["watch_region"], "the region is not sent: \(url)")
            XCTAssertFalse(url.absoluteString.contains("DE"), "the region value is not sent: \(url)")
        }
    }
}
