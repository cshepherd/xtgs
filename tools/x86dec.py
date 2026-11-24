"""A small 8086 instruction decoder for the profiler: length, kind and what
the instruction needs of a translator. decode(mem, lin) -> Ins. Not a
disassembler (ndisasm prints the text)."""
from collections import namedtuple

Ins = namedtuple("Ins", "length op kind target cond mem memform seg rep sets uses wide prefixes modrm")
# kind: 'seq' ordinary, 'jcc', 'jmp', 'call', 'ret', 'loop' (LOOP/JCXZ), 'jmpf', 'callf', 'retf', 'iret',
#       'int', 'jind' (FF /4 /5), 'cind' (FF /2 /3), 'hlt', 'str' (string op), 'io', 'sreg' (segment load),
#       'stack' (push/pop), 'flagio' (pushf/popf/lahf/sahf/cli/sti/cld/std...), 'muldiv', 'shift', 'bad'
# sets/uses: sets of the arithmetic flags 'oszapc' the instruction writes / reads

ALL = frozenset("oszapc")
NOC = frozenset("oszap")
JCC_USES = [frozenset("o"), frozenset("o"), frozenset("c"), frozenset("c"), frozenset("z"), frozenset("z"),
            frozenset("cz"), frozenset("cz"), frozenset("s"), frozenset("s"), frozenset("p"), frozenset("p"),
            frozenset("so"), frozenset("so"), frozenset("soz"), frozenset("soz")]
MEMFORM = ["bx+si", "bx+di", "bp+si", "bp+di", "si", "di", "bp", "bx"]
E = frozenset()


def s8(b):
    return b - 256 if b & 0x80 else b


