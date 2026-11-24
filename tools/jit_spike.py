#!/usr/bin/env python3
"""M6 JIT spike: time the hand-translated native loops (the J command) against
the interpreter running the same reg/mem/jmp benchmarks (the B command), on a
stock IIGS and a 16 MHz ZipGS, and report the per-program speedup.

    jit_spike.py [--seconds S] [--stock-only]

Both engines do the identical logical workload per program (OUTER must match
JIT_OUTER in src/core/jit.s). Timing is MAME's emulated frame count between
MB_RUNIDX = $BE57 and $D04E, the same method as tools/bench.py.
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

OUTER = 4                 # must equal JIT_OUTER in src/core/jit.s
PROGRAMS = {              # name: (instructions an iteration, iterations, J arg)
    "reg": (4, 65536, "R"),
    "mem": (5, 65536, "M"),
    "jmp": (5, 65536, "J"),
}
XT_IPS = 300_000


def make_image(workdir, stage, cmd_str, tag, bench_bin=None):
    cmd = os.path.join(workdir, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write(f"{cmd_str}\r")
    files = [os.path.join(stage, "XTGS.SYSTEM#FF2000"),
             os.path.join(stage, "CORE#060000"), os.path.join(stage, "SVC#060000")]
    if bench_bin is not None:
        staged = os.path.join(workdir, "BENCH#060000")
        with open(bench_bin, "rb") as f, open(staged, "wb") as g:
            g.write(f.read())
        files.append(staged)
    files.append(cmd)
    image = os.path.join(workdir, f"{tag}.po")
    subprocess.run([os.path.join(HERE, "make_image.sh"), image, *files],
                   check=True, capture_output=True)
    return image


def time_run(image, syms, zip_mode, seconds):
    r = mamerun.run(image, waits=[(syms["mb_runidx"], 0xD04E)],
                    dumps=[("mb", syms["mb_stage"], 0x80)], seconds=seconds, settle=0,
                    ready=(syms["mb_runidx"], 0xBE57), zip=zip_mode)
    return None if r["status"] != "hit" else r["frame"] - r["ready_frame"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=float, default=900)
    ap.add_argument("--stock-only", action="store_true")
    args = ap.parse_args()

    workdir = os.path.join(ROOT, "build", "jitbench")
    os.makedirs(workdir, exist_ok=True)
    stage = os.path.join(ROOT, "build", "stage")
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    modes = (False,) if args.stock_only else (False, True)

    print(f"OUTER={OUTER}; IPS = guest instructions / emulated seconds\n")
    hdr = f"{'program':8s} {'clock':10s} {'interp IPS':>12s} {'JIT IPS':>12s} {'speedup':>9s}"
    print(hdr)
    print("-" * len(hdr))
    for name, (per, iters, arg) in PROGRAMS.items():
        count = per * iters * OUTER
        reg_bin = os.path.join(workdir, f"{name}.bin")
        subprocess.run(["nasm", "-f", "bin", f"-DOUTER={OUTER}", "-o", reg_bin,
                        os.path.join(ROOT, "tests", "bench", f"{name}.asm")], check=True)
        interp_img = make_image(workdir, stage, "B", f"{name}_b", reg_bin)
        jit_img = make_image(workdir, stage, f"J {arg}", f"{name}_j")
        for zip_mode in modes:
            clock = "16MHz Zip" if zip_mode else "stock"
            fi = time_run(interp_img, syms, zip_mode, args.seconds)
            fj = time_run(jit_img, syms, zip_mode, args.seconds)
            ii = count / (fi / 60.0) if fi else None
            ij = count / (fj / 60.0) if fj else None
            ii_s = f"{ii:12.0f}" if ii else f"{'timeout':>12s}"
            ij_s = f"{ij:12.0f}" if ij else f"{'timeout':>12s}"
            sp = f"{ij / ii:7.1f}x" if (ii and ij) else f"{'-':>8s}"
            print(f"{name:8s} {clock:10s} {ii_s} {ij_s} {sp:>9s}", flush=True)
        print()
    print(f"(a 4.77 MHz 8088 does ~{XT_IPS//1000}K IPS on typical code, for context)")


if __name__ == "__main__":
    main()
