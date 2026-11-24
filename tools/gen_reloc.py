#!/usr/bin/env python3
"""Make an image relocatable: find the bytes that hold a bank or a
bank-$00 page of the layout, append the list.

    gen_reloc.py LINK BIN OUT        LINK is core, svc, jit or sys

CORE and SVC are assembled for the banks and the bank-$00 pages in
src/include/layout.s, and the front end may put any of them somewhere
else (docs/relocation.md). Every byte of an image that holds a region's
bank number, or the high byte of an address in a bank-$00 area, then
needs (actual - assembled) added. This finds those bytes without reading
the source: it assembles the link four more times from a copy of src/
whose layout.s has each place moved by its own amount, and compares.

    bank A   region r's bank moved by 1 << r          (1, 2, 4, ...)
    bank B   by BANK_B[r]                             (3, 5, 7, ...)
    page A   area p's page moved by 1 << p            (1, 2, 4, ...)
    page B   by PAGE_B[p]                             (3, 5, 7, ...)

A byte that differs from BIN must differ by exactly one place's amount
in A and by the same place's amount in B, and in the bank pair or the
page pair, not both. Anything else -- a length change, a byte that
follows two places (a difference of banks), twice a bank, a bank used as
more than one byte -- is something the loader's byte-add cannot fix, and
fails the build with the offsets.

OUT is BIN followed by

    groups   one per place used: RG_ index (u8), assembled bank or page
             (u8), count (u16), count offsets (u16) into the image
    u16      bytes of groups
    u16      RELOC_MAGIC

read backwards from the end of the file by the loader's reloc_image.

sys is XTGS.SYSTEM itself (src/sys/xtgs.s), which has one thing to move:
its own front page (MBX: the file-call entry and the mailbox), for the
'+' test layout. Its list keeps the MBX bytes only -- the banks and the
other pages in the loader are the assembled layout, tables it relocates
the others from -- and the file's length goes into the image at
MB_SELFLEN, for the loader to find the list by.
"""
import os
import shutil
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import layout  # noqa: E402

BANK_B = [3, 5, 7, 11, 48, 13, 17]      # the guest's stays 1 MiB-aligned
PAGE_B = [3, 5, 7, 11, 13]
LINKS = {"core": ("core", "core"), "svc": ("svc", "svc"), "jit": ("jit", "jit"), "sys": ("sys", "xtgs")}  # directory, name
SYS_PAGE = 0x20                         # ProDOS 8 loads a SYS file at $2000


