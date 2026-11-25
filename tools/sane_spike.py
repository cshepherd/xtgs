#!/usr/bin/env python3
"""sane_spike.py [--zip] [--gsos] [--show] [--only vec|time] | --basic [--zip]: M9.1
(docs/8087.md), the SANE tool set tried as an 8087's arithmetic.

Makes tests/sane/gen/vectors.s (operations with the results an 8087 gives,
worked out here in exact arithmetic, and loops to time), assembles
tests/sane/sanebench.s with it, boots it from ProDOS 8 in MAME (--zip: with
the 16 MHz ZipGS; --gsos: launched from GS/OS, a System 6 volume's own
patches to the tool sets in place: SYSTEM6 in the environment, as
make_image.sh has it) and reports: each vector's result against the expected
one, what SANE makes of the encodings an 8087 treats in its own way, and
the time of each operation, the loop's own time taken off.

--basic is the other side of the comparison, arithmetic done by the guest's
own code: tests/sane/fpbase.bas under GW-BASIC and FreeDOS in XT/GS (with
the translator under XTGS_JIT=1), each loop timed by the byte it pokes at
F800:0000. A statement with the operation less the same statement without
it is what the operation costs there, BASIC's own handling of one more
operand included.

Work files in build/sane/ (--basic: build/cgatest/). The Apple Numerics
Manual (2nd ed., 1988), chapters 11-16 and appendix D, is the interface's
authority.
"""
import os
import random
import struct
import subprocess
import sys
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "mame"))
if "--basic" not in sys.argv:
    os.environ["XTGS_LAYOUT"] = "probe"                     # (not XT/GS: no layout to translate or to check)
import mamerun  # noqa: E402
import symbols  # noqa: E402

WORK = os.path.join(ROOT, "build", "sane")
SRC = os.path.join(ROOT, "tests", "sane")
BIAS = 16383
# operation codes and operand formats (appendix D)
ADD, SUB, MUL, DIV, CMP, CPX, REM, Z2X, X2Z, SQRT, RINT, TINT, SCALB, LOGB, CLASS = (
    0x00, 0x02, 0x04, 0x06, 0x08, 0x0A, 0x0C, 0x0E, 0x10, 0x12, 0x14, 0x16, 0x18, 0x1A, 0x1C)
SETENV, GETENV, NEG, ABS = 0x01, 0x03, 0x0D, 0x0F
X, D, S, L, I, C = 0x0000, 0x0100, 0x0200, 0x0300, 0x0400, 0x0500
LNX, LOG2X, LN1X, LOG21X, EXPX, EXP2X, EXP1X, EXP21X, XPWRI, XPWRY, ATANX, SINX, COSX, TANX = (
    0x00, 0x02, 0x04, 0x06, 0x08, 0x0A, 0x0C, 0x0E, 0x10, 0x12, 0x18, 0x1A, 0x1C, 0x1E)
DST, BOTH, VAL, WORD, NONE = 0, 1, 2, 3, 4                  # the call's shapes
ELEMS = 0x100
# the Environment word
RN, RU, RD, RZ = 0x0000, 0x4000, 0x8000, 0xC000
PX, PD, PS = 0x0000, 0x0040, 0x0080
F_INV, F_UNF, F_OVF, F_DVZ, F_INX = 0x0100, 0x0200, 0x0400, 0x0800, 0x1000
FLAGS = {F_INV: "invalid", F_UNF: "underflow", F_OVF: "overflow", F_DVZ: "divide-by-zero", F_INX: "inexact"}
CLASSES = {0xFC: "signaling NaN", 0xFD: "quiet NaN", 0xFE: "infinity", 0xFF: "zero", 0x00: "normalized",
           0x01: "denormalized"}
RELS = {0x40: "SRC > DST", 0x80: "SRC < DST", 0x02: "SRC = DST", 0x01: "unordered"}


# ---- exact arithmetic: an extended number is (-1)^s * m * 2^e2, 2^63 <= m < 2^64 ----
def ext(sign, m, e2):
    """The ten bytes, least significant first (the 8087's layout, and SANE's by the manual)."""
    if m == 0:
        return bytes(8) + struct.pack("<H", sign << 15)
    return m.to_bytes(8, "little") + struct.pack("<H", sign << 15 | (e2 + 63 + BIAS))


def raw(m, se):
    return m.to_bytes(8, "little") + struct.pack("<H", se)


def frac(b):
    m = int.from_bytes(b[:8], "little")
    se, = struct.unpack_from("<H", b, 8)
    return Fraction(-m if se >> 15 else m) * Fraction(2) ** ((se & 0x7FFF) - BIAS - 63)


def rnd(fr, p=64, mode=RN):
    """fr rounded to p significant bits in the mode: (sign, m of 64 bits, e2, inexact)."""
    if fr == 0:
        return 0, 0, 0, False
    s, a = int(fr < 0), abs(fr)
    e = a.numerator.bit_length() - a.denominator.bit_length() - p
    q = a / Fraction(2) ** e
    while q >= 1 << p:
        e += 1
        q /= 2
    while q < 1 << (p - 1):
        e -= 1
        q *= 2
    m = q.numerator // q.denominator
    rem = q - m
    up = {RN: rem > Fraction(1, 2) or (rem == Fraction(1, 2) and m & 1), RU: rem > 0 and not s,
          RD: rem > 0 and s, RZ: False}[mode]
    if up:
        m += 1
        if m == 1 << p:
            m >>= 1
            e += 1
    return s, m << (64 - p), e - (64 - p), rem != 0


