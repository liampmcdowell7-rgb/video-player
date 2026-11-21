import Foundation
import VideoPlayerCore
@testable import SourcePlex

/// A stand-in for plex.tv and for one Plex Media Server, answering from the HAND-WRITTEN fixtures in Fixtures/ (see its
/// README). It is an `HTTPTransport`, so nothing touches the network. It records every request, so tests can check headers,
/// that no token leaks, and that no write ever reaches the server (R305).
final class FakePlexServer: HTTPTransport, @unchecked Sendable {
    struct NetworkDown: Error, CustomStringConvertible {
        var url: String
        var description: String { "could not connect to \(url)" }
    }

    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []

    // plex.tv
    var accountToken = "account-token-placeholder"
    /// The PIN is claimed after this many polls (nil: never).
    var claimAfterPolls: Int? = 2
    /// Polls after which the PIN is gone (404), the way an expired PIN is assumed to answer (UNVERIFIED).
    var expireAfterPolls: Int?
    var pinExpiresIn: Int? = 900
    private(set) var pinsCreated = 0
    private var polls = 0
    var resourcesData: Data

    // The media server
    var serverToken = "server-token-placeholder"
    /// Hosts that answer; every other host fails like a switched-off machine.
    var reachableHosts: Set<String> = ["192-168-1-20.machine0001.plex.direct", "192.168.1.20"]
    var sections: Data
    /// Metadata answers keyed by path ("/library/sections/1/all", "/library/metadata/3001/allLeaves").
    var lists: [String: [[String: Any]]] = [:]
    var answerWithXML = false
    /// Every Part's bytes: (offset * 7 + 3) mod 251, `partSize` long.
    var partSize: Int64 = 1000
    var rangesSupported = true

    init() throws {
        resourcesData = try Fixture.data("resources.json")
        sections = try Fixture.data("sections.json")
        lists["/library/sections/1/all"] = try Fixture.metadata("section-1-all.json")
        lists["/library/sections/2/all"] = try Fixture.metadata("section-2-all.json")
        lists["/library/metadata/3001/allLeaves"] = try Fixture.metadata("show-3001-leaves.json")
    }

    var requests: [HTTPRequest] { lock.lock(); defer { lock.unlock() }; return recorded }

    /// Requests that would change something on the media server (anything but GET/HEAD to a non-plex.tv host).
    var serverWrites: [HTTPRequest] {
        requests.filter { !Self.isPlexTV($0.url) && !["GET", "HEAD"].contains($0.method) }
    }

