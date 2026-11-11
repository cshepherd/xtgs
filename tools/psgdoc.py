#!/usr/bin/env python3
"""psgdoc.py - what the DOC was told to play, against what a Tandy 1000's
sound chip (the SN76496 at ports C0h-C7h), the speaker and the timer
would (docs/tandy.md, docs/sound.md).

src/svc/sound.s keeps every write to a DOC register in a ring (DOC_LOG,
doc_w), and before the writes a byte to the chip led to, the byte itself
(DOC_MARK). judge() follows the bytes with a model of the chip written
from its data sheet's rules, follows the writes with the DOC's registers
and, after each byte, asks of each voice whether its two oscillators play
what the chip would:

  a tone      3,579,545 / 32n Hz for a period n (0 is 1024), the square
              wave, at 2 dB of attenuation a step; nothing at 15, and
              nothing for a period under 6 (above 18.6 kHz)
  the noise   the shift register's sequence (DOC RAM $8000) at 3,579,545
              / 512, / 1024 or / 2048 shifts a second, or one a cycle of
              tone 2; "periodic", one bit in fifteen: the pulse (page 1) at
              a fifteenth of that rate. A write to its register starts it
              again
  the pair    one oscillator on each DOC channel, the same frequency,
              table and volume, started by two writes next to each other;
              no frequency written to one that runs; a voice the byte did
              not change has no register changed, and an attenuation
              alone changes volumes and nothing else

An oscillator's frequency is SR * FC / 2^(17 + r) for a table of any
length (r the resolution), a table's byte lasts 2^(9 + r - s) / FC visits
(s the size's code), and SR is 7,159,090 / 8 / (oscillators + 2). The
speaker (oscillators 0 and 1) and the timer (the last one enabled, its
interrupt on) are asked for the 8253's 1,193,182 / count Hz in the same
way, at the bytes a test's manifest names.

    spec = {"writes": 150,                 # bytes the chip took (PSG_WRITES)
            "speaker": [[0, 0], [140, 1193]],  # from that byte on: channel 2's
            "timer": [[0, 0]]}             # count while it sounds (0: silent);
                                           # channel 0's (0: 65536)
    problems, notes = judge(dumps, spec)   # dumps: name -> bytes (DUMPS)

Without a spec only the oscillator count and the timer's rate at the end
are judged, which is true of any program that leaves channel 0 alone.
"""
import struct

XTAL = 7159090.0                 # the IIGS's master clock: twice the PC's colour clock
PSG_CLOCK = XTAL / 2             # the chip's on a Tandy 1000
PIT_CLOCK = XTAL / 6
R_FCL, R_FCH, R_VOL, R_PTR, R_CTL, R_SIZ, R_ENA = 0x00, 0x20, 0x40, 0x80, 0xA0, 0xC0, 0xE1
SQUARE_PP, PULSE_PP = 254, 136   # the tables' peak to peak: $FF/$01 and $FF/$77
NOISE_PAGE, PULSE_PAGE = 0x80, 0x01
TOL_TONE, TOL_NOISE = 2e-4, 1.6e-2
PSG_O = 2                        # the chip's first oscillator
MIN_PERIOD = 6                   # a tone's period under this is not played (PSG_MINDIV)


def dumps(sym):
    """The dump list for mamerun (name, address, length) from svc.lst's symbols."""
    return [("doclog", sym["DOC_LOG"], (sym["DOC_LOGM"] + 1) * 2), ("docn", sym["DOC_LOGN"], 2),
            ("docreg", sym["DOC_REG"], 256), ("psgreg", sym["PSG_REG"], 16),
            ("psgst", sym["PSG_LATCH"], 8), ("tdyon", sym["TDY_ON"], 2)]


def noise_sum():
    """The checksum of the 32,768 steps of x^15 + x + 1 from one bit set, a
    byte ($FF or $01) a step, as DOC_SUM has it."""
    o = [0] * 14 + [1]
    while len(o) < 32768:
        o.append(o[-15] ^ o[-14])
    assert o[32767:] == o[:1] and sum(o[:32767]) == 16384     # the full period
    s = 0
    for bit in o:
        s = ((s << 1 & 0xFFFF) + (s >> 15) + (0xFF if bit else 0x01)) & 0xFFFF
    return s


