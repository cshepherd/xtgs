#!/usr/bin/env python3
"""joy_test.py: the IIGS's joystick as the PC's game port (make test-joy;
docs/joystick.md).

FreeDOS boots from a floppy whose AUTOEXEC.BAT runs JOYTEST L
(tests/demo/joytest.asm), with MAME's Apple joystick in the game port
(XTGS_GAMEIO=joy). The harness then moves the stick and presses its
buttons, a state every 200 frames, and JOYTEST starts a line for each
change in what it reads: by port 201h (a write, then reads counted until
each axis's bit falls; the buttons in bits 4 and 5) and by INT 15h AH=84h.
The lines on the screen are held to the states, in order.

Work files in build/joy/. One boot, about 190 emulated seconds.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
os.environ["XTGS_GAMEIO"] = "joy"
sys.path.insert(0, os.path.join(HERE, "mame"))
sys.path.insert(0, HERE)
import mamerun  # noqa: E402
import symbols  # noqa: E402

FD = os.path.join(ROOT, "third_party", "freedos", "fd")
X = ("P1 Joystick X", ":gameio:joy:joystick_1_x")
Y = ("P1 Joystick Y", ":gameio:joy:joystick_1_y")
B1 = ("P2 Button 1", ":gameio:joy:joystick_buttons")     # (MAME's names: the first stick's two)
B2 = ("P2 Button 2", ":gameio:joy:joystick_buttons")
# what the harness does, and the state after it: x, y (the stick's 0-255), buttons
STEPS = [((X, 0), (0, 128, "--")), ((X, 255), (255, 128, "--")), ((X, 128), (128, 128, "--")),
         ((Y, 0), (128, 0, "--")), ((Y, 255), (128, 255, "--")), ((X, 255), (255, 255, "--")),
         ((X, 64), (64, 255, "--")), ((Y, 192), (64, 192, "--")), ((B1, 1), (64, 192, "1-")),
         ((B2, 1), (64, 192, "12")), ((B1, 0), (64, 192, "-2")), ((B2, 0), (64, 192, "--"))]
FIRST, EVERY = 7600, 200
LOOP = 12                # the bytes of JOYTEST's read loop (joytest.asm, axis)
LINE = re.compile(r"port X\s*(\d+|none) Y\s*(\d+|none) buttons (..)\s+BIOS X\s*(\d+) Y\s*(\d+) buttons (..)")


def near(got, stick):
    """A paddle as read for a stick position: MAME's count of it, a little either way."""
    return abs(got - stick) <= 4


def main():
    work = os.path.join(ROOT, "build", "joy")
    os.makedirs(work, exist_ok=True)
    with open(os.path.join(work, "AUTOEXEC.BAT"), "w", newline="\r\n") as f:
        f.write("@ECHO OFF\nCLS\nJOYTEST L\n")
    img = os.path.join(work, "joy.img")
    subprocess.run([sys.executable, "-I", os.path.join(HERE, "make_fat12.py"), os.path.join(FD, "boot.bin"), img,
                    "KERNEL.SYS=" + os.path.join(FD, "KERNEL.SYS"), "COMMAND.COM=" + os.path.join(FD, "COMMAND.COM"),
                    "FDCONFIG.SYS=" + os.path.join(FD, "FDCONFIG.SYS"),
                    "AUTOEXEC.BAT=" + os.path.join(work, "AUTOEXEC.BAT"),
                    "JOYTEST.COM=" + os.path.join(FD, "JOYTEST.COM")], check=True, capture_output=True)
    disk = os.path.join(work, "DISK#060000")
    with open(img, "rb") as f, open(disk, "wb") as g:
        g.write(f.read())
    cmd = os.path.join(work, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write("D\r")
    stage = os.path.join(ROOT, "build", "stage")
    po = os.path.join(work, "joy.po")
    subprocess.run([os.path.join(HERE, "make_image.sh"), po, os.path.join(stage, "XTGS.SYSTEM#FF2000"),
                    os.path.join(stage, "CORE#060000"), os.path.join(stage, "SVC#060000"), disk, cmd],
                   check=True, capture_output=True)
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    svc = symbols.read(os.path.join(ROOT, "build", "svc.lst"))
    inputs = [{"at": FIRST + i * EVERY, "after": "start", "press": name, "port": port, "value": v}
              for i, (((name, port), v), _s) in enumerate(STEPS)]
    end = FIRST + len(STEPS) * EVERY + 200
    r = mamerun.run(po, waits=[(syms["mb_magic"], 0x5A5A)],
                    dumps=[("fb", 0x2B8000, 4000), ("joy", svc["JOY_HAVE"], 8)], seconds=end / 60, settle=5, inputs=inputs)
    if r["status"] == "no-output":
        print(r.get("mame_output", ""))
        sys.exit("joy_test: MAME produced no result")
    fb = bytes.fromhex(r["dumps"]["fb"]["hex"])
    rows = [bytes(fb[y * 160 + x * 2] for x in range(80)).decode("cp437").rstrip("\0 ") for y in range(25)]
    got = [m.groups() for m in map(LINE.search, rows) if m]
    for row in rows:
        if row:
            print("  | " + row)
    states = [(128, 128, "--")] + [s for _a, s in STEPS]

    def fits(g, state):
        px, py, pb, bx, by, bb = g
        sx, sy, sb = state
        if px == "none" or py == "none":
            return False
        want_p = lambda v: max(1, (v + 7) * 60 // (14 * LOOP + 35))   # joystick.s: the reads a paddle's bit lasts
        return (near(int(bx), sx) and near(int(by), sy) and abs(int(px) - want_p(sx)) <= 3
                and abs(int(py) - want_p(sy)) <= 3 and pb == sb and bb == sb)

    # The paddles read one count either way from sample to sample, and a line may be
    # read across a change: so every state must have its line, in order, and a line
    # that is not the state's own must come between two that are.
    bad = []
    k = 0
    strays = 0
    for g in got:
        if fits(g, states[k]):
            strays = 0
        elif k + 1 < len(states) and fits(g, states[k + 1]):
            k += 1
            strays = 0
        else:
            strays += 1
            if strays > 1:
                bad.append("the line " + " ".join(g) + f" is neither state {k} {states[k]} nor the next")
    if k != len(states) - 1:
        bad.append(f"the lines reach state {k} of {len(states) - 1}: {states[k + 1]} never shows")
    if bad:
        sys.exit("FAIL joystick: " + "; ".join(bad))
    print(f"PASS joystick: {len(states)} states of the stick and its buttons, by port 201h and by INT 15h AH=84h")


if __name__ == "__main__":
    main()
