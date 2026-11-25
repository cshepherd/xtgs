#!/usr/bin/env python3
"""Resource forks for the GS/OS application's Finder icon (docs/relocation.md).
From ../somi-iigs-port/iigs/tools/gsos_rfork.py, which worked the formats out.

    gsos_rfork.py program --name XTGS --large icon/dos_32x32.qdicon.bin \\
        --small icon/dos_16x16.qdicon.bin [--remap 9=4] [--no-trim] \\
        [--doc '*.EXE=MS-DOS program']... -o build/xtgs16.rfork
    gsos_rfork.py desktop --fork build/xtgs16.rfork --path :VOL:XTGS:XTGS -o Desktop.rfork

`program` is the application's own fork: an rBundle that names the file and
its type ($B3), the two rIcons, and rVersion and rComment for the Finder's
Icon Info window. Each --doc is a document of the application's: a record
of the bundle that matches a filename (PATTERN, `*` for any run of
characters, as GS.ShrinkIt's `*.SIT`), shows the application's icons for
it, has the Finder open the application when it is opened (docs/finder.md)
and, after an `=`, says what kind of file it is. The icons are QuickDraw II icon records as icon/README.md
describes them (iconType, iconSize, iconHeight, iconWidth, image, mask),
which is what an rIcon holds. cadius adds a file's resource fork from
NAME#TTAAAA_ResourceFork.bin beside it.

Two things the Finder (640 mode) does with a record, both seen in MAME:
  * It stands an icon on its name and gives a row of a window about 20
    lines, so a taller record loses its top in the first row (a 32-line
    one half of itself, and scrolling does not reach it). A record's
    empty rows count: `program` drops the rows above and below the
    drawing in which the mask is clear (--no-trim keeps them). The
    drawing itself is not touched.
  * A 4-bit pixel is two 2-bit screen pixels side by side, the left from
    black/red/green/white and the right from black/blue/yellow/white:
    sixteen dithered colours, which are not the sixteen entries of the
    640-mode colour table (TN #63). $E (white+yellow), $A (green+yellow)
    and $D (white+blue) are close to that table's yellow, green and
    blue, but $9 is green+blue, not red; the dithered red is $4
    (red+black). --remap FROM=TO (hex digits, repeatable) rewrites a
    pixel value in the drawing as the record goes into the fork.

The Finder (System 6.0.1) shows a bundle's icon only once the bundle is in
the volume's Icons/Desktop file, which it writes the first time the program
is launched from it; until then the program has the generic application
icon. `desktop` builds that file's resource fork from the program's (type
$C9, aux $0003, empty data fork), so that an image can carry it and the icon
shows before any launch: the two icons (the small one as ID 2), the rVersion
as $20000, the bundle with the small icon's ID 2 and two fields changed
(header +4: 0, record +$0A: 2), and an rFinderPath ($802C, $20000) naming
the program; all with attributes $40, and an index with spare slots (with
the same resources and a full index the Finder ignored the file).

The layout is GS.ShrinkIt's resource fork, read field by field:
  file    version (long 0), offset to the map (long), map size (long), a
          128-byte memo; the map follows at 140, the resources after it.
  map     next (long), flags (word), its file offset (long), its size
          (long), offset to the index (word, 116), file number (word), ID
          (word), index slots (long), slots used (long), free-list slots
          (word, 10), used (word, 1), the free list (8 bytes a slot: the
          one used is the space from the end of the file), 4 bytes, the
          index: 20 bytes a resource (type word, ID long, file offset
          long, attributes word, size long, handle long), in order of
          type and ID: the Resource Manager does not find entries out of
          order.
  rBundle an 18-byte header (copied: version 0, $0010, 1, 1, 0) ending
          in the number of records; each record its size (word), then
          the copied fields of GS.ShrinkIt's own-icon record with the
          large and small rIcon IDs at +$10 and +$18, and at +$2C the
          filename to match (a Pascal string), then 18 zero bytes. The
          file type it matches ($B3, at +$26) is in the copied fields.
          Read from the seventeen bundles of a System 6 volume's
          Desktop file (every record of them parses this way):
            +0  size (word)
            +2  offset of the match flags (word): $20, or past the kind
            +4  number of results (word): 4, or 5 with a kind
            +6  launch flags (word): bit 0, open the application for it
            +8  the rFinderPath's ID (long; 0 here, the Finder's in its
                Desktop file: $20000 + the application's number), long 0
            +10 large rIcon ID (long), long 0
            +18 small rIcon ID (long), long 0
            +20 with five results: the kind of file (a Pascal string)
            then the match flags (long), and for each of bits 0-11 a
            word: 0 when the bit is clear, the bit's number + 1 and its
            field when it is set. Bit 0 the file type (a word), bit 1
            the auxiliary type (a mask and a value, longs), bit 2 the
            filename (a Pascal string), bits 8 and 9 the HFS type and
            creator (longs).
  rVersion version (long: major, minor.bug, stage, release from the top
          byte down; GS.ShrinkIt's 1.1 is $0110A000), country (word),
          name and comment (Pascal strings).
The resource IDs are GS.ShrinkIt's (large icon 1, small $11, rVersion 1,
rComment 1).
"""
import argparse
import struct

