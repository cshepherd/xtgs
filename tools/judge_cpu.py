#!/usr/bin/env python3
"""M1 judge: pack vectors, build an image with command V, boot it
headless, read the harness's results, and explain the first failure.

    judge_cpu.py --op 00 [--op 80.3] [--count N] [--skip K] [--seconds S]

Needs build/stage/{XTGS.SYSTEM#FF2000,CORE#060000,SVC#060000} (make).
Exit status 0 only if every vector passed.
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
import vectors  # noqa: E402

RES_BASE = 0x050000
REGS = vectors.REGS
FLAG_BITS = [(0, "CF"), (2, "PF"), (4, "AF"), (6, "ZF"), (7, "SF"), (8, "TF"), (9, "IF"), (10, "DF"), (11, "OF")]


def flags_str(v, mask=0xFFFF):
    return " ".join(n if v & (1 << b) else n.lower() for b, n in FLAG_BITS if mask & (1 << b))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--op", action="append", required=True)
    ap.add_argument("--count", type=int)
    ap.add_argument("--skip", type=int, default=0)
    ap.add_argument("--seconds", type=float, default=300)
    ap.add_argument("--settle", type=int, default=10)
    ap.add_argument("--workdir", default=os.path.join(ROOT, "build", "vec"))
    ap.add_argument("--list", type=int, default=15, help="how many failing vectors to name")
    args = ap.parse_args()

    meta = vectors.metadata()
    tests = vectors.collect(args.op, args.count, args.skip, meta)
    if not tests:
        sys.exit("judge_cpu: no vectors")
    data = vectors.pack(tests, meta)
    os.makedirs(args.workdir, exist_ok=True)
    vec = os.path.join(args.workdir, "VEC#060000")
    cmd = os.path.join(args.workdir, "XTGS.CMD#040000")
    with open(vec, "wb") as f:
        f.write(data)
    with open(cmd, "w") as f:
        f.write("V\r")
    stage = os.path.join(ROOT, "build", "stage")
    image = os.path.join(args.workdir, "cpu.po")
    subprocess.run([os.path.join(HERE, "make_image.sh"), image,
                    os.path.join(stage, "XTGS.SYSTEM#FF2000"), os.path.join(stage, "CORE#060000"),
                    os.path.join(stage, "SVC#060000"), vec, cmd],
                   check=True, capture_output=True)
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    n = len(tests)
    r = mamerun.run(image, waits=[(syms["mb_magic"], 0x5A5A)],
                    dumps=[("mb", syms["mb_stage"], 0x70), ("res", RES_BASE, 0x80),
                           ("bitmap", RES_BASE + 0x100, (n + 7) // 8)],
                    seconds=args.seconds, settle=args.settle)
    if r["status"] == "no-output":
        print(r.get("mame_output", ""))
        sys.exit("judge_cpu: MAME produced no result")
    mb = bytes.fromhex(r["dumps"]["mb"]["hex"])
    stage_v, magic, exit_v = struct.unpack_from("<HHH", mb, 0)
    runidx = struct.unpack_from("<H", mb, 0x1E)[0]
    if r["status"] != "hit":
        print("text screen:\n  " + "\n  ".join(l for l in r["text"] if l.strip()))
        sys.exit(f"judge_cpu: timed out at frame {r['frame']}; loader stage {stage_v}, "
                 f"vector index in progress {runidx} ({tests[runidx][1]['name'] if runidx < n else '?'})")
    res = bytes.fromhex(r["dumps"]["res"]["hex"])
    n_run, n_pass, first = struct.unpack_from("<HHH", res, 0)
    actual = struct.unpack_from("<14H", res, 8)
    ram_lo, ram_bank, ram_exp, ram_act = struct.unpack_from("<HBBB", res, 36)[:4]
    bad = struct.unpack_from("<H", res, 64)[0]
    bitmap = bytes.fromhex(r["dumps"]["bitmap"]["hex"])
    fails = [i for i in range(n) if not (bitmap[i >> 3] >> (i & 7)) & 1]
    names = ",".join(args.op)
    print(f"op {names}: {n_run} run, {n_pass} passed, {len(fails)} failed"
          f"{f', {bad} hit unimplemented opcodes' if bad else ''}; frames {r['frame']}, exit {exit_v:#x}")
    if n_run != n:
        print(f"  harness ran {n_run} of {n} vectors")
    failset = set(fails)
    per = {}
    for i, (name, _t) in enumerate(tests):
        run, failed = per.get(name, (0, 0))
        per[name] = (run + 1, failed + (i in failset))
    for name, (run, failed) in sorted(per.items()):
        print(f"  {name:6s} {run:5d} run {run - failed:5d} pass {failed:5d} fail   {'ok' if not failed else 'FAIL'}")
    for i in fails[:args.list]:
        name, t = tests[i]
        print(f"  #{i:5d} {name:6s} {t['name']:40s} bytes {' '.join(f'{b:02X}' for b in t['bytes'])}")
    if fails:
        i = first
        name, t = tests[i]
        print(f"first failure #{i} ({name}): {t['name']}")
        init = t["initial"]["regs"]
        exp = vectors.final_regs(t)
        mask = vectors.flags_mask(t, meta)
        print("  reg   initial  expected  actual")
        for k, rn in enumerate(REGS):
            a = actual[k]
            e = exp[rn]
            if rn == "flags":
                diff = (a ^ e) & mask
                mark = "  <-- " + flags_str(a ^ e, mask) if diff else ""
                print(f"  {rn:5s} {init[rn]:04X}     {e:04X}      {a:04X}{mark}")
                print(f"        expected {flags_str(e)}\n        actual   {flags_str(a)}  (mask {mask:04X})")
            else:
                mark = "  <--" if a != e else ""
                print(f"  {rn:5s} {init[rn]:04X}     {e:04X}      {a:04X}{mark}")
        print("  initial ram: " + " ".join(f"{a:05X}={v:02X}" for a, v in t["initial"]["ram"]))
        print("  expected ram: " + " ".join(f"{a:05X}={v:02X}" for a, v in t["final"]["ram"]))
        if ram_exp or ram_act:
            print(f"  first ram mismatch: {(ram_bank << 16) | ram_lo:05X} expected {ram_exp:02X} actual {ram_act:02X}")
    sys.exit(0 if not fails and n_run == n else 1)


if __name__ == "__main__":
    main()
