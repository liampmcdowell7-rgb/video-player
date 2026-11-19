import XCTest
import Foundation

// #22 A (OPEN_QUESTIONS R195, PROVISIONAL): every film, show, episode and person name the unit tests use is invented.
// This file is the one place to review them. The tests in the other bundles write these names as plain strings (a test
// target cannot import another test target); the check below fails when a name listed here is no longer used anywhere
// under Tests/, so the list cannot go stale silently. Add a name here when a test starts using a new invented title.
//
// The edge cases the names carry, kept from the earlier test strings:
//   year in parentheses, S01E02 / 1x02 / 102 episode patterns, digits in titles ("Room 419", "2047", "417", "1871",
//   "Aquila 13" vs "Aquila 100", "Fo4r"), a leading "The" / "A" / "An", punctuation ("Mr. & Mrs.", "S.P.A.R.R.O.W.",
//   "T*E*N*T", "Kite-Man:", "(700)", "TIK·T"), non-English characters ("Amélise" in every encoding, Japanese, Korean,
//   Spanish "La bóveda de papel"), the same title with different years ("Dunerra" 1984 / 2021, "Professor Where"
//   1963 / 2005) and the folder-hint tie-break cases.
enum TestTitles {
    static let films: [String] = [
        "Hexfall", "The Marrowgate", "The Marrowgate Reloaded", "The Marrowgate Revolutions", "The Marrowgate Collection",
        "マロウゲート", "Dunerra", "Amélise", "Le Petit Monde d'Amélise Vernon", "Drifting Lanterns", "漂う灯籠の夜",
        "Mr. & Mrs. Pemberton", "Kite-Man", "Kite-Man: Homeward", "The Dusk Warden", "Aftlander", "Aftlanders",
        "Mr. Nowhere", "Dr. Oddly", "Zornwick", "Aquila 13", "Aquila 100", "River Of No Harbor", "Silent Fennel", "Zuvio",
        "Room 419", "Ninefold", "1871", "417", "2047: A Quiet Voyage", "(700) Nights of Rain", "青い灯台の物語",
        "The Apiary", "Vanished Wren", "Septima", "Brass Ranger", "Inverlane", "Fo4r", "Léandre: The Courier",
        "Brisk", "TIK·T", "달팽이집", "Snailhouse", "Sky Lanes", "Finding Pellow", "A Hushed Room", "An Orchard Tale",
        "Harbor's Eleven", "T*E*N*T", "I Am Lantern", "Q-Folk", "Pebblémon", "Final Reverie VII", "Marlow X",
        "Starship Couriers", "The Bureau", "Bureau Space", "The Midnight Bakery",
    ]
    static let shows: [String] = [
        "Crossing Brine", "Paper Vault", "La bóveda de papel", "Corwin's Agents of S.P.A.R.R.O.W.",
        "Agents of SPARROW", "Saga of the Starward Wardens", "星海守護伝", "Professor Where", "Pip & Wren",
    ]
    static let episodes: [String] = ["Good Day Bad Day", "Cat's in the Box", "And the Box's in the Lake"]
    static let people: [String] = [
        "Rowan Ashby", "Corin Hale", "Tamsin Vale", "Mira Castell", "Nell Castell", "Dale Hollis", "Warren Holt",
        "Oracle One", "Wren", "Sable",
    ]
    static let companies: [String] = ["North Channel", "North Pier Pictures", "Northlight"]
    static var all: [String] { films + shows + episodes + people + companies }
}

final class TestTitlesTests: XCTestCase {
    func testEveryRegisteredInventedTitleIsStillUsedByATest() throws {
        // Tests/AppLogicTests/<this file> -> Tests/
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let walker = FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil) else {
            #if os(Linux)
            return XCTFail("cannot read \(tests.path)")
            #else
            throw XCTSkip("The test sources are not readable from this test host (\(tests.path)).")
            #endif
        }
        var text = ""
        for case let url as URL in walker where url.pathExtension == "swift" && url.lastPathComponent != "TestTitles.swift" {
            text += (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        #if !os(Linux)
        if text.isEmpty { throw XCTSkip("The test sources are not readable from this test host (\(tests.path)).") }
        #endif
        XCTAssertEqual(Set(TestTitles.all).count, TestTitles.all.count, "a name is listed twice")
        for name in TestTitles.all {
            XCTAssertTrue(text.contains(name), "\(name) is listed in TestTitles.swift but no test uses it")
        }
    }
}
