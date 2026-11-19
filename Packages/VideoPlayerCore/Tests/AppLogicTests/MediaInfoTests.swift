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
        XCTAssertEqual(value(r, "Frame Rate"), MediaInfo.notKnown, "not read from the header yet; never guessed")
        XCTAssertEqual(value(r, "Bitrate"), "57.6 Mbit/s")
        XCTAssertEqual(value(r, "Audio"), "Dolby TrueHD with Dolby Atmos 7.1")
        XCTAssertEqual(value(r, "Subtitles"), "In the file: not known; files: Sample Movie (2020).en.srt")
        XCTAssertEqual(value(r, "Container"), "MKV")
        XCTAssertEqual(value(r, "Source"), "Sample Server")
        XCTAssertEqual(value(r, "Path"), "/Movies/Sample Movie (2020)/Sample Movie (2020).mkv")
    }

    func testAFileWithNothingKnownSaysSoInsteadOfGuessing() {
        let r = rows(nil, size: nil)
        for label in ["Resolution", "HDR", "Video", "Bitrate", "Audio", "Container", "File Size", "Source"] {
            XCTAssertEqual(value(r, label), MediaInfo.notKnown, label)
        }
        XCTAssertEqual(value(r, "Frame Rate"), MediaInfo.notKnown)
        XCTAssertEqual(value(r, "Subtitles"), "In the file: not known; no subtitle files next to the video")
    }

    // #21 C: what the file's header says, once read.

    private let readTracks = FileTrackDetails(
        frameRate: 23.976023976,
        audio: [FileTrackDetails.Audio(codec: "truehd", channels: 8, language: "eng", name: nil, isDefault: true),
                FileTrackDetails.Audio(codec: "ac3", channels: 6, language: "fre", name: nil, isDefault: false),
                FileTrackDetails.Audio(codec: "aac", channels: 2, language: "eng", name: "Sample commentary", isDefault: false, isCommentary: true)],
        subtitles: [FileTrackDetails.Subtitle(codec: "PGS", language: "eng", name: nil, isForced: false, isHearingImpaired: false),
                    FileTrackDetails.Subtitle(codec: "SRT", language: "fre", name: nil, isForced: true, isHearingImpaired: false)])

    func testReadTracksGiveTheFrameRateEveryAudioTrackAndTheEmbeddedSubtitles() {
        let t = FileTechnicalInfo(container: .mkv, height: 2160, videoCodec: "hevc", audioCodec: "truehd", audioChannels: 8, hasAtmos: true)
        let r = MediaInfo.rows(technical: t, size: 1, path: "/Movies/Sample Movie.mkv", subtitleNames: ["Sample Movie.de.srt"],
                               sourceName: nil, tracks: readTracks)
        XCTAssertEqual(r.map(\.label), ["Resolution", "HDR", "Video", "Frame Rate", "Bitrate", "Audio 1", "Audio 2", "Audio 3",
                                        "Subtitles", "Container", "File Size", "Source", "Path"], "most important first, every track")
        XCTAssertEqual(value(r, "Frame Rate"), "23.976 fps")
        XCTAssertEqual(value(r, "Audio 1"), "Dolby TrueHD 7.1 · English · default", "Atmos is not claimed from the header")
        XCTAssertEqual(value(r, "Audio 2"), "Dolby Digital 5.1 · French")
        XCTAssertEqual(value(r, "Audio 3"), "AAC Stereo · English · commentary · “Sample commentary”")
        XCTAssertEqual(value(r, "Subtitles"), "In the file: English (PGS), French (SRT, forced); files: Sample Movie.de.srt")
    }

    func testOneTrackKeepsThePlainLabelAndNoEmbeddedSubtitlesSaysSo() {
        let one = FileTrackDetails(frameRate: 25, audio: [FileTrackDetails.Audio(codec: "eac3", channels: 6, language: nil, name: nil, isDefault: true)],
                                   subtitles: [])
        let r = MediaInfo.rows(technical: nil, size: nil, path: "/a.mkv", subtitleNames: [], sourceName: nil, tracks: one)
        XCTAssertEqual(value(r, "Frame Rate"), "25 fps")
        XCTAssertNotNil(value(r, "Audio"))
        XCTAssertNil(value(r, "Audio 1"))
        XCTAssertEqual(value(r, "Subtitles"), "None in the file; no subtitle files next to the video")
        XCTAssertNil(MediaInfo.frameRate(0))
        XCTAssertEqual(MediaInfo.frameRate(29.97), "29.97 fps")
    }

    func testTheDetailPageReadsTheHeaderOnceAndKeepsIt() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        let reads = Counter()
        let tracks = readTracks
        var vm = ItemDetailViewModel(store: rig.store, itemID: id, trackReader: { _ in await reads.add(); return tracks })
        await vm.load()
        XCTAssertEqual(vm.state.content.flatMap { c in c.mediaInfo.first { $0.label == "Frame Rate" }?.value }, MediaInfo.notKnown,
                       "\"Not known\" until the header is read")
        await vm.loadTrackDetails()
        XCTAssertEqual(vm.state.content.flatMap { c in c.mediaInfo.first { $0.label == "Frame Rate" }?.value }, "23.976 fps")
        XCTAssertEqual(vm.state.content?.mediaInfo.filter { $0.label.hasPrefix("Audio") }.count, 3)

        var again = ItemDetailViewModel(store: rig.store, itemID: id, trackReader: { _ in await reads.add(); return nil })
        await again.load()
        XCTAssertEqual(again.state.content.flatMap { c in c.mediaInfo.first { $0.label == "Frame Rate" }?.value }, "23.976 fps",
                       "kept in the library index")
        await again.loadTrackDetails()
        let count = await reads.value
        XCTAssertEqual(count, 1, "read once per file")
    }

    func testAFailedReadLeavesNotKnown() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var vm = ItemDetailViewModel(store: rig.store, itemID: try await rig.movieID("Hexfall"), trackReader: { _ in nil })
        await vm.load()
        await vm.loadTrackDetails()
        XCTAssertEqual(vm.state.content.flatMap { c in c.mediaInfo.first { $0.label == "Frame Rate" }?.value }, MediaInfo.notKnown)
    }

    func testTheProbeMapsAHeaderAndOnlyReadsMatroska() {
        XCTAssertEqual(MediaTrackProbe.subtitleCodec("S_TEXT/UTF8"), "SRT")
        XCTAssertEqual(MediaTrackProbe.subtitleCodec("S_HDMV/PGS"), "PGS")
        XCTAssertEqual(MediaTrackProbe.subtitleCodec("S_SOMETHING"), "S_SOMETHING")
        XCTAssertTrue(MediaTrackProbe.canRead(name: "Sample Movie.mkv"))
        XCTAssertTrue(MediaTrackProbe.canRead(name: "Sample Movie.webm"))
        XCTAssertFalse(MediaTrackProbe.canRead(name: "Sample Movie.mp4"), "MP4 is not read in this version (R192)")
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
        var vm = ItemDetailViewModel(store: rig.store, itemID: try await rig.movieID("Hexfall"))
        await vm.load()
        let content = try XCTUnwrap(vm.state.content)
        XCTAssertEqual(content.mediaInfo.count, 11)
        XCTAssertEqual(content.mediaInfo.last?.label, "Path")
        XCTAssertTrue(content.mediaInfo.last?.value.hasSuffix(".mkv") ?? false, "\(content.mediaInfo)")
    }
}

private actor Counter {
    private(set) var value = 0
    func add() { value += 1 }
}
