#!/bin/bash
set -euo pipefail
TIBOMETER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$TIBOMETER_ROOT/scripts/build-app.sh"
TIBOMETER_DEST="${1:-$HOME/Applications}/Tibometer.app"
if pgrep -x Tibometer >/dev/null; then
    printf '请先从菜单栏退出 Tibometer，再重新安装。\n' >&2
    exit 1
fi
mkdir -p "$(dirname "$TIBOMETER_DEST")"
ditto "$TIBOMETER_ROOT/dist/Tibometer.app" "$TIBOMETER_DEST"
codesign --verify --deep --strict "$TIBOMETER_DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TIBOMETER_DEST"
open "$TIBOMETER_DEST"
printf 'Installed: %s\n' "$TIBOMETER_DEST"