class Chip:
    """The SN76496's eight registers: 0, 2, 4 a tone's period, 6 the noise,
    the odd ones attenuations."""

    def __init__(self):
        self.reg = [0, 15, 0, 15, 0, 15, 0, 15]
        self.last = 0

    def write(self, b):
        if b & 0x80:                                 # 1 rrr dddd: the register, its low four bits
            self.last = b >> 4 & 7
            self.reg[self.last] = self.reg[self.last] & 0x3F0 | b & 15
        elif self.last in (0, 2, 4):                 # 0 x dddddd: a period's high six
            self.reg[self.last] = self.reg[self.last] & 15 | (b & 0x3F) << 4
        else:                                        # or the low four again
            self.reg[self.last] = self.reg[self.last] & 0x3F0 | b & 15
        return self.last

    def period(self, v):
        return self.reg[v * 2] & 0x3FF or 1024

    def voice(self, v):
        """What makes voice v's sound: a change in it is a change to hear."""
        if v < 3:
            return (self.period(v), self.reg[v * 2 + 1])
        return (self.reg[6] & 7, self.reg[7], self.period(2) if self.reg[6] & 3 == 3 else None)


class Doc:
    def __init__(self):
        self.r = bytearray(256)
        for o in range(32):
            self.r[R_CTL + o] = 1

    def nosc(self):
        return (self.r[R_ENA] >> 1) + 1

    def rate(self):
        return XTAL / 8 / (self.nosc() + 2)

    def fc(self, o):
        return self.r[R_FCL + o] | self.r[R_FCH + o] << 8

    def runs(self, o):
        return not self.r[R_CTL + o] & 1

    def freq(self, o):                               # a whole table a cycle
        return self.rate() * self.fc(o) / 2 ** (17 + (self.r[R_SIZ + o] & 7))

    def step(self, o):                               # table bytes a second
        siz = self.r[R_SIZ + o]
        return self.rate() * self.fc(o) / 2 ** (9 + (siz & 7) - (siz >> 3 & 7))

    def table(self, o):                              # (page, bytes)
        return self.r[R_PTR + o], 256 << (self.r[R_SIZ + o] >> 3 & 7)

    def same(self, a, b):
        return all(self.r[x + a] == self.r[x + b] for x in (R_FCL, R_FCH, R_PTR, R_SIZ))


def near(got, want, tol):
    return abs(got - want) <= want * tol


def pair(doc, a, what, f, vol, problems, page=0, size=256, step=None, tol=TOL_TONE):
    """Oscillators a and a+1 playing f Hz (or step table bytes a second) at vol."""
    b = a + 1
    ca, cb = doc.r[R_CTL + a], doc.r[R_CTL + b]
    if ca & 1 or cb & 1:
        problems.append(f"{what}: silent (controls {ca:02X} {cb:02X})")
        return
    if ca & 0x0E or cb & 0x0E:
        problems.append(f"{what}: not free-running without an interrupt (controls {ca:02X} {cb:02X})")
    if (ca >> 4 & 1) == (cb >> 4 & 1):
        problems.append(f"{what}: both oscillators on one channel")
    if not doc.same(a, b):
        problems.append(f"{what}: the two oscillators differ")
    if doc.r[R_VOL + a] != doc.r[R_VOL + b]:
        problems.append(f"{what}: volumes {doc.r[R_VOL + a]} and {doc.r[R_VOL + b]}")
    if doc.table(a)[0] != page or (size is not None and doc.table(a)[1] != size):
        problems.append(f"{what}: table {doc.table(a)}, not page {page:#x}" + (f" of {size}" if size else ""))
    if doc.r[R_SIZ + a] & 0x40:
        problems.append(f"{what}: the other bank of DOC RAM")
    got, want = (doc.step(a), step) if step else (doc.freq(a), f)
    if not near(got, want, tol):
        problems.append(f"{what}: {got:.3f} Hz, not {want:.3f}")
    if vol is not None and abs(doc.r[R_VOL + a] - vol) > 0.5001:
        problems.append(f"{what}: volume {doc.r[R_VOL + a]}, not {vol:.1f}")


def halted(doc, a, what, problems):
    if doc.runs(a) or doc.runs(a + 1):
        problems.append(f"{what}: playing when it should be silent "
                        f"(controls {doc.r[R_CTL + a]:02X} {doc.r[R_CTL + a + 1]:02X})")


def chip_check(doc, chip, sym, where, problems):
    full, mindiv = sym["PSG_VOL"], MIN_PERIOD
    for v in range(3):
        n, att = chip.period(v), chip.reg[v * 2 + 1]
        what = f"{where}: tone {v} (period {n}, attenuation {att})"
        if att == 15 or n < mindiv:
            halted(doc, PSG_O + v * 2, what, problems)
        else:
            pair(doc, PSG_O + v * 2, what, PSG_CLOCK / (32 * n), full * 10 ** (-att / 10), problems)
    nf, att = chip.reg[6] & 7, chip.reg[7]
    shift = PSG_CLOCK / (32 * chip.period(2)) if nf & 3 == 3 else PSG_CLOCK / (512 << (nf & 3))
    what = f"{where}: noise (register {nf}, {shift:.1f} shifts a second, attenuation {att})"
    a = PSG_O + 6
    if att == 15:
        halted(doc, a, what, problems)
    elif nf & 4:                                     # white: the sequence, a bit a shift
        pair(doc, a, what, None, full * 10 ** (-att / 10), problems, page=NOISE_PAGE, size=None,
             step=shift, tol=0 if nf & 3 != 3 else TOL_NOISE)
        size = doc.table(a)[1]
        if size != 32768 and size / shift < 2:
            problems.append(f"{what}: {size} bits of the sequence, {size / shift:.2f} s of it")
    else:                                            # periodic: a bit in fifteen
        pair(doc, a, what, shift / 15, full * SQUARE_PP / PULSE_PP * 10 ** (-att / 10), problems,
             page=PULSE_PAGE)


