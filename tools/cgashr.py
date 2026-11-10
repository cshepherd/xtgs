#!/usr/bin/env python3
"""Does the SHR screen show B800 as CGA graphics? Packs the two fields'
200 lines the way src/svc/video.s gfx_flush does (its own tables, read
from the source) and compares them with the SHR pixels: a byte of B800
that changed without its page marked in VID_DIRTY shows as a stale line.

    cgashr.is_cga(shr_dump, mode)                 # mode 4, 5 or 6
    bad = cgashr.mismatches(b800, shr_dump, mode) # [(line, byte), ...]

b800 is the first 16 KB of the segment: the even lines' field at 0, the
odd lines' at $2000, 80 bytes a line.
"""
import os

import textshr

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIDEO = os.path.join(ROOT, "src", "svc", "video.s")
LEN = 0x4000
SCB = 0x7D00                                                # in a dump from $E1:2000


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


def mismatches(b800, shr_dump, mode):
    want = expected(b800, mode)
    return [(o // 160, o % 160 // 2) for o in range(0, 32000, 2) if shr_dump[o:o + 2] != want[o:o + 2]]
