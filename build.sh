#!/bin/zsh
# Builds "СДВГ Киллер.app" for Apple Silicon and Intel into build/.
# Needs only Command Line Tools (xcode-select --install), not Xcode.
#   ./build.sh            build
#   ./build.sh --install  build and copy to /Applications
#   ./build.sh --zip      build and pack build/ADHDKiller.zip for a GitHub release
set -euo pipefail
cd "$(dirname "$0")"

APP="build/СДВГ Киллер.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/focus_prompt.txt "$APP/Contents/Resources/"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos13.0" -module-cache-path build/cache \
        -o "build/ADHDKiller-$arch" Sources/*.swift -framework AppKit
done
lipo -create -output "$APP/Contents/MacOS/ADHDKiller" build/ADHDKiller-arm64 build/ADHDKiller-x86_64
rm -rf build/ADHDKiller-arm64 build/ADHDKiller-x86_64 build/cache

# Ad-hoc signature: no Apple ID needed.
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built: $APP"

case "${1:-}" in
    --install)
        pkill -x ADHDKiller 2>/dev/null || true
        rm -rf "/Applications/СДВГ Киллер.app"
        cp -R "$APP" /Applications/
        open "/Applications/СДВГ Киллер.app"
        echo "Installed: /Applications/СДВГ Киллер.app" ;;
    --zip)
        (cd build && ditto -c -k --keepParent "СДВГ Киллер.app" ADHDKiller.zip)
        echo "Packed: build/ADHDKiller.zip" ;;
esac
