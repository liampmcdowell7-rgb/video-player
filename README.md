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

## Rules
- No secrets in the repo. Keys and credentials go in Keychain or CI secure variables.
- Run `scripts/pre-push-check.sh` before any push.
