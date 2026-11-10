#!/usr/bin/env python3
"""minix_test.py [IMAGE] [--zip] [--seconds S] [--show] - Minix 1.5 from
its demonstration diskette (docs/minix.md), headless.

IMAGE is the 360K diskette image (default third_party/minix/demo_dsk.ibm,
in the tree with its licence). It goes on a ProDOS volume as DISK with
command D,
and the run answers the boot menu with "=", types the date Minix asks for,
logs in as root and has the shell list directories until the screen has
scrolled to where the CGA's 16K ends in the middle of it. Nothing here goes through the
BIOS once the kernel is up, so what is judged is what Minix needs of the
PC itself:

  the 8259   Minix moves the interrupts to vectors 28h-2Fh and masks and
             unmasks them at port 21h; a clock or keyboard interrupt at
             vector 8 or 9 is an exception to it and the boot stops.
  the 765    the RAM disk is read from the diskette through the
             controller's ports and the 8237's (src/svc/ports.s).
  the 6845   the console writes B800 itself, scrolls by moving the start
             address and puts the cursor at R14/R15: the SHR pixels must
             show the buffer from where the 6845 starts, round the end of
             the 16K, and the cursor where the 6845 has it.
  the clock  the date Minix prints is the one typed, with the weekday it
             worked out; the one it prints at the end is later.

Each step waits for the cursor to reach the place the prompt leaves it at
(a trigger on the BDA for the boot menu, on the 6845's R14/R15 after), so
the run does not depend on the machine's speed. --zip is a 16 MHz ZipGS.
XTGS_FRONT=s16 and XTGS_LAYOUT=alt work as for the other tools. One run at
a time: the work files are in build/minix.
"""
import argparse
import datetime
import os
import re
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
import textshr  # noqa: E402

RES = 0x050000
TXT = 0x2B8000
BDA_CURSOR = 0x200450
CRTC = RES + 0x880                  # src/include/pc.s CRTC_REG
PIC = RES + 0x8AC                   # PIC_BASE, PIC_MASK
DOC = RES + 0x878                   # DOC_IRQS, DOC_DROPS
COMMANDS = "ls -l; ls /bin /dev; ls /dev; echo round the end; date"
# where the cursor waits (cells from the top of the screen) at each prompt
AT_MENU = 16 << 8 | 2               # the boot menu's "# " (BIOS: row, column)
AT_DATE = 8 * 80                    # under "Please enter date"
AT_LOGIN = 13 * 80 + 7              # after "login: "
AT_SHELL = 14 * 80 + 2              # after the shell's first "# "
# ... and after COMMANDS: the last row, the screen's start 84 rows on, which
# puts the end of the 16K in the middle of row 18
SCROLLED = 84
AT_END = (SCROLLED * 80 & 0x1FFF) + 24 * 80 + 2     # (Minix does not wrap the cursor address)


