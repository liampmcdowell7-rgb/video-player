import XCTest
@testable import ScreenChecks

/// R471 (74), PROVISIONAL (owner 25 Nov 2026 round 8, Part B item 3, finding F): a scan asked for while one runs (a source
/// just added, a sort setting changed) is not lost. Before, the caller only waited for the running scan, which had read the
/// list of sources when it started, so a source added meanwhile was not scanned until the next launch or the next scan;
/// and a second call right after could find the finished scan's handle and return without scanning. Now the running scan
/// goes round once more for every request made while it ran, and clears its own handle with no wait after its last check.
/// Structure only, from the source: nothing is compiled or run on tvOS.
extension ScreenChecksTests {
    func testAScanAskedForDuringAScanIsNotLost() throws {
        guard let services = try appSource("App/Support/AppServices.swift") else { return }
        guard let start = services.range(of: "    func scanAll() async {"),
              let end = services.range(of: "\n    }\n", range: start.upperBound..<services.endIndex) else {
            return XCTFail("scanAll not found")
        }
        let body = services[start.upperBound..<end.lowerBound]
        XCTAssertTrue(body.contains("if let running = scanTask { scanAgain = true; await running.value; return }"),
                      "a call during a scan asks for one more round and waits for it")
        XCTAssertTrue(body.contains("repeat {"))
        XCTAssertTrue(body.contains("scanAgain = false"))
        XCTAssertTrue(body.contains("} while scanAgain\n            scanTask = nil"),
                      "the handle is cleared right after the last check, with no wait between")
        XCTAssertFalse(body.contains("await task.value\n        scanTask = nil"), "no stale handle after the scan ended")
        XCTAssertTrue(services.contains("@ObservationIgnored private var scanAgain = false"))
    }
}
