#!/usr/bin/env python3
"""Pack SingleStepTests 8088 (v2) vectors for tests/cpu/harness.s.

    vectors.py --op 00 [--op 80.3 ...] [--count N] [--skip K] -o VEC

An --op is an opcode ("00") or a group sub-opcode ("80.3"); a bare group
opcode expands to every sub-opcode the metadata does not mark undefined.
Files are fetched into third_party/8088/v2/ on first use.

Record (little-endian):
    u16 reclen; u16 regs[14] (AX CX DX BX SP BP SI DI ES CS SS DS IP FLAGS);
    u16 xregs[14]; u16 mask; u16 nram; u16 nxram;
    {u16 lo, u8 bank, u8 val} x nram; the same x nxram.
A zero reclen ends the list.

Excluded (tests/cpu/EXCLUDE.md): FE /7, which XT/GS uses as its hypercall.
"""
import argparse
import gzip
import json
import os
import struct
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SUITE = os.path.join(ROOT, "third_party", "8088")
V2 = os.path.join(SUITE, "v2")
URL = "https://raw.githubusercontent.com/SingleStepTests/8088/main/v2/{}.json.gz"
REGS = ["ax", "cx", "dx", "bx", "sp", "bp", "si", "di", "es", "cs", "ss", "ds", "ip", "flags"]
PREFIXES = {0x26, 0x2E, 0x36, 0x3E, 0xF0, 0xF1, 0xF2, 0xF3}


def metadata():
    with open(os.path.join(SUITE, "v2_metadata.json")) as f:
        return json.load(f)["opcodes"]


def files_for(op, meta):
    op = op.upper()
    if "." in op:
        return [op]
    entry = meta.get(op, {})
    if "reg" in entry:
        return [f"{op}.{r}" for r, v in sorted(entry["reg"].items()) if v.get("status") != "undefined"]
    return [op]


def fetch(name):
    os.makedirs(V2, exist_ok=True)
    path = os.path.join(V2, f"{name}.json.gz")
    if not os.path.exists(path):
        try:
            with urllib.request.urlopen(URL.format(name), timeout=60) as r, open(path + ".part", "wb") as f:
                f.write(r.read())
            os.replace(path + ".part", path)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            raise
    return path


def load(name):
    path = fetch(name)
    if path is None:
        return []
    with gzip.open(path) as f:
        return json.load(f)


def opcode_of(test):
    """(opcode, modrm or None) after any prefixes."""
    bs = test["bytes"]
    i = 0
    while i < len(bs) and bs[i] in PREFIXES:
        i += 1
    op = bs[i]
    modrm = bs[i + 1] if i + 1 < len(bs) else None
    return op, modrm


def flags_mask(test, meta):
    op, modrm = opcode_of(test)
    entry = meta.get(f"{op:02X}", {})
    if "reg" in entry and modrm is not None:
        entry = entry["reg"].get(str((modrm >> 3) & 7), {})
    return entry.get("flags-mask", 0xFFFF)


def excluded(test):
    op, modrm = opcode_of(test)
    if op == 0xFE and modrm is not None and (modrm & 0x38) == 0x38:
        return "FE /7 is the XT/GS hypercall"
    regs = test["initial"]["regs"]
    if (regs["cs"] << 4) + regs["ip"] + len(test["bytes"]) > 0x100000:
        return "instruction bytes cross the 1 MiB wrap"
    addrs = {a for a, _v in test["initial"]["ram"]} | {a for a, _v in test["final"]["ram"]}
    if 0xFFFFF in addrs and 0 in addrs:
        return "a data word straddles the 1 MiB wrap"
    return None


def final_regs(test):
    regs = dict(test["initial"]["regs"])
    regs.update(test["final"]["regs"])
    return regs


def pack_one(test, mask):
    init = test["initial"]["regs"]
    fin = final_regs(test)
    ram = {}
    for addr, val in test["initial"]["ram"]:
        ram[addr] = val
    xram = {}
    for addr, val in test["final"]["ram"]:
        xram[addr] = val
    body = struct.pack("<14H", *[init[r] for r in REGS])
    body += struct.pack("<14H", *[fin[r] for r in REGS])
    body += struct.pack("<HHH", mask, len(ram), len(xram))
    for table in (ram, xram):
        for addr, val in table.items():
            body += struct.pack("<HBB", addr & 0xFFFF, (addr >> 16) & 0xF, val)
    return struct.pack("<H", len(body) + 2) + body


def collect(ops, count=None, skip=0, meta=None):
    """[(file, test)] for the ops, excluded ones dropped, as packed."""
    meta = meta or metadata()
    tests = []
    for op in ops:
        names = files_for(op, meta)
        loaded = [(name, load(name)) for name in names]
        if not any(ts for _n, ts in loaded) and "." not in op:
            loaded = [(op.upper(), load(op.upper()))]   # a group file without a sub-index
        for name, ts in loaded:
            for t in ts:
                if excluded(t):
                    continue
                tests.append((name, t))
    tests = tests[skip:]
    if count is not None:
        tests = tests[:count]
    return tests


def pack(tests, meta=None):
    meta = meta or metadata()
    out = bytearray()
    for _name, t in tests:
        out += pack_one(t, flags_mask(t, meta))
    out += b"\0\0"
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--op", action="append", required=True)
    ap.add_argument("--count", type=int)
    ap.add_argument("--skip", type=int, default=0)
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()
    meta = metadata()
    tests = collect(args.op, args.count, args.skip, meta)
    data = pack(tests, meta)
    with open(args.output, "wb") as f:
        f.write(data)
    print(f"{len(tests)} vectors, {len(data)} bytes -> {args.output}")


if __name__ == "__main__":
    main()
