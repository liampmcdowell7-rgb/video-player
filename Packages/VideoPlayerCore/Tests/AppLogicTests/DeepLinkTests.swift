import XCTest
@testable import AppLogic

final class DeepLinkTests: XCTestCase {
    private func parse(_ text: String) -> DeepLink? { URL(string: text).flatMap(DeepLink.parse) }

    func testTheThreeShapesParse() {
        XCTAssertEqual(parse("videoplayer://item/42"), .item(42))
        XCTAssertEqual(parse("videoplayer://series/7"), .series(7))
        XCTAssertEqual(parse("videoplayer://library"), .library)
    }

    func testEveryLinkRoundTripsThroughItsURL() {
        for link in [DeepLink.item(1), .item(999_999_999_999_999_999), .series(12), .library] {
            XCTAssertEqual(DeepLink.parse(link.url), link, "\(link)")
        }
    }

    func testSchemeAndHostAreCaseInsensitive() {
        XCTAssertEqual(parse("VideoPlayer://ITEM/5"), .item(5))
    }

    func testAWrongSchemeIsRejected() {
        XCTAssertNil(parse("https://item/42"))
        XCTAssertNil(parse("video://item/42"))
    }

    func testNonNumericZeroNegativeAndHugeIdsAreRejected() {
        for text in ["videoplayer://item/abc", "videoplayer://item/0", "videoplayer://item/-3", "videoplayer://item/4.5",
                     "videoplayer://item/99999999999999999999", "videoplayer://item/1234567890123456789"] {
            XCTAssertNil(parse(text), text)
        }
    }

    func testExtraPathQueryFragmentUserInfoAreRejected() {
        for text in ["videoplayer://item/42/extra", "videoplayer://item/42?x=1", "videoplayer://item/42#top",
                     "videoplayer://user:pw@item/42", "videoplayer://item", "videoplayer://series", "videoplayer://library/1",
                     "videoplayer://elsewhere/42", "videoplayer://", "videoplayer:item/42"] {
            XCTAssertNil(parse(text), text)
        }
    }

    func testALinkNeverCarriesAServerAddressOrPassword() {
        let all = [DeepLink.item(3), .series(4), .library].map(\.url.absoluteString)
        XCTAssertEqual(all, ["videoplayer://item/3", "videoplayer://series/4", "videoplayer://library"])
    }
}
