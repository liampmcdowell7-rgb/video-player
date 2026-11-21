import XCTest
import VideoPlayerCore
@testable import SourcePlex

/// R315: the server's intro and credits markers, read with one GET of the item's details. The answers are HAND-WRITTEN
/// (the field names are UNVERIFIED, see PlexModels.swift); no server is contacted.
final class PlexMarkerTests: XCTestCase {
    let identity = PlexClientIdentity(clientIdentifier: "install-1234", version: "0.1.0")
    let base = URL(string: "https://192-168-1-20.machine0001.plex.direct:32400")!

    private func client(_ fake: FakePlexServer) -> PlexClient {
        PlexClient(baseURL: base, token: "server-token-placeholder", identity: identity, transport: fake)
    }

    private func pilotPath(_ plex: PlexClient) async throws -> String {
        let items = try await plex.serverItems()
        return try XCTUnwrap(items.first { $0.value.metadata.ratingKey == "3101" }?.key)
    }

    func testIntroAndCreditsMarkersAreReadInSeconds() async throws {
        let fake = try FakePlexServer()
        fake.lists["/library/metadata/3101"] = [[
            "ratingKey": "3101", "type": "episode",
            "Marker": [
                ["id": 1, "type": "intro", "startTimeOffset": 61_000, "endTimeOffset": 112_500],
                ["id": 2, "type": "credits", "startTimeOffset": 2_580_000, "endTimeOffset": 2_700_000, "final": true],
                ["id": 3, "type": "commercial", "startTimeOffset": 900_000, "endTimeOffset": 960_000],
                ["id": 4, "type": "intro"],
            ],
        ]]
        let plex = client(fake)
        let markers = try await plex.serverMarkers(at: try await pilotPath(plex))
        XCTAssertEqual(markers, [ServerSegmentMarker(kind: "intro", start: 61, end: 112.5),
                                 ServerSegmentMarker(kind: "credits", start: 2580, end: 2700, isFinal: true)],
                       "other kinds and markers without times are dropped")
        let request = try XCTUnwrap(fake.requests.last)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.path, "/library/metadata/3101")
        XCTAssertEqual(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "includeMarkers", value: "1")], "the token stays in the header")
        XCTAssertTrue(fake.serverWrites.isEmpty)
    }

    func testAnItemWithoutMarkersGivesNone() async throws {
        let fake = try FakePlexServer()
        fake.lists["/library/metadata/3101"] = [["ratingKey": "3101", "type": "episode"]]
        let plex = client(fake)
        let markers = try await plex.serverMarkers(at: try await pilotPath(plex))
        XCTAssertTrue(markers.isEmpty)
    }

    func testAFileTheServerDoesNotListGivesNoneWithoutARequest() async throws {
        let fake = try FakePlexServer()
        let plex = client(fake)
        let before = fake.requests.count
        _ = try await plex.serverItems()
        let afterTree = fake.requests.count
        XCTAssertGreaterThan(afterTree, before)
        let markers = try await plex.serverMarkers(at: "/TV Shows/Nowhere/S01E01.mkv")
        XCTAssertTrue(markers.isEmpty)
        XCTAssertEqual(fake.requests.count, afterTree)
    }
}
