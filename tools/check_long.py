#!/usr/bin/env python3
"""Merlin32 assembles `ldx >addr` as plain absolute: LDX LDY STX STY CPX CPY
have no long addressing mode, and the bank byte is silently dropped. This
flags every such line in the sources (exit 1). Found the hard way in
src/svc/keyboard.s during M2.

It also flags an address operand that adds before it multiplies
(`sta htab+3*8`): Merlin32 has no precedence, so that is (htab+3)*8, cut to
16 bits, somewhere else in the bank. Write the product first (`3*8+htab`).
Immediates and `err` lines are left alone: several are written left to
right on purpose. Found when the stray store landed on code (files.s, EGA).

    check_long.py FILE...
"""
import re
import sys

PREC = re.compile(r"^\S*\s+(?!err\b|ERR\b)\w+\s+[<>|\[(]*[A-Za-z_:][\w:]*\s*[+-][^*/;,\s]*[*/]")
BAD = re.compile(r"^\s+(ldx|ldy|stx|sty|cpx|cpy|inc|dec|asl|lsr|rol|ror|bit|stz|trb|tsb)\s+>", re.I)


def main(paths):
    bad = 0
    for p in paths:
        with open(p, errors="replace") as f:
            for n, line in enumerate(f, 1):
                if BAD.match(line):
                    print(f"{p}:{n}: {line.strip()}  <- no long addressing mode; use lda >addr / tax")
                    bad += 1
                elif not line.startswith("*") and PREC.match(line):
                    print(f"{p}:{n}: {line.strip()}  <- left to right: put the product first")
                    bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
