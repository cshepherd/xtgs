#!/usr/bin/env python3
"""Symbols from a Merlin32 -V listing (<name>_Output.txt).

    symbols.py LISTING [NAME...]      print NAME=0xADDR for each (all if none)

read(path) -> {label: address}. Code, data, DUM and empty lines take the
address column (bank/offset); EQU lines take their operand, which the
listing shows with the equates in it already replaced ("{{$20}*$100}+$10")
and evaluate() works out the way Merlin32 does: left to right, no
precedence. Merlin32 renames :local labels to ozunid_N; those and @
labels are skipped.
"""
import re
import sys

LINE = re.compile(r"^\s*\d+\s*\|\s*\d+\s+\S+\s+\d+\s*\|\s*(\w+)\s*\|\s*(\d\d|)\s*\|[^|]*\|\s*(\d+)\s*\|\s*([0-9A-F]{2})/([0-9A-F]{4})[^|]*\|\s?(.*)$")


TOKEN = re.compile(r"\s*(\$[0-9A-Fa-f]+|%[01]+|\d+|[A-Za-z_]\w*|[-+*/&{}])")
OPS = {"+": lambda a, b: a + b, "-": lambda a, b: a - b, "*": lambda a, b: a * b,
       "/": lambda a, b: a // b if b else 0, "&": lambda a, b: a & b}


def evaluate(text, env=None):
    """A Merlin32 expression of numbers, names from env, + - * / & and
    {groups}; None when it is anything else (a string, an unknown name)."""
    toks, at = [], 0
    text = text.strip()
    while at < len(text):
        m = TOKEN.match(text, at)
        if not m:
            return None
        toks.append(m.group(1))
        at = m.end()
    pos = 0

    def term():
        nonlocal pos
        if pos >= len(toks):
            return None
        t = toks[pos]
        pos += 1
        if t == "{":
            v = expr()
            if pos >= len(toks) or toks[pos] != "}":
                return None
            pos += 1
            return v
        if t[0] == "$":
            return int(t[1:], 16)
        if t[0] == "%":
            return int(t[1:], 2)
        if t.isdigit():
            return int(t)
        return (env or {}).get(t) if t not in OPS and t != "}" else None

    def expr():
        nonlocal pos
        v = term()
        while v is not None and pos < len(toks) and toks[pos] in OPS:
            op = toks[pos]
            pos += 1
            w = term()
            v = None if w is None else OPS[op](v, w)
        return v
    v = expr()
    return v if pos == len(toks) else None


def value(text, env=None):
    return evaluate(text, env)


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
                    v = value(parts[2], syms)
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
