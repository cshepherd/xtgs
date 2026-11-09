#!/usr/bin/env python3
"""Profile the interpreter: run a bench program with MAME sampling PB:PC
every frame, attribute each sample to the core routine that contains it
(from build/core.lst), and print the histogram.

    profile.py [reg|mem|jmp|str] [--outer N]

Coarse (60 Hz sampling) but enough over a multi-second run to show which
routines dominate.
"""
import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, "mame"))
sys.path.insert(0, HERE)
import mamerun  # noqa: E402
import symbols  # noqa: E402


def routine_table(listing):
    """Sorted [(addr, name)] of non-local labels in the core bank."""
    syms = symbols.read(listing)
    items = sorted((a, n) for n, a in syms.items() if 0x030000 <= a < 0x040000)
    return items


def enclosing(items, addr):
    lo, hi, best = 0, len(items), None
    for a, n in items:
        if a <= addr:
            best = n
        else:
            break
    return best or "?"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bench", nargs="?", default="reg", choices=["reg", "mem", "jmp", "str"])
    ap.add_argument("--outer", type=int, default=6)
    ap.add_argument("--top", type=int, default=25)
    args = ap.parse_args()

    workdir = os.path.join(ROOT, "build", "prof")
    os.makedirs(workdir, exist_ok=True)
    src = os.path.join(ROOT, "tests", "bench", f"{args.bench}.asm")
    binary = os.path.join(workdir, "BENCH#060000")
    subprocess.run(["nasm", "-f", "bin", f"-DOUTER={args.outer}", "-o", binary, src], check=True)
    cmd = os.path.join(workdir, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write("B\r")
    stage = os.path.join(ROOT, "build", "stage")
    image = os.path.join(workdir, "bench.po")
    subprocess.run([os.path.join(HERE, "make_image.sh"), image,
                    os.path.join(stage, "XTGS.SYSTEM#FF2000"), os.path.join(stage, "CORE#060000"),
                    os.path.join(stage, "SVC#060000"), binary, cmd], check=True, capture_output=True)
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    items = routine_table(os.path.join(ROOT, "build", "core.lst"))
    r = mamerun.run(image, waits=[(syms["mb_runidx"], 0xD04E)], dumps=[], seconds=240, settle=0,
                    ready=(syms["mb_runidx"], 0xBE57), profile=True)
    prof = r.get("profile", {})
    buckets = {}
    total = 0
    for addr_hex, n in prof.items():
        addr = int(addr_hex, 16)
        total += n
        if 0x030000 <= addr < 0x040000:
            buckets[enclosing(items, addr)] = buckets.get(enclosing(items, addr), 0) + n
        else:
            buckets[f"[{addr >> 16:02X}:non-core]"] = buckets.get(f"[{addr >> 16:02X}:non-core]", 0) + n
    print(f"bench {args.bench}: {total} samples over {r['frame']} frames")
    for name, n in sorted(buckets.items(), key=lambda kv: -kv[1])[:args.top]:
        print(f"  {100*n/total:5.1f}%  {n:5d}  {name}")


if __name__ == "__main__":
    main()
