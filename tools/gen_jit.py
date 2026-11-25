#!/usr/bin/env python3
"""Generate the translator's tables (docs/jit.md, "M6.3"): src/jit/gen/jtab.s.

    gen_jit.py

What the translator (src/jit) stamps into its code cache is here, as
templates: 65816 code for one guest instruction of one form, with the
places where an operand of that instruction goes (a register's direct-page
offset, an immediate, a displacement...). The tables:

  tp_tab     the templates: length, fixups, the bytes, (offset, slot) pairs
  ts_tab     template sets, one for each thing an opcode with a ModR/M byte
             (or a register in its low bits) can be: its width, the template
             for the register form and the memory form, each without and
             with the lazy flags stored, and the class its native flags are
             for a conditional jump that follows it
  oi_k/p/l/s/u  for each opcode: the emitter's kind and its parameter, what
             follows the opcode byte, the flags it sets and the ones it reads
  gr_tab     the same four for the eight of a group (80-83, D0-D3, F6, F7,
             FE, FF), by the ModR/M byte's middle
  eo_tab     an effective address's offset, by mod and r/m; ea_seg its
             default segment
  jf_tab     a conditional jump on the native flags the instruction before
             it left, by that instruction's class; jg_tab on the lazy flags
  kt_tab     for each kind: nothing falls through it

A template is written below as a list of 65816 instructions, and assembled
here: Merlin never sees them as code, so nothing checks them but the tests
(tools/jit_fuzz.py; XTGS_JIT=1 make test-com). A byte that is a bank of the
layout is written by name, so tools/gen_reloc.py finds it.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "src", "jit", "gen", "jtab.s")
OUT_RT = os.path.join(ROOT, "src", "jit", "gen", "jrt.s")

# ---- the guest's direct page (src/include/guest.s)
rAX, rCX, rDX, rBX, rSP, rBP, rSI, rDI = 0, 2, 4, 6, 8, 10, 12, 14
rFL = 0x1A
bES, bCS, bSS, bDS = 0x1C, 0x20, 0x24, 0x28
pEA = 0x2E
tmp4 = 0x60
rES, rCS, rSS, rDS = 0x10, 0x12, 0x14, 0x16
jG, jEP, jT, jtmp, jtmp2 = 0xC8, 0xCA, 0xCC, 0xD6, 0xD8   # the translator's own (guest.s)
vLP, vLRES, vFS, vFD = 0x4C, 0x4E, 0x76, 0x78
LP_CF, LP_ZF, LP_AFD, LP_OF, LP_SF = 1, 2, 8, 0x40, 0x80
F_DF = 0x0400

# ---- slots: what a fixup takes its value from (src/jit/emit.s, sl_val), and its bytes
SLOTS = {"R": (1, 1), "M": (2, 1), "I8": (3, 1), "I16": (4, 2), "D16": (5, 2), "S0": (6, 1), "S2": (7, 1),
         "IPC": (8, 2), "IPN": (9, 2), "CB": (10, 2), "T16": (11, 2), "SR": (12, 1), "CB2": (13, 2), "EAR": (14, 2)}

# ---- a small 65816 assembler: (mnemonic, mode) -> opcode
OPC = {
    ("lda", "dp"): 0xA5, ("lda", "imm"): 0xA9, ("lda", "il"): 0xA7, ("lda", "abs"): 0xAD,
    ("sta", "dp"): 0x85, ("sta", "il"): 0x87, ("sta", "abs"): 0x8D, ("stz", "dp"): 0x64,
    ("adc", "dp"): 0x65, ("adc", "imm"): 0x69, ("adc", "il"): 0x67,
    ("sbc", "dp"): 0xE5, ("sbc", "imm"): 0xE9, ("sbc", "il"): 0xE7,
    ("and", "dp"): 0x25, ("and", "imm"): 0x29, ("and", "il"): 0x27,
    ("ora", "dp"): 0x05, ("ora", "imm"): 0x09, ("ora", "il"): 0x07,
    ("eor", "dp"): 0x45, ("eor", "imm"): 0x49, ("eor", "il"): 0x47,
    ("cmp", "dp"): 0xC5, ("cmp", "imm"): 0xC9, ("cmp", "il"): 0xC7,
    ("inc", "dp"): 0xE6, ("dec", "dp"): 0xC6, ("inc", "a"): 0x1A, ("dec", "a"): 0x3A,
    ("asl", "a"): 0x0A, ("lsr", "a"): 0x4A, ("rol", "a"): 0x2A, ("ror", "a"): 0x6A,
    ("asl", "dp"): 0x06, ("lsr", "dp"): 0x46, ("rol", "dp"): 0x26, ("ror", "dp"): 0x66,
    ("clc", ""): 0x18, ("sec", ""): 0x38, ("php", ""): 0x08, ("plp", ""): 0x28, ("pha", ""): 0x48, ("pla", ""): 0x68,
    ("tax", ""): 0xAA, ("tay", ""): 0xA8, ("txa", ""): 0x8A, ("tya", ""): 0x98, ("xba", ""): 0xEB,
    ("dex", ""): 0xCA, ("inx", ""): 0xE8, ("dey", ""): 0x88, ("iny", ""): 0xC8, ("nop", ""): 0xEA,
    ("sep", "i8"): 0xE2, ("rep", "i8"): 0xC2,
    ("ldy", "i16"): 0xA0, ("ldx", "i16"): 0xA2, ("ldx", "dp"): 0xA6, ("stx", "dp"): 0x86, ("ldy", "dp"): 0xA4, ("sty", "dp"): 0x84,
    ("cpy", "i16"): 0xC0,
    ("bcc", "rel"): 0x90, ("bcs", "rel"): 0xB0, ("beq", "rel"): 0xF0, ("bne", "rel"): 0xD0, ("bmi", "rel"): 0x30,
    ("bpl", "rel"): 0x10, ("bvc", "rel"): 0x50, ("bvs", "rel"): 0x70, ("bra", "rel"): 0x80,
    ("jmp", "abs"): 0x4C, ("jsr", "abs"): 0x20, ("rts", ""): 0x60, ("rtl", ""): 0x6B,
    ("bit", "dp"): 0x24, ("tsb", "dp"): 0x04, ("trb", "dp"): 0x14,
    ("clv", ""): 0xB8, ("lda", "ily"): 0xB7, ("ora", "dp"): 0x05, ("and", "dp"): 0x25,
}


class Tmpl:
    """One template: width is the accumulator's the code runs with (16 or 8)."""

    def __init__(self, name, width, code):
        self.name, self.width = name, width
        self.bytes, self.fix, labels, refs = [], [], {}, []
        for ins in code:
            if isinstance(ins, str):                       # a label
                labels[ins] = len(self.bytes)
                continue
            mn, mode, arg = (ins + ("", None))[:3] if len(ins) < 3 else ins
            if mode == "imm":                               # by the accumulator's width
                mode, size = ("imm", 2 if width == 16 else 1)
            elif mode in ("i16", "abs"):
                size = 2
            elif mode in ("dp", "il", "ily", "i8", "rel"):
                size = 1
            else:
                size = 0
            key = (mn, "imm" if mode == "imm" else mode)
            if key not in OPC:
                raise SystemExit(f"gen_jit: no opcode for {mn} {mode} in {name}")
            self.bytes.append(OPC[key])
            at = len(self.bytes)
            if size == 0:
                continue
            if mode == "rel":
                refs.append((at, arg))
                self.bytes.append(0)
            elif isinstance(arg, str) and arg in SLOTS:
                sid, ssz = SLOTS[arg]
                if ssz != size:
                    raise SystemExit(f"gen_jit: slot {arg} is {ssz} bytes, {mn} {mode} wants {size} in {name}")
                self.fix.append((at, sid))
                self.bytes += [0] * size
            elif isinstance(arg, str):                      # a name Merlin knows: a helper, a bank
                if size == 2 and arg.startswith("^"):      # (a bank as a 16-bit immediate)
                    self.bytes += [arg, 0]
                elif size == 2:
                    self.bytes += [f"<{arg}", f">{arg}"]
                else:
                    self.bytes.append(arg)
            else:
                self.bytes += [(arg >> (8 * i)) & 0xFF for i in range(size)]
        for at, lab in refs:
            if lab == "SKIP":                               # the emitter's: the last byte of the template
                if at != len(self.bytes) - 1:
                    raise SystemExit(f"gen_jit: SKIP is not the last byte of {name}")
                continue
            to = len(self.bytes) if lab == "END" else labels[lab]
            d = to - (at + 1)
            if not -128 <= d <= 127:
                raise SystemExit(f"gen_jit: branch out of range in {name}")
            self.bytes[at] = d & 0xFF
        if len(self.bytes) > 255 or len(self.fix) > 255:
            raise SystemExit(f"gen_jit: {name} is too long")


