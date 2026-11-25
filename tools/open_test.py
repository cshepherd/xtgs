#!/usr/bin/env python3
"""open_test.py [--only a,b,...] [--show] [--stock]: a document opened with XT/GS
(make test-open; docs/finder.md).

The GS/OS application is launched as the Finder launches it for a file of
its own (tests/gsos/start16.s: the pathname in the volume's file ARG goes to
the Message Center as message 1), with FreeDOS in the folder SHARED, command
S. Each step is a boot of a volume built for it:

  sub      a batch file in a folder whose ProDOS names are not DOS's
           (X..7UP/MW.MAIN.BAT, given in lower case): the keys CD \\7UP and
           MW_MAIN.BAT are typed at the prompt, and the batch file says where
           it ran
  root     a .COM in the drive's root, after an AUTOEXEC.BAT that waits for a
           key: nothing is typed into the wait (the harness's own key ends
           it), CD \\ and the name at the prompt after it
  outside  a file beside the folder, and one in a folder whose name only
           begins like it: refused (MB_ARGN $8001) and said on the text screen
  noname   a file in a folder DOS has no name for: refused ($8003)
  nodos    an XTGS.CMD that boots no DOS: refused by the front end ($8002)
  state    a boot state written at the prompt (the desk accessory's sixth
           choice), then the application opened with the batch file and
           STATE=ON: the PC starts from the state and the keys are typed
  drive    FreeDOS booted from its diskette image (command D) with the
           folder as E:: the drive's letter is typed first
  bas      a BASIC program in a folder: \\GWBASIC and its name, GW-BASIC
           being in the drive's root, and in a second boot, with GWBASIC.EXE
           in a folder that AUTOEXEC.BAT puts on the PATH, GWBASIC and its
           name; the program runs both times

Work files in build/open/. Always the GS/OS front end (the ProDOS 8 loader
has no documents); XTGS_JIT=1 and XTGS_LAYOUT are the caller's. The IIGS is
a 16 MHz one; --stock is the 2.8 MHz one, for the steps that send no keys
of their own (sub, outside, noname, nodos).
"""
import os
import shutil
import subprocess
import sys

os.environ["XTGS_FRONT"] = "s16"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "mame"))
import mamerun  # noqa: E402
import symbols  # noqa: E402

FD = os.path.join(ROOT, "third_party", "freedos", "fd", "SHARED")
WORK = os.path.join(ROOT, "build", "open")
PO = os.path.join(WORK, "open.po")
CADIUS = os.path.join(HERE, "cadius_strict.sh")
K1, K2, K3 = ":macadb:KEY1", ":macadb:KEY2", ":macadb:KEY3"
RES = 0x050000
BS_BOOT = RES + 0x8BC                                       # src/include/pc.s
LATE = mamerun.GSOS_BOOT * 60
HOME = "/XTGS/XTGS"                                         # the application's folder on the volume
STEPS = ["sub", "root", "outside", "noname", "nodos", "state", "drive", "bas"]
STOCK = "--stock" in sys.argv
# RUNME.COM: mov ah,9 / mov dx,109h / int 21h / int 19h, and what it says
RUNME = bytes.fromhex("B409BA0901CD21CD19") + b"COM-RAN\r\n$"
BAT = "@ECHO OFF\nCD\nECHO BAT-RAN\n\\REBOOT\n"
MARKW = 0x2F8000                                            # F800:0000, where SAY.BAS leaves a word when it has run
BAS = '10 PRINT "BAS-RAN"\n20 DEF SEG=&HF800:POKE 0,&HEF:POKE 1,&HBE\n'

WHY = {1: "it is not in the folder DOS has", 2: "XTGS.CMD gives DOS no folder", 3: "DOS has no name for it"}
SAID = {1: "It is outside the folder DOS uses.", 2: "XTGS.CMD gives DOS no folder.", 3: "DOS has no name for that file."}


def tap(at, name, port=K3, hold=8):
    return [{"at": at, "press": name, "port": port, "value": 1},
            {"at": at + hold, "press": name, "port": port, "value": 0}]


