import XCTest
@testable import ScreenChecks

/// R471 (73), PROVISIONAL (owner 25 Nov 2026 round 8, Part B item 3, finding E): in Change Artwork, a picture still being
/// fetched when the user chooses Automatic (or another choice) is not set when it arrives. Each choice and Automatic take a
/// new number; a fetch sets its picture only when no newer choice was made while it waited. Structure only, from the source.
extension ScreenChecksTests {
    func testAnArtworkChoiceThatArrivesAfterAutomaticIsNotSet() throws {
        guard let gallery = try appSource("App/Features/Edit/ArtworkGalleryView.swift") else { return }
        XCTAssertTrue(gallery.contains("@State private var choiceGeneration = 0"))
        func body(_ start: String) -> Substring? {
            guard let open = gallery.range(of: start),
                  let end = gallery.range(of: "\n    }\n", range: open.upperBound..<gallery.endIndex) else { return nil }
            return gallery[open.upperBound..<end.lowerBound]
        }
        for name in ["private func choose(_ candidate: ArtworkCandidate) async {", "private func chooseWebAddress() async {"] {
            guard let text = body(name) else { return XCTFail("\(name) not found") }
            XCTAssertTrue(text.contains("choiceGeneration += 1"), "\(name): a choice takes a new number")
            XCTAssertTrue(text.contains("let generation = choiceGeneration"), name)
            XCTAssertTrue(text.contains("guard generation == choiceGeneration else { working = false; return }"),
                          "\(name): a newer choice or Automatic made during the fetch wins")
        }
        guard let auto = body("private func automatic() {") else { return XCTFail("automatic() not found") }
        XCTAssertTrue(auto.contains("choiceGeneration += 1"), "Automatic makes a fetch still running out of date")
    }
}
