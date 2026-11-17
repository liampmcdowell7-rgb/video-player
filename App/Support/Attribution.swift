import Foundation

// The notices TMDB requires, as constants so every screen shows the same words (Discover, Settings > Online
// Lookup, Settings > About). TMDB and JustWatch are in the docs/NAMES.md allowlist, so no design-lint exception is needed;
// the claim-wording rule exempts the TMDB sentence because it says "not endorsed".
//
// Wording source: TMDB's own public pages, read 2026-11-17, quoted with links in docs/ARTWORK_DISCOVER.md section 5a.
// - TMDB API terms of use, section 3 "Attribution", give the notice word for word with a choice of
//   "[website, program, service, application, product]"; "application" is used here.
// - TMDB's watch-provider endpoint page says the source of that data must be attributed as JustWatch.
// The same terms also say the TMDB logo must be used. The user decided (OPEN_QUESTIONS R148) to show it as the one logo
// exception, only in Settings > About > Data Sources (App/Features/Settings/AboutView.swift, asset TMDBAttributionLogo).
// AppLogicTests/AttributionNoticeTests reads this file and pins every text below.
enum Attribution {
    // Word for word from the TMDB API terms, section 3.
    static let catalogueNotice = "This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB."
    // Source attribution required by TMDB's watch-provider documentation.
    static let whereToWatchNotice = "Where-to-watch data is provided by JustWatch."
    static let aboutHeading = "Data Sources"
    static let aboutNote = "Pictures, matches, Discover and where-to-watch information come from TMDB, and only after you enter your own TMDB key in Settings > Online Lookup."
}
