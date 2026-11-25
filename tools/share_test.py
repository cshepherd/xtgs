#!/usr/bin/env python3
"""share_test.py [--boot] [--letter L] [--full] [--seconds S] - the shared
drive (docs/share.md) under FreeDOS, headless.

Builds a FreeDOS floppy whose AUTOEXEC.BAT works on drive C:, a ProDOS
volume whose folder SHARE is that drive (XTGS.CMD: "D", then "C=SHARE"),
boots it in MAME and compares what DOS printed (the BIOS teletype capture
in the results bank) and what the ProDOS volume holds afterwards (cadius)
with what is expected. The last program on the floppy calls INT 19h, which
ends the run.

--boot is the S command instead: no floppy, FreeDOS and the batch file in
the folder SHARED, which DOS boots from as C: (XTGS.CMD is "S" alone, the
folder being the default; --full names it, "C=/XTGS/SHARED").

XTGS_FRONT=s16 and XTGS_LAYOUT=alt work as for the other tools. One run at
a time: the work files in build/share are shared.
"""
import argparse
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

RES = 0x050000
CADIUS = os.path.join(HERE, "cadius_strict.sh")
FD = os.path.join(ROOT, "third_party", "freedos", "fd")

HELLO = b"Hello from ProDOS.\r\n"
NOTE = b"A file in a folder.\r\n"

AUTOEXEC = r"""@ECHO OFF
ECHO [dir]
DIR C:
ECHO [type]
TYPE C:\HELLO.TXT
TYPE C:\DOCS\NOTE.TXT
TYPE C:\7UP.TXT
TYPE C:\A_B.TXT
ECHO [toA]
COPY C:\HELLO.TXT A:\H2.TXT
TYPE A:\H2.TXT
ECHO [toC]
COPY A:\FDCONFIG.SYS C:\KEEP.TXT
TYPE C:\KEEP.TXT
COPY A:\COMMAND.COM C:\BIG.BIN
ECHO [cd]
C:
MD SUB
CD SUB
COPY A:\FDCONFIG.SYS ONE.TXT
COPY ONE.TXT TWO.TXT
REN TWO.TXT THREE.TXT
COPY ONE.TXT 4FOUR.TXT
COPY 4*.TXT 5FIVE.TXT
COPY ONE.TXT S_X
COPY S_?.* T_U.V
COPY ONE.TXT 6_7.TXT
DEL 4FOUR.TXT
DIR
DEL ONE.TXT
CD ..
ECHO [prog]
FILEOPS
ECHO [bat]
CALL T.BAT
ECHO one > R.TXT
ECHO two >> R.TXT
TYPE R.TXT
ECHO [after]
DIR SUB
DIR *.TXT
MD GONE
RD GONE
IF EXIST GONE\NUL ECHO GONE is still there
IF EXIST HELLO.TXT ECHO HELLO.TXT exists
IF EXIST NOPE.TXT ECHO NOPE.TXT exists
%sA:
ECHO [end]
REBOOT
"""

# GW-BASIC (when third_party/gwbasic/GWBASIC.EXE is there) runs a program
# from the drive, with files named relative to C:'s current directory. (No
# directories in the names: this GW-BASIC takes a backslash for a letter of
# an eight-letter name, on any drive and on a PC as well.)
BASIC_BAT = r"""ECHO [basic]
COPY A:\GWBASIC.EXE C:\GW.EXE
GW PROG.BAS
TYPE BAS2.OUT
"""
BASIC = r"""10 OPEN "BAS.OUT" FOR OUTPUT AS #1
20 FOR I=1 TO 3:PRINT #1,"line";I:NEXT
30 CLOSE #1
40 OPEN "BAS.OUT" FOR APPEND AS #1:PRINT #1,"more":CLOSE #1
50 OPEN "C:HELLO.TXT" FOR INPUT AS #1:LINE INPUT #1,A$:CLOSE #1
60 OPEN "BAS.OUT" FOR APPEND AS #1:PRINT #1,A$:CLOSE #1
70 OPEN "TMP.OUT" FOR OUTPUT AS #1:CLOSE #1:KILL "TMP.OUT"
80 NAME "BAS.OUT" AS "BAS2.OUT"
90 SYSTEM
"""
GW = os.path.join(ROOT, "third_party", "gwbasic", "GWBASIC.EXE")


