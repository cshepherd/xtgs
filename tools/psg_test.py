#!/usr/bin/env python3
"""psg_test.py - make test-psg: the Tandy 1000's sound chip by ear.

Runs tests/snd/psgwav.asm under the .COM runner as a Tandy (XTGS.CMD's
VIDEO=TANDY) with MAME recording its sound, and measures the recording:
fourteen sounds, each nine ticks of the BIOS's count long and four apart
(SOUNDS, the program's table), on both of the DOC's channels.

  a tone        its frequency by its zero crossings, its level (the
                fundamental's) against the first sound's
  a chord       each note's line in the spectrum, where it should be and
                as strong as one tone's
  white noise   the bits read back from the recording against the chip's
                shift register (x^15 + x + 1 from one bit set), and the
                rate they come at
  periodic      the pulse's frequency, its height and how much of a cycle
                it is high (a bit in fifteen)
  the speaker   its 1000 Hz alone and under a tone
  the timer     the sounds' spacing: 13 ticks at 18.2 Hz, with eleven
                oscillators enabled

MAME's es5503 plays a 256-byte table 256/255 sharp (docs/sound.md), the
timer's too, so that is what a tone is held to; the noise's bits are not
a table's cycle and come at the chip's rate. The recording (20 MB) is
deleted afterwards unless KEEP=1; work files in build/psg/. tools/psgdoc.py
is the other half: every register the DOC was given, in make test-com.

    python3 -I tools/psg_test.py
"""
import array
import math
import os
import subprocess
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, "mame"))
sys.path.insert(0, HERE)
import mamerun  # noqa: E402
import symbols  # noqa: E402

CLOCK = 3579545.0                # the chip's
PIT = 1193181.67
SHARP = 256 / 255                # MAME's es5503, a 256-byte table
TICK = PIT / 65536
ON, OFF = 9, 4                   # ticks: psgwav.asm


def tone(n):
    return CLOCK / (32 * n)


# (what, ...): the program's table in order
SOUNDS = [
    ("tone", tone(254), 1.0),
    ("tone", tone(170), 1.0),
    ("tone", tone(1023), 1.0),
    ("chord", [tone(254), tone(202), tone(170)], 1.0),
    ("tone", tone(254), 10 ** -0.5),             # 10 dB down
    ("tone", tone(254), 10 ** -1.0),             # 20 dB down
    ("white", CLOCK / 512, 0.0005),
    ("white", CLOCK / 2048, 0.0005),
    ("pulse", CLOCK / 512 / 15),
    ("white", tone(20), 0.016),                  # tone 2 its clock, period 20
    ("pulse", tone(20) / 15),
    ("tone", PIT / 1193, 112 / 136),             # the speaker (SPK_VOL / PSG_VOL)
    ("chord", [PIT / 1193, tone(254)], [112 / 136, 1.0]),
    ("tone", tone(32), 1.0),
]


def sequence(n):
    o = [0] * 14 + [1]
    while len(o) < n:
        o.append(o[-15] ^ o[-14])
    return o


def bursts(ch, fs, gap=0.1):
    out, start, last = [], None, None
    for i, v in enumerate(ch):
        if v:
            if start is None:
                start = i
            last = i
        elif start is not None and i - last > gap * fs:
            out.append((start, last + 1))
            start = None
    if start is not None:
        out.append((start, last + 1))
    return out


def crossings(x, fs):
    t = [i - 1 + (-x[i - 1]) / (x[i] - x[i - 1]) for i in range(1, len(x)) if x[i - 1] < 0 <= x[i]]
    return (len(t) - 1) * fs / (t[-1] - t[0]) if len(t) > 1 else 0.0


def rms(x):
    m = sum(x) / len(x)
    return math.sqrt(sum((v - m) ** 2 for v in x) / len(x))


def line(x, fs, f):
    """The amplitude of the spectrum's line at f (Goertzel)."""
    w = 2 * math.pi * f / fs
    c = 2 * math.cos(w)
    s1 = s2 = 0.0
    for v in x:
        s1, s2 = v + c * s1 - s2, s1
    return 2 * math.sqrt(max(s1 * s1 + s2 * s2 - c * s1 * s2, 0.0)) / len(x)


def peak(x, fs, f):
    """Where the line near f is strongest (within 1.5 %), and how strong."""
    best = max((line(x, fs, f * (1 + k / 2000)), f * (1 + k / 2000)) for k in range(-30, 31))
    return best[1], best[0]


