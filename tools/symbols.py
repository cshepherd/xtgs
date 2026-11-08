#!/usr/bin/env python3
"""Symbols from a Merlin32 -V listing (<name>_Output.txt).

    symbols.py LISTING [NAME...]      print NAME=0xADDR for each (all if none)

read(path) -> {label: address}. Code, data and empty lines take the
address column (bank/offset); EQU lines take their operand when it is a
plain number. Merlin32 renames :local labels to ozunid_N; those and @
labels are skipped.
"""
import re
import sys

LINE = re.compile(r"^\s*\d+\s*\|\s*\d+\s+\S+\s+\d+\s*\|\s*(\w+)\s*\|\s*(\d\d|)\s*\|[^|]*\|\s*(\d+)\s*\|\s*([0-9A-F]{2})/([0-9A-F]{4})[^|]*\|\s?(.*)$")


def value(text):
    text = text.strip()
    if text.startswith("$"):
        return int(text[1:], 16)
    if text.startswith("%"):
        return int(text[1:], 2)
    if text.isdigit():
        return int(text)
    return None


def read(path):
    syms = {}
    with open(path, errors="replace") as f:
        for line in f:
            m = LINE.match(line)
            if not m:
                continue
            kind, _mx, _size, bank, off, src = m.groups()
            if not src or src[0] in " \t;*":
                continue
            parts = src.split()
            label = parts[0]
            if label.startswith(("@", ":", "ozunid")):
                continue
            if kind == "Equivalence":
                if len(parts) >= 3:
                    v = value(parts[2])
                    if v is not None:
                        syms[label] = v
                continue
            syms[label] = (int(bank, 16) << 16) | int(off, 16)
    return syms


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    syms = read(sys.argv[1])
    names = sys.argv[2:] or sorted(syms)
    for n in names:
        if n in syms:
            print(f"{n}=0x{syms[n]:06X}")
        else:
            print(f"{n}=?", file=sys.stderr)


if __name__ == "__main__":
    main()
