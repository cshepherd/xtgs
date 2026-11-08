#!/usr/bin/env bash
# Boot an XT/GS image in Ample's MAME (apple2gs, ROM 03) with the
# claudebridge Lua bridge, for interactive debugging with tools/mame/mame-lua.
#
#   tools/mame/run-mame.sh [IMAGE] [extra mame args]      (default build/xtgs.po)
#   tools/mame/run-mame.sh build/xtgs.po -debug            MAME debugger too
#
# The bridge uses fixed /tmp paths: run one bridged MAME at a time. Install
# the plugin once with tools/mame/install-plugin.sh.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGE="${1:-$REPO/build/xtgs.po}"
[ $# -gt 0 ] && shift
[ -f "$IMAGE" ] || { echo "run-mame: no $IMAGE (make first)" >&2; exit 1; }
IMAGE="$(cd "$(dirname "$IMAGE")" && pwd)/$(basename "$IMAGE")"
MAME=""
for app in "${AMPLE_APP:-}" /Applications/Ample.app "$HOME/Applications/Ample.app"; do
    if [ -n "$app" ] && [ -x "$app/Contents/MacOS/mame64" ]; then MAME="$app/Contents/MacOS/mame64"; break; fi
done
[ -n "$MAME" ] || { echo "run-mame: Ample.app not found; set AMPLE_APP" >&2; exit 1; }
if [ ! -f "$HOME/Library/Application Support/Ample/plugins/claudebridge/init.lua" ]; then
    echo "run-mame: claudebridge plugin missing; run tools/mame/install-plugin.sh" >&2
fi
cd "$HOME/Library/Application Support/Ample"
exec "$MAME" apple2gs -skip_gameinfo -nosamples -window -nounevenstretch -video bgfx \
    -ramsize 8M -sl7 scsi -hard1 "$IMAGE" -plugin claudebridge "$@"
