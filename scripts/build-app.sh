#!/bin/bash
set -euo pipefail
TIBOMETER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TIBOMETER_ROOT"
TIBOMETER_BUILD="$(mktemp -d /tmp/tibometer-build.XXXXXX)"
trap 'rm -rf "$TIBOMETER_BUILD"' EXIT
swift build -c release --product Tibometer --scratch-path "$TIBOMETER_BUILD" \
    -Xswiftc -file-prefix-map -Xswiftc "$TIBOMETER_ROOT=/Tibometer"
TIBOMETER_BIN="$(swift build -c release --scratch-path "$TIBOMETER_BUILD" --show-bin-path)"
TIBOMETER_APP="$TIBOMETER_ROOT/dist/Tibometer.app"
mkdir -p "$TIBOMETER_APP/Contents/MacOS" "$TIBOMETER_APP/Contents/Resources"
cp "$TIBOMETER_BIN/Tibometer" "$TIBOMETER_APP/Contents/MacOS/Tibometer"
strip -S "$TIBOMETER_APP/Contents/MacOS/Tibometer"
cp Resources/Info.plist "$TIBOMETER_APP/Contents/Info.plist"
cp LICENSE "$TIBOMETER_APP/Contents/Resources/LICENSE"
ditto "$TIBOMETER_BIN/Tibometer_TibometerCore.bundle" "$TIBOMETER_APP/Contents/Resources/Tibometer_TibometerCore.bundle"
ditto "$TIBOMETER_BIN/Tibometer_Tibometer.bundle" "$TIBOMETER_APP/Contents/Resources/Tibometer_Tibometer.bundle"
swift scripts/make-icon.swift "$TIBOMETER_APP/Contents/Resources" "$TIBOMETER_ROOT/Sources/Tibometer/Resources/Logo.png"
codesign --force --sign "${TIBOMETER_SIGN_IDENTITY:--}" --identifier app.tibometer.codex-limits "$TIBOMETER_APP"
codesign --verify --deep --strict "$TIBOMETER_APP"
printf 'Built: %s\n' "$TIBOMETER_APP"
