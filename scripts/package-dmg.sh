#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Package an already verified build without changing its signature or settings.
APP_SOURCE="${1:-/Applications/MacBook Duo.app}"
DMG_OUTPUT="${2:-$PWD/dist/MacBook-Duo-1.0.0-arm64-test.dmg}"
if [[ ! -d "$APP_SOURCE" ]]; then
    echo "Missing app: $APP_SOURCE" >&2
    exit 1
fi
if [[ -e "$DMG_OUTPUT" ]]; then
    echo "Output already exists: $DMG_OUTPUT" >&2
    exit 1
fi
codesign --verify --deep --strict "$APP_SOURCE"
mkdir -p "$(dirname "$DMG_OUTPUT")" "$HOME/Library/Caches/MacBookDuo/work"
PACKAGE_WORK=$(mktemp -d "$HOME/Library/Caches/MacBookDuo/work/package.XXXXXX")
trap 'rm -rf "$PACKAGE_WORK"' EXIT
mkdir -p "$PACKAGE_WORK/volume" "$PACKAGE_WORK/mount"
ditto --norsrc --noextattr "$APP_SOURCE" "$PACKAGE_WORK/volume/MacBook Duo.app"
ln -s /Applications "$PACKAGE_WORK/volume/Applications"
cp 'Distribution/Read Me - 使用说明.txt' "$PACKAGE_WORK/volume/Read Me - 使用说明.txt"
codesign --verify --deep --strict "$PACKAGE_WORK/volume/MacBook Duo.app"

hdiutil create -volname 'MacBook Duo' -srcfolder "$PACKAGE_WORK/volume" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG_OUTPUT"
hdiutil verify "$DMG_OUTPUT"
hdiutil attach -readonly -nobrowse -mountpoint "$PACKAGE_WORK/mount" "$DMG_OUTPUT"
trap 'hdiutil detach "$PACKAGE_WORK/mount" >/dev/null 2>&1 || true; rm -rf "$PACKAGE_WORK"' EXIT
codesign --verify --deep --strict "$PACKAGE_WORK/mount/MacBook Duo.app"
cmp "$APP_SOURCE/Contents/MacOS/MacBookDuo" "$PACKAGE_WORK/mount/MacBook Duo.app/Contents/MacOS/MacBookDuo"
[[ "$(readlink "$PACKAGE_WORK/mount/Applications")" == /Applications ]]
[[ -s "$PACKAGE_WORK/mount/Read Me - 使用说明.txt" ]]
# Check the installed copy too, including the copy operation recipients perform.
ditto --norsrc --noextattr "$PACKAGE_WORK/mount/MacBook Duo.app" "$PACKAGE_WORK/install-check/MacBook Duo.app"
codesign --verify --deep --strict "$PACKAGE_WORK/install-check/MacBook Duo.app"
hdiutil detach "$PACKAGE_WORK/mount"
trap 'rm -rf "$PACKAGE_WORK"' EXIT

(cd "$(dirname "$DMG_OUTPUT")" && shasum -a 256 "$(basename "$DMG_OUTPUT")" > "$(basename "$DMG_OUTPUT").sha256")
echo "Packaged and verified: $DMG_OUTPUT"
