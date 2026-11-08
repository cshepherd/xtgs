#!/usr/bin/env python3
"""Try candidate algorithms for DAA/DAS/AAA/AAS against the suite's
vectors, to learn the 8088's exact rules before writing them in 65816."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vectors

CF, PF, AF, ZF, SF, OF = 1, 4, 0x10, 0x40, 0x80, 0x800


def szp(al):
    f = 0
    if al == 0: f |= ZF
    if al & 0x80: f |= SF
    if bin(al).count("1") % 2 == 0: f |= PF
    return f


def daa_v1(al, fl):          # Intel pseudo-code (286+ wording): final CF cleared otherwise
    old_al, old_cf = al, fl & CF
    f = fl & ~(CF | AF)
    if (al & 0xF) > 9 or fl & AF:
        al = (al + 6) & 0xFF
        if old_al + 6 > 0xFF or old_cf: f |= CF
        f |= AF
    if old_al > 0x99 or old_cf:
        al = (al + 0x60) & 0xFF
        f |= CF
    else:
        f &= ~CF
    return al, f


def daa_v2(al, fl):          # as written in ops_grp.s: step-1 carry sets CF, no clearing in step 2
    old_al, old_cf = al, fl & CF
    f = fl & ~(CF | AF)
    if (al & 0xF) > 9 or fl & AF:
        al = (al + 6) & 0xFF
        if old_al + 6 > 0xFF: f |= CF
        f |= AF
    if old_al > 0x99 or old_cf:
        al = (al + 0x60) & 0xFF
        f |= CF
    return al, f


def daa_v3(al, fl):          # second test on the adjusted AL, threshold 9F, old CF
    old_cf = fl & CF
    f = fl & ~(CF | AF)
    if (al & 0xF) > 9 or fl & AF:
        c = al + 6 > 0xFF
        al = (al + 6) & 0xFF
        f |= AF
        if c: f |= CF
    if al > 0x9F or old_cf or f & CF:
        al = (al + 0x60) & 0xFF
        f |= CF
    return al, f


def daa_v4(al, fl):          # like v1 but keep step-1 carry (no else-clear)
    old_al, old_cf = al, fl & CF
    f = fl & ~(CF | AF)
    if (al & 0xF) > 9 or fl & AF:
        c = old_al + 6 > 0xFF
        al = (al + 6) & 0xFF
        f |= AF
        if c or old_cf: f |= CF
    if old_al > 0x99 or old_cf:
        al = (al + 0x60) & 0xFF
        f |= CF
    return al, f


def das_v1(al, fl):
    old_al, old_cf = al, fl & CF
    f = fl & ~(CF | AF)
    if (al & 0xF) > 9 or fl & AF:
        b = al < 6
        al = (al - 6) & 0xFF
        if b or old_cf: f |= CF
        f |= AF
    if old_al > 0x99 or old_cf:
        al = (al - 0x60) & 0xFF
        f |= CF
    else:
        f &= ~CF
    return al, f


def das_v2(al, fl):          # as written: borrow sets CF; step 2 no clear
    old_al, old_cf = al, fl & CF
    f = fl & ~(CF | AF)
    if (al & 0xF) > 9 or fl & AF:
        b = al < 6
        al = (al - 6) & 0xFF
        if b: f |= CF
        f |= AF
    if old_al > 0x99 or old_cf:
        al = (al - 0x60) & 0xFF
        f |= CF
    return al, f


def das_v4(al, fl):          # keep step-1 borrow|old_cf, no else-clear
    old_al, old_cf = al, fl & CF
    f = fl & ~(CF | AF)
    if (al & 0xF) > 9 or fl & AF:
        b = al < 6
        al = (al - 6) & 0xFF
        if b or old_cf: f |= CF
        f |= AF
    if old_al > 0x99 or old_cf:
        al = (al - 0x60) & 0xFF
        f |= CF
    return al, f


def aaa_v1(ax, fl):          # AL+6 (8-bit), AH+1, mask
    al, ah = ax & 0xFF, ax >> 8
    f = fl & ~(CF | AF)
    if (al & 0xF) > 9 or fl & AF:
        al = (al + 6) & 0xFF
        ah = (ah + 1) & 0xFF
        f |= CF | AF
    al &= 0x0F
    return (ah << 8) | al, f


def aaa_v2(ax, fl):          # AX + 0x106 (16-bit), mask
    f = fl & ~(CF | AF)
    if (ax & 0xF) > 9 or fl & AF:
        ax = (ax + 0x106) & 0xFFFF
        f |= CF | AF
    return ax & 0xFF0F, f


def aaa_v3(ax, fl):          # AL += 6 then mask, AH += 1; but SZP from AL before mask?
    return aaa_v1(ax, fl)


def aas_v1(ax, fl):
    al, ah = ax & 0xFF, ax >> 8
    f = fl & ~(CF | AF)
    if (al & 0xF) > 9 or fl & AF:
        al = (al - 6) & 0xFF
        ah = (ah - 1) & 0xFF
        f |= CF | AF
    al &= 0x0F
    return (ah << 8) | al, f


def aas_v2(ax, fl):
    f = fl & ~(CF | AF)
    if (ax & 0xF) > 9 or fl & AF:
        ax = (ax - 0x106) & 0xFFFF
        f |= CF | AF
    return ax & 0xFF0F, f


def check(op, variants, kind):
    meta = vectors.metadata()
    tests = vectors.collect([op], meta=meta)
    mask = vectors.flags_mask(tests[0][1], meta)
    for name, fn in variants:
        bad = 0
        examples = []
        for _n, t in tests:
            init = t["initial"]["regs"]
            exp = vectors.final_regs(t)
            ax, fl = init["ax"], init["flags"]
            if kind == "al":
                al, f = fn(ax & 0xFF, fl)
                f = (f & ~(SF | ZF | PF)) | szp(al)
                got_ax = (ax & 0xFF00) | al
            else:
                got_ax, f = fn(ax, fl)
                f = (f & ~(SF | ZF | PF)) | szp(got_ax & 0xFF)
            f |= 0xF002
            ok = got_ax == exp["ax"] and (f ^ exp["flags"]) & mask == 0
            if not ok:
                bad += 1
                if len(examples) < 4:
                    examples.append((init["ax"], init["flags"], exp["ax"], exp["flags"], got_ax, f))
        print(f"{op} {name:8s} {len(tests) - bad:5d}/{len(tests)} ok, mask {mask:04X}")
        for ax, fl, eax, efl, gax, gf in examples:
            print(f"      AX {ax:04X} FL {fl:04X} -> expected AX {eax:04X} FL {efl:04X}, got AX {gax:04X} FL {gf:04X}")


check("27", [("v1", daa_v1), ("v2", daa_v2), ("v3", daa_v3), ("v4", daa_v4)], "al")
check("2F", [("v1", das_v1), ("v2", das_v2), ("v4", das_v4)], "al")
check("37", [("v1", aaa_v1), ("v2", aaa_v2)], "ax")
check("3F", [("v1", aas_v1), ("v2", aas_v2)], "ax")