TEMPLATES = []
INDEX = {}


def T(name, width, code):
    t = Tmpl(name, width, code)
    INDEX[name] = len(TEMPLATES) + 1                        # 0 is "none"
    TEMPLATES.append(t)
    return INDEX[name]


# ---- the lazy flags, as the interpreter's own tails leave them (tools/gen_cpu.py, tail):
# vFS and vFD the operands, vLRES the result, vLP the 65816's P after the operation. Here the
# native flags are put back afterwards (PLP), so that a conditional jump (or an ADC, an RCL)
# stamped next can still use them.
def keep(w):
    return [("php",), ("php",)] + ([("php",)] if w == 16 else [])


def flags_tail(cls, w):
    out = [("sta", "dp", vLRES)] + keep(w) + [("pla",)]
    if cls == "sub":
        out.append(("eor", "imm", LP_CF))
    if cls == "log":
        out += [("and", "imm", LP_SF + LP_ZF), ("ora", "imm", LP_AFD)]
    if cls == "incdec":
        out += [("eor", "dp", vLP), ("and", "imm", 0xFE if w == 8 else 0x00FE), ("eor", "dp", vLP)]
    return out + [("sta", "dp", vLP), ("plp",)]


ALU = {  # name: (65816 instruction, class, stores, takes CF in)
    "add": ("adc", "add", True, False), "or": ("ora", "log", True, False), "and": ("and", "log", True, False),
    "sub": ("sbc", "sub", True, False), "xor": ("eor", "log", True, False), "cmp": ("sbc", "sub", False, False),
    "test": ("and", "log", False, False), "adc": ("adc", "add", True, True), "sbb": ("sbc", "sub", True, True),
}
CARRY = {"add": [("clc",)], "sub": [("sec",)], "log": []}


def alu(name, w, dst, src):
    """dst = dst op src: (without the flags, with them). dst and src are (mode, operand). ADC and SBB
    begin with the carry already the 65816's (the emitter's work: cin, cinv, or the instruction before)."""
    ins, cls, store, cin = ALU[name]
    st = [("sta",) + dst] if store else []
    if cls == "log":
        plain = [("lda",) + dst, (ins,) + src] + st
        return plain, plain + flags_tail(cls, w)
    c = [] if cin else CARRY[cls]
    plain = [("lda",) + dst] + c + [(ins,) + src] + st
    full = ([("lda",) + src, ("sta", "dp", vFS), ("lda",) + dst, ("sta", "dp", vFD)] + c +
            [(ins, "dp", vFS)] + st + flags_tail(cls, w))
    return plain, full


SETS = []                                                   # (flags, t_rr, t_rr_f, t_m, t_m_f, fclass)
SET_INDEX = {}
# a set's flags: 8-bit; the memory form writes; a word in memory; a segment register named by the ModR/M
# byte's middle (slots SR, S0, S2); four bytes in memory; CF comes in as the 65816's carry, or inverted
W8, MEMW, WORDMEM, SREG, FAR, CIN, CINV = 1, 2, 4, 8, 16, 32, 64
# the class of the native flags an instruction of the set leaves: sub (C inverted), add, log (N and Z),
# incdec (N and Z), nzc (N, Z and C: a shift), conly (C: a rotate)
FCLASS = {"none": 0, "sub": 1, "add": 2, "log": 3, "incdec": 4, "nzc": 5, "conly": 6}


def tset(name, w, rr, mm, cls="none", writes=False, extra=0):
    """A template set. rr and mm are (plain, with flags) code lists or None."""
    ids = []
    for form, pair in (("rr", rr), ("m", mm)):
        for flag, code in zip(("", "f"), pair or (None, None)):
            if code is None:
                ids.append(0)
            elif flag == "f" and code is pair[0]:
                ids.append(ids[-1])                         # no flags to store: the same template
            else:
                ids.append(T(f"{name}_{form}{flag}", w, code))
    fl = (W8 if w == 8 else 0) | (MEMW if writes else 0) | (WORDMEM if w == 16 else 0) | extra
    SET_INDEX[name] = len(SETS)
    SETS.append((fl, ids[0], ids[1], ids[2], ids[3], FCLASS[cls]))
    return SET_INDEX[name]


def same(code):
    return (code, code)


def setseg(sr, b0, b2):
    """A (16 bits) into a segment register and its base: the core's set_es and the others."""
    return [("sta", "dp", sr)] + [("asl", "a")] * 4 + [("sta", "dp", b0), ("lda", "dp", sr), ("xba",)] + \
        [("lsr", "a")] * 4 + [("and", "imm", 0x000F), ("ora", "imm", "GUEST_BANK"), ("sta", "dp", b2)]


# ---- shifts and rotates by one (the interpreter's: ops_grp.s, flags.s). A shift's flags are all its own
# (AF "defined": LP_AFD); a rotate changes CF and OF and nothing else.
def shift_tail(w, v):
    return keep(w) + [("pla",), ("and", "imm", 0xC3 if v else 0x83), ("ora", "imm", LP_AFD), ("sta", "dp", vLP), ("plp",)]


def rot_tail(w, kind, res):
    """CF is the 65816's carry; res is where the result is. OF: for a turn left the top bit against CF,
    for a turn right the top two bits against each other."""
    out = keep(w) + [("pla",), ("and", "imm", 1), ("sta", "dp", jT), ("lda",) + res, ("asl", "a")]
    if kind == "l":
        out += [("lda", "dp", jT), ("bcc", "rel", "k"), ("eor", "imm", 1), "k", ("beq", "rel", "n"), ("lda", "imm", LP_OF), "n"]
    else:
        out += [("bcc", "rel", "k"), ("bmi", "rel", "o0"), ("bra", "rel", "o1"), "k", ("bpl", "rel", "o0"),
                "o1", ("lda", "imm", LP_OF), ("bra", "rel", "s"), "o0", ("lda", "imm", 0), "s"]
    return out + [("ora", "dp", jT), ("eor", "dp", vLP), ("and", "imm", LP_CF + LP_OF), ("eor", "dp", vLP),
                  ("sta", "dp", vLP), ("plp",)]


