#!/usr/bin/env python3
"""Does the SHR screen show B800 as CGA graphics? Packs the two fields'
200 lines the way src/svc/video.s gfx_flush does (its own tables, read
from the source) and compares them with the SHR pixels: a byte of B800
that changed without its page marked in VID_DIRTY shows as a stale line.

    cgashr.is_cga(shr_dump, mode)                 # mode 4, 5 or 6
    bad = cgashr.mismatches(b800, shr_dump, mode) # [(line, byte), ...]
    cols = cgashr.colours(sel, modereq, mode, tandy_regs)   # [c0, c1, c2, c3] or [c0, c1]
    bad = cgashr.palette(shr_dump, mode, cols)    # [(entry, got, want), ...]

b800 is the first 16 KB of the segment: the even lines' field at 0, the
odd lines' at $2000, 80 bytes a line.

The colours are worked out here from the registers, not read from
video.s's table: sel is the colour-select register (3D9h) as the guest
or the BIOS last wrote it, modereq the mode-control register (3D8h),
and tandy_regs, on a Tandy, the video array's 32 registers, whose mask
(01h) and palette (10h-1Fh) have the last word (docs/tandy.md).
"""
import os

import textshr

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIDEO = os.path.join(ROOT, "src", "svc", "video.s")
LEN = 0x4000
SCB, PAL = 0x7D00, 0x7E00                                   # in a dump from $E1:2000


def expected(b800, mode):
    """The 32000 pixel bytes for these 16 KB of B800."""
    tab = textshr._table(VIDEO, "cga640_tab" if mode == 6 else "cga320_tab", "dw")
    assert len(tab) == 256, len(tab)
    pix = bytearray(32000)
    for y in range(200):
        src = (y >> 1) * 80 + (0x2000 if y & 1 else 0)
        for i in range(80):
            w = tab[b800[src + i]]
            pix[y * 160 + i * 2], pix[y * 160 + i * 2 + 1] = w & 0xFF, w >> 8
    return pix


def is_cga(shr_dump, mode):
    """Every scan line in 640 mode (mode 6) or in 320 mode, palette 0."""
    return all(b == (0x80 if mode == 6 else 0) for b in shr_dump[SCB:SCB + 200])


def colours(sel, modereq, mode, tandy_regs=None):
    """Which of the CGA's sixteen colours each pixel value is shown in."""
    if mode == 6:                                           # a set pixel: 3D9h's low four bits
        cols = [0, sel & 15]
    else:
        bright = 8 if sel & 0x10 else 0
        if modereq & 4:                                     # mode 5: cyan, red, white
            three = [3, 4, 7]
        else:                                               # green/red/brown or cyan/magenta/white
            three = [2 + (sel >> 5 & 1), 4 + (sel >> 5 & 1), 6 + (sel >> 5 & 1)]
        cols = [sel & 15] + [c | bright for c in three]
    if tandy_regs is not None:
        cols = [tandy_regs[0x10 + (c & tandy_regs[1] & 15)] & 15 for c in cols]
    return cols


def palette(shr_dump, mode, cols):
    """The SHR palette entries the pixels use against those colours."""
    rgb = textshr._table(VIDEO, "cga_rgb", "dw")
    assert len(rgb) == 16, len(rgb)
    if mode == 6:                                           # cga640_tab: 0 or 3 of each group of four
        want = {g + 0: cols[0] for g in (0, 4, 8, 12)}
        want.update({g + 3: cols[1] for g in (0, 4, 8, 12)})
    else:
        want = dict(enumerate(cols))
    bad = []
    for i, c in sorted(want.items()):
        got = shr_dump[PAL + i * 2] | shr_dump[PAL + i * 2 + 1] << 8
        if got != rgb[c]:
            bad.append((i, got, rgb[c]))
    return bad


def mismatches(b800, shr_dump, mode):
    want = expected(b800, mode)
    return [(o // 160, o % 160 // 2) for o in range(0, 32000, 2) if shr_dump[o:o + 2] != want[o:o + 2]]
