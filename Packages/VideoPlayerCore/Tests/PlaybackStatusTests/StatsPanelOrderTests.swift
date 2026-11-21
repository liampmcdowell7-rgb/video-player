import XCTest
@testable import PlaybackStatus

/// R340: every stat in the info panel, most important first, none left out.
final class StatsPanelOrderTests: XCTestCase {
    func testEveryRowIsKeptAndOrdered() {
        let rows = StatsOverlay.rows(PlaybackStatsSnapshot())
        let panel = StatsOverlay.panelRows(rows)
        XCTAssertEqual(panel.count, rows.count, "none collapsed or dropped")
        XCTAssertEqual(Set(panel.map(\.label)), Set(rows.map(\.label)))
        XCTAssertEqual(Set(rows.map(\.label)), Set(StatsOverlay.panelOrder), "the order names every stat there is")
        XCTAssertEqual(panel.map(\.label), StatsOverlay.panelOrder)
        XCTAssertEqual(panel.first?.label, "Resolution")
    }

    func testAnUnknownRowKeepsItsPlaceAtTheEnd() {
        let rows = [StatRow(label: "New stat", value: "1", tone: .normal), StatRow(label: "Container", value: "MKV", tone: .normal),
                    StatRow(label: "Resolution", value: "4K", tone: .normal)]
        XCTAssertEqual(StatsOverlay.panelRows(rows).map(\.label), ["Resolution", "Container", "New stat"])
    }
}
