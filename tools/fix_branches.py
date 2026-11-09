#!/usr/bin/env python3
"""Rewrite conditional branches to far-away local labels as an inverted
branch over a JMP, so Merlin32's "Bad Jump ... Too long" never appears.
A target is far when the source distance to the label's definition, within
the same routine (between global labels), exceeds --lines (default 40,
about 100 bytes of code).

    fix_branches.py FILE... [--lines N]
"""
import re
import sys

INV = {"bcs": "bcc", "bcc": "bcs", "beq": "bne", "bne": "beq", "bmi": "bpl", "bpl": "bmi", "bvs": "bvc", "bvc": "bvs"}
BR = re.compile(r"^ (b(?:cs|cc|eq|ne|mi|pl|vs|vc|ra))\s+(:\w+)\s*(;.*)?$")
LBL = re.compile(r"^(:\w+)\b")
GLB = re.compile(r"^[A-Za-z_]\w*")


def fix(path, maxlines):
    lines = open(path).read().split("\n")
    # routine boundaries and local label positions
    out, changed, n = [], 0, 0
    i = 0
    while i < len(lines):
        # find the routine extent
        if GLB.match(lines[i]) and not lines[i].startswith(("*", " ")):
            j = i + 1
            while j < len(lines) and not (GLB.match(lines[j]) and not lines[j].startswith(("*", " "))):
                j += 1
            block = lines[i:j]
            labels = {}
            for k, l in enumerate(block):
                m = LBL.match(l)
                if m:
                    labels[m.group(1)] = k
            newblock = []
            for k, l in enumerate(block):
                m = BR.match(l)
                if m and m.group(2) in labels and abs(labels[m.group(2)] - k) > maxlines:
                    op, tgt, cmt = m.group(1), m.group(2), m.group(3) or ""
                    n += 1
                    if op == "bra":
                        newblock.append(f" jmp {tgt} {cmt}".rstrip())
                    else:
                        newblock.append(f" {INV[op]} :lj{n}")
                        newblock.append(f" jmp {tgt} {cmt}".rstrip())
                        newblock.append(f":lj{n}")
                    changed += 1
                else:
                    newblock.append(l)
            out += newblock
            i = j
        else:
            out.append(lines[i])
            i += 1
    if changed:
        open(path, "w").write("\n".join(out))
    return changed


def main():
    args = sys.argv[1:]
    maxlines = 40
    if "--lines" in args:
        k = args.index("--lines")
        maxlines = int(args[k + 1])
        del args[k:k + 2]
    for p in args:
        print(f"{p}: {fix(p, maxlines)} branches rewritten")


if __name__ == "__main__":
    main()
