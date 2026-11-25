#!/usr/bin/env python3
"""gen_fputest.py: writes tests/com/fpuops.asm and tests/expected/fpuops.out (docs/8087.md, M9.3), and
tests/com/fpuext.asm and tests/expected/fpuext.out (M9.4: the square root, the scale, the partial
remainder, the extraction, packed decimal, and the transcendentals), and tests/com/fpumd.asm and
tests/expected/fpumd.out (the multiply and divide done in the 8087's image instead of by SANE: random
operands in every direction and precision, ties, and the ranges where SANE takes over).

Each case is a few 8087 instructions; the program's report then prints the case's
number, ST(0) as FSTP TBYTE stores it (an empty register is the indefinite), the
status word stored before that, and eight bytes the case may have stored
(AA where it did not; ten bytes in fpuext). The expected line is worked out here in exact arithmetic
(Python's fractions) from Intel's 8087 manual, not from src/fpu: a difference is
a fault in one or the other, to be read in the manual.

A transcendental's last bits are not the 8087's to promise, nor SANE's: such a case
("near") is judged by the program itself against a 70-digit value, within 2^-56 of it,
with the instructions fpuops has judged exactly, and prints OK and its status word.

Run it again after changing a case: python3 -I tools/gen_fputest.py
"""
import decimal
import os
import struct
from fractions import Fraction as F

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RN, RD, RU, RZ = 0, 1, 2, 3                                 # the 8087's rounding control, in its order
I, D, Z, O, U, P = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20
C0, C1, C2, C3 = 0x0100, 0x0200, 0x0400, 0x4000
BIAS = 16383


def rnd(fr, p=64, mode=RN):
    """(sign, m, e2, inexact): fr = m * 2^e2 rounded to p bits, m of 64 bits."""
    s, a = int(fr < 0), abs(fr)
    e = a.numerator.bit_length() - a.denominator.bit_length() - p
    q = a / F(2) ** e
    while q >= 1 << p:
        e += 1
        q /= 2
    while q < 1 << (p - 1):
        e -= 1
        q *= 2
    m = q.numerator // q.denominator
    rem = q - m
    up = {RN: rem > F(1, 2) or (rem == F(1, 2) and m & 1), RU: rem > 0 and not s,
          RD: rem > 0 and s, RZ: False}[mode]
    if up:
        m += 1
        if m == 1 << p:
            m >>= 1
            e += 1
    return s, m << (64 - p), e - (64 - p), rem != 0


def raw(m, se):
    return m.to_bytes(8, "little") + struct.pack("<H", se)


def X(fr, p=64, mode=RN):
    """(ten bytes, inexact)"""
    fr = F(fr)
    if fr == 0:
        return raw(0, 0), False
    s, m, e2, inx = rnd(fr, p, mode)
    return raw(m, s << 15 | (e2 + 63 + BIAS)), inx


def x(fr, p=64, mode=RN):
    return X(fr, p, mode)[0]


def sgl(fr, mode=RN):
    s, m, e2, inx = rnd(F(fr), 24, mode)
    return struct.pack("<I", s << 31 | (e2 + 63 + 127) << 23 | (m >> 40) & 0x7FFFFF), inx


def dbl(fr, mode=RN):
    s, m, e2, inx = rnd(F(fr), 53, mode)
    return struct.pack("<Q", s << 63 | (e2 + 63 + 1023) << 52 | (m >> 11) & ((1 << 52) - 1)), inx


def qd(v):
    return struct.pack("<d", v)


def fd(v):
    return struct.pack("<f", v)


INDEF = raw(0xC000000000000000, 0xFFFF)
INF = raw(0x8000000000000000, 0x7FFF)
NINF = raw(0x8000000000000000, 0xFFFF)
ZERO = raw(0, 0)
NAN_A = raw(0xC000000000001234, 0x7FFF)
NAN_B = raw(0xE000000000000000, 0xFFFF)


