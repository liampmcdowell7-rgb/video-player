import XCTest
import VideoPlayerCore
@testable import MetadataOnline

// FIXTURE: hand-written Wikidata SPARQL JSON, shaped like the query's result rows (WikidataClient.query); the titles, item
// ids, ratings and descriptors are invented for the test, not copied from Wikidata. Nothing is contacted.
// R372 (owner's request of 21 Nov 2026): official ratings and content descriptors from the existing Wikidata lookup.
final class WikidataRatingTests: XCTestCase {
    static func row(_ q: String, label: String, cast: String? = nil, board: String? = nil, rating: String? = nil, descriptor: String? = nil) -> String {
        var parts = [#""item":{"type":"uri","value":"http://www.wikidata.org/entity/\#(q)"}"#, #""itemLabel":{"value":"\#(label)"}"#]
        if let cast { parts.append(#""castLabel":{"value":"\#(cast)"}"#) }
        if let board { parts.append(#""board":{"value":"\#(board)"}"#) }
        if let rating { parts.append(#""ratingLabel":{"value":"\#(rating)"}"#) }
        if let descriptor { parts.append(#""descriptorLabel":{"value":"\#(descriptor)"}"#) }
        return "{" + parts.joined(separator: ",") + "}"
    }

    static func body(_ rows: [String]) -> Data {
        Data((#"{"head":{"vars":[]},"results":{"bindings":["# + rows.joined(separator: ",") + "]}}").utf8)
    }

    /// FIXTURE: a film with a rating and two descriptors (one statement, two descriptor rows) and a second system.
    func testAFilmWithARatingAndDescriptors() throws {
        let rows = [
            Self.row("Q900001", label: "Sample Rated Film", cast: "First Actor"),
            Self.row("Q900001", label: "Sample Rated Film", board: "MPA", rating: "R", descriptor: "Violence"),
            Self.row("Q900001", label: "Sample Rated Film", board: "MPA", rating: "R", descriptor: "Strong Language"),
            Self.row("Q900001", label: "Sample Rated Film", board: "BBFC", rating: "15"),
        ]
        let title = try XCTUnwrap(WikidataClient.decode(Self.body(rows), preferringYear: nil))
        XCTAssertEqual(title.cast, ["First Actor"])
        XCTAssertEqual(title.ratings, [WikidataRating(system: "MPA", label: "R", descriptors: ["Violence", "Strong Language"]),
                                       WikidataRating(system: "BBFC", label: "15")])
    }

    /// FIXTURE: a film with a rating only (no descriptor qualifier).
    func testAFilmWithARatingOnly() throws {
        let rows = [Self.row("Q900002", label: "Sample Plain Film", board: "FSK", rating: "FSK 12")]
        let title = try XCTUnwrap(WikidataClient.decode(Self.body(rows), preferringYear: nil))
        XCTAssertEqual(title.ratings, [WikidataRating(system: "FSK", label: "FSK 12")])
    }

    /// FIXTURE: a film with neither: no ratings at all (nil, as before R372), and a bare item id is never a label.
    func testAFilmWithNeither() throws {
        let rows = [Self.row("Q900003", label: "Sample Unrated Film", cast: "Only Actor"),
                    Self.row("Q900003", label: "Sample Unrated Film", board: "MPA", rating: "Q123456")]
        let title = try XCTUnwrap(WikidataClient.decode(Self.body(rows), preferringYear: nil))
        XCTAssertNil(title.ratings)
        XCTAssertEqual(title, WikidataTitle(qid: "Q900003", label: "Sample Unrated Film", cast: ["Only Actor"]))
    }

    /// The query asks the five rating properties and the descriptor qualifier, in a UNION with the cast.
    func testTheQueryAsksTheRatingPropertiesInTheSameRequest() {
        let q = WikidataClient.query(pattern: "?item wdt:P4947 \"77\" .", language: "en")
        for p in ["P1657", "P2629", "P1981", "P3156", "P3216"] { XCTAssertTrue(q.contains("p:\(p) ps:\(p)"), p) }
        XCTAssertTrue(q.contains("pq:P7367 ?descriptor"))
        XCTAssertTrue(q.contains("UNION"))
        XCTAssertTrue(q.contains("?ratingLabel ?descriptorLabel"))
    }

    /// A title cached before R372 (no "ratings" key) still decodes.
    func testAnOldCacheEntryStillDecodes() throws {
        let old = Data(#"{"qid":"Q1","label":"Old","cast":["A"]}"#.utf8)
        XCTAssertEqual(WikidataClient.decodeCached(old), WikidataTitle(qid: "Q1", label: "Old", cast: ["A"]))
    }
}