R_ICON, R_VERSION, R_COMMENT, R_BUNDLE, R_FINDERPATH = 0x8001, 0x8029, 0x802A, 0x802B, 0x802C
LARGE_ID, SMALL_ID = 1, 0x11
MAP_AT, TO_INDEX, FREE_SLOTS = 140, 116, 10
NAME_AT = 18 + 0x2C                     # the filename in a one-record rBundle

# GS.ShrinkIt's own-icon rBundle record, from +2 up to its filename
RECORD_HEAD = bytes.fromhex(
    "2000" "0400" "01000000" "00000000" "0000"
    "01000000" "00000000" "11000000" "00000000"
    "05000000" "0100" "b3000000" "0300")
assert len(RECORD_HEAD) == 0x2C - 2
BUNDLE_HEAD = bytes.fromhex("0000" "1000" "01000000" "01000000" "00000000")


def icon(path, trim=True, remap=None):
    """The record at path; trim: without the rows above and below the
    drawing whose mask is clear; remap: {from: to} for the drawing's
    4-bit pixel values (where the mask is set)."""
    with open(path, "rb") as f:
        b = f.read()
    kind, size, h, w = struct.unpack_from("<HHHH", b)
    row = (w + 1) // 2
    if kind & 0x7FFF or len(b) != 8 + 2 * size or size != h * row:
        raise SystemExit(f"gsos_rfork: {path}: not a QuickDraw II icon record")
    image, mask = bytearray(b[8:8 + size]), b[8 + size:]
    for i, m in enumerate(mask):
        hi, lo = image[i] >> 4, image[i] & 15
        if m & 0xF0:
            hi = (remap or {}).get(hi, hi)
        if m & 0x0F:
            lo = (remap or {}).get(lo, lo)
        image[i] = hi << 4 | lo
    rows = [y for y in range(h) if any(mask[y * row:(y + 1) * row])]
    if trim and rows:
        top, end = rows[0], rows[-1] + 1
        image, mask = image[top * row:end * row], mask[top * row:end * row]
        h = end - top
    print(f"gsos_rfork: {path}: {w}x{h}")
    return struct.pack("<HHHH", kind, h * row, h, w) + bytes(image) + mask


def pstr(s):
    b = s.encode("ascii")
    return bytes([len(b)]) + b


def doc_record(pattern, kind, small, desktop):
    """A document: any file whose name matches, opened with the application."""
    results = struct.pack("<HIIIIII", 1, 0x20000 if desktop else 0, 0, LARGE_ID, 0, small, 0)
    if kind:
        results += pstr(kind)
    match = struct.pack("<IHH", 4, 0, 0) + struct.pack("<H", 3) + pstr(pattern) + bytes(18)
    body = struct.pack("<HH", 6 + len(results), 5 if kind else 4) + results + match
    return struct.pack("<H", 2 + len(body)) + body


