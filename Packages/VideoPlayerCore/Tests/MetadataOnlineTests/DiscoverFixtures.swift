import Foundation

// FIXTURE FILE for the Discover tests (MetadataOnline and AppLogic read the same shapes).
//
// FIXTURE: shaped like the service's documented reply. Hand-written from TMDB's public documentation for
// /movie/{id}/similar and /movie/{id}/watch/providers (read 2026-11-17), NOT recorded from the real service. No provider was
// contacted. Ids, titles and provider names are invented.

enum DiscoverFixtures {
    // FIXTURE: shaped like the service's documented reply
    static let similarMovies = #"""
    {"page":1,"results":[
    {"id":701,"title":"Fixture Film One","original_title":"Fixture Film One","release_date":"2001-05-01","overview":"A.","poster_path":"/f701.jpg","popularity":55.5},
    {"id":702,"title":"Fixture Film Two","original_title":"Fixture Film Two","release_date":"","overview":"B.","poster_path":null,"popularity":20.0},
    {"title":"No id, ignored"}
    ],"total_pages":1,"total_results":3}
    """#

    // FIXTURE: shaped like the service's documented reply
    static let watchProviders = #"""
    {"id":701,"results":{
    "US":{"link":"https://example.invalid/fixture/US",
      "flatrate":[{"logo_path":"/b.jpg","provider_id":2,"provider_name":"Fixture Stream B","display_priority":5},
                  {"logo_path":"/a.jpg","provider_id":1,"provider_name":"Fixture Stream A","display_priority":1}],
      "rent":[{"logo_path":"/r.jpg","provider_id":3,"provider_name":"Fixture Rent","display_priority":2}]},
    "DE":{"link":"https://example.invalid/fixture/DE",
      "buy":[{"logo_path":"/d.jpg","provider_id":4,"provider_name":"Fixture Buy DE","display_priority":1}]},
    "FR":{"link":"https://example.invalid/fixture/FR"}
    }}
    """#

    // FIXTURE: shaped like the service's documented reply
    static let watchProvidersEmpty = #"{"id":9,"results":{}}"#
}