def shift1(kind, w, d):
    """(plain, with flags) for one of ROL ROR RCL RCR SHL SHR SAR by one on d: ("dp", "M") or ("il", pEA)."""
    msb = 0x8000 if w == 16 else 0x80
    reg = d[0] == "dp"
    ld, st = [("lda",) + d], [("sta",) + d]
    if kind == "shl":
        plain = [("asl", "dp", d[1])] if reg else ld + [("asl", "a")] + st
        full = ld + [("clc",), ("adc",) + d] + st + [("sta", "dp", vLRES)] + shift_tail(w, True)
    elif kind == "shr":
        plain = [("lsr", "dp", d[1])] if reg else ld + [("lsr", "a")] + st
        full = ld + [("lsr", "a")] + st + [("sta", "dp", vLRES), ("bit", "dp", vLRES)] + shift_tail(w, True)
    elif kind == "sar":
        plain = (ld + [("asl", "a"), ("ror", "dp", d[1])]) if reg else ld + [("cmp", "imm", msb), ("ror", "a")] + st
        full = ld + [("cmp", "imm", msb), ("ror", "a")] + st + [("sta", "dp", vLRES)] + shift_tail(w, False)
    elif kind == "rol":
        plain = (ld + [("asl", "a"), ("rol", "dp", d[1])]) if reg else ld + [("cmp", "imm", msb), ("rol", "a")] + st
        full = plain + rot_tail(w, "l", d)
    elif kind == "ror":
        plain = (ld + [("lsr", "a"), ("ror", "dp", d[1])]) if reg else ld + [("lsr", "a")] + ld + [("ror", "a")] + st
        full = plain + rot_tail(w, "r", d)
    elif kind == "rcl":
        plain = [("rol", "dp", d[1])] if reg else ld + [("rol", "a")] + st
        full = plain + rot_tail(w, "l", d)
    else:
        plain = [("ror", "dp", d[1])] if reg else ld + [("ror", "a")] + st
        full = plain + rot_tail(w, "r", d)
    return plain, full


def by_cl(kind, w, body):
    """The same by CL on a register: all but the last step in a loop on A, then the step by one. A count
    of nothing does nothing (and changes no flag). jT counts."""
    msb = 0x8000 if w == 16 else 0x80
    step = {"shl": [("asl", "a")], "shr": [("lsr", "a")], "sar": [("cmp", "imm", msb), ("ror", "a")],
            "rol": [("cmp", "imm", msb), ("rol", "a")], "ror": [("lsr", "a"), ("bcc", "rel", "r"), ("ora", "imm", msb), "r"],
            "rcl": [("rol", "a")], "rcr": [("ror", "a")]}[kind]
    count = [("lda", "dp", rCX)] + ([("and", "imm", 0x00FF)] if w == 16 else []) + [("beq", "rel", "END"), ("sta", "dp", jT)]
    return count + [("dec", "dp", jT), ("beq", "rel", "last"), ("lda", "dp", "M"), "l"] + step + \
        [("dec", "dp", jT), ("bne", "rel", "l"), ("sta", "dp", "M"), "last"] + body


R, M, EA = ("dp", "R"), ("dp", "M"), ("il", pEA)
SHIFTS = ("rol", "ror", "rcl", "rcr", "shl", "shr", None, "sar")
for w in (16, 8):
    s = "w" if w == 16 else "b"
    I = ("imm", "I16" if w == 16 else "I8")
    for name in ("add", "or", "and", "sub", "xor", "cmp", "test", "adc", "sbb"):
        cls = ALU[name][1]
        wr = ALU[name][2]
        x = (CINV if cls == "sub" else CIN) if ALU[name][3] else 0
        tset(f"{name}_rm_r_{s}", w, alu(name, w, M, R), alu(name, w, EA, R), cls, wr, x)    # r/m op= reg
        if name != "test":
            tset(f"{name}_r_rm_{s}", w, alu(name, w, R, M), alu(name, w, R, EA), cls, False, x)   # reg op= r/m
        tset(f"{name}_rm_i_{s}", w, alu(name, w, M, I), alu(name, w, EA, I), cls, wr, x)    # r/m op= imm
    mv = lambda d, sr: same([("lda",) + sr, ("sta",) + d])  # noqa: E731
    tset(f"mov_rm_r_{s}", w, mv(M, R), mv(EA, R), writes=True)
    tset(f"mov_r_rm_{s}", w, mv(R, M), mv(R, EA))
    tset(f"mov_rm_i_{s}", w, mv(M, I), mv(EA, I), writes=True)
    for name, ins, cin in (("inc", "adc", "clc"), ("dec", "sbc", "sec")):
        one_ = ("imm", 1)
        # (the interpreter's: the operand in vFD, vFS 0, CF kept; tools/gen_cpu.py)
        def incdec(d):
            plain = [(name, "dp", d[1])] if d[0] == "dp" else [("lda",) + d, (name, "a"), ("sta",) + d]
            full = [("lda",) + d, ("sta", "dp", vFD), (cin,), (ins,) + one_, ("sta",) + d, ("stz", "dp", vFS)] + \
                flags_tail("incdec", w)
            return plain, full
        tset(f"{name}_rm_{s}", w, incdec(M), incdec(EA), "incdec", True)
    nt = lambda d: same([("lda",) + d, ("eor", "imm", 0xFFFF if w == 16 else 0xFF), ("sta",) + d])   # noqa: E731
    tset(f"not_rm_{s}", w, nt(M), nt(EA), writes=True)
    ng = lambda d: ([("lda", "imm", 0), ("sec",), ("sbc",) + d, ("sta",) + d],                        # noqa: E731
                    [("lda",) + d, ("sta", "dp", vFS), ("stz", "dp", vFD), ("lda", "imm", 0), ("sec",),
                     ("sbc", "dp", vFS), ("sta",) + d] + flags_tail("sub", w))
    tset(f"neg_rm_{s}", w, ng(M), ng(EA), "sub", True)
    tset(f"xchg_rm_r_{s}", w, same([("lda",) + M, ("pha",), ("lda",) + R, ("sta",) + M, ("pla",), ("sta",) + R]),
         same([("lda",) + EA, ("pha",), ("lda",) + R, ("sta",) + EA, ("pla",), ("sta",) + R]), writes=True)
    for kind in SHIFTS:
        if kind is None:
            continue
        rot = kind in ("rol", "ror", "rcl", "rcr")
        x = CIN if kind in ("rcl", "rcr") else 0
        tset(f"{kind}1_{s}", w, shift1(kind, w, M), shift1(kind, w, EA), "conly" if rot else "nzc", True, x)
        pl, fu = shift1(kind, w, M)
        tset(f"{kind}c_{s}", w, (by_cl(kind, w, pl), by_cl(kind, w, fu)), None, "none", True, x)
