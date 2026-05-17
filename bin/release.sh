#!/bin/zsh
# Build Release, package a .dmg, tag the commit, and publish a GitHub release.
#
#   bin/release.sh                # run from the repo root
#
# The version is read from project.yml (MARKETING_VERSION). Bump that, run
# this, and the running Loom on any user's Mac picks the new release up via
# GitHubReleaseFetcher within ~60 seconds.
#
# Requirements:
#   - xcodegen, xcodebuild        (dev tools)
#   - hdiutil                     (built-in, used to build the .dmg)
#   - gh CLI authenticated        (gh auth login)
#   - OpenSSL 3                   (used to sign release metadata)
#   - LOOM_RELEASE_SIGNING_KEY_PEM and LOOM_RELEASE_SIGNATURE_PUBLIC_KEY_BASE64
#   - clean working tree          (we tag the current HEAD)

set -euo pipefail

# Resolve the repo root from the script location so this works regardless of
# where it lives on disk. Override with PROJECT_ROOT=... when needed.
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DERIVED_BASE="${HOME}/Library/Developer/Xcode/DerivedData"
RELEASE_DIR="${PROJECT_ROOT}/build/release"
REPO="BigBeardedMan/Loom"
OPENSSL_BIN="${LOOM_OPENSSL_BIN:-}"

if [[ -z "$OPENSSL_BIN" ]]; then
  if [[ -x /opt/homebrew/opt/openssl@3/bin/openssl ]]; then
    OPENSSL_BIN=/opt/homebrew/opt/openssl@3/bin/openssl
  elif [[ -x /usr/local/opt/openssl@3/bin/openssl ]]; then
    OPENSSL_BIN=/usr/local/opt/openssl@3/bin/openssl
  else
    OPENSSL_BIN=$(command -v openssl || true)
  fi
fi

cd "$PROJECT_ROOT"

# --- Version ----------------------------------------------------------------

VERSION=$(/usr/bin/awk '/MARKETING_VERSION:/ {gsub(/[" ]/, "", $2); print $2; exit}' project.yml)
BUILD=$(/usr/bin/awk '/CURRENT_PROJECT_VERSION:/ {gsub(/[" ]/, "", $2); print $2; exit}' project.yml)
TAG="v${VERSION}"

if [[ -z "$VERSION" || -z "$BUILD" ]]; then
  echo "error: could not parse version/build from project.yml" >&2
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: MARKETING_VERSION '$VERSION' is not MAJOR.MINOR.PATCH semver" >&2
  exit 1
fi

echo "==> Loom ${VERSION} (${BUILD}) — tag ${TAG}"

# --- Pre-flight -------------------------------------------------------------

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI not installed. brew install gh" >&2
  exit 1
fi

# `gh auth status` exits non-zero whenever *any* configured account has a
# stale token, even if the active one is fine. Hit the API instead — that
# exercises only the active token.
if ! gh api user >/dev/null 2>&1; then
  echo "error: gh not authenticated for the active account. run: gh auth login -h github.com" >&2
  exit 1
fi

if [[ -z "$OPENSSL_BIN" || ! -x "$OPENSSL_BIN" ]]; then
  echo "error: OpenSSL 3 is required to sign release metadata. Install with: brew install openssl@3" >&2
  exit 1
fi

if ! "$OPENSSL_BIN" list -public-key-algorithms 2>/dev/null | /usr/bin/grep -qi "ED25519"; then
  echo "error: $OPENSSL_BIN does not support Ed25519. Set LOOM_OPENSSL_BIN to an OpenSSL 3 binary." >&2
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

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "error: working tree has uncommitted tracked changes; commit before releasing" >&2
  exit 1
fi

if git rev-parse --verify "$TAG" >/dev/null 2>&1; then
  echo "error: tag $TAG already exists locally. bump MARKETING_VERSION first." >&2
  exit 1
fi

# The unified release flow can race Windows CI: if CI publishes first, we
# upload to the existing release instead of creating it.
REUSE_EXISTING_RELEASE=0
if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  echo "note: release $TAG already exists on $REPO (likely created by Windows CI); appending DMG."
  REUSE_EXISTING_RELEASE=1
fi

# --- Build ------------------------------------------------------------------

echo "==> xcodegen"
xcodegen generate >/dev/null

