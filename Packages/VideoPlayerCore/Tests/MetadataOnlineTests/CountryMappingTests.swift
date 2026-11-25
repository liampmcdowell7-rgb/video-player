import XCTest
@testable import MetadataOnline

/// R471 item 5: Region of Origin comes from the details we already fetch (no new request).
final class CountryMappingTests: XCTestCase {
    private func json(_ text: String) throws -> JSON { try JSON(data: Data(text.utf8)) }

    func testAMoviesCountriesAreItsProductionCountries() throws {
        let movie = try XCTUnwrap(TMDBMapper.movie(try json(#"{"id":1,"title":"A","production_countries":[{"iso_3166_1":"gb","name":"x"},{"iso_3166_1":"US"},{"iso_3166_1":"GB"}],"origin_country":["FR"]}"#),
                                                    language: nil, region: "US"))
        XCTAssertEqual(movie.countries, ["GB", "US"], "upper case, each once, production countries first")
    }

    func testAMovieWithoutProductionCountriesTakesItsOriginCountry() throws {
        let movie = try XCTUnwrap(TMDBMapper.movie(try json(#"{"id":1,"title":"A","production_countries":[],"origin_country":["fr"]}"#), language: nil, region: "US"))
        XCTAssertEqual(movie.countries, ["FR"])
        let none = try XCTUnwrap(TMDBMapper.movie(try json(#"{"id":1,"title":"A"}"#), language: nil, region: "US"))
        XCTAssertNil(none.countries)
    }

    func testAShowsCountriesAreItsOriginCountries() throws {
        let show = try XCTUnwrap(TMDBMapper.series(try json(#"{"id":2,"name":"B","origin_country":["KR","", "kr","USA"]}"#), language: nil, region: "US"))
        XCTAssertEqual(show.countries, ["KR"], "blank and three-letter codes are left out")
    }

    func testDetailsCachedBeforeTheFieldStillDecode() throws {
        let old = MovieMetadata(ids: ProviderIDs(tmdb: 5), title: "Old")
        var data = try JSONEncoder().encode(old)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "countries")
        data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(try JSONDecoder().decode(MovieMetadata.self, from: data).countries)
    }
}
