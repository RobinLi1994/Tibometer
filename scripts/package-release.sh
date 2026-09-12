#!/bin/bash
set -euo pipefail
TIBOMETER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIBOMETER_APP="$TIBOMETER_ROOT/dist/Tibometer.app"
if [[ ! -d "$TIBOMETER_APP" ]]; then
    printf 'Build the app with ./scripts/build-app.sh first.\n' >&2
    exit 1
fi
codesign --verify --deep --strict "$TIBOMETER_APP"
TIBOMETER_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TIBOMETER_APP/Contents/Info.plist")"
TIBOMETER_EXPECTED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TIBOMETER_ROOT/Resources/Info.plist")"
if [[ "$TIBOMETER_VERSION" != "$TIBOMETER_EXPECTED_VERSION" ]]; then
    printf 'The app version differs from the source. Rebuild before packaging.\n' >&2
    exit 1
fi
TIBOMETER_ARCH="$(lipo -archs "$TIBOMETER_APP/Contents/MacOS/Tibometer")"
case "$TIBOMETER_ARCH" in
    arm64|x86_64) ;;
    "arm64 x86_64"|"x86_64 arm64") TIBOMETER_ARCH="universal" ;;
    *) printf 'Unsupported architecture: %s\n' "$TIBOMETER_ARCH" >&2; exit 1 ;;
esac
TIBOMETER_OUTPUT="$TIBOMETER_ROOT/dist/releases/v$TIBOMETER_VERSION"
TIBOMETER_ARCHIVE="Tibometer-$TIBOMETER_VERSION-macOS-$TIBOMETER_ARCH.zip"
mkdir -p "$TIBOMETER_OUTPUT"
ditto -c -k --norsrc --keepParent "$TIBOMETER_APP" "$TIBOMETER_OUTPUT/$TIBOMETER_ARCHIVE"
unzip -tq "$TIBOMETER_OUTPUT/$TIBOMETER_ARCHIVE"
(
    cd "$TIBOMETER_OUTPUT"
    shasum -a 256 "$TIBOMETER_ARCHIVE" > SHA256SUMS
)
printf 'Release files: %s\n' "$TIBOMETER_OUTPUT"