echo "==> xcodebuild Release"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
    -project Loom.xcodeproj \
    -scheme Loom \
    -configuration Release \
    -quiet \
    "MARKETING_VERSION=${VERSION}" \
    "CURRENT_PROJECT_VERSION=${BUILD}" \
    "LOOM_RELEASE_SIGNATURE_PUBLIC_KEY_BASE64=${LOOM_RELEASE_SIGNATURE_PUBLIC_KEY_BASE64}" \
    build

BUILT=$(find "$DERIVED_BASE" -maxdepth 6 -type d -name "Loom.app" -path "*/Build/Products/Release/*" -print -quit)
if [[ -z "$BUILT" ]]; then
  echo "error: built Release/Loom.app not found under $DERIVED_BASE" >&2
  exit 1
fi
echo "==> built: $BUILT"

# --- Package .dmg -----------------------------------------------------------

mkdir -p "$RELEASE_DIR"
DMG_NAME="Loom-${VERSION}.dmg"
DMG_PATH="${RELEASE_DIR}/${DMG_NAME}"

# Clean previous artifact for this version (let the user re-run after a fix).
[[ -f "$DMG_PATH" ]] && rm -f "$DMG_PATH"

# Stage the .app in a temp dir with an /Applications symlink so the user's
# drag-to-install gesture works inside the mounted volume.
STAGE=$(mktemp -d -t loom-dmg)
cp -R "$BUILT" "$STAGE/Loom.app"
/usr/bin/xattr -cr "$STAGE/Loom.app"
ln -s /Applications "$STAGE/Applications"

echo "==> hdiutil create $DMG_NAME"
/usr/bin/hdiutil create \
  -volname "Loom" \
  -srcfolder "$STAGE" \
  -ov -quiet \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGE"
echo "==> dmg: $DMG_PATH ($(du -h "$DMG_PATH" | awk '{print $1}'))"

# --- Publish SHA-256 sidecar -----------------------------------------------
# GitHubReleaseFetcher fetches `<dmg>.sha256` and refuses to install the DMG
# if the hash doesn't match. Without this sidecar, in-app auto-update will
# fall back to "missing checksum — refusing to install" for this release.

CHECKSUM_PATH="${DMG_PATH}.sha256"
( cd "$RELEASE_DIR" && /usr/bin/shasum -a 256 "$DMG_NAME" > "$(basename "$CHECKSUM_PATH")" )
echo "==> sha256: $(awk '{print $1}' "$CHECKSUM_PATH")"

SIGNATURE_PATH="${CHECKSUM_PATH}.sig"
KEY_FILE=$(mktemp -t loom-release-key)
trap 'rm -f "$KEY_FILE"' EXIT
printf '%s' "$LOOM_RELEASE_SIGNING_KEY_PEM" > "$KEY_FILE"
"$OPENSSL_BIN" pkeyutl -sign -rawin -inkey "$KEY_FILE" -in "$CHECKSUM_PATH" | /usr/bin/base64 | /usr/bin/tr -d '\n' > "$SIGNATURE_PATH"
rm -f "$KEY_FILE"
trap - EXIT
echo "==> signature: $SIGNATURE_PATH"

# --- Tag + push -------------------------------------------------------------

echo "==> git tag $TAG"
git tag -a "$TAG" -m "Loom $VERSION ($BUILD)"
git push origin "$TAG"

# --- GitHub release ---------------------------------------------------------

NOTES_FILE=$(mktemp -t loom-notes)
cat >"$NOTES_FILE" <<EOF
Loom ${VERSION} (build ${BUILD})

## Install
1. Download \`${DMG_NAME}\` below.
2. Open it and drag **Loom** into your Applications folder.
3. First launch: right-click Loom → **Open** (the build is ad-hoc signed, not Developer ID; macOS will prompt once).

## Updates
Already running Loom? It auto-checks GitHub every 60 seconds. The **Update** pill in the top bar lights up when a newer release is staged — click it to swap in the new build.
EOF

if [[ "$REUSE_EXISTING_RELEASE" -eq 1 ]]; then
  echo "==> gh release upload $TAG (append to existing release)"
  gh release upload "$TAG" "$DMG_PATH" "$CHECKSUM_PATH" "$SIGNATURE_PATH" \
    -R "$REPO" \
    --clobber
else
  echo "==> gh release create $TAG"
  gh release create "$TAG" "$DMG_PATH" "$CHECKSUM_PATH" "$SIGNATURE_PATH" \
    -R "$REPO" \
    -t "Loom ${VERSION}" \
    -F "$NOTES_FILE"
fi

rm -f "$NOTES_FILE"

echo "==> released: https://github.com/${REPO}/releases/tag/${TAG}"
