#!/usr/bin/env python3
"""What does the 8088 do on IDIV? Recover each vector's divisor from its
disassembly, then tabulate trap decisions by true quotient, and test
hypotheses for the FLAGS word pushed on the divide error."""
import re, sys, os
from collections import Counter, defaultdict
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vectors

CF, PF, AF, ZF, SF, OF = 1, 4, 0x10, 0x40, 0x80, 0x800
R16 = {"ax", "bx", "cx", "dx", "si", "di", "bp", "sp"}
R8 = {"al": ("ax", 0), "ah": ("ax", 8), "bl": ("bx", 0), "bh": ("bx", 8),
      "cl": ("cx", 0), "ch": ("cx", 8), "dl": ("dx", 0), "dh": ("dx", 8)}


def operand(t, bits):
    regs = t["initial"]["regs"]
    m = re.search(r"\[(\w\w):([^\]]+)\]", t["name"])
    if m:
        seg = regs[m.group(1)]
        off = 0
        for tok in re.findall(r"[+-]?[A-Za-z0-9]+", m.group(2)):
            sign = -1 if tok.startswith("-") else 1
            tok = tok.lstrip("+-")
            off += sign * (regs[tok.lower()] if tok.lower() in R16 else int(tok.rstrip("hH"), 16))
        phys = ((seg << 4) + (off & 0xFFFF)) & 0xFFFFF
        ram = dict(t["initial"]["ram"])
        v = ram[phys]
        if bits == 16:
            v |= ram[(phys + 1) & 0xFFFFF] << 8
        return v
    reg = t["name"].split()[-1].lower()
    if reg in R16:
        return regs[reg]
    r, sh = R8[reg]
    return (regs[r] >> sh) & 0xFF


def signed(v, bits):
    return v - (1 << bits) if v >> (bits - 1) else v


def sub_flags(a, b, bits):
    m = (1 << bits) - 1
    r = (a - b) & m
    f = 0
    if a < b: f |= CF
    if r == 0: f |= ZF
    if r >> (bits - 1): f |= SF
    if bin(r & 0xFF).count("1") % 2 == 0: f |= PF
    if (a ^ b ^ r) & 0x10: f |= AF
    if (a >> (bits - 1)) != (b >> (bits - 1)) and (r >> (bits - 1)) != (a >> (bits - 1)): f |= OF
    return f


def pushed_flags(t):
    fin = vectors.final_regs(t); ini = t["initial"]["regs"]
    addr = ((ini["ss"] << 4) + ((fin["sp"] + 4) & 0xFFFF)) & 0xFFFFF
    ram = dict(t["initial"]["ram"]); ram.update(dict(t["final"]["ram"]))
    return ram.get(addr, 0) | (ram.get(addr + 1, 0) << 8)


for op, bits in (("F6.7", 8), ("F7.7", 16)):
    tests = vectors.collect([op])
    lim = 1 << (bits - 1)
    cats = Counter()
    hyp = defaultdict(Counter)
    examples = defaultdict(list)
    for _n, t in tests:
        ini = t["initial"]["regs"]; fin = vectors.final_regs(t)
        trapped = fin["sp"] == (ini["sp"] - 6) & 0xFFFF
        d = operand(t, bits)
        ds = signed(d, bits)
        dividend = ini["ax"] if bits == 8 else (ini["dx"] << 16) | ini["ax"]
        dv = signed(dividend, 2 * bits)
        if ds == 0:
            cat = "div0"
        else:
            q = int(dv / ds)
            cat = ("q<-lim" if q < -lim else "q==-lim" if q == -lim else "q>lim-1" if q > lim - 1 else "fits")
        cats[(cat, "TRAP" if trapped else "ok")] += 1
        if trapped:
            pf = pushed_flags(t) & (CF | PF | AF | ZF | SF | OF)
            hi = (dividend >> bits) & ((1 << bits) - 1)
            absdv = abs(dv); absd = abs(ds)
            hi_abs = (absdv >> bits) & ((1 << bits) - 1)
            cands = {
                "cmp(hi,d)": sub_flags(hi, d, bits),
                "cmp(|hi|,|d|)": sub_flags(hi_abs, absd & ((1 << bits) - 1), bits),
                "neg(d)": sub_flags(0, d, bits),
                "neg(hi)": sub_flags(0, hi, bits),
                "neg(lo)": sub_flags(0, dividend & ((1 << bits) - 1), bits),
                "cmp(|hi|,|d|)|neg(d)": None,
            }
            for name, f in cands.items():
                if f is not None:
                    hyp[cat][name] += (f == pf)
            if len(examples[cat]) < 2:
                examples[cat].append((t["name"], f"AX={ini['ax']:04X}", f"DX={ini['dx']:04X}", f"d={d:X}", f"FL={ini['flags']:04X}", f"pushed={pushed_flags(t):04X}"))
    print(f"== {op} ==")
    for k in sorted(cats):
        print(f"   {k[0]:8s} {k[1]:5s} {cats[k]}")
    for cat, c in hyp.items():
        n = sum(v for (cc, tr), v in cats.items() if cc == cat and tr == "TRAP")
        print(f"   pushed flags for {cat} traps (n={n}): " + ", ".join(f"{h}={v}" for h, v in c.items()))
    for cat, ex in examples.items():
        for e in ex:
            print("     ", cat, e)
