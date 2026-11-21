import Foundation
import VideoPlayerCore

/// Who the app is to Plex (docs/PLEX_SOURCE.md section 1; OPEN_QUESTIONS R300).
///
/// Headers, from https://developer.plex.tv/pms/#section/API-Info/Headers (re-read 20 Nov 2026): "X-Plex-Client-Identifier
/// is typically required, as is X-Plex-Token for authentication"; Product, Version, Platform and Device are in the same
/// table, whether they are required is not stated. "all X-Plex- headers can also be sent as query string arguments": this
/// client never does that for the token (it would end up in logged URLs); headers only.
///
/// `clientIdentifier` (PROVISIONAL, R300): the app installation's own random device identifier, the one Jellyfin and Emby
/// already get. Stable per installation, not secret, never derived from the hardware.
public struct PlexClientIdentity: Equatable, Sendable {
    public var clientIdentifier: String
    /// "should be different from any existing Plex products" (read): the app's display name is.
    public var product: String
    public var version: String
    public var platform: String
    public var device: String

    public init(clientIdentifier: String, product: String = "Video Player", version: String = AppInfo.version,
                platform: String = "tvOS", device: String = "Apple TV") {
        self.clientIdentifier = clientIdentifier
        self.product = product
        self.version = version
        self.platform = platform
        self.device = device
    }

    /// The headers of every request. JSON only: "The default is XML, so JSON will only be returned if it's explicitly
    /// requested (Accept: application/json)" (read). The token header only when there is a token.
    public func headers(token: String?) -> [String: String] {
        var headers: [String: String] = [
            "Accept": "application/json",
            "X-Plex-Client-Identifier": clientIdentifier,
            "X-Plex-Product": product,
            "X-Plex-Version": version,
            "X-Plex-Platform": platform,
            "X-Plex-Device": device,
        ]
        if let token, !token.isEmpty { headers["X-Plex-Token"] = token }
        return headers
    }
}

/// What can go wrong with Plex in words the screens can show. No case carries a token, a URL with a token or a server answer.
public enum PlexError: Error, Equatable, Sendable {
    /// The sign-in code ran out before it was entered.
    case codeExpired
    /// The account has no server this app can use.
    case noServers
    /// No connection of the server answered (the relay is off, or the server is off).
    case serverUnreachable
    /// The only route is the relay and the relay is not allowed (R302).
    case onlyRelay
    /// The server answered with XML or something else that is not JSON.
    case notJSON
    /// The file cannot be played by this app (R304): the reason in plain words.
    case cannotPlay(String)
    /// The server came without a token of its own; the account token is never used in its place (R302, R303).
    case noServerToken
}

extension PlexError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .codeExpired: return "The code expired. Choose Get a New Code."
        case .noServers: return "This Plex account has no server this app can use."
        case .serverUnreachable: return "The Plex server did not answer. Check that it is on and on the same network."
        case .onlyRelay: return "This server is reachable only through the Plex relay, which is off."
        case .notJSON: return "The Plex server sent an answer this app cannot read."
        case .cannotPlay(let reason): return reason
        case .noServerToken: return "This server cannot be added yet."
        }
    }
}

/// Request plumbing shared by the account (plex.tv) and the server calls.
struct PlexHTTP: Sendable {
    let identity: PlexClientIdentity
    let transport: HTTPTransport

    func request(_ method: String, _ url: URL, token: String?, extra: [String: String] = [:]) -> HTTPRequest {
        var headers = identity.headers(token: token)
        for (name, value) in extra { headers[name] = value }
        return HTTPRequest(url: url, method: method, headers: headers)
    }

    /// Sends a request. A transport failure becomes `SourceError.transport` with the error's text with every token removed.
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch let error as SourceError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SourceError.transport(PlexRedaction.redact(String(describing: error), tokens: [request.headers["X-Plex-Token"]]))
        }
    }

    static func check(_ response: HTTPResponse) throws {
        switch response.statusCode {
        case 200...299: return
        case 401: throw SourceError.unauthorized
        case 403: throw SourceError.forbidden
        case 404: throw SourceError.notFound
        default: throw SourceError.httpStatus(response.statusCode)
        }
    }

    /// Decodes a JSON answer. An XML (or any non-JSON) answer is refused: the client always asks for JSON (R300).
    static func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse) throws -> T {
        try check(response)
        let contentType = (response.header("content-type") ?? "").lowercased()
        let first = response.body.first { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09) }
        if contentType.contains("xml") || first == UInt8(ascii: "<") { throw PlexError.notJSON }
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw SourceError.malformedResponse }
    }
}

/// Removes tokens from any text before it can reach a log line or an error message (docs/PLEX_SOURCE.md section 3).
public enum PlexRedaction {
    public static let placeholder = "<token>"

    public static func redact(_ text: String, tokens: [String?]) -> String {
        var out = text
        for token in tokens.compactMap({ $0 }) where token.count >= 4 {
            out = out.replacingOccurrences(of: token, with: placeholder)
        }
        // A token in a query string (X-Plex-Token=...) is removed even when the value is not known here.
        if let regex = try? NSRegularExpression(pattern: "(?i)(X-Plex-Token=)[^&\\s\"']+") {
            out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1" + placeholder)
        }
        return out
    }
}