def x(fr, p=64, mode=RN):
    s, m, e2, _ = rnd(Fraction(fr), p, mode)
    return ext(s, m, e2)


def isqrt_frac(fr):
    """A stand-in for sqrt(fr) that rounds as it does: exact when it is rational, else strictly between."""
    n, d = fr.numerator, fr.denominator
    num = n * d << 400                                      # sqrt(n/d) = sqrt(n*d) / d
    import math
    r = math.isqrt(num)
    if r * r == num:
        return Fraction(r, d << 200)
    return Fraction(2 * r + 1, d << 201)


def dbl(fr, mode=RN):
    s, m, e2, _ = rnd(Fraction(fr), 53, mode)
    if m == 0:
        return struct.pack("<Q", s << 63)
    return struct.pack("<Q", s << 63 | (e2 + 63 + 1023) << 52 | (m >> 11) & ((1 << 52) - 1))


def sgl(fr, mode=RN):
    s, m, e2, _ = rnd(Fraction(fr), 24, mode)
    if m == 0:
        return struct.pack("<I", s << 31)
    return struct.pack("<I", s << 31 | (e2 + 63 + 127) << 23 | (m >> 40) & ((1 << 23) - 1))


def to_int(fr, mode=RN):
    f = fr.numerator // fr.denominator                       # floor
    rem = fr - f
    return f + int({RN: rem > Fraction(1, 2) or (rem == Fraction(1, 2) and f & 1), RU: rem > 0, RD: False,
                    RZ: rem > 0 and fr < 0}[mode])


PI = raw(0xC90FDAA22168C235, 0x4000)
E = raw(0xADF85458A2BB4A9A, 0x4000)
INDEF = raw(0xC000000000000000, 0xFFFF)                     # the 8087's answer to an invalid operation
INF = raw(0x8000000000000000, 0x7FFF)


