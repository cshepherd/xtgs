#!/usr/bin/env python3
"""Merlin32 assembles `ldx >addr` as plain absolute: LDX LDY STX STY CPX CPY
have no long addressing mode, and the bank byte is silently dropped. This
flags every such line in the sources (exit 1). Found the hard way in
src/svc/keyboard.s during M2.

    check_long.py FILE...
"""
import re
import sys

BAD = re.compile(r"^\s+(ldx|ldy|stx|sty|cpx|cpy|inc|dec|asl|lsr|rol|ror|bit|stz|trb|tsb)\s+>", re.I)


def main(paths):
    bad = 0
    for p in paths:
        with open(p, errors="replace") as f:
            for n, line in enumerate(f, 1):
                if BAD.match(line):
                    print(f"{p}:{n}: {line.strip()}  <- no long addressing mode; use lda >addr / tax")
                    bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
