import Foundation
import VideoPlayerCore

public struct WebDAVCredentials: Sendable, Equatable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

/// One challenge from a WWW-Authenticate header, for example `Digest realm="x", nonce="y"`.
public struct AuthChallenge: Equatable, Sendable {
    public var scheme: String
    public var params: [String: String]
}

public enum AuthChallengeParser {
    /// Parses a (possibly merged) WWW-Authenticate header value into challenges.
    public static func parse(_ header: String) -> [AuthChallenge] {
        let chars = Array(header)
        var i = 0
        var result: [AuthChallenge] = []

        func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\t" { i += 1 }
        }
        func readToken() -> String {
            var out = ""
            while i < chars.count, chars[i] != " ", chars[i] != ",", chars[i] != "=", chars[i] != "\t" {
                out.append(chars[i]); i += 1
            }
            return out
        }
        func readValue() -> String {
            if i < chars.count, chars[i] == "\"" {
                i += 1
                var out = ""
                while i < chars.count, chars[i] != "\"" {
                    if chars[i] == "\\", i + 1 < chars.count { i += 1 }
                    out.append(chars[i]); i += 1
                }
                if i < chars.count { i += 1 }
                return out
            }
            var out = ""
            while i < chars.count, chars[i] != "," { out.append(chars[i]); i += 1 }
            return out.trimmingCharacters(in: .whitespaces)
        }

        while i < chars.count {
            skipSeparators()
            guard i < chars.count else { break }
            let token = readToken()
            if token.isEmpty { i += 1; continue }
            if i < chars.count, chars[i] == "=" {
                i += 1
                let value = readValue()
                if !result.isEmpty { result[result.count - 1].params[token.lowercased()] = value }
            } else {
                result.append(AuthChallenge(scheme: token.lowercased(), params: [:]))
            }
        }
        return result
    }
}

public enum DigestAlgorithm: Sendable, Equatable {
    case md5, md5Sess, sha256, sha256Sess

    init?(headerValue: String?) {
        switch (headerValue ?? "MD5").uppercased() {
        case "", "MD5": self = .md5
        case "MD5-SESS": self = .md5Sess
        case "SHA-256": self = .sha256
        case "SHA-256-SESS": self = .sha256Sess
        default: return nil
        }
    }

    var headerName: String {
        switch self {
        case .md5: return "MD5"
        case .md5Sess: return "MD5-sess"
        case .sha256: return "SHA-256"
        case .sha256Sess: return "SHA-256-sess"
        }
    }

    var isSession: Bool { self == .md5Sess || self == .sha256Sess }

    func hash(_ s: String) -> String {
        switch self {
        case .md5, .md5Sess: return Digests.md5Hex(s)
        case .sha256, .sha256Sess: return Digests.sha256Hex(s)
        }
    }
}

public struct DigestChallenge: Equatable, Sendable {
    public var realm: String
    public var nonce: String
    public var opaque: String?
    public var algorithm: DigestAlgorithm
    /// True when the server offers qop=auth. False means the legacy RFC 2069 form.
    public var usesQop: Bool

    /// Returns nil when the challenge is incomplete or only offers something unsupported
    /// (an unknown algorithm, or qop=auth-int without auth).
    public init?(_ challenge: AuthChallenge) {
        guard challenge.scheme == "digest",
              let realm = challenge.params["realm"],
              let nonce = challenge.params["nonce"],
              let algorithm = DigestAlgorithm(headerValue: challenge.params["algorithm"])
        else { return nil }
        var usesQop = false
        if let qop = challenge.params["qop"] {
            let options = qop.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard options.contains("auth") else { return nil }
            usesQop = true
        }
        self.realm = realm
        self.nonce = nonce
        self.opaque = challenge.params["opaque"]
        self.algorithm = algorithm
        self.usesQop = usesQop
    }
}

public enum DigestAuth {
    /// Builds the value of an `Authorization: Digest ...` header (RFC 7616; RFC 2617 compatible).
    public static func authorization(
        challenge: DigestChallenge,
        username: String,
        password: String,
        method: String,
        uri: String,
        nonceCount: Int,
        cnonce: String
    ) -> String {
        let alg = challenge.algorithm
        var ha1 = alg.hash("\(username):\(challenge.realm):\(password)")
        if alg.isSession { ha1 = alg.hash("\(ha1):\(challenge.nonce):\(cnonce)") }
        let ha2 = alg.hash("\(method):\(uri)")

        let nc = String(format: "%08x", nonceCount)
        let response: String
        if challenge.usesQop {
            response = alg.hash("\(ha1):\(challenge.nonce):\(nc):\(cnonce):auth:\(ha2)")
        } else {
            response = alg.hash("\(ha1):\(challenge.nonce):\(ha2)")
        }

        func quoted(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        var parts = [
            "username=\(quoted(username))",
            "realm=\(quoted(challenge.realm))",
            "nonce=\(quoted(challenge.nonce))",
            "uri=\(quoted(uri))",
            "algorithm=\(alg.headerName)",
            "response=\(quoted(response))"
        ]
        if let opaque = challenge.opaque { parts.append("opaque=\(quoted(opaque))") }
        if challenge.usesQop {
            parts.append("qop=auth")
            parts.append("nc=\(nc)")
            parts.append("cnonce=\(quoted(cnonce))")
        }
        return "Digest " + parts.joined(separator: ", ")
    }
}

public enum BasicAuth {
    public static func authorization(username: String, password: String) -> String {
        "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }
}