def bundle(name, small=SMALL_ID, desktop=False, docs=()):
    """docs: (pattern, kind) pairs."""
    rec = bytearray(RECORD_HEAD)
    struct.pack_into("<I", rec, 0x10 - 2, LARGE_ID)
    struct.pack_into("<I", rec, 0x18 - 2, small)
    head = bytearray(BUNDLE_HEAD)
    if desktop:                         # as the Finder rewrites them
        struct.pack_into("<I", rec, 0x0A - 2, 2)
        struct.pack_into("<I", head, 4, 0)
    rec += pstr(name) + bytes(18)
    out = bytes(head) + struct.pack("<H", 1 + len(docs)) + struct.pack("<H", 2 + len(rec)) + rec
    for pattern, kind in docs:
        out += doc_record(pattern, kind, small, desktop)
    return out


def bundle_docs(b):
    """The (pattern, kind) pairs of a bundle this tool wrote."""
    n, = struct.unpack_from("<H", b, 16)
    at = 18 + struct.unpack_from("<H", b, 18)[0]
    docs = []
    for _ in range(n - 1):
        size, to_flags, results = struct.unpack_from("<HHH", b, at)
        kind = b[at + 0x21:at + 0x21 + b[at + 0x20]].decode("ascii") if results == 5 else ""
        name = at + to_flags + 10
        docs.append((b[name + 1:name + 1 + b[name]].decode("ascii"), kind))
        at += size
    return docs


def finder_path(path):
    b = path.encode("ascii")
    return struct.pack("<HHIIH", 0, 0x0E, 1, 2, 0) + struct.pack("<H", len(b)) + b


def fork(resources, attr=0, spare=0):
    """spare: empty index slots after the resources'."""
    n = len(resources)
    map_size = TO_INDEX + 20 * (n + spare)
    at = MAP_AT + map_size
    index, data = bytearray(), bytearray()
    for rtype, rid, body in sorted(resources, key=lambda r: (r[0], r[1])):
        index += struct.pack("<HIIHII", rtype, rid, at + len(data), attr, len(body), 0)
        data += body
    index += bytes(20 * spare)
    end = at + len(data)
    m = struct.pack("<IHIIHHHIIHH", 0, 0, MAP_AT, map_size, TO_INDEX, 0, 0, n + spare, n, FREE_SLOTS, 1)
    m += struct.pack("<II", end, (1 << 32) - end) + bytes(8 * (FREE_SLOTS - 1)) + bytes(4)
    assert len(m) == TO_INDEX
    return struct.pack("<III", 0, MAP_AT, map_size) + bytes(128) + m + index + data


def read_fork(path):
    """{(type, ID): body} of a fork this tool wrote."""
    with open(path, "rb") as f:
        b = f.read()
    _, map_at, _ = struct.unpack_from("<III", b)
    to_index, = struct.unpack_from("<H", b, map_at + 14)
    used, = struct.unpack_from("<I", b, map_at + 24)
    out = {}
    for i in range(used):
        rtype, rid, at, _attr, size, _h = struct.unpack_from("<HIIHII", b, map_at + to_index + 20 * i)
        out[rtype, rid] = b[at:at + size]
    return out


