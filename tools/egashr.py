#!/usr/bin/env python3
"""Does the SHR screen show the EGA's planes (mode 0Dh, 320x200 in 16
colours; docs/ega.md)? Packs the four planes' 8000 bytes from the 6845's
start address into SHR 320 pixels, a bit of each plane a pixel, and
compares them with the screen: a byte of the planes that changed without
its flag in EGA_DIRTY shows as stale. The palette is the attribute
controller's sixteen registers through the BIOS's colours (cga_rgb in
src/svc/video.s): the low three bits and bit 4 for the intensity, as the
card's 200-line monitor takes them.

    egashr.is_ega(shr_dump)
    bad = egashr.mismatches(planes, start, shr_dump)   # [(line, byte), ...]
    bad = egashr.palette(ac, shr_dump)                 # [(entry, got, want), ...]

planes is four byte strings, each plane from offset 0 as far as the
screen reaches; ac the attribute controller's first sixteen registers.
"""
import os

import textshr

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIDEO = os.path.join(ROOT, "src", "svc", "video.s")
LEN = 8000                                                  # bytes of a plane on the screen
SCB, PAL = 0x7D00, 0x7E00                                   # in a dump from $E1:2000
PLANES = (0xA0000, 0xC0000, 0xD0000, 0xE0000)               # in the guest's megabyte (src/include/pc.s)


def expected(planes, start):
    """The 32000 pixel bytes for the screen that begins at `start`."""
    pix = bytearray(32000)
    for o in range(LEN):
        b = [pl[start + o] for pl in planes]
        c = [sum((b[p] >> (7 - j) & 1) << p for p in range(4)) for j in range(8)]
        at = o // 40 * 160 + o % 40 * 4
        for k in range(4):
            pix[at + k] = c[k * 2] << 4 | c[k * 2 + 1]
    return pix


def is_ega(shr_dump):
    """Every scan line in 320 mode, palette 0."""
    return all(b == 0 for b in shr_dump[SCB:SCB + 200])


def mismatches(planes, start, shr_dump):
    want = expected(planes, start)
    return [(o // 160, o % 160 // 4) for o in range(0, 32000, 4) if shr_dump[o:o + 4] != want[o:o + 4]]


def palette(ac, shr_dump):
    rgb = textshr._table(VIDEO, "cga_rgb", "dw")
    assert len(rgb) == 16, len(rgb)
    bad = []
    for i in range(16):
        want = rgb[(ac[i] & 7) | (8 if ac[i] & 0x10 else 0)]
        got = shr_dump[PAL + i * 2] | shr_dump[PAL + i * 2 + 1] << 8
        if got != want:
            bad.append((i, got, want))
    return bad