def vectors():
    """[(name, opword, shape, env, src, dst, want)], want: None (reported only) or a dict of
    dst (bytes, compared over their length), flags (the exception bits), x (the X register's low byte)."""
    rng = random.Random(8087)
    vals = [Fraction(v) for v in (1, 2, 3, 10, 7, 123456789)] + [Fraction(1, 2), Fraction(-5, 4)]
    vals += [frac(x(Fraction(1, 10))), frac(PI), frac(E), -frac(PI), Fraction(10) ** 10, frac(x(Fraction(1, 10 ** 10))),
             Fraction((1 << 64) - 1), 1 + Fraction(1, 1 << 63)]
    for _ in range(14):
        vals.append(Fraction(rng.getrandbits(64) | 1 << 63) * Fraction(2) ** rng.randint(-103, -23)
                    * rng.choice((1, 1, -1)))
    out = []

    def arith(op, name, fn, pairs, env=RN | PX, fmt=X, src_bytes=None):
        for a, b in pairs:                                  # dst = a <op> b
            p = {PX: 64, PD: 53, PS: 24}[env & 0xC0]
            try:
                exact = fn(a, b)
            except ZeroDivisionError:
                continue
            s, m, e2, inx = rnd(exact, p, env & 0xC000)
            src = src_bytes(b) if src_bytes else x(b)
            out.append((f"{name} {float(a):.6g}, {float(b):.6g}" + (f" env ${env:04X}" if env else "")
                        + (f" src ${fmt:04X}" if fmt else ""), fmt | op, BOTH, env, src, x(a),
                        dict(dst=ext(s, m, e2), flags=F_INX if inx else 0)))

    pairs = [(a, b) for a in vals[:16] for b in (vals[1], vals[9], vals[8], vals[12])][:44]
    pairs += [(vals[16 + i], vals[17 + i]) for i in range(12)]
    for op, name, fn in ((ADD, "add", lambda a, b: a + b), (SUB, "sub", lambda a, b: a - b),
                         (MUL, "mul", lambda a, b: a * b), (DIV, "div", lambda a, b: a / b)):
        arith(op, name, fn, pairs)
        for env in (RU, RD, RZ, RN | PD, RN | PS, RZ | PD, RU | PS):
            arith(op, name, fn, pairs[40:52], env)
    # a source that is not extended: the 8087's memory operands
    exact_d = [Fraction(v) for v in (3, -7, 1000000)] + [frac(x(v, 53)) for v in vals[8:12]]
    arith(ADD, "add", lambda a, b: a + b, [(vals[9], b) for b in exact_d], fmt=D, src_bytes=dbl)
    arith(MUL, "mul", lambda a, b: a * b, [(vals[9], b) for b in exact_d], fmt=D, src_bytes=dbl)
    arith(DIV, "div", lambda a, b: a / b, [(vals[9], b) for b in exact_d], fmt=D, src_bytes=dbl)
    exact_s = [Fraction(v) for v in (3, -7, 1000000)] + [frac(x(v, 24)) for v in vals[8:12]]
    arith(ADD, "add", lambda a, b: a + b, [(vals[10], b) for b in exact_s], fmt=S, src_bytes=sgl)
    arith(MUL, "mul", lambda a, b: a * b, [(vals[10], b) for b in exact_s], fmt=S, src_bytes=sgl)
    ints = [Fraction(v) for v in (1, -1, 12345, -32768, 32767)]
    arith(ADD, "add", lambda a, b: a + b, [(vals[9], b) for b in ints], fmt=I,
          src_bytes=lambda b: struct.pack("<h", int(b)))
    longs = [Fraction(v) for v in (1, -1, 123456789, -2147483648, 2147483647)]
    arith(MUL, "mul", lambda a, b: a * b, [(vals[9], b) for b in longs], fmt=L,
          src_bytes=lambda b: struct.pack("<i", int(b)))
    arith(SUB, "sub", lambda a, b: a - b, [(vals[9], Fraction(v)) for v in (1, -(1 << 62), (1 << 63) - 1)], fmt=C,
          src_bytes=lambda b: struct.pack("<q", int(b)))
    # every operation with every format of source, on operands made to round: the same exponent (a sum
    # of 65 bits: half way when it is odd), one apart, and far apart
    def rand_src(fmt, e2):
        if fmt == X:
            return Fraction(rng.getrandbits(64) | 1 << 63 | 1) * Fraction(2) ** (e2 - 63), x
        if fmt == D:
            return Fraction(rng.getrandbits(53) | 1 << 52) * Fraction(2) ** (e2 - 52), dbl
        if fmt == S:
            return Fraction(rng.getrandbits(24) | 1 << 23) * Fraction(2) ** (e2 - 23), sgl
        n = rng.getrandbits({I: 14, L: 30, C: 62}[fmt]) | 1 << {I: 14, L: 30, C: 62}[fmt]
        return Fraction(n), {I: lambda b: struct.pack("<h", int(b)), L: lambda b: struct.pack("<i", int(b)),
                             C: lambda b: struct.pack("<q", int(b))}[fmt]
    for fmt in (X, D, S, I, L, C):
        for op, name, fn in ((ADD, "add", lambda a, b: a + b), (SUB, "sub", lambda a, b: a - b),
                             (MUL, "mul", lambda a, b: a * b), (DIV, "div", lambda a, b: a / b)):
            for k in range(36):
                b, pack = rand_src(fmt, rng.randint(-8, 8))
                eb = b.numerator.bit_length() - b.denominator.bit_length()
                ea = eb + (0, 0, 1, -1, rng.randint(-70, 70), rng.randint(-12, 12))[k % 6]
                a = Fraction(rng.getrandbits(64) | 1 << 63 | 1) * Fraction(2) ** (ea - 63)
                if rng.random() < 0.3:
                    a = -a
                arith(op, "sweep " + name, fn, [(a, b)], fmt=fmt, src_bytes=pack)
    for env in (RN, RU, RD, RZ, RN | PD, RN | PS):
        p = {PX: 64, PD: 53, PS: 24}[env & 0xC0]
        for a in [abs(v) for v in vals[:12]] + [abs(v) for v in vals[16:22]]:
            s, m, e2, inx = rnd(isqrt_frac(a), p, env & 0xC000)
            out.append((f"sqrt {float(a):.6g}" + (f" env ${env:04X}" if env else ""), SQRT, DST, env, bytes(10),
                        x(a), dict(dst=ext(s, m, e2), flags=F_INX if inx else 0)))
    # to integral values, and to the 8087's memory formats
    halves = [Fraction(v) for v in ("2.5", "3.5", "-2.5", "-3.5", "0.5", "1.5", "-0.5", "7", "123456.75",
                                    "-123456.25", "0.25", "-0.75")]
    for env in (RN, RU, RD, RZ):
        for a in halves:
            n = to_int(a, env)
            out.append((f"rint {float(a)} env ${env:04X}", RINT, DST, env, bytes(10), x(a),
                        dict(dst=x(n) if n else None, flags=F_INX if n != a else 0)))
    for a in halves:
        n = to_int(a, RZ)
        out.append((f"tint {float(a)}", TINT, DST, RN, bytes(10), x(a),
                    dict(dst=x(n) if n else None, flags=F_INX if n != a else 0)))
    for env in (RN, RU, RD, RZ):
        for a in halves + [Fraction(32767), Fraction(-32768), Fraction("32766.5")]:
            n = to_int(a, env)
            for fmt, pk, name in ((I, "<h", "x2i"), (L, "<i", "x2l"), (C, "<q", "x2c")):
                if fmt == I and not -32768 <= n <= 32767:
                    continue                                # (out of range: reported below, not judged)
                out.append((f"{name} {float(a)} env ${env:04X}", fmt | X2Z, BOTH, env, x(a), bytes(10),
                            dict(dst=struct.pack(pk, n), flags=F_INX if n != a else 0)))
    for a in vals[:16]:
        for env in (RN, RU, RD, RZ):
            s, m, e2, inx = rnd(a, 53, env)
            out.append((f"x2d {float(a):.6g} env ${env:04X}", D | X2Z, BOTH, env, x(a), bytes(10),
                        dict(dst=dbl(a, env), flags=F_INX if inx else 0)))
            s, m, e2, inx = rnd(a, 24, env)
            out.append((f"x2s {float(a):.6g} env ${env:04X}", S | X2Z, BOTH, env, x(a), bytes(10),
                        dict(dst=sgl(a, env), flags=F_INX if inx else 0)))
    for a in vals[:16]:
        out.append((f"d2x {float(a):.6g}", D | Z2X, BOTH, RN, dbl(a), bytes(10),
                    dict(dst=x(frac(x(a, 53))), flags=0)))
        out.append((f"s2x {float(a):.6g}", S | Z2X, BOTH, RN, sgl(a), bytes(10),
                    dict(dst=x(frac(x(a, 24))), flags=0)))
    for n in (0, 1, -1, 32767, -32768, 12345):
        out.append((f"i2x {n}", I | Z2X, BOTH, RN, struct.pack("<h", n), bytes(10),
                    dict(dst=x(n) if n else bytes(10), flags=0)))
    for n in (1, -1, 2147483647, -2147483648, 123456789):
        out.append((f"l2x {n}", L | Z2X, BOTH, RN, struct.pack("<i", n), bytes(10), dict(dst=x(n), flags=0)))
    for n in (1, -1, (1 << 63) - 1, -(1 << 63) + 1, 1234567890123456789):
        out.append((f"c2x {n}", C | Z2X, BOTH, RN, struct.pack("<q", n), bytes(10), dict(dst=x(n), flags=0)))
    # comparisons: SRC <relation> DST, in X
    for a, b in ((1, 2), (2, 1), (2, 2), (-1, 1), (frac(PI), frac(E)), (0, 0)):
        want = 0x40 if a > b else 0x80 if a < b else 0x02
        out.append((f"cmp src {float(a):.6g}, dst {float(b):.6g}", CMP, BOTH, RN, x(a), x(b), dict(x=want, flags=0)))
    # ---- what follows is reported, not judged: where an 8087 has ways of its own ----
    one, two, zero, mzero = x(1), x(2), bytes(10), raw(0, 0x8000)
    snan, qnan = raw(0xA000000000000000, 0x7FFF), raw(0xC000000000000000, 0x7FFF)
    for name, b in (("+0", zero), ("-0", mzero), ("1", one), ("-pi", raw(0xC90FDAA22168C235, 0xC000)),
                    ("largest", raw((1 << 64) - 1, 0x7FFE)), ("+infinity", INF),
                    ("-infinity", raw(1 << 63, 0xFFFF)), ("quiet NaN", qnan), ("signaling NaN", snan),
                    ("the 8087's indefinite", INDEF), ("exponent 0, integer bit set (m = 2^63)", raw(1 << 63, 0)),
                    ("exponent 0, integer bit clear (m = 2^62)", raw(1 << 62, 0)),
                    ("exponent 0, m = 1 (the smallest)", raw(1, 0)),
                    ("unnormal: exponent of 1.0, integer bit clear (m = 2^62)", raw(1 << 62, 0x3FFF)),
                    ("exponent $7FFF, m = 0 (infinity without its integer bit)", raw(0, 0x7FFF)),
                    ("exponent $7FFF, integer bit clear, fraction set", raw(1 << 62, 0x7FFF))):
        out.append((f"class of {name}", CLASS, DST, RN, bytes(10), b, None))
    for name, b, n in (("exponent 0, m = 2^63, scaled by 2^16383", raw(1 << 63, 0), 16383),
                       ("exponent 0, m = 2^62, scaled by 2^16384", raw(1 << 62, 0), 16384),
                       ("exponent 1, m = 2^63, scaled by 2^16382", raw(1 << 63, 1), 16382),
                       ("1.0 scaled by 2^-16383", one, -16383), ("1.0 scaled by 2^-16382", one, -16382),
                       ("1.0 scaled by 2^-16400", one, -16400)):
        out.append((f"scalb: {name}", SCALB, VAL, RN, struct.pack("<h", n) + bytes(8), b, None))
    unn = raw(1 << 62, 0x3FFF)
    out.append(("unnormal 0.5 + 0", ADD, BOTH, RN, zero, unn, None))
    out.append(("unnormal 0.5 * 1", MUL, BOTH, RN, one, unn, None))
    out.append(("unnormal 0.5 -> double", D | X2Z, BOTH, RN, unn, bytes(10), None))
    for name, op, shape, src, dst in (
            ("0 / 0", DIV, BOTH, zero, zero), ("infinity - infinity", SUB, BOTH, INF, INF),
            ("0 * infinity", MUL, BOTH, INF, zero), ("sqrt(-1)", SQRT, DST, zero, x(-1)),
            ("1 / 0", DIV, BOTH, zero, one), ("-1 / 0", DIV, BOTH, zero, x(-1)),
            ("1 + signaling NaN", ADD, BOTH, snan, one), ("1 + quiet NaN", ADD, BOTH, qnan, one),
            ("largest * 2", MUL, BOTH, two, raw((1 << 64) - 1, 0x7FFE)),
            ("smallest normal / 2", DIV, BOTH, two, raw(1 << 63, 1)),
            ("1 / 3", DIV, BOTH, x(3), one), ("2^63 -> comp", C | X2Z, BOTH, x(1 << 63), bytes(10)),
            ("-2^63 -> comp", C | X2Z, BOTH, x(-(1 << 63)), bytes(10)),
            ("40000 -> integer", I | X2Z, BOTH, x(40000), bytes(10)),
            ("infinity -> integer", I | X2Z, BOTH, INF, bytes(10)),
            ("NaN -> long", L | X2Z, BOTH, qnan, bytes(10)),
            ("comp $8000000000000000 -> extended", C | Z2X, BOTH, struct.pack("<Q", 1 << 63), bytes(10)),
            ("compare 1 with NaN (FCMP)", CMP, BOTH, qnan, one), ("compare 1 with NaN (FCPX)", CPX, BOTH, qnan, one),
            ("compare +0 with -0", CMP, BOTH, mzero, zero), ("compare infinity with infinity", CMP, BOTH, INF, INF),
            ("1000.7 rem pi", REM, BOTH, PI, x(Fraction(10007, 10))), ("7 rem 2", REM, BOTH, two, x(7)),
            ("-7 rem 2", REM, BOTH, two, x(-7)), ("5 rem 2", REM, BOTH, two, x(5)),
            ("logb pi", LOGB, DST, zero, PI), ("neg +0", NEG, DST, zero, zero), ("abs -pi", ABS, DST, zero, x(-frac(PI)))):
        out.append((name, op, shape, RN, src, dst, None))
    for name, op, dst, src in (("log2(8)", LOG2X, x(8), zero), ("log2(2)", LOG2X, two, zero),
                               ("log2(1+1)", LOG21X, one, zero), ("2^3-1", EXP21X, x(3), zero),
                               ("2^10", EXP2X, x(10), zero), ("2^0.5-1", EXP21X, x(Fraction(1, 2)), zero),
                               ("tan(pi/4)", TANX, raw(0xC90FDAA22168C235, 0x3FFE), zero),
                               ("atan(1)", ATANX, one, zero), ("ln(e)", LNX, E, zero), ("e^1", EXPX, one, zero),
                               ("sin(pi/6)", SINX, x(frac(PI) / 6), zero), ("cos(pi/3)", COSX, x(frac(PI) / 3), zero),
                               ("log2(0)", LOG2X, zero, zero), ("log2(-1)", LOG2X, x(-1), zero),
                               ("tan(1e10)", TANX, x(10 ** 10), zero)):
        out.append((name, op, DST | ELEMS, RN, src, dst, None))
    out.append(("2^10 by x^y", XPWRY, BOTH | ELEMS, RN, x(10), two, None))
    return out


