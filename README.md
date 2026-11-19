# Video Player

Open-source tvOS 17+ video player that browses and plays files from WebDAV servers. SwiftUI, system components only.

Status: step 1 of 8 (scaffold and CI). Placeholder screens only.

## Layout
- `project.yml`: XcodeGen spec (the Xcode project is generated on the build machine)
- `App/`: the tvOS app (`Shell/` tab bar, `Features/` one folder per tab)
- `Packages/VideoPlayerCore/`: pure-Swift logic with unit tests
- `codemagic.yaml`: manual-only CI (compile check, TestFlight)
- `scripts/generate-icons.ps1`: regenerates the neutral app icon and Top Shelf image
- `docs/CODEMAGIC_SETUP.md`: step-by-step setup
- `docs/HIG_AUDIT.md`: Human Interface Guidelines audit
- `OPEN_QUESTIONS.md`: undecided items

## Verification status
Nothing here has been compiled yet: it was written on a machine without Swift or Xcode. The first compile check is the first real test and may need small fixes.

## Data sources and keys
The app ships with no key. Each user enters their own free TMDB key once, in Settings > Online Lookup; it covers every
source, library, Discover, pictures and details, and is never asked for per source. Wikidata and IntroDB need no key and
are used only after the user turns on Free Data Sources. The app is **non-commercial for now**. Full audit, terms
summaries and code map: `docs/DATA_SOURCES.md`.

| Source | Used for | Licence of the data | Needs | If the app were sold |
|---|---|---|---|---|
| TMDB | pictures, details, Fix Match, Discover, where to watch | TMDB API terms: personal, non-commercial key | the user's own key | needs a commercial agreement with TMDB, or remove it |
| JustWatch (through TMDB) | where to watch | through TMDB, credit required | the TMDB key | covered only by a TMDB agreement |
| Wikidata | cast names, IMDb numbers | CC0 | Free Data Sources on | unchanged |
| IntroDB | intro and recap times | IntroDB terms: commercial with reasonable use | Free Data Sources on | unchanged (bulk use only via their ODbL export) |

To get a TMDB key: create a free account at themoviedb.org, open account settings > API, ask for a developer key for
personal use and accept the terms, then enter the key in Settings > Online Lookup.

## Rules
- No secrets in the repo. Keys and credentials go in Keychain or CI secure variables.
- Run `scripts/pre-push-check.sh` before any push. Run this before git push, every time.
