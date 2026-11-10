#!/usr/bin/env python3
"""Does the SHR screen show the text buffer? Renders the 80x25 buffer
the way src/svc/video.s render_cell does (same generated font and
expand table, same level masks) and compares it with the SHR pixels.

    bad = textshr.mismatches(txt, shr_dump)   # [(row, col), ...]

The services bank draws only the cells that differ from its shadow of
the screen (render_row), so a stale shadow shows up here as a cell whose
pixels are an older character's. One cell may carry the cursor's
underline (font rows 6-7 all set).
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, "src", "svc", "gen")
FG = [0x0000] + [0xAAAA] * 7 + [0x5555] + [0xFFFF] * 7      # video.s fg_mask
BG = [0x0000] + [0x5555] * 7                                # video.s bg_mask
SCB = 0x7D00                                                # in a dump from $E1:2000


def _table(path, label, directive):
    """The bytes (hex) or words (dw) that follow `label` in a generated source."""
    out, on = [], False
    with open(path) as f:
        for line in f:
            if not on:
                on = line.split("*")[0].strip() == label
                continue
            m = re.match(r"\s+(hex|dw)\s+(\S+)", line)
            if not m or m.group(1) != directive:
                break
            if directive == "hex":
                out.extend(bytes.fromhex(m.group(2)))
            else:
                out.extend(int(w.lstrip("$"), 16) for w in m.group(2).split(","))
    return out


def expected(txt):
    """The 32000 pixel bytes render_cell would draw for this text buffer."""
    font = _table(os.path.join(GEN, "font.s"), "font", "hex")
    exp = _table(os.path.join(GEN, "tables.s"), "exp_tab", "dw")
    pix = bytearray(32000)
    for row in range(25):
        for col in range(80):
            ch, attr = txt[row * 160 + col * 2], txt[row * 160 + col * 2 + 1]
            fg, bg = FG[attr & 15], BG[attr >> 4 & 7]
            for r in range(8):
                e = exp[font[ch * 8 + r]]
                w = (e & fg) | (~e & bg & 0xFFFF)
                o = row * 1280 + r * 160 + col * 2
                pix[o], pix[o + 1] = w & 0xFF, w >> 8
    return pix


def is_text(shr_dump):
    """Every scan line in 640 mode (a graphics mode 4/5 sets them to 320)."""
    return all(b & 0x80 for b in shr_dump[SCB:SCB + 200])


def mismatches(txt, shr_dump, cursors=None):
    """cursors: a list that gets the (row, col) of each cell drawn with the
    cursor's underline over the right character."""
    want, bad, cursor = expected(txt), [], []
    for row in range(25):
        for col in range(80):
            rows = []
            for r in range(8):
                o = row * 1280 + r * 160 + col * 2
                rows.append(shr_dump[o:o + 2] == want[o:o + 2])
            if all(rows):
                continue
            o = row * 1280 + col * 2
            under = all(shr_dump[o + r * 160:o + r * 160 + 2] == b"\xff\xff" for r in (6, 7))
            if all(rows[:6]) and under:
                cursor.append((row, col))
            else:
                bad.append((row, col))
    if cursors is not None:
        cursors.extend(cursor)
    return bad + cursor[1:]                                 # one cursor at most
