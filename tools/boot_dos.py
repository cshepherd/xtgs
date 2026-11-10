#!/usr/bin/env python3
"""Boot a raw disk image in Mode B and report how far it gets.

    boot_dos.py IMAGE [--seconds S] [--trace]

Stages the image as DISK on a ProDOS volume with command D, boots headless,
and dumps the guest CPU state, the INT 13h call count, the text screen and a
SHR screenshot. With --trace it also samples guest CS:IP over time.
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
import shr  # noqa: E402
import symbols  # noqa: E402

RES = 0x050000
TXT = 0x2B8000


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--seconds", type=float, default=180)
    ap.add_argument("--trace", action="store_true")
    args = ap.parse_args()

    work = os.path.join(ROOT, "build", "boot")
    os.makedirs(work, exist_ok=True)
    disk = os.path.join(work, "DISK#060000")
    with open(args.image, "rb") as f, open(disk, "wb") as g:
        g.write(f.read())
    cmd = os.path.join(work, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write("D\r")
    stage = os.path.join(ROOT, "build", "stage")
    po = os.path.join(work, "boot.po")
    subprocess.run([os.path.join(HERE, "make_image.sh"), po,
                    os.path.join(stage, "XTGS.SYSTEM#FF2000"), os.path.join(stage, "CORE#060000"),
                    os.path.join(stage, "SVC#060000"), disk, cmd],
                   check=True, capture_output=True)
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    traces = []
    if args.trace:
        traces = [("int13", RES + 0x80C), ("ip", 0x001018), ("cs", 0x001012),
                  ("ticks", 0x20046C)]
    r = mamerun.run(po, waits=[(syms["mb_magic"], 0x5A5A)],
                    dumps=[("gregs", 0x001000, 0x20), ("mb", syms["mb_stage"], 0x80),
                           ("res", RES + 0x800, 0x20), ("txt", TXT, 4000), ("shr", shr.SHR_BASE, shr.SHR_LEN)],
                    seconds=args.seconds, settle=5, traces=traces)
    g = bytes.fromhex(r["dumps"]["gregs"]["hex"])
    names = ["AX", "CX", "DX", "BX", "SP", "BP", "SI", "DI", "ES", "CS", "SS", "DS", "IP", "FL"]
    gr = {names[i]: struct.unpack_from("<H", g, i * 2)[0] for i in range(14)}
    res = bytes.fromhex(r["dumps"]["res"]["hex"])
    disklen, int13n, boottrc = struct.unpack_from("<IHH", res, 8)
    print(f"status {r['status']} frame {r['frame']}")
    print("guest:", " ".join(f"{k}={v:04X}" for k, v in gr.items()))
    print(f"INT 13h calls: {int13n}   boot trace: {boottrc:#06x}   image bytes loaded: {disklen}")
    txt = bytes.fromhex(r["dumps"]["txt"]["hex"])
    rows = [bytes(txt[row * 160 + c * 2] for c in range(80)).decode("cp437").rstrip() for row in range(25)]
    print("text screen:")
    for i, row in enumerate(rows):
        if row.strip():
            print(f"  {i:2d}|{row}")
    png, _ = shr.render(bytes.fromhex(r["dumps"]["shr"]["hex"]))
    with open(os.path.join(work, "boot.png"), "wb") as f:
        f.write(png)
    print(f"screenshot -> {os.path.join(work, 'boot.png')}")
    if args.trace:
        for k, v in r.get("traces", {}).items():
            print(f"  trace {k}: {[(fr, hex(val)) for fr, val in v][:16]}")


if __name__ == "__main__":
    main()
