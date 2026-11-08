#!/bin/bash
# make_image.sh IMAGE FILE...
#
# Build a bootable ProDOS volume (name XTGS): PRODOS, then every FILE,
# whose basename must carry cadius's NAME#TTAAAA suffix so it gets the
# right ProDOS type and aux type (the loader is XTGS.SYSTEM#FF2000, the
# bank images NAME#060000). VOLSIZE (environment, default 8192KB) sets
# the volume size; not "32MB", which cadius makes 65536 blocks, one past
# ProDOS's 16-bit block count.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
CADIUS="$here/cadius_strict.sh"
image="$1"; shift
rm -f "$image"
"$CADIUS" CREATEVOLUME "$image" XTGS "${VOLSIZE:-8192KB}" --quiet >/dev/null
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp "$here/../res/PRODOS" "$stage/PRODOS#FF0000"
"$CADIUS" ADDFILE "$image" /XTGS/ "$stage/PRODOS#FF0000" --quiet >/dev/null
for f in "$@"; do
    cp "$f" "$stage/$(basename "$f")"
    "$CADIUS" ADDFILE "$image" /XTGS/ "$stage/$(basename "$f")" --quiet >/dev/null
done
"$CADIUS" CATALOG "$image" | grep -E "XTGS|CORE|SVC|VEC|CMD|COM|Free"