def timings():
    """[(name, opword, shape, times, src, dst)]: the loops; a name that begins '(' is a loop without its call."""
    a, b = PI, E
    far = raw(0xD3C21BCECCEDA100, 0x4040 + 20)              # 1e20 or so: an add with a long shift
    d_pi, s_pi = dbl(frac(PI)), sgl(frac(PI))
    N, NE = 400, 24
    t = [("(two addresses)", ADD, BOTH | 0x80, 2000, a, b), ("(one address)", NEG, DST | 0x80, 2000, a, b),
         ("(a word and an address)", SCALB, VAL | 0x80, 2000, a, b), ("(a word)", SETENV, WORD | 0x80, 2000, bytes(10), b),
         ("(nothing)", GETENV, NONE | 0x80, 2000, a, b),
         ("get the environment", GETENV, NONE, 2000, a, b), ("set the environment", SETENV, WORD, 2000, bytes(10), b),
         ("negate", NEG, DST, 2000, a, b), ("absolute value", ABS, DST, 2000, a, b),
         ("classify", CLASS, DST, 1000, a, b), ("compare", CMP, BOTH, 1000, a, b),
         ("add", ADD, BOTH, N, a, b), ("add, exponents 60 apart", ADD, BOTH, N, far, b), ("subtract", SUB, BOTH, N, a, b),
         ("multiply", MUL, BOTH, N, a, b), ("divide", DIV, BOTH, N, a, b), ("square root", SQRT, DST, N, a, b),
         ("remainder (1000.7 rem pi)", REM, BOTH, N, a, x(Fraction(10007, 10))),
         ("round to integer", RINT, DST, N, a, x(Fraction("123456.789"))),
         ("truncate to integer", TINT, DST, N, a, x(Fraction("123456.789"))),
         ("scale by 2^5", SCALB, VAL, N, struct.pack("<h", 5) + bytes(8), b), ("logb", LOGB, DST, N, a, b),
         ("add a double", D | ADD, BOTH, N, d_pi + bytes(2), b), ("multiply by a double", D | MUL, BOTH, N, d_pi + bytes(2), b),
         ("divide by a double", D | DIV, BOTH, N, d_pi + bytes(2), b), ("add a single", S | ADD, BOTH, N, s_pi + bytes(6), b),
         ("multiply by a single", S | MUL, BOTH, N, s_pi + bytes(6), b),
         ("add a 16-bit integer", I | ADD, BOTH, N, struct.pack("<h", 12345) + bytes(8), b),
         ("add a 32-bit integer", L | ADD, BOTH, N, struct.pack("<i", 123456789) + bytes(6), b),
         ("add a comp", C | ADD, BOTH, N, struct.pack("<q", 1234567890123) + bytes(2), b),
         ("load: extended to extended", X | Z2X, BOTH, N, a, b), ("load a double", D | Z2X, BOTH, N, d_pi + bytes(2), b),
         ("load a single", S | Z2X, BOTH, N, s_pi + bytes(6), b),
         ("load a 16-bit integer", I | Z2X, BOTH, N, struct.pack("<h", 12345) + bytes(8), b),
         ("load a 32-bit integer", L | Z2X, BOTH, N, struct.pack("<i", 123456789) + bytes(6), b),
         ("load a comp", C | Z2X, BOTH, N, struct.pack("<q", 1234567890123) + bytes(2), b),
         ("store a double", D | X2Z, BOTH, N, a, b), ("store a single", S | X2Z, BOTH, N, a, b),
         ("store a 16-bit integer", I | X2Z, BOTH, N, x(Fraction("12345.6")), b),
         ("store a 32-bit integer", L | X2Z, BOTH, N, x(Fraction("123456789.6")), b),
         ("store a comp", C | X2Z, BOTH, N, x(Fraction("1234567890123.6")), b),
         ("log2(x)", LOG2X, DST | ELEMS, NE, a, b), ("log2(1+x)", LOG21X, DST | ELEMS, NE, a, x(Fraction(1, 3))),
         ("2^x-1", EXP21X, DST | ELEMS, NE, a, x(Fraction(1, 3))), ("tan(x)", TANX, DST | ELEMS, NE, a, x(Fraction(1, 3))),
         ("atan(x)", ATANX, DST | ELEMS, NE, a, x(Fraction(1, 3))), ("ln(x)", LNX, DST | ELEMS, NE, a, b),
         ("e^x", EXPX, DST | ELEMS, NE, a, x(Fraction(1, 3))), ("sin(x)", SINX, DST | ELEMS, NE, a, x(Fraction(1, 3))),
         ("cos(x)", COSX, DST | ELEMS, NE, a, x(Fraction(1, 3))), ("x^y", XPWRY, BOTH | ELEMS, NE, a, b)]
    return t


