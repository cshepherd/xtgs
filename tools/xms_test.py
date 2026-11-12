#!/usr/bin/env python3
"""xms_test.py [XTGS.CMD line...]: the XMS driver by its calls (make test-xms;
docs/xms.md).

FreeDOS boots from a copy of the folder third_party/freedos/fd/SHARED
(command S: the driver's memory is the banks a disk image would have), whose
AUTOEXEC.BAT runs XMSTEST (tests/demo/xmstest.asm: blocks allocated, moved to and from,
resized, locked, freed, and the errors) and its line on the screen judged.
An argument is one more line of XTGS.CMD: after XMS=OFF the program must
find no driver. --show prints the screen.

Work files in build/xms/. One boot, about 170 emulated seconds.
"""
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "mame"))
import mamerun  # noqa: E402
import symbols  # noqa: E402

FD = os.path.join(ROOT, "third_party", "freedos", "fd", "SHARED")
END = 9000


def main():
    show = "--show" in sys.argv
    lines = [a for a in sys.argv[1:] if a != "--show"]
    off = any(a.upper().replace(" ", "") == "XMS=OFF" for a in lines)
    work = os.path.join(ROOT, "build", "xms")
    os.makedirs(work, exist_ok=True)
    cmd = os.path.join(work, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write("S\rC=SHARED\r" + "".join(a + "\r" for a in lines))
    folder = os.path.join(work, "SHARED")
    shutil.rmtree(folder, ignore_errors=True)
    shutil.copytree(FD, folder)
    with open(os.path.join(folder, "AUTOEXEC.BAT#040000"), "w", newline="\r\n") as f:
        f.write("@ECHO OFF\nXMSTEST\n")
    stage = os.path.join(ROOT, "build", "stage")
    po = os.path.join(work, "xms.po")
    subprocess.run([os.path.join(HERE, "make_image.sh"), po, os.path.join(stage, "XTGS.SYSTEM#FF2000"),
                    os.path.join(stage, "CORE#060000"), os.path.join(stage, "SVC#060000"), cmd, folder],
                   check=True, capture_output=True, env=dict(os.environ, VOLSIZE="4096KB"))
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    r = mamerun.run(po, waits=[(syms["mb_magic"], 0x5A5A)], dumps=[("fb", 0x2B8000, 4000)],
                    seconds=END / 60, settle=5)
    if r["status"] == "no-output":
        print(r.get("mame_output", ""))
        sys.exit("xms_test: MAME produced no result")
    fb = bytes.fromhex(r["dumps"]["fb"]["hex"])
    rows = [bytes(fb[y * 160 + x * 2] for x in range(80)).decode("cp437").rstrip("\0 ") for y in range(25)]
    if show:
        print("\n".join(rows))
    said = [x for x in rows if x.startswith("XMS ") or x.startswith("no XMS")]
    if off:
        if said != ["no XMS driver"]:
            sys.exit(f"FAIL xms: with XMS=OFF the program said {said}, not that there is no driver")
        print("PASS xms: XMS=OFF, no driver answers INT 2Fh AX=4300h")
        return
    m = re.match(r"XMS PASS free=(\d+)$", said[0]) if len(said) == 1 else None
    if not m:
        sys.exit(f"FAIL xms: the program said {said}\n" + "\n".join(rows))
    free = int(m.group(1))
    # (FreeCOM is in a block of its own while the program runs)
    if not 1200 <= free <= 1472:
        sys.exit(f"FAIL xms: {free} KB free, not most of the 1472 the region holds")
    print(f"PASS xms: blocks allocated, moved to and from, resized, locked and freed, the errors refused; "
          f"{free} KB free with FreeCOM swapped out")


main()
