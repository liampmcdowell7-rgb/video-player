#!/usr/bin/env bash
# CI only (compile-check.yml, jobs "screenshots", "screenshots-library" and "accessibility-screenshots": all build exactly this way).
# Builds the app and the UI tests for the booted simulator ($SIM_UDID), Debug, AD-HOC signed (identity "-", no team, no
# profile, no secret; OPEN_QUESTIONS R164); if that build fails, builds again unsigned and says so.
# Writes SIGNING and APP_PATH to $GITHUB_ENV for the later steps. Log: $OUT/test.log.
set -uo pipefail
bash "$(dirname "$0")/ci-stage.sh" "Build the app and the UI tests"
common=(-project VideoPlayer.xcodeproj -scheme VideoPlayerUITests -configuration Debug
        -destination "platform=tvOS Simulator,id=$SIM_UDID" -clonedSourcePackagesDirPath build/SourcePackages
        -derivedDataPath build/DerivedData -skipPackagePluginValidation -skipMacroValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES)
if xcodebuild build-for-testing "${common[@]}" \
     CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
     DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= 2>&1 | tee "$OUT/test.log"; then
  echo "SIGNING=ad-hoc" | tee -a "$GITHUB_ENV"
else
  echo "::warning::The ad-hoc signed build failed (errors above); building again unsigned (CODE_SIGNING_ALLOWED=NO): no entitlement will be embedded."
  xcodebuild build-for-testing "${common[@]}" CODE_SIGNING_ALLOWED=NO 2>&1 | tee -a "$OUT/test.log" || exit 1
  echo "SIGNING=unsigned" | tee -a "$GITHUB_ENV"
fi
APP="$(find build/DerivedData/Build/Products/Debug-appletvsimulator -maxdepth 1 -name 'VideoPlayer.app' -type d | head -n 1)"
[ -n "$APP" ] || { echo "::error::No VideoPlayer.app in build/DerivedData/Build/Products/Debug-appletvsimulator"; exit 1; }
echo "APP_PATH=$APP" >> "$GITHUB_ENV"
# #24 B: how big one shared build-for-testing artifact would be (the three UI jobs each build for about 7:45 now).
# Not shared yet: the size was never measured (docs/COVERAGE.md "UI-test jobs"). This line measures it.
{ echo "Build products (what a shared build-for-testing artifact would hold):"; du -sh build/DerivedData/Build/Products 2>&1
  du -sh build/DerivedData/Build/Products/* 2>&1; } | tee "$OUT/build-products-size.txt" || true
