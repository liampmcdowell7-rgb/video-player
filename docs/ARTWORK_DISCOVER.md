# Artwork, online lookups, Discover, ledger cloud sync, letter jump list

Status: written in WSL against fixtures. The package code is compiled and tested (see the test counts in the build report). Everything in App/ is syntax-checked only and has **never been compiled or run**. Every interpretation below is PROVISIONAL with its alternative.

## 1. What is sent, and when (decision D10, PROVISIONAL)

Nothing is sent to any online service until the user enters a key in Settings > Online Lookup. The settings screen shows `OnlineLookupText.whatIsSent` (AppLogic/OnlineLookup.swift; services named by their real names, per the user's rule of 2026-11-17 that replaces R91). Tests never contact a service: every test uses a mock transport and fixtures marked `// FIXTURE: shaped like the service's documented reply`.

**Reconciled 2026-11-17 (screen text = docs/PRIVACY_POLICY_DRAFT.txt = code).** The facts were read from the request builders (`TMDBClient`, `TMDBDiscover`, `OMDbClient`, `MatchEngine`, `DiscoverEngine`, `OnlineServices`), and `AttributionNoticeTests.testRequestsSend...` checks the main ones against real request URLs:

| Fact | Code that proves it |
|---|---|
| Title (query) and year (`year` / `first_air_date_year`) from file and folder names | `TMDBClient.searchMovies` / `searchSeries`, called by `MatchEngine` and Fix Match |
| Season numbers in the path (`/tv/{id}/season/{n}`); **episode numbers are never sent** (the whole season comes back, the episode is picked on the device). The earlier texts said "season and episode numbers": corrected | `TMDBClient.season`; `episode(...)` exists but no app path calls it |
| The catalogue's own number of a matched title (details, collection, similar, recommendations, watch providers, images) | `TMDBClient.movie/series/collection`, `TMDBDiscover` |
| A title number from an info file next to the video (`/find/{id}`) | `MatchEngine` -> `TMDBClient.find(imdbID:)` |
| Language: the fixed code `en-US` (plus image languages `en,null`). The earlier screen text said "your language setting": **wrong**, corrected (the app never passes a language; `TMDBClient.language` defaults to `en-US`) | `OnlineServices.rebuild`, `TMDBClient.init` |
| The key (`api_key` query item, or a bearer header for a read token) | `TMDBClient.makeRequest` |
| The where-to-watch region is **not** sent (all regions come back; `WhereToWatchBuilder` keeps one on the device) | `TMDBDiscover.watchProviders`, `WhereToWatchBuilder.build` |
| The ratings key is stored, but **no app path calls the ratings service**, so nothing is sent to it. The earlier texts said scores are added: corrected to "saved but not used yet" | no `OMDbClient` is built anywhere in App/ or AppLogic |

If any of these changes, the screen text, the policy draft and `OnlineKeyTests.testThePlainStatement...` change together.

## 2. Keys

`OnlineKeyStore` (AppLogic) keeps the keys under the ids `online-key.tmdb` and `online-key.omdb` through `MirroredSecrets`: protected local storage plus an encrypted copy in the user's own cloud storage, the same path as source passwords. PROVISIONAL; alternative: local only (`mirrored: false`). The screen shows a key masked (`••••1a2b`), never whole, with Replace and Remove (with a confirmation). A key is validated by shape only (no spaces, printable, at most 2000 characters). There is no "Test key" button (PROVISIONAL; alternative: one request on an explicit press, never from tests). The region for where-to-watch lists is the setting `onlineRegion`, default `US` (R37, PROVISIONAL; alternative: the device region).

## 3. Artwork

Order, strongest first: a picture next to the video on the source (`SidecarImageFinder`: poster, folder, cover, movie-name poster, episode thumb), then the poster of the title the matcher found online, then the placeholder symbol. `ArtworkEngine` (AppLogic) answers `resolve(key:)` for keys `item-<id>`, `series-<id>` and `remote:/poster.jpg` (Discover cards).

- Online picture sizes (quality principle, changed 2026-11-17): poster `w780` (was `w500`: the five-column grid draws a poster 320 pt wide = 640 px at @2x on a 4K screen, so `w500` was upscaled), backdrop/still/logo `original`, profile `h632`. Proof and alternatives: docs/COVERAGE.md "Defaults changed" and docs/QUALITY_CEILINGS.md.
- Source pictures are read once (at most 40 MB, was 8 MB: a full-resolution 4K PNG can be larger, and skipping it fell back to a smaller online picture) and kept in `Caches/artwork` by `ArtworkDiskCache`: a size limit (150 MB, PROVISIONAL), least recently used removed first, one picture larger than the whole cache refused. The cache key includes path, size and modified date, so a replaced poster shows up. A system cleanup of Caches only means the pictures are read again.
- Online posters are web addresses (nothing is downloaded by the engine); the system image loader (`AsyncImage` with `asyncImageURLSession`) fetches them through a session whose `URLCache` is capped at 20 MB memory / 100 MB disk in `Caches/remote-artwork` (PROVISIONAL numbers).
- Online metadata answers are small JSON files in `Caches/online-metadata` with their own expiry (details 14 days, search 1 day, from `CachePolicy.standard`).
- A "found nothing" answer is remembered for 15 minutes so scrolling does not repeat lookups.
- An item without an online id is matched from its file name by the matcher (saved Fix Match choice first, then automatic matching at the 0.8 threshold); an accepted match is written back as the item's id. A match that "needs review" gives no picture: nothing is guessed.
- Top Shelf: the pictures the snapshot names are written into the shelf folder after each scan (a source picture, or the downloaded matched poster); items with no picture are left out of the snapshot. The folder is not durable storage and is rewritten after every scan.

## 4. Fix Match

Needs the TMDB key (without one the screen says `OnlineLookupText.fixMatchNeedsKey` and sends nothing). Movie: one choice sets title, year and id on that item. Episode: scope picker "This File Only / This Season / The Whole Show"; the choice sets the series id (not the title: an episode's own title is the episode's name) on every episode in scope. The choice is saved in the match store (`Application Support/matches.json`) so the automatic matcher never overrides it (R37). PROVISIONAL: kept on this device only (alternative: a ledger record so it syncs; needs a new record type in Schema.swift). A failure to save is shown and nothing is claimed applied.

## 5. Discover

Four sections, all from the user's own key; nothing is invented, and a section that cannot be filled says why (`problems`) without hiding the sections that worked.

- Missing Episodes: aired episodes (not future ones, not Season 0 specials) in the seasons the user already has, for series the library has matched.
- Collection Gaps: parts of a collection the user owns one of, excluding unreleased parts.
- Similar to Your Library: from up to 4 seeds (favorites first, then most recently played), excluding titles owned, de-duplicated, with the reason "Similar to X".
- Watchlist: titles the user chose (poster press toggles), hidden once owned. Stored as a ledger record type `watchlist` (no Schema.swift change; an older app keeps the unknown record), so it syncs with the ledger.
- Where to watch: from the watch-provider data, for the user's region only (stream, rent, buy); "not listed for US" when none. Limits per load: 20 series, 40 movie lookups, 4 seeds, 24 similar, 40 where-to-watch lookups (PROVISIONAL).
- With no key the tab says `OnlineLookupText.discoverNeedsKey`. With Settings > Home Screen > Show Discover off, the tab is gone and no request is made.

Attribution: see section 5a.

## 5a. Attribution required by TMDB (read from its own pages, 2026-11-17)

Pages read (public, with WebFetch; nothing was contacted through the API):

1. **API terms of use**, https://www.themoviedb.org/api-terms-of-use ("last updated on: October 20, 2023").
   - Section 1.B makes attribution a licence condition: "Giving TMDB attribution for all TMDB Content, as specified in Paragraph 3 (Attribution), below."
   - Section 3 "Attribution", the notice: "In addition, You must place the following notice prominently in or on Your Application:" followed by "This [website, program, service, application, product] uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB."
   - Section 3, the logo: "You must use the TMDB logo to identify Your use of TMDB, the TMDB APIs, or TMDB Content." The same section says the logo must be less prominent than the app's own marks and must not suggest endorsement.
   - Placement: only "prominently in or on Your Application"; no about page or credits screen is named.
2. **Logos and attribution**, https://www.themoviedb.org/about/logos-attribution: "As per our terms of use, every application that uses our data or images is required to properly attribute TMDB as the source." It offers logos to download and gives no notice text or placement of its own.
3. **Watch providers, movie** (the endpoint the app calls, `/movie/{id}/watch/providers`), https://developer.themoviedb.org/reference/movie-watch-providers: "In order to use this data you must attribute the source of the data as **JustWatch**." and "If we find any usage not complying with these terms we will revoke access to the API." The provider-list page the user named (https://developer.themoviedb.org/reference/watch-providers-movie-list) was read in full and states no attribution rule; the rule is on the endpoint page above.

What the app shows (plain native `Text`, from the constants in `App/Support/Attribution.swift`; the "Trademarks and Attributions" section of Settings > About is built by the NAMES work and shows the same two constants):

| Text | Where |
|---|---|
| "This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB." ("application" chosen from the page's bracketed list) | Discover (under the shelves, the where-to-watch screen), Settings > Online Lookup (section "Data Sources"), Settings > About ("Data Sources") |
| "Where-to-watch data is provided by JustWatch." | the same three places |

**Not done, on purpose: the logo.** The terms say a logo "must" be used. Adding a company logo is the user's decision (the app shows no company logos), so no logo is in the app and `AttributionNoticeTests.testNoLogoImageIsReferenced...` fails if one is added without updating the test. Open question for the user (batch report).
**Not done: a link back.** The watch-provider data carries a link per title and region; tvOS has no web browser for an app to open it, and none of the pages read requires a link, so no link is shown.
The earlier text "This product uses the TMDB API but is not endorsed or certified by TMDB." was from memory and did not match the terms; it is replaced (also in `MetadataAttribution`). The earlier ratings line ("Ratings come from OMDb when you enter an OMDb key.") claimed something the app does not do (no ratings are fetched) and is removed.

## 6. Letter jump list

Movies (title sorts): a menu "Jump to Letter" with # then A to Z, only letters that exist, each with its count. It reads the library index (`alphabetIndex`) and starts the grid at that row number; paging continues by row offset from there. Shows: the same menu scrolls to the first show of the letter; shows are sorted by the same key the letters use. The article "The" is skipped, accents ignored, leading punctuation skipped (so "!Hero" is under H, like the grid's sort), digits and other scripts under "#". PROVISIONAL: a native menu; alternative: a side strip.

## 7. Ledger cloud sync

`UserDataSyncEngine` (merge rules, push/pull, retries) already existed and is tested. New: `CloudSyncCoordinator` (AppLogic) schedules it, `CloudSyncHost` (App/Support) connects it. Start-up runs `LibraryBootstrap` (restore after a cleanup, rebuild a lost ledger, merge); then: changes go up 5 seconds after the first change; the app pulls every 15 minutes; coming back to the foreground and an account change sync at once; "Sync Now" in Settings > Storage and Cloud; after a failure the wait doubles from 30 seconds to 15 minutes; a signed-out device and a full cloud are not retried on a timer (only on an account change, Sync Now or the periodic pull). The ledger file is rewritten in Caches (`user-data-ledger.json`) whenever it has unsaved changes. The status sentence under Cloud Sync says the real state: last synced, signed out, offline, full, with how many changes are waiting. All numbers PROVISIONAL.

## 8. Not done / known gaps

No logo image; no link back to the data providers; no "Test key" button; Fix Match choices not synced; no background refresh of artwork when keys are removed (pictures already downloaded stay until the system clears them, as the screen says); the account-change notification name is used as text (NOT CHECKED); nothing in App/ compiled.