def hexline(b):
    return " hex " + b.hex().upper() + "\n"


def generate(vec, tim):
    os.makedirs(os.path.join(SRC, "gen"), exist_ok=True)
    with open(os.path.join(SRC, "gen", "vectors.s"), "w") as f:
        f.write("* vectors.s - generated by tools/sane_spike.py; do not edit\nvec_tab\n")
        for _n, op, shape, env, src, dst, _w in vec:
            f.write(hexline(struct.pack("<HHH", op, shape, env) + src[:10].ljust(10, b"\0") + dst[:10].ljust(10, b"\0")))
        f.write(" dw $FFFF\ntim_tab\n")
        for i, (_n, op, shape, times, src, dst) in enumerate(tim):
            f.write(hexline(struct.pack("<HHHH", i + 1, op, shape, times) + src[:10].ljust(10, b"\0")
                            + dst[:10].ljust(10, b"\0")))
        f.write(" dw 0\n")


def assemble():
    os.makedirs(WORK, exist_ok=True)
    for n in ("error_output.txt", "_FileInformation.txt", "sanebench_Output.txt", "sanebench"):
        if os.path.exists(os.path.join(SRC, n)):
            os.remove(os.path.join(SRC, n))
    r = subprocess.run(["merlin32", "-V", "sanebench.s"], cwd=SRC, capture_output=True, text=True)
    if os.path.exists(os.path.join(SRC, "sanebench_Output.txt")):
        os.replace(os.path.join(SRC, "sanebench_Output.txt"), os.path.join(WORK, "sanebench.lst"))
    for n in ("error_output.txt", "_FileInformation.txt"):
        if os.path.exists(os.path.join(SRC, n)):
            os.replace(os.path.join(SRC, n), os.path.join(WORK, n))
    if r.returncode or not os.path.exists(os.path.join(SRC, "sanebench")):
        print("\n".join(l for l in r.stdout.splitlines() if "rror" in l or "=>" in l))
        sys.exit("sane_spike: merlin32 failed")
    os.replace(os.path.join(SRC, "sanebench"), os.path.join(WORK, "SANE.SYSTEM#FF2000"))
    subprocess.run([sys.executable, "-I", os.path.join(HERE, "check_mx.py"), os.path.join(WORK, "sanebench.lst")], check=True)
    po = os.path.join(WORK, "sane.po")
    if GSOS:                                                # tests/gsos/start.s quits to /VOL/XTGS/XTGS.SYSTEM
        import shutil
        shutil.copyfile(os.path.join(WORK, "SANE.SYSTEM#FF2000"), os.path.join(WORK, "XTGS.SYSTEM#FF2000"))
        sys6 = os.environ.get("SYSTEM6", os.path.join(ROOT, "..", "ddiigs", "assets", "system6.hdv"))
        subprocess.run([os.path.join(HERE, "gsos_image.sh"), sys6, po, os.path.join(ROOT, "build", "gsos", "Start"),
                        os.path.join(WORK, "XTGS.SYSTEM#FF2000")], check=True, capture_output=True)
    else:
        subprocess.run([os.path.join(HERE, "make_image.sh"), po, os.path.join(WORK, "SANE.SYSTEM#FF2000")],
                       check=True, capture_output=True, env=dict(os.environ, VOLSIZE="800KB"))
    return po, symbols.read(os.path.join(WORK, "sanebench.lst"))