def version(text):
    """'0.1' or '1.2.3' -> the rVersion long, stage 'release'."""
    parts = [int(p) for p in text.split(".")] + [0, 0]
    major, minor, bug = parts[:3]
    if not (major < 100 and minor < 10 and bug < 10):
        raise SystemExit(f"gsos_rfork: version {text}: want MAJOR.MINOR[.BUG], one digit each after the first")
    return (major // 10 << 28) | (major % 10 << 24) | (minor << 20) | (bug << 16) | 0xA000


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="what", required=True)
    p = sub.add_parser("program", help="the application's resource fork")
    p.add_argument("--name", required=True, help="the filename the bundle matches")
    p.add_argument("--large", required=True)
    p.add_argument("--small", required=True)
    p.add_argument("--no-trim", action="store_true", help="keep the records' empty rows")
    p.add_argument("--remap", action="append", default=[], metavar="FROM=TO",
                   help="draw pixel value FROM as TO (hex digits)")
    p.add_argument("--title", default="XT/GS")
    p.add_argument("--version", default="0.1")
    p.add_argument("--about", default="8086/8088 PC for the Apple IIGS")
    p.add_argument("--comment", default="XT/GS: an IBM PC/XT for the Apple IIGS. "
                                        "Keep CORE, SVC and XTGS.CMD in this folder.")
    p.add_argument("--doc", action="append", default=[], metavar="PATTERN[=KIND]",
                   help="a document of the application's, by its filename (repeatable)")
    p.add_argument("-o", "--output", required=True)
    d = sub.add_parser("desktop", help="the volume's Icons/Desktop resource fork, from a program's")
    d.add_argument("--fork", required=True, help="the program's resource fork (from `program`)")
    d.add_argument("--path", required=True, help="the program on the volume, as :VOLUME:Folder:Name")
    d.add_argument("-o", "--output", required=True)
    args = ap.parse_args()

    if args.what == "program":
        try:
            remap = {int(a, 16): int(b, 16) for a, b in (r.split("=") for r in args.remap)}
        except ValueError:
            raise SystemExit(f"gsos_rfork: --remap {' '.join(args.remap)}: want FROM=TO, hex digits")
        if any(not 0 <= v < 16 for kv in remap.items() for v in kv):
            raise SystemExit("gsos_rfork: --remap: pixel values are 0 to F")
        docs = [tuple((d.split("=", 1) + [""])[:2]) for d in args.doc]
        for pattern, kind in docs:
            if not 0 < len(pattern) < 16 or len(kind) > 40:
                raise SystemExit(f"gsos_rfork: --doc {pattern}={kind}: a filename's pattern, 15 characters at most")
        out = fork([
            (R_BUNDLE, 1, bundle(args.name, docs=docs)),
            (R_ICON, LARGE_ID, icon(args.large, not args.no_trim, remap)),
            (R_ICON, SMALL_ID, icon(args.small, not args.no_trim, remap)),
            (R_VERSION, 1, struct.pack("<IH", version(args.version), 0) + pstr(args.title) + pstr(args.about)),
            (R_COMMENT, 1, args.comment.encode("ascii")),
        ])
        what = f"bundle for {args.name}" + "".join(f", {p}" for p, _ in docs)
    else:
        res = read_fork(args.fork)
        b = res[R_BUNDLE, 1]
        name = b[NAME_AT + 1:NAME_AT + 1 + b[NAME_AT]].decode("ascii")
        try:
            docs = bundle_docs(b)
        except (struct.error, IndexError, UnicodeDecodeError):
            docs = None
        if docs is None or bundle(name, docs=docs) != b:
            raise SystemExit(f"gsos_rfork: {args.fork}: not a bundle this tool wrote")
        out = fork([
            (R_ICON, 1, res[R_ICON, LARGE_ID]),
            (R_ICON, 2, res[R_ICON, SMALL_ID]),
            (R_VERSION, 0x20000, res[R_VERSION, 1]),
            (R_BUNDLE, 1, bundle(name, small=2, desktop=True, docs=docs)),
            (R_FINDERPATH, 0x20000, finder_path(args.path)),
        ], attr=0x40, spare=5)
        what = f"the Finder's Desktop file for {args.path}"
    with open(args.output, "wb") as f:
        f.write(out)
    print(f"gsos_rfork: {args.output}: {len(out)} bytes, {what}")


if __name__ == "__main__":
    main()
