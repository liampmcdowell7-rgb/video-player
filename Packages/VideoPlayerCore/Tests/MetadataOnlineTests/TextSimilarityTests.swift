import XCTest
@testable import MetadataOnline

final class TextSimilarityTests: XCTestCase {
    func testNormalizeBasics() {
        XCTAssertEqual(TitleText.normalize("The Marrowgate"), "marrowgate")
        XCTAssertEqual(TitleText.normalize("  A Hushed Room "), "hushed room")
        XCTAssertEqual(TitleText.normalize("An Orchard Tale"), "orchard tale")
        XCTAssertEqual(TitleText.normalize("Marrowgate, The"), "marrowgate")
        XCTAssertEqual(TitleText.normalize("Hushed Room, A"), "hushed room")
        XCTAssertEqual(TitleText.normalize(""), "")
        XCTAssertEqual(TitleText.normalize("!!!"), "")
    }

    func testArticleOnlyTitlesAreKept() {
        XCTAssertEqual(TitleText.normalize("The"), "the")
        XCTAssertEqual(TitleText.normalize("A"), "a")
    }

    func testPunctuationAndCase() {
        XCTAssertEqual(TitleText.normalize("Kite-Man: Homeward"), "kite man homeward")
        XCTAssertEqual(TitleText.normalize("TIK·T"), TitleText.normalize("Tik-T"))
        XCTAssertEqual(TitleText.normalize("Harbor's Eleven"), "harbors eleven")
        XCTAssertEqual(TitleText.normalize("Harbor\u{2019}s Eleven"), "harbors eleven")
        XCTAssertEqual(TitleText.normalize("Mr. & Mrs. Pemberton"), "mr and mrs pemberton")
        XCTAssertEqual(TitleText.normalize("Pip & Wren"), TitleText.normalize("Pip and Wren"))
        XCTAssertEqual(TitleText.normalize("What...?"), "what")
        XCTAssertEqual(TitleText.normalize("Fo4r"), "fo4r")
    }

    func testAbbreviationsWithDotsJoin() {
        XCTAssertEqual(TitleText.normalize("Agents of S.P.A.R.R.O.W."), "agents of sparrow")
        XCTAssertEqual(TitleText.normalize("Agents of SPARROW"), "agents of sparrow")
        XCTAssertEqual(TitleText.normalize("T*E*N*T"), "tent")
        XCTAssertEqual(TitleText.normalize("I Am Lantern"), "i am lantern", "a single letter between words is not joined")
        XCTAssertEqual(TitleText.normalize("Q-Folk"), "q folk")
    }

    func testAccentsAreFolded() {
        XCTAssertEqual(TitleText.normalize("Amélise"), "amelise")
        XCTAssertEqual(TitleText.normalize("Pebblémon"), "pebblemon")
        XCTAssertEqual(TitleText.normalize("Léandre: The Courier"), "leandre the courier")
    }

    func testRomanNumeralsBecomeDigitsButNotWhenAlone() {
        XCTAssertEqual(TitleText.normalize("Brisk II"), TitleText.normalize("Brisk 2"))
        XCTAssertEqual(TitleText.normalize("Final Reverie VII"), "final reverie 7")
        XCTAssertEqual(TitleText.normalize("Part IV"), "part 4")
        XCTAssertEqual(TitleText.normalize("X"), "x")
        XCTAssertEqual(TitleText.normalize("Marlow X"), "marlow x", "a lone X is a name, not 10")
        XCTAssertEqual(TitleText.normalize("II"), "ii")
    }

    func testNonLatinScriptsSurvive() {
        XCTAssertEqual(TitleText.normalize("漂う灯籠の夜"), "漂う灯籠の夜")
        XCTAssertEqual(TitleText.normalize("달팽이집"), "달팽이집")
        XCTAssertEqual(TitleText.similarity("달팽이집", "달팽이집"), 1)
        XCTAssertLessThan(TitleText.similarity("달팽이집", "Snailhouse"), 0.5)
    }

