import XCTest
@testable import ScreenChecks

/// R471 (66), PROVISIONAL (owner 25 Nov 2026 round 7, Part B item 2, finding P3): only the newest reload of the skip button
/// and Up Next logic is installed. Each reload reads the segments and builds the overlay in its own task; a mark made during
/// playback starts a second one while the first may still run, and whichever finished last was installed, so an older
/// reload could replace the one that knew the new mark. Structure only, from the source: nothing is compiled or run on tvOS.
extension ScreenChecksTests {
    func testOnlyTheNewestOverlayReloadIsInstalled() throws {
        guard let coordinator = try appSource("App/Features/Player/PlayerCoordinator.swift") else { return }
        XCTAssertTrue(coordinator.contains("overlayGeneration += 1\n        let generation = overlayGeneration"))
        XCTAssertTrue(coordinator.contains("guard let self, !self.stopped, generation == self.overlayGeneration else { return }\n            self.overlay = made"))
    }
}
