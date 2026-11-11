#!/usr/bin/env python3
"""release_test.py IMAGE [--gsos] [--show]: boot the release volume (make test-release).

Without --gsos: a copy of the volume boots from ProDOS 8 as a IIGS's disk;
FreeDOS must come up from the folder SHARED, run its AUTOEXEC.BAT and reach
C:\\>; then, in a second boot, GWBASIC HELLO, typed there, must run and
leave (GW-BASIC clears the screen, and with NANSI.SYS as the console the
BIOS teletype's capture does not have what DOS printed: so two boots, each
judged by its screen).

With --gsos: a System 6 volume (SYSTEM6 in the environment; named GSBOOT
here) boots GS/OS with a copy of the release volume as the second disk, and
its Start program launches /XTGS/XTGS, the application on the release
volume, as the Finder would; FreeDOS must reach C:\\> the same way.

The copies are in build/release/test/: the release volume itself is never
booted, so nothing DOS or GS/OS writes gets into it.
--show prints the screen and what the BIOS teletype printed.
"""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GSOS = "--gsos" in sys.argv
if GSOS:
    os.environ["XTGS_FRONT"] = "s16"       # mamerun then finds the layout as the run goes
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "mame"))
import mamerun  # noqa: E402
import symbols  # noqa: E402

TXT = 0x2B8000
RES = 0x050000
CAP_LEN, CAP_BUF, CAP_MAX = RES + 0x800, RES + 0x1000, 0x7000     # src/include/pc.s
BANNER = "XT/GS: FreeDOS on the Apple IIGS"
START = os.path.join(ROOT, "tests", "gsos", "start16.s")


def screen(r):
    fb = bytes.fromhex(r["dumps"]["fb"]["hex"])
    return [bytes(fb[y * 160 + x * 2] for x in range(80)).decode("cp437").rstrip("\0 ") for y in range(25)]


def launcher(work):
    """start16.s, quitting to the release volume's application by its full name."""
    with open(START) as f:
        src = f.read()
    assert src.count("'*/XTGS/XTGS'") == 1 and src.count("dsk gsstart16") == 1
    src = src.replace("'*/XTGS/XTGS'", "'/XTGS/XTGS'").replace("dsk gsstart16", "dsk gsstartrel")
    with open(os.path.join(work, "gsstartrel.s"), "w") as f:
        f.write(src)
    out = os.path.join(work, "gsstartrel")
    if os.path.exists(out):
        os.remove(out)
    p = subprocess.run(["merlin32", "-V", "gsstartrel.s"], cwd=work, capture_output=True, text=True)
    if p.returncode or not os.path.exists(out):
        sys.exit("release_test: the launcher did not assemble\n" + p.stdout[-2000:])
    return out


def main():
    image = [a for a in sys.argv[1:] if not a.startswith("--")][0]
    work = os.path.join(ROOT, "build", "release", "test")
    os.makedirs(work, exist_ok=True)
    copy = os.path.join(work, "gsos.po" if GSOS else "p8.po")
    shutil.copyfile(image, copy)
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    dumps = [("fb", TXT, 4000), ("caplen", CAP_LEN, 2), ("cap", CAP_BUF, CAP_MAX)]
    waits = [(syms["mb_magic"], 0x5A5A)]            # (never: DOS does not end)
    if GSOS:
        sys6 = os.environ.get("SYSTEM6") or os.path.join(ROOT, "..", "ddiigs", "assets", "system6.hdv")
        if not os.path.isfile(sys6):
            sys.exit(f"release_test: no System 6 volume at {sys6} (set SYSTEM6=)")
        boot = os.path.join(work, "gsboot.hdv")
        env = dict(os.environ, GSOS_VOL="GSBOOT")
        env.pop("XTGS_FRONT", None)
        subprocess.run([os.path.join(HERE, "gsos_image.sh"), sys6, boot, launcher(work)],
                       check=True, env=env, stdout=subprocess.DEVNULL)
        runs = [(dict(seconds=330, image2=copy), [BANNER, "TDYDEMO  TDYSND"], boot)]
        what = "launched from GS/OS on the second disk"
    else:
        runs = [(dict(seconds=125), [BANNER, "TDYDEMO  TDYSND"], copy),
                (dict(seconds=170, inputs=[{"at": 7200, "after": "start", "coded": "GWBASIC HELLO{ENTER}"}]),
                 ["HELLO FROM GW-BASIC", "2 + 2 = 4"], copy)]
        what = "booted from ProDOS 8"
    for kw, want, disk in runs:
        r = mamerun.run(disk, waits=waits, dumps=dumps, settle=5, **kw)
        judge(r, want, what)
    print(f"PASS release, {what}: FreeDOS from SHARED, AUTOEXEC.BAT, C:\\>" +
          ("" if GSOS else ", GWBASIC HELLO") + f" (frame {r['frame']})")


def judge(r, want, what):
    if r["status"] == "no-output":
        print(r.get("mame_output", ""))
        sys.exit("release_test: MAME produced no result")
    rows = screen(r)
    # (and what the BIOS teletype printed: the kernel's lines, before a console driver loads)
    n = int.from_bytes(bytes.fromhex(r["dumps"]["caplen"]["hex"]), "little")
    text = "\n".join(rows) + "\n" + bytes.fromhex(r["dumps"]["cap"]["hex"])[:n].decode("cp437")
    if "--show" in sys.argv:                 # the teletype's capture and the screen
        print(text.replace("\r\n", "\n").replace("\r", "\n"))
    bad = [w for w in want if w not in text]
    last = [row for row in rows if row]
    if not last or last[-1] != "C:\\>":
        bad.append("the prompt C:\\> on the last line")
    if bad:
        print("\n".join("  | " + row for row in rows if row))
        sys.exit(f"FAIL release, {what}: the screen lacks " + "; ".join(bad))


if __name__ == "__main__":
    main()