def speaker_check(doc, count, sym, where, problems):
    what = f"{where}: the speaker (count {count})"
    if not count:
        halted(doc, 0, what, problems)
    else:
        pair(doc, 0, what, PIT_CLOCK / count, sym["SPK_VOL"], problems)


def timer_check(doc, count, where, problems):
    o = doc.nosc() - 1
    c = doc.r[R_CTL + o]
    what = f"{where}: the timer (oscillator {o}, count {count or 65536})"
    if c & 0x0F != 0x08:
        problems.append(f"{what}: control {c:02X}, not free-running with its interrupt")
    if doc.r[R_VOL + o]:
        problems.append(f"{what}: volume {doc.r[R_VOL + o]}")
    # (at the finest resolution a frequency is right to half a step of FC and no better)
    tol = max(TOL_TONE, 0.6 / doc.fc(o)) if doc.r[R_SIZ + o] & 7 == 7 and doc.fc(o) else TOL_TONE
    if not near(doc.freq(o), PIT_CLOCK / (count or 65536), tol):
        problems.append(f"{what}: {doc.freq(o):.4f} Hz, not {PIT_CLOCK / (count or 65536):.4f}")


def at(schedule, k):
    """The count in force at byte k of [[from, count], ...]."""
    v = None
    for frm, count in schedule:
        if frm <= k:
            v = count
    return v