    static func isPlexTV(_ url: URL) -> Bool { (url.host ?? "").hasSuffix("plex.tv") }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
        let host = request.url.host ?? ""
        if Self.isPlexTV(request.url) { return plexTV(request) }
        guard reachableHosts.contains(host) else { throw NetworkDown(url: request.url.absoluteString) }
        if request.method != "GET" && request.method != "HEAD" { return HTTPResponse(statusCode: 400) }
        return server(request)
    }

    // MARK: plex.tv

    private func plexTV(_ request: HTTPRequest) -> HTTPResponse {
        let path = request.url.path
        guard request.headers["X-Plex-Client-Identifier"]?.isEmpty == false else { return HTTPResponse(statusCode: 400) }
        if path == "/api/v2/pins", request.method == "POST" {
            pinsCreated += 1
            polls = 0
            return json(["id": 51233 + pinsCreated, "code": "WX\(pinsCreated)Z", "authToken": NSNull(), "expiresIn": pinExpiresIn.map { $0 as Any } ?? NSNull()])
        }
        if path.hasPrefix("/api/v2/pins/"), request.method == "GET" {
            polls += 1
            if let expire = expireAfterPolls, polls >= expire { return HTTPResponse(statusCode: 404) }
            let id = String(path.dropFirst("/api/v2/pins/".count))
            let claimed = claimAfterPolls.map { polls >= $0 } ?? false
            return json(["id": Int(id) ?? 0, "code": "WX\(pinsCreated)Z", "authToken": claimed ? accountToken as Any : NSNull() as Any])
        }
        if path == "/api/v2/resources", request.method == "GET" {
            guard request.headers["X-Plex-Token"] == accountToken else { return HTTPResponse(statusCode: 401) }
            return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: resourcesData)
        }
        return HTTPResponse(statusCode: 404)
    }

    // MARK: Media server

    private func server(_ request: HTTPRequest) -> HTTPResponse {
        let path = request.url.path
        if path == "/identity" { return HTTPResponse(statusCode: 200, body: (try? Fixture.data("identity.json")) ?? Data()) }
        guard request.headers["X-Plex-Token"] == serverToken else { return HTTPResponse(statusCode: 401) }
        if answerWithXML {
            return HTTPResponse(statusCode: 200, headers: ["Content-Type": "text/xml"], body: Data("<MediaContainer size=\"0\"/>".utf8))
        }
        if path == "/library/sections" { return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: sections) }
        if let list = lists[path] { return page(list, request: request) }
        if path.hasPrefix("/library/parts/") { return part(request) }
        // A picture (thumb or art): invented bytes, the same length as a Part (no real image is needed).
        if path.hasPrefix("/library/metadata/"), path.contains("/thumb") || path.contains("/art") {
            return HTTPResponse(statusCode: 200, headers: ["Content-Type": "image/jpeg"], body: Data(Self.bytes(0, Int(partSize))))
        }
        return HTTPResponse(statusCode: 404)
    }

    /// Paging as read on the PMS reference: "Both headers should be sent in order to request paginated content"; without
    /// them some lists "should only return the first 20 Metadata objects" (the fake does that for every list).
    private func page(_ list: [[String: Any]], request: HTTPRequest) -> HTTPResponse {
        let start = Int(request.headers["X-Plex-Container-Start"] ?? "")
        let size = Int(request.headers["X-Plex-Container-Size"] ?? "")
        let (offset, count) = (start != nil && size != nil) ? (start!, size!) : (0, 20)
        let slice = Array(list.dropFirst(offset).prefix(count))
        return json(["MediaContainer": ["size": slice.count, "totalSize": list.count, "offset": offset, "Metadata": slice]])
    }

    private func part(_ request: HTTPRequest) -> HTTPResponse {
        let size = partSize
        guard rangesSupported, let header = request.headers["Range"], header.hasPrefix("bytes=") else {
            return HTTPResponse(statusCode: 200, body: Data(Self.bytes(0, Int(size))))
        }
        let parts = header.dropFirst(6).split(separator: "-").compactMap { Int64($0) }
        guard parts.count == 2, parts[0] < size else { return HTTPResponse(statusCode: 416) }
        let last = min(parts[1], size - 1)
        return HTTPResponse(statusCode: 206, headers: ["Content-Range": "bytes \(parts[0])-\(last)/\(size)"],
                            body: Data(Self.bytes(parts[0], Int(last - parts[0] + 1))))
    }

    static func bytes(_ offset: Int64, _ count: Int) -> [UInt8] {
        (0..<count).map { UInt8(((offset + Int64($0)) * 7 + 3) % 251) }
    }

    private func json(_ object: Any) -> HTTPResponse {
        HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"],
                     body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
    }
}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        return try Data(contentsOf: folder.appendingPathComponent(name))
    }

    static func metadata(_ name: String) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: data(name)) as? [String: Any]
        return ((object?["MediaContainer"] as? [String: Any])?["Metadata"] as? [[String: Any]]) ?? []
    }
}

/// A synthetic movie with one Part, for lists longer than the fixtures (paging tests).
func makeMovie(_ n: Int, container: String = "mkv") -> [String: Any] {
    [
        "ratingKey": String(5000 + n), "type": "movie", "title": "Paged Movie \(n)", "year": 2000 + n % 20,
        "Media": [["container": container, "videoCodec": "h264", "audioCodec": "aac",
                   "Part": [["id": 6000 + n, "key": "/library/parts/\(6000 + n)/1/file.\(container)",
                             "file": "D:\\Media\\Movies\\Paged Movie \(n) (\(2000 + n % 20)).\(container)", "size": 1000, "container": container]]]],
    ]
}
