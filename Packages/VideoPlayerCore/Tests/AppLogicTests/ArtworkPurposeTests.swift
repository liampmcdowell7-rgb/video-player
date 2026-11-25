import XCTest
@testable import AppLogic

/// R471 (36): every gallery kind says, in one sentence of our own, where the app shows the picture.
final class ArtworkPurposeTests: XCTestCase {
    func testEveryKindHasOneSentence() {
        for kind in ArtworkGalleryKind.allCases {
            let text = kind.purpose
            XCTAssertFalse(text.isEmpty, "\(kind)")
            XCTAssertTrue(text.hasSuffix("."), "\(kind) ends as a sentence")
            XCTAssertFalse(text.lowercased().contains("mobile"), "\(kind): this app runs on the television only")
        }
        XCTAssertEqual(Set(ArtworkGalleryKind.allCases.map(\.purpose)).count, ArtworkGalleryKind.allCases.count, "one each")
    }
}
