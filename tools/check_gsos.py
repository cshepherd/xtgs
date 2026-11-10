#!/usr/bin/env python3
"""Launch XT/GS from GS/OS in headless MAME and judge it (make test-gsos).

The volume (tools/gsos_image.sh) is a System 6 disk whose startup program
quits to /VOL/XTGS/XTGS.SYSTEM, as the Finder would launch it. GS/OS and
its tool patches then own memory XT/GS takes on a bare ProDOS 8 boot, so
the loader's regions land where the Memory Manager has room, and nothing
here can know those banks beforehand. Two boots:

  1. XTGS_LAYOUT=probe (tools/layout.py): no address translation; wait for
     the loader to finish, press a key so it QUITs back to GS/OS, and wait
     for GS/OS to launch it a second time. Checks: OS_BOOT says GS/OS, both
     runs end at stage 10 with the same banks (so the first released what
     it claimed), and at least one region is away from its assembled bank
     (otherwise the run proves nothing about relocation).
  2. tools/judge_m0.py with XTGS_LAYOUT spelling the banks run 1 reported:
     the memory probe and the 80x25 test frame, read from where they are.
"""
import argparse
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "mame"))
import layout  # noqa: E402
import mamerun  # noqa: E402
import symbols  # noqa: E402

# GS/OS 6.0.1 does not start in MAME from the Apple II SCSI Card (the
# ProDOS 8 images' card); with a CFFA 2.0 it boots.
CARD = "cffa2"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True)
    ap.add_argument("--listing", required=True, help="XTGS.SYSTEM listing, for the mailbox labels")
    ap.add_argument("--png")
    ap.add_argument("--seconds", type=float, default=180)
    args = ap.parse_args()

    syms = symbols.read(args.listing)
    magic, stage = syms["mb_magic"], syms["mb_stage"]
    os.environ["XTGS_LAYOUT"] = "probe"
    r = mamerun.run(args.image, waits=[(magic, 0x5A5A)], dumps=[("mb", stage, 0x10)],
                    seconds=args.seconds, settle=30, card=CARD, occurrence=2,
                    triggers={"first": (magic, 0x5A5A)},
                    inputs=[{"at": 90, "key": " ", "after": "first"}],
                    traces=[("magic", magic), ("stage", stage),
                            *((f"bank{i}", layout.mailbox()["MB_LAYOUT"] + 2 * i)
                              for i in range(len(layout.regions())))])
    if r["status"] == "no-output":
        print(r.get("mame_output", ""))
        sys.exit("check_gsos: MAME produced no result")
    tr = r["traces"]
    done = [f for f, v in tr["magic"] if v == 0x5A5A]
    # the stage at each finish: the last change at or before that frame
    stages = [[v for f, v in tr["stage"] if f <= d][-1] for d in done]

    def banks_at(frame):
        return [([v for f, v in tr[f"bank{i}"] if f <= frame] or [0])[-1]
                for i in range(len(layout.regions()))]
    names = [n for n, _ in sorted(layout.regions().items(), key=lambda kv: kv[1][0])]
    asm = [b for _, (_, b) in sorted(layout.regions().items(), key=lambda kv: kv[1][0])]
    osboot = struct.unpack_from("<H", bytes.fromhex(r["dumps"]["mb"]["hex"]), 8)[0]

    def show(words):
        return " ".join(f"{n}=${w:02X}" for n, w in zip(names, words) if w)
    print(f"GS/OS launch: status {r['status']}, {len(done)} runs finished "
          f"(frames {', '.join(map(str, done))}), OS_BOOT {osboot:#x}")
    problems = []
    if len(done) < 2:
        problems.append(f"wanted two runs (launch, QUIT to GS/OS, relaunch); stage trace {tr['stage'][-8:]}")
    if any(s != 10 for s in stages):
        problems.append(f"loader stage at the end of each run: {[hex(s) for s in stages]} (want 0xa)")
    if osboot == 0:
        problems.append("OS_BOOT is 0: this was a bare ProDOS 8 boot, not a GS/OS launch")
    runs = [banks_at(d) for d in done]
    for i, b in enumerate(runs):
        print(f"  run {i + 1}: {show(b)}")
    if len(runs) == 2 and runs[0] != runs[1]:
        problems.append("the second run got different banks: the first did not release its memory?")
    if runs and all(w in (0, a) for w, a in zip(runs[0], asm)):
        problems.append("every region got its assembled bank: nothing was relocated")
    if problems or not runs:
        print("GSOS: FAIL\n  " + "\n  ".join(problems))
        sys.exit(1)

    env = dict(os.environ, XTGS_LAYOUT=layout.spell(runs[0]))
    print(f"judging the probe with XTGS_LAYOUT={env['XTGS_LAYOUT']}")
    cmd = [sys.executable, "-I", os.path.join(HERE, "judge_m0.py"), "--image", args.image,
           "--listing", args.listing, "--card", CARD, "--seconds", str(args.seconds)]
    if args.png:
        cmd += ["--png", args.png]
    sys.stdout.flush()
    rc = subprocess.run(cmd, env=env).returncode
    print("GSOS: PASS" if rc == 0 else "GSOS: FAIL (the M0 judge)")
    sys.exit(rc)


if __name__ == "__main__":
    main()
