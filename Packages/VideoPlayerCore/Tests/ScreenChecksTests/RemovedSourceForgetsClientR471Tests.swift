import XCTest
@testable import ScreenChecks

/// R471 (68), PROVISIONAL (owner 25 Nov 2026 round 8, Part B item 2): removing a source and every save of an edited
/// definition let the kept Plex client go. Structure only, from the source: nothing is compiled or run on tvOS.
extension ScreenChecksTests {
    func testRemovingOrEditingASourceForgetsItsKeptClient() throws {
        guard let services = try appSource("App/Support/AppServices.swift"),
              let factory = try appSource("App/Support/SourceFactory.swift") else { return }
        guard let remove = services.range(of: "func removeSource(id: String) async {"),
              let end = services.range(of: "\n    }\n", range: remove.upperBound..<services.endIndex) else {
            return XCTFail("removeSource not found")
        }
        XCTAssertTrue(services[remove.upperBound..<end.lowerBound].contains("sourceFactory.forgetLiveSource(id: id)"),
                      "a removed source's client is let go")
        XCTAssertTrue(services.contains("ForgettingDefinitionSaver(inner: LedgerSourceDefinitions(ledger: ledger, essentials: essentials),"),
                      "every definition save goes through the forgetting saver")
        XCTAssertTrue(services.contains("forget: sourceFactory.liveSourceForgetter)"))
        XCTAssertTrue(factory.contains("var liveSourceForgetter: @Sendable (String) -> Void { { [live] id in live.forget(id: id) } }"))
    }
}
