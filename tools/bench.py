#!/usr/bin/env python3
"""Guest instructions a second: assemble tests/bench/*.asm with nasm, boot
each as the B command on a stock IIGS and on a 16 MHz ZipGS, and time it
by MAME's emulated frame count between the core's start and done marks
(MB_RUNIDX = $BE57 / $D04E), so no guest timer is involved.

    bench.py [--outer N] [--only reg,mem] [--stock-only]

The instruction count is the program's own: OUTER x 65536 iterations x the
instructions an iteration (REP MOVSW counted a word an instruction).
"""
import argparse
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, "mame"))
sys.path.insert(0, HERE)
import mamerun  # noqa: E402
import symbols  # noqa: E402

PROGRAMS = {          # name: (instructions an iteration, iterations a loop)
    "reg": (4, 65536),
    "mem": (5, 65536),
    "jmp": (5, 65536),   # the taken-every-other-time JZ is one of the five
    "str": (1, 0x2000),  # one word an "instruction"
}
XT_IPS = 300_000      # a 4.77 MHz 8088 on typical code; context only


def build(name, outer, workdir):
    src = os.path.join(ROOT, "tests", "bench", f"{name}.asm")
    out = os.path.join(workdir, f"{name}.bin")
    subprocess.run(["nasm", "-f", "bin", f"-DOUTER={outer}", "-o", out, src], check=True)
    return out


def run(image, syms, zip_mode, seconds):
    r = mamerun.run(image, waits=[(syms["mb_runidx"], 0xD04E)],
                    dumps=[("mb", syms["mb_stage"], 0x80)], seconds=seconds, settle=0,
                    ready=(syms["mb_runidx"], 0xBE57), zip=zip_mode)
    if r["status"] != "hit":
        print("  text screen: " + " / ".join(l for l in r["text"] if l.strip()))
        return None
    return r["frame"] - r["ready_frame"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outer", type=int, default=4)
    ap.add_argument("--only")
    ap.add_argument("--stock-only", action="store_true")
    ap.add_argument("--seconds", type=float, default=900)
    args = ap.parse_args()
    names = args.only.split(",") if args.only else list(PROGRAMS)
    workdir = os.path.join(ROOT, "build", "bench")
    os.makedirs(workdir, exist_ok=True)
    stage = os.path.join(ROOT, "build", "stage")
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    cmd = os.path.join(workdir, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write("B\r")
    print(f"{'program':8s} {'instructions':>12s} {'stock s':>8s} {'stock IPS':>10s} {'zip s':>8s} {'zip IPS':>10s}  (XT ~{XT_IPS//1000}K IPS)")
    for name in names:
        per, iters = PROGRAMS[name]
        count = per * iters * args.outer
        binary = build(name, args.outer, workdir)
        staged = os.path.join(workdir, "BENCH#060000")
        with open(binary, "rb") as f, open(staged, "wb") as g:
            g.write(f.read())
        image = os.path.join(workdir, f"{name}.po")
        subprocess.run([os.path.join(HERE, "make_image.sh"), image,
                        os.path.join(stage, "XTGS.SYSTEM#FF2000"), os.path.join(stage, "CORE#060000"),
                        os.path.join(stage, "SVC#060000"), staged, cmd], check=True, capture_output=True)
        row = f"{name:8s} {count:12d}"
        for zip_mode in ((False,) if args.stock_only else (False, True)):
            frames = run(image, syms, zip_mode, args.seconds)
            if frames is None:
                row += f" {'timeout':>8s} {'':>10s}"
                continue
            secs = frames / 60.0
            ips = count / secs if secs else 0
            row += f" {secs:8.2f} {ips:10.0f}"
        print(row, flush=True)


if __name__ == "__main__":
    main()
