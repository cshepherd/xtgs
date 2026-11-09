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
    c = zipfile.ZipFile(os.path.join(FD, "freecom.zip"))
    open(os.path.join(OUT, "COMMAND.COM"), "wb").write(c.read("BIN/COMMAND.COM"))
    sz = zipfile.ZipFile(os.path.join(OUT, "SOURCES.ZIP"))
    open(os.path.join(OUT, "boot.asm"), "wb").write(sz.read("boot/boot.asm"))
    subprocess.run(["nasm", "-dISFAT12", "-f", "bin", "-o", os.path.join(OUT, "boot.bin"),
                    os.path.join(OUT, "boot.asm")], check=True)
    with open(os.path.join(OUT, "FDCONFIG.SYS"), "w", newline="\r\n") as f:
        f.write("LASTDRIVE=Z\nSHELL=A:\\COMMAND.COM /P\n")
    with open(os.path.join(OUT, "AUTOEXEC.BAT"), "w", newline="\r\n") as f:
        f.write("@ECHO OFF\nECHO XT/GS: FreeDOS booted.\nVER\n")
    img = os.path.join(OUT, "freedos.img")
    subprocess.run([sys.executable, "-I", os.path.join(HERE, "make_fat12.py"),
                    os.path.join(OUT, "boot.bin"), img,
                    "KERNEL.SYS=" + os.path.join(OUT, "KERNEL.SYS"),
                    "COMMAND.COM=" + os.path.join(OUT, "COMMAND.COM"),
                    "FDCONFIG.SYS=" + os.path.join(OUT, "FDCONFIG.SYS"),
                    "AUTOEXEC.BAT=" + os.path.join(OUT, "AUTOEXEC.BAT")], check=True)
    print(f"built {img}")


if __name__ == "__main__":
    main()
