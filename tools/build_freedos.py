#!/usr/bin/env python3
"""Build FreeDOS for Mode B, reproducibly: the folder DOS boots from (the S
command, docs/share.md) and the boot floppy image (the D command).

    build_freedos.py            -> third_party/freedos/fd/SHARED/
                                   third_party/freedos/fd/freedos.img

Needs the FreeDOS kernel, shell and boot-sector source fetched by
tools/fetch_dos.py (kernel.zip, freecom.zip), and nasm. The folder holds
KERNEL.SYS (the 8086 kernel KERNL86.SYS), COMMAND.COM, SETVER.SYS, an
FDCONFIG.SYS that names them on C:, the demo .BAS files, EGADEMO.COM and
TDYDEMO.COM (tests/demo/egademo.asm, tdydemo.asm) and GW-BASIC when it is there, each under cadius's NAME#TTAAAA name: tools/make_image.sh
takes the folder as it is. The floppy has the same files, named on A:,
behind the FreeDOS FAT12 boot sector (tools/make_fat12.py).
"""
import os
import shutil
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FD = os.path.join(ROOT, "third_party", "freedos")
OUT = os.path.join(FD, "fd")


def need(path, msg):
    if not os.path.exists(path):
        sys.exit(f"missing {path}\n{msg}")


