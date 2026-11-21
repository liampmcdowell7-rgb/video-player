import Foundation

// Plex JSON models (docs/PLEX_SOURCE.md section 4; OPEN_QUESTIONS R300). Only the fields the app uses; everything else is
// ignored. Field names come from the Plex Media Server reference (https://developer.plex.tv/pms/), re-read 20 Nov 2026:
//   read there (samples or tables): MediaContainer size/totalSize/offset, Metadata ratingKey, key, type, title, year, summary,
//   duration ("Runtime in milliseconds"), thumb, art, contentRating, rating, index, parentIndex, parentTitle,
//   grandparentTitle, Guid id ("provider://id"), Media (id, container, videoCodec, audioCodec, audioChannels, bitrate, width,
//   height), Part (id, key, file, size, container); PIN id and code; resource name, clientIdentifier, accessToken and its
//   connections (protocol, address, port, uri, local, relay).
//   UNVERIFIED (not in the text returned; kept optional so a missing field never breaks decoding): Directory key/type/title
//   and Location path of a library section, viewOffset, viewCount, lastViewedAt, addedAt, updatedAt, videoProfile, PIN
//   authToken in the classic flow (named for the JWT flow), PIN expiresIn/expiresAt, resource provides/owned/product.
// Plex sends ids sometimes as strings and sometimes as numbers, and booleans sometimes as 0/1: the decoders accept both.

/// `{"MediaContainer": {...}}`, the envelope of every Plex Media Server JSON answer.
struct PlexEnvelope: Decodable {
    var container: PlexMediaContainer
    enum CodingKeys: String, CodingKey { case container = "MediaContainer" }
}

struct PlexMediaContainer: Decodable {
    var size: Int?
    var totalSize: Int?
    var offset: Int?
    var machineIdentifier: String?
    var version: String?
    var directories: [PlexDirectory]
    var metadata: [PlexMetadata]

    enum CodingKeys: String, CodingKey {
        case size, totalSize, offset, machineIdentifier, version
        case directories = "Directory", metadata = "Metadata"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = c.flexibleInt(.size)
        totalSize = c.flexibleInt(.totalSize)
        offset = c.flexibleInt(.offset)
        machineIdentifier = c.flexibleString(.machineIdentifier)
        version = c.flexibleString(.version)
        directories = (try? c.decodeIfPresent([PlexDirectory].self, forKey: .directories)) ?? []
        metadata = (try? c.decodeIfPresent([PlexMetadata].self, forKey: .metadata)) ?? []
    }
}

/// A library section (`/library/sections`). UNVERIFIED field names (see the header).
struct PlexDirectory: Decodable, Equatable {
    var key: String
    var type: String?
    var title: String
    var locations: [String]

    enum CodingKeys: String, CodingKey { case key, type, title, locations = "Location" }
    private struct Location: Decodable { var path: String? }

    init(key: String, type: String?, title: String, locations: [String]) {
        self.key = key; self.type = type; self.title = title; self.locations = locations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = c.flexibleString(.key) else {
            throw DecodingError.keyNotFound(CodingKeys.key, .init(codingPath: c.codingPath, debugDescription: "section without key"))
        }
        self.key = key
        type = c.flexibleString(.type)
        title = c.flexibleString(.title) ?? ""
        locations = ((try? c.decodeIfPresent([Location].self, forKey: .locations)) ?? []).compactMap(\.path)
    }
}

/// A movie, show, season or episode.
public struct PlexMetadata: Decodable, Equatable, Sendable {
    public var ratingKey: String
    public var key: String?
    public var type: String?
    public var title: String?
    public var year: Int?
    public var summary: String?
    /// Milliseconds ("Runtime in milliseconds", read).
    public var duration: Int?
    public var thumb: String?
    public var art: String?
    public var contentRating: String?
    public var rating: Double?
    public var index: Int?
    public var parentIndex: Int?
    public var parentTitle: String?
    public var grandparentTitle: String?
    /// UNVERIFIED names (not in the reference text returned): resume position in ms, play count, last played (Unix seconds).
    public var viewOffset: Int?
    public var viewCount: Int?
    public var lastViewedAt: Int?
    /// "provider://id", for example "tmdb://603" (read).
    public var guids: [String]
    public var media: [PlexMedia]