LUA = """
XS = {}                                 -- (globals: a tap that nothing holds is collected, and gone)
local xsp = manager.machine.devices[":maincpu"].spaces["program"]
XTAP = xsp:install_write_tap(%d, %d, "sbphase", function(o, d, m)
    XS[#XS + 1] = string.format("MAMERUN-X T %%d %%.9f", d & 0xFF, manager.machine.time:as_double())
end)
xreport = function()
    for _, l in ipairs(XS) do print(l) end
end
"""


GSOS = "--gsos" in sys.argv
# vectors a boot: the table and what is kept of them end below $BF00, and launched from GS/OS well below
# that (with 600 the system died at the 304th, "Detected trashed memory", $0308: something of its own
# is in the bank's upper half then)
CHUNK = 220 if GSOS else 600


def run(po, syms, nvec, zip_):
    r = mamerun.run(po, waits=[(syms["sb_magic"], 0x5A5A)], seconds=900, settle=2, zip=zip_,
                    card="cffa2" if GSOS else "scsi",
                    dumps=[("hdr", syms["sb_magic"], 10), ("out", syms["OUTBUF"], 18 * nvec)],
                    extra={"top": LUA % (syms["sb_phase"], syms["sb_phase"])})
    if r["status"] != "hit":
        print(r.get("mame_output", "")[-2000:])
        sys.exit(f"sane_spike: the program did not finish ({r['status']})")
    return r


