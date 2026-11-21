import Foundation
import XCTest
import VideoPlayerCore
@testable import SourceJellyfin

/// A stand-in for the server's HTTP API. It answers with the responses recorded from a real
/// Jellyfin 12.4 server (Fixtures/) and follows the same rules for tokens, paging and ranges.
final class FakeJellyfinServer: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []

    var items: [[String: Any]]
    var foldersData: Data
    var foldersStatus = 200
    /// R374: fields only the single-item endpoint returns (keyed by item id), as the docs say list queries are minimal.
    var fullItemFields: [String: [String: Any]] = [:]
    var password = "testpass-local"
    /// Counts returned for `Limit=0` requests, one per request; the last one repeats.
    var countSequence: [Int]?
    private var countCalls = 0
    private(set) var logins = 0
    private(set) var validToken: String

    init(items: [[String: Any]]? = nil, folders: Data? = nil, token: String = "good-token") throws {
        self.items = try items ?? FakeJellyfinServer.fixtureItems()
        self.foldersData = try folders ?? Fixture.data("virtual-folders.json")
        self.validToken = token
    }

    static func fixtureItems() throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: Fixture.data("items.json")) as? [String: Any]
        return (object?["Items"] as? [[String: Any]]) ?? []
    }

    var requests: [HTTPRequest] { lock.lock(); defer { lock.unlock() }; return recorded }

    func revokeToken() { lock.lock(); validToken = "revoked-\(UUID().uuidString)"; lock.unlock() }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
        return handle(request)
    }

    private func handle(_ request: HTTPRequest) -> HTTPResponse {
        let path = request.url.path
        let query = Dictionary(
            uniqueKeysWithValues: (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .map { ($0.name, $0.value ?? "") })

        if path.hasSuffix("/Users/AuthenticateByName") {
            let body = (try? JSONSerialization.jsonObject(with: request.body ?? Data())) as? [String: String]
            guard body?["Pw"] == password else { return HTTPResponse(statusCode: 401) }
            logins += 1
            validToken = "token-\(logins)"
            let text = String(decoding: (try? Fixture.data("authenticate.json")) ?? Data(), as: UTF8.self)
                .replacingOccurrences(of: "REDACTED-TOKEN", with: validToken)
            return HTTPResponse(statusCode: 200, body: Data(text.utf8))
        }
        guard tokenOf(request) == validToken else { return HTTPResponse(statusCode: 401) }

        if path.hasSuffix("/Library/VirtualFolders") {
            return HTTPResponse(statusCode: foldersStatus, body: foldersStatus == 200 ? foldersData : Data())
        }
        if let range = path.range(of: "/Items/"), true {
            let id = String(path[range.upperBound...])
            guard !id.contains("/"), var item = items.first(where: { ($0["Id"] as? String) == id }) else {
                return HTTPResponse(statusCode: 404)
            }
            item.merge(fullItemFields[id] ?? [:]) { _, full in full }
            return json(item)
        }
        if path.hasSuffix("/Items") {
            if query["Limit"] == "0" {
                let total = countSequence.map { $0[min(countCalls, $0.count - 1)] } ?? items.count
                countCalls += 1
                return json(["Items": [], "TotalRecordCount": total, "StartIndex": 0])
            }
            let start = Int(query["StartIndex"] ?? "0") ?? 0
            let limit = Int(query["Limit"] ?? "") ?? items.count
            let slice = Array(items.dropFirst(start).prefix(limit))
            return json(["Items": slice, "TotalRecordCount": items.count, "StartIndex": start])
        }
        if path.contains("/Videos/"), path.hasSuffix("/stream") {
            return stream(request, query: query)
        }
        return HTTPResponse(statusCode: 404)
    }

    /// Every file is `size` bytes long and holds byte (offset * 7 + 3) mod 251 at each offset.
    static let fileSize: Int64 = 1000

    private func stream(_ request: HTTPRequest, query: [String: String]) -> HTTPResponse {
        guard query["static"] == "true" else { return HTTPResponse(statusCode: 400) }
        let size = FakeJellyfinServer.fileSize
        guard let header = request.headers["Range"], header.hasPrefix("bytes=") else {
            return HTTPResponse(statusCode: 200, body: Data(FakeJellyfinServer.bytes(0, Int(size))))
        }
        let parts = header.dropFirst(6).split(separator: "-").compactMap { Int64($0) }
        guard parts.count == 2, parts[0] < size else { return HTTPResponse(statusCode: 416) }
        let last = min(parts[1], size - 1)
        return HTTPResponse(
            statusCode: 206, headers: ["Content-Range": "bytes \(parts[0])-\(last)/\(size)"],
            body: Data(FakeJellyfinServer.bytes(parts[0], Int(last - parts[0] + 1))))
    }

    static func bytes(_ offset: Int64, _ count: Int) -> [UInt8] {
        (0..<count).map { UInt8(((offset + Int64($0)) * 7 + 3) % 251) }
    }

    private func json(_ object: Any) -> HTTPResponse {
        HTTPResponse(statusCode: 200, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
    }

    private func tokenOf(_ request: HTTPRequest) -> String? {
        guard let value = request.headers["Authorization"], let range = value.range(of: "Token=\"") else { return nil }
        return value[range.upperBound...].split(separator: "\"").first.map(String.init)
    }
}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        return try Data(contentsOf: folder.appendingPathComponent(name))
    }
}

func makeItem(id: String, sources: [(id: String, path: String, size: Int64)], etag: String = "etag") -> [String: Any] {
    [
        "Id": id, "Etag": etag, "Name": "Server Title \(id)", "Path": sources.first?.path ?? "",
        "MediaSources": sources.map { ["Id": $0.id, "Path": $0.path, "Size": $0.size, "Protocol": "File", "Container": "mkv", "ETag": "src-\($0.id)"] },
    ]
}

func folders(_ list: [(String, [String])]) -> Data {
    let array = list.map { ["Name": $0.0, "Locations": $0.1] as [String: Any] }
    return (try? JSONSerialization.data(withJSONObject: array)) ?? Data()
}
