#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/MacBook Duo.app"
mkdir -p work build
# Reuse an identical binary so an incidental build command cannot invalidate TCC.
FINGERPRINT=$(shasum -a 256 Sources/MacBookDuo/*.swift Info.plist scripts/build.sh scripts/make-icon.swift | shasum -a 256 | cut -d ' ' -f 1)
if [[ -f work/build-fingerprint && -x "$APP/Contents/MacOS/MacBookDuo" && "$(cat work/build-fingerprint)" == "$FINGERPRINT:${DUO_SIGN_IDENTITY:--}" ]]; then
    xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
    echo "Unchanged: $APP"
    exit 0
fi
if pgrep -x MacBookDuo >/dev/null; then
    echo 'MacBook Duo is running. Quit it before rebuilding to preserve a consistent app identity.' >&2
    exit 1
fi
STAGING="$HOME/Library/Caches/MacBookDuo/work/MacBook Duo.app"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 Sources/MacBookDuo/*.swift -o "$STAGING/Contents/MacOS/MacBookDuo" -framework AppKit -framework SwiftUI -framework MetalKit -framework CoreImage -framework ScreenCaptureKit -framework IOKit -framework Carbon
xcrun swift scripts/make-icon.swift work/AppIcon.iconset
iconutil -c icns work/AppIcon.iconset -o "$STAGING/Contents/Resources/AppIcon.icns"
cp Info.plist "$STAGING/Contents/Info.plist"
xattr -cr "$STAGING"
codesign --force --sign "${DUO_SIGN_IDENTITY:--}" "$STAGING"
codesign --verify --strict "$STAGING"
ditto --norsrc --noextattr "$STAGING" "$APP"
# iCloud Desktop may attach Finder metadata while copying the bundle.
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
# The synchronized build copy may acquire FinderInfo again; install.sh
# strips that metadata and verifies the final /Applications installation.
printf '%s' "$FINGERPRINT:${DUO_SIGN_IDENTITY:--}" > work/build-fingerprint
echo "Built: $APP"