# LEA: the offset is in A when the template begins (the emitter stamps it after the eo_ one)
tset("lea", 16, None, same([("sta",) + R]))
# PUSH and POP: the stack through the helpers, which need the instruction's IP in Y
tset("push_r", 16, same([("lda",) + M, ("ldy", "i16", "IPC"), ("jsr", "abs", "h_push")]), None)
tset("pop_r", 16, same([("ldy", "i16", "IPC"), ("jsr", "abs", "h_pop"), ("sta",) + M]), None)
tset("push_rm", 16, None, same([("lda",) + EA, ("ldy", "i16", "IPC"), ("jsr", "abs", "h_push")]))
# (POP to memory: the pointer first, which SP has no part in, and the helper keeps it)
tset("pop_rm", 16, same([("ldy", "i16", "IPC"), ("jsr", "abs", "h_pop"), ("sta",) + M]),
     same([("ldy", "i16", "IPC"), ("jsr", "abs", "h_pop"), ("sta",) + EA]), writes=True)
# the segment registers: MOV to one and from one (the ModR/M byte's middle says which), LES and LDS
tset("mov_sr_rm", 16, same([("lda",) + M] + setseg("SR", "S0", "S2")), same([("lda",) + EA] + setseg("SR", "S0", "S2")),
     extra=SREG)
tset("mov_rm_sr", 16, same([("lda", "dp", "SR"), ("sta",) + M]), same([("lda", "dp", "SR"), ("sta",) + EA]),
     writes=True, extra=SREG)
for nm, sr, b in (("les", rES, bES), ("lds", rDS, bDS)):
    tset(nm, 16, None, same([("lda",) + EA, ("pha",), ("ldy", "i16", 2), ("lda", "ily", pEA)] + setseg(sr, b, b + 2) +
                            [("pla",), ("sta",) + R]), extra=FAR)
# a jump or a call through a register or a word in memory: the word is the IP the dispatcher takes
tset("jmp_ind", 16, same([("lda",) + M, ("tay",), ("jmp", "abs", "h_disp")]),
     same([("lda",) + EA, ("tay",), ("jmp", "abs", "h_disp")]))
tset("call_ind", 16, same([("lda",) + M, ("sta", "dp", jT), ("lda", "imm", "IPN"), ("ldy", "i16", "IPC"),
                           ("jsr", "abs", "h_push"), ("ldy", "dp", jT), ("jmp", "abs", "h_disp")]),
     same([("lda",) + EA, ("sta", "dp", jT), ("lda", "imm", "IPN"), ("ldy", "i16", "IPC"), ("jsr", "abs", "h_push"),
           ("ldy", "dp", jT), ("jmp", "abs", "h_disp")]))
T("cbw", 16, [("lda", "dp", rAX), ("and", "imm", 0x00FF), ("cmp", "imm", 0x0080), ("bcc", "rel", "p"),
              ("ora", "imm", 0xFF00), "p", ("sta", "dp", rAX)])
T("cwd", 16, [("lda", "dp", rAX), ("asl", "a"), ("lda", "imm", 0), ("bcc", "rel", "p"), ("dec", "a"), "p", ("sta", "dp", rDX)])
T("xchg_ax", 16, [("lda", "dp", rAX), ("tay",), ("lda",) + M, ("sta", "dp", rAX), ("tya",), ("sta",) + M])
for nm, sr, b in (("es", rES, bES), ("cs", rCS, bCS), ("ss", rSS, bSS), ("ds", rDS, bDS)):
    T(f"push_{nm}", 16, [("lda", "dp", sr), ("ldy", "i16", "IPC"), ("jsr", "abs", "h_push")])
    if nm != "cs":
        T(f"pop_{nm}", 16, [("ldy", "i16", "IPC"), ("jsr", "abs", "h_pop")] + setseg(sr, b, b + 2) +
          ([("jsr", "abs", "sp_sync")] if nm == "ss" else []))        # (the stack's remembered range is another SS's)
# after a MOV to SS (the emitter stamps it: em_gen)
T("spsync", 16, [("jsr", "abs", "sp_sync")])
# CF for an ADC, an SBB, an RCL or an RCR that the instruction before did not leave in the carry
T("cin", 16, [("lda", "dp", vLP), ("lsr", "a")])
T("cinv", 16, [("lda", "dp", vLP), ("eor", "imm", 1), ("lsr", "a")])
T("cflip", 16, [("lda", "imm", 0), ("rol", "a"), ("eor", "imm", 1), ("lsr", "a")])      # the carry the other way up

# ---- an effective address. The offset, by mod and r/m, in A:
BASES = [(rBX, rSI), (rBX, rDI), (rBP, rSI), (rBP, rDI), (rSI,), (rDI,), (rBP,), (rBX,)]
EO = []
for disp in (False, True):
    for rm in range(8):
        if rm == 6 and not disp:
            EO.append(T("eo_d16", 16, [("lda", "imm", "D16")]))
            continue
        code = [("lda", "dp", BASES[rm][0])]
        for b in BASES[rm][1:]:
            code += [("clc",), ("adc", "dp", b)]
        if disp:
            code += [("clc",), ("adc", "imm", "D16")]
        EO.append(T(f"eo_{rm}{'d' if disp else ''}", 16, code))
EA_SEG = [bDS, bDS, bSS, bSS, bDS, bDS, bSS, bDS]           # (r/m 6 with no displacement is DS: the emitter knows)
# A helper that gives the instruction back to the interpreter needs its IP: every JSR to one has LDY #IP
# straight before it, and the helper reads the IP from there (h_bailr), so Y is its own to use meanwhile.
T("ea_y", 16, [("ldy", "i16", "IPC")])


# The host pointer is made by a routine of the run-time bank, one for each segment base, for a read or a
# write, for a byte, a word or four bytes (gen/jrt.s; ea_rt has their addresses, by base * 6 + write * 3 +
# size): the base and the offset in A, the bank past a carry; then what the bank says. A word at offset
# FFFFh is in two places (and four bytes from FFFDh): the interpreter's work. A store onto a page that
# translated code was made from (pg_map: the page's flag, and for a word or four bytes the next page's, both
# in the one word read) asks h_smc whether it is into such code, by an entry that knows how long the store
# is: a byte beside code is not a word on it.
def ea_routines():
    L = ["* jrt.s - generated by tools/gen_jit.py; do not edit.", ""]
    names = []
    tail = [" clc", " adc @B@", " sta pEA", " lda @B@+2", " bcc :nc", " adc #0", " and #$000F", " ora #GUEST_BANK",
            ":nc", " sta pEA+2", " cmp #^H_EGA", " bcs :hi"]
    for seg, b in (("es", "bES"), ("cs", "bCS"), ("ss", "bSS"), ("ds", "bDS")):
        base = f"ea_{seg}_r"
        names += [base + "b", base + "w", base + "f"]
        L += [base + "f", " mx %00", " cmp #$FFFD", f" bcc {base}b", " jmp ea_bail",
              base + "w", " mx %00", " cmp #$FFFF", f" bne {base}b", " jmp ea_bail",
              base + "b", " mx %00"] + [t.replace("@B@", b) for t in tail] + [" rts", ":hi", " jmp h_hi"]
        base = f"ea_{seg}_w"
        names += [base + "b", base + "w", base + "f"]
        for size, guard, mask, smc in (("b", [], "$0001", "h_smcb"),
                                       ("w", [" cmp #$FFFF", " bne :in", " jmp ea_bail", ":in"], "$0101", "h_smc"),
                                       ("f", [" cmp #$FFFD", " bcc :in", " jmp ea_bail", ":in"], "$0101", "h_smcf")):
            L += [base + size, " mx %00"] + guard + [t.replace("@B@", b) for t in tail] + \
                 [" lda pEA+1", " and #$0FFF", " tax", " lda >pg_map,x", f" and #{mask}", " bne :smc", " rts",
                  ":smc", f" jmp {smc}", ":hi", " jmp h_hi"]
    L += ["ea_bail", " mx %00", " jmp h_bailr", ""]
    with open(OUT_RT, "w") as f:
        f.write("\n".join(L))
    return names