def flags(env):
    return ", ".join(n for b, n in FLAGS.items() if env & b) or "none"


def judge(vec, out, show):
    bad, ties, judged, notes = [], [], 0, []
    for i, (name, op, shape, env, src, dst, want) in enumerate(vec):
        rec = out[18 * i:18 * i + 18]
        got, xr, yr, p, e = rec[:10], *struct.unpack_from("<4H", rec, 10)
        if want is None:
            what = f"result {got[8:10][::-1].hex().upper()} {got[:8][::-1].hex().upper()}"
            if op & 0xFF == CLASS and not shape & ELEMS:
                what = f"{CLASSES.get(xr & 0xFF, hex(xr))}{', negative' if yr & 0x80 else ''}"
            elif op & 0xFF in (CMP, CPX) and not shape & ELEMS:
                what = RELS.get(xr & 0xFF, hex(xr))
            elif op & 0xFF == X2Z and op >> 8:
                what = "result " + got[:{1: 8, 2: 4, 3: 4, 4: 2, 5: 8}[op >> 8]][::-1].hex().upper()
            elif op & 0xFF == REM and not shape & ELEMS:
                what += f", quotient bits ${xr & 0xFF:02X}{' negative' if p & 0x80 else ''}"
            notes.append(f"  {name}: {what}; flags: {flags(e)}")
            continue
        judged += 1
        why = []
        if want.get("dst") is not None and got[:len(want["dst"])] != want["dst"]:
            why.append(f"result {got[:len(want['dst'])][::-1].hex().upper()}, expected {want['dst'][::-1].hex().upper()}")
        if "x" in want and xr & 0xFF != want["x"]:
            why.append(f"X ${xr & 0xFF:02X}, expected ${want['x']:02X}")
        if "flags" in want and e & 0x1F00 != want["flags"]:
            why.append(f"flags {flags(e)}, expected {flags(want['flags'])}")
        if why:
            # what SANE 3.0 and 3.01 both do: a sum or a difference with a source that is not extended, exactly
            # half way between two results, comes back as the odd one of the two and is not called inexact
            w = want.get("dst")
            if (op & 0xFF in (ADD, SUB) and op >> 8 in (1, 2, 3, 4) and w and got[8:10] == w[8:10]
                    and abs(int.from_bytes(got[:8], "little") - int.from_bytes(w[:8], "little")) == 1
                    and got[0] & 1 and not e & F_INX and want["flags"] == F_INX):
                ties.append(f"  {name}: " + "; ".join(why))
            else:
                bad.append(f"  {name}: " + "; ".join(why))
    print(f"{judged} vectors judged against exact arithmetic: {judged - len(bad) - len(ties)} as an 8087 would give "
          f"them, {len(ties)} ties of a mixed-format add or subtract that SANE does not round, {len(bad)} others not")
    for b in ties[:3 if not show else None]:
        print(b)
    for b in bad[:60 if not show else None]:
        print(b)
    print("Reported, not judged:")
    print("\n".join(notes))
    return not bad


