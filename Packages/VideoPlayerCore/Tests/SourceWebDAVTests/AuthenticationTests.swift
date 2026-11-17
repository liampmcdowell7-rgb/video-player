import XCTest
@testable import VideoPlayerCore
@testable import SourceWebDAV

final class AuthenticationTests: XCTestCase {
    private func responseValue(in header: String) -> String? {
        guard let range = header.range(of: #"response=""#) else { return nil }
        let rest = header[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    func testChallengeParserHandlesMergedHeadersAndQuotedCommas() {
        let header = #"Digest realm="a, b", nonce="x1", qop="auth,auth-int", Basic realm="r""#
        let parsed = AuthChallengeParser.parse(header)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].scheme, "digest")
        XCTAssertEqual(parsed[0].params["realm"], "a, b")
        XCTAssertEqual(parsed[0].params["qop"], "auth,auth-int")
        XCTAssertEqual(parsed[1].scheme, "basic")
        XCTAssertEqual(parsed[1].params["realm"], "r")
    }

    func testDigestRFC2617Example() throws {
        let challenge = AuthChallenge(scheme: "digest", params: [
            "realm": "testrealm@host.com",
            "nonce": "dcd98b7102dd2f0e8b11d0f600bfb0c093",
            "opaque": "5ccc069c403ebaf9f0171e9517f40e41",
            "qop": "auth,auth-int"
        ])
        let digest = try XCTUnwrap(DigestChallenge(challenge))
        let header = DigestAuth.authorization(
            challenge: digest, username: "Mufasa", password: "Circle Of Life",
            method: "GET", uri: "/dir/index.html", nonceCount: 1, cnonce: "0a4f113b"
        )
        XCTAssertEqual(responseValue(in: header), "6629fae49393a05397450978507c4ef1")
        XCTAssertTrue(header.contains("nc=00000001"))
        XCTAssertTrue(header.contains("qop=auth"))
    }

    func testDigestRFC7616Examples() throws {
        func make(_ algorithm: String) throws -> DigestChallenge {
            try XCTUnwrap(DigestChallenge(AuthChallenge(scheme: "digest", params: [
                "realm": "http-auth@example.org",
                "nonce": "7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v",
                "opaque": "FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS",
                "qop": "auth, auth-int",
                "algorithm": algorithm
            ])))
        }
        let cnonce = "f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ"
        let sha = DigestAuth.authorization(
            challenge: try make("SHA-256"), username: "Mufasa", password: "Circle of Life",
            method: "GET", uri: "/dir/index.html", nonceCount: 1, cnonce: cnonce
        )
        XCTAssertEqual(responseValue(in: sha), "753927fa0e85d155564e2e272a28d1802ca10daf4496794697cf8db5856cb6c1")
        let md5 = DigestAuth.authorization(
            challenge: try make("MD5"), username: "Mufasa", password: "Circle of Life",
            method: "GET", uri: "/dir/index.html", nonceCount: 1, cnonce: cnonce
        )
        XCTAssertEqual(responseValue(in: md5), "8ca523f5e9506fed4657c9700eebdbec")
    }

    func testDigestWithoutQopUsesLegacyForm() throws {
        let digest = try XCTUnwrap(DigestChallenge(AuthChallenge(scheme: "digest", params: ["realm": "r", "nonce": "n"])))
        let header = DigestAuth.authorization(
            challenge: digest, username: "u", password: "p", method: "GET", uri: "/", nonceCount: 1, cnonce: "c"
        )
        let ha1 = Digests.md5Hex("u:r:p")
        let ha2 = Digests.md5Hex("GET:/")
        XCTAssertEqual(responseValue(in: header), Digests.md5Hex("\(ha1):n:\(ha2)"))
        XCTAssertFalse(header.contains("cnonce"))
    }

    func testAuthIntOnlyIsRejected() {
        let challenge = AuthChallenge(scheme: "digest", params: ["realm": "r", "nonce": "n", "qop": "auth-int"])
        XCTAssertNil(DigestChallenge(challenge))
    }

    func testBasicHeader() {
        XCTAssertEqual(BasicAuth.authorization(username: "user", password: "pass"), "Basic dXNlcjpwYXNz")
    }
}