# A memory operand that is only read is fetched into jT, and the instruction's register form is stamped
# with jT for its r/m: the segment's base is the pointer and the offset the index, when the base is low
# enough for that to reach nothing but memory (below 9000:0: no video, no wrap at the megabyte); else, and
# for a word at FFFFh, by the pointer routine (slot EAR). The offset is in A, or the instruction's own
# 16 bits (D16).
def fetch(w, d16):
    c = []
    if d16:
        c += [("ldy", "i16", "D16")]
    else:
        if w == 16:
            c += [("cmp", "imm", 0xFFFF), ("beq", "rel", "s")]
        c += [("tay",)]
    c += [("lda", "dp", "S2"), ("cmp", "imm", "^H_HIGH9"), ("bcs", "rel", "s2"), ("lda", "ily", "S0"), ("bra", "rel", "d"), "s2"]
    if w == 8:
        c += [("rep", "i8", 0x20)]
    c += [("tya",)]
    if w == 16 and not d16:
        c += ["s"]
    c += [("ldy", "i16", "IPC"), ("jsr", "abs", "EAR")]
    if w == 8:
        c += [("sep", "i8", 0x20)]
    return c + [("lda", "il", pEA), "d", ("sta", "dp", jT)]


T("fetch_b", 8, fetch(8, False))
T("fetch_w", 16, fetch(16, False))
T("fetch_bd", 8, fetch(8, True))
T("fetch_wd", 16, fetch(16, True))

# ---- the string instructions alone: the pointer by the pieces above, then these
T("lods_b", 8, [("lda",) + EA, ("sta", "dp", rAX)])
T("lods_w", 16, [("lda",) + EA, ("sta", "dp", rAX)])
T("stos_b", 8, [("lda", "dp", rAX), ("sta",) + EA])
T("stos_w", 16, [("lda", "dp", rAX), ("sta",) + EA])
T("movs_ld_b", 8, [("lda",) + EA, ("sta", "dp", tmp4)])
T("movs_ld_w", 16, [("lda",) + EA, ("sta", "dp", tmp4)])
T("movs_st_b", 8, [("lda", "dp", tmp4), ("sta",) + EA])
T("movs_st_w", 16, [("lda", "dp", tmp4), ("sta",) + EA])


def adv(reg, n):                                            # SI or DI on by the element, the way DF says
    up = [("inc", "dp", reg)] * n
    dn = [("dec", "dp", reg)] * n
    return [("lda", "dp", rFL), ("and", "imm", F_DF), ("bne", "rel", "d")] + up + [("bra", "rel", "END"), "d"] + dn


for reg, nm in ((rSI, "si"), (rDI, "di")):
    T(f"adv_{nm}1", 16, adv(reg, 1))
    T(f"adv_{nm}2", 16, adv(reg, 2))


# ---- a conditional jump. Each ends with a branch over the code for "taken", which the emitter
# stamps next and whose length it then puts in the template's last byte.
def cond_fused(cls, cc):
    c_set = "bcc" if cls == "sub" else "bcs"                 # the branch taken when the guest's CF is set
    c_clr = "bcs" if cls == "sub" else "bcc"
    if cls == "incdec" and cc not in (4, 5, 8, 9):
        return None                                         # INC and DEC leave V and C the 65816's own
    if cls == "conly" and cc not in (2, 3):
        return None
    if cls == "nzc" and cc not in (2, 3, 4, 5, 6, 7, 8, 9):
        return None                                         # (V is not the shift's)
    if cls == "log":                                        # CF and OF are 0
        return {0: "never", 1: "always", 2: "never", 3: "always", 4: [("bne", "rel", "SKIP")],
                5: [("beq", "rel", "SKIP")], 6: [("bne", "rel", "SKIP")], 7: [("beq", "rel", "SKIP")],
                8: [("bpl", "rel", "SKIP")], 9: [("bmi", "rel", "SKIP")], 12: [("bpl", "rel", "SKIP")],
                13: [("bmi", "rel", "SKIP")], 14: [("beq", "rel", "END"), ("bpl", "rel", "SKIP")],
                15: [("beq", "rel", "s"), ("bpl", "rel", "END"), "s", ("bra", "rel", "SKIP")]}.get(cc)
    less = [("bvs", "rel", "v"), ("bmi", "rel", "END"), ("bra", "rel", "s"), "v", ("bpl", "rel", "END"), "s",
            ("bra", "rel", "SKIP")]
    geq = [("bvs", "rel", "v"), ("bpl", "rel", "END"), ("bra", "rel", "s"), "v", ("bmi", "rel", "END"), "s",
           ("bra", "rel", "SKIP")]
    return {0: [("bvc", "rel", "SKIP")], 1: [("bvs", "rel", "SKIP")],
            2: [(c_clr, "rel", "SKIP")], 3: [(c_set, "rel", "SKIP")],
            4: [("bne", "rel", "SKIP")], 5: [("beq", "rel", "SKIP")],
            6: [(c_set, "rel", "END"), ("beq", "rel", "END"), ("bra", "rel", "SKIP")],
            7: [(c_set, "rel", "s"), ("bne", "rel", "END"), "s", ("bra", "rel", "SKIP")],
            8: [("bpl", "rel", "SKIP")], 9: [("bmi", "rel", "SKIP")],
            12: less, 13: geq, 14: [("beq", "rel", "END")] + less,
            15: [("beq", "rel", "s2")] + geq[:-2] + ["s", "s2", ("bra", "rel", "SKIP")]}.get(cc)


ALWAYS, NEVER = 0xFFFF, 0xFFFE
JF = []                                                     # [class 1-6][cc]
for cls in ("sub", "add", "log", "incdec", "nzc", "conly"):
    row = []
    for cc in range(16):
        c = cond_fused(cls, cc)
        if cls in ("nzc", "conly") and c is not None:       # (the add class's own template)
            row.append(INDEX[f"jf_add_{cc}"])
            continue
        row.append(0 if c is None else ALWAYS if c == "always" else NEVER if c == "never" else T(f"jf_{cls}_{cc}", 16, c))
    JF.append(row)
# on the lazy flags, as the interpreter's own handlers test them (tools/gen_cpu.py, JCC); parity is not here
LESS = [("lda", "dp", vLP), ("asl", "a"), ("eor", "dp", vLP), ("and", "imm", LP_SF)]


def lz(mask, taken_if_set):
    return [("lda", "dp", vLP), ("and", "imm", mask), ("beq" if taken_if_set else "bne", "rel", "SKIP")]


