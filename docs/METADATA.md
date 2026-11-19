# Online metadata: TMDB, OMDb, matching, Fix Match, cache

Target: `MetadataOnline` (`Packages/VideoPlayerCore/Sources/MetadataOnline`), tests in `MetadataOnlineTests`. It depends on `VideoPlayerCore` only. Local sidecar reading is a different target (see `METADATA_LOCAL.md`); the filename parser is in `VideoPlayerCore`.

**The wording below was copied from the user's own message ("ARCHITECTURE: METADATA") and from `docs/FEATURE_BACKLOG.md` ("Binding rule: your library only").** `docs/SPECS.md` is only an index and is not the spec, so the user's wording is repeated here on purpose. Anything not in quotation blocks is my reading and is marked **Interpretation (PROVISIONAL)**.

## 1. The user's wording (copied)

### Sources and priority

> Sources, in priority order: (1) local sidecar files next to the video on the WebDAV server (.nfo XML, poster.jpg, fanart.jpg, folder.jpg, and same-name images), (2) TMDB (movies, TV series, seasons, episodes), (3) the file's own embedded MKV tags and chapters. Local sidecar data wins over online data.

### Matching order

> Matching: score candidates by title similarity, year, and runtime (compare file duration to TMDB runtime), then auto-accept only above a confidence threshold. Below it, mark the item "Needs review". Provide a "Fix Match" screen (search TMDB by title and year, pick the right result) that saves the choice permanently and applies it to the whole folder or season when the user chooses.

### Ratings

> Ratings: show TMDB rating plus IMDb rating, Rotten Tomatoes score and Metacritic score (from OMDb, matched by IMDb ID, which TMDB provides). Label each score with its source. If a score is missing, hide that item cleanly.

### Storage and performance (the part this target owns)

> Respect each provider's rate limits with a request queue and back-off. Match in the background and never block browsing or playback. A "Refresh Metadata" action per item, folder and library.

### API keys and attribution

> the user enters their own free TMDB API key and free OMDb API key in Settings (stored in Keychain). [...] Show required attributions in Settings > About: the TMDB notice ("This product uses the TMDB API but is not endorsed or certified by TMDB") with the TMDB logo as their guidelines require, and the JustWatch attribution required for watch-provider data.

### Binding rule: your library only (from `FEATURE_BACKLOG.md`)

> - Home, Movies, Shows, Files, Collections and Search show only content from the user's own sources. Search searches only the library.
> - No ads, sponsored rows, promoted services, free or live channels, trending rows, banners, upsells, or any content the user did not add. No third-party content in any playback flow.
> - The user never has to scroll past or dismiss anything to reach their own content.
> - Home rows are library-only: Continue Watching, Next Up, Recently Added, Upcoming Episodes (air dates for shows the user owns), Favorites, and More Like This built only from titles the user owns.

`FEATURE_BACKLOG.md` also defines **Discover** as the one tab for titles the user does not own. **Discover is not in this target.** `MetadataOnline` has no recommendations, similar, trending, discover or watch-provider call at all.

## 2. Your Library Only, enforced in types and tests

| Rule | How it is enforced | Test |
|---|---|---|
| Nothing is looked up for an item the library does not own | `LibraryMetadataService` (an actor) asks `LibraryCatalog.contains(itemID:)` first. An unknown id throws `MetadataError.notInLibrary` before any provider is called. | `LibraryOnlyTests` (zero provider calls asserted) |
| No outside titles in results | `LibraryResolution` is `.matched(MatchedLibraryItem)`, `.needsReview(itemID:reason:)` (no candidates) or `.unmatched`. `MatchedLibraryItem` has an internal initialiser, so callers cannot build one for a title they do not own. | `LibraryOnlyTests` |
| Collections list only owned parts | `OwnedCollection` is filtered through `LibraryCatalog.ownedTMDBIDs()`. Parts not owned are not returned, not even as names or counts. | `LibraryOnlyTests` |
| No Discover surface | The module has no method for recommendations, similar, trending, discover or watch providers. Fix Match candidates are a separate type (`ScoredCandidate`), reachable only through calls on an owned item. | `LibraryOnlyTests` (API surface listed in the test) |
| No ads or third-party rows | There is no type for them. | n/a |

## 3. Attribution constants

