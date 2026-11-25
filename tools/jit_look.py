#!/usr/bin/env python3
"""jit_look.py: what the translator's time is made of, call by call (docs/jit.md, "A closer look").

Reads what tools/jit_profile.py left in build/jitprof/: for each workload the profile without the
translator (NAME.pkl), the one with it (jit/NAME.pkl: `collect NAME --jit`) and the counts (jit/NAME.count:
`count NAME`), and prints

  - the cycles a call of each run-time routine takes (its share of the samples over its calls a second),
  - the lazy flags stored by translated code and never read, and what a look at the code a piece goes on
    to could show of that (from the run without the translator: every transfer of control, the flags the
    code before it left, the first instructions of where it goes),
  - the stores, and how the look for translated code under them ends,
  - the code cache a workload's window would fill.
"""
import json
import os
import pickle
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import jit_profile as jp  # noqa: E402
import x86dec  # noqa: E402

B = os.path.join(jp.ROOT, "build", "jitprof")
NAMES = ("keen-load", "basic", "thexder-tandy", "arkanoid", "lsl2")
PER = 22.0          # bytes of cache an instruction, its share of the piece's stub and record in it
ALL = frozenset("oszapc")
UNKNOWN = ("ret", "retf", "iret", "jind", "cind", "int", "callf", "jmpf", "hlt", "bad")


def look(mem, cs, ip, depth, pending, budget):
    """True: every flag in `pending` is written before it is read, on every way on from cs:ip."""
    while budget > 0:
        i = x86dec.decode(mem, ((cs << 4) + ip) & 0xFFFFF, cs, ip)
        budget -= 1
        if i.uses & pending:
            return False
        if i.kind in UNKNOWN or (i.kind == "str" and i.rep):     # (a REP is the interpreter's: it must find the flags)
            return False
        pending = pending - i.sets
        if not pending:
            return True
        nxt = (ip + i.length) & 0xFFFF
        if i.kind in ("jmp", "call") and i.target is not None:   # (a call: the routine's first instructions)
            ip = i.target
        elif i.kind in ("jcc", "loop") and i.target is not None:
            return depth > 0 and look(mem, cs, i.target, depth - 1, pending, budget) and \
                look(mem, cs, nxt, depth - 1, pending, budget)
        elif i.kind in ("io", "sreg", "stack", "seq", "muldiv", "shift", "flagio", "str"):
            ip = nxt
        else:
            return False
    return False


def exits(d):
    """{kind: [transfers, with flags left by the code before, of those shown unwanted where it goes]} a second."""
    mem, cnt, edge = d["mem"], d["cnt"], d["edge"]
    ins = {k: x86dec.decode(mem, (((k >> 16) << 4) + (k & 0xFFFF)) & 0xFFFFF, k >> 16, k & 0xFFFF) for k in cnt}
    prev = {(k & ~0xFFFF) | ((k + i.length) & 0xFFFF): k for k, i in ins.items()}
    secs = (d["window"][1] - d["window"][0]) / 60.0
    out = {}
    for (u, v), w in edge.items():
        if u not in ins or v not in ins:
            continue
        i = ins[u]
        if v == ((u & ~0xFFFF) | ((u + i.length) & 0xFFFF)) and i.kind != "call":
            continue                                            # (the next instruction)
        near = (u >> 16) == (v >> 16) and abs((v & 0xFFFF) - (u & 0xFFFF)) <= 48 and i.kind in ("jcc", "jmp", "loop")
        kind = "a jump of 48 bytes or less" if near else \
            {"jcc": "a jump further", "jmp": "a jump further", "loop": "a jump further", "call": "a call"}.get(i.kind, "a return")
        row = out.setdefault(kind, [0, 0, 0])
        row[0] += w / secs
        k, n = u, 0
        while k is not None and n < 48 and not ins[k].sets:
            k, n = prev.get(k), n + 1
        if k is None or n >= 48:
            continue
        row[1] += w / secs
        if kind != "a return" and look(mem, v >> 16, v & 0xFFFF, 2, ALL, 12):
            row[2] += w / secs
    return out


