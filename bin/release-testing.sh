#!/bin/zsh
# Loom Testing Edition release. Reads MARKETING_VERSION from project.yml as
# the user-visible semver, packages a Mac DMG, tags as testing-<version>,
# and creates a GitHub pre-release. Windows CI picks the same tag up and
# appends NSIS installers.
#
#   bin/release-testing.sh           # run from the repo root, on the
#                                    # loom-testing-edition branch
#
# Versions follow semver and are always one or more minors ahead of the
# latest stable Loom release (so the in-app update pill never shows a code
# that looks lower than what's on main). Bump MARKETING_VERSION in
# project.yml before running this script. The pre-release flag keeps these
# builds out of the stable app's /releases/latest query.
#
# Requirements:
#   - xcodegen, xcodebuild        (dev tools)
#   - hdiutil                     (built-in, used to build the .dmg)
#   - gh CLI authenticated        (gh auth login)
#   - openssl                     (built-in, used to sign the checksum)
#   - LOOM_RELEASE_SIGNING_KEY_PEM and LOOM_RELEASE_SIGNATURE_PUBLIC_KEY_BASE64
#   - clean working tree on loom-testing-edition

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DERIVED_BASE="${HOME}/Library/Developer/Xcode/DerivedData"
RELEASE_DIR="${PROJECT_ROOT}/build/release"
REPO="BigBeardedMan/Loom"

cd "$PROJECT_ROOT"

# Sanity check the branch. release.sh ships from main; this one only ships
# from loom-testing-edition. Mixing the two has bitten us before.
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" != "loom-testing-edition" ]]; then
  echo "error: release-testing.sh must run on the loom-testing-edition branch (currently on $BRANCH)" >&2
  exit 1
fi

# --- Version ---------------------------------------------------------------
# Read MARKETING_VERSION out of project.yml. Single source of truth: the
# value Xcode stamps into the bundle is the same value we tag with on GitHub
# and show in the update pill.

VERSION=$(awk -F'"' '/^[[:space:]]+MARKETING_VERSION:[[:space:]]*"/{print $2; exit}' project.yml)
TAG="testing-${VERSION}"

if [[ -z "$VERSION" ]]; then
  echo "error: could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: MARKETING_VERSION '$VERSION' is not MAJOR.MINOR.PATCH semver" >&2
  exit 1
fi

echo "==> Loom Testing Edition ${VERSION} (tag ${TAG})"

# --- Pre-flight -------------------------------------------------------------

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI not installed. brew install gh" >&2
  exit 1
fi

if ! gh api user >/dev/null 2>&1; then
  echo "error: gh not authenticated for the active account. run: gh auth login -h github.com" >&2
  exit 1
fi

if [[ -z "${LOOM_RELEASE_SIGNING_KEY_PEM:-}" ]]; then
  echo "error: LOOM_RELEASE_SIGNING_KEY_PEM is required to sign the .sha256 sidecar" >&2
  exit 1
fi

if [[ -z "${LOOM_RELEASE_SIGNATURE_PUBLIC_KEY_BASE64:-}" ]]; then
  echo "error: LOOM_RELEASE_SIGNATURE_PUBLIC_KEY_BASE64 is required for the embedded updater trust key" >&2
  exit 1
fi

if git rev-parse --verify "$TAG" >/dev/null 2>&1; then
  echo "error: tag $TAG already exists locally. Bump MARKETING_VERSION in project.yml." >&2
  exit 1
fi

REUSE_EXISTING_RELEASE=0
if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  echo "note: pre-release $TAG already exists on $REPO (likely created by Windows CI); appending DMG."
  REUSE_EXISTING_RELEASE=1
fi

# --- Build ------------------------------------------------------------------

echo "==> xcodegen"
xcodegen generate >/dev/null

echo "==> xcodebuild Release (MARKETING_VERSION=${VERSION})"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
    -project LoomTestingEdition.xcodeproj \
    -scheme LoomTestingEdition \
    -configuration Release \
    -quiet \
    "MARKETING_VERSION=${VERSION}" \
    "LOOM_RELEASE_SIGNATURE_PUBLIC_KEY_BASE64=${LOOM_RELEASE_SIGNATURE_PUBLIC_KEY_BASE64}" \
    build

