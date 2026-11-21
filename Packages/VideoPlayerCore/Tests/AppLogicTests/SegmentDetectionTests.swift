import XCTest
import VideoPlayerCore
import PlaybackLogic
import LibraryIndex
@testable import AppLogic

/// R315 and R316: server markers and the on-device memory as collector inputs, and the memory kept per season on disk.
/// Synthetic fingerprints only (random words with a shared block standing in for the theme tune).
final class SegmentDetectionTests: XCTestCase {
    private let frame = Double(AudioFingerprinter.hop) / AudioFingerprinter.workingRate

    private struct Words {
        var state: UInt64
        mutating func next() -> UInt32 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return UInt32(truncatingIfNeeded: state) | 1
        }
    }

    /// 600 frames (about 111 s) of an episode's own sound with the 200-frame theme (about 37 s) at frame `at`.
    private func intro(seed: UInt64, at: Int) -> AudioFingerprint {
        var own = Words(state: seed &* 0x9E37_79B9_7F4A_7C15 | 1)
        var theme = Words(state: 4242)
        let tune = (0..<200).map { _ in theme.next() }
        var frames = (0..<600).map { _ in own.next() }
        for k in 0..<200 { frames[at + k] = tune[k] }
        return AudioFingerprint(frames: frames, frameSeconds: frame, startOffset: 0)
    }

    private func file(_ n: Int) -> FileIdentity { FileIdentity(path: "/tv/Show/S01E0\(n).mkv", size: Int64(n), duration: 1500) }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("detect-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testTheSeasonIsRememberedAcrossLaunches() async throws {
        let folder = try temporaryFolder()
        let season = DetectionSeason(series: "Show One", season: 1)
        let first = SeasonDetectionStore(directory: folder)
        let starts = [40, 120, 10]
        for n in 1...3 {
            let needs = await first.needsAnalysis(file(n), in: season)
            XCTAssertTrue(needs)
            await first.add(EpisodeAudioRecord(file: file(n), intro: intro(seed: UInt64(n), at: starts[n - 1]), credits: nil), in: season)
        }
        let analysed = await first.needsAnalysis(file(2), in: season)
        XCTAssertFalse(analysed)
        let later = SeasonDetectionStore(directory: folder)
        let found = await later.segments(for: file(2), in: season)
        XCTAssertEqual(found.first?.type, .intro)
        XCTAssertEqual(found.first?.source, .onDeviceDetection)
        XCTAssertEqual(found.first?.start ?? -1, Double(120) * frame, accuracy: 1)
        XCTAssertEqual(found.first?.confidence, 0.9, "two partners agree")
        let other = await later.segments(for: file(2), in: DetectionSeason(series: "Show One", season: 2))
        XCTAssertTrue(other.isEmpty, "seasons never mix")
    }

    func testNoTitleEndsUpInAFileName() async throws {
        let folder = try temporaryFolder()
        let store = SeasonDetectionStore(directory: folder)
        await store.add(EpisodeAudioRecord(file: file(1), intro: intro(seed: 1, at: 5), credits: nil),
                        in: DetectionSeason(series: "Private Show Title", season: 3))
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(names.count, 1)
        XCTAssertFalse(names[0].lowercased().contains("private"))
        await store.removeAll()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    func testServerMarkersBecomeFileExactCandidates() {
        let f = file(1)
        let found = ServerMarkerSegments.candidates([ServerSegmentMarker(kind: "intro", start: 61, end: 112),
                                                     ServerSegmentMarker(kind: "credits", start: 1380, end: 1500, isFinal: true),
                                                     ServerSegmentMarker(kind: "recap", start: 0, end: 30)], file: f)
        XCTAssertEqual(found.map(\.type), [.intro, .credits])
        XCTAssertTrue(found.allSatisfy { $0.source == .serverMarkers && $0.confidence == 1 })
        XCTAssertNil(ServerMarkerSegments.lookup(source: nil, path: f.path))
    }

    // MARK: The collector

    private let info = SegmentFileInfo(path: "/tv/Show/S01E02.mkv", size: 2, duration: 1500)

    func testServerMarkersAreUsedAndOnlineTimingsAreNotAsked() async {
        let asked = SegmentFeedTests.Box()
        let collection = await SegmentCollector().collect(
            file: info, source: nil, marks: [],
            online: { _ in asked.append([]); return OnlineSegmentResult(segments: [], note: "asked") },
            serverMarkers: { f in OnlineSegmentResult(segments: ServerMarkerSegments.candidates(
                [ServerSegmentMarker(kind: "intro", start: 60, end: 110)], file: f), note: "Server markers: 1") })
        XCTAssertEqual(collection.segments.first?.source, .serverMarkers)
        XCTAssertTrue(asked.value.isEmpty, "the server's own markers make the online lookup unnecessary")
        XCTAssertTrue(collection.notes.contains("Server markers: 1"))
    }

    func testDetectionConfirmsAnOnlineTimingSoItMaySkipByItself() async {
        let collection = await SegmentCollector().collect(
            file: info, source: nil, marks: [],
            online: { f in OnlineSegmentResult(segments: [SkipSegment(type: .intro, start: 60, end: 110, source: .onlineDatabase,
                                                                      confidence: 0.9, file: f)], note: "online") },
            detected: { f in [SkipSegment(type: .intro, start: 60.5, end: 109.5, source: .onDeviceDetection, confidence: 0.75, file: f)] })
        let intro = collection.resolved.segment(of: .intro)
        XCTAssertEqual(intro?.source, .onlineDatabase)
        XCTAssertEqual(intro?.audioConfirmed, true)
        XCTAssertTrue(SkipController(segments: collection.segments, settings: SkipSettings(intro: .automatic)).allowsAutomatic(intro!))
    }

    func testDetectionAloneGivesTheButtonAfterOnePartner() async {
        let collection = await SegmentCollector().collect(
            file: info, source: nil, marks: [],
            detected: { f in [SkipSegment(type: .intro, start: 30, end: 80, source: .onDeviceDetection,
                                          confidence: SeasonSegmentMemory.confidence(votes: 1), file: f)] })
        let intro = collection.resolved.segment(of: .intro)
        XCTAssertEqual(intro?.source, .onDeviceDetection)
        XCTAssertFalse(SkipController(segments: collection.segments, settings: SkipSettings(intro: .automatic)).allowsAutomatic(intro!))
    }

    // MARK: The provider

    func testTheProviderAsksForEachEpisodeOnceAndThenUsesWhatWasLearned() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let eps = try await rig.episodes(ofSeriesTitle: "Show One").sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
        let store = SeasonDetectionStore(directory: try temporaryFolder())
        let provider = SegmentProvider(store: rig.store, ledger: nil, itemKey: { _ in nil }, openSource: { _ in nil }, detection: store)
        let movie = try await rig.movieID("Hexfall")
        let none = await provider.analysisTarget(forItem: movie)
        XCTAssertNil(none, "films are not compared")
        var targets: [SegmentProvider.AnalysisTarget] = []
        for (n, ep) in eps.prefix(3).enumerated() {
            let versions = try await rig.store.versions(of: ep.id)
            let file = try XCTUnwrap(versions.first)
            try await rig.store.setTechnicalInfo(fileID: file.id, FileTechnicalInfo(duration: 1500))
            let found = await provider.analysisTarget(forItem: ep.id)
            let target = try XCTUnwrap(found)
            XCTAssertEqual(target.introWindow, 0...375)
            XCTAssertEqual(target.creditsWindow, 900...1500)
            await provider.store(EpisodeAudioRecord(file: target.file, intro: intro(seed: UInt64(n + 1), at: [40, 120, 10][n]), credits: nil),
                                 for: target)
            targets.append(target)
            let again = await provider.analysisTarget(forItem: ep.id)
            XCTAssertNil(again, "analysed once")
        }
        let segments = await provider.segments(forItem: eps[1].id)
        XCTAssertEqual(segments.first?.source, .onDeviceDetection)
        XCTAssertEqual(segments.first?.start ?? -1, Double(120) * frame, accuracy: 1)
    }

    func testAnalysingAnEpisodeBuildsBothFingerprints() {
        let rate = AudioFingerprinter.workingRate
        let tone = (0..<Int(rate * 20)).map { Float(0.2 * sin(2 * Double.pi * 440 * Double($0) / rate)) }
        let record = EpisodeAnalysis.record(file: file(1), intro: (tone, rate, 0), credits: (tone, rate, 900))
        XCTAssertEqual(record.intro?.startOffset, 0)
        XCTAssertEqual(record.credits?.startOffset, 900)
        XCTAssertGreaterThan(record.intro?.frames.count ?? 0, 100)
    }
}