def assemble(link, tag, moved):
    """The link's image with layout.s's places at moved[name]."""
    sub, name = LINKS[link]
    work = os.path.join(ROOT, "build", "reloc", f"{link}_{tag}")
    shutil.rmtree(work, ignore_errors=True)
    shutil.copytree(os.path.join(ROOT, "src"), os.path.join(work, "src"))
    path = os.path.join(work, "src", "include", "layout.s")
    seen = set()

    def move(m):
        seen.add(m.group(1))
        return f"{m.group(1)}_{m.group(2)}{m.group(3)}${moved[m.group(1)]:02X}"
    with open(path) as f:
        text = layout.PLACE_LINE.sub(move, f.read())
    if seen != set(moved):
        sys.exit(f"gen_reloc: could not rewrite {sorted(set(moved) - seen)} in layout.s")
    with open(path, "w") as f:
        f.write(text)
    src = os.path.join(work, "src", sub)
    out = os.path.join(src, name)
    if os.path.exists(out):
        os.unlink(out)
    p = subprocess.run(["merlin32", "-V", f"{name}.s"], cwd=src, capture_output=True, text=True)
    if p.returncode or not os.path.exists(out):
        sys.exit(f"gen_reloc: merlin32 failed on the moved {link} ({tag}):\n{p.stdout[-1500:]}")
    with open(out, "rb") as f:
        return f.read()


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in LINKS:
        sys.exit(__doc__)
    link, bin_path, out_path = sys.argv[1:]
    regions = layout.regions()                       # name -> (id, assembled bank or page)
    names = {rid: name for name, (rid, _) in regions.items()}
    asm = {name: val for name, (_, val) in regions.items()}
    with open(bin_path, "rb") as f:
        base = f.read()

    # each kind's places in RG_ order, and its two sets of amounts
    kinds = []
    for what, is_page, b_amounts in (("bank", False, BANK_B), ("page", True, PAGE_B)):
        rids = sorted(rid for rid, n in names.items() if (n in layout.PAGES) == is_page)
        if len(rids) > len(b_amounts):
            sys.exit(f"gen_reloc: more {what}s than there are amounts for")
        if what == "bank" and link == "sys":
            continue
        kinds.append((what, rids, [1 << i for i in range(len(rids))], b_amounts[:len(rids)]))

    groups, bad = {}, []
    claimed = {}                                     # offset -> kind, to catch a byte in both
    for what, rids, a_amt, b_amt in kinds:
        imgs = []
        for tag, amounts in (("a", a_amt), ("b", b_amt)):
            moved = dict(asm)
            for rid, d in zip(rids, amounts):
                moved[names[rid]] = asm[names[rid]] + d
            imgs.append(assemble(link, f"{what}_{tag}", moved))
        va, vb = imgs
        if len(va) != len(base) or len(vb) != len(base):
            sys.exit(f"gen_reloc: {link} changes length when its {what}s move "
                     f"({len(base)}, {len(va)}, {len(vb)}): a {what} decides the code's shape")
        for off, (x, a, b) in enumerate(zip(base, va, vb)):
            da, db = (a - x) & 0xFF, (b - x) & 0xFF
            if not da and not db:
                continue
            i = a_amt.index(da) if da in a_amt else None
            if i is None or db != b_amt[i] or off in claimed:
                bad.append(f"  ${off:04X}: {x:02X} -> {a:02X} / {b:02X} ({what}s moved"
                           + (f"; also follows a {claimed[off]}" if off in claimed else "") + ")")
                continue
            claimed[off] = what
            groups.setdefault(rids[i], []).append(off)
    if bad:
        sys.exit(f"gen_reloc: {link} has {len(bad)} bytes that do not follow one bank or one page "
                 f"(offset: assembled -> variant A / B; see build/{LINKS[link][1]}.lst):\n"
                 + "\n".join(bad[:40]))

    if link == "sys":
        mbx = regions["MBX"][0]
        if asm["MBX"] != SYS_PAGE:
            sys.exit(f"gen_reloc: MBX_PAGE is ${asm['MBX']:02X}, but XTGS.SYSTEM's front page is "
                     f"its first, and ProDOS 8 loads it at ${SYS_PAGE:02X}00")
        groups = {mbx: groups[mbx]} if mbx in groups else {}

    body = b""
    for rid in sorted(groups):
        offs = groups[rid]
        body += struct.pack("<BBH", rid, asm[names[rid]], len(offs))
        body += struct.pack(f"<{len(offs)}H", *offs)
    image = base + body + struct.pack("<HH", len(body), layout.equates()["RELOC_MAGIC"])
    if link == "sys":
        mb = layout.mailbox()
        at = mb["MB_SELFLEN"] - mb["MB_BASE"]
        if image[at:at + 2] != b"\0\0":
            sys.exit(f"gen_reloc: XTGS.SYSTEM has something at +${at:02X}, where its length goes")
        image = image[:at] + struct.pack("<H", len(image)) + image[at + 2:]
    if len(image) > (0x2000 if link == "sys" else 0x10000):
        sys.exit(f"gen_reloc: {link} with its list is {len(image)} bytes, more than "
                 + ("the loader's 8 KB" if link == "sys" else "a bank"))
    with open(out_path, "wb") as f:
        f.write(image)
    count = sum(map(len, groups.values()))
    print(f"gen_reloc: {link}: {count} bytes ("
          + ", ".join(f"{names[r].lower()} {len(groups[r])}" for r in sorted(groups))
          + f"), {len(image) - len(base)} bytes appended")


if __name__ == "__main__":
    main()
