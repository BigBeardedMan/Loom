#!/bin/zsh
# Build Release and stage it for Loom's in-app Update button.
#
# Run this anytime you want to stage a change for a running Loom install:
#   bin/stage.sh                  # run from the repo root
#
# It builds to Xcode's default DerivedData (outside iCloud, so iCloud doesn't
# rename the output dirs mid-build), copies the bundle into
# ~/Library/Application Support/Loom/staging/Loom.app,
# and writes manifest.json with the build code pulled from the bundle's
# Info.plist. The running Loom app polls the manifest and lights up its
# Update button. Clicking it performs the swap into
# /Applications/Loom.app and relaunches.
#
# DO NOT cp -R Release/Loom.app over /Applications/Loom.app
# while the app is running. That's what crashed the app before this script
# existed.

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DERIVED_BASE="${HOME}/Library/Developer/Xcode/DerivedData"
STAGING_DIR="${HOME}/Library/Application Support/Loom/staging"

cd "$PROJECT_ROOT"

# Build code: first 10 chars of HEAD SHA. Lets `stage.sh` exercise the same
# code path end-to-end without cutting a real release.
BUILD_CODE=$(git rev-parse HEAD | cut -c1-10)

echo "==> xcodegen"
xcodegen generate >/dev/null

echo "==> xcodebuild Release (MARKETING_VERSION=${BUILD_CODE})"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
    -project Loom.xcodeproj \
    -scheme Loom \
    -configuration Release \
    -quiet \
    "MARKETING_VERSION=${BUILD_CODE}" \
    build

BUILT=$(find "$DERIVED_BASE" -maxdepth 6 -type d -name "Loom.app" -path "*/Build/Products/Release/*" -print -quit)
if [[ -z "$BUILT" ]]; then
  echo "error: built Release/Loom.app not found under $DERIVED_BASE" >&2
  exit 1
fi
echo "==> built: $BUILT"

mkdir -p "$STAGING_DIR"
STAGED="$STAGING_DIR/Loom.app"

if [[ -d "$STAGED" ]]; then rm -rf "$STAGED"; fi
cp -R "$BUILT" "$STAGED"
/usr/bin/xattr -cr "$STAGED"

VERSION=$(/usr/bin/defaults read "$STAGED/Contents/Info.plist" CFBundleShortVersionString)
BUILDNO=$(/usr/bin/defaults read "$STAGED/Contents/Info.plist" CFBundleVersion)
NOW=$(date -u +%FT%TZ)

cat >"$STAGING_DIR/manifest.json" <<EOF
{
  "version": "$VERSION",
  "build": "$BUILDNO",
  "stagedAt": "$NOW"
}
EOF

echo "==> staged Loom $VERSION ($BUILDNO) at $STAGED"
echo "    user can click Update inside the running Loom app to apply."
