# Feature backlog and content rules

Principle: a plain video player. A feature earns its place only if it makes finding, starting or watching the user's own videos faster, clearer or better. Fix basics first: browsing, filtering, sync, subtitle rendering, audio and video sync.

## Binding rule: your library only
- Home, Movies, Shows, Files, Collections and Search show only content from the user's own sources. Search searches only the library.
- No ads, sponsored rows, promoted services, free or live channels, trending rows, banners, upsells, or any content the user did not add. No third-party content in any playback flow.
- The user never has to scroll past or dismiss anything to reach their own content.
- Home rows are library-only: Continue Watching, Next Up, Recently Added, Upcoming Episodes (air dates for shows the user owns), Favorites, and More Like This built only from titles the user owns.

## Discover (replaces the earlier suggestions section)
- All recommendations of titles the user does not own live in one tab, Discover, placed last before Search. Settings > Discover has Show Discover (default on). When off, the tab disappears and no discovery requests are made.
- Contents: Missing Episodes, Collection Gaps, Similar to Your Library, Watchlist.
- Every item shows poster, scores from all sources, and Where to Watch grouped Stream, Rent, Buy, filtered by My Services. Clear message when no provider data exists for the region.
- Quality bar: minimum rating and vote count (adjustable in Settings > Discover). No filler, no duplicates, nothing marked Not Interested.
- Sources: TMDB recommendations, similar and discover; TMDB watch providers (JustWatch attribution); OMDb scores; the user's own keys. No scraping of IMDb or Rotten Tomatoes. No torrent, download-site or file-sharing sources. Taste data stays on the device. No accounts, no analytics.
- Tabs (provisional): Home, Movies, Shows, Files, Discover, Search, Settings.

## Tier A: browsing, setup and playback basics
1. Instant, scalable library: local cache, incremental sync by ETag and last-modified, automatic refresh on launch and on a schedule, 50,000+ files, alphabet jump scrubber.
2. Combined sort and filter: any number of filters (genre, year, rating, unwatched, resolution, HDR format, Dolby Vision, Dolby Atmos, audio channels, container, added date). Saved per view and per folder, remembered across launches, pinnable.
3. Direct file browsing: Files works at once in plain folder view with no matching or indexing, fast on large folders.
4. Continue Watching, Next Up, watched marks (episode, season, series), resume. Long-press actions on every poster: Play, Play from Beginning, Mark Watched or Unwatched, Add to Favorites, Remove from Continue Watching, Fix Match, Refresh Metadata, File Details. Setting for how long unfinished shows stay in Next Up and Continue Watching.
5. Setup that works once: Bonjour discovery, connection test with plain explanations, and sync of sources, credentials, favorites, saved filters and watch state across the user's own Apple TVs through private iCloud (CloudKit, iCloud Keychain). No third-party server.
6. Home-server security: self-signed certificates handled the way NAS devices use them. Show the fingerprint, trust it for that server only, pin it. Warn before Basic authentication over plain HTTP.
7. WebDAV compatibility tests (Nextcloud, Synology, Apache, nginx, rclone serve webdav): path encoding, NFC and NFD names, Depth, very large listings, no Range support, no ETags. Document tested servers.
8. Audio and video sync: honour the wireless audio sync setting on every playback path including the fallback engine; per-file audio delay; no drift in long playback.
9. Subtitles: external files matched by name and language (.srt, .ass, .vtt, .sup, .sub, .idx); embedded text and image subtitles; PGS at correct position and scale with a vertical-position setting; styled ASS and SSA at least on the fallback engine; timing offset; follows system subtitle settings including tvOS 27 Larger Text.
10. Track selection rules: preferred audio and subtitle languages, original language plus forced subtitles, highest channel count, prefer Atmos, SDH preference, remembered per series. Set once in Settings > Playback.
11. Playback Stats overlay: every stat visible at once, no collapsed sections, most important first: resolution, frame rate, video codec, profile and level, HDR format and Dolby Vision profile, bitrate (live and average), audio codec, channels and whether passed through or decoded, network throughput, buffer health, dropped frames, decode path (remux or fallback), then extras.
12. Honest audio and video status: always show the active audio and HDR mode and, when a feature is unavailable, one plain sentence why. Never show a mode not in use.
13. Smooth transitions: keep the display mode between same-format episodes; prepare the next episode during the credits.
14. Versions: group files of the same film or episode into one item with a version picker; remember the choice.
15. Extras and editions: trailers, behind-the-scenes and bonus content, Director's Cut and similar, multi-part files.
16. Collections and franchises, Favorites pinned to Home, user-made collections, pinned folders in Files.
17. Playback conveniences: speed menu, temporary 2x by holding, chapter list and skipping, zoom and fill, sleep timer, audio night mode (off by default).
18. System integration: Siri and App Intents, Top Shelf, AirPlay in and out, Now Playing.
19. Accessibility: audio description tracks, captions, VoiceOver, Larger Text, Bold Text, Reduce Motion, Reduce Transparency, Increase Contrast.
20. Performance budgets, written down and tested where possible: cold launch to usable Home from cache in about 2 seconds, smooth scrolling in grids of thousands of posters, bounded memory, downsampled images. Report real measurements and say which need a device.
21. Backup: export and import of watch history, saved views, sources (no passwords) and settings, in addition to iCloud (CloudKit) sync. It matters most for people who are signed out of iCloud, because on tvOS only the iCloud copy survives a system cleanup (docs/STORAGE_MODEL.md). PROVISIONAL: the export file is plain JSON because it holds no secrets; alternative: encrypt it with a passphrase.

