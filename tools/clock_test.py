#!/usr/bin/env python3
"""clock_test.py [--dos] [--seconds S] - the IIGS clock as the guest's
(docs/clock.md), headless.

Runs tests/com/clock.asm, which prints the date and time every way a PC
program can ask for them, and holds the answers against this machine's
clock: MAME's IIGS starts with the host's local date and time and counts
emulated seconds from there, so the guest's clock must lie between the
time the run began and the time it ended plus the seconds it emulated.

Without --dos the program runs under the stub DOS (Mode A, command C), and
INT 21h AH=2Ah/2Ch are XT/GS's own. With --dos FreeDOS boots from the
folder SHARED (command S) and runs it from AUTOEXEC.BAT: there the date
and time are FreeDOS's, kept from the BIOS tick count since it started.
The program then keeps interrupts off for ten seconds, in which all but
TICK_MAX of the timer's ticks are lost, and asks again: the answers agree
with the real-time clock only when the lost ticks are made up (clk_sync).
It also waits for 20 ticks in a loop that polls INT 1Ah, and must see the
count change tick by tick (the slot's look after IRET, irq_chk).

XTGS_FRONT=s16 and XTGS_LAYOUT=alt work as for the other tools. One run at
a time: the work files are in build/clock.
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
import symbols  # noqa: E402

RES = 0x050000
CADIUS = os.path.join(HERE, "cadius_strict.sh")
FD = os.path.join(ROOT, "third_party", "freedos", "fd")
TICKS_A_SECOND = 1193180 / 65536
FRAMES_A_SECOND = 59.9


def sh(*args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"{' '.join(args)}\n{r.stdout}{r.stderr}")
    return r.stdout


def bcd(text):
    return int(text) if text.isdigit() else -1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dos", action="store_true", help="under FreeDOS, booted from the folder (command S)")
    ap.add_argument("--seconds", type=float, default=600)
    args = ap.parse_args()
    s16 = os.environ.get("XTGS_FRONT") == "s16"
    work = os.path.join(ROOT, "build", "clock")
    os.makedirs(work, exist_ok=True)

    def put(name, data):
        p = os.path.join(work, name)
        with open(p, "wb") as f:
            f.write(data)
        return p

    com = os.path.join(work, "CLOCK.COM#060000")
    sh("nasm", "-f", "bin", "-o", com, os.path.join(ROOT, "tests", "com", "clock.asm"))
    stage = os.path.join(ROOT, "build", "stage")
    po = os.path.join(work, "clock.po")
    base = [os.path.join(stage, "XTGS.SYSTEM#FF2000"), os.path.join(stage, "CORE#060000"),
            os.path.join(stage, "SVC#060000")]
    if args.dos:
        sh(os.path.join(HERE, "make_image.sh"), po, *base, put("XTGS.CMD#040000", b"S\r"))
        vol = os.environ.get("GSOS_VOL", "XTGS") if s16 else "XTGS"
        share = (f"/{vol}/XTGS" if s16 else f"/{vol}") + "/SHARED"
        sh(CADIUS, "CREATEFOLDER", po, share, "--quiet")
        files = [com, put("FDCONFIG.SYS#060000", b"SHELL=C:\\COMMAND.COM /P\r\n"),
                 put("AUTOEXEC.BAT#060000", b"@ECHO OFF\r\nCLOCK\r\nREBOOT\r\n"),
                 put("REBOOT.COM#060000", bytes([0xCD, 0x19]))]
        for n in ("KERNEL.SYS", "COMMAND.COM"):
            with open(os.path.join(FD, n), "rb") as f:
                files.append(put(n + "#060000", f.read()))
        for p in files:
            sh(CADIUS, "ADDFILE", po, share + "/", p, "--quiet")
    else:
        sh(os.path.join(HERE, "make_image.sh"), po, *base, com, put("XTGS.CMD#040000", b"C CLOCK.COM\r"))

    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    t0 = datetime.datetime.now()
    r = mamerun.run(po, waits=[(syms["mb_magic"], 0x5A5A)],
                    dumps=[("res", RES + 0x800, 0x100), ("cap", RES + 0x1000, 0x6000)],
                    seconds=args.seconds, settle=5)
    t1 = datetime.datetime.now()
    res = bytes.fromhex(r["dumps"]["res"]["hex"])
    caplen = struct.unpack_from("<H", res, 0)[0]
    irqs, drops = struct.unpack_from("<2H", res, 0x78)
    paid, made = struct.unpack_from("<2H", res, 0xA8)
    cap = bytes.fromhex(r["dumps"]["cap"]["hex"])[:caplen].decode("cp437").replace("\r", "")
    with open(os.path.join(work, "clock.out"), "w") as f:
        f.write(cap)
    emulated = r["frame"] / FRAMES_A_SECOND
    print(f"{'FreeDOS' if args.dos else 'stub DOS'}: status {r['status']} frame {r['frame']} "
          f"({emulated:.0f} emulated seconds in {(t1 - t0).total_seconds():.0f})")
    print(f"  IRQ0: {irqs} timer interrupts, {drops} dropped with the guest not taking them; "
          f"{made} ticks made up from the clock in {paid} steps")
    bad = []
    if r["status"] != "hit":
        bad.append("the run did not end")
    if "R none" in cap:
        bad.append("INT 1Ah AH=02/04 returned with carry set: no real-time clock")
    lines = re.findall(r"^([DTRKWX]) ([0-9A-F ]*)$", cap, re.M)
    for tag, rest in lines:
        print(f"  {tag} {rest}")
    if "".join(tag for tag, _ in lines) != "DTRKWXDTRK":
        bad.append(f"the program's lines are {''.join(tag for tag, _ in lines) or 'missing'}, not DTRKWXDTRK")
        lines = []
    for when, group in (("at the start", lines[:5]), ("after ten seconds with interrupts off", lines[6:])):
        line = {tag: rest.split() for tag, rest in group}
        if not line:
            break
        try:
            d, t, rt = line["D"], line["T"], line["R"]
            dos = datetime.datetime(int(d[0], 16), int(d[1], 16), int(d[2], 16),
                                    int(t[0], 16), int(t[1], 16), int(t[2], 16), int(t[3], 16) * 10000)
            rtc = datetime.datetime(bcd(rt[0]), bcd(rt[1][:2]), bcd(rt[1][2:]),
                                    bcd(rt[2][:2]), bcd(rt[2][2:]), bcd(rt[3]))
        except ValueError as e:
            bad.append(f"{when}: not a date and time: {e}")
            continue
        lo = t0 - datetime.timedelta(seconds=2)
        hi = t1 + datetime.timedelta(seconds=emulated + 2)
        k = int(line["K"][0], 16)
        midnight = rtc.replace(hour=0, minute=0, second=0)
        behind = (rtc - midnight).total_seconds() - k / TICKS_A_SECOND
        print(f"  {when}: real-time clock {rtc}, DOS {dos}, the tick count {behind:+.1f} seconds behind")
        if not lo <= rtc <= hi:
            bad.append(f"{when} the real-time clock says {rtc}: not between {lo:%Y-%m-%d %H:%M:%S} "
                       f"and {hi:%Y-%m-%d %H:%M:%S} (this machine's clock and the seconds emulated)")
        gap = (dos - rtc).total_seconds()
        if abs(gap) > 3:
            bad.append(f"{when} DOS's time is {gap:+.1f} seconds from the real-time clock's")
        if int(d[3], 16) != (dos.weekday() + 1) % 7:
            bad.append(f"{when} DOS's weekday is {d[3]} on a {dos:%A}")
        if abs(behind) > 3:
            bad.append(f"{when} the tick count {k:#x} is {-behind:+.1f} seconds from the real-time clock's time of day")
        if "W" in line and int(line["W"][1], 16) < 15:
            bad.append(f"the tick count changed {int(line['W'][1], 16)} times in a wait for 20 ticks: "
                       "IRQ0 is not reaching the program's polling loop")
        if line["K"][1] != "00" and rtc.date() == t0.date():
            bad.append(f"{when} the midnight flag is {line['K'][1]}")
    if bad:
        print("FAIL clock:")
        for b in bad:
            print("  " + b)
        print(f"  output: {os.path.join(work, 'clock.out')}")
        sys.exit(1)
    print("PASS clock: the date, the time and the tick count are this machine's"
          + (", and FreeDOS's time has kept up with them" if args.dos else ""))


if __name__ == "__main__":
    main()