**Updated 2026-11-17 from TMDB's own pages (quotes and links in docs/ARTWORK_DISCOVER.md section 5a).** `MetadataAttribution.tmdbNotice` is now the notice from TMDB's API terms section 3, word for word: "This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB." (the earlier sentence was from memory and did not match). `MetadataAttribution.justWatchNotice` is "Where-to-watch data is provided by JustWatch." (TMDB's watch-provider page: "you must attribute the source of the data as JustWatch"; it gives no exact sentence, so the wording is PROVISIONAL, alternative "Source: JustWatch."). The app shows its own copy in App/Support/Attribution.swift; `AttributionNoticeTests` checks the two copies are equal. The TMDB logo, which the terms also require, is NOT added: the user decides.

## 4. What the target contains

| File | Purpose |
|---|---|
| `Models.swift` | `CalendarDate`, `TitleKind`, `ProviderIDs`, images, credits, `RatingSet`, `MovieMetadata`, `SeriesMetadata`, `SeasonMetadata`, `EpisodeMetadata`, `MetadataError`, `MetadataAttribution` |
| `RequestQueue.swift` | `ProviderQueue` actor: per-provider spacing, back-off, `Retry-After`, jitter, retry cap, cancellation, daily cap. `MetadataClock` seam for a fake clock |
| `Cache.swift` | `MetadataCache` protocol, `InMemoryMetadataCache`, `JSONFileMetadataCache`, TTLs, `RefreshScope` and `MetadataRefresh.invalidate` |
| `JSONValue.swift`, `TMDBMapping.swift` | Tolerant JSON reading and mapping of TMDB shapes |
| `TMDBClient.swift` | TMDB v3 client (search, details, season, episode, credits, images, external_ids, collection, configuration, release dates, translations, `append_to_response`). The key or token is passed in and never stored |
| ~~`OMDbClient.swift`~~ | **Removed in #27** (OPEN_QUESTIONS R211): the app never created it; the key, client, ratings hook and tests are gone. The OMDb notes below are history |
| `TextSimilarity.swift` | Title normalisation and similarity |
| `MatchEngine.swift` | Scores candidates, produces confidence 0...1, auto-accepts or marks Needs Review |
| `MatchStore.swift` | `MatchStore` protocol, in-memory and JSON-file stores (saved Fix Match choices) |
| `FixMatch.swift` | Fix Match search, choose (file, season or folder), undo |
| `MetadataMerger.swift` | Sidecar > TMDB > embedded, per field, with provenance |
| `LibraryMetadataService.swift` | The library-only front door (section 2) |

## 5. Matching order

The order the engine follows, from first to last:

1. **A saved Fix Match choice** for the file (file scope, then season scope, then the deepest folder scope). If one exists it is used and nothing else runs. No provider call is needed for a movie.
2. **A sidecar id** (TMDB or IMDb id read from a local `.nfo`). Confidence 1.0, no search.
3. **An id in the filename** (`{tmdb-603}`, `[imdbid-tt0133093]` style, as the parser reports it). Confidence 1.0, no search. An IMDb-only id uses TMDB `/find`. An id TMDB does not know falls back to searching.
4. **Search** by parsed title and year. Candidates are scored on title similarity, year, runtime and (for episodes) whether the episode exists. A search with a year that does not auto-accept is repeated once without the year. Fallback queries come from parent folder names, then the normalised title.
5. **Decision:** the top candidate is auto-accepted when its confidence is at or above the threshold and it is clearly ahead of the second. Otherwise the item is **Needs review** with up to 5 ranked candidates.

Episodes then resolve season and episode numbers against the matched series: standard `SxxEyy`, multi-episode (`S01E01-E02`), specials (season 0), absolute numbers (cumulative season counts) and date-based names (the 3 most recent plausible seasons).

### Interpretation (PROVISIONAL): everything in the order above that the user did not specify

The user specified: sidecar > TMDB > embedded; scoring on title, year and runtime; auto-accept above a threshold; otherwise Needs review; Fix Match saves permanently and can apply to a folder or season. Everything else in this document is my choice and is open to change. In particular:

- **A stored Fix Match choice beats even a sidecar id.** Reason: the user corrected it by hand. Alternative: let sidecar ids win.
- **Weights:** title 0.55, year 0.20, runtime 0.15, episode existence 0.10. Confidence is the weighted average over the components that apply, times (0.85 + 0.15 × used weight / total weight). A match with fewer pieces of evidence is therefore discounted.
- **Caps:** title similarity below 0.6 caps confidence at 0.5. A year off by more than 1 caps it at 0.6. An episode that does not exist in the matched series caps it at 0.5.
- **Year score:** exact 1.0, off by one 0.6, otherwise 0. An unknown year is "not applicable", not a mismatch.
- **Runtime:** tolerance is the larger of 5 minutes and 8%. Within the tolerance scores 1.0, within twice the tolerance 0.5, otherwise 0. A named edition (Director's Cut, Extended) raises the floor to 0.5 because those cuts are longer. Runtime is only used when the file duration is known.
- **Tie margin 0.05:** if the top two candidates are within 0.05 the item is Needs review with reason `closeScores`, even above the threshold.
- **Candidates shown:** at most 5. The engine enriches (fetches runtime or season data for) up to 3 candidates per round, up to 3 rounds. Alternative titles are only fetched when the preliminary ranking is not already settled.
- **Title similarity:** normalise (lower case, fold accents, "&" read as "and", drop apostrophes, other punctuation to spaces, join runs of single letters so "S.H.I.E.L.D." becomes "shield", drop a leading the/a/an and a trailing ", The", roman numerals II to IX become digits when there is more than one word). Then the larger of Jaro-Winkler scaled by the square root of the length ratio, and 1 minus normalised Levenshtein distance. A title wholly inside the other at word boundaries gets a floor of 0.85 (two or more words) or 0.7 (one word). Spacing-only differences score 0.98. Anything not identical is capped at 0.97, so 1.0 means identical after normalisation. The Jaro-Winkler prefix bonus only applies when plain Jaro is at least 0.7.
- **Articles and ", The" are English only.** Other languages' articles are not handled.
- **Season defaults to 1** when an episode filename has no season.
- **Original and alternative titles** count: the best similarity across title, original title and alternative titles is used.
- **Region and language:** text uses the user's language setting with an English fallback for an empty overview; certification uses the client's `region` setting, which defaults to "US" (the app should pass the tvOS locale region). Both are provisional because they depend on how Settings stores region and language.
- **Cast is capped at 60 people** per title.

### Open question: the auto-accept threshold

The user asked for a "confidence threshold" and gave no number. **I used 0.8 as a provisional default**, configurable through `MatchConfiguration`. This has to be added to `OPEN_QUESTIONS.md` (I am not allowed to edit that file; the parent should add it). Alternatives:

| Threshold | Effect |
|---|---|
| 0.7 | More automatic matches, more wrong ones to fix by hand |
| **0.8 (current)** | Balanced. In the hand-written cases it accepts a year-less movie with an exact title and a runtime match, and sends a two-way tie to Needs review |
| 0.9 | Almost no wrong matches, but many files with no year or runtime go to Needs review |

The tests pin the behaviour at the threshold (`MatchEngineTests`), so changing the default will show exactly which cases move. The threshold should be tuned against the user's real library, which I do not have.

## 6. Fix Match

- `FixMatchService.search(title:year:)` returns ranked `ScoredCandidate`s (the same scoring as auto-matching).
- `choose(...)` saves a `StoredMatch` in the `MatchStore`. Keyed by file path; the size is stored for information only.
- Scopes: `.file`, `.season(n)` (same folder, same season) and `.folder` (every file under the folder). **Season and folder scopes are for series only**; applying them to a movie throws `MetadataError.scopeNotAllowed` because a folder of movies shares no single title.
- Lookup order: file, then season, then the deepest matching folder. The same scope and path replaces the earlier entry.
- **Undo** restores exactly what the last choice replaced (or removes it).
- `InMemoryMatchStore` and `JSONFileMatchStore`. The JSON store writes atomically; a corrupt file is renamed `.corrupt` and the store starts empty; a write failure throws `MatchStoreError` (a Fix Match is never silently lost).
- **Interpretation (PROVISIONAL):** keying by file path means renaming or moving a file drops its saved choice. Keying by a content hash would survive renames but cannot be computed without reading the file. This is a decision for the user.

## 7. Cache and Refresh Metadata

- Keys are plain text: `tmdb/movie/603/en-US`, `tmdb/tv/1396/season-1/en-US`, `omdb/title/tt0133093/...`.
- Every entry has a time to live. **Interpretation (PROVISIONAL) defaults:** details 14 days, season 3 days (episodes appear), search 1 day, configuration 7 days, OMDb scores 7 days.
- **Offline use:** an expired entry is still returned when the network fails, on a 5xx, on a 429 or when the provider quota is exhausted. It is not returned on 404 (the title is gone) or 401 (the key is wrong).
- `InMemoryMetadataCache` and `JSONFileMetadataCache` (one percent-encoded file per key).
- **Refresh Metadata** (`MetadataRefresh.invalidate`) removes by prefix: per item (`tmdb/movie/{id}/`, `tmdb/tv/{id}/`, `omdb/title/{imdb}/`), per folder (the items in it) and per library (everything under `tmdb/` and `omdb/`). Refresh does not fetch anything by itself; the next lookup does.
- Images are not cached here; the target only builds image URLs. The user asked for a disk image cache with downsampling for tvOS, which belongs to the UI layer.

## 8. Rate limiting and errors

`ProviderQueue`: one queue per provider, with spacing between requests, retry with exponential back-off and jitter on network errors, 5xx and 429 (a `Retry-After` header, when present, wins over the computed delay), a retry cap, cancellation during waits, and a daily request cap. Tests use a fake clock, so no test sleeps.

**Interpretation (PROVISIONAL):** the OMDb free tier is documented as 1,000 requests a day, so `QueueConfiguration.omdb` has `dailyLimit` 1000. TMDB has no hard daily limit for ordinary use, so none is set. The spacing and back-off numbers are my choices.

Status mapping: 401 and 403 mean `invalidAPIKey`, 404 means `notFound`, everything else unexpected is `unexpectedStatus(code)`. Network failures are `network`.

## 9. Merging

`MetadataMerger` combines three layers per field: **local sidecar > TMDB > embedded tags**. A blank string, an empty list or a runtime of 0 or less counts as missing, so the next layer fills it. Each merged field records its source (`provenance`), so the UI can show where a value came from and Fix Match can show what changes. Artwork is `.local(...)` or `.tmdb(...)`.

**Interpretation (PROVISIONAL):** "wins" is read per field, not per item. A sidecar that has a title but no plot keeps the sidecar title and takes the plot from TMDB.

## 10. Credentials

`TMDBCredentials` holds either a v3 API key or a v4 read access token. It is `Sendable`, never written to the cache or any store, and redacted in `description`, `debugDescription` and `dump`. A test checks that the key does not appear in any file the cache wrote. The Keychain itself is outside this target; the app passes the credential in when it creates the client.

## 11. Verification: what is and is not proven

**What ran:** the unit tests, in a private copy on Linux (WSL Ubuntu, Swift 6.4.2). They use a mock `HTTPTransport`. **Nothing here has contacted TMDB or OMDb.** I was told not to, and no real key was used. Test keys are the placeholder text `test-key-not-real`.

**Fixtures are hand-written from the documentation, not recorded from the real service.** `Tests/MetadataOnlineTests/Fixtures.swift` says so at the top. The tests prove my code reads those shapes and handles those errors. They do not prove the real services answer in those shapes.

### Unverified (needs one real call per item, with the user's own key)

TMDB:
- Field names and nesting in search, `/movie/{id}`, `/tv/{id}`, `/tv/{id}/season/{n}`, episode, `/collection/{id}` and credits responses.
- `append_to_response` combinations (`credits`, `images`, `videos`, `release_dates` for movies, `content_ratings` for series, `external_ids`).
- Certification: that release type 3 (theatrical) is a good choice in `release_dates`, and the `content_ratings` shape for series.
- `/find/{imdb_id}` result keys (`movie_results`, `tv_results`).
- `/configuration` image base URL and size lists (a built-in fallback is used if it is missing).
- Translations shape, and `alternative_titles`: I assumed `titles` for movies and `results` for series.
- `images` with `include_image_language` and which language the logo and poster pick.
- The error body and status for a bad key (assumed 401) and a missing id (assumed 404), and the `Retry-After` behaviour on 429.

OMDb:
- The exact `Ratings` source strings ("Internet Movie Database", "Rotten Tomatoes", "Metacritic") and formats ("8.7/10", "88%", "73/100"). The flat fields (`imdbRating`, `Metascore`) are used as fallbacks.
- "N/A" for a missing value.
- `Response: "False"` and the `Error` texts ("Invalid API key!", "Request limit reached!", "Movie not found!") and whether a bad key arrives as HTTP 401 or 200 with the body error (both are handled).

Also unverified: the thresholds and weights against a real library, and behaviour on real filenames beyond the hand-written cases.

## 12. Test coverage for the required matching cases

All in `MatchEngineTests` and `FixMatchTests`: movie with year, movie without year, TV episode, multi-episode, special (season 0), mismatched title needing Fix Match, remake with the same title and a different year, foreign title with original title, "The" prefix, punctuation, long series titles, and two candidates with close scores. Absolute-numbered and date-based episodes also have tests.
