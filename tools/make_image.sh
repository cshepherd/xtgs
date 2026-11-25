#!/bin/bash
# make_image.sh IMAGE FILE...
#
# Build a bootable ProDOS volume (name XTGS): PRODOS, then every FILE,
# whose basename must carry cadius's NAME#TTAAAA suffix so it gets the
# right ProDOS type and aux type (the loader is XTGS.SYSTEM#FF2000, the
# bank images NAME#060000); a FILE that is a directory becomes a folder
# of that name with what it holds (the folder DOS boots from). VOLSIZE
# (environment, default 8192KB) sets the volume size; not "32MB", which cadius makes 65536 blocks, one past
# ProDOS's 16-bit block count.
#
# XTGS_LAYOUT=alt (environment) asks the loader for its test layout: a '+'
# before the command in XTGS.CMD (tools/layout.py; the harness translates
# addresses to match).
#
# XTGS_JIT=1 (environment) is every volume with the translator (docs/jit.md):
# the file JIT beside CORE, and the line JIT=ON at XTGS.CMD's end.
#
# XTGS_FPU=1 (environment) is every volume with the 8087 (docs/8087.md):
# the file FPU beside CORE, and the line FPU=8087 at XTGS.CMD's end. A
# volume whose XTGS.CMD has the line already gets the file too.
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
dirs=()
for f in "$@"; do
    if [ -d "$f" ]; then
        dirs+=("$f")
        continue
    fi
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
    if [ "$name" = "XTGS.CMD#040000" ]; then havecmd=1; fi
    if [ "$name" = "JIT#060000" ]; then havejit=1; fi
    if [ "$name" = "FPU#060000" ]; then havefpu=1; fi
    files+=("$stage/$name")
done
if [ -n "${XTGS_JIT:-}" ] && [ -n "${havecmd:-}" ]; then
    grep -q 'JIT=ON' "$stage/XTGS.CMD#040000" || printf 'JIT=ON\r' >> "$stage/XTGS.CMD#040000"
    if [ -z "${havejit:-}" ]; then
        cp "$here/../build/stage/JIT#060000" "$stage/JIT#060000"
        files+=("$stage/JIT#060000")
    fi
fi
if [ -n "${havecmd:-}" ]; then
    if [ -n "${XTGS_FPU:-}" ]; then
        grep -q 'FPU=' "$stage/XTGS.CMD#040000" || printf 'FPU=8087\r' >> "$stage/XTGS.CMD#040000"
    fi
    if grep -q 'FPU=8087' "$stage/XTGS.CMD#040000" && [ -z "${havefpu:-}" ]; then
        cp "$here/../build/stage/FPU#060000" "$stage/FPU#060000"
        files+=("$stage/FPU#060000")
    fi
fi
if [ "${XTGS_FRONT:-}" = s16 ]; then
    sys6="${SYSTEM6:-$here/../../ddiigs/assets/system6.hdv}"
    [ -f "$sys6" ] || { echo "make_image: no System 6 volume at $sys6 (set SYSTEM6=)" >&2; exit 1; }
    "$here/gsos_image.sh" "$sys6" "$image" "$here/../build/gsos/Start16" "${files[@]}" ${dirs[@]+"${dirs[@]}"}
    exit 0
fi
"$CADIUS" CREATEVOLUME "$image" XTGS "${VOLSIZE:-8192KB}" --quiet >/dev/null
cp "$here/../res/PRODOS" "$stage/PRODOS#FF0000"
"$CADIUS" ADDFILE "$image" /XTGS/ "$stage/PRODOS#FF0000" --quiet >/dev/null
for f in "${files[@]}"; do
    "$CADIUS" ADDFILE "$image" /XTGS/ "$f" --quiet >/dev/null
done
for d in ${dirs[@]+"${dirs[@]}"}; do
    "$CADIUS" ADDFOLDER "$image" "/XTGS/$(basename "$d")" "$d" --quiet >/dev/null
done
"$CADIUS" CATALOG "$image" | grep -E "XTGS|CORE|SVC|JIT|VEC|CMD|COM|Free"