def constants():
    decimal.getcontext().prec = 70
    Dm = decimal.Decimal

    def atan_inv(n):                                        # atan(1/n)
        x, n2, k, t, s = Dm(1) / n, n * n, 1, Dm(1) / n, Dm(0)
        while True:
            term = t / k
            if abs(term) < Dm(10) ** -68:
                return s + term
            s += term if (k // 2) % 2 == 0 else -term
            t /= n2
            k += 2
    pi = 16 * atan_inv(5) - 4 * atan_inv(239)
    ln2, ln10 = Dm(2).ln(), Dm(10).ln()
    return {"fld1": F(1), "fldl2t": F(ln10 / ln2), "fldl2e": F(1 / ln2), "fldpi": F(pi),
            "fldlg2": F(ln2 / ln10), "fldln2": F(ln2), "fldz": F(0)}


def top(pushes, pops=0):
    return ((pops - pushes) & 7) << 11


def cw(rc=RN, pc=3, ic=0):
    return 0x00FF | pc << 8 | rc << 10 | ic << 12


cases = []                                                  # (code lines, data {label: bytes}, st0, sw, out)


def case(code, st0, sw, out=b"", **data):
    cases.append((code, data, st0, sw, out))


def near(code, want, sw, **data):
    """ST(0) within 2^-56 of want (a Fraction), judged by the program"""
    tol = abs(want) / F(2) ** 56
    data["e"] = x(want) + x(tol)
    cases.append((code + ["mov si, @e"], data, None, sw, b""))


def main():
    a, b = 0.1, 0.2
    fa, fb = F(a), F(b)
    # --- loads and the arithmetic with a memory operand
    case(["fld qword [@a]"], x(fa), top(1), a=qd(a))
    for op, fn in (("fadd", lambda p, q: p + q), ("fsub", lambda p, q: p - q), ("fsubr", lambda p, q: q - p),
                   ("fmul", lambda p, q: p * q), ("fdiv", lambda p, q: p / q), ("fdivr", lambda p, q: q / p)):
        r, inx = X(fn(fa, fb))
        case(["fld qword [@a]", f"{op} qword [@b]"], r, top(1) | (P if inx else 0), a=qd(a), b=qd(b))
        r, inx = X(fn(F(1.5), F(struct.unpack("<f", fd(0.3))[0])))
        case(["fld qword [@a]", f"{op} dword [@b]"], r, top(1) | (P if inx else 0), a=qd(1.5), b=fd(0.3))
    for op, fn in (("fiadd", lambda p, q: p + q), ("fisub", lambda p, q: p - q), ("fisubr", lambda p, q: q - p),
                   ("fimul", lambda p, q: p * q), ("fidiv", lambda p, q: p / q), ("fidivr", lambda p, q: q / p)):
        r, inx = X(fn(F(2.5), F(-7)))
        case(["fld qword [@a]", f"{op} word [@b]"], r, top(1) | (P if inx else 0), a=qd(2.5), b=struct.pack("<h", -7))
        r, inx = X(fn(F(-1000.25), F(100003)))
        case(["fld qword [@a]", f"{op} dword [@b]"], r, top(1) | (P if inx else 0), a=qd(-1000.25),
             b=struct.pack("<i", 100003))
    # --- the register forms: D8 (to ST), DC (to ST(i)), DE (to ST(i) and pop); reg 4/6 ST op ST(i), 5/7 ST(i) op ST
    p, q = F(7), F(3)                                       # ST(1) = 7, ST(0) = 3
    for reg, fn in ((0, lambda s, t: s + t), (1, lambda s, t: s * t), (4, lambda s, t: s - t),
                    (5, lambda s, t: t - s), (6, lambda s, t: s / t), (7, lambda s, t: t / s)):
        r, inx = X(fn(q, p))
        fl = P if inx else 0
        case(["fld qword [@a]", "fld qword [@b]", f"db 0D8h, {0xC1 | reg << 3:#04x}"], r, top(2) | fl, a=qd(7), b=qd(3))
        case(["fld qword [@a]", "fld qword [@b]", f"db 0DCh, {0xC1 | reg << 3:#04x}", "fstp st0"], r, top(2, 1) | fl,
             a=qd(7), b=qd(3))
        case(["fld qword [@a]", "fld qword [@b]", f"db 0DEh, {0xC1 | reg << 3:#04x}"], r, top(2, 1) | fl,
             a=qd(7), b=qd(3))
    # --- the tie SANE gets wrong with a source that is not extended: rounded to even here
    case(["fld tword [@a]", "fadd qword [@b]"], x(F(2) ** 63), top(1) | P, a=x(F(2) ** 63), b=qd(0.5))
    case(["fld tword [@a]", "fadd dword [@b]"], x(F(2) ** 63), top(1) | P, a=x(F(2) ** 63), b=fd(0.5))
    case(["fld tword [@a]", "fiadd word [@b]"], x(F(2) ** 64), top(1) | P, a=x(F(2) ** 64), b=struct.pack("<h", 1))
    case(["fld tword [@a]", "fisub dword [@b]"], x(F(2) ** 64 - 1), top(1), a=x(F(2) ** 64), b=struct.pack("<i", 1))
    case(["fld tword [@a]", "fisub dword [@b]"], x(F(2) ** 64), top(1) | P, a=x(F(2) ** 64), b=struct.pack("<i", -1))
    # --- rounding and precision
    for rc in (RN, RD, RU, RZ):
        r, inx = X(F(1, 3), 64, rc)
        case(["fldcw [@c]", "fld1", "fdiv dword [@b]"], r, top(1) | P, c=struct.pack("<H", cw(rc)), b=fd(3.0))
        r, inx = X(F(-2, 3), 64, rc)
        case(["fldcw [@c]", "fld1", "fchs", "fadd st0, st0", "fdiv dword [@b]"], r, top(1) | P,
             c=struct.pack("<H", cw(rc)), b=fd(3.0))
    for pc, bits in ((0, 24), (2, 53)):
        for rc in (RN, RZ):
            r, inx = X(F(1, 3), bits, rc)
            case(["fldcw [@c]", "fld1", "fdiv dword [@b]"], r, top(1) | P, c=struct.pack("<H", cw(rc, pc)), b=fd(3.0))
    # --- compares
    case(["fld qword [@a]", "fcom qword [@b]"], x(fa), top(1) | C0, a=qd(a), b=qd(b))
    case(["fld qword [@b]", "fcom qword [@a]"], x(fb), top(1), a=qd(a), b=qd(b))
    case(["fld qword [@a]", "fcom qword [@a]"], x(fa), top(1) | C3, a=qd(a))
    case(["fld qword [@a]", "fcomp qword [@b]"], INDEF, top(1, 1) | C0, a=qd(a), b=qd(b))
    case(["fld qword [@a]", "fld qword [@b]", "fcompp"], INDEF, top(2, 2), a=qd(a), b=qd(b))
    case(["fld qword [@a]", "fld qword [@b]", "fcom st1"], x(fb), top(2), a=qd(a), b=qd(b))
    case(["fld qword [@a]", "fld qword [@b]", "fcomp st1"], x(fa), top(2, 1), a=qd(a), b=qd(b))
    case(["fld qword [@a]", "ficom word [@b]"], x(5), top(1) | C3, a=qd(5.0), b=struct.pack("<h", 5))
    case(["fld qword [@a]", "ficomp dword [@b]"], INDEF, top(1, 1) | C0, a=qd(-5.0), b=struct.pack("<i", -4))
    case(["fld qword [@a]", "fcom dword [@b]"], raw(0, 0x8000), top(1) | C3, a=qd(-0.0), b=fd(0.0))
    case(["fld tword [@a]", "fcom qword [@b]"], x(F(2) ** 63 + 1), top(1), a=x(F(2) ** 63 + 1), b=qd(2.0 ** 63))
    case(["fld qword [@a]", "ftst"], x(-0.5), top(1) | C0, a=qd(-0.5))
    case(["fld qword [@a]", "ftst"], x(0.5), top(1), a=qd(0.5))
    case(["fldz", "ftst"], ZERO, top(1) | C3)
    case(["fld tword [@a]", "fcom qword [@b]"], NAN_A, top(1) | C3 | C2 | C0 | I, a=NAN_A, b=qd(1.0))
    case(["fld tword [@a]", "ftst"], INF, top(1) | C3 | C2 | C0 | I, a=INF)            # projective
    case(["fldcw [@c]", "fld tword [@a]", "ftst"], INF, top(1), a=INF, c=struct.pack("<H", cw(ic=1)))
    case(["fld tword [@a]", "fld tword [@a]", "fcompp"], INDEF, top(2, 2) | C3, a=INF)   # projective: equal
    case(["fld tword [@a]", "fcom qword [@b]"], NINF, top(1) | C3 | C2 | C0 | I, a=NINF, b=qd(1.0))
    case(["fldcw [@c]", "fld tword [@a]", "fcom qword [@b]"], NINF, top(1) | C0, a=NINF, b=qd(1.0),
         c=struct.pack("<H", cw(ic=1)))
    # --- FXAM
    case(["fld qword [@a]", "fxam"], x(-2), top(1) | C2 | C1, a=qd(-2.0))
    case(["fld qword [@a]", "fxam"], x(2), top(1) | C2, a=qd(2.0))
    case(["fldz", "fxam"], ZERO, top(1) | C3)
    case(["fldz", "fchs", "fxam"], raw(0, 0x8000), top(1) | C3 | C1)
    case(["fxam"], INDEF, top(0) | C3 | C0)
    case(["fld tword [@a]", "fxam"], INF, top(1) | C2 | C0, a=INF)
    case(["fld tword [@a]", "fxam"], NINF, top(1) | C2 | C1 | C0, a=NINF)
    case(["fld tword [@a]", "fxam"], NAN_A, top(1) | C0, a=NAN_A)
    case(["fld tword [@a]", "fxam"], raw(0x4000000000000000, 0), top(1) | C3 | C2, a=raw(0x4000000000000000, 0))
    case(["fld tword [@a]", "fxam"], raw(0x4000000000000000, 0x4000), top(1), a=raw(0x4000000000000000, 0x4000))
    # a single's denormal is loaded as the unnormal of its value, with D
    case(["fld dword [@a]", "fxam"], raw(1 << 40, 0x3F81), top(1) | D, a=struct.pack("<I", 1))
    case(["fld qword [@a]"], raw(3 << 11, 0x3C01), top(1) | D, a=struct.pack("<Q", 3))
    # --- the constants, and what moves numbers or their signs
    for name, v in constants().items():
        case([name], x(v), top(1))
    case(["fld qword [@a]", "fabs"], x(3), top(1), a=qd(-3.0))
    case(["fld1", "fchs"], x(-1), top(1))
    case(["fld1", "fldz", "fxch st1"], x(1), top(2))
    case(["fld1", "fldz", "fld st1"], x(1), top(3))
    case(["fldz", "fld1", "fstp st1"], x(1), top(2, 1))
    case(["fld1", "fldpi", "fst st1", "fstp st0"], x(constants()["fldpi"]), top(2, 1))
    case(["fld1", "ffree st0"], INDEF, top(1))
    case(["fld1", "fincstp"], INDEF, top(1, 1))
    case(["fld1", "fdecstp"], INDEF, top(2))
    case(["fld1", "fdecstp", "fincstp"], x(1), top(1))
    case(["fnop", "fld1"], x(1), top(1))
    # --- FRNDINT
    for v, rc, want in ((2.5, RN, 2), (3.5, RN, 4), (2.5, RU, 3), (-2.5, RD, -3), (-2.7, RZ, -2), (-0.3, RU, 0),
                        (4.0, RN, 4), (1e30, RN, 1e30)):
        r = x(F(want)) if want != 0 else raw(0, 0x8000)
        exact = F(v) == F(want)
        case(["fldcw [@c]", "fld qword [@a]", "frndint"], r, top(1) | (0 if exact else P), a=qd(v),
             c=struct.pack("<H", cw(rc)))
    # --- stores
    third = F(1 / 3)
    s, inx = sgl(third)
    case(["fld qword [@a]", "fst dword [@o]"], x(third), top(1) | P, s, a=qd(1 / 3))
    s, inx = dbl(F(1, 3))
    case(["fld1", "fdiv dword [@b]", "fstp qword [@o]"], INDEF, top(1, 1) | P, s, b=fd(3.0))
    for rc in (RD, RU, RZ):
        s, inx = dbl(F(-1, 3), rc)
        case(["fldcw [@c]", "fld1", "fchs", "fdiv dword [@b]", "fst qword [@o]"], x(F(-1, 3), 64, rc), top(1) | P,
             s, b=fd(3.0), c=struct.pack("<H", cw(rc)))
    case(["fld qword [@a]", "fist word [@o]"], x(2.5), top(1) | P, struct.pack("<h", 2), a=qd(2.5))
    case(["fld qword [@a]", "fistp word [@o]"], INDEF, top(1, 1) | P, struct.pack("<h", -4), a=qd(-3.5))
    case(["fldcw [@c]", "fld qword [@a]", "fist dword [@o]"], x(-2.7), top(1) | P, struct.pack("<i", -2),
         a=qd(-2.7), c=struct.pack("<H", cw(RZ)))
    case(["fld qword [@a]", "fist word [@o]"], x(40000), top(1) | I, struct.pack("<H", 0x8000), a=qd(40000.0))
    case(["fld qword [@a]", "fist dword [@o]"], x(1e10), top(1) | I, struct.pack("<I", 0x80000000), a=qd(1e10))
    case(["fld qword [@a]", "fistp qword [@o]"], INDEF, top(1, 1), struct.pack("<q", 123456789012345),
         a=qd(123456789012345.0))
    case(["fild qword [@a]", "fld st0", "fistp qword [@o]"], x(-(F(2) ** 63)), top(2, 1), struct.pack("<q", -2 ** 63),
         a=struct.pack("<q", -2 ** 63))
    case(["fild qword [@a]"], x(-(F(2) ** 63) + 1), top(1), a=struct.pack("<q", -2 ** 63 + 1))
    case(["fild word [@a]"], x(-32768), top(1), a=struct.pack("<h", -32768))
    case(["fild dword [@a]"], x(-1), top(1), a=struct.pack("<i", -1))
    case(["fild word [@a]"], ZERO, top(1), a=struct.pack("<h", 0))
    case(["fld tword [@a]", "fist dword [@o]"], INF, top(1) | I, struct.pack("<I", 0x80000000), a=INF)
    case(["fld qword [@a]", "fst dword [@o]"], x(1e40), top(1) | O | P, struct.pack("<I", 0x7F800000), a=qd(1e40))
    case(["fldcw [@c]", "fld qword [@a]", "fst dword [@o]"], x(1e40), top(1) | O | P, struct.pack("<I", 0x7F800000),
         a=qd(1e40), c=struct.pack("<H", cw(RZ)))
    case(["fldcw [@c]", "fld qword [@a]", "fst dword [@o]"], x(1e40), top(1) | O | P, struct.pack("<I", 0x7F7FFFFF),
         a=qd(1e40), c=struct.pack("<H", cw(RD)))
    case(["fld tword [@a]", "fst qword [@o]"], NAN_A, top(1), struct.pack("<Q", 0x7FF0000000000000 | 0xC000000000001234 >> 11 & ((1 << 52) - 1)), a=NAN_A)
    case(["fld tword [@a]", "fst dword [@o]"], NINF, top(1), struct.pack("<I", 0xFF800000), a=NINF)
    case(["fstp qword [@o]"], INDEF, top(0, 1) | I, struct.pack("<Q", 0xFFF8000000000000))
    case(["fld tword [@a]", "fstp tword [@t]", "fld tword [@t]"], raw(0x0123456789ABCDEF, 0x3FFF), top(1, 0),
         a=raw(0x0123456789ABCDEF, 0x3FFF), t=bytes(10))
    # --- the special values in arithmetic
    case(["fld1", "fdiv dword [@b]"], INF, top(1) | Z, b=fd(0.0))
    case(["fld1", "fchs", "fdiv dword [@b]"], NINF, top(1) | Z, b=fd(0.0))
    case(["fldz", "fdiv dword [@b]"], INDEF, top(1) | I, b=fd(0.0))
    case(["fld tword [@a]", "fadd qword [@b]"], INF, top(1), a=INF, b=qd(1.0))
    case(["fld tword [@a]", "fsubr qword [@b]"], NINF, top(1), a=INF, b=qd(1.0))
    case(["fld tword [@a]", "fld tword [@a]", "fadd st0, st1"], INDEF, top(2) | I, a=INF)       # projective
    case(["fldcw [@c]", "fld tword [@a]", "fld tword [@a]", "fadd st0, st1"], INF, top(2), a=INF,
         c=struct.pack("<H", cw(ic=1)))
    case(["fldcw [@c]", "fld tword [@a]", "fld tword [@a]", "fsub st0, st1"], INDEF, top(2) | I, a=INF,
         c=struct.pack("<H", cw(ic=1)))
    case(["fld tword [@a]", "fmul dword [@b]"], INDEF, top(1) | I, a=INF, b=fd(0.0))
    case(["fld tword [@a]", "fmul dword [@b]"], NINF, top(1), a=INF, b=fd(-2.0))
    case(["fld tword [@b]", "fdivr dword [@a]"], raw(0, 0x8000), top(1), a=fd(-2.0), b=INF)
    case(["fld tword [@a]", "fadd qword [@b]"], NAN_A, top(1) | I, a=NAN_A, b=qd(1.0))
    case(["fld tword [@a]", "fld tword [@b]", "fadd st0, st1"], NAN_B, top(2) | I, a=NAN_A, b=NAN_B)
    case(["fld tword [@b]", "fld tword [@a]", "fadd st0, st1"], NAN_B, top(2) | I, a=NAN_A, b=NAN_B)
    case(["fadd qword [@b]"], INDEF, top(0) | I, b=qd(1.0))
    case(["fld1"] * 9, INDEF, top(9) | I)
    case(["fld st3"], INDEF, top(1) | I)
    case(["fld1", "fxch st1"], INDEF, top(1) | I)
    case(["fld1", "fxch st1", "fstp st0"], x(1), top(1, 1) | I)
    # --- denormals: D, and the 8087's encoding in a register (exponent 0 is 2^-16382)
    den = raw(0x4000000000000000, 0)                         # 2^-16383
    case(["fld tword [@a]", "fmul qword [@b]"], raw(0x8000000000000000, 1), top(1) | D, a=den, b=qd(2.0))
    case(["fld tword [@a]", "fmul qword [@b]"], den, top(1) | U, a=raw(0x8000000000000000, 1), b=qd(0.5))
    case(["fld tword [@a]", "fld1", "fdiv st0, st1"], INDEF, top(2) | D | I, a=den)
    case(["fld tword [@a]", "fadd qword [@b]"], x(1), top(1) | D | P, a=den, b=qd(1.0))
    case(["fld qword [@b]", "fdiv dword [@a]"], INDEF, top(1) | D | I, a=struct.pack("<I", 1), b=qd(1.0))
    # --- an operand that goes round the segment's end
    case(["mov ax, cs", "add ax, 1000h", "mov es, ax", "fld qword [@a]", "fstp qword [es:0FFFDh]",
          "mov si, 0FFFDh", "mov di, @o", "mov cx, 3", ".c1: mov al, [es:si]", "mov [di], al", "inc si", "inc di",
          "loop .c1", "xor si, si", "mov cx, 5", ".c2: mov al, [es:si]", "mov [di], al", "inc si", "inc di",
          "loop .c2", "fld qword [es:0FFFDh]"], x(F(-1234.5)), top(2, 1), qd(-1234.5), a=qd(-1234.5))
    case(["mov ax, cs", "add ax, 1000h", "mov es, ax", "fld tword [@a]", "fstp tword [es:0FFF9h]",
          "fld tword [es:0FFF9h]"], x(F(1, 7)), top(2, 1), a=x(F(1, 7)))
    write("fpuops", 8)
    cases.clear()
    ext()
    write("fpuext", 10)
    cases.clear()
    md()
    write("fpumd", 8)


def md():
    import random
    r = random.Random(87)

    def rx():
        m = (1 << 63) | r.getrandbits(63)
        return raw(m, (r.getrandbits(1) << 15) | (0x3FFF + r.randint(-40, 40)))
    pairs = [(rx(), rx()) for _ in range(70)]
    one63 = raw((1 << 63) | 1, 0x3FFF)                     # 1 + 2^-63
    pairs += [(one63, x(F(3, 2))), (x(F(3, 2)), one63), (raw(2 ** 64 - 1, 0x3FFF), raw(2 ** 64 - 1, 0x3FFF)),
              (raw(2 ** 64 - 1, 0x3FFF), raw(1 << 63, 0x4000)), (x(7), x(3)), (x(1), x(10)), (x(355), x(113)),
              (x(F(2) ** 40 + 1), x(F(2) ** 40 - 1)), (raw((1 << 63) | (1 << 39), 0x3FFF), raw((1 << 63) | (1 << 39), 0x3FFF))]
    modes = [(rc, pc) for rc in (RN, RD, RU, RZ) for pc in (3, 2, 0)]
    for n, (a, b) in enumerate(pairs):
        fa, fb = x_frac(a), x_frac(b)
        for op, val in (("fmul", fa * fb), ("fdiv", fa / fb)):
            rc, pc = modes[(n * 2 + (op == "fdiv")) % len(modes)] if n < 70 else (RN, 3)
            for rc_, pc_ in ([(rc, pc)] if n < 70 else modes):
                bits = {3: 64, 2: 53, 0: 24}[pc_]
                res, inx = X(val, bits, rc_)
                case(["fldcw [@c]", "fld tword [@b]", "fld tword [@a]", f"{op} st0, st1"], res, top(2) | (P if inx else 0),
                     a=a, b=b, c=struct.pack("<H", cw(rc_, pc_)))
    # out of the normal range: SANE's, as before
    big = raw(1 << 63, 0x7FF0)
    case(["fld tword [@a]", "fld tword [@a]", "fmul st0, st1"], INF, top(2) | O | P, a=big)
    tiny = raw(1 << 63, 0x0010)
    case(["fld tword [@a]", "fld tword [@a]", "fmul st0, st1"], ZERO, top(2) | U | P, a=tiny)
    case(["fld tword [@b]", "fld tword [@a]", "fdiv st0, st1"], INF, top(2) | O | P, a=big, b=tiny)
    case(["fld tword [@b]", "fld tword [@a]", "fdiv st0, st1"], ZERO, top(2) | U | P, a=tiny, b=big)
    # right at the range's ends, still here
    case(["fld tword [@b]", "fld tword [@a]", "fmul st0, st1"], raw(1 << 63, 0x7FFE), top(2), a=raw(1 << 63, 0x7FFE),
         b=raw(1 << 63, 0x3FFF))
    case(["fld tword [@b]", "fld tword [@a]", "fdiv st0, st1"], raw(1 << 63, 0x0001), top(2), a=raw(1 << 63, 0x3FFF),
         b=raw(1 << 63, 0x7FFD))


DM = decimal.Decimal


def dctx():
    decimal.getcontext().prec = 70


def d_ln2():
    dctx()
    return DM(2).ln()


def _pi():
    dctx()

    def atan_inv(n):
        t, s, k = DM(1) / n, DM(0), 1
        while True:
            term = t / k
            if abs(term) < DM(10) ** -68:
                return s + term
            s += term if (k // 2) % 2 == 0 else -term
            t /= n * n
            k += 2
    return 16 * atan_inv(5) - 4 * atan_inv(239)


def d_of(fr):
    dctx()
    return DM(fr.numerator) / DM(fr.denominator)


def d_atan(v):
    dctx()
    v = DM(v)
    halvings = 0
    while abs(v) > DM("0.1"):
        v = v / (1 + (1 + v * v).sqrt())
        halvings += 1
    s, t, k, v2 = DM(0), v, 1, v * v
    while True:
        term = t / k
        if abs(term) < DM(10) ** -68:
            break
        s += term if (k // 2) % 2 == 0 else -term
        t *= v2
        k += 2
    return s * (2 ** halvings)


def d_tan(v):
    dctx()
    v = DM(v)
    sn, cs, t, k = DM(0), DM(0), DM(1), 0
    while True:                                             # t = v^k / k!
        if abs(t) < DM(10) ** -68 and k > 2:
            break
        if k % 2 == 0:
            cs += t if (k // 2) % 2 == 0 else -t
        else:
            sn += t if (k // 2) % 2 == 0 else -t
        k += 1
        t = t * v / k
    return sn / cs


def sqrt_x(fr, p=64, mode=RN):
    """the square root rounded: exact when it is rational, else by a stand-in strictly between"""
    import math
    n, d = fr.numerator, fr.denominator
    num = n * d << 600
    r = math.isqrt(num)
    v = F(r, d << 300) if r * r == num else F(2 * r + 1, d << 301)
    return X(v, p, mode)


def bcd(v):
    s = "%018d" % abs(v)
    b = bytes(int(s[16 - 2 * i]) << 4 | int(s[17 - 2 * i]) for i in range(9))
    return b + bytes([0x80 if v < 0 else 0])


def ext():
    W = {"w": bytes(2)}
    # --- FSQRT
    for v, rc in ((2, RN), (2, RD), (2, RU), (2, RZ), (16, RN), (0.25, RN), (1e-300, RN), (3e300, RN)):
        r, inx = sqrt_x(F(v), 64, rc)
        case(["fldcw [@c]", "fld qword [@a]", "fsqrt"], r, top(1) | (P if inx else 0), a=qd(v),
             c=struct.pack("<H", cw(rc)))
    r, inx = sqrt_x(F(2), 24)
    case(["fldcw [@c]", "fld qword [@a]", "fsqrt"], r, top(1) | P, a=qd(2.0), c=struct.pack("<H", cw(RN, 0)))
    case(["fldz", "fchs", "fsqrt"], raw(0, 0x8000), top(1))
    case(["fld qword [@a]", "fsqrt"], INDEF, top(1) | I, a=qd(-1.0))
    case(["fld tword [@a]", "fsqrt"], INDEF, top(1) | I, a=INF)                          # projective
    case(["fldcw [@c]", "fld tword [@a]", "fsqrt"], INF, top(1), a=INF, c=struct.pack("<H", cw(ic=1)))
    case(["fld tword [@a]", "fsqrt"], INDEF, top(1) | I | D, a=raw(0x4000000000000000, 0))   # a denormal
    case(["fld tword [@a]", "fsqrt"], INDEF, top(1) | I, a=raw(0x4000000000000000, 0x4000))  # an unnormal
    case(["fsqrt"], INDEF, top(0) | I)
    # --- FSCALE: ST * 2^(ST(1) chopped)
    for v, sc, want in ((1.5, 3.0, F(12)), (1.5, -2.7, F(3, 8)), (-5.0, 0.9, F(-5)), (1.0, 16000.0, F(2) ** 16000),
                        (3.0, -1.0, F(3, 2))):
        case(["fld qword [@b]", "fld qword [@a]", "fscale"], x(want), top(2), a=qd(v), b=qd(sc))
    case(["fld qword [@b]", "fld tword [@a]", "fscale"], INF, top(2) | O | P, a=x(F(2) ** 16000), b=qd(1000.0))
    case(["fld qword [@a]", "fscale"], INDEF, top(1) | I, a=qd(2.0))                      # ST(1) empty
    case(["fld tword [@b]", "fld qword [@a]", "fscale"], INDEF, top(2) | I, a=qd(2.0), b=INF)
    case(["fld qword [@b]", "fldz", "fscale"], ZERO, top(2), b=qd(5.0))
    # --- FXTRACT: the significand on top, the exponent below it
    for v, sig, e in ((12.0, F(3, 2), 3), (-0.375, F(-3, 2), -2), (1.0, F(1), 0), (2.0 ** 100, F(1), 100)):
        case(["fld qword [@a]", "fxtract"], x(sig), top(2), a=qd(v))
        case(["fld qword [@a]", "fxtract", "fstp st0"], x(F(e)) if e else ZERO, top(2, 1), a=qd(v))
    case(["fld tword [@a]", "fxtract"], x(1), top(2) | D, a=raw(0x4000000000000000, 0))
    case(["fld tword [@a]", "fxtract", "fstp st0"], x(-16383), top(2, 1) | D, a=raw(0x4000000000000000, 0))
    case(["fldz", "fchs", "fxtract"], raw(0, 0x8000), top(2))
    case(["fldz", "fchs", "fxtract", "fstp st0"], raw(0, 0x8000), top(2, 1))
    case(["fld tword [@a]", "fxtract"], INDEF, top(1) | I, a=INF)
    # --- FPREM: the quotient chopped; C0 C3 C1 its last three bits; C2 while it is partial
    for a_, b_ in ((F(10), F(3)), (F(-10), F(3)), (F(10), F(-3)), (F(15, 2), F(2)), (F(1), F(3)), (F(3), F(3)),
                   (F(-3), F(3)), (F(3, 4), F(1, 4)), (F(2) ** 70, F(3)), (F(2) ** 1000 + 12345, F(7)),
                   (F(1000), F(355, 113)), (F(-(2 ** 64) + 1), F(10))):
        a_, b_ = x_frac(x(a_)), x_frac(x(b_))                # (as the program loads them: rounded to 64 bits)
        q = abs(a_ / b_)
        q = q.numerator // q.denominator
        r = a_ - (q if (a_ < 0) == (b_ < 0) else -q) * b_
        st = raw(0, 0x8000 if a_ < 0 else 0) if r == 0 else x(r)
        cc = (C0 if q & 4 else 0) | (C3 if q & 2 else 0) | (C1 if q & 1 else 0)
        case(["fld tword [@b]", "fld tword [@a]", ".l: fprem", "fnstsw [@w]", "test byte [@w+1], 4", "jnz .l"],
             st, top(2) | cc, a=x(a_), b=x(b_), **W)
    case(["fld qword [@b]", "fld qword [@a]", "fprem"], x(5), top(2), a=qd(5.0), b=qd(float("inf")))
    case(["fldz", "fld qword [@a]", "fprem"], INDEF, top(2) | I, a=qd(5.0))
    case(["fld qword [@b]", "fld tword [@a]", "fprem"], INDEF, top(2) | I, a=INF, b=qd(2.0))
    case(["fld qword [@b]", "fldz", "fprem"], ZERO, top(2), b=qd(2.0))
    # --- packed decimal
    for v in (-123456789012345678, 0, 999999999999999999, 7):
        case(["fbld [@a]"], x(v) if v else ZERO, top(1), a=bcd(v))
    case(["fbld [@a]"], raw(0, 0x8000), top(1), a=bytes(9) + b"\x80")
    for v, rc, want, fl in ((2.5, RN, 2, P), (-7.5, RD, -8, P), (-7.5, RZ, -7, P), (123.0, RN, 123, 0)):
        case(["fldcw [@c]", "fld qword [@a]", "fbstp [@o]"], INDEF, top(1, 1) | fl, bcd(want), a=qd(v),
             c=struct.pack("<H", cw(rc)))
    case(["fild qword [@a]", "fbstp [@o]"], INDEF, top(1, 1), bcd(999999999999999999),
         a=struct.pack("<q", 999999999999999999))
    case(["fild qword [@a]", "fbstp [@o]"], INDEF, top(1, 1), bcd(-999999999999999999),
         a=struct.pack("<q", -999999999999999999))
    bind = bytes(7) + b"\xC0\xFF\xFF"
    case(["fild qword [@a]", "fbstp [@o]"], INDEF, top(1, 1) | I, bind, a=struct.pack("<q", 10 ** 18))
    case(["fld tword [@a]", "fbstp [@o]"], INDEF, top(1, 1) | I, bind, a=INF)
    case(["fbstp [@o]"], INDEF, top(0, 1) | I, bind)
    case(["fldz", "fchs", "fbstp [@o]"], INDEF, top(1, 1), bytes(9) + b"\x80")
    # --- the transcendentals, judged near
    ln2 = d_ln2()
    for v in (0.5, -0.5, 0.25, 1e-10):
        dctx()
        near(["fld qword [@a]", "f2xm1"], F((DM(v) * ln2).exp() - 1), top(1) | P, a=qd(v))
    case(["fldz", "f2xm1"], ZERO, top(1))
    for y, v in ((1.0, 8.0), (2.0, 0.1), (3.0, 1e-300), (-1.5, 1e300)):
        dctx()
        near(["fld qword [@b]", "fld qword [@a]", "fyl2x"], F(DM(y) * DM(v).ln() / ln2), top(2, 1) | P,
             a=qd(v), b=qd(y))
    for y, v in ((1.0, 0.25), (3.0, -0.25), (1.0, 1e-10)):
        dctx()
        near(["fld qword [@b]", "fld qword [@a]", "fyl2xp1"], F(DM(y) * (1 + DM(v)).ln() / ln2), top(2, 1) | P,
             a=qd(v), b=qd(y))
    for v in (0.5, 1e-5, 0.785):
        near(["fld qword [@a]", "fptan", "fdivp st1, st0"], F(d_tan(v)), top(2, 1) | P, a=qd(v))
    near(["fldpi", "fmul dword [@a]", "fptan", "fdivp st1, st0"], F(d_tan(d_of(x_frac(x(constants()["fldpi"])) / 4))),
         top(2, 1) | P, a=fd(0.25))
    for yv, xv in ((1.0, 2.0), (1.0, 1.0), (0.3, 0.4), (1e-20, 1.0)):
        near(["fld qword [@b]", "fld qword [@a]", "fpatan"], F(d_atan(d_of(F(yv) / F(xv)))), top(2, 1) | P,
             a=qd(xv), b=qd(yv))
    case(["fldz", "fld1", "fpatan"], ZERO, top(2, 1) | P)


def x_frac(b):
    m = int.from_bytes(b[:8], "little")
    se, = struct.unpack_from("<H", b, 8)
    return F(-m if se >> 15 else m) * F(2) ** ((se & 0x7FFF) - BIAS - 63)


def write(name, outlen):
    asm = [
        f"; {name}.asm - written by tools/gen_fputest.py: do not edit; edit the generator.",
        "; The 8087 (docs/8087.md, M9.3 and M9.4): each case a few instructions, then a",
        "; line: its number, ST(0) as FSTP TBYTE stores it (or OK: within 2^-56 of the",
        f"; value it should have), the status word before that, and the {outlen} bytes at OUT",
        "; (AA where the case stored nothing).",
        "        cpu 8086",
        f"OUTLEN  equ {outlen}",
        "        org 100h",
        "start:  fninit",
    ]
    data = []
    expect = []
    for n, c in enumerate(cases):
        code, d, st0, sw, out = c
        lab = {k: f"d{n}_{k}" for k in d}
        lab["o"] = "out"
        for k, v in d.items():
            data.append(f"d{n}_{k}: db " + ", ".join(f"{b:#04x}" for b in v))
        asm.append(f"; case {n:02X}")
        asm.append(f"c{n}:")
        for line in code:
            for k, l in lab.items():
                line = line.replace("@" + k, l)
            asm.append(("        " + line) if not line.startswith(".") else line)
        asm.append("        call report" if st0 is not None else "        call nearck")
        o = (out + b"\xAA" * outlen)[:outlen]
        expect.append(f"{n & 0xFF:02X} {st0[::-1].hex().upper() if st0 is not None else 'OK'} {sw:04X} "
                      f"{o[::-1].hex().upper()}")
    asm += """        mov dx, done
        mov ah, 9
        int 21h
        mov ax, 4C00h
        int 21h

nearck: fnstsw [sw]
        fld tword [si]
        fsub st0, st1
        fabs
        fld tword [si+10]
        fcompp
        fnstsw [t]
        fstp tword [res]
        mov al, [num]
        call hex2
        inc byte [num]
        call spc
        test byte [t+1], 1
        jnz .far
        mov al, 'O'
        call putc
        mov al, 'K'
        call putc
        jmp rest
.far:   mov si, res+9
        mov cx, 10
        call hexr
        jmp rest
report: fnstsw [sw]
        fstp tword [res]
        mov al, [num]
        call hex2
        inc byte [num]
        call spc
        mov si, res+9
        mov cx, 10
        call hexr
rest:   call spc
        mov ax, [sw]
        call hex4
        call spc
        mov si, out+OUTLEN-1
        mov cx, OUTLEN
        call hexr
        mov al, 13
        call putc
        mov al, 10
        call putc
        fninit
        push es
        push ds
        pop es
        mov di, out
        mov cx, OUTLEN/2
        mov ax, 0AAAAh
        rep stosw
        pop es
        ret
hexr:   mov al, [si]
        dec si
        call hex2
        loop hexr
        ret
spc:    mov al, ' '
putc:   push ax
        mov dl, al
        mov ah, 2
        int 21h
        pop ax
        ret
hex4:   push ax
        mov al, ah
        call hex2
        pop ax
hex2:   push ax
        push cx
        mov cl, 4
        shr al, cl
        call .n
        pop cx
        pop ax
        and al, 0Fh
.n:     push ax
        add al, '0'
        cmp al, '9'
        jbe .p
        add al, 7
.p:     call putc
        pop ax
        ret

done:   db 'DONE', 13, 10, '$'
num:    db 0
sw:     dw 0
t:      dw 0
res:    times 10 db 0
out:    times OUTLEN db 0AAh
""".split("\n")
    asm += data
    with open(os.path.join(ROOT, "tests", "com", name + ".asm"), "w") as f:
        f.write("\n".join(asm) + "\n")
    with open(os.path.join(ROOT, "tests", "expected", name + ".out"), "w", newline="") as f:
        f.write("".join(l + "\r\n" for l in expect) + "DONE\r\n")
    print(f"gen_fputest: {name}, {len(expect)} cases")


main()
