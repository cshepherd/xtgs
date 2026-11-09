#!/usr/bin/env python3
"""Build the FreeDOS boot floppy image for Mode B, reproducibly.

    build_freedos.py            -> third_party/freedos/fd/freedos.img

Needs the FreeDOS kernel, shell and boot-sector source fetched by
tools/fetch_dos.py (kernel.zip, freecom.zip), and nasm. Assembles the
FreeDOS FAT12 boot sector, then lays down KERNEL.SYS (the 8086 kernel
KERNL86.SYS), COMMAND.COM, FDCONFIG.SYS and AUTOEXEC.BAT with
tools/make_fat12.py.
"""
import os
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
    ]
    if os.path.exists(gwbasic):
        files.append("GWBASIC.EXE=" + gwbasic)
    else:
        print("note: " + gwbasic + " absent; image built without GW-BASIC")
    img = os.path.join(OUT, "freedos.img")
    subprocess.run([sys.executable, "-I", os.path.join(HERE, "make_fat12.py"),
                    os.path.join(OUT, "boot.bin"), img] + files, check=True)
    print(f"built {img}")


if __name__ == "__main__":
    main()
