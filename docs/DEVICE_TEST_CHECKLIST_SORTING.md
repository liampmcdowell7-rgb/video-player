# Device test checklist: sorting files into Movies and Shows (docs/SORTING.md, OPEN_QUESTIONS R171)

Nothing here has been seen on a device. Each line says what to do and what passes. Use synthetic file names only.

- SO1. **Flat mixed folder sorts into Movies and Shows.** Put these files in ONE folder of a WebDAV or SMB share, with no
  subfolders: `Sample.Show.S01E01.2160p.WEB-DL.x265-GRP.mkv`, `Sample Show 1x02.mkv`, `Sample Show Season 1 Episode 3.mkv`,
  `Sample Anime - 001.mkv`, `Sample Anime - 002.mkv`, `Sample Movie (2019).mkv`, `Sample.Movie.Four.2021.2160p.mkv`,
  `Sample Movie 2049 (2017).mkv`, `Sample Clip.mkv`, `Sample Lone Show - 007.mkv`. Add the share and let it scan.
  Pass: Shows has "Sample Show" (3 episodes, S1 E1 to E3) and "Sample Anime" (2 episodes); Movies has "Sample Movie"
  (2019), "Sample Movie Four" (2021) and "Sample Movie 2049" (2017); neither "Sample Clip" nor "Sample Lone Show" appears in
  Movies, Shows, Home, Search or the Settings > Library counts; Settings > Library > Needs Review shows 2 and lists both
  with a reason.
- SO2. In Needs Review choose "Sample Clip.mkv" > Move to Movies, keep the title, Year 2011, Move. Pass: it leaves the list
  at once; after the scan it is in Movies as "Sample Clip" (2011); the Needs Review count is 1.
- SO3. Choose "Sample Lone Show - 007.mkv" > Move to Shows. Pass: the form says Show "Sample Lone Show", Season 1,
  Episode 7; after Move the show appears in Shows with S1 E7.
- SO4. In the Move form type Year "19", then Season empty. Pass: a calm sentence says what to fix; nothing is saved.
- SO5. Long press a movie card. Pass: the menu has Move to Shows next to Mark as Watched and Add to Favorites. Long press an
  episode card: Move to Movies.
- SO6. Open "Sample Clip" > More > How This Was Sorted. Pass: Sorted By "Moved by Hand", the file name, Move to Shows and
  Sort Automatically. Choose Sort Automatically. Pass: after the scan it is back in Needs Review.
- SO7. Scan Now twice. Pass: nothing moves between Movies, Shows and Needs Review.
- SO8. A second Apple TV signed in to the same iCloud account with the same source. Pass: after its sync and scan, the
  moves made in SO2 and SO3 are there too.
- SO9. Open "Sample Movie (2019)" > More > How This Was Sorted. Pass: "Year in the File Name" and "A year in the file name
  and no episode pattern."; "Sample Show" episodes say "Episode Pattern in the File Name".
- SO10. With a TMDB key entered (Settings > Online Lookup), put a year-less file named after a well-known film into the
  folder and relaunch. Pass: if TMDB confirms it, it is in Movies and How This Was Sorted says "Online Lookup"; if not, it
  stays in Needs Review. Without a key nothing is sent (no network request at all for it).
- SO11. A Jellyfin or Emby source with a movie library that holds a file named like an episode (`Sample Show S01E04.mkv`).
  Pass: it is in Shows and How This Was Sorted says "File Name, Not the Server" and "Sorted by filename, not by the server."
  A file named `Sample Clip.mkv` in that movie library is in Movies with "Server Library Type".
- SO12. On that source: Settings > Sources > the source > Sort by Filename Instead of Server Library Types, on. Pass: after
  the scan `Sample Clip.mkv` moves to Needs Review; turning it off brings it back to Movies.
- SO13. Console (Mac, connected Apple TV), category "Sorting", debug messages on. Pass: one line per file:
  "sorted movie by moviePattern: <private> (...)"; the path is not shown in clear.
- SO14. Discover. Pass: nothing in Discover changes; Discover titles never appear in Needs Review.
- SO15 (addendum #18 G). Your own flat mixed folder (movies and episodes side by side, no Movies/TV split) on the real
  Jellyfin source. Step 1: Settings > Sources > the source > Sort by Filename Instead of Server Library Types, off; Scan
  Now. Write down every file in Settings > Library > Needs Review (the file name and the note under it). Step 2: turn the
  setting on; Scan Now; write the list down again. Pass: every file is in exactly one of Movies, Shows or Needs Review in
  both steps, nothing is lost, and the report names which files were in Needs Review in each step and which ones moved
  between the two steps. Expected, not yet seen on a device: with the setting off, Jellyfin's own types decide and few
  or no files are in Needs Review; with it on, files with neither an episode pattern nor a year (and no folder hint) are
  in Needs Review.
