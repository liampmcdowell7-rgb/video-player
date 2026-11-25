import XCTest
@testable import AppLogic

/// R471 (48): pictures are decoded at the pixels their frame shows, never larger than the file.
final class ImageSizingTests: XCTestCase {
    func testAPosterFileIsDecodedAtItsCardsPixels() {
        // A 2000 x 3000 poster file in a card 340 x 510 points on a 2x screen: 680 x 1020 pixels, longest side 1020 → 1024.
        XCTAssertEqual(ImageSizing.maxPixelSize(frameWidth: 340, frameHeight: 510, imageWidth: 2000, imageHeight: 3000, scale: 2), 1024)
    }

    func testAWidePictureInAPortraitFrameStillFillsIt() {
        // A 16:9 still filling a 2:3 frame: its height must cover 510 x 2 = 1020 px, so its width is 1813 px.
        let size = ImageSizing.maxPixelSize(frameWidth: 340, frameHeight: 510, imageWidth: 3840, imageHeight: 2160, scale: 2)
        XCTAssertEqual(size, 1856, "1813 rounded up to the 64 px step")
        let decodedHeight = 2160.0 * Double(size ?? 0) / 3840.0
        XCTAssertGreaterThanOrEqual(decodedHeight, 1020, "the decoded copy still covers the frame's height")
    }

    func testNeverLargerThanTheFile() {
        XCTAssertEqual(ImageSizing.maxPixelSize(frameWidth: 1920, frameHeight: 1080, imageWidth: 780, imageHeight: 439, scale: 2), 780,
                       "a small remote backdrop is decoded whole, never upscaled")
    }

    func testNothingBeforeTheFrameIsMeasured() {
        XCTAssertNil(ImageSizing.maxPixelSize(frameWidth: 0, frameHeight: 510, imageWidth: 2000, imageHeight: 3000, scale: 2))
        XCTAssertNil(ImageSizing.maxPixelSize(frameWidth: 340, frameHeight: 510, imageWidth: 0, imageHeight: 3000, scale: 2))
    }

    func testTheCacheKeyHoldsTheSize() throws {
        let url = try XCTUnwrap(URL(string: "file:///library/poster.jpg"))
        XCTAssertNotEqual(ImageSizing.cacheKey(url: url, maxPixelSize: 512), ImageSizing.cacheKey(url: url, maxPixelSize: 1024))
    }
}