def judge(d, sym, spec=None):
    problems, notes = [], []
    tdy = d["tdyon"][0] != 0
    n = struct.unpack("<H", d["docn"])[0]
    size = sym["DOC_LOGM"] + 1
    latch, writes, nosc, dsum = struct.unpack("<4H", d["psgst"])
    final = d["docreg"]
    want_n = sym["N_OSCT"] if tdy else sym["N_OSC"]
    if nosc != want_n or (final[R_ENA] >> 1) + 1 != want_n:
        problems.append(f"{nosc} oscillators (the DOC's register {final[R_ENA]:02X}), not {want_n}")
    if tdy and dsum != noise_sum():
        problems.append(f"the noise table's checksum is {dsum:04X}, not {noise_sum():04X}")
    if spec is None:                                 # the timer as the program left it
        doc = Doc()
        doc.r[:] = final
        if n:                                        # (the close halts every oscillator)
            doc.r[R_CTL + doc.nosc() - 1] = 0x08 | final[R_CTL + doc.nosc() - 1] & 0xF0
            timer_check(doc, 0, "at the end", problems)
        return problems, notes
    if n > size:
        problems.append(f"{n} DOC writes: the log of {size} went round")
        return problems, notes
    log = [(d["doclog"][i * 2], d["doclog"][i * 2 + 1]) for i in range(n)]
    close = log[-32:]
    if [r for r, _v in close] != [R_CTL + o for o in range(32)] or not all(v & 1 for _r, v in close):
        problems.append("the log does not end with the close's 32 halts")
    else:
        log = log[:-32]
    marks = sum(1 for r, _v in log if r == sym["DOC_MARK"])
    if writes != spec.get("writes", 0) or marks != writes:
        problems.append(f"the chip took {writes} bytes ({marks} in the log), expected {spec.get('writes', 0)}")
    doc, chip = Doc(), Chip()
    keyed = {}                                       # oscillator -> the log index of its last start
    k = -1                                           # the byte the writes follow
    touched, before, reg6 = set(), None, False
    first = None

    def after(k):                                    # byte k's writes are all in
        where = f"byte {k}"
        np = len(problems)
        chip_check(doc, chip, sym, where, problems)
        for v in range(4):
            a = PSG_O + v * 2
            mine = {r for r, o in touched if o in (a, a + 1)}
            was, now = before[v], chip.voice(v)
            if was == now and not (v == 3 and reg6):
                if mine:
                    problems.append(f"{where}: voice {v} written to (registers "
                                    f"{' '.join(f'{r:02X}' for r in sorted(mine))}) by a byte that was not its")
            elif was[0] == now[0] and was[2:] == now[2:] and not (v == 3 and reg6) \
                    and 15 not in (was[1], now[1]) and mine - {R_VOL}:
                problems.append(f"{where}: voice {v}'s attenuation alone wrote registers "
                                f"{' '.join(f'{r:02X}' for r in sorted(mine))}")
            if v == 3 and reg6 and chip.reg[7] != 15 and (started[a], started[a + 1]) != (1, 1):
                problems.append(f"{where}: the noise register written and the noise not started again")
        return len(problems) > np

    started = [0] * 32
    for i, (r, v) in enumerate(log):
        if r == sym["DOC_MARK"]:
            if k >= 0 and first is None and after(k):
                first = k
            if "speaker" in spec:
                speaker_check(doc, at(spec["speaker"], k + 1), sym, f"at byte {k + 1}", problems)
            if "timer" in spec:
                timer_check(doc, at(spec["timer"], k + 1), f"at byte {k + 1}", problems)
            k += 1
            before = [chip.voice(x) for x in range(4)]
            reg6 = chip.write(v) == 6
            touched, started = set(), [0] * 32
            continue
        o = r & 0x1F
        if tdy and r < 0xE0 and PSG_O <= o < PSG_O + 8:
            base = r & 0xE0
            if doc.r[r] != v:                        # (the same value again changes nothing)
                touched.add((base, o))
            if k < 0 and base == R_CTL and not v & 1:
                problems.append(f"oscillator {o} started before any byte to the chip")
            if base in (R_FCL, R_FCH, R_PTR, R_SIZ) and doc.runs(o) and doc.r[r] != v:
                problems.append(f"byte {k}: register {r:02X} written while oscillator {o} runs")
            if base == R_CTL and doc.r[r] & 1 and not v & 1:      # a start
                started[o] += 1
                keyed[o] = i
                if (o - PSG_O) & 1 and keyed.get(o - 1) != i - 1:
                    problems.append(f"byte {k}: oscillator {o} started apart from its partner")
                if (o - PSG_O) & 1 and not doc.same(o - 1, o):
                    problems.append(f"byte {k}: oscillators {o - 1} and {o} started with different frequencies")
        doc.r[r] = v
        if tdy and r < 0xE0 and PSG_O <= o < PSG_O + 8 and r & 0xE0 == R_CTL and not (o - PSG_O) & 1 and not v & 1:
            nxt = log[i + 1] if i + 1 < len(log) else (None, 1)
            if nxt[0] != r + 1 or nxt[1] & 1:
                problems.append(f"byte {k}: oscillator {o} started and its partner not next")
    if k >= 0 and first is None and after(k):
        first = k
    if not tdy and any(doc.runs(o) for o in range(PSG_O, 32) if o != doc.nosc() - 1):
        problems.append("an oscillator that is not the speaker's or the timer's runs on a PC with no sound chip")
    if "speaker" in spec:
        speaker_check(doc, at(spec["speaker"], 1 << 30), sym, "at the end", problems)
    if "timer" in spec:
        timer_check(doc, at(spec["timer"], 1 << 30), "at the end", problems)
    if bytes(doc.r) != bytes(final[:256]) and not problems:
        # (the close's halts are the only difference there may be)
        diff = [x for x in range(256) if doc.r[x] != final[x] and not (R_CTL <= x < R_CTL + 32)]
        if diff:
            problems.append(f"DOC_REG and the log disagree at registers {' '.join(f'{x:02X}' for x in diff)}")
    regs = struct.unpack("<8H", d["psgreg"])
    if tdy and (list(regs) != chip.reg or latch != chip.last):
        problems.append(f"the chip's registers are {regs} (latch {latch}), the model's {chip.reg} ({chip.last})")
    notes.append(f"{marks} bytes to the chip, {len(log)} log entries, {doc.nosc()} oscillators; at the end: " +
                 ", ".join(f"{'tone ' + str(v) if v < 3 else 'noise'} "
                           f"{doc.freq(PSG_O + v * 2) if v < 3 or not chip.reg[6] & 4 else doc.step(PSG_O + 6):.1f} Hz "
                           f"vol {doc.r[R_VOL + PSG_O + v * 2]}"
                           for v in range(4) if tdy and doc.runs(PSG_O + v * 2)) +
                 (", " if tdy and any(doc.runs(PSG_O + v * 2) for v in range(4)) else "") +
                 (f"speaker {doc.freq(0):.1f} Hz, " if doc.runs(0) else "") +
                 f"timer {doc.freq(doc.nosc() - 1):.4f} Hz")
    if len(problems) > 12:
        problems[12:] = [f"and {len(problems) - 12} more"]
    return problems, notes
