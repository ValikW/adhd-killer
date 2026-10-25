#!/bin/bash
# СДВГ Киллер / ADHD Killer installer.
#   curl -fsSL https://raw.githubusercontent.com/ValikW/adhd-killer/main/install.sh | bash
set -euo pipefail

REPO="ValikW/adhd-killer"
APP="СДВГ Киллер.app"
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"

if [ "$(uname)" != "Darwin" ]; then
    echo "Only macOS is supported." >&2; exit 1
fi
major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -lt 13 ]; then
    echo "macOS 13 Ventura or newer is required." >&2; exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "→ Downloading the latest release…"
curl -fsSL -o "$tmp/ADHDKiller.zip" "https://github.com/$REPO/releases/latest/download/ADHDKiller.zip"
ditto -x -k "$tmp/ADHDKiller.zip" "$tmp"

echo "→ Installing to $DEST…"
pkill -x ADHDKiller 2>/dev/null || true
mkdir -p "$DEST"
rm -rf "$DEST/$APP"
mv "$tmp/$APP" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

open "$DEST/$APP"
echo "✓ Done. Look for the ◎ icon in the menu bar."
echo "  Готово. Ищи значок ◎ в строке меню."
