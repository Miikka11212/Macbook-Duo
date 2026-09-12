#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE_APP="$PWD/build/MacBook Duo.app"
INSTALLED_APP="/Applications/MacBook Duo.app"
if pgrep -x MacBookDuo >/dev/null; then
    echo 'Quit MacBook Duo before installing a new version.' >&2
    exit 1
fi
if [[ ! -x "$SOURCE_APP/Contents/MacOS/MacBookDuo" ]]; then
    ./scripts/build.sh
fi
# Exclude iCloud/Finder metadata; preserve the compiled code signature.
ditto --norsrc --noextattr "$SOURCE_APP" "$INSTALLED_APP"
codesign --verify --strict "$INSTALLED_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALLED_APP"
echo "Installed: $INSTALLED_APP"
echo 'If this was a changed ad-hoc build, macOS may require a fresh screen-recording grant.'
