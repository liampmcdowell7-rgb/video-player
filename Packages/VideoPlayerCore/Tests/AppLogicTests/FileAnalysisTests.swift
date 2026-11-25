import XCTest
import VideoPlayerCore
import LibraryIndex
import PlaybackLogic
@testable import AppLogic

/// R471 (19), Part 4: Analyze File reads the streams again and keeps them, finds an episode's intro and credits again even
/// when it was analysed before, says what it found, and reports each step as it starts.
final class FileAnalysisTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("analyze-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func provider(_ rig: LibraryRig, detection: SeasonDetectionStore) -> SegmentProvider {
        SegmentProvider(store: rig.store, ledger: nil, itemKey: { _ in nil }, openSource: { _ in nil }, detection: detection)
    }

    private let tracks = FileTrackDetails(frameRate: 24, audio: [.init(codec: "eac3", channels: 6, language: "en", name: nil, isDefault: true)],
                                          subtitles: [.init(codec: "SRT", language: "en", name: nil, isForced: false, isHearingImpaired: false),
                                                      .init(codec: "SRT", language: "de", name: nil, isForced: false, isHearingImpaired: false)])

    func testAMovieGetsItsStreamsReadAgainAndKept() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        let steps = Steps()
        let analyzer = FileAnalyzer(store: rig.store, provider: provider(rig, detection: SeasonDetectionStore(directory: try folder())),
                                    readTracks: { [tracks] _ in tracks }, analyseAudio: { _ in XCTFail("a movie has no intro step"); return false })
        let report = await analyzer.run(itemID: id) { await steps.add($0) }
        XCTAssertEqual(report, FileAnalysis.Report(streams: .read(audio: 1, subtitles: 2), segments: .notAnEpisode))
        let seen = await steps.list
        XCTAssertEqual(seen, [.streams])
        let file = try await rig.store.versions(of: id).first
        let kept = try await rig.store.trackDetails(fileID: try XCTUnwrap(file).id)
        XCTAssertEqual(kept, tracks)
        XCTAssertEqual(FileAnalysis.lines(report!), ["Streams read: 1 audio track, 2 subtitle tracks."])
    }

    func testAnEpisodeIsAnalysedAgainEvenWhenItWasBefore() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let episodes = try await rig.episodes(ofSeriesTitle: "Show One")
        let episode = try XCTUnwrap(episodes.first { $0.season == 1 })
        try await rig.store.updateProgress(itemID: episode.id, position: 0, duration: 1_500, at: epoch)
        let detection = SeasonDetectionStore(directory: try folder())
        let segments = provider(rig, detection: detection)
        let first = await segments.analysisTarget(forItem: episode.id)
        let target = try XCTUnwrap(first)
        await segments.store(EpisodeAnalysis.record(file: target.file, intro: nil, credits: nil), for: target)
        let again = await segments.analysisTarget(forItem: episode.id)
        XCTAssertNil(again, "the background pass skips a file it analysed before")

        let analysed = Steps()
        let analyzer = FileAnalyzer(store: rig.store, provider: segments, readTracks: { _ in nil }) { target in
            await analysed.add(.introAndCredits)
            await segments.store(EpisodeAnalysis.record(file: target.file, intro: nil, credits: nil), for: target)
            return true
        }
        let steps = Steps()
        let report = await analyzer.run(itemID: episode.id) { await steps.add($0) }
        XCTAssertEqual(report, FileAnalysis.Report(streams: .failed, segments: .noneYet))
        let ran = await analysed.list
        XCTAssertEqual(ran.count, 1, "Analyze File reads the audio again")
        let seen = await steps.list
        XCTAssertEqual(seen, [.streams, .introAndCredits])
    }

    func testAFailedAudioReadAndAnEpisodeWithoutALengthSaySo() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let episodes = try await rig.episodes(ofSeriesTitle: "Show Two")
        let episode = try XCTUnwrap(episodes.first)
        let analyzer = FileAnalyzer(store: rig.store, provider: provider(rig, detection: SeasonDetectionStore(directory: try folder())),
                                    readTracks: { _ in nil }, analyseAudio: { _ in true })
        let noLength = await analyzer.run(itemID: episode.id)
        XCTAssertEqual(noLength?.segments, .failed)
        let missing = await analyzer.run(itemID: 999_999)
        XCTAssertNil(missing)
    }

    func testTheResultWords() {
        XCTAssertEqual(FileAnalysis.lines(FileAnalysis.Report(streams: .notReadable, segments: .found(intro: true, credits: false))),
                       ["The streams of this kind of file are read when it plays, not here.",
                        "Found the intro. The skip buttons use it from the next playback."])
        XCTAssertTrue(FileAnalysis.lines(FileAnalysis.Report(streams: .read(audio: 2, subtitles: 1), segments: .noneYet))[1]
            .contains("another episode of this season"))
        XCTAssertEqual(FileAnalysis.Step.allCases.map(\.title), ["Reading the file's streams", "Finding the intro and credits"])
    }

    func testAnalyzeIsOfferedWhereThereIsAFile() {
        var movie = ProductActionContext(kind: .movie)
        movie.hasFile = true
        XCTAssertTrue(ProductActions.manageList(movie).contains(.analyze))
        XCTAssertFalse(ProductActions.manageList(ProductActionContext(kind: .movie)).contains(.analyze))
    }
}

private actor Steps {
    var list: [FileAnalysis.Step] = []
    func add(_ step: FileAnalysis.Step) { list.append(step) }
}