def main():
    os.makedirs(OUT, exist_ok=True)
    need(os.path.join(FD, "kernel.zip"), "run tools/fetch_dos.py (and add kernel/freecom)")
    need(os.path.join(FD, "freecom.zip"), "run tools/fetch_dos.py")
    k = zipfile.ZipFile(os.path.join(FD, "kernel.zip"))
    open(os.path.join(OUT, "KERNEL.SYS"), "wb").write(k.read("BIN/KERNL86.SYS"))
    open(os.path.join(OUT, "SOURCES.ZIP"), "wb").write(k.read("SOURCE/KERNEL/SOURCES.ZIP"))
    open(os.path.join(OUT, "SETVER.SYS"), "wb").write(k.read("BIN/SETVER.SYS"))
    c = zipfile.ZipFile(os.path.join(FD, "freecom.zip"))
    open(os.path.join(OUT, "COMMAND.COM"), "wb").write(c.read("BIN/COMMAND.COM"))
    sz = zipfile.ZipFile(os.path.join(OUT, "SOURCES.ZIP"))
    open(os.path.join(OUT, "boot.asm"), "wb").write(sz.read("boot/boot.asm"))
    subprocess.run(["nasm", "-dISFAT12", "-f", "bin", "-o", os.path.join(OUT, "boot.bin"),
                    os.path.join(OUT, "boot.asm")], check=True)
    with open(os.path.join(OUT, "FDCONFIG.SYS"), "w", newline="\r\n") as f:
        f.write("LASTDRIVE=Z\nDEVICE=A:\\SETVER.SYS\nSHELL=A:\\COMMAND.COM /P\n")
    # A short BASIC program GW-BASIC loads and runs, then exits to DOS. A
    # headless boot then proves GW-BASIC launched, rendered (its direct B800
    # writes) and ran guest BASIC, without needing interactive keystrokes.
    with open(os.path.join(OUT, "HELLO.BAS"), "w", newline="\r\n") as f:
        f.write('10 PRINT "HELLO FROM GW-BASIC 3.23 ON XT/GS"\n'
                '20 PRINT "2 + 2 ="; 2 + 2\n'
                '30 SYSTEM\n')
    # CGA 320x200 graphics (SCREEN 1) demo. Loops at the end so a headless
    # boot can screenshot the drawn frame.
    with open(os.path.join(OUT, "CGADEMO.BAS"), "w", newline="\r\n") as f:
        f.write('10 SCREEN 1\n'
                '20 CLS\n'
                '30 LINE (0,0)-(319,199),1\n'
                '40 LINE (319,0)-(0,199),2\n'
                '50 LINE (40,30)-(279,170),3,B\n'
                '60 CIRCLE (160,100),70,3\n'
                '70 A$=INPUT$(1)\n'
                '80 SCREEN 0:SYSTEM\n')
    # The EGA's 320x200 16-colour mode (docs/ega.md): EGADEMO.COM is ours
    # (tests/demo/egademo.asm) and runs as it is; EGADEMO.BAS is SCREEN 7,
    # which the GW-BASIC rebuilt from the 1983 source does not have.
    subprocess.run(["nasm", "-f", "bin", "-o", os.path.join(OUT, "EGADEMO.COM"),
                    os.path.join(ROOT, "tests", "demo", "egademo.asm")], check=True)
    # A Tandy 1000's mode 09h (docs/tandy.md): for a PC that XTGS.CMD's
    # VIDEO=TANDY makes; anywhere else it says so and ends.
    subprocess.run(["nasm", "-f", "bin", "-o", os.path.join(OUT, "TDYDEMO.COM"),
                    os.path.join(ROOT, "tests", "demo", "tdydemo.asm")], check=True)
    with open(os.path.join(OUT, "EGADEMO.BAS"), "w", newline="\r\n") as f:
        f.write('10 REM SCREEN 7 needs a GW-BASIC with the EGA modes (Microsoft 3.2x)\n'
                '20 SCREEN 7\n'
                '30 FOR C=0 TO 15:LINE (C*20,24)-(C*20+19,95),C,BF:NEXT\n'
                '40 CIRCLE (160,145),45,14:PAINT (160,145),4,14\n'
                '50 LOCATE 2,6:PRINT "XT/GS: EGA 320x200, 16 colours"\n'
                '60 A$=INPUT$(1)\n'
                '70 SCREEN 0:SYSTEM\n')
    # No AUTOEXEC.BAT: FreeDOS boots straight to the A:\ prompt. GWBASIC.EXE
    # and the demo .BAS files are on the volume to run by hand.
    # GW-BASIC 3.23 (third_party/gwbasic/, not fetched by fetch_dos.py); added
    # only if present so the FreeDOS image still builds without it.
    gwbasic = os.path.join(ROOT, "third_party", "gwbasic", "GWBASIC.EXE")
    files = [
        "KERNEL.SYS=" + os.path.join(OUT, "KERNEL.SYS"),
        "SETVER.SYS=" + os.path.join(OUT, "SETVER.SYS"),
        "COMMAND.COM=" + os.path.join(OUT, "COMMAND.COM"),
        "FDCONFIG.SYS=" + os.path.join(OUT, "FDCONFIG.SYS"),
        "HELLO.BAS=" + os.path.join(OUT, "HELLO.BAS"),
        "CGADEMO.BAS=" + os.path.join(OUT, "CGADEMO.BAS"),
        "EGADEMO.BAS=" + os.path.join(OUT, "EGADEMO.BAS"),
        "EGADEMO.COM=" + os.path.join(OUT, "EGADEMO.COM"),
        "TDYDEMO.COM=" + os.path.join(OUT, "TDYDEMO.COM"),
    ]
    if os.path.exists(gwbasic):
        files.append("GWBASIC.EXE=" + gwbasic)
    else:
        print("note: " + gwbasic + " absent; image built without GW-BASIC")
    # The folder: the same files for a ProDOS volume, DOS's drive C:.
    shared = os.path.join(OUT, "SHARED")
    shutil.rmtree(shared, ignore_errors=True)
    os.makedirs(shared)
    for f in files:
        name, path = f.split("=", 1)
        with open(path, "rb") as g:
            data = g.read()
        if name == "FDCONFIG.SYS":
            data = data.replace(b"A:\\", b"C:\\")
        text = name.endswith((".SYS", ".BAS")) and name not in ("KERNEL.SYS", "SETVER.SYS")
        with open(os.path.join(shared, name + ("#040000" if text else "#060000")), "wb") as g:
            g.write(data)
    print(f"built {shared}")
    img = os.path.join(OUT, "freedos.img")
    subprocess.run([sys.executable, "-I", os.path.join(HERE, "make_fat12.py"),
                    os.path.join(OUT, "boot.bin"), img] + files, check=True)
    print(f"built {img}")


if __name__ == "__main__":
    main()