def decode(mem, lin, cs=None, ip=None):
    """mem: the guest's bytes; lin: linear address of the first byte (prefixes
    included). cs/ip give a near target as an IP when known."""
    p = lin
    seg = None
    rep = None
    prefixes = 0
    while True:
        b = mem[p & 0xFFFFF]
        if b in (0x26, 0x2E, 0x36, 0x3E):
            seg = "ecsd"[(b >> 3) & 3]
        elif b in (0xF2, 0xF3):
            rep = b
        elif b == 0xF0:
            pass
        else:
            break
        p += 1
        prefixes += 1
        if prefixes > 6:
            return Ins(prefixes, b, "bad", None, None, False, None, seg, rep, E, E, False, prefixes, None)
    op = b
    p += 1
    st = dict(mem=False, memform=None, modrm=None)

    def rm():
        nonlocal p
        m = mem[p & 0xFFFFF]
        p += 1
        mod, r = m >> 6, m & 7
        st["modrm"] = m
        if mod == 3:
            return m
        st["mem"] = True
        if mod == 0 and r == 6:
            p += 2
            st["memform"] = "disp16"
        else:
            st["memform"] = MEMFORM[r] + ("" if mod == 0 else "+d8" if mod == 1 else "+d16")
            p += mod if mod < 3 else 0
        return m

    def fin(kind="seq", target=None, cond=None, sets=E, uses=E, wide=False):
        return Ins(p - lin, op, kind, target, cond, st["mem"], st["memform"], seg, rep, sets, uses, wide,
                   prefixes, st["modrm"])

    def rel8():
        nonlocal p
        d = s8(mem[p & 0xFFFFF])
        p += 1
        return (p - lin + d)          # displacement from the instruction's first byte

    def rel16():
        nonlocal p
        d = mem[p & 0xFFFFF] | mem[(p + 1) & 0xFFFFF] << 8
        p += 2
        return (p - lin + (d - 65536 if d & 0x8000 else d))

    w = bool(op & 1)
    if op < 0x40:
        lo = op & 7
        if lo < 4:                                   # ALU r/m,r  r,r/m
            rm()
            g = op >> 3
            sets = ALL
            uses = frozenset("c") if g in (2, 3) else E
            return fin(sets=sets, uses=uses, wide=w)
        if lo == 4:
            p += 1
            return fin(sets=ALL, uses=frozenset("c") if (op >> 3) in (2, 3) else E)
        if lo == 5:
            p += 2
            return fin(sets=ALL, uses=frozenset("c") if (op >> 3) in (2, 3) else E, wide=True)
        if op in (0x27, 0x2F, 0x37, 0x3F):           # DAA DAS AAA AAS
            return fin("flagio", sets=ALL, uses=frozenset("ac"))
        if lo == 6:
            return fin("stack")                      # push sreg
        return fin("sreg")                           # pop sreg (0F: pop cs)
    if op < 0x48:
        return fin(sets=NOC, wide=True)              # inc r16
    if op < 0x50:
        return fin(sets=NOC, wide=True)              # dec r16
    if op < 0x60:
        return fin("stack", wide=True)
    if op < 0x70:
        if op in (0x60, 0x61):
            return fin("stack")
        # 8086: 60-6F alias 70-7F
        t = rel8()
        return fin("jcc", t, op & 15, uses=JCC_USES[op & 15])
    if op < 0x80:
        t = rel8()
        return fin("jcc", t, op & 15, uses=JCC_USES[op & 15])
    if op < 0x84:                                    # group 1
        m = rm()
        p += 2 if op == 0x81 else 1
        g = (m >> 3) & 7
        return fin(sets=ALL, uses=frozenset("c") if g in (2, 3) else E, wide=w)
    if op < 0x86:
        rm()
        return fin(sets=ALL, wide=w)                 # test
    if op < 0x8C:
        rm()
        return fin(wide=w)                           # xchg, mov
    if op == 0x8C:
        rm()
        return fin(wide=True)                        # mov r/m,sreg
    if op == 0x8D:
        rm()
        return fin(wide=True)                        # lea
    if op == 0x8E:
        rm()
        return fin("sreg", wide=True)
    if op == 0x8F:
        rm()
        return fin("stack", wide=True)
    if op < 0x98:
        return fin(wide=True)                        # xchg ax,r / nop
    if op in (0x98, 0x99):
        return fin(wide=True)
    if op == 0x9A:
        p += 4
        return fin("callf")
    if op == 0x9B:
        return fin()
    if op in (0x9C, 0x9D):
        return fin("flagio", sets=ALL if op == 0x9D else E, uses=ALL if op == 0x9C else E)
    if op == 0x9E:
        return fin("flagio", sets=frozenset("szapc"))
    if op == 0x9F:
        return fin("flagio", uses=frozenset("szapc"))
    if op < 0xA4:
        p += 2
        st["mem"], st["memform"] = True, "disp16"
        return fin(wide=w)
    if op < 0xB0:
        if op in (0xA8, 0xA9):
            p += 2 if w else 1
            return fin(sets=ALL, wide=w)
        cmpk = op in (0xA6, 0xA7, 0xAE, 0xAF)
        return fin("str", sets=ALL if cmpk else E, wide=w)
    if op < 0xB8:
        p += 1
        return fin()
    if op < 0xC0:
        p += 2
        return fin(wide=True)
    if op in (0xC0, 0xC2):
        p += 2
        return fin("ret")
    if op in (0xC1, 0xC3):
        return fin("ret")
    if op in (0xC4, 0xC5):
        rm()
        return fin("sreg", wide=True)
    if op in (0xC6, 0xC7):
        rm()
        p += 2 if w else 1
        return fin(wide=w)
    if op in (0xC8, 0xCA):
        p += 2
        return fin("retf")
    if op in (0xC9, 0xCB):
        return fin("retf")
    if op == 0xCC:
        return fin("int")
    if op == 0xCD:
        p += 1
        return fin("int")
    if op == 0xCE:
        return fin("int", uses=frozenset("o"))
    if op == 0xCF:
        return fin("iret", sets=ALL)
    if op < 0xD4:
        m = rm()
        g = (m >> 3) & 7
        return fin("shift", sets=ALL if g >= 4 else frozenset("oc"), uses=frozenset("c") if g in (2, 3) else E, wide=w)
    if op in (0xD4, 0xD5):
        p += 1
        return fin("muldiv", sets=ALL)
    if op == 0xD6:
        return fin(uses=frozenset("c"))
    if op == 0xD7:
        st["mem"], st["memform"] = True, "bx+al"
        return fin()
    if op < 0xE0:
        rm()
        return fin("bad")                            # ESC
    if op < 0xE4:
        t = rel8()
        return fin("loop", t, uses=frozenset("z") if op < 0xE2 else E)
    if op < 0xE8:
        p += 1
        return fin("io")
    if op == 0xE8:
        t = rel16()
        return fin("call", t)
    if op == 0xE9:
        t = rel16()
        return fin("jmp", t)
    if op == 0xEA:
        p += 4
        return fin("jmpf")
    if op == 0xEB:
        t = rel8()
        return fin("jmp", t)
    if op < 0xF0:
        return fin("io")
    if op == 0xF1:
        return fin()
    if op == 0xF4:
        return fin("hlt")
    if op == 0xF5:
        return fin("flagio", sets=frozenset("c"), uses=frozenset("c"))
    if op in (0xF6, 0xF7):
        m = rm()
        g = (m >> 3) & 7
        if g < 2:
            p += 2 if w else 1
            return fin(sets=ALL, wide=w)             # test
        if g == 2:
            return fin(wide=w)                       # not
        if g == 3:
            return fin(sets=ALL, wide=w)             # neg
        return fin("muldiv", sets=ALL, wide=w)
    if op in (0xF8, 0xF9):
        return fin("flagio", sets=frozenset("c"))
    if op < 0xFE:
        return fin("flagio")                         # cli sti cld std
    m = rm()
    g = (m >> 3) & 7
    if g < 2:
        return fin(sets=NOC, wide=w)                 # inc/dec r/m
    if op == 0xFF:
        if g == 2:
            return fin("cind")
        if g == 3:
            return fin("callf")
        if g == 4:
            return fin("jind")
        if g == 5:
            return fin("jmpf")
        if g == 6:
            return fin("stack", wide=True)
    return fin("bad")
