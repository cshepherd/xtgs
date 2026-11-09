#!/usr/bin/env python3
"""Build a 1.44 MB FAT12 boot floppy image from the FreeDOS boot sector,
kernel and shell (no mtools needed).

    make_fat12.py BOOT.BIN OUT.IMG NAME=FILE [NAME=FILE ...]

BOOT.BIN is the assembled FreeDOS FAT12 boot sector; its BPB (0x0B-0x3D)
is filled here for a standard 1.44 MB floppy and its boot code kept. Each
NAME=FILE adds a root-directory file (NAME is an 8.3 DOS name). The kernel
must be named KERNEL.SYS (the boot sector searches for "KERNEL  SYS").
"""
import os
import struct
import sys

SECTOR = 512
TOTAL_SECTORS = 2880
RESERVED = 1
NFATS = 2
SEC_PER_FAT = 9
ROOT_ENTS = 224
ROOT_SECS = ROOT_ENTS * 32 // SECTOR          # 14
FAT_START = RESERVED                           # sector 1
ROOT_START = RESERVED + NFATS * SEC_PER_FAT    # sector 19
DATA_START = ROOT_START + ROOT_SECS            # sector 33 -> cluster 2


def bpb(boot):
    b = bytearray(boot)
    b[0x03:0x0B] = b"FRDOS5.1"
    struct.pack_into("<H", b, 0x0B, SECTOR)
    b[0x0D] = 1                                 # sectors/cluster
    struct.pack_into("<H", b, 0x0E, RESERVED)
    b[0x10] = NFATS
    struct.pack_into("<H", b, 0x11, ROOT_ENTS)
    struct.pack_into("<H", b, 0x13, TOTAL_SECTORS)
    b[0x15] = 0xF0                              # media descriptor
    struct.pack_into("<H", b, 0x16, SEC_PER_FAT)
    struct.pack_into("<H", b, 0x18, 18)         # sectors/track
    struct.pack_into("<H", b, 0x1A, 2)          # heads
    struct.pack_into("<I", b, 0x1C, 0)          # hidden
    struct.pack_into("<I", b, 0x20, 0)          # large total
    b[0x24] = 0                                 # drive number (A:)
    b[0x25] = 0
    b[0x26] = 0x29                              # extended boot signature
    struct.pack_into("<I", b, 0x27, 0x1C0FFEE5) # volume serial
    b[0x2B:0x36] = b"FREEDOS    "
    b[0x36:0x3E] = b"FAT12   "
    b[0x1FE] = 0x55
    b[0x1FF] = 0xAA
    return bytes(b)


def dosname(name):
    base, _, ext = name.upper().partition(".")
    return (base[:8].ljust(8) + ext[:3].ljust(3)).encode("ascii")


def set_fat12(fat, cluster, value):
    off = cluster * 3 // 2
    if cluster & 1:
        fat[off] = (fat[off] & 0x0F) | ((value << 4) & 0xF0)
        fat[off + 1] = (value >> 4) & 0xFF
    else:
        fat[off] = value & 0xFF
        fat[off + 1] = (fat[off + 1] & 0xF0) | ((value >> 8) & 0x0F)


def main():
    boot = open(sys.argv[1], "rb").read()
    out = sys.argv[2]
    files = [a.split("=", 1) for a in sys.argv[3:]]

    image = bytearray(TOTAL_SECTORS * SECTOR)
    image[0:SECTOR] = bpb(boot)

    fat = bytearray(SEC_PER_FAT * SECTOR)
    fat[0] = 0xF0
    fat[1] = 0xFF
    fat[2] = 0xFF
    next_cluster = 2
    root = bytearray()

    for name, path in files:
        data = open(path, "rb").read()
        nclust = max(1, (len(data) + SECTOR - 1) // SECTOR)
        first = next_cluster
        for i in range(nclust):
            c = first + i
            sec = DATA_START + (c - 2)
            chunk = data[i * SECTOR:(i + 1) * SECTOR]
            image[sec * SECTOR:sec * SECTOR + len(chunk)] = chunk
            set_fat12(fat, c, 0xFFF if i == nclust - 1 else c + 1)
        next_cluster += nclust
        ent = bytearray(32)
        ent[0:11] = dosname(name)
        ent[0x0B] = 0x20                         # archive
        struct.pack_into("<H", ent, 0x1A, first)
        struct.pack_into("<I", ent, 0x1C, len(data))
        struct.pack_into("<H", ent, 0x16, 0x0021)  # time
        struct.pack_into("<H", ent, 0x18, 0x5461)  # date 2022-03-01
        root += ent
        print(f"  {name:12s} {len(data):7d} bytes, clusters {first}..{next_cluster-1}")

    for i in range(NFATS):
        s = (FAT_START + i * SEC_PER_FAT) * SECTOR
        image[s:s + len(fat)] = fat
    rs = ROOT_START * SECTOR
    image[rs:rs + len(root)] = root

    with open(out, "wb") as f:
        f.write(image)
    print(f"{out}: {len(image)} bytes, {next_cluster-2} data clusters used")


if __name__ == "__main__":
    main()
