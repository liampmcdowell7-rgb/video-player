import XCTest
@testable import AppLogic

/// R454: the player's Video tab line: order, formatters, parts without data left out, the bitrate estimate.
final class VideoTabLineTests: XCTestCase {
    private let us = Locale(identifier: "en_US")

    private var full: VideoTabFacts {
        VideoTabFacts(runtimeSeconds: 7_200, year: 2021, fileSizeBytes: 18_000_000_000, videoCodec: "HEVC", resolution: "4K",
                      audioFormat: "Dolby Digital Plus 5.1", bitrateBitsPerSecond: 20_000_000, frameRate: 23.976, genre: "Drama",
                      contentRating: "PG-13")
    }

    func testOrderIsRuntimeYearSizeVideoAudioBitrateFrameRateGenreRating() {
        let parts = VideoTabLine.parts(full, locale: us)
        XCTAssertEqual(parts, [DisplayText.runtime(7_200), "2021", "18 GB", "HEVC 4K", "Dolby Digital Plus 5.1", "20.0 Mbps", "23.976 fps", "Drama", "PG-13"])
    }

    func testPartsWithoutDataAreLeftOutAndNothingIsInvented() {
        XCTAssertEqual(VideoTabLine.line(VideoTabFacts(), locale: us), "")
        XCTAssertEqual(VideoTabLine.line(VideoTabFacts(year: 2020, genre: "Comedy"), locale: us), "2020 · Comedy")
        XCTAssertEqual(VideoTabLine.parts(VideoTabFacts(videoCodec: "H.264"), locale: us), ["H.264"])
        XCTAssertEqual(VideoTabLine.parts(VideoTabFacts(resolution: "1080p"), locale: us), ["1080p"])
    }

    func testBitrateIsEstimatedAsFileSizeOverRuntimeOnlyWhenNoneWasRead() {
        var f = VideoTabFacts(runtimeSeconds: 1_000, fileSizeBytes: 125_000_000)
        XCTAssertEqual(VideoTabLine.bitrate(f), 1_000_000, "125 MB over 1000 s is 1 Mbps")
        XCTAssertEqual(VideoTabLine.parts(f, locale: us).last, "1.0 Mbps")
        f.bitrateBitsPerSecond = 5_500_000
        XCTAssertEqual(VideoTabLine.bitrate(f), 5_500_000, "a bitrate that was read wins over the estimate")
        XCTAssertNil(VideoTabLine.bitrate(VideoTabFacts(fileSizeBytes: 100)), "no runtime, no estimate")
        XCTAssertNil(VideoTabLine.bitrate(VideoTabFacts(runtimeSeconds: 100)), "no size, no estimate")
    }

    func testMbpsHasOneDecimalAndFrameRateUpToThree() {
        XCTAssertEqual(VideoTabLine.megabitsPerSecond(18_449_000, locale: us), "18.4 Mbps")
        XCTAssertEqual(VideoTabLine.megabitsPerSecond(950_000, locale: us), "1.0 Mbps")
        XCTAssertEqual(VideoTabLine.framesPerSecond(24, locale: us), "24 fps")
        XCTAssertEqual(VideoTabLine.framesPerSecond(23.976, locale: us), "23.976 fps")
        XCTAssertEqual(VideoTabLine.framesPerSecond(29.97002997, locale: us), "29.97 fps")
        XCTAssertEqual(VideoTabLine.framesPerSecond(59.94, locale: us), "59.94 fps")
    }

    func testFileSizeUsesDecimalUnits() {
        XCTAssertEqual(VideoTabLine.fileSize(1_500_000_000), "1.5 GB")
        XCTAssertEqual(VideoTabLine.fileSize(734_000_000), "734 MB")
    }

    func testNonsenseValuesAreLeftOut() {
        let f = VideoTabFacts(runtimeSeconds: 0, year: 99, fileSizeBytes: 0, frameRate: .infinity)
        XCTAssertEqual(VideoTabLine.line(f, locale: us), "")
    }
}