def main():
    for name in NAMES:
        try:
            d0 = pickle.load(open(os.path.join(B, name + ".pkl"), "rb"))
            d = pickle.load(open(os.path.join(B, "jit", name + ".pkl"), "rb"))
            c = json.load(open(os.path.join(B, "jit", name + ".count")))
        except OSError as e:
            print("%s: %s" % (name, e))
            continue
        hz = d["hz"]
        secs = (c["window"][1] - c["window"][0]) / 60.0
        jl = d["jit"]
        lab = jp.Labels(jl, 0x060000, 0x080000)
        N = sum(d["samp"].values())
        rout, cache = Counter(), 0
        for (a, _k), n in d["samp"].items():
            if a >> 16 == 9:                                 # (the second bank of code)
                a -= 0x020000
            if a >> 16 in (6, 7):
                if a >= jl["jt_cache"]:
                    cache += n
                else:
                    rout[lab.find(a)] += n
        pct = lambda n: 100.0 * n / N                            # noqa: E731
        calls = {k: v / secs for k, v in c["calls"].items()}

        def each(names):
            t = sum(rout[r] for r in names)
            n = sum(calls.get(r, 0) for r in names if not (r.startswith("ea_") and r[7] in "wf"))
            n += sum(calls.get(r, 0) for r in names if r.startswith("ea_") and r[7] in "wf")
            return pct(t), (t / N * hz / n if n else 0), n
        print("==== %s (%.0f MHz): translated code %.1f%% of the time, its routines %.1f%%" %
              (name, hz / 1e6, pct(cache), pct(sum(n for r, n in rout.items() if (jl.get(r, 0) >> 16) == 7))))
        fl = c["flags"]
        st, dead = fl["translated"] / secs, fl["dead"] / max(fl["dead"] + fl["used"], 1)
        print("  flags: stored %.0f times a second by translated code, %.1f%% of them never read: %.1f%% to %.1f%% of all "
              "time (32 to 42 cycles a store)" % (st, 100 * dead, 100 * st * dead * 32 / hz, 100 * st * dead * 42 / hz))
        ex = exits(d0)
        tot = sum(r[1] for k, r in ex.items() if k != "a jump of 48 bytes or less")
        got = sum(r[2] for k, r in ex.items() if k != "a jump of 48 bytes or less")
        for kind in ("a jump of 48 bytes or less", "a jump further", "a call", "a return"):
            r = ex.get(kind, [0, 0, 0])
            print("    without the translator, %-27s %6.0f a second, %6.0f with flags the code before it left, %6.0f "
                  "(%.0f%%) unwanted by the first instructions of where it goes" %
                  (kind + ":", r[0], r[1], r[2], 100 * r[2] / max(r[1], 1)))
        print("    of the ways out of a piece that have flags to store, %.0f%% go where a look shows them unwanted" %
              (100 * got / max(tot, 1)))
        wr = [r for r in rout if r.startswith("ea_") and r[6] == "w"] + [r for r in calls if r.startswith("ea_") and r[6] == "w"]
        rd = [r for r in rout if r.startswith("ea_") and r[6] == "r"] + [r for r in calls if r.startswith("ea_") and r[6] == "r"]
        for what, names in (("stores, the pointer routine", sorted(set(wr))), ("reads by a pointer routine", sorted(set(rd))),
                            ("  on to the look for code (h_smc, pg_chk)", ["h_smc", "pg_chk"]), ("  to video memory (h_hi)", ["h_hi"]),
                            ("pushes (h_push)", ["h_push"]), ("pops (h_pop)", ["h_pop"]), ("far returns (h_retf)", ["h_retf"]),
                            ("looks in the map (h_disp, jt_look)", ["jt_look", "h_disp"]),
                            ("pieces comparing their bytes (h_verify)", ["h_verify"])):
            n = sum(calls.get(r, 0) for r in names if r not in ("pg_chk", "h_disp"))
            t = sum(rout[r] for r in names)
            if n >= 1:
                print("  %-42s %7.0f a second, %5.1f%% of the time, %4.0f cycles each" % (what, n, pct(t), t / N * hz / n))
        if calls.get("h_smc"):
            print("    of the stores that go on to the look for code, %.1f%% find a page no code was made from "
                  "(%.0f a second get as far as the sixteens, %.0f as far as the pieces)" %
                  (100 - 100 * calls.get("pg_dead", 0) / calls["h_smc"], calls.get("pg_dead", 0), calls.get("smc0", 0)))
        p = c["pieces"]
        print("  pieces: %d made since the run began, for %d addresses (%d of them more than once, %s nine times or "
              "more); %d made in the window" % (p["made"], p["addresses"], p["again"], c["hist"].get("9", 0), p["in_window"]))
        order = sorted(d0["cnt"].values(), reverse=True)
        tot, acc, marks, mi, got = sum(order), 0, [0.90, 0.95, 0.99], 0, []
        for n, v in enumerate(order, 1):
            acc += v
            while mi < len(marks) and acc >= marks[mi] * tot:
                got.append("%.0f%% of what is executed: %.0f KB" % (100 * marks[mi], n * PER / 1024))
                mi += 1
        print("  the window's code: %d instructions, %.0f KB of cache at %.0f bytes each; %s" %
              (len(order), len(order) * PER / 1024, PER, "; ".join(got)))
        print()


if __name__ == "__main__":
    main()
