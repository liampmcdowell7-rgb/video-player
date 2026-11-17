import Foundation
import VideoPlayerCore

/// UPnP / DLNA MediaServer client. Created from the device description URL the user typed
/// (for example `http://192.168.1.20:8200/rootDesc.xml`) or that SSDP found.
///
/// Paths are built from the titles of the containers (`/Movies/Test Movie (2020).mkv`), and the
/// client keeps the path <-> object id map the server needs, filled in as folders are listed.
public actor UPnPClient: MediaSource {
    private struct Node {
        var id: String
        var entry: SourceEntry
        var resourceURL: URL?
    }

    private static let contentDirectoryAction = "urn:schemas-upnp-org:service:ContentDirectory:1#Browse"
    private static let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub", "smi"]

    private let deviceURL: URL
    private let transport: HTTPTransport
    private let pageSize: Int
    private var controlURL: URL?
    private var serviceType = "urn:schemas-upnp-org:service:ContentDirectory:1"
    private var deviceDescription: UPnPDeviceDescription?
    private var nodes: [String: Node] = [:]   // path -> node
    private var idToPath: [String: String] = ["0": "/"]

    /// - Parameters:
    ///   - deviceURL: the device description document URL.
    ///   - pageSize: how many objects to ask for per Browse call (paging with StartingIndex/RequestedCount).
    public init(deviceURL: URL, transport: HTTPTransport, pageSize: Int = 100) {
        self.deviceURL = deviceURL
        self.transport = transport
        self.pageSize = max(1, pageSize)
    }

    // MARK: MediaSource

    public nonisolated var kind: SourceKind { .upnp }

    public nonisolated var capabilities: SourceCapabilities {
        SourceCapabilities(
            authMethods: [.none],
            byteRanges: true,
            changeSignals: [.size, .modified],
            discovery: true,            // SSDP, device-only (see SSDPDiscovery)
            directPlaybackURL: true,
            alwaysEncrypted: false
        )
    }

    /// Fetches the device description and finds the ContentDirectory control URL.
    public func authenticate() async throws {
        let response = try await send(HTTPRequest(url: deviceURL, method: "GET"))
        try Self.check(response.statusCode)
        let description = try UPnPDeviceDescription.parse(response.body)
        guard let service = description.contentDirectory else {
            throw SourceError.unsupported("This device has no ContentDirectory service, so it is not a media server")
        }
        let base = description.urlBase.flatMap { URL(string: $0) } ?? deviceURL
        guard let control = URL(string: service.controlURL, relativeTo: base)?.absoluteURL else { throw SourceError.invalidURL }
        deviceDescription = description
        controlURL = control
        serviceType = service.serviceType
    }

    /// The device's own name, available after `authenticate()`.
    public var friendlyName: String? { deviceDescription?.friendlyName }

    public func list(_ path: String = "/") async throws -> [SourceEntry] {
        let normalized = Self.normalize(path)
        let id = try await objectID(forPath: normalized)
        return try await browseChildren(id: id, parentPath: normalized)
    }

    public func info(_ path: String) async throws -> SourceEntry {
        let normalized = Self.normalize(path)
        if normalized == "/" { return SourceEntry(path: "/", name: "", isDirectory: true) }
        return try await node(forPath: normalized).entry
    }

    public func read(_ path: String, range: ByteRange) async throws -> Data {
        if range.length == 0 { return Data() }
        let url = try await resourceURL(forPath: path)
        let response = try await send(HTTPRequest(url: url, method: "GET", headers: ["Range": range.httpHeaderValue]))
        switch response.statusCode {
        case 206: return response.body.count > Int(range.length) ? response.body.prefix(Int(range.length)) : response.body
        case 200: throw SourceError.rangesNotSupported
        case 416: throw SourceError.rangeNotSatisfiable
        default: try Self.check(response.statusCode); throw SourceError.httpStatus(response.statusCode)
        }
    }

    public func playbackAccess(for path: String) async throws -> PlaybackAccess {
        .url(try await resourceURL(forPath: path), headers: [:])
    }

    // MARK: Browsing

    private func resourceURL(forPath path: String) async throws -> URL {
        let found = try await node(forPath: Self.normalize(path))
        guard let url = found.resourceURL else { throw SourceError.unsupported("A folder has nothing to play") }
        return url
    }

    /// Finds the node for a path, listing parent folders as needed to learn their ids.
    private func node(forPath path: String) async throws -> Node {
        if let known = nodes[path] { return known }
        let parent = Self.parentPath(of: path)
        let parentID = try await objectID(forPath: parent)
        _ = try await browseChildren(id: parentID, parentPath: parent)
        guard let found = nodes[path] else { throw SourceError.notFound }
        return found
    }

    private func objectID(forPath path: String) async throws -> String {
        if path == "/" { return "0" }
        let found = try await node(forPath: path)
        guard found.entry.isDirectory else { throw SourceError.unsupported("Not a folder") }
        return found.id
    }

    private func browseChildren(id: String, parentPath: String) async throws -> [SourceEntry] {
        if controlURL == nil { try await authenticate() }
        var objects: [DIDLObject] = []
        var start = 0
        while true {
            let page = try await browse(id: id, startingIndex: start)
            let parsed = try DIDLParser.parse(page.didl)
            objects.append(contentsOf: parsed)
            start += page.numberReturned > 0 ? page.numberReturned : parsed.count
            if page.numberReturned == 0 && parsed.isEmpty { break }
            if page.totalMatches > 0 && start >= page.totalMatches { break }
            if page.totalMatches == 0 && parsed.count < pageSize { break }   // server does not report a total
        }
        // Forget what was known under this folder, then rebuild it (names can change on the server).
        let prefix = parentPath == "/" ? "/" : parentPath + "/"
        for key in nodes.keys where key.hasPrefix(prefix) && !key.dropFirst(prefix.count).contains("/") {
            if let old = nodes.removeValue(forKey: key) { idToPath.removeValue(forKey: old.id) }
        }
        var entries: [SourceEntry] = []
        var used = Set<String>()
        for object in objects {
            for node in makeNodes(for: object, parentPath: parentPath, used: &used) {
                nodes[node.entry.path] = node
                if idToPath[node.id] == nil { idToPath[node.id] = node.entry.path }
                entries.append(node.entry)
            }
        }
        return entries
    }

    /// The path the client assigned to a server object id (after the folder holding it was listed).
    public func path(forObjectID id: String) -> String? { idToPath[id] }

    private func browse(id: String, startingIndex: Int) async throws -> BrowseResponse {
        guard let control = controlURL else { throw SourceError.invalidURL }
        let body = """
        <?xml version="1.0"?>\
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
        <s:Body><u:Browse xmlns:u="\(Self.xmlEscape(serviceType))">\
        <ObjectID>\(Self.xmlEscape(id))</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag><Filter>*</Filter>\
        <StartingIndex>\(startingIndex)</StartingIndex><RequestedCount>\(pageSize)</RequestedCount><SortCriteria></SortCriteria>\
        </u:Browse></s:Body></s:Envelope>
        """
        let request = HTTPRequest(
            url: control, method: "POST",
            headers: [
                "Content-Type": "text/xml; charset=\"utf-8\"",
                "SOAPACTION": "\"\(serviceType)#Browse\""
            ],
            body: Data(body.utf8)
        )
        let response = try await send(request)
        // A SOAP fault arrives with status 500; its body says what went wrong.
        if response.statusCode == 200 || response.statusCode == 500 {
            return try SOAPParser.parseBrowse(response.body)
        }
        try Self.check(response.statusCode)
        throw SourceError.httpStatus(response.statusCode)
    }

    // MARK: Mapping DIDL objects to entries

    private func makeNodes(for object: DIDLObject, parentPath: String, used: inout Set<String>) -> [Node] {
        let modified = DIDLParser.parseDate(object.date)
        if object.isContainer {
            let path = Self.uniquePath(parent: parentPath, name: Self.sanitize(object.title), used: &used)
            return [Node(id: object.id, entry: SourceEntry(path: path, name: Self.leaf(of: path), isDirectory: true, modified: modified), resourceURL: nil)]
        }
        guard !object.resources.isEmpty else { return [] }
        var result: [Node] = []
        let main = object.resources.first { ($0.mimeType ?? "").hasPrefix("video/") || ($0.mimeType ?? "").hasPrefix("audio/") }
            ?? object.resources[0]
        for resource in object.resources {
            guard let url = URL(string: resource.url, relativeTo: deviceURL)?.absoluteURL else { continue }
            let isMain = resource == main
            let urlName = (url.path as NSString).lastPathComponent
            let ext = (urlName as NSString).pathExtension
            var name: String
            if isMain {
                name = Self.sanitize(object.title)
                if Self.isPlausibleExtension(ext), !name.lowercased().hasSuffix("." + ext.lowercased()) { name += "." + ext }
            } else if Self.subtitleExtensions.contains(ext.lowercased()) || (resource.mimeType ?? "").hasPrefix("text/")
                        || (resource.mimeType ?? "") == "application/x-subrip" {
                name = Self.sanitize(urlName)
            } else {
                continue   // artwork, other renditions
            }
            let path = Self.uniquePath(parent: parentPath, name: name, used: &used)
            result.append(Node(
                id: object.id,
                entry: SourceEntry(path: path, name: Self.leaf(of: path), isDirectory: false, size: resource.size,
                                   modified: modified, contentType: resource.mimeType),
                resourceURL: url
            ))
        }
        return result
    }

    /// Two objects can share a title; the second gets " (2)" so every path is unique within a folder.
    private static func uniquePath(parent: String, name: String, used: inout Set<String>) -> String {
        let base = parent == "/" ? "/" + name : parent + "/" + name
        var candidate = base
        var counter = 2
        while used.contains(candidate) {
            let ext = (name as NSString).pathExtension
            let stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
            let newName = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
            candidate = parent == "/" ? "/" + newName : parent + "/" + newName
            counter += 1
        }
        used.insert(candidate)
        return candidate
    }

    // MARK: Helpers

    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch let error as SourceError {
            throw error
        } catch {
            throw SourceError.transport(String(describing: error))
        }
    }

    private static func check(_ status: Int) throws {
        switch status {
        case 200..<300: return
        case 401: throw SourceError.unauthorized
        case 403: throw SourceError.forbidden
        case 404: throw SourceError.notFound
        default: throw SourceError.httpStatus(status)
        }
    }

    /// Titles may hold "/", which would break paths.
    static func sanitize(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "\u{2215}").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    static func isPlausibleExtension(_ ext: String) -> Bool {
        (1...5).contains(ext.count) && ext.allSatisfy { $0.isLetter || $0.isNumber }
    }

    static func normalize(_ path: String) -> String {
        "/" + path.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
    }

    static func parentPath(of path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        return parts.count <= 1 ? "/" : "/" + parts.dropLast().joined(separator: "/")
    }

    static func leaf(of path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? ""
    }

    static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
