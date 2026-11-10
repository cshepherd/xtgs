#!/bin/bash
# gsos_image.sh SYSTEM6 IMAGE START FILE...
#
# A GS/OS boot volume as IMAGE, for launching XT/GS from GS/OS: ProDOS and
# the System folder of a System 6 volume (SYSTEM6, untouched) on a fresh
# volume named XTGS (GSOS_VOL in the environment for another name), VOLSIZE
# (environment, default 8192KB) large; every FILE (cadius NAME#TTAAAA
# names, as make_image.sh takes) in a new folder /VOL/XTGS, and a FILE
# that is a directory as a folder there with what it holds (the folder
# DOS boots from, docs/share.md); and START (an OMF load file,
# tests/gsos/start.s or start16.s) as /VOL/System/Start, the program GS/OS runs once it is up,
# so the volume boots straight into XT/GS with no Finder. START "-" is
# System 6's own Start instead, and its Icons/FType.* files with it (the
# Finder refuses to start without a file type descriptor file): the volume
# boots to the Finder.
#
# A FILE with a resource fork (NAME#TTAAAA_ResourceFork.bin beside it,
# which cadius adds with it) is the application with its Finder bundle
# (tools/gsos_rfork.py): the volume also gets /VOL/Icons/Desktop naming
# it, so the Finder shows its icon before the first launch.
#
# A file of the System folder that names its own volume is a file GS/OS
# would stop for at startup, asking for the disk of the old name (DeskMaker's
# System/DeskConfig, the pathname of the desktop picture, on one System 6
# volume). gsos_volname.py gives such pathnames the new name in the copy.
#
# The System folder is extracted once and the bare volume kept
# (GSOS_CACHE, default build/gsos: sys6/, start6/, icons6/ and
# base-NAME-VOLSIZE.hdv), redone when SYSTEM6 or this script is newer.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
CADIUS="$here/cadius_strict.sh"

sys6="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; image="$2"; start="$3"; shift 3
size="${VOLSIZE:-8192KB}"
cache="${GSOS_CACHE:-$here/../build/gsos}"
mkdir -p "$cache"
cache="$(cd "$cache" && pwd)"
vol="${GSOS_VOL:-XTGS}"
base="$cache/base-$vol-$size.hdv"
tmp="$cache/base-$vol-$size.tmp.hdv"       # (cadius goes by the extension)
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

if [ ! -f "$base" ] || [ "$sys6" -nt "$base" ] || [ "$0" -nt "$base" ]; then
    svol="$("$CADIUS" CATALOG "$sys6" | awk '/^\/[^ ]+\/$/ && !v {v = $0} END {print v}' | tr -d /)"
    [ -n "$svol" ] || { echo "gsos_image: no volume name in $sys6" >&2; exit 1; }
    rm -rf "$cache/sys6" "$cache/start6" "$cache/icons6" "$base" "$tmp"
    mkdir "$cache/sys6" "$cache/start6" "$cache/icons6"
    # (cadius cannot make the folders under some absolute paths: a relative one)
    (cd "$cache" && "$CADIUS" EXTRACTFOLDER "$sys6" "/$svol/SYSTEM/" sys6/ --quiet >/dev/null &&
        "$CADIUS" EXTRACTFILE "$sys6" "/$svol/ProDOS" sys6/ --quiet >/dev/null &&
        "$CADIUS" EXTRACTFOLDER "$sys6" "/$svol/ICONS/" icons6/ --quiet >/dev/null)
    sysdir="$(find "$cache/sys6" -mindepth 1 -maxdepth 1 -type d | head -1)"
    [ -f "$cache/sys6/ProDOS#FF0000" ] && [ -n "$sysdir" ] ||
        { echo "gsos_image: no ProDOS and System folder in $sys6" >&2; exit 1; }
    mv "$sysdir"/Start#* "$cache/start6/"       # START goes there
    python3 -I "$here/gsos_volname.py" "$svol" "$vol" "$sysdir"
    "$CADIUS" CREATEVOLUME "$tmp" "$vol" "$size" --quiet >/dev/null
    "$CADIUS" ADDFILE "$tmp" "/$vol/" "$cache/sys6/ProDOS#FF0000" --quiet >/dev/null
    "$CADIUS" ADDFOLDER "$tmp" "/$vol/System" "$sysdir" --quiet >/dev/null
    mv "$tmp" "$base"
fi

rm -f "$image"
cp -c "$base" "$image" 2>/dev/null || cp "$base" "$image"
ftypes=()
if [ "$start" = - ]; then
    start="$(find "$cache/start6" -name 'Start#*' ! -name '*_ResourceFork.bin' | head -1)"
    [ -n "$start" ] || { echo "gsos_image: $sys6 has no System/Start" >&2; exit 1; }
    while IFS= read -r f; do ftypes+=("$f"); done < <(find "$cache/icons6" -name 'FType.*#*' ! -name '*_ResourceFork.bin')
    [ ${#ftypes[@]} -gt 0 ] || { echo "gsos_image: $sys6 has no Icons/FType file" >&2; exit 1; }
else
    cp "$start" "$stage/Start#B30000"
    start="$stage/Start#B30000"
fi
"$CADIUS" ADDFILE "$image" "/$vol/SYSTEM/" "$start" --quiet >/dev/null
"$CADIUS" CREATEFOLDER "$image" "/$vol/XTGS" --quiet >/dev/null
app=
for f in "$@"; do
    if [ -d "$f" ]; then
        "$CADIUS" ADDFOLDER "$image" "/$vol/XTGS/$(basename "$f")" "$f" --quiet >/dev/null
        continue
    fi
    "$CADIUS" ADDFILE "$image" "/$vol/XTGS/" "$f" --quiet >/dev/null
    if [ -f "${f}_ResourceFork.bin" ]; then
        [ -z "$app" ] || { echo "gsos_image: two files with a resource fork: $app, $f" >&2; exit 1; }
        app="$f"
    fi
done
if [ -n "$app" ] || [ ${#ftypes[@]} -gt 0 ]; then
    "$CADIUS" CREATEFOLDER "$image" "/$vol/Icons" --quiet >/dev/null
fi
for f in ${ftypes[@]+"${ftypes[@]}"}; do
    "$CADIUS" ADDFILE "$image" "/$vol/Icons/" "$f" --quiet >/dev/null
done
if [ -n "$app" ]; then
    name="$(basename "$app")"
    : > "$stage/Desktop#C90003"
    python3 -I "$here/gsos_rfork.py" desktop --fork "${app}_ResourceFork.bin" \
        --path ":$vol:XTGS:${name%%#*}" -o "$stage/Desktop#C90003_ResourceFork.bin" >/dev/null
    "$CADIUS" ADDFILE "$image" "/$vol/Icons/" "$stage/Desktop#C90003" --quiet >/dev/null
fi
"$CADIUS" CATALOG "$image" | grep -E "^/|^    Start |^  /XTGS/|^  /ICONS/|^    /SHARED/|^    (XTGS|CORE|SVC|DISK|Desktop|FType)[. ]|Free :" | cut -c1-72