JG_CODE = {0: lz(LP_OF, True), 1: lz(LP_OF, False), 2: lz(LP_CF, True), 3: lz(LP_CF, False), 4: lz(LP_ZF, True),
           5: lz(LP_ZF, False), 6: lz(LP_CF + LP_ZF, True), 7: lz(LP_CF + LP_ZF, False), 8: lz(LP_SF, True),
           9: lz(LP_SF, False), 12: LESS + [("beq", "rel", "SKIP")], 13: LESS + [("bne", "rel", "SKIP")],
           14: LESS + [("bne", "rel", "END"), ("lda", "dp", vLP), ("and", "imm", LP_ZF), ("beq", "rel", "SKIP")],
           15: LESS + [("bne", "rel", "s"), ("lda", "dp", vLP), ("and", "imm", LP_ZF), ("beq", "rel", "END"), "s",
                       ("bra", "rel", "SKIP")]}
JG = [T(f"jg_{cc}", 16, JG_CODE[cc]) if cc in JG_CODE else 0 for cc in range(16)]
T("loop", 16, [("dec", "dp", rCX), ("beq", "rel", "SKIP")])
T("jcxz", 16, [("lda", "dp", rCX), ("bne", "rel", "SKIP")])

# ---- the ways out and the pieces around a jump (the core's side of them: jitc.s, jit_ret)
T("w8", 16, [("sep", "i8", 0x20)])
T("w16", 8, [("rep", "i8", 0x20)])
# on at IP T16, wherever its code is: the first time by the map, and then the JSR is a JMP to the code
T("linkf", 16, [("ldy", "i16", "T16"), ("jsr", "abs", "h_linkf")])
T("linkb", 16, [("ldy", "i16", "T16"), ("jsr", "abs", "h_linkb")])              # (back: the guard counts it)
T("jmp", 16, [("jmp", "abs", "T16")])
T("guard", 16, [("dec", "dp", jG), ("bne", "rel", "END"), ("ldy", "i16", "T16"), ("jmp", "abs", "h_gx")])
# (the piece is gone on with after it: the core is told which bank of code it is in, above the 3)
T("step", 16, [("lda", "imm", "IPN"), ("sta", "dp", jtmp2), ("lda", "imm", "T16"), ("sta", "dp", jtmp),
               ("ldy", "i16", "IPC"), ("lda", "abs", "rt_flag"), ("xba",), ("ora", "imm", 3), ("rtl",)])
for n in (0, 5, 6, 7, 8, 9):
    T(f"x{n}", 16, [("ldy", "i16", "IPC"), ("lda", "imm", n), ("rtl",)])
T("call", 16, [("lda", "imm", "IPN"), ("ldy", "i16", "IPC"), ("jsr", "abs", "h_push")])
T("ret", 16, [("ldy", "i16", "IPC"), ("jsr", "abs", "h_pop"), ("tay",), ("jmp", "abs", "h_disp")])
T("retn", 16, [("ldy", "i16", "IPC"), ("jsr", "abs", "h_pop"), ("tay",), ("lda", "dp", rSP), ("clc",),
               ("adc", "imm", "I16"), ("sta", "dp", rSP), ("jmp", "abs", "h_disp")])
T("retf", 16, [("ldy", "i16", "IPC"), ("jsr", "abs", "h_retf"), ("jmp", "abs", "h_disp")])
T("clc", 16, [("lda", "dp", vLP), ("and", "imm", 0xFFFE), ("sta", "dp", vLP)])
T("stc", 16, [("lda", "dp", vLP), ("ora", "imm", 0x0001), ("sta", "dp", vLP)])
T("cmc", 16, [("lda", "dp", vLP), ("eor", "imm", 0x0001), ("sta", "dp", vLP)])
T("cld", 16, [("lda", "dp", rFL), ("and", "imm", 0xFFFF - F_DF), ("sta", "dp", rFL)])
T("std", 16, [("lda", "dp", rFL), ("ora", "imm", F_DF), ("sta", "dp", rFL)])

# ---- the opcodes
(K_EXIT, K_STEP, K_GEN, K_JCC, K_JMP8, K_JMP16, K_LOOP, K_JCXZ, K_STR, K_GRP, K_SEG, K_ONE, K_LEA, K_CALL, K_RET,
 K_IND) = range(16)
KNAMES = ("EXIT", "STEP", "GEN", "JCC", "JMP8", "JMP16", "LOOP", "JCXZ", "STR", "GRP", "SEG", "ONE", "LEA", "CALL", "RET",
          "IND")
KT = [1 if k in (K_EXIT, K_JMP8, K_JMP16, K_CALL, K_RET, K_IND) else 0 for k in range(16)]
# what follows the opcode byte: a ModR/M byte; an immediate of 8 or 16 bits (SX: the 8 sign-extended to the
# operand's 16); the operand is the register in the opcode's low three bits, or AL/AX (ACC), or the byte or
# word at a 16-bit address (MOFFS); F6: an immediate only for /0 and /1, its size the operand's
L_MODRM, L_I8, L_I16, L_SX, L_REGOP, L_MOFFS, L_ACC, L_F6 = 1, 2, 4, 8, 16, 32, 64, 128
C, P, A, Z, S, O = 1, 2, 4, 8, 16, 32
ALLF = C | P | A | Z | S | O
NOC = ALLF & ~C
JCC_USES = [O, O, C, C, Z, Z, C | Z, C | Z, S, S, P, P, S | O, S | O, S | O | Z, S | O | Z]
# K_EXIT's parameter is how the core goes on (jitc.s): 0 the interpreter from there; 5 the interpreter
# for that one instruction and then whatever code there is for where it lands, translated code no longer
# trusted (the instruction may have written anywhere); 6 the same when all it wrote is the stack; 7 when
# it wrote nothing; 8 a REP MOVS or STOS, whose bytes are then held against the pages of code. K_STEP's
# parameter 1: its operand in memory is written (then it is K_EXIT 5).
PLAIN, ANY, STACK, PURE, STRING = 0, 5, 6, 7, 8           # (8: a REP MOVS or STOS, scan.s: what it wrote is looked at)

oi = [[K_EXIT, PLAIN, 0, 0, 0] for _ in range(256)]         # kind, param, what follows, sets, uses
ONE = [0]                                                   # K_ONE's and K_RET's parameter is a place in this list


def one(name):
    ONE.append(INDEX[name])
    return len(ONE) - 1


def op(o, k, p=0, l=0, s=0, u=0):
    oi[o] = [k, p, l, s, u]


for g, name in enumerate(("add", "or", "adc", "sbb", "and", "sub", "xor", "cmp")):
    base = g * 8
    u = C if name in ("adc", "sbb") else 0
    for w, sfx in ((0, "b"), (1, "w")):
        op(base + w, K_GEN, SET_INDEX[f"{name}_rm_r_{sfx}"], L_MODRM, ALLF, u)
        op(base + 2 + w, K_GEN, SET_INDEX[f"{name}_r_rm_{sfx}"], L_MODRM, ALLF, u)
        op(base + 4 + w, K_GEN, SET_INDEX[f"{name}_rm_i_{sfx}"], (L_I16 if w else L_I8) | L_ACC, ALLF, u)   # AL/AX, imm
for o, sr in ((0x26, bES), (0x2E, bCS), (0x36, bSS), (0x3E, bDS)):
    op(o, K_SEG, sr)
for o, nm in ((0x06, "push_es"), (0x0E, "push_cs"), (0x16, "push_ss"), (0x1E, "push_ds"), (0x07, "pop_es"),
              (0x17, "pop_ss"), (0x1F, "pop_ds")):
    op(o, K_ONE, one(nm))