## Tier B: after Tier A
22. Connection Test: sample read, measured throughput, highest sustainable video bitrate, Ethernet or Wi-Fi, plain advice.
23. Library Statistics screen: totals, hours watched, breakdowns by resolution, HDR, audio, codec, container, genre, storage by resolution, watch time over time, most watched. All visible, most important first.
24. Deinterlacing for 50i and 60i as far as AVPlayer and the fallback engine allow (research first).
25. Subtitle search and download from a public database with the user's own key. RECLASSIFIED (R57): saved next to the video when the server allows it (durable, on the user's server); otherwise kept in Caches as a purgeable copy that is downloaded again on demand. The app never promises a downloaded subtitle file is still there next time.
26. Optional "Are you still watching?" after a set number of episodes (off by default).

## Tier C: research first
27. (Moved) Source types are not a later item. SMB, NFS, SFTP, FTP/FTPS, UPnP/DLNA, cloud storage (device-code sign-in) and media servers (Jellyfin, Emby, Plex) are built as one program behind one contract. See docs/SOURCES.md. Release gate (decided, R9): no public release until every technically possible source type passes its integration tests; platform-limited and account-blocked sources are excluded and documented.
28. Disc structures (BDMV, VIDEO_TS, ISO).
29. "Offline downloads" is NOT possible as persistent storage on tvOS (R57, docs/STORAGE_MODEL.md): everything outside the 500 KB of UserDefaults must be purgeable. Replaced by **Prefetch to cache, best effort, never promised**: the app may download the first minutes of the next episode or an item the user is about to play into Caches, and uses it only if it is still there. No "Downloaded" badge, no "available offline" label, no download list. PROVISIONAL; alternative: drop prefetch of whole titles and keep only the small read-ahead the player already does. (Whether tvOS 27 gives third-party apps any smart-download feature is still to be verified from Apple pages.)
30. On-device AI subtitles (verify existence and third-party availability first).
31. Dolby Vision Profile 7 playback or conversion quality (verify on real files).

## Considered and cut (kept visible; any can be reversed)
Separate user profiles, parental controls, Trakt sync, Ambient Mode, AI upscaling, Surprise Me random pick, local ratings and notes, Rewatch list, Wake-on-LAN, SharePlay watch-together, scrub thumbnails, dual subtitles, social features.

## Explicitly out of scope
Music, photos, podcasts, live TV, DVR, a hosted server, user accounts, ads.

## Later items added 2026-11-17 (visible so none vanishes)
32. **ASS original styling and typesetting (positions, colors, signs and songs).** NOT in the first release (D5, PROVISIONAL). Text subtitles are served as WebVTT renditions and drawn by the system player, which applies the viewer's own caption style; ASS positioning, colours, fonts, karaoke and "signs and songs" typesetting are flattened to text with basic italic and bold. A later item would draw ASS in an overlay of our own (an ASS renderer on top of the video). Trade-off against D1: an overlay is a second subtitle surface next to the system menu, so the system "What did they say?" replay and the system caption style would not apply to those tracks, and a second menu entry appears. Alternative if you want it now: draw ALL subtitles ourselves (the rejected D1 option a). PROVISIONAL.
33. Online timestamp lookups for intro, recap and credits (an online database of community timestamps): later. First release produces segments from chapters, sidecar files and user-marked positions only.
34. On-device detection of intros and credits (audio or picture analysis): later, research first.
35. Swift 6 language mode for App and TopShelf (after the first clean compile; OPEN_QUESTIONS R104/R108): first raise SWIFT_STRICT_CONCURRENCY from minimal to targeted, then complete, in Swift 5 mode and fix the warnings; then set SWIFT_VERSION to "6.0". Then decide the same for the package targets (VideoPlayerCore tools 5.9). The vendored SMB library is already Swift 6 mode.
36. OMDb ratings lookup (IMDb, Rotten Tomatoes, Metacritic scores): the key is stored but nothing calls OMDb yet (OPEN_QUESTIONS R120).