    enum CodingKeys: String, CodingKey {
        case ratingKey, key, type, title, year, summary, duration, thumb, art, contentRating, rating, index, parentIndex
        case parentTitle, grandparentTitle, viewOffset, viewCount, lastViewedAt
        case guids = "Guid", media = "Media"
    }
    private struct GuidEntry: Decodable { var id: String? }

    public init(ratingKey: String, type: String? = nil, title: String? = nil, media: [PlexMedia] = [], guids: [String] = []) {
        self.ratingKey = ratingKey; self.type = type; self.title = title; self.media = media; self.guids = guids
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let ratingKey = c.flexibleString(.ratingKey) else {
            throw DecodingError.keyNotFound(CodingKeys.ratingKey, .init(codingPath: c.codingPath, debugDescription: "item without a rating key"))
        }
        self.ratingKey = ratingKey
        key = c.flexibleString(.key)
        type = c.flexibleString(.type)
        title = c.flexibleString(.title)
        year = c.flexibleInt(.year)
        summary = c.flexibleString(.summary)
        duration = c.flexibleInt(.duration)
        thumb = c.flexibleString(.thumb)
        art = c.flexibleString(.art)
        contentRating = c.flexibleString(.contentRating)
        rating = c.flexibleDouble(.rating)
        index = c.flexibleInt(.index)
        parentIndex = c.flexibleInt(.parentIndex)
        parentTitle = c.flexibleString(.parentTitle)
        grandparentTitle = c.flexibleString(.grandparentTitle)
        viewOffset = c.flexibleInt(.viewOffset)
        viewCount = c.flexibleInt(.viewCount)
        lastViewedAt = c.flexibleInt(.lastViewedAt)
        guids = ((try? c.decodeIfPresent([GuidEntry].self, forKey: .guids)) ?? []).compactMap(\.id)
        media = (try? c.decodeIfPresent([PlexMedia].self, forKey: .media)) ?? []
    }

    /// The TMDB id from a `tmdb://` Guid, if any.
    public var tmdbID: Int? { guidValue("tmdb").flatMap { Int($0) } }
    public var imdbID: String? { guidValue("imdb") }

    func guidValue(_ provider: String) -> String? {
        let prefix = provider + "://"
        return guids.first { $0.lowercased().hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    /// Runtime in whole seconds.
    public var runtimeSeconds: Int? { duration.map { $0 / 1000 } }
}

public struct PlexMedia: Decodable, Equatable, Sendable {
    public var id: String?
    public var container: String?
    public var videoCodec: String?
    public var audioCodec: String?
    public var audioChannels: Int?
    public var bitrate: Int?
    public var width: Int?
    public var height: Int?
    /// UNVERIFIED name (not in the sample read); used only as a hint, never required.
    public var videoProfile: String?
    public var parts: [PlexPart]

    enum CodingKeys: String, CodingKey {
        case id, container, videoCodec, audioCodec, audioChannels, bitrate, width, height, videoProfile
        case parts = "Part"
    }

    public init(container: String?, videoCodec: String? = nil, audioCodec: String? = nil, parts: [PlexPart]) {
        self.container = container; self.videoCodec = videoCodec; self.audioCodec = audioCodec; self.parts = parts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexibleString(.id)
        container = c.flexibleString(.container)
        videoCodec = c.flexibleString(.videoCodec)
        audioCodec = c.flexibleString(.audioCodec)
        audioChannels = c.flexibleInt(.audioChannels)
        bitrate = c.flexibleInt(.bitrate)
        width = c.flexibleInt(.width)
        height = c.flexibleInt(.height)
        videoProfile = c.flexibleString(.videoProfile)
        parts = (try? c.decodeIfPresent([PlexPart].self, forKey: .parts)) ?? []
    }
}

public struct PlexPart: Decodable, Equatable, Sendable {
    public var id: String?
    /// The server path of the file itself, for example "/library/parts/827/file.mkv" (read as a sample).
    public var key: String?
    /// The file's path on the server's disk (builds the folder tree).
    public var file: String?
    public var size: Int64?
    public var container: String?

    enum CodingKeys: String, CodingKey { case id, key, file, size, container }

    public init(id: String?, key: String?, file: String?, size: Int64?, container: String?) {
        self.id = id; self.key = key; self.file = file; self.size = size; self.container = container
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexibleString(.id)
        key = c.flexibleString(.key)
        file = c.flexibleString(.file)
        size = c.flexibleInt(.size).map(Int64.init)
        container = c.flexibleString(.container)
    }
}

// MARK: plex.tv account answers

/// A sign-in PIN (`POST https://plex.tv/api/v2/pins`). `id` and `code` read; the rest UNVERIFIED in the classic flow.
struct PlexPinResponse: Decodable {
    var id: String
    var code: String
    var authToken: String?
    var expiresIn: Int?

    enum CodingKeys: String, CodingKey { case id, code, authToken, expiresIn }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.flexibleString(.id), let code = c.flexibleString(.code) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "PIN without id or code"))
        }
        self.id = id
        self.code = code
        let token = c.flexibleString(.authToken)
        authToken = (token?.isEmpty ?? true) ? nil : token
        expiresIn = c.flexibleInt(.expiresIn)
    }
}