def decode(x, fs, rate, tol):
    """The recording as the shift register's bits: the best fit of a rate
    within tol of the one given and of where the first bit starts, on the
    first 150 bits, then 800, then all. -> (the bits that agree, of how
    many, the rate)."""
    seq = sequence(32768)

    def score(r, off, nbits):
        ok = 0
        for i in range(nbits):
            ok += (x[int(off + (i + 0.5) * fs / r)] > 0) == bool(seq[i])
        return ok

    total = int((len(x) - 16) * rate * (1 - tol) / fs) - 2
    centre, width = rate, max(tol, 0.003)
    for nbits in (min(total, 150), min(total, 800), total):
        step = 0.2 / nbits                   # a fifth of a bit at the end
        n = int(width / step) + 1
        got = [(score(centre * (1 + k * step), off, nbits), centre * (1 + k * step), off)
               for k in range(-n, n + 1) for off in range(7)]
        top = max(g[0] for g in got)
        tied = sorted(g[1:] for g in got if g[0] == top)
        centre, off = tied[len(tied) // 2]   # the middle of those that fit
        width = 0.6 / nbits
    return score(centre, off, total), total, centre


def judge(left, right, fs):
    problems, notes = [], []
    bl, br = bursts(left, fs), bursts(right, fs)
    if len(bl) < len(SOUNDS) or len(br) < len(SOUNDS):
        return [f"{len(bl)} and {len(br)} sounds on the two channels, not {len(SOUNDS)}"], notes
    bl, br = bl[-len(SOUNDS):], br[-len(SOUNDS):]
    ref = None
    for k, spec in enumerate(SOUNDS):
        what = f"sound {k + 1} ({spec[0]})"
        res = []
        for name, ch, (s, e) in (("left", left, bl[k]), ("right", right, br[k])):
            x = ch[s:e]
            mid = x[len(x) // 8:len(x) * 7 // 8]
            level = rms(mid)
            if abs((e - s) / fs - ON / (TICK * SHARP)) > 0.03:
                problems.append(f"{what}, {name}: {(e - s) / fs:.3f} s long, not {ON / (TICK * SHARP):.3f}")
            if max(abs(v) for v in x) > 30000:
                problems.append(f"{what}, {name}: clipped")
            if spec[0] == "tone":
                f = crossings(mid, fs)
                amp = line(mid, fs, f) * math.pi / 4     # the square wave by its fundamental
                if ref is None:
                    ref = amp
                if abs(f / (spec[1] * SHARP) - 1) > 0.0005:
                    problems.append(f"{what}, {name}: {f:.2f} Hz, not {spec[1] * SHARP:.2f}")
                if abs(amp / ref / spec[2] - 1) > 0.05:
                    problems.append(f"{what}, {name}: level {amp / ref:.3f} of the first sound's, not {spec[2]:.3f}")
                res.append(f"{f:.2f} Hz ({spec[1] * SHARP:.2f}), level {amp / ref:.3f}")
            elif spec[0] == "chord":
                levels = spec[2] if isinstance(spec[2], list) else [spec[2]] * len(spec[1])
                got = []
                for want, lv in zip(spec[1], levels):
                    f, amp = peak(mid, fs, want * SHARP)
                    amp *= math.pi / 4 / ref
                    if abs(f / (want * SHARP) - 1) > 0.003:
                        problems.append(f"{what}, {name}: a line at {f:.1f} Hz, not {want * SHARP:.1f}")
                    if abs(amp / lv - 1) > 0.12:
                        problems.append(f"{what}, {name}: the line at {f:.1f} Hz is {amp:.2f} of a tone's, not {lv:.2f}")
                    got.append(f"{f:.1f} Hz x{amp:.2f}")
                res.append(", ".join(got))
            elif spec[0] == "white":
                ok, n, rate = decode(x, fs, spec[1], spec[2])
                if n < 400 or ok < n * 0.99:
                    problems.append(f"{what}, {name}: {ok} of {n} bits are the shift register's")
                if abs(rate / spec[1] - 1) > spec[2]:
                    problems.append(f"{what}, {name}: {rate:.1f} shifts a second, not {spec[1]:.1f}")
                if abs(level / ref - 1) > 0.08:
                    problems.append(f"{what}, {name}: level {level / ref:.3f} of a tone's")
                res.append(f"{ok} of {n} bits, {rate:.1f} shifts a second ({spec[1]:.1f}), level {level / ref:.3f}")
            else:                                        # the pulse
                f = crossings(mid, fs)
                hi = sorted(v for v in mid if v > max(mid) / 2)
                lo = sorted(v for v in mid if v <= max(mid) / 2)
                height = (hi[len(hi) // 2] - lo[len(lo) // 2]) / (2 * ref)   # against a tone's peak to peak
                duty = len(hi) / len(mid)
                if abs(f / (spec[1] * SHARP) - 1) > 0.0005:
                    problems.append(f"{what}, {name}: {f:.2f} Hz, not {spec[1] * SHARP:.2f}")
                if abs(height - 1) > 0.06:
                    problems.append(f"{what}, {name}: the pulse is {height:.2f} of a tone's height")
                if abs(duty - 1 / 15) > 0.012:
                    problems.append(f"{what}, {name}: high {duty * 100:.1f} % of the time, not 6.7")
                res.append(f"{f:.2f} Hz ({spec[1] * SHARP:.2f}), height {height:.2f}, high {duty * 100:.1f} %")
        if abs(bl[k][0] - br[k][0]) > fs * 0.0005:
            problems.append(f"{what}: the channels start {abs(bl[k][0] - br[k][0]) / fs * 1e6:.0f} us apart")
        notes.append(f"{k + 1:2d} {spec[0]:5s} {res[0]}" + ("" if res[0] == res[1] else f" | right: {res[1]}"))
    ticks = (ON + OFF) * (len(SOUNDS) - 1)
    rate = ticks / ((bl[-1][0] - bl[0][0]) / fs)
    notes.append(f"the timer: {rate:.3f} ticks a second by the sounds' spacing ({TICK * SHARP:.3f})")
    if abs(rate / (TICK * SHARP) - 1) > 0.005:
        problems.append(f"the timer: {rate:.3f} ticks a second, not {TICK * SHARP:.3f}")
    return problems, notes


def main():
    work = os.path.join(ROOT, "build", "psg")
    os.makedirs(work, exist_ok=True)
    com = os.path.join(work, "PSGWAV.COM#060000")
    subprocess.run(["nasm", "-f", "bin", "-o", com, os.path.join(ROOT, "tests", "snd", "psgwav.asm")], check=True)
    cmd = os.path.join(work, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write("C PSGWAV.COM\rVIDEO=TANDY\r")
    stage = os.path.join(ROOT, "build", "stage")
    image = os.path.join(work, "psgwav.po")
    subprocess.run([os.path.join(HERE, "make_image.sh"), image, os.path.join(stage, "XTGS.SYSTEM#FF2000"),
                    os.path.join(stage, "CORE#060000"), os.path.join(stage, "SVC#060000"), com, cmd],
                   check=True, capture_output=True)
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    svc = symbols.read(os.path.join(ROOT, "build", "svc.lst"))
    path = os.path.join(work, "psgwav.wav")
    r = mamerun.run(image, waits=[(syms["mb_magic"], 0x5A5A)],
                    dumps=[("mb", syms["mb_stage"], 8), ("irqs", svc["DOC_IRQS"], 4)],
                    seconds=90, settle=30, wav=path)
    if r["status"] != "hit":
        print(f"psg: the program did not end ({r['status']}, frame {r['frame']})")
        sys.exit(1)
    irqs = bytes.fromhex(r["dumps"]["irqs"]["hex"])
    with wave.open(path) as w:
        nch, fs = w.getnchannels(), w.getframerate()
        data = array.array("h")
        data.frombytes(w.readframes(w.getnframes()))
    if sys.byteorder == "big":
        data.byteswap()
    if not os.environ.get("KEEP"):
        os.unlink(path)
    # MAME's channels: the Apple II speaker, then the DOC's
    if nch < 3:
        print(f"psg: {nch} channels in the recording")
        sys.exit(1)
    stray = [c for c in range(3, nch) if any(data[c::nch])]
    problems, notes = judge(data[1::nch], data[2::nch], fs)
    if stray:
        problems.append(f"sound on the DOC's channels {stray}")
    print(f"psg: {r['frame']} frames, {irqs[0] | irqs[1] << 8} timer interrupts ({irqs[2] | irqs[3] << 8} dropped), "
          f"{nch} channels at {fs} Hz")
    for n in notes:
        print("  " + n)
    if problems:
        print("  FAIL: " + "; ".join(problems))
        sys.exit(1)
    print("PSG sound: PASS")


if __name__ == "__main__":
    main()