    func testSimilarityIdentityAndEmpties() {
        XCTAssertEqual(TitleText.similarity("The Marrowgate", "Marrowgate, The"), 1)
        XCTAssertEqual(TitleText.similarity("Kite-Man", "Kite Man"), 1)
        XCTAssertEqual(TitleText.similarity("", "x"), 0)
        XCTAssertEqual(TitleText.similarity("x", ""), 0)
        XCTAssertEqual(TitleText.similarity("", ""), 0)
    }

    func testSpacingDifferencesAreNearlyIdentical() {
        let s = TitleText.similarity("Kiteman", "Kite Man")
        XCTAssertGreaterThan(s, 0.95)
        XCTAssertLessThan(s, 1)
    }

    func testSmallTyposScoreHigh() {
        XCTAssertGreaterThan(TitleText.similarity("The Marrowgaet", "The Marrowgate"), 0.85)
        XCTAssertGreaterThan(TitleText.similarity("Inverlane", "Inverlnae"), 0.9)
    }

    func testDifferentTitlesScoreLow() {
        XCTAssertLessThan(TitleText.similarity("The Marrowgate", "Finding Pellow"), 0.5)
        XCTAssertLessThan(TitleText.similarity("Dunerra", "Hexfall"), 0.6)
        XCTAssertLessThan(TitleText.similarity("Bttl Rygl", "Brass Ranger"), 0.6)
    }

    func testContainmentAtWordBoundaries() {
        let multi = TitleText.similarity("Sky Lanes", "Sky Lanes A New Dawn")
        XCTAssertEqual(multi, 0.85, accuracy: 0.0001)
        let single = TitleText.similarity("Marrowgate", "The Marrowgate Reloaded")
        XCTAssertEqual(single, 0.7, accuracy: 0.0001, "one word inside a longer title is weaker evidence")
        XCTAssertLessThan(TitleText.similarity("Star", "Starship Couriers"), 0.7, "not at a word boundary")
    }

    func testSimilarityIsSymmetric() {
        for (a, b) in [("Dunerra", "Dunerra Part Two"), ("The Bureau", "Bureau Space"), ("Amélise", "Amelise from Montclair")] {
            XCTAssertEqual(TitleText.similarity(a, b), TitleText.similarity(b, a), accuracy: 1e-9)
        }
    }

    func testNonIdenticalTitlesNeverReachOne() {
        XCTAssertLessThan(TitleText.similarity("Dunerra", "Dunerra 2"), 1)
        XCTAssertLessThanOrEqual(TitleText.similarity("Aftlander", "Aftlanders"), 0.97)
    }

    func testBestSimilarityTakesTheBestName() {
        let s = TitleText.bestSimilarity(query: "La Bóveda de Papel", names: ["Paper Vault", "La bóveda de papel"])
        XCTAssertEqual(s, 1)
        XCTAssertEqual(TitleText.bestSimilarity(query: "x", names: []), 0)
    }

    func testLevenshteinAndJaroWinklerKnownValues() {
        XCTAssertEqual(TitleText.levenshtein(Array("kitten"), Array("sitting")), 3)
        XCTAssertEqual(TitleText.levenshtein(Array(""), Array("abc")), 3)
        XCTAssertEqual(TitleText.levenshtein(Array("abc"), Array("abc")), 0)
        XCTAssertEqual(TitleText.jaroWinkler(Array("martha"), Array("marhta")), 0.9611, accuracy: 0.0005)
        XCTAssertEqual(TitleText.jaroWinkler(Array("dixon"), Array("dicksonx")), 0.8133, accuracy: 0.0005)
        XCTAssertEqual(TitleText.jaroWinkler(Array("abc"), Array("xyz")), 0)
        XCTAssertEqual(TitleText.jaroWinkler(Array(""), Array("a")), 0)
    }
}