/// One entry of the account's resource list (servers and other devices).
public struct PlexResource: Decodable, Equatable, Sendable {
    public var name: String
    public var clientIdentifier: String?
    /// UNVERIFIED (not in the text returned): a comma list such as "server" or "client,player".
    public var provides: String?
    public var accessToken: String?
    public var connections: [PlexConnection]

    enum CodingKeys: String, CodingKey { case name, clientIdentifier, provides, accessToken, connections, connection = "Connection" }

    public init(name: String, clientIdentifier: String?, provides: String?, accessToken: String?, connections: [PlexConnection]) {
        self.name = name; self.clientIdentifier = clientIdentifier; self.provides = provides
        self.accessToken = accessToken; self.connections = connections
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.flexibleString(.name) ?? ""
        clientIdentifier = c.flexibleString(.clientIdentifier)
        provides = c.flexibleString(.provides)
        let token = c.flexibleString(.accessToken)
        accessToken = (token?.isEmpty ?? true) ? nil : token
        connections = (try? c.decodeIfPresent([PlexConnection].self, forKey: .connections))
            ?? (try? c.decodeIfPresent([PlexConnection].self, forKey: .connection)) ?? []
    }

    /// True when the resource says it is a media server. A resource that does not say (`provides` missing) counts as a server
    /// when it has a token and a connection, because the field name is UNVERIFIED.
    public var isServer: Bool {
        if let provides { return provides.lowercased().split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == "server" } }
        return accessToken != nil && !connections.isEmpty
    }
}

public struct PlexConnection: Decodable, Equatable, Sendable {
    public var uri: String
    public var `protocol`: String?
    public var address: String?
    public var port: Int?
    public var local: Bool
    public var relay: Bool

    enum CodingKeys: String, CodingKey { case uri, `protocol`, address, port, local, relay }

    public init(uri: String, protocol: String? = nil, local: Bool, relay: Bool) {
        self.uri = uri; self.protocol = `protocol`; self.local = local; self.relay = relay
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let uri = c.flexibleString(.uri), !uri.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "connection without uri"))
        }
        self.uri = uri
        `protocol` = c.flexibleString(.protocol)
        address = c.flexibleString(.address)
        port = c.flexibleInt(.port)
        local = c.flexibleBool(.local) ?? false
        relay = c.flexibleBool(.relay) ?? false
    }

    /// "https" or "http": from `protocol`, else from the uri's scheme.
    public var scheme: String {
        (`protocol` ?? URL(string: uri)?.scheme ?? "").lowercased()
    }
}

// MARK: Lenient decoding

extension KeyedDecodingContainer {
    func flexibleString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int64.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        return nil
    }
    func flexibleInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s) }
        return nil
    }
    func flexibleDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
    func flexibleBool(_ key: Key) -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return ["1", "true"].contains(s.lowercased()) }
        return nil
    }
}
