import XCTest
@testable import VideoPlayerCore

final class DigestsTests: XCTestCase {
    func testMD5KnownVectors() {
        XCTAssertEqual(Digests.md5Hex(""), "d41d8cd98f00b204e9800998ecf8427e")
        XCTAssertEqual(Digests.md5Hex("abc"), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(Digests.md5Hex("The quick brown fox jumps over the lazy dog"), "9e107d9d372bb6826bd81d3542a419d6")
        XCTAssertEqual(Digests.md5Hex(String(repeating: "1234567890", count: 8)), "57edf4a22be3c955ac49da2e2107b67a")
    }

    func testSHA256KnownVectors() {
        XCTAssertEqual(Digests.sha256Hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(Digests.sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(
            Digests.sha256Hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        )
    }
}