def times(tim, r):
    stamps = [l.split() for l in r.get("extra", []) if l.startswith("T ")]
    span, start = {}, None
    for _t, ident, when in stamps:
        ident, when = int(ident), float(when)
        if ident == 0xFF and start:
            span[start[0]] = when - start[1]
            start = None
        else:
            start = (ident, when)
    per = {}
    for i, (name, op, shape, n, _s, _d) in enumerate(tim):
        if i + 1 in span:
            per[name] = span[i + 1] / n * 1e6
    null = {BOTH: per.get("(two addresses)"), DST: per.get("(one address)"), VAL: per.get("(a word and an address)"),
            WORD: per.get("(a word)"), NONE: per.get("(nothing)")}
    rows = []
    for name, op, shape, n, _s, _d in tim:
        if name.startswith("(") or name not in per:
            continue
        rows.append((name, per[name] - (null[shape & 0x7F] or 0)))
    return rows, null


def main():
    args = sys.argv[1:]
    show = "--show" in args
    only = args[args.index("--only") + 1] if "--only" in args else None
    vec, tim = vectors(), timings()
    out, r = b"", None
    for at in range(0, len(vec) if only != "time" else 1, CHUNK):
        part = vec[at:at + CHUNK]
        generate(part, tim if at == 0 and only != "vec" else [])
        po, syms = assemble()
        one = run(po, syms, len(part), False)
        hdr = struct.unpack("<5H", bytes.fromhex(one["dumps"]["hdr"]["hex"]))
        if hdr[4] != len(part) or hdr[3]:
            sys.exit(f"sane_spike: {hdr[4]} of {len(part)} vectors run, SANEStartUp's error ${hdr[3]:04X}")
        out += bytes.fromhex(one["dumps"]["out"]["hex"])
        r = r or one
    print(f"SANE version ${hdr[2]:04X}")
    ok = judge(vec, out, show) if only != "time" else True
    if only != "vec":
        stock, null = times(tim, r)
        if "--zip" in args:
            generate(vec[:1], tim)
            po, syms = assemble()
        fast, _ = times(tim, run(po, syms, 1, True)) if "--zip" in args else ([], None)
        fast = dict(fast)
        print("The loop alone, microseconds a turn: " + ", ".join(f"{k} {v:.0f}" for k, v in
              (("two addresses", null[BOTH]), ("one", null[DST]), ("none", null[NONE])) if v))
        print(f"{'operation':34} {'2.8 MHz':>12} {'cycles':>8}" + (f" {'16 MHz Zip':>12}" if fast else ""))
        for name, us in stock:
            print(f"{name:34} {us:9.0f} us {us * 2.8:8.0f}" + (f" {fast[name]:9.0f} us" if name in fast else ""))
    if not ok:
        sys.exit("FAIL sane: results that are not an 8087's (above)")
    print("PASS sane: every judged vector is what exact arithmetic says an 8087 gives, but for the ties above")


BASIC_LUA = """
XS = {}
local xsp = manager.machine.devices[":maincpu"].spaces["program"]
XTAP = xsp:install_write_tap(at(%d), at(%d), "fpmark", function(o, d, m)
    XS[#XS + 1] = string.format("MAMERUN-X T %%d %%.6f", d & 0xFF, manager.machine.time:as_double())
end)
xreport = function()
    for _, l in ipairs(XS) do print(l) end
end
"""
BASIC_LOOPS = {1: "the loop alone", 2: "A=B (double)", 3: "double add", 4: "double multiply", 5: "double divide",
               6: "Z!=X! (single)", 7: "single add", 8: "single multiply", 9: "single divide", 10: "single SQR",
               11: "single LOG", 12: "single SIN", 13: "single EXP"}


def basic():
    """tests/sane/fpbase.bas: 200 turns a loop, the loop's number poked at F800:0000 before it."""
    subprocess.run([sys.executable, "-I", os.path.join(HERE, "cga_test.py"), os.path.join(SRC, "fpbase.bas"), "1"],
                   capture_output=True, check=False)        # (for the volume it builds)
    mark = 0x2F8000
    r = mamerun.run(os.path.join(ROOT, "build", "cgatest", "fpbase.po"), waits=[(mark, 0x00FF)], dumps=[], seconds=900,
                    settle=2, zip="--zip" in sys.argv, extra={"top": BASIC_LUA % (mark, mark)})
    st = [(int(a), float(b)) for _t, a, b in (l.split() for l in r.get("extra", []) if l.startswith("T "))]
    st = [v for v in st if v[0] in BASIC_LOOPS or v[0] == 255]
    dur = {st[i][0]: (st[i + 1][1] - st[i][1]) / 200 * 1000 for i in range(len(st) - 1)}
    if r["status"] != "hit" or len(dur) != len(BASIC_LOOPS):
        sys.exit(f"sane_spike: the BASIC program did not finish ({r['status']}, {len(dur)} loops timed)")
    print("GW-BASIC's own arithmetic, " + ("the translator" if os.environ.get("XTGS_JIT") else "the interpreter")
          + (", 16 MHz Zip" if "--zip" in sys.argv else ", 2.8 MHz"))
    for k in sorted(dur):
        base = dur[2] if 3 <= k <= 5 else dur[6] if k >= 7 else 0
        print(f"  {BASIC_LOOPS[k]:18} {dur[k]:8.2f} ms a turn" + (f"   the operation {dur[k] - base:7.2f} ms" if base else ""))


if "--basic" in sys.argv:
    basic()
else:
    main()
