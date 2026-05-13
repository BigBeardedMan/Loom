#!/bin/zsh
# Install the `lmstudio` CLI to ~/.local/bin (no sudo required).
#
# The CLI is a stdlib-only Python script; the install is just a symlink
# from the user's local bin to bin/lmstudio in this repo. Re-running the
# script updates the link in place.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${REPO_ROOT}/bin/lmstudio"
TARGET_DIR="${HOME}/.local/bin"
TARGET="${TARGET_DIR}/lmstudio"

if [[ ! -x "$SOURCE" ]]; then
  echo "error: ${SOURCE} not found or not executable" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"

if [[ -L "$TARGET" || -e "$TARGET" ]]; then
  rm -f "$TARGET"
fi
ln -s "$SOURCE" "$TARGET"

echo "installed: $TARGET -> $SOURCE"

case ":$PATH:" in
  *":$TARGET_DIR:"*)
    echo "ready: $TARGET_DIR is already on \$PATH"
    ;;
  *)
    echo ""
    echo "note: $TARGET_DIR is not on your \$PATH. Add this to your shell rc:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac

echo ""
echo "usage:"
echo "  export LMSTUDIO_MODEL=qwen2.5-coder-7b-instruct"
echo "  lmstudio                          # interactive REPL"
echo "  lmstudio \"refactor this file\"     # one-shot"
echo "  lmstudio --allow-bash \"...\"       # enable run_bash"