def save_state(t):
    """Control-Apple-Esc at frame t, XTGS Control, its sixth choice (the boot state), and Quit."""
    seq = tap(t, "Control", hold=40) + tap(t + 2, "Command / Open Apple", hold=36) + tap(t + 10, "Esc", hold=20)
    t += 200
    for _ in range(5):
        seq += tap(t, "Down Arrow")
        t += 40
    seq += tap(t, "Return", K2) + tap(t + 80, "6  ^", K1) + tap(t + 140, "Space") + tap(t + 200, "Esc")
    t += 260
    for _ in range(2):
        seq += tap(t, "Down Arrow")
        t += 40
    return seq + tap(t, "Return", K2), t


def cadius(*args):
    r = subprocess.run([CADIUS] + list(args), capture_output=True, text=True)
    if r.returncode:
        sys.exit("open_test: cadius %s failed:\n%s" % (args[0], r.stdout + r.stderr))


def arg_file(path):
    name = os.path.join(WORK, "ARG#040000")
    with open(name, "w") as f:
        f.write(path + "\r")
    return name


def build(arg, cmd=("S", "C=SHARED"), autoexec="@ECHO OFF\n", disk=False, basic_in=None):
    os.makedirs(WORK, exist_ok=True)
    folder = os.path.join(WORK, "SHARED")
    shutil.rmtree(folder, ignore_errors=True)
    shutil.copytree(FD, folder)
    with open(os.path.join(folder, "AUTOEXEC.BAT#040000"), "w", newline="\r\n") as f:
        f.write(autoexec)
    open(os.path.join(folder, "RUNME.COM#060000"), "wb").write(RUNME)
    open(os.path.join(folder, "REBOOT.COM#060000"), "wb").write(b"\xCD\x19")
    for sub in ("X..7UP", "LONGFOLDER1"):
        os.mkdir(os.path.join(folder, sub))
        with open(os.path.join(folder, sub, "MW.MAIN.BAT#040000"), "w", newline="\r\n") as f:
            f.write(BAT)
    with open(os.path.join(folder, "X..7UP", "SAY.BAS#040000"), "w", newline="\r\n") as f:
        f.write(BAS)
    if basic_in:                                            # GW-BASIC out of the root
        os.mkdir(os.path.join(folder, basic_in))
        os.rename(os.path.join(folder, "GWBASIC.EXE#060000"), os.path.join(folder, basic_in, "GWBASIC.EXE#060000"))
    name = os.path.join(WORK, "XTGS.CMD#040000")
    with open(name, "w") as f:
        f.write("".join(l + "\r" for l in cmd))
    stage = os.path.join(ROOT, "build", "stage")
    files = [os.path.join(stage, n) for n in ("XTGS.SYSTEM#FF2000", "CORE#060000", "SVC#060000")] + [name]
    if arg:
        files.append(arg_file(arg))
    if disk:
        shutil.copyfile(os.path.join(os.path.dirname(FD), "freedos.img"), os.path.join(WORK, "DISK#060000"))
        files.append(os.path.join(WORK, "DISK#060000"))
    subprocess.run([os.path.join(HERE, "make_image.sh"), PO] + files + [folder],
                   check=True, capture_output=True, env=dict(os.environ, VOLSIZE="4096KB"))


def boot(seconds, inputs=()):
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    inputs = [dict(i, at=i["at"] + LATE, after="start") for i in inputs]
    r = mamerun.run(PO, waits=[(syms["mb_magic"], 0x5A5A), (MARKW, 0xBEEF)],
                    seconds=(seconds * 4 if STOCK else seconds) + LATE / 60, settle=5, inputs=inputs, zip=not STOCK,
                    dumps=[("fb", 0x2B8000, 4000), ("arg", syms["mb_argn"], 4), ("boot", BS_BOOT, 2),
                           ("text", 0x000400, 0x400), ("caplen", RES + 0x800, 2), ("cap", RES + 0x1000, 0x6000)])
    if r["status"] == "no-output":
        print(r.get("mame_output", ""))
        sys.exit("open_test: MAME produced no result")
    def dump(name, size):                                   # (a region the front end never claimed is not dumped)
        return bytes.fromhex(r["dumps"][name]["hex"]) if name in r["dumps"] else bytes(size)
    fb = dump("fb", 4000)
    r["rows"] = [bytes(fb[y * 160 + x * 2] for x in range(80)).decode("cp437").rstrip("\0 ") for y in range(25)]
    a = dump("arg", 4)
    r["argn"], r["argi"] = a[0] | a[1] << 8, a[2] | a[3] << 8
    r["bootw"] = dump("boot", 2)[0]
    n = dump("caplen", 2)                                   # what the BIOS's teletype was given, from the boot on
    r["said"] = [x.rstrip() for x in
                 dump("cap", 0x6000)[:n[0] | n[1] << 8].decode("cp437").replace("\r", "").split("\n")]
    t = bytes.fromhex(r["dumps"]["text"]["hex"])
    base = [0x000, 0x080, 0x100, 0x180, 0x200, 0x280, 0x300, 0x380]
    r["text"] = ["".join(chr(c & 0x7F) if 32 <= c & 0x7F < 127 else " " for c in t[b + o:b + o + 40]).strip()
                 for o in (0, 0x28, 0x50) for b in base]
    return r


