import XCTest
@testable import MetadataOnline

final class TextSimilarityTests: XCTestCase {
    func testNormalizeBasics() {
        XCTAssertEqual(TitleText.normalize("The Matrix"), "matrix")
        XCTAssertEqual(TitleText.normalize("  A Quiet Place "), "quiet place")
        XCTAssertEqual(TitleText.normalize("An American Tail"), "american tail")
        XCTAssertEqual(TitleText.normalize("Matrix, The"), "matrix")
        XCTAssertEqual(TitleText.normalize("Quiet Place, A"), "quiet place")
        XCTAssertEqual(TitleText.normalize(""), "")
        XCTAssertEqual(TitleText.normalize("!!!"), "")
    }

    func testArticleOnlyTitlesAreKept() {
        XCTAssertEqual(TitleText.normalize("The"), "the")
        XCTAssertEqual(TitleText.normalize("A"), "a")
    }

    func testPunctuationAndCase() {
        XCTAssertEqual(TitleText.normalize("Spider-Man: Homecoming"), "spider man homecoming")
        XCTAssertEqual(TitleText.normalize("WALL·E"), TitleText.normalize("Wall-E"))
        XCTAssertEqual(TitleText.normalize("Ocean's Eleven"), "oceans eleven")
        XCTAssertEqual(TitleText.normalize("Ocean\u{2019}s Eleven"), "oceans eleven")
        XCTAssertEqual(TitleText.normalize("Mr. & Mrs. Smith"), "mr and mrs smith")
        XCTAssertEqual(TitleText.normalize("Tom & Jerry"), TitleText.normalize("Tom and Jerry"))
        XCTAssertEqual(TitleText.normalize("What...?"), "what")
        XCTAssertEqual(TitleText.normalize("Se7en"), "se7en")
    }

    func testAbbreviationsWithDotsJoin() {
        XCTAssertEqual(TitleText.normalize("Agents of S.H.I.E.L.D."), "agents of shield")
        XCTAssertEqual(TitleText.normalize("Agents of SHIELD"), "agents of shield")
        XCTAssertEqual(TitleText.normalize("M*A*S*H"), "mash")
        XCTAssertEqual(TitleText.normalize("I Am Legend"), "i am legend", "a single letter between words is not joined")
        XCTAssertEqual(TitleText.normalize("X-Men"), "x men")
    }

    func testAccentsAreFolded() {
        XCTAssertEqual(TitleText.normalize("Amélie"), "amelie")
        XCTAssertEqual(TitleText.normalize("Pokémon"), "pokemon")
        XCTAssertEqual(TitleText.normalize("Léon: The Professional"), "leon the professional")
    }

    func testRomanNumeralsBecomeDigitsButNotWhenAlone() {
        XCTAssertEqual(TitleText.normalize("Rocky II"), TitleText.normalize("Rocky 2"))
        XCTAssertEqual(TitleText.normalize("Final Fantasy VII"), "final fantasy 7")
        XCTAssertEqual(TitleText.normalize("Part IV"), "part 4")
        XCTAssertEqual(TitleText.normalize("X"), "x")
        XCTAssertEqual(TitleText.normalize("Malcolm X"), "malcolm x", "a lone X is a name, not 10")
        XCTAssertEqual(TitleText.normalize("II"), "ii")
    }

    func testNonLatinScriptsSurvive() {
        XCTAssertEqual(TitleText.normalize("千と千尋の神隠し"), "千と千尋の神隠し")
        XCTAssertEqual(TitleText.normalize("기생충"), "기생충")
        XCTAssertEqual(TitleText.similarity("기생충", "기생충"), 1)
        XCTAssertLessThan(TitleText.similarity("기생충", "Parasite"), 0.5)
    }

    func testSimilarityIdentityAndEmpties() {
        XCTAssertEqual(TitleText.similarity("The Matrix", "Matrix, The"), 1)
        XCTAssertEqual(TitleText.similarity("Spider-Man", "Spider Man"), 1)
        XCTAssertEqual(TitleText.similarity("", "x"), 0)
        XCTAssertEqual(TitleText.similarity("x", ""), 0)
        XCTAssertEqual(TitleText.similarity("", ""), 0)
    }

    func testSpacingDifferencesAreNearlyIdentical() {
        let s = TitleText.similarity("Spiderman", "Spider Man")
        XCTAssertGreaterThan(s, 0.95)
        XCTAssertLessThan(s, 1)
    }

    func testSmallTyposScoreHigh() {
        XCTAssertGreaterThan(TitleText.similarity("The Matirx", "The Matrix"), 0.85)
        XCTAssertGreaterThan(TitleText.similarity("Inception", "Inceptoin"), 0.9)
    }

    func testDifferentTitlesScoreLow() {
        XCTAssertLessThan(TitleText.similarity("The Matrix", "Finding Nemo"), 0.5)
        XCTAssertLessThan(TitleText.similarity("Dune", "Heat"), 0.6)
        XCTAssertLessThan(TitleText.similarity("Bttl Rygl", "Blade Runner"), 0.6)
    }

    func testContainmentAtWordBoundaries() {
        let multi = TitleText.similarity("Star Wars", "Star Wars A New Hope")
        XCTAssertEqual(multi, 0.85, accuracy: 0.0001)
        let single = TitleText.similarity("Matrix", "The Matrix Reloaded")
        XCTAssertEqual(single, 0.7, accuracy: 0.0001, "one word inside a longer title is weaker evidence")
        XCTAssertLessThan(TitleText.similarity("Star", "Starship Troopers"), 0.7, "not at a word boundary")
    }

    func testSimilarityIsSymmetric() {
        for (a, b) in [("Dune", "Dune Part Two"), ("The Office", "Office Space"), ("Amélie", "Amelie from Montmartre")] {
            XCTAssertEqual(TitleText.similarity(a, b), TitleText.similarity(b, a), accuracy: 1e-9)
        }
    }

    func testNonIdenticalTitlesNeverReachOne() {
        XCTAssertLessThan(TitleText.similarity("Dune", "Dune 2"), 1)
        XCTAssertLessThanOrEqual(TitleText.similarity("Alien", "Aliens"), 0.97)
    }

    func testBestSimilarityTakesTheBestName() {
        let s = TitleText.bestSimilarity(query: "La Casa de Papel", names: ["Money Heist", "La casa de papel"])
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
