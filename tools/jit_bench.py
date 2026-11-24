#!/usr/bin/env python3
"""M6 revisited: the bench loops by every engine, timed the way tools/bench.py
does (MAME's frames between MB_RUNIDX = $BE57 and $D04E), their registers
compared with the interpreter's, and the translator's own counts.

    jit_bench.py [--outer N] [--only reg,jmp] [--engines B,J,U,S,L,G,C]
                 [--stock-only | --zip-only] [--seconds S] [--dump]

Engines: B the interpreter (command B), J the hand translation (command J,
always JIT_OUTER iterations), and the runtime translator's modes (command
K x, src/core/jit2.s):
    U  unlinked: every block ends in the dispatcher
    S  a block's branch to its own entry stays native (the first M6's link)
    L  every direct edge linked
    G  the same with the guard: a count on each backward edge
    C  U translating again at every dispatch: (C - U) / dispatches is what
       a translation costs
K alone is whatever the build does with no letter.
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

JIT_OUTER = 4             # src/core/jit.s
PROGRAMS = {              # name: (instructions an iteration, iterations, J's letter)
    "reg": (4, 65536, "R"),
    "mem": (5, 65536, "M"),
    "jmp": (5, 65536, "J"),
    "jlink": (0, 0, None),   # tests/bench/jlink.asm: the links' test, judged by its registers
}
CLOCK_HZ = {False: 2.8636e6, True: 16e6}   # cycles an instruction: what MAME gives the hand-translated reg loop (34 cycles)
STATS = ("dispatches", "translations", "links", "bytes", "resets")


def make_image(workdir, stage, cmd_str, tag, bench_bin):
    cmd = os.path.join(workdir, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write(f"{cmd_str}\r")
    staged = os.path.join(workdir, "BENCH#060000")
    with open(bench_bin, "rb") as f, open(staged, "wb") as g:
        g.write(f.read())
    image = os.path.join(workdir, f"{tag}.po")
    subprocess.run([os.path.join(HERE, "make_image.sh"), image,
                    os.path.join(stage, "XTGS.SYSTEM#FF2000"), os.path.join(stage, "CORE#060000"),
                    os.path.join(stage, "SVC#060000"), staged, cmd], check=True, capture_output=True)
    return image


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outer", type=int, default=7)   # odd: jmp's AX is then not 0
    ap.add_argument("--only")
    ap.add_argument("--engines", default="B,J,U,S,L,G")
    ap.add_argument("--stock-only", action="store_true")
    ap.add_argument("--zip-only", action="store_true")
    ap.add_argument("--seconds", type=float, default=1200)
    ap.add_argument("--dump", action="store_true", help="print the code cache's first bytes after each K run")
    args = ap.parse_args()
    names = args.only.split(",") if args.only else ["reg", "mem", "jmp"]
    engines = args.engines.split(",")
    workdir = os.path.join(ROOT, "build", "jitbench")
    os.makedirs(workdir, exist_ok=True)
    stage = os.path.join(ROOT, "build", "stage")
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    core = symbols.read(os.path.join(ROOT, "build", "core.lst"))
    modes = (True,) if args.zip_only else (False,) if args.stock_only else (False, True)
    dumps = [("regs", 0x001000, 0x10)]
    if "jit_stats" in core:
        dumps.append(("stats", core["jit_stats"], 4 * len(STATS)))
    if args.dump:
        dumps.append(("cache", 0x060010, 0xA0))

    print(f"OUTER={args.outer} (J: {JIT_OUTER}); IPS = guest instructions / emulated seconds")
    print(f"{'program':7s} {'clock':6s} {'engine':6s} {'frames':>7s} {'IPS':>9s} {'x interp':>8s} {'cyc/ins':>7s}  regs  counts")
    for name in names:
        per, iters, jarg = PROGRAMS[name]
        binary = os.path.join(workdir, f"{name}.bin")
        subprocess.run(["nasm", "-f", "bin", f"-DOUTER={args.outer}", "-o", binary,
                        os.path.join(ROOT, "tests", "bench", f"{name}.asm")], check=True)
        for zip_mode in modes:
            base_ips = base_regs = None
            for e in engines:
                if e == "J" and jarg is None:
                    continue
                cmd = "B" if e == "B" else f"J {jarg}" if e == "J" else "K" if e == "K" else f"K {e}"
                outer = JIT_OUTER if e == "J" else args.outer
                image = make_image(workdir, stage, cmd, "bench", binary)   # one image: each is 8 MB
                r = mamerun.run(image, waits=[(syms["mb_runidx"], 0xD04E)], dumps=dumps,
                                seconds=args.seconds, settle=0,
                                ready=(syms["mb_runidx"], 0xBE57), zip=zip_mode)
                clock = "zip16" if zip_mode else "stock"
                if r["status"] != "hit":
                    print(f"{name:7s} {clock:6s} {e:6s} timeout", flush=True)
                    continue
                frames = r["frame"] - r["ready_frame"]
                ips = per * iters * outer / (frames / 60.0) if frames and per else 0
                regs = bytes.fromhex(r["dumps"]["regs"]["hex"])
                regs = regs[:8] + regs[10:16]          # not SP
                if e == "B":
                    base_ips, base_regs, base_frames = ips, regs, frames
                ok = "  - " if e == "J" or base_regs is None else " ok " if regs == base_regs else "DIFF"
                rel = (f"{ips / base_ips:7.2f}x" if base_ips else
                       f"{base_frames / frames:7.2f}x" if base_regs is not None and frames else f"{'':8s}")
                counts = ""
                if "stats" in r["dumps"] and e not in "BJ":
                    v = struct.unpack("<%dI" % len(STATS), bytes.fromhex(r["dumps"]["stats"]["hex"]))
                    counts = " ".join(f"{k}={x}" for k, x in zip(STATS, v))
                print(f"{name:7s} {clock:6s} {e:6s} {frames:7d} {ips:9.0f} {rel} {CLOCK_HZ[zip_mode] / ips if ips else 0:7.1f}  {ok}  {counts}",
                      flush=True)
                if args.dump and e not in "BJ":
                    raw = bytes.fromhex(r["dumps"]["cache"]["hex"])
                    for o in range(0, len(raw), 16):
                        print("        %04X  %s" % (0x10 + o, raw[o:o + 16].hex(" ")))
                if ok == "DIFF":
                    print("        interp " + base_regs.hex(" ") + "\n        this   " + regs.hex(" "))


if __name__ == "__main__":
    main()
