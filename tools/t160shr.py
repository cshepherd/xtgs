#!/usr/bin/env python3
"""Does the SHR screen show B800 as the 160x100 16-colour mode? Renders
the 80x100 cells the way src/svc/video.s t160_flush does and compares
them with the SHR pixels.

    t160shr.is_t160(shr_dump)                 # 320 mode, the 16 CGA colours
    bad = t160shr.mismatches(cells, shr_dump) # [(row, col), ...]

The masks of the characters the mode is used with are written out here
(what a CGA shows of them in two scan lines); every other character's
come from the generated table, so a wrong table shows up as a block
character's cell and a stale shadow as any cell's.
"""
import os

import textshr

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, "src", "svc", "gen", "t160.s")
CELLS = 16000
SCB, PAL = 0x7D00, 0x7E00                                   # in a dump from $E1:2000
CGA_RGB = [0x000, 0x00A, 0x0A0, 0x0AA, 0xA00, 0xA0A, 0xA50, 0xAAA,   # video.s cga_rgb
           0x555, 0x55F, 0x5F5, 0x5FF, 0xF55, 0xF5F, 0xFF5, 0xFFF]
# (first line, second line) of four pixels, left to right
BLOCKS = {0x00: ("....", "...."), 0x20: ("....", "...."), 0xFF: ("....", "...."),
          0xDB: ("####", "####"), 0xDD: ("##..", "##.."), 0xDE: ("..##", "..##"),
          0xDF: ("####", "####"), 0xDC: ("....", "....")}


def _masks():
    words = textshr._table(GEN, "t160_cm", "dw")
    out = []
    for ch in range(256):
        rows = []
        for w in words[ch * 2:ch * 2 + 2]:                  # the left byte is first in memory
            rows.append("".join("#" if w >> s & 15 else "." for s in (4, 0, 12, 8)))
        out.append(BLOCKS.get(ch, tuple(rows)))
    return out


def expected(cells):
    """The 32000 pixel bytes for these 16,000 bytes of B800."""
    masks = _masks()
    pix = bytearray(32000)
    for row in range(100):
        for col in range(80):
            ch, attr = cells[row * 160 + col * 2], cells[row * 160 + col * 2 + 1]
            fg, bg = attr & 15, attr >> 4
            for line in range(2):
                p = [fg if c == "#" else bg for c in masks[ch][line]]
                o = (row * 2 + line) * 160 + col * 2
                pix[o], pix[o + 1] = p[0] << 4 | p[1], p[2] << 4 | p[3]
    return pix


def is_t160(shr_dump):
    """Every scan line in 320 mode with palette 0, and that the CGA's colours."""
    pal = [shr_dump[PAL + 2 * i] | shr_dump[PAL + 2 * i + 1] << 8 for i in range(16)]
    return not any(shr_dump[SCB:SCB + 200]) and pal == CGA_RGB


def mismatches(cells, shr_dump):
    want, bad = expected(cells), []
    for row in range(100):
        for col in range(80):
            for line in range(2):
                o = (row * 2 + line) * 160 + col * 2
                if shr_dump[o:o + 2] != want[o:o + 2]:
                    bad.append((row, col))
                    break
    return bad
