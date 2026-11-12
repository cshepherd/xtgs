#!/usr/bin/env python3
"""mouse_test.py: the IIGS's mouse as the PC's, by INT 33h (make test-mouse;
docs/mouse.md).

FreeDOS boots from a floppy whose AUTOEXEC.BAT runs MOUSETST L
(tests/demo/mousetst.asm). The harness then moves MAME's mouse and presses
its button, and MOUSETST starts a line at each change in what function
03h says, with what its handler (function 0Ch) was called with since. The
lines on the screen are held to what was done.

Work files in build/mouse/. One boot, about 150 emulated seconds.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, "mame"))
sys.path.insert(0, HERE)
import mamerun  # noqa: E402
import symbols  # noqa: E402

FD = os.path.join(ROOT, "third_party", "freedos", "fd")
FIRST = 7600
LINE = re.compile(r"mouse x=(\d+) y=(\d+) b=(\d+) handler ev=(\d+) n=(\d+) x=(\d+) y=(\d+)")
# what the harness does: MAME's mouse fields moved (a step a frame) and the button
INPUTS = [{"at": FIRST, "move": [1, 0], "frames": 10},            # right
          {"at": FIRST + 150, "move": [0, 1], "frames": 10},      # down
          {"at": FIRST + 300, "button": 1},
          {"at": FIRST + 400, "move": [-1, -1], "frames": 5},     # up and left, held
          {"at": FIRST + 550, "button": 0}]
END = FIRST + 750


def main():
    work = os.path.join(ROOT, "build", "mouse")
    os.makedirs(work, exist_ok=True)
    with open(os.path.join(work, "AUTOEXEC.BAT"), "w", newline="\r\n") as f:
        f.write("@ECHO OFF\nCLS\nMOUSETST L\n")
    img = os.path.join(work, "mouse.img")
    subprocess.run([sys.executable, "-I", os.path.join(HERE, "make_fat12.py"), os.path.join(FD, "boot.bin"), img,
                    "KERNEL.SYS=" + os.path.join(FD, "KERNEL.SYS"), "COMMAND.COM=" + os.path.join(FD, "COMMAND.COM"),
                    "FDCONFIG.SYS=" + os.path.join(FD, "FDCONFIG.SYS"),
                    "AUTOEXEC.BAT=" + os.path.join(work, "AUTOEXEC.BAT"),
                    "MOUSETST.COM=" + os.path.join(FD, "MOUSETST.COM")], check=True, capture_output=True)
    disk = os.path.join(work, "DISK#060000")
    with open(img, "rb") as f, open(disk, "wb") as g:
        g.write(f.read())
    cmd = os.path.join(work, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write("D\r" + "".join(a + "\r" for a in sys.argv[1:]))
    stage = os.path.join(ROOT, "build", "stage")
    po = os.path.join(work, "mouse.po")
    subprocess.run([os.path.join(HERE, "make_image.sh"), po, os.path.join(stage, "XTGS.SYSTEM#FF2000"),
                    os.path.join(stage, "CORE#060000"), os.path.join(stage, "SVC#060000"), disk, cmd],
                   check=True, capture_output=True)
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    inputs = [dict(i, after="start") for i in INPUTS]
    r = mamerun.run(po, waits=[(syms["mb_magic"], 0x5A5A)],
                    dumps=[("fb", 0x2B8000, 4000), ("raw", 0x0509EE, 2)], seconds=END / 60, settle=5, inputs=inputs)
    if r["status"] == "no-output":
        print(r.get("mame_output", ""))
        sys.exit("mouse_test: MAME produced no result")
    fb = bytes.fromhex(r["dumps"]["fb"]["hex"])
    rows = [bytes(fb[y * 160 + x * 2] for x in range(80)).decode("cp437").rstrip("\0 ") for y in range(25)]
    for row in rows:
        if row:
            print("  | " + row)
    got = [tuple(int(v) for v in m.groups()) for m in map(LINE.search, rows) if m]
    judge(rows, got)


def judge(rows, got):
    """MAME's mouse does not report every step of its fields, so a movement is held
    to its direction and to no more than was asked: a count is two across, one down."""
    bad = []
    if not got or got[0][:3] != (320, 100, 0):
        sys.exit("FAIL mouse: the first line is not the middle of the screen with no button down")
    last = {}                                   # the last line of each state of the button, in order
    order = []
    seen = 0
    for x, y, b, ev, n, hx, hy in got:
        seen |= ev
        if not order or order[-1][0] != b:
            order.append([b, None, None])
            order[-1][1] = (x, y)
            if b == 1 and not ev & 2:
                bad.append("the handler was not told of the press")
            if b == 0 and len(order) > 1 and not ev & 4:
                bad.append("the handler was not told of the release")
        order[-1][2] = (x, y)
    if [o[0] for o in order] != [0, 1, 0]:
        sys.exit(f"FAIL mouse: the button went {[o[0] for o in order]}, not up, down, up")
    (x0, y0), (x1, y1) = order[0][1], order[0][2]           # right 10, then down 10
    if not (x0 < x1 <= x0 + 20 and (x1 - x0) % 2 == 0 and y0 < y1 <= y0 + 10):
        bad.append(f"10 right and 10 down took it from {x0},{y0} to {x1},{y1}")
    if order[1][1] != (x1, y1):
        bad.append(f"the press was at {order[1][1]}, not where the mouse was, {x1},{y1}")
    x2, y2 = order[1][2]                                     # up and left 5, held
    if not (x1 - 10 <= x2 < x1 and y1 - 5 <= y2 < y1):
        bad.append(f"5 up and left took it from {x1},{y1} to {x2},{y2}")
    if order[2][2] != (x2, y2):
        bad.append(f"the release was at {order[2][2]}, not where the mouse was, {x2},{y2}")
    x, y, b, ev, n, hx, hy = got[-1]
    if (hx, hy) != (x, y):
        bad.append(f"the handler's last place {hx},{hy} is not the mouse's {x},{y}")
    if n < 10:
        bad.append(f"the handler was called {n} times for 25 movements and 2 changes of the button")
    if seen & 1 == 0:
        bad.append("the handler was not told of a movement")
    if bad:
        sys.exit("FAIL mouse: " + "; ".join(bad))
    print(f"PASS mouse: right, down, a press, up and left, a release by INT 33h function 03h; "
          f"the handler called {n} times")


if __name__ == "__main__":
    main()
