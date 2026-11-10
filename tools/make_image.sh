#!/bin/bash
# make_image.sh IMAGE FILE...
#
# Build a bootable ProDOS volume (name XTGS): PRODOS, then every FILE,
# whose basename must carry cadius's NAME#TTAAAA suffix so it gets the
# right ProDOS type and aux type (the loader is XTGS.SYSTEM#FF2000, the
# bank images NAME#060000). VOLSIZE (environment, default 8192KB) sets
# the volume size; not "32MB", which cadius makes 65536 blocks, one past
# ProDOS's 16-bit block count.
#
# XTGS_LAYOUT=alt (environment) asks the loader for its test layout: a '+'
# before the command in XTGS.CMD (tools/layout.py; the harness translates
# addresses to match).
#
# XTGS_FRONT=s16 (environment) makes it a GS/OS volume instead, booting
# into the native front end: tools/gsos_image.sh with the System 6 volume
# SYSTEM6 (environment; default ../ddiigs/assets/system6.hdv), the files
# in its folder /VOL/XTGS, the S16 application XTGS#B30000 from the same
# folder in place of XTGS.SYSTEM#FF2000 (with its resource fork, the file
# XTGS#B30000_ResourceFork.bin beside it), and build/gsos/Start16 to launch it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
CADIUS="$here/cadius_strict.sh"
image="$1"; shift
rm -f "$image"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
files=()
for f in "$@"; do
    name="$(basename "$f")"
    if [ "${XTGS_FRONT:-}" = s16 ] && [ "$name" = "XTGS.SYSTEM#FF2000" ]; then
        name="XTGS#B30000"
        f="$(dirname "$f")/$name"
        if [ -f "${f}_ResourceFork.bin" ]; then
            cp "${f}_ResourceFork.bin" "$stage/${name}_ResourceFork.bin"
        fi
    fi
    if [ "${XTGS_LAYOUT:-}" = alt ] && [ "$name" = "XTGS.CMD#040000" ]; then
        { printf '+'; cat "$f"; } > "$stage/$name"
    else
        cp "$f" "$stage/$name"
    fi
    files+=("$stage/$name")
done
if [ "${XTGS_FRONT:-}" = s16 ]; then
    sys6="${SYSTEM6:-$here/../../ddiigs/assets/system6.hdv}"
    [ -f "$sys6" ] || { echo "make_image: no System 6 volume at $sys6 (set SYSTEM6=)" >&2; exit 1; }
    "$here/gsos_image.sh" "$sys6" "$image" "$here/../build/gsos/Start16" "${files[@]}"
    exit 0
fi
"$CADIUS" CREATEVOLUME "$image" XTGS "${VOLSIZE:-8192KB}" --quiet >/dev/null
cp "$here/../res/PRODOS" "$stage/PRODOS#FF0000"
"$CADIUS" ADDFILE "$image" /XTGS/ "$stage/PRODOS#FF0000" --quiet >/dev/null
for f in "${files[@]}"; do
    "$CADIUS" ADDFILE "$image" /XTGS/ "$f" --quiet >/dev/null
done
"$CADIUS" CATALOG "$image" | grep -E "XTGS|CORE|SVC|VEC|CMD|COM|Free"
