#!/bin/zsh
# Remove Finder/iCloud "shadow duplicate" files that break project generation
# and release packaging when this repo lives under an iCloud-synced folder.

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
shift || true

DRY_RUN=0
QUIET=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --quiet) QUIET=1 ;;
    *)
      echo "usage: $0 [repo-root] [--dry-run] [--quiet]" >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$ROOT/.git" ]]; then
  echo "error: $ROOT does not look like the Loom repo root" >&2
  exit 1
fi

targets=()

add_matches() {
  local base="$1"
  shift
  [[ -d "$base" ]] || return 0
  while IFS= read -r -d '' match; do
    targets+=("$match")
  done < <(/usr/bin/find "$base" "$@" -print0 2>/dev/null)
}

add_matches "$ROOT" -maxdepth 1 -type d \( \
  -name "Loom [0-9]*.xcodeproj" -o \
  -name "LoomTestingEdition [0-9]*.xcodeproj" \
\)

add_matches "$ROOT/Loom" -type f \( \
  -name "* [0-9].swift" -o \
  -name "* [0-9].json" -o \
  -name "* [0-9].plist" -o \
  -name "* [0-9].entitlements" \
\)

add_matches "$ROOT/windows-tauri/src-tauri/src" -type f -name "* [0-9].rs"

if [[ "${#targets[@]}" -eq 0 ]]; then
  [[ "$QUIET" -eq 1 ]] || echo "no iCloud shadow duplicates found"
  exit 0
fi

for target in "${targets[@]}"; do
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "$target"
  else
    [[ "$QUIET" -eq 1 ]] || echo "removing $target"
    /bin/rm -rf -- "$target"
  fi
done