def sh(*args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"{' '.join(args)}\n{r.stdout}{r.stderr}")
    return r.stdout


def g0(cap):
    """The [dir] section of the capture."""
    m = re.search(r"^\[dir\]\n(.*?)^\[type\]", cap, re.M | re.S)
    return m.group(1) if m else ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=float, default=900)
    ap.add_argument("--letter", default="C", help="the drive letter (the batch file follows it)")
    ap.add_argument("--full", action="store_true", help="name the folder by its full pathname")
    ap.add_argument("--cfg", help="the XTGS.CMD setting line as it is (for the cases that fail)")
    ap.add_argument("--show", action="store_true", help="print the whole capture")
    ap.add_argument("--boot", action="store_true", help="boot DOS from the folder (the S command), no floppy")
    args = ap.parse_args()
    s16 = os.environ.get("XTGS_FRONT") == "s16"
    basic = os.path.isfile(GW)
    boot = args.boot
    L = "C" if boot else args.letter.upper()
    A = "C" if boot else "A"        # the drive DOS boots from
    folder = "SHARED" if boot else "SHARE"

    work = os.path.join(ROOT, "build", "share")
    os.makedirs(work, exist_ok=True)

    def put(name, data):
        p = os.path.join(work, name)
        with open(p, "wb") as f:
            f.write(data)
        return p

    # what DOS boots from: the floppy, or (--boot) the same files for the folder
    sh("nasm", "-f", "bin", "-o", os.path.join(work, "FILEOPS.COM#060000"),
       os.path.join(ROOT, "tests", "com", "fileops.asm"))
    dos = [("KERNEL.SYS", os.path.join(FD, "KERNEL.SYS")), ("COMMAND.COM", os.path.join(FD, "COMMAND.COM")),
           ("FDCONFIG.SYS", put("FDCONFIG.SYS", f"LASTDRIVE=Z\r\nSHELL={A}:\\COMMAND.COM /P\r\n".encode())),
           ("AUTOEXEC.BAT", put("AUTOEXEC.BAT", (AUTOEXEC % (BASIC_BAT if basic else "")).replace("C:", L + ":")
                                .replace("A:", A + ":").replace("\n", "\r\n").encode())),
           ("REBOOT.COM", put("REBOOT.COM", bytes([0xCD, 0x19])))] + ([("GWBASIC.EXE", GW)] if basic else [])
    disk = []
    if not boot:
        img = os.path.join(work, "share.img")
        sh(sys.executable, "-I", os.path.join(HERE, "make_fat12.py"), os.path.join(FD, "boot.bin"), img,
           *(f"{n}={p}" for n, p in dos))
        with open(img, "rb") as f:
            disk = [put("DISK#060000", f.read())]
    # (the volume's name is make_image.sh's and gsos_image.sh's)
    vol = os.environ.get("GSOS_VOL", "XTGS") if s16 else "XTGS"
    home = f"/{vol}/XTGS" if s16 else f"/{vol}"
    share = f"{home}/{folder}"
    if boot:
        cfg = args.cfg or (f"C={share}" if args.full else "")
        cmd = put("XTGS.CMD#040000", ("S\r" + (cfg + "\r" if cfg else "")).encode())
        cfg = "S " + (cfg or "(the folder SHARED)")
    else:
        cfg = args.cfg or f"{L}={share if args.full else folder}"
        cmd = put("XTGS.CMD#040000", ("D\r" + cfg + "\r").encode())

    # the volume, and the folder that is drive C:
    stage = os.path.join(ROOT, "build", "stage")
    po = os.path.join(work, "share.po")
    sh(os.path.join(HERE, "make_image.sh"), po, os.path.join(stage, "XTGS.SYSTEM#FF2000"),
       os.path.join(stage, "CORE#060000"), os.path.join(stage, "SVC#060000"), *disk, cmd)
    sh(CADIUS, "CREATEFOLDER", po, share, "--quiet")
    if boot:
        for n, p in dos:
            with open(p, "rb") as f:
                sh(CADIUS, "ADDFILE", po, share + "/", put(n + "#060000", f.read()), "--quiet")
    sh(CADIUS, "CREATEFOLDER", po, share + "/DOCS", "--quiet")
    sh(CADIUS, "ADDFILE", po, share + "/", put("HELLO.TXT#040000", HELLO), "--quiet")
    sh(CADIUS, "ADDFILE", po, share + "/", os.path.join(work, "FILEOPS.COM#060000"), "--quiet")
    sh(CADIUS, "ADDFILE", po, share + "/", put("LONG.NAME.FILE#040000", b"not a DOS name\r\n"), "--quiet")
    sh(CADIUS, "ADDFILE", po, share + "/DOCS/", put("NOTE.TXT#040000", NOTE), "--quiet")
    sh(CADIUS, "ADDFILE", po, share + "/", put("X..7UP.TXT#040000", b"Seven up.\r\n"), "--quiet")
    sh(CADIUS, "ADDFILE", po, share + "/", put("A.B.TXT#040000", b"A and B.\r\n"), "--quiet")
    sh(CADIUS, "ADDFILE", po, share + "/", put("T.BAT#040000", b"@ECHO OFF\r\nECHO a batch file on the drive\r\n"), "--quiet")
    if basic:
        sh(CADIUS, "ADDFILE", po, share + "/", put("PROG.BAS#040000", BASIC.replace("C:", L + ":").replace("\n", "\r\n").encode()), "--quiet")

    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    r = mamerun.run(po, waits=[(syms["mb_magic"], 0x5A5A)],
                    dumps=[("res", RES + 0x800, 0x100), ("cap", RES + 0x1000, 0x6000),
                           ("txt", 0x2B8000, 4000), ("shr", shr.SHR_BASE, shr.SHR_LEN)],
                    seconds=args.seconds, settle=5)
    res = bytes.fromhex(r["dumps"]["res"]["hex"])
    caplen = struct.unpack_from("<H", res, 0)[0]
    state, diag, calls, last = struct.unpack_from("<4H", res, 0xA0)
    cap = bytes.fromhex(r["dumps"]["cap"]["hex"])[:caplen].decode("cp437").replace("\r", "")
    txt = bytes.fromhex(r["dumps"]["txt"]["hex"])
    rows = [bytes(txt[row * 160 + c * 2] for c in range(80)).decode("cp437").rstrip() for row in range(25)]
    png, _ = shr.render(bytes.fromhex(r["dumps"]["shr"]["hex"]))
    with open(os.path.join(work, "share.png"), "wb") as f:
        f.write(png)
    with open(os.path.join(work, "share.out"), "w") as f:
        f.write(cap)
    print(f"{cfg}: status {r['status']} frame {r['frame']}  RD_STATE {state} RD_DIAG {diag} "
          f"RD_CALLS {calls} RD_LAST {last:#06x}  capture {caplen} bytes")
    if args.show or r["status"] != "hit" or state != 4:
        log = struct.unpack_from("<32H", res, 0xC0)
        order = [log[(calls + i) % 32] for i in range(32)] if calls >= 32 else list(log[:calls])
        print("last redirector calls (function:error):",
              " ".join(f"{w & 0xFF:02X}:{w >> 8:02X}" if w >> 8 else f"{w & 0xFF:02X}" for w in order))
        print(cap)
        print("text screen:")
        for i, row in enumerate(rows):
            if row.strip():
                print(f"  {i:2d}|{row}")

    cat = sh(CADIUS, "CATALOG", po)
    with open(os.path.join(work, "share.cat"), "w") as f:
        f.write(cat)
    bad = []

    def want(cond, what):
        if not cond:
            bad.append(what)

    want(r["status"] == "hit", "the run did not end (REBOOT.COM not reached)")
    if boot:
        want(re.search(r"KERNEL\s+SYS", g0(cap)), "DIR C: does not list KERNEL.SYS, which DOS booted from")
    want(state == 4, f"RD_STATE {state}, not 4 (RD_DIAG {diag})")
    sec = {}
    marks = ("dir", "type", "toA", "toC", "cd", "prog", "bat", "after", "end") + (("basic",) if basic else ())
    alt = "|".join(marks)
    for m in re.finditer(rf"^\[({alt})\]\n(.*?)(?=^\[(?:{alt})\]\n|\Z)", cap, re.M | re.S):
        sec[m.group(1)] = m.group(2)
    for name in marks:
        want(name in sec, f"no [{name}] section in the output")
    g = lambda k: sec.get(k, "")
    want(re.search(r"HELLO\s+TXT\s+20\b", g("dir")), "DIR C: does not list HELLO.TXT, 20 bytes")
    want(re.search(r"FILEOPS\s+COM", g("dir")), "DIR C: does not list FILEOPS.COM")
    want(re.search(r"DOCS\s+<DIR>", g("dir")), "DIR C: does not list DOCS as a directory")
    want("LONG" not in g("dir"), "DIR C: lists the name that is not 8.3")
    want("Hello from ProDOS." in g("type"), "TYPE C:\\HELLO.TXT")
    want(re.search(r"^7UP\s+TXT\s+11\b", g("dir"), re.M), "DIR C: does not list X..7UP.TXT as 7UP.TXT, 11 bytes")
    want("Seven up." in g("type"), "TYPE C:\\7UP.TXT")
    want(re.search(r"^A_B\s+TXT\s+10\b", g("dir"), re.M), "DIR C: does not list A.B.TXT as A_B.TXT, 10 bytes")
    want("A and B." in g("type"), "TYPE C:\\A_B.TXT")
    want(re.search(r"^S_X\s+38\b", g("cd"), re.M) and re.search(r"^T_U\s+V\s", g("cd"), re.M)
         and re.search(r"^6_7\s+TXT", g("cd"), re.M), "DIR in C:\\SUB does not list S_X, T_U.V and 6_7.TXT")
    want(re.search(r"^5FIVE\s+TXT", g("cd"), re.M) and not re.search(r"4FOUR\s+TXT", g("cd")),
         "DIR in C:\\SUB: 5FIVE.TXT copied from 4*.TXT, 4FOUR.TXT deleted")
    want("A file in a folder." in g("type"), "TYPE C:\\DOCS\\NOTE.TXT")
    want("Hello from ProDOS." in g("toA"), "the copy to A: does not read back")
    want("LASTDRIVE=Z" in g("toC") and "SHELL=" in g("toC"), "the copy to C: does not read back")
    want(re.search(r"ONE\s+TXT", g("cd")) and re.search(r"THREE\s+TXT", g("cd")),
         "DIR in C:\\SUB does not list ONE.TXT and THREE.TXT")
    want(not re.search(r"TWO\s+TXT", g("cd")), "TWO.TXT is still listed after REN")
    with open(os.path.join(ROOT, "tests", "expected", "fileops.out"), "rb") as f:
        exp = f.read().decode("cp437").replace("\r", "")
    want(exp.strip() in g("prog"), "FILEOPS.COM's output on C: is not tests/expected/fileops.out")
    want(re.search(r"THREE\s+TXT", g("after")) and not re.search(r"ONE\s+TXT", g("after")),
         "DIR SUB after DEL ONE.TXT")
    want(re.search(r"KEEP\s+TXT", g("after")) and re.search(r"HELLO\s+TXT", g("after")), "DIR *.TXT")
    m = re.search(r"([\d,]+) bytes free", g("dir"))
    free = int(m.group(1).replace(",", "")) if m else -1
    want(0 < free <= 32 << 20 and free % 512 == 0, f"DIR C: free space: {m.group(0) if m else 'none'}")
    want("GONE is still there" not in g("after"), "RD GONE left the directory")
    want("HELLO.TXT exists" in g("after"), "IF EXIST HELLO.TXT")
    want("NOPE.TXT exists" not in g("after"), "IF EXIST NOPE.TXT")
    want("a batch file on the drive" in g("bat"), "CALL T.BAT on the drive")
    want(re.search(r"one\s*\ntwo", g("bat")), "ECHO > and >> to a file on the drive")
    if basic:
        lines = [x.strip() for x in g("basic").replace("\x1a", "").split("\n") if x.strip() and "=>>" not in x]
        want(lines == ["line 1", "line 2", "line 3", "more", "Hello from ProDOS."],
             f"GW-BASIC's BAS2.OUT reads {lines}")

    # the ProDOS side
    out = os.path.join(work, "out")
    sh("rm", "-rf", out)
    os.makedirs(out)
    names = set(re.findall(r"^\s*(\S+?)\*?\s+(?:[A-Z0-9$]{3})\s", cat, re.M))
    for n in ("KEEP.TXT", "BIG.BIN", "SUB", "THREE.TXT", "HELLO.TXT") + (("BAS2.OUT",) if basic else ()):
        want(re.search(rf"\b{re.escape(n)}\b", cat), f"the volume has no {n}")
    for n in ("ONE.TXT", "TWO.TXT", "GONE", "T1.TMP", "T2.TMP", "TMP.OUT", "BAS.OUT"):
        want(not re.search(rf"\b{re.escape(n)}\b", cat), f"the volume still has {n}")
    same = [("KEEP.TXT", os.path.join(work, "FDCONFIG.SYS")), ("BIG.BIN", os.path.join(FD, "COMMAND.COM")),
            ("SUB/THREE.TXT", os.path.join(work, "FDCONFIG.SYS")),
            ("SUB/X..5FIVE.TXT", os.path.join(work, "FDCONFIG.SYS")), ("SUB/S.X.", os.path.join(work, "FDCONFIG.SYS")),
            ("SUB/T.U.V", os.path.join(work, "FDCONFIG.SYS")), ("SUB/X..6.7.TXT", os.path.join(work, "FDCONFIG.SYS"))] + ([("GW.EXE", GW)] if basic else [])
    for pd, ref in same:
        r2 = subprocess.run([CADIUS, "EXTRACTFILE", po, f"{share}/{pd}", out + "/", "--quiet"],
                            capture_output=True, text=True)
        got = [f for f in os.listdir(out) if f.startswith(os.path.basename(pd))]
        if r2.returncode or not got:
            bad.append(f"cadius cannot extract {pd}")
            continue
        with open(os.path.join(out, got[0]), "rb") as f, open(ref, "rb") as h:
            want(f.read() == h.read(), f"{pd} on the volume differs from {os.path.basename(ref)}")
        os.remove(os.path.join(out, got[0]))
    if bad:
        print("FAIL share:")
        for b in bad:
            print("  " + b)
        print(f"  output: {os.path.join(work, 'share.out')}  screen: {os.path.join(work, 'share.png')}")
        sys.exit(1)
    print(("PASS share, booted from the folder: " if boot else "PASS share: ") + "DIR, TYPE, COPY both ways, MD/CD/REN/DEL/RD, a program on C:, "
          + ("GW-BASIC files, " if basic else "") + "and the files on the ProDOS volume")


if __name__ == "__main__":
    main()
