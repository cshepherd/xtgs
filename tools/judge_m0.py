#!/usr/bin/env python3
"""M0 judge: boot the image headless, wait for the loader's MB_MAGIC,
then check the memory probe and shutdown fields and render the SHR
screen and the guest text buffer.

    judge_m0.py --image build/xtgs.po --listing build/xtgs.lst --png build/m0.png

Exit status 0 only if the loader reached stage 10 with exit code 0, no
probe mismatches, no shutdown errors, and the text buffer carries the
test frame's title.
"""
import argparse
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "mame"))
sys.path.insert(0, HERE)
import mamerun  # noqa: E402
import shr  # noqa: E402
import symbols  # noqa: E402

TXT_BASE = 0x2B8000


def text_rows(buf):
    rows = []
    for r in range(25):
        chars = bytes(buf[r * 160 + c * 2] for c in range(80))
        rows.append(chars.decode("cp437").rstrip())
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True)
    ap.add_argument("--listing", required=True, help="XTGS.SYSTEM listing, for the mailbox labels")
    ap.add_argument("--png")
    ap.add_argument("--seconds", type=float, default=120)
    ap.add_argument("--card", default="scsi", help="slot 7 disk card (MAME's name; cffa2 for a GS/OS volume)")
    args = ap.parse_args()

    syms = symbols.read(args.listing)
    mb = syms["mb_stage"]
    r = mamerun.run(args.image, waits=[(syms["mb_magic"], 0x5A5A)],
                    dumps=[("mb", mb, 0x70), ("shr", shr.SHR_BASE, shr.SHR_LEN),
                           ("txt", TXT_BASE, 4000)],
                    seconds=args.seconds, settle=30, card=args.card)
    if r["status"] == "no-output":
        print(r.get("mame_output", ""))
        sys.exit("judge_m0: MAME produced no result")
    screen = [l for l in r["text"] if l.strip()]
    print("text screen:\n  " + "\n  ".join(screen))
    d = bytes.fromhex(r["dumps"]["mb"]["hex"])
    f = {}
    (f["stage"], f["magic"], f["exit"], f["err"], f["osboot"], f["master"], f["mmid"],
     f["downerr"], f["done"], f["filelen"], f["sp"], f["perrs"], f["pfirst"], f["runidx"]) = \
        struct.unpack_from("<HHHHHHHHHIHHIH", d, 0)
    cmd = d[0x20:0x40]
    f["cmd"] = cmd[1:1 + cmd[0]].decode("ascii", "replace")
    f["dbg_owner"], f["dbg_addr"], f["dbg_size"] = struct.unpack_from("<HII", d, 0x40)
    for k, v in f.items():
        print(f"  {k:9s} {v:#x}" if isinstance(v, int) else f"  {k:9s} {v}")
    if r["status"] != "hit":
        sys.exit(f"judge_m0: MB_MAGIC never set (status {r['status']}, frame {r['frame']})")

    txt = bytes.fromhex(r["dumps"]["txt"]["hex"])
    rows = text_rows(txt)
    print("guest text buffer (B800):")
    for i, row in enumerate(rows):
        if row:
            print(f"  {i:2d}|{row}")
    if args.png:
        png, lines640 = shr.render(bytes.fromhex(r["dumps"]["shr"]["hex"]))
        with open(args.png, "wb") as fh:
            fh.write(png)
        print(f"SHR screen -> {args.png} ({lines640} lines in 640 mode)")

    problems = []
    if f["stage"] != 10:
        problems.append(f"loader stopped at stage {f['stage']:#x} (error {f['err']:#x})")
    if f["exit"] != 0:
        problems.append(f"core exit {f['exit']:#x}")
    if f["perrs"] != 0:
        problems.append(f"{f['perrs']} probe mismatches, first at {f['pfirst']:#08x}")
    if f["done"] != 0xA5A5:
        problems.append("core never returned")
    if f["downerr"] != 0:
        problems.append(f"shutdown error {f['downerr']:#x}")
    if f["mmid"] != f["master"] or f["master"] == 0:
        problems.append(f"MMStartUp ID {f['mmid']:#x} != master {f['master']:#x}")
    if not rows[0].startswith("XT/GS M0"):
        problems.append("test frame title missing from the text buffer")
    print(f"frames: {r['frame']}")
    if problems:
        print("M0: FAIL\n  " + "\n  ".join(problems))
        sys.exit(1)
    print("M0: PASS")


if __name__ == "__main__":
    main()
