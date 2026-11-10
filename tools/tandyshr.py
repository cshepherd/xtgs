#!/usr/bin/env python3
"""Does the SHR screen show the Tandy's mode 09h (320x200 in 16 colours)
or 08h (160x200 in 16; docs/tandy.md)? In mode 09h the screen is two of
the eight 16K pages, the even one the page register names (bits 0-2) and
the next; line y is in the 8K bank y & 3 of those 32K at (y >> 2) * 160,
a pixel four bits and the left one a byte's high four: the SHR's 320 mode
a byte for a byte. In mode 08h it is the one page the register names,
laid out as the CGA's graphics are: line y at (y & 1) * 8K + (y >> 1) *
80, a byte two pixels, each of them two of the SHR's. The pages are
read from where they are kept (TDY_SLOT, src/include/pc.s), so a page
that is shown but not the CPU's is judged too, and a line that changed
without its flag in VID_DIRTY shows as stale. The palette is the video
array's sixteen registers, reached through the palette mask, each one of
the BIOS's sixteen colours (cga_rgb in src/svc/video.s).

    tandyshr.is_tandy9(shr_dump)                       # (either mode: SHR 320, palette 0)
    tandyshr.mode(state, modereq)                      # 8, 9 or None: what the ports ask for
    bad = tandyshr.mismatches(mem, state, shr_dump, mode=9)   # [(line, byte), ...]
    bad = tandyshr.palette(state, shr_dump)            # [(entry, got, want), ...]

mem is {guest address: bytes} for the REGIONS; state the 48 bytes from
TDY_ON (ON, IDX, PAGE, MOVES as words, the eight slots, the registers);
modereq the byte at MODEREQ in the results bank (the CGA's mode register,
3D8h, as the guest last wrote it).
"""
import os

import textshr

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIDEO = os.path.join(ROOT, "src", "svc", "video.s")
SCB, PAL = 0x7D00, 0x7E00                                   # in a dump from $E1:2000
STATE, STATE_LEN = 0x990, 48                                # TDY_ON in the results bank
MODEREQ = 0x870                                             # CGA_MODEREQ there
SLOTS = (0xA0000, 0xA4000, 0xA8000, 0xAC000, 0xC0000, 0xC4000, 0xB8000, 0xBC000, 0xC8000)
REGIONS = ((0xA0000, 0x10000), (0xB8000, 0x8000), (0xC0000, 0xC000))   # what holds the slots


def page_reg(state):
    return state[4]


def slots(state):
    return list(state[8:16])


def regs(state):
    return state[16:48]


def page(mem, state, n):
    """The 16K of page n, wherever it is."""
    at = SLOTS[slots(state)[n]]
    for base, size in REGIONS:
        if base <= at < base + size:
            return mem[base][at - base:at - base + 0x4000]
    raise ValueError(f"page {n} is in no slot the judge reads")


def expected(mem, state):
    """The 32000 pixel bytes of the two pages shown."""
    d0 = page_reg(state) & 6
    both = page(mem, state, d0) + page(mem, state, d0 + 1)
    pix = bytearray(32000)
    for y in range(200):
        at = (y & 3) * 0x2000 + (y >> 2) * 160
        pix[y * 160:y * 160 + 160] = both[at:at + 160]
    return pix


def expected8(mem, state):
    """The 32000 pixel bytes of mode 08h's one page: a pixel twice."""
    pg = page(mem, state, page_reg(state) & 7)
    pix = bytearray(32000)
    for y in range(200):
        at = (y & 1) * 0x2000 + (y >> 1) * 80
        for x in range(80):
            b = pg[at + x]
            pix[y * 160 + x * 2] = (b >> 4) * 0x11
            pix[y * 160 + x * 2 + 1] = (b & 15) * 0x11
    return pix


def is_tandy9(shr_dump):
    """Every scan line in 320 mode, palette 0 (mode 08h is the same)."""
    return all(b == 0 for b in shr_dump[SCB:SCB + 200])


def mode(state, modereq):
    """The 16-colour mode the array and the CGA's mode register ask for."""
    if not regs(state)[3] & 0x10 or not modereq & 2:
        return None
    return 9 if modereq & 1 else 8


def mismatches(mem, state, shr_dump, mode=9):
    want = expected8(mem, state) if mode == 8 else expected(mem, state)
    return [(o // 160, o % 160) for o in range(32000) if shr_dump[o] != want[o]]


def palette(state, shr_dump):
    rgb = textshr._table(VIDEO, "cga_rgb", "dw")
    assert len(rgb) == 16, len(rgb)
    r = regs(state)
    bad = []
    for i in range(16):
        want = rgb[r[0x10 + (i & r[1] & 15)] & 15]
        got = shr_dump[PAL + i * 2] | shr_dump[PAL + i * 2 + 1] << 8
        if got != want:
            bad.append((i, got, want))
    return bad