def typed(r, name, want, show):
    """What DOS printed (the teletype's capture: a program may have cleared the screen since) must have
    these lines, in this order."""
    rows, at, missing = r["said"], 0, []
    for w in want:
        hit = [i for i in range(at, len(rows)) if rows[i] == w]
        if not hit:
            missing.append(w)
            continue
        at = hit[0] + 1
    bad = [f"DOS printed no line {m!r} where it should be" for m in missing]
    if r["status"] != "hit":
        bad.append(f"the run did not end ({r['status']}): the program's INT 19h was not reached")
    if r["argn"] != 0:
        bad.append(f"MB_ARGN is {r['argn']:#x} at the end, not 0 (all typed)")
    if show or bad:
        print("\n".join(rows[-30:]))
    if bad:
        sys.exit(f"FAIL open ({name}): " + "; ".join(bad))


def refused(r, name, why, file, show):
    bad = []
    if r["argn"] != 0x8000 + why:
        bad.append(f"MB_ARGN is {r['argn']:#x}, not {0x8000 + why:#x} ({WHY[why]})")
    said = [t for t in r["text"] if t]
    for w in (f"XT/GS will not run {file}", SAID[why]):
        if not any(w in t for t in said):
            bad.append(f"the text screen does not say {w!r}")
    if r["status"] != "hit":
        bad.append(f"the front end did not finish ({r['status']})")
    if show or bad:
        print("\n".join(said))
    if bad:
        sys.exit(f"FAIL open ({name}): " + "; ".join(bad))


def step_sub(show):
    build("/xtgs/Xtgs/Shared/x..7up/mw.main.bat")
    r = boot(150)
    typed(r, "sub", ["C:\\>CD \\7UP", "C:\\7UP>MW_MAIN.BAT", "C:\\7UP", "BAT-RAN"], show)
    print("PASS open (sub): SHARED/X..7UP/MW.MAIN.BAT, given in lower case: CD \\7UP and MW_MAIN.BAT typed at the "
          "prompt, and the batch file ran in that folder")


def step_root(show):
    build(HOME + "/SHARED/RUNME.COM", autoexec="@ECHO OFF\nPAUSE\nECHO AFTER\n")
    r = boot(190, [{"at": 4200, "key": " "}])
    typed(r, "root", ["AFTER", "C:\\>CD \\", "C:\\>RUNME.COM", "COM-RAN"], show)
    wait = [x for x in r["said"] if x.startswith("Press any key")]
    if not wait or wait[0].rstrip(" .") != "Press any key to continue":
        sys.exit(f"FAIL open (root): the wait's line is {wait}: something was typed into it")
    print("PASS open (root): SHARED/RUNME.COM: nothing typed while AUTOEXEC.BAT waited for a key, then CD \\ and "
          "RUNME.COM at the prompt, and the program ran")


def step_outside(show):
    build(HOME + "/CORE.BAT")
    r = boot(60)
    refused(r, "outside", 1, "CORE.BAT", show)
    build(HOME + "/SHARED2/A.COM")
    r = boot(60)
    refused(r, "outside", 1, "A.COM", show)
    print("PASS open (outside): a file beside the folder, and one in a folder whose name begins like it: not run, "
          "no PC started, and the text screen says why")


def step_noname(show):
    build(HOME + "/SHARED/LONGFOLDER1/MW.MAIN.BAT")
    r = boot(60)
    refused(r, "noname", 3, "MW.MAIN.BAT", show)
    print("PASS open (noname): a file in a folder DOS has no name for: not run, and said")