def r14(cell):
    """The u16 at R14 when the 6845's cursor address is `cell`."""
    return (cell & 0xFF) << 8 | cell >> 8


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image", nargs="?", default=os.path.join(ROOT, "third_party", "minix", "demo_dsk.ibm"))
    ap.add_argument("--zip", action="store_true", help="a 16 MHz ZipGS")
    ap.add_argument("--seconds", type=float, default=1800)
    ap.add_argument("--show", action="store_true", help="print the screen")
    args = ap.parse_args()
    if not os.path.isfile(args.image):
        sys.exit(f"minix_test: no diskette image at {args.image}")
    work = os.path.join(ROOT, "build", "minix")
    os.makedirs(work, exist_ok=True)
    disk = os.path.join(work, "DISK#060000")
    with open(args.image, "rb") as f, open(disk, "wb") as g:
        g.write(f.read())
    cmd = os.path.join(work, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write("D\r")
    stage = os.path.join(ROOT, "build", "stage")
    po = os.path.join(work, "minix.po")
    r = subprocess.run([os.path.join(HERE, "make_image.sh"), po,
                        os.path.join(stage, "XTGS.SYSTEM#FF2000"), os.path.join(stage, "CORE#060000"),
                        os.path.join(stage, "SVC#060000"), disk, cmd], capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stdout + r.stderr)

    now = datetime.datetime.now().replace(microsecond=0)
    typed = now.strftime("%m%d%y%H%M%S")
    triggers = {"menu": (BDA_CURSOR, AT_MENU), "date": (CRTC + 14, r14(AT_DATE)),
                "login": (CRTC + 14, r14(AT_LOGIN)), "shell": (CRTC + 14, r14(AT_SHELL))}
    inputs = [{"at": 30, "after": "menu", "key": "="},
              {"at": 30, "after": "date", "coded": typed + "{ENTER}"},
              {"at": 30, "after": "login", "coded": "root{ENTER}"},
              {"at": 30, "after": "shell", "coded": COMMANDS + "{ENTER}"}]
    r = mamerun.run(po, waits=[(CRTC + 14, r14(AT_END))],
                    dumps=[("gregs", 0x001000, 0x20), ("txt", TXT, 0x4000), ("crtc", CRTC, 0x20),
                           ("pic", PIC, 4), ("doc", DOC, 4), ("shr", shr.SHR_BASE, shr.SHR_LEN)],
                    seconds=args.seconds, settle=45, triggers=triggers, inputs=inputs, zip=args.zip)
    txt = bytes.fromhex(r["dumps"]["txt"]["hex"])
    crtc = bytes.fromhex(r["dumps"]["crtc"]["hex"])
    pix = bytes.fromhex(r["dumps"]["shr"]["hex"])
    org = (crtc[12] << 8 | crtc[13]) & 0x1FFF
    cur = ((crtc[14] << 8 | crtc[15]) - org) & 0x1FFF
    base, mask = struct.unpack("<2H", bytes.fromhex(r["dumps"]["pic"]["hex"]))
    irqs, drops = struct.unpack("<2H", bytes.fromhex(r["dumps"]["doc"]["hex"]))
    screen = bytes(txt[(org * 2 + i) & 0x3FFF] for i in range(4000))
    rows = [screen[i * 160:i * 160 + 160:2].decode("cp437").replace("\0", " ").rstrip() for i in range(25)]
    png, _ = shr.render(pix)
    with open(os.path.join(work, "minix.png"), "wb") as f:
        f.write(png)
    with open(os.path.join(work, "minix.txt"), "w") as f:
        f.write("\n".join(rows) + "\n")

    frames = {n: f[0] for n, f in r.get("triggers", {}).items()}
    print(f"Minix: status {r['status']} frame {r['frame']} ({r['frame'] / 60:.0f} emulated seconds"
          f"{', 16 MHz' if args.zip else ''})")
    print("  " + ", ".join(f"{n} at {frames[n] / 60:.0f} s" for n in ("menu", "date", "login", "shell") if n in frames))
    print(f"  8259: IRQ0 at vector {base:#04x}, mask {mask:#04x}; timer: {irqs} interrupts (mod 65536), "
          f"{drops} dropped with the guest not taking them")
    print(f"  6845: screen from cell {org}, cursor at row {cur // 80} column {cur % 80}")
    if args.show or r["status"] != "hit":
        for i, row in enumerate(rows):
            print(f"  {i:2d}|{row}")
    bad = []
    if r["status"] != "hit":
        bad.append("the shell's prompt did not come back after the commands "
                   f"(waited for: {', '.join(n for n in triggers if n not in frames) or 'the end'})")
    else:
        if base != 0x28:
            bad.append(f"IRQ0 is at vector {base:#x}, not where Minix puts it (28h)")
        if org != (SCROLLED * 80) & 0x1FFF or cur != 24 * 80 + 2:
            bad.append("the screen does not start, or the cursor is not, where the commands should leave them")
        if org * 2 + 4000 <= 0x4000 or (0x4000 - org * 2) % 160 == 0:
            bad.append("the end of the 16K is not in the middle of a row of the screen")
        dates = [m for m in (re.match(r"(\w{3} \w{3} [ \d]\d \d\d:\d\d:\d\d \d{4})$", row) for row in rows) if m]
        if rows[22] != "round the end" or len(dates) != 1 or rows[24] != "#":
            bad.append("the last rows are not the echo, the date and the prompt")
        else:
            at = datetime.datetime.strptime(dates[0].group(1), "%a %b %d %H:%M:%S %Y")
            print(f"  date typed {now:%a %b %d %H:%M:%S %Y}; Minix at the end: {at:%a %b %d %H:%M:%S %Y}")
            if not now < at <= now + datetime.timedelta(seconds=r["frame"] / 59.9 + 2):
                bad.append("Minix's date at the end is not after the one typed, or is too far on")
        wrong, cursors = [], []
        if not textshr.is_text(pix):
            bad.append("the screen is not in the text mode")
        else:
            wrong = textshr.mismatches(screen, pix, cursors)
        if wrong:
            bad.append(f"{len(wrong)} cells of the SHR screen do not show the text buffer: {wrong[:8]}")
        if cursors and cursors != [(cur // 80, cur % 80)]:
            bad.append(f"the cursor is drawn at {cursors}, not where the 6845 has it")
        print(f"  screen: {4000 - len(wrong) * 2} of 4000 bytes shown; cursor "
              f"{'drawn at row %d column %d' % cursors[0] if cursors else 'in the dark half of its blink'}")
    for b in bad:
        print(f"  FAIL: {b}")
    print("minix_test:", "FAIL" if bad else "ok")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