XCHG_AX = one("xchg_ax")
for r in range(8):
    op(0x40 + r, K_GEN, SET_INDEX["inc_rm_w"], L_REGOP, NOC)
    op(0x48 + r, K_GEN, SET_INDEX["dec_rm_w"], L_REGOP, NOC)
    op(0x50 + r, K_GEN, SET_INDEX["push_r"], L_REGOP)
    op(0x58 + r, K_GEN, SET_INDEX["pop_r"], L_REGOP)
    op(0xB0 + r, K_GEN, SET_INDEX["mov_rm_i_b"], L_I8 | L_REGOP)
    op(0xB8 + r, K_GEN, SET_INDEX["mov_rm_i_w"], L_I16 | L_REGOP)
    if r:
        op(0x90 + r, K_ONE, XCHG_AX, L_REGOP)
op(0x54, K_EXIT, STACK)                                     # PUSH SP pushes the new value
op(0x5C, K_STEP)
op(0x90, K_ONE, 0)                                          # NOP
for o in range(0x60, 0x70):                                 # (an 8088 runs these as 70-7F)
    op(o, K_EXIT, PURE)
for cc in range(16):
    if cc in (10, 11):
        op(0x70 + cc, K_EXIT, PURE)                         # parity: the interpreter knows how
    else:
        op(0x70 + cc, K_JCC, cc, L_I8, 0, JCC_USES[cc])
op(0x80, K_GRP, 0, L_MODRM | L_I8)
op(0x81, K_GRP, 1, L_MODRM | L_I16)
op(0x82, K_GRP, 0, L_MODRM | L_I8)
op(0x83, K_GRP, 1, L_MODRM | L_I8 | L_SX)
op(0x84, K_GEN, SET_INDEX["test_rm_r_b"], L_MODRM, ALLF)
op(0x85, K_GEN, SET_INDEX["test_rm_r_w"], L_MODRM, ALLF)
op(0x86, K_GEN, SET_INDEX["xchg_rm_r_b"], L_MODRM)
op(0x87, K_GEN, SET_INDEX["xchg_rm_r_w"], L_MODRM)
op(0x88, K_GEN, SET_INDEX["mov_rm_r_b"], L_MODRM)
op(0x89, K_GEN, SET_INDEX["mov_rm_r_w"], L_MODRM)
op(0x8A, K_GEN, SET_INDEX["mov_r_rm_b"], L_MODRM)
op(0x8B, K_GEN, SET_INDEX["mov_r_rm_w"], L_MODRM)
op(0x8C, K_GEN, SET_INDEX["mov_rm_sr"], L_MODRM)
op(0x8D, K_LEA, SET_INDEX["lea"], L_MODRM)
op(0x8E, K_GEN, SET_INDEX["mov_sr_rm"], L_MODRM)
op(0x8F, K_GEN, SET_INDEX["pop_rm"], L_MODRM)
op(0x98, K_ONE, one("cbw"))
op(0x99, K_ONE, one("cwd"))
op(0x9A, K_EXIT, STACK)                                     # CALL far
op(0x9B, K_STEP)
op(0x9C, K_EXIT, STACK)                                     # PUSHF
op(0x9D, K_EXIT, PURE)                                      # POPF (an interrupt it lets in: jit_hook sees it owed)
op(0x9E, K_STEP)
op(0x9F, K_STEP, u=ALLF)
op(0xA0, K_GEN, SET_INDEX["mov_r_rm_b"], L_MOFFS)
op(0xA1, K_GEN, SET_INDEX["mov_r_rm_w"], L_MOFFS)
op(0xA2, K_GEN, SET_INDEX["mov_rm_r_b"], L_MOFFS)
op(0xA3, K_GEN, SET_INDEX["mov_rm_r_w"], L_MOFFS)
for o, p in ((0xA4, 0), (0xA5, 1), (0xAA, 2), (0xAB, 3), (0xAC, 4), (0xAD, 5)):
    op(o, K_STR, p)
for o in (0xA6, 0xA7, 0xAE, 0xAF):
    op(o, K_STEP)
op(0xA8, K_GEN, SET_INDEX["test_rm_i_b"], L_I8 | L_ACC, ALLF)
op(0xA9, K_GEN, SET_INDEX["test_rm_i_w"], L_I16 | L_ACC, ALLF)
for o in (0xC0, 0xC1, 0xC8, 0xC9, 0xCA, 0xCF, 0xEA):          # returns the 8088 has twice, RETF n, IRET, JMP far
    op(o, K_EXIT, PURE)
for o in (0xCC, 0xCD, 0xCE):                                # INT: three words pushed
    op(o, K_EXIT, STACK)
op(0xC2, K_RET, one("retn"), L_I16)
op(0xC3, K_RET, one("ret"))
op(0xCB, K_RET, one("retf"))
op(0xC4, K_GEN, SET_INDEX["les"], L_MODRM)
op(0xC5, K_GEN, SET_INDEX["lds"], L_MODRM)
op(0xC6, K_GEN, SET_INDEX["mov_rm_i_b"], L_MODRM | L_I8)
op(0xC7, K_GEN, SET_INDEX["mov_rm_i_w"], L_MODRM | L_I16)
op(0xD0, K_GRP, 6, L_MODRM)
op(0xD1, K_GRP, 7, L_MODRM)
op(0xD2, K_GRP, 8, L_MODRM)
op(0xD3, K_GRP, 9, L_MODRM)
op(0xD4, K_STEP, 0, L_I8)
op(0xD5, K_STEP, 0, L_I8)
op(0xD7, K_STEP)
for o in range(0xD8, 0xE0):                                 # ESC: the 8087's, or nothing. The interpreter does it
    op(o, K_STEP, 0, L_MODRM)                               # inside the piece: a store of the 8087's onto a page of
                                                            # code puts the epoch on (src/fpu: fp_put), and an
                                                            # interrupt it asks for changes CS:IP, either of which
                                                            # sends jit_hook to the dispatcher
op(0xE0, K_EXIT, PURE)
op(0xE1, K_EXIT, PURE)
op(0xE2, K_LOOP, 0, L_I8)
op(0xE3, K_JCXZ, 0, L_I8)
for o in (0xE4, 0xE5, 0xE6, 0xE7, 0xEC, 0xED, 0xEE, 0xEF):  # (an OUT that moves memory puts the epoch on: jit_hook sees)
    op(o, K_STEP, 0, L_I8 if o < 0xE8 else 0)
op(0xE8, K_CALL, 0, L_I16)
op(0xEB, K_JMP8, 0, L_I8)
op(0xE9, K_JMP16, 0, L_I16)
op(0xF2, K_EXIT, ANY)                                       # REP and what it repeats
op(0xF3, K_EXIT, ANY)
op(0xF5, K_ONE, one("cmc"), 0, C, C)
op(0xF6, K_GRP, 2, L_MODRM | L_F6)
op(0xF7, K_GRP, 3, L_MODRM | L_F6)
op(0xF8, K_ONE, one("clc"), 0, C)
op(0xF9, K_ONE, one("stc"), 0, C)
op(0xFA, K_EXIT, PURE)
op(0xFB, K_EXIT, PURE)                                      # STI (with an interrupt owed the interpreter keeps the run)
op(0xFC, K_ONE, one("cld"))
op(0xFD, K_ONE, one("std"))
op(0xFE, K_GRP, 4, L_MODRM)
op(0xFF, K_GRP, 5, L_MODRM)
for o in (0x27, 0x2F, 0x37, 0x3F):
    op(o, K_STEP, 0, 0, 0, ALLF)