def step_nodos(show):
    build(HOME + "/SHARED/RUNME.COM", cmd=("P",))
    r = boot(60)
    refused(r, "nodos", 2, "RUNME.COM", show)
    print("PASS open (nodos): XTGS.CMD's command P boots no DOS: the front end refuses the file itself")


def step_state(show):
    build(None, cmd=("S", "C=SHARED", "STATE=ON"))
    seq, t = save_state(3000)
    r = boot((t + 2400) / 60, seq)
    if "XTGS.STATE" not in subprocess.run([CADIUS, "CATALOG", PO], capture_output=True, text=True).stdout:
        print("\n".join(r["rows"]))
        sys.exit("FAIL open (state): the boot state was not written")
    cadius("ADDFILE", PO, HOME + "/", arg_file(HOME + "/SHARED/X..7UP/MW.MAIN.BAT"))
    r = boot(120)
    if r["bootw"] != 1:
        print("\n".join(r["rows"]))
        sys.exit(f"FAIL open (state): BS_BOOT is {r['bootw']}, not 1: the PC was not started from the boot state")
    typed(r, "state", ["C:\\>CD \\7UP", "C:\\7UP>MW_MAIN.BAT", "C:\\7UP", "BAT-RAN"], show)
    print("PASS open (state): the PC started from its boot state, and CD \\7UP and MW_MAIN.BAT typed at its prompt")


def step_drive(show):
    build(HOME + "/SHARED/X..7UP/MW.MAIN.BAT", cmd=("D", "E=SHARED"), disk=True)
    # (the image has no AUTOEXEC.BAT: FreeCOM asks for the date and the time, and nothing may be typed into those)
    r = boot(200, [{"at": 3900, "coded": "{ENTER}"}, {"at": 4080, "coded": "{ENTER}"}])
    typed(r, "drive", ["A:\\>E:", "E:\\>CD \\7UP", "E:\\7UP>MW_MAIN.BAT", "E:\\7UP", "BAT-RAN"], show)
    if not any(x.rstrip() == "Enter new date (mm-dd-[cc]yy):" for x in r["said"]):
        sys.exit("FAIL open (drive): the date's line is not as FreeCOM left it: something was typed into it")
    print("PASS open (drive): DOS booted from the diskette image with the folder as E:: nothing typed at the date "
          "and the time, then E:, CD \\7UP and MW_MAIN.BAT at the A:\\> prompt")


def step_bas(show):
    build("/XTGS/XTGS/SHARED/X..7UP/SAY.BAS")
    r = boot(150)
    typed(r, "bas", ["C:\\>CD \\7UP", "C:\\7UP>\\GWBASIC SAY.BAS"], show)
    if "BAS-RAN" not in r["rows"]:
        sys.exit("FAIL open (bas): GW-BASIC's screen has no line BAS-RAN\n" + "\n".join(r["rows"]))
    build("/XTGS/XTGS/SHARED/X..7UP/SAY.BAS", autoexec="@ECHO OFF\nPATH C:\\BIN\n", basic_in="BIN")
    r = boot(150)
    typed(r, "bas", ["C:\\>CD \\7UP", "C:\\7UP>GWBASIC SAY.BAS"], show)
    if "BAS-RAN" not in r["rows"]:
        sys.exit("FAIL open (bas): with GW-BASIC on the PATH its screen has no line BAS-RAN\n" + "\n".join(r["rows"]))
    print("PASS open (bas): SHARED/X..7UP/SAY.BAS: CD \\7UP and \\GWBASIC SAY.BAS typed, GW-BASIC being in the "
          "drive's root, and GWBASIC SAY.BAS when it is in a folder on the PATH; the program ran both times")


def main():
    show = "--show" in sys.argv
    only = STEPS
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1].split(",")
        for o in only:
            if o not in STEPS:
                sys.exit(f"open_test: no step {o} (there are {', '.join(STEPS)})")
    if STOCK and any(o in ("root", "state", "drive") for o in only):
        sys.exit("open_test: --stock is for sub, outside, noname and nodos (--only)")
    for s in STEPS:
        if s in only:
            globals()["step_" + s](show)


main()
