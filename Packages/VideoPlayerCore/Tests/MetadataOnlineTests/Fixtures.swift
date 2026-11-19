import Foundation

// FIXTURES FOR THE MetadataOnline TESTS
//
// Every response below is HAND-WRITTEN FROM THE DOCUMENTATION (as remembered), NOT RECORDED FROM THE REAL
// SERVICE. No provider (TMDB, OMDb) was contacted to produce them. Ids, titles and numbers are invented or
// recalled for plausibility and must not be read as real data. The shapes (field names, nesting, "N/A"
// strings, null handling) are the unverified part: see docs/METADATA.md "Unverified".

enum Fixtures {
    // MARK: TMDB

    static let tmdbConfiguration = #"""
    {"images":{"base_url":"http://image.tmdb.org/t/p/","secure_base_url":"https://image.tmdb.org/t/p/",
    "backdrop_sizes":["w300","w780","w1280","original"],"logo_sizes":["w45","w92","w154","w185","w300","w500","original"],
    "poster_sizes":["w92","w154","w185","w342","w500","w780","original"],"profile_sizes":["w45","w185","h632","original"],
    "still_sizes":["w92","w185","w300","original"]},"change_keys":["adult","air_date"]}
    """#

    static let searchMovieMarrowgate = #"""
    {"page":1,"results":[
    {"id":603,"title":"The Marrowgate","original_title":"The Marrowgate","original_language":"en","release_date":"1999-03-31","overview":"A hacker learns the truth.","poster_path":"/p603.jpg","popularity":80.5,"vote_average":8.2,"genre_ids":[28,878]},
    {"id":604,"title":"The Marrowgate Reloaded","original_title":"The Marrowgate Reloaded","original_language":"en","release_date":"2003-05-15","overview":"Sequel.","poster_path":null,"popularity":60.1}
    ],"total_pages":1,"total_results":2}
    """#

    static let searchEmpty = #"{"page":1,"results":[],"total_pages":0,"total_results":0}"#

    static let searchTV = #"""
    {"page":1,"results":[
    {"id":1396,"name":"Crossing Brine","original_name":"Crossing Brine","original_language":"en","first_air_date":"2008-01-20","overview":"A teacher turns to crime.","poster_path":"/bb.jpg","popularity":120.0}
    ],"total_pages":1,"total_results":1}
    """#

    static let movie603 = #"""
    {"id":603,"imdb_id":"tt0133093","title":"The Marrowgate","original_title":"The Marrowgate","original_language":"en",
    "tagline":"Welcome to the Waking Hour.","overview":"A computer hacker learns about the true nature of reality.",
    "release_date":"1999-03-31","runtime":136,"genres":[{"id":28,"name":"Action"},{"id":878,"name":"Science Fiction"}],
    "poster_path":"/poster603.jpg","backdrop_path":"/backdrop603.jpg",
    "belongs_to_collection":{"id":2344,"name":"The Marrowgate Collection","poster_path":"/coll_poster.jpg","backdrop_path":null},
    "vote_average":8.2,"vote_count":25000,
    "credits":{"cast":[
      {"id":2975,"name":"Corin Hale","character":"Oracle One","profile_path":null,"order":1},
      {"id":6384,"name":"Rowan Ashby","character":"Wren","profile_path":"/ashby.jpg","order":0}],
     "crew":[{"id":9340,"name":"Mira Castell","job":"Director","department":"Directing","profile_path":"/lana.jpg"},
             {"id":9341,"name":"Someone","job":"Editor","department":"Editing","profile_path":null}]},
    "images":{"posters":[
      {"file_path":"/p_en.jpg","width":1000,"height":1500,"iso_639_1":"en","vote_average":5.5},
      {"file_path":"/p_de.jpg","width":1000,"height":1500,"iso_639_1":"de","vote_average":6.0},
      {"file_path":"/p_none.jpg","width":1000,"height":1500,"iso_639_1":null,"vote_average":5.0}],
     "backdrops":[{"file_path":"/b1.jpg","width":1920,"height":1080,"iso_639_1":null,"vote_average":5.1}],
     "logos":[{"file_path":"/logo_en.png","width":500,"height":200,"iso_639_1":"en","vote_average":5.0}]},
    "videos":{"results":[{"iso_639_1":"en","iso_3166_1":"US","key":"vKQi3bBA1y8","site":"YouTube","type":"Trailer","name":"Official Trailer","official":true},
                         {"iso_639_1":"en","key":"x1","site":"Vimeo","type":"Clip","name":"Clip","official":false}]},
    "release_dates":{"results":[
      {"iso_3166_1":"DE","release_dates":[{"certification":"16","type":3,"release_date":"1999-06-17T00:00:00.000Z"}]},
      {"iso_3166_1":"US","release_dates":[{"certification":"","type":1},{"certification":"R","type":3}]}]},
    "external_ids":{"imdb_id":"tt0133093"}}
    """#

    /// Missing and null fields everywhere; only id and title are present.
    static let movieSparse = #"""
    {"id":42,"title":"Sparse","original_title":null,"release_date":"","runtime":null,"genres":null,"poster_path":null,
    "overview":"","tagline":"   ","belongs_to_collection":null,"credits":null,"images":{"posters":null},"videos":{},
    "vote_average":0,"vote_count":0,"release_dates":{"results":[]}}
    """#

    /// A German-language request for a title that TMDB has no German overview for.
    static let movieGermanNoOverview = #"""
    {"id":777,"title":"Das Beispiel","original_title":"The Example","original_language":"en","overview":"","tagline":"","release_date":"2001-01-01","runtime":100,"genres":[{"id":18,"name":"Drama"}]}
    """#
    static let movieEnglishOverview = #"{"id":777,"title":"The Example","overview":"English overview.","tagline":"English tagline."}"#

    static let tv1396 = #"""
    {"id":1396,"name":"Crossing Brine","original_name":"Crossing Brine","original_language":"en","tagline":"Remember the tide",
    "overview":"A teacher turns to crime.","first_air_date":"2008-01-20","last_air_date":"2013-09-29","status":"Ended",
    "genres":[{"id":18,"name":"Drama"}],"networks":[{"id":174,"name":"North Channel"}],"poster_path":"/bb.jpg","backdrop_path":"/bbb.jpg",
    "seasons":[
      {"season_number":1,"name":"Season 1","episode_count":7,"air_date":"2008-01-20","poster_path":"/s1.jpg"},
      {"season_number":0,"name":"Specials","episode_count":2,"air_date":"2009-02-17","poster_path":null},
      {"season_number":2,"name":"Season 2","episode_count":13,"air_date":"2009-03-08","poster_path":null}],
    "vote_average":8.9,"vote_count":12000,
    "external_ids":{"imdb_id":"tt0903747","tvdb_id":81189},
    "content_ratings":{"results":[{"iso_3166_1":"DE","rating":"16"},{"iso_3166_1":"US","rating":"TV-MA"}]},
    "credits":{"cast":[{"id":17419,"name":"Dale Hollis","character":"Warren Holt","profile_path":"/bc.jpg","order":0}],"crew":[]},
    "images":{"posters":[],"backdrops":[],"logos":[]},"videos":{"results":[]}}
    """#

    static let tv1396Season1 = #"""
    {"id":3572,"name":"Season 1","overview":"First season.","air_date":"2008-01-20","poster_path":"/s1.jpg","season_number":1,
    "episodes":[
     {"id":62085,"name":"Pilot","overview":"Warren learns.","air_date":"2008-01-20","episode_number":1,"season_number":1,"runtime":58,"still_path":"/e1.jpg","vote_average":8.2,
      "guest_stars":[{"id":1,"name":"Guest One","character":"Cop","profile_path":null,"order":0}],"crew":[{"id":2,"name":"Dir","job":"Director","department":"Directing"}]},
     {"id":62086,"name":"Cat's in the Box...","overview":"Cleanup.","air_date":"2008-01-27","episode_number":2,"season_number":1,"runtime":48,"still_path":null,"vote_average":8.1},
     {"id":62087,"name":"...And the Box's in the Lake","overview":null,"air_date":"2008-02-10","episode_number":3,"season_number":1,"runtime":null}
    ]}
    """#

    static let tv1396Episode = #"""
    {"id":62085,"name":"Pilot","overview":"Warren learns.","air_date":"2008-01-20","episode_number":1,"season_number":1,"runtime":58,"still_path":"/e1.jpg","vote_average":8.2,
     "guest_stars":[{"id":1,"name":"Guest One","character":"Cop","profile_path":null,"order":0}],
     "crew":[{"id":2,"name":"Dir","job":"Director","department":"Directing"}]}
    """#

    static let collection2344 = #"""
    {"id":2344,"name":"The Marrowgate Collection","overview":"Series.","poster_path":"/cp.jpg","backdrop_path":"/cb.jpg",
     "parts":[
      {"id":604,"title":"The Marrowgate Reloaded","release_date":"2003-05-15","poster_path":"/r.jpg"},
      {"id":603,"title":"The Marrowgate","release_date":"1999-03-31","poster_path":"/m.jpg"},
      {"id":605,"title":"The Marrowgate Revolutions","release_date":"2003-11-05","poster_path":null}]}
    """#

    static let findByIMDb = #"""
    {"movie_results":[{"id":603,"title":"The Marrowgate","original_title":"The Marrowgate","release_date":"1999-03-31","popularity":80.5}],
     "person_results":[],"tv_results":[],"tv_episode_results":[],"tv_season_results":[]}
    """#

    static let images603 = #"""
    {"id":603,"posters":[{"file_path":"/p_en.jpg","width":1000,"height":1500,"iso_639_1":"en","vote_average":5.5}],
     "backdrops":[{"file_path":"/b1.jpg","width":1920,"height":1080,"iso_639_1":null,"vote_average":5.1}],
     "logos":[{"file_path":"/logo_en.png","width":500,"height":200,"iso_639_1":"en","vote_average":5.0}]}
    """#

    static let credits603 = #"""
    {"id":603,"cast":[{"id":6384,"name":"Rowan Ashby","character":"Wren","profile_path":"/ashby.jpg","order":0}],
     "crew":[{"id":9340,"name":"Mira Castell","job":"Director","department":"Directing","profile_path":null}]}
    """#

    static let externalIDs1396 = #"{"id":1396,"imdb_id":"tt0903747","tvdb_id":81189,"tvrage_id":18164,"facebook_id":null}"#

    static let translations603 = #"""
    {"id":603,"translations":[
     {"iso_3166_1":"DE","iso_639_1":"de","name":"Deutsch","english_name":"German","data":{"title":"Marrowgate","overview":"Ein Hacker ...","tagline":"Willkommen in der Wachstunde."}},
     {"iso_3166_1":"US","iso_639_1":"en","name":"English","english_name":"English","data":{"title":"The Marrowgate","overview":"A hacker ...","tagline":""}}]}
    """#

    static let alternativeTitlesMovie = #"""
    {"id":603,"titles":[{"iso_3166_1":"FR","title":"Marrowgate","type":""},{"iso_3166_1":"JP","title":"マロウゲート","type":""}]}
    """#
    static let alternativeTitlesTV = #"""
    {"id":1396,"results":[{"iso_3166_1":"US","title":"BB","type":""}]}
    """#

    static let tmdbInvalidKey = #"{"status_code":7,"status_message":"Invalid API key: You must be granted a valid key.","success":false}"#
    static let tmdbNotFound = #"{"status_code":34,"status_message":"The resource you requested could not be found.","success":false}"#

    // MARK: OMDb

    static let omdbMarrowgate = #"""
    {"Title":"The Marrowgate","Year":"1999","Rated":"R","Released":"31 Mar 1999","Runtime":"136 min","Genre":"Action, Sci-Fi",
     "Plot":"A hacker learns.","Poster":"N/A",
     "Ratings":[{"Source":"Internet Movie Database","Value":"8.7/10"},{"Source":"Rotten Tomatoes","Value":"83%"},{"Source":"Metacritic","Value":"73/100"}],
     "Metascore":"73","imdbRating":"8.7","imdbVotes":"2,000,000","imdbID":"tt0133093","Type":"movie","DVD":"N/A","BoxOffice":"N/A","Response":"True"}
    """#

    /// IMDb only; the others are "N/A" or missing.
    static let omdbOnlyIMDb = #"""
    {"Title":"Obscure","Year":"2015","Ratings":[{"Source":"Internet Movie Database","Value":"6.1/10"}],
     "Metascore":"N/A","imdbRating":"6.1","imdbVotes":"N/A","imdbID":"tt7654321","Type":"movie","Response":"True"}
    """#

    static let omdbNothing = #"""
    {"Title":"Unrated","Year":"2020","Ratings":[],"Metascore":"N/A","imdbRating":"N/A","imdbVotes":"N/A","imdbID":"tt1111111","Type":"movie","Response":"True"}
    """#

    static let omdbFlatOnly = #"""
    {"Title":"Flat","Year":"2001","Metascore":"61","imdbRating":"7.4","imdbVotes":"12,345","imdbID":"tt2222222","Type":"movie","Response":"True"}
    """#

    static let omdbInvalidKey = #"{"Response":"False","Error":"Invalid API key!"}"#
    static let omdbLimit = #"{"Response":"False","Error":"Request limit reached!"}"#
    static let omdbNotFound = #"{"Response":"False","Error":"Movie not found!"}"#
    static let omdbBadID = #"{"Response":"False","Error":"Incorrect IMDb ID."}"#
}