# the groups: (kind, param, sets, uses) for /0 to /7
GR = []
for sfx in ("b", "w"):                                      # 80/82 and 81/83
    GR.append([(K_GEN, SET_INDEX[f"{n}_rm_i_{sfx}"], ALLF, C if n in ("adc", "sbb") else 0)
               for n in ("add", "or", "adc", "sbb", "and", "sub", "xor", "cmp")])
for sfx in ("b", "w"):                                      # F6 and F7
    GR.append([(K_GEN, SET_INDEX[f"test_rm_i_{sfx}"], ALLF, 0), (K_EXIT, PLAIN, 0, 0),
               (K_GEN, SET_INDEX[f"not_rm_{sfx}"], 0, 0), (K_GEN, SET_INDEX[f"neg_rm_{sfx}"], ALLF, 0)] +
              [(K_STEP, 0, 0, 0)] * 4)
GR.append([(K_GEN, SET_INDEX["inc_rm_b"], NOC, 0), (K_GEN, SET_INDEX["dec_rm_b"], NOC, 0)] + [(K_EXIT, PLAIN, 0, 0)] * 5 +
          [(K_EXIT, ANY, 0, 0)])                            # FE (/7: the hypercall)
GR.append([(K_GEN, SET_INDEX["inc_rm_w"], NOC, 0), (K_GEN, SET_INDEX["dec_rm_w"], NOC, 0),
           (K_IND, SET_INDEX["call_ind"], 0, 0), (K_EXIT, STACK, 0, 0), (K_IND, SET_INDEX["jmp_ind"], 0, 0),
           (K_EXIT, PURE, 0, 0), (K_GEN, SET_INDEX["push_rm"], 0, 0), (K_EXIT, PLAIN, 0, 0)])                        # FF
for by, sfx in (("1", "b"), ("1", "w"), ("c", "b"), ("c", "w")):                                                     # D0-D3
    row = []
    for kind in SHIFTS:
        if kind is None:
            row.append((K_EXIT, PLAIN, 0, 0))
            continue
        rot = kind in ("rol", "ror", "rcl", "rcr")
        sets = (C | O) if rot else ALLF
        uses = (C if kind in ("rcl", "rcr") else 0) | (sets if by == "c" else 0)   # (a count of nothing keeps them)
        row.append((K_GEN, SET_INDEX[f"{kind}{by}_{sfx}"], sets, uses))
    GR.append(row)


def dfb(vals, per=16):
    out = []
    for i in range(0, len(vals), per):
        out.append(" dfb " + ",".join(v if isinstance(v, str) else f"${v:02X}" for v in vals[i:i + per]))
    return out


def main():
    L = ["* jtab.s - generated by tools/gen_jit.py; do not edit.", ""]
    L += [f"K_{n} = {v}" for v, n in enumerate(KNAMES)]
    L += [f"L_{n} = {v}" for n, v in (("MODRM", L_MODRM), ("I8", L_I8), ("I16", L_I16), ("SX", L_SX), ("REGOP", L_REGOP),
                                      ("MOFFS", L_MOFFS), ("ACC", L_ACC), ("F6", L_F6))]
    L += [f"TS_{n} = {v}" for n, v in (("W8", W8), ("MEMW", MEMW), ("WORDMEM", WORDMEM), ("SREG", SREG), ("FAR", FAR),
                                       ("CIN", CIN), ("CINV", CINV))]
    L += [f"TP_{n.upper()} = {INDEX[n]}" for n in ("w8", "w16", "linkf", "linkb", "jmp", "guard", "step", "x0", "x5", "x6",
                                                    "x7", "call", "cin", "cinv", "cflip", "ea_y", "fetch_b", "fetch_w",
                                                    "fetch_bd", "fetch_wd",
                                                    "loop", "jcxz", "lods_b", "lods_w", "stos_b",
                                                    "stos_w", "movs_ld_b", "movs_ld_w", "movs_st_b", "movs_st_w",
                                                    "adv_si1", "adv_si2", "adv_di1", "adv_di2", "spsync")]
    L += [f"JF_ALWAYS = ${ALWAYS:04X}", f"JF_NEVER = ${NEVER:04X}", f"TP_COUNT = {len(TEMPLATES)}",
          f"TP_STEP_LEN = {len(TEMPLATES[INDEX['step'] - 1].bytes)}",
          f"SET_MOV_SR = {SET_INDEX['mov_sr_rm']}", ""]
    L += ["sl_size" + dfb([0] + [sz for _, (sid, sz) in sorted(SLOTS.items(), key=lambda kv: kv[1][0])])[0]]
    L += ["kt_tab " + dfb(KT)[0]]
    L.append("ea_rt                      ; the pointer routines: base * 6 + write * 3 + size (byte, word, four bytes)")
    names = ea_routines()
    for i in range(0, len(names), 6):
        L.append(" da " + ",".join(names[i:i + 6]))
    for name, col in (("oi_k", 0), ("oi_p", 1), ("oi_l", 2), ("oi_s", 3), ("oi_u", 4)):
        L.append(name)
        L += dfb([row[col] for row in oi])
    L.append("gr_tab                     ; kind, parameter, sets, uses: eight a group")
    for g in GR:
        L += dfb([v for e in g for v in e], 16)
    L.append("ts_tab                     ; flags, class; then words: register form, with flags, memory form, with flags")
    for s in SETS:
        L.append(f" dfb ${s[0]:02X},${s[5]:02X}")
        L.append(" dw " + ",".join(str(v) for v in s[1:5]))
    L.append("one_tab                    ; K_ONE's templates (0: nothing)")
    L.append(" dw " + ",".join(str(v) for v in ONE))
    L.append("eo_tab                     ; the offset's template: r/m, then r/m with a displacement")
    L.append(" dw " + ",".join(str(v) for v in EO))
    L.append("ea_seg                     ; and the segment base it is from, when no prefix says")
    L += dfb(EA_SEG)
    L.append("jf_tab                     ; a jump on native flags: class 1-6, sixteen conditions each")
    for row in JF:
        L.append(" dw " + ",".join(str(v) for v in row))
    L.append("jg_tab                     ; and on the lazy ones")
    L.append(" dw " + ",".join(str(v) for v in JG))
    L.append("tp_tab")
    for i in range(0, len(TEMPLATES), 8):
        L.append(" da " + ",".join(f"tp_{t.name}" for t in TEMPLATES[i:i + 8]))
    for t in TEMPLATES:
        L.append(f"tp_{t.name}")
        L += dfb([len(t.bytes), len(t.fix), 1 if t.width == 8 else 0])
        if t.bytes:
            L += dfb(t.bytes)
        if t.fix:
            L += dfb([v for f in t.fix for v in f])
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write("\n".join(L) + "\n")
    size = sum(3 + len(t.bytes) + 2 * len(t.fix) for t in TEMPLATES)
    return f"{OUT}: {len(TEMPLATES)} templates ({size} bytes), {len(SETS)} sets"


if __name__ == "__main__":
    print(main())
