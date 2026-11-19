import XCTest
import LibraryIndex
import MetadataOnline
@testable import AppLogic

/// #15 6.2: the "Media Info" rows and the synopsis and cast. Synthetic values only.
final class MediaInfoTests: XCTestCase {
    private func rows(_ t: FileTechnicalInfo?, size: Int64? = 4_000_000_000, subtitles: [String] = [], source: String? = nil) -> [MediaInfoRow] {
        MediaInfo.rows(technical: t, size: size, path: "/Movies/Sample Movie (2020)/Sample Movie (2020).mkv", subtitleNames: subtitles, sourceName: source)
    }

    private func value(_ rows: [MediaInfoRow], _ label: String) -> String? { rows.first { $0.label == label }?.value }

    func testAFullyKnownFileListsEveryRowMostImportantFirst() {
        let t = FileTechnicalInfo(duration: 7200, container: .mkv, width: 3840, height: 2160, hdrFormats: [.dolbyVision, .hdr10],
                                  dolbyVisionProfile: 8, videoCodec: "hevc", audioCodec: "truehd", audioChannels: 8, hasAtmos: true, bitrate: 57_600_000)
        let r = rows(t, subtitles: ["Sample Movie (2020).en.srt"], source: "Sample Server")
        XCTAssertEqual(r.map(\.label), ["Resolution", "HDR", "Video", "Frame Rate", "Bitrate", "Audio", "Subtitles", "Container", "File Size", "Source", "Path"])
        XCTAssertEqual(value(r, "Resolution"), "3840 × 2160 (4K)")
        XCTAssertEqual(value(r, "HDR"), "Dolby Vision Profile 8 / HDR10")
        XCTAssertEqual(value(r, "Video"), "HEVC")
        XCTAssertEqual(value(r, "Frame Rate"), MediaInfo.frameRateNotRead, "the index does not record it; never guessed")
        XCTAssertEqual(value(r, "Bitrate"), "57.6 Mbit/s")
        XCTAssertEqual(value(r, "Audio"), "Dolby TrueHD with Dolby Atmos 7.1")
        XCTAssertEqual(value(r, "Subtitles"), "Sample Movie (2020).en.srt")
        XCTAssertEqual(value(r, "Container"), "MKV")
        XCTAssertEqual(value(r, "Source"), "Sample Server")
        XCTAssertEqual(value(r, "Path"), "/Movies/Sample Movie (2020)/Sample Movie (2020).mkv")
    }

    func testAFileWithNothingKnownSaysSoInsteadOfGuessing() {
        let r = rows(nil, size: nil)
        for label in ["Resolution", "HDR", "Video", "Bitrate", "Audio", "Container", "File Size", "Source"] {
            XCTAssertEqual(value(r, label), MediaInfo.notKnown, label)
        }
        XCTAssertEqual(value(r, "Subtitles"), "No subtitle files next to the video")
    }

    func testAnSDRFileSaysNoneAndSmallValuesRead() {
        let r = rows(FileTechnicalInfo(height: 1080, videoCodec: "h264", bitrate: 800_000))
        XCTAssertEqual(value(r, "HDR"), "None (SDR)")
        XCTAssertEqual(value(r, "Resolution"), "1080p", "only the height is known")
        XCTAssertEqual(value(r, "Bitrate"), "800 kbit/s")
        XCTAssertNil(MediaInfo.resolution(width: 1280, height: 0))
        XCTAssertEqual(MediaInfo.resolution(width: 720, height: 480), "720 × 480 (480p)")
    }

    func testTheCastIsInBillingOrderLimitedAndBlankValuesDropped() {
        var people = (0..<20).map { Person(id: $0, name: "Sample Actor \($0)", character: $0 == 19 ? " " : "Sample Role", order: 19 - $0) }
        people.append(Person(id: 99, name: "  ", order: -1))
        let d = TitleDetails(overview: "  ", people: people)
        XCTAssertNil(d.overview)
        XCTAssertEqual(d.cast.count, TitleDetails.castLimit)
        XCTAssertEqual(d.cast.first?.name, "Sample Actor 19")
        XCTAssertNil(d.cast.first?.role, "a blank role is dropped")
        XCTAssertFalse(d.isEmpty)
    }

    func testTheDetailPageCarriesTheMediaInfoOfThePreferredFile() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var vm = ItemDetailViewModel(store: rig.store, itemID: try await rig.movieID("Heat"))
        await vm.load()
        let content = try XCTUnwrap(vm.state.content)
        XCTAssertEqual(content.mediaInfo.count, 11)
        XCTAssertEqual(content.mediaInfo.last?.label, "Path")
        XCTAssertTrue(content.mediaInfo.last?.value.hasSuffix(".mkv") ?? false, "\(content.mediaInfo)")
    }
}
