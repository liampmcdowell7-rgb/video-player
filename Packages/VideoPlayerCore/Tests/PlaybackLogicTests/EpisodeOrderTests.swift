import XCTest
@testable import PlaybackLogic

final class EpisodeOrderTests: XCTestCase {
    private func ep(_ season: Int, _ episode: Int, last: Int? = nil, series: String = "s", file: String? = nil) -> EpisodeRef {
        EpisodeRef(seriesID: series, season: season, episode: episode, lastEpisode: last,
                   fileID: file ?? "S\(season)E\(episode).mkv")
    }

    // NE-30
    func testNE30_nextEpisodeInTheSameSeason() {
        let all = [ep(1, 1), ep(1, 2), ep(1, 3)]
        XCTAssertEqual(EpisodeOrder.next(after: ep(1, 1), in: all), .next(ep(1, 2)))
    }

    // NE-31
    func testNE31_inputOrderDoesNotMatter() {
        let all = [ep(2, 1), ep(1, 3), ep(1, 2), ep(1, 1)]
        XCTAssertEqual(EpisodeOrder.next(after: ep(1, 1), in: all), .next(ep(1, 2)))
        XCTAssertEqual(EpisodeOrder.next(after: ep(1, 3), in: all), .next(ep(2, 1)))
    }

    // NE-32
    func testNE32_seasonRolloverGoesToTheFirstEpisodeOfTheNextSeason() {
        let all = [ep(1, 1), ep(1, 2), ep(2, 1), ep(2, 2)]
        XCTAssertEqual(EpisodeOrder.next(after: ep(1, 2), in: all), .next(ep(2, 1)))
    }

    // NE-33
    func testNE33_lastEpisodeOfTheLastSeasonHasNoNext() {
        let all = [ep(1, 1), ep(2, 1), ep(2, 2)]
        XCTAssertEqual(EpisodeOrder.next(after: ep(2, 2), in: all), .none(.endOfSeries))
    }

    // NE-34
    func testNE34_season0NeverAutoAdvances() {
        let all = [ep(0, 1), ep(0, 2), ep(1, 1)]
        XCTAssertEqual(EpisodeOrder.next(after: ep(0, 1), in: all), .none(.special))
        XCTAssertEqual(EpisodeOrder.next(after: ep(0, 2), in: all), .none(.special))
    }

    // NE-35
    func testNE35_rolloverNeverEntersSeason0() {
        let all = [ep(0, 1), ep(1, 1)]
        XCTAssertEqual(EpisodeOrder.next(after: ep(1, 1), in: all), .none(.endOfSeries))
    }

    // NE-36
    func testNE36_gapsAreSkipped_nextIsTheNextAvailable() {
        let all = [ep(1, 1), ep(1, 3), ep(1, 7)]
        XCTAssertEqual(EpisodeOrder.next(after: ep(1, 1), in: all), .next(ep(1, 3)))
        XCTAssertEqual(EpisodeOrder.next(after: ep(1, 3), in: all), .next(ep(1, 7)))
    }

    // NE-37
    func testNE37_missingSeasonIsSkippedAndAMissingFirstEpisodeToo() {
        let all = [ep(1, 5), ep(3, 2), ep(3, 4)]
        XCTAssertEqual(EpisodeOrder.next(after: ep(1, 5), in: all), .next(ep(3, 2)))
    }

    // NE-38
    func testNE38_multiEpisodeFileCountsUpToItsLastEpisode() {
        let all = [ep(1, 1, last: 2), ep(1, 2, file: "dup.mkv"), ep(1, 3)]
        XCTAssertEqual(EpisodeOrder.next(after: ep(1, 1, last: 2), in: all), .next(ep(1, 3)))
    }

    // NE-39
    func testNE39_severalVersionsOfTheSameEpisodeCountOnce() {
        let all = [ep(1, 1), ep(1, 2, file: "S1E2-1080p.mkv"), ep(1, 2, file: "S1E2-4k.mkv"), ep(1, 3)]
        XCTAssertEqual(EpisodeOrder.next(after: ep(1, 1), in: all), .next(ep(1, 2, file: "S1E2-1080p.mkv")))
        XCTAssertEqual(EpisodeOrder.next(after: ep(1, 2, file: "S1E2-4k.mkv"), in: all), .next(ep(1, 3)))
    }

    // NE-40
    func testNE40_otherSeriesAreIgnored() {
        let all = [ep(1, 1), ep(1, 2, series: "other")]
        XCTAssertEqual(EpisodeOrder.next(after: ep(1, 1), in: all), .none(.endOfSeries))
    }

    // NE-41
    func testNE41_libraryProviderLoadsTheSeriesAndResolves() async {
        let provider = LibraryNextEpisodeProvider { seriesID in
            seriesID == "s" ? [self.ep(1, 1), self.ep(1, 2)] : []
        }
        let decision = await provider.nextEpisode(after: ep(1, 1))
        XCTAssertEqual(decision, .next(ep(1, 2)))
    }
}
