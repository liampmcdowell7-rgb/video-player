import XCTest
@testable import ScreenChecks

/// R471 (90): Settings > Playback lists the last converted play's loopback requests right under Last Playback Problem, and
/// the trail is set only when a converted play starts (no work otherwise).
extension ScreenChecksTests {
    func testLoopbackRequestsSitUnderLastPlaybackProblem() throws {
        guard let playback = try appSource("App/Features/Settings/PlaybackSettingsView.swift"),
              let remux = try appSource("App/Features/Player/RemuxPlayback.swift") else { return }
        let problem = try XCTUnwrap(playback.range(of: "Section(PlaybackProblem.sectionTitle)"), "no Last Playback Problem")
        let requests = try XCTUnwrap(playback.range(of: "Text(LoopbackRequestsText.sectionTitle)"), "no Loopback Requests section")
        let focus = try XCTUnwrap(playback.range(of: "Text(ScrollDiagnosticsText.focusSectionTitle)"))
        XCTAssertLessThan(problem.lowerBound, requests.lowerBound, "Loopback Requests is not under Last Playback Problem")
        XCTAssertLessThan(requests.lowerBound, focus.lowerBound, "Loopback Requests is not right under Last Playback Problem")
        XCTAssertTrue(playback.contains("LoopbackRequestsStore.last?.rows ?? []"))
        XCTAssertTrue(remux.contains("LoopbackRequestsStore.last = host.requestTrail"), "a converted play does not publish its trail")
    }
}
