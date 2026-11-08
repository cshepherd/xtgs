#!/usr/bin/env python3
"""Render a dump of Super Hi-Res memory ($E1:2000-$E1:9FFF) to PNG.

Per scan line, SCB bit 7 selects 640 mode (four 2-bit pixels a byte,
each pixel position taking its colour from its own group of four
palette entries: pixel 0 from 8-11, 1 from 12-15, 2 from 0-3, 3 from
4-7) or 320 mode (two 4-bit pixels a byte). The image is 640 wide when
any line is in 640 mode (320-mode pixels are doubled), else 320.
Adapted from the Monkey Island IIGS port's tools/mame/shr.py.
"""
import struct
import zlib

SHR_BASE = 0xE12000
SHR_LEN = 0x8000
GROUP = (8, 12, 0, 4)


def iigs_rgb(word):
    r, g, b = (word >> 8) & 0xF, (word >> 4) & 0xF, word & 0xF
    return r * 17, g * 17, b * 17


def render(data):
    """data: the 32 KB at $E1:2000. Returns (png bytes, number of 640-mode lines)."""
    pixels = data[:32000]
    scbs = data[0x7D00:0x7DC8]
    pals = data[0x7E00:0x8000]
    lines640 = sum(1 for y in range(200) if scbs[y] & 0x80)
    width = 640 if lines640 else 320
    rows = []
    for y in range(200):
        scb = scbs[y]
        pal = struct.unpack_from("<16H", pals, (scb & 0x0F) * 32)
        row = bytearray([0])
        for x in range(160):
            b = pixels[y * 160 + x]
            if scb & 0x80:
                for k in range(4):
                    v = (b >> (6 - 2 * k)) & 3
                    row += bytes(iigs_rgb(pal[GROUP[k] + v]))
            else:
                for nib in (b >> 4, b & 0xF):
                    rgb = bytes(iigs_rgb(pal[nib]))
                    row += rgb if width == 320 else rgb + rgb
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(kind, body):
        c = kind + body
        return struct.pack(">I", len(body)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, 200, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    return png, lines640
