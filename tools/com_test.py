#!/usr/bin/env python3
"""com_test.py: the IIGS's serial ports as the PC's COM1 and COM2 (make
test-serial; docs/serial.md).

FreeDOS boots from a floppy whose AUTOEXEC.BAT runs COMTEST1 and COMTEST2
(tests/serial/comtest.asm, for 3F8h/IRQ4 and 2F8h/IRQ3), XTGS.CMD has the
lines COM1=MODEM and COM2=PRINTER, and MAME's modem and printer ports are
each looped back on themselves (XTGS_MODEM, XTGS_PRINTER = loopback). Each
program sends and must get back what it sent: by INT 14h, by the 8250's
registers polled, in a burst read only afterwards, and by the port's
interrupt. Its lines are held to "ok", and the SCC's interrupts and lost
characters are read from memory. A second boot has COM2=PRINTER alone (the
BDA's first port, still at 2F8h), a third neither line: no port in the
BDA, and the SCC never touched.

Work files in build/serial/. Three boots, about 200 emulated seconds each.
"""
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
os.environ["XTGS_MODEM"] = "loopback"
os.environ["XTGS_PRINTER"] = "loopback"
sys.path.insert(0, os.path.join(HERE, "mame"))
sys.path.insert(0, HERE)
import mamerun  # noqa: E402
import symbols  # noqa: E402

FD = os.path.join(ROOT, "third_party", "freedos", "fd")
CASES = ["bda", "bios", "registers", "polled", "burst", "irq", "thre"]


def boot(work, line, ports):
    """One boot with XTGS.CMD's lines after the first; COMTEST for each port in turn."""
    with open(os.path.join(work, "AUTOEXEC.BAT"), "w", newline="\r\n") as f:
        f.write("@ECHO OFF\nCLS\n" + "".join(f"COMTEST{n}\n" for n in ports))
    img = os.path.join(work, "serial.img")
    subprocess.run([sys.executable, "-I", os.path.join(HERE, "make_fat12.py"), os.path.join(FD, "boot.bin"), img,
                    "KERNEL.SYS=" + os.path.join(FD, "KERNEL.SYS"), "COMMAND.COM=" + os.path.join(FD, "COMMAND.COM"),
                    "FDCONFIG.SYS=" + os.path.join(FD, "FDCONFIG.SYS"),
                    "AUTOEXEC.BAT=" + os.path.join(work, "AUTOEXEC.BAT")] +
                   [f"COMTEST{n}.COM=" + os.path.join(work, f"COMTEST{n}.COM") for n in (1, 2)],
                   check=True, capture_output=True)
    with open(img, "rb") as f, open(os.path.join(work, "DISK#060000"), "wb") as g:
        g.write(f.read())
    cmd = os.path.join(work, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write("D\r" + line)
    stage = os.path.join(ROOT, "build", "stage")
    po = os.path.join(work, "serial.po")
    subprocess.run([os.path.join(HERE, "make_image.sh"), po, os.path.join(stage, "XTGS.SYSTEM#FF2000"),
                    os.path.join(stage, "CORE#060000"), os.path.join(stage, "SVC#060000"),
                    os.path.join(work, "DISK#060000"), cmd], check=True, capture_output=True)
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    svc = symbols.read(os.path.join(ROOT, "build", "svc.lst"))
    r = mamerun.run(po, waits=[(syms["mb_magic"], 0x5A5A)],
                    dumps=[("fb", 0x2B8000, 4000), ("on", svc["COM_ON"], 4), ("st", svc["COM_IRQS"], 8)],
                    seconds=200, settle=5)
    if r["status"] == "no-output":
        print(r.get("mame_output", ""))
        sys.exit("com_test: MAME produced no result")
    fb = bytes.fromhex(r["dumps"]["fb"]["hex"])
    rows = [bytes(fb[y * 160 + x * 2] for x in range(80)).decode("cp437").rstrip("\0 ") for y in range(25)]
    on, opened = struct.unpack("<2H", bytes.fromhex(r["dumps"]["on"]["hex"]))
    irqs1, irqs2, lost1, lost2 = struct.unpack("<4H", bytes.fromhex(r["dumps"]["st"]["hex"]))
    for row in rows:
        if row:
            print("  | " + row)
    return rows, dict(on=on, open=opened, irqs=(irqs1, irqs2), lost=(lost1, lost2))


def held(rows, n, bad):
    """COMTESTn's lines: every case ok, and its last line there."""
    mine = []
    for row in rows:
        if row.startswith(f"COM{n} "):
            mine = []
        mine.append(row)
        if row.startswith("modem status: "):
            break
    else:
        bad.append(f"COM{n}: the program did not reach its end")
    for c in CASES:
        if f"{c}: ok" not in mine:
            bad.append(f"COM{n}: no line '{c}: ok'")


def main():
    work = os.path.join(ROOT, "build", "serial")
    os.makedirs(work, exist_ok=True)
    for n in (1, 2):
        subprocess.run(["nasm", f"-DPORT={n}", "-f", "bin", "-o", os.path.join(work, f"COMTEST{n}.COM"),
                        os.path.join(ROOT, "tests", "serial", "comtest.asm")], check=True)
    bad = []
    # both ports, each looped back
    rows, st = boot(work, "COM1=MODEM\rCOM2=PRINTER\r", (1, 2))
    print(f"  {st}")
    held(rows, 1, bad)
    held(rows, 2, bad)
    if st["on"] != 3 or st["open"] != 3:
        bad.append(f"COM_ON {st['on']}, COM_OPEN {st['open']} for 3 and 3")
    if not all(st["irqs"]):
        bad.append(f"SCC interrupts {st['irqs']}: a channel never interrupted")
    if any(st["lost"]):
        bad.append(f"characters lost: {st['lost']}")
    # the printer port alone: it is the PC's first port by the BDA, and still at 2F8h
    rows, st2 = boot(work, "COM2=PRINTER\r", (2,))
    print(f"  {st2}")
    held(rows, 2, bad)
    if st2["on"] != 2 or st2["open"] != 2 or st2["irqs"][0] or not st2["irqs"][1]:
        bad.append(f"COM2 alone: {st2}")
    # neither: no port, and the SCC is never touched
    rows, st3 = boot(work, "", (1,))
    print(f"  {st3}")
    if "bda:  FAIL" not in rows or st3["on"] or st3["open"] or any(st3["irqs"]):
        bad.append(f"without the lines there is still a COM port ({st3})")
    if bad:
        sys.exit("FAIL serial: " + "; ".join(bad))
    print(f"PASS serial: {len(CASES)} cases on each of COM1 (the modem port) and COM2 (the printer port), "
          f"looped back; {st['irqs'][0]} and {st['irqs'][1]} SCC interrupts, no character lost")


if __name__ == "__main__":
    main()