BUILT=$(find "$DERIVED_BASE" -maxdepth 6 -type d -name "Loom Testing Edition.app" -path "*/Build/Products/Release/*" -print -quit)
if [[ -z "$BUILT" ]]; then
  echo "error: built Release/Loom Testing Edition.app not found under $DERIVED_BASE" >&2
  exit 1
fi
echo "==> built: $BUILT"

# --- Package .dmg -----------------------------------------------------------

mkdir -p "$RELEASE_DIR"
DMG_NAME="LoomTestingEdition-${VERSION}.dmg"
DMG_PATH="${RELEASE_DIR}/${DMG_NAME}"

[[ -f "$DMG_PATH" ]] && rm -f "$DMG_PATH"

STAGE=$(mktemp -d -t loom-testing-dmg)
cp -R "$BUILT" "$STAGE/Loom Testing Edition.app"
/usr/bin/xattr -cr "$STAGE/Loom Testing Edition.app"
ln -s /Applications "$STAGE/Applications"

echo "==> hdiutil create $DMG_NAME"
/usr/bin/hdiutil create \
  -volname "Loom Testing Edition" \
  -srcfolder "$STAGE" \
  -ov -quiet \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGE"
echo "==> dmg: $DMG_PATH ($(du -h "$DMG_PATH" | awk '{print $1}'))"

# --- SHA-256 sidecar --------------------------------------------------------

CHECKSUM_PATH="${DMG_PATH}.sha256"
( cd "$RELEASE_DIR" && /usr/bin/shasum -a 256 "$DMG_NAME" > "$(basename "$CHECKSUM_PATH")" )
echo "==> sha256: $(awk '{print $1}' "$CHECKSUM_PATH")"

SIGNATURE_PATH="${CHECKSUM_PATH}.sig"
KEY_FILE=$(mktemp -t loom-release-key)
printf '%s' "$LOOM_RELEASE_SIGNING_KEY_PEM" > "$KEY_FILE"
/usr/bin/openssl pkeyutl -sign -rawin -inkey "$KEY_FILE" -in "$CHECKSUM_PATH" | /usr/bin/base64 > "$SIGNATURE_PATH"
rm -f "$KEY_FILE"
echo "==> signature: $SIGNATURE_PATH"

# --- Tag + push -------------------------------------------------------------

echo "==> git tag $TAG"
git tag -a "$TAG" -m "Loom Testing Edition $VERSION"
git push origin "$TAG"

# --- GitHub release ---------------------------------------------------------

NOTES_FILE=$(mktemp -t loom-testing-notes)
cat >"$NOTES_FILE" <<EOF
Loom Testing Edition \`${VERSION}\`

Pre-release channel. Installs alongside the main Loom build with its own
bundle ID, data folder, and Keychain service.

## Install
1. Download \`${DMG_NAME}\` (Mac) or \`LoomTestingEdition_${VERSION}_<arch>-setup.exe\` (Windows) below.
2. Open it and drag **Loom Testing Edition** into your Applications folder.
3. First launch on Mac: right-click **Loom Testing Edition → Open** to bypass Gatekeeper.
EOF

if [[ "$REUSE_EXISTING_RELEASE" -eq 1 ]]; then
  echo "==> gh release upload $TAG (append to existing pre-release)"
  gh release upload "$TAG" "$DMG_PATH" "$CHECKSUM_PATH" "$SIGNATURE_PATH" \
    -R "$REPO" \
    --clobber
else
  echo "==> gh release create $TAG (pre-release)"
  gh release create "$TAG" "$DMG_PATH" "$CHECKSUM_PATH" "$SIGNATURE_PATH" \
    -R "$REPO" \
    -t "Loom Testing Edition ${VERSION}" \
    --prerelease \
    -F "$NOTES_FILE"
fi

rm -f "$NOTES_FILE"

echo "==> released: https://github.com/${REPO}/releases/tag/${TAG}"
