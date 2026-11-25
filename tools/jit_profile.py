#!/usr/bin/env python3
"""M6.2: profile a real guest workload from MAME's side (docs/jit.md).

    jit_profile.py list
    jit_profile.py collect NAME [--from F --to T] [--no-smc] [--stock]
    jit_profile.py report NAME [--top N]
    jit_profile.py summary                  a line for every workload collected
    jit_profile.py compare                  each against its copy in build/jitprof/base/ (keep one
                                            there before a change): instructions a second, the shares, and
                                            "same x", the interpreter's speed on the same instructions
                                            (a demo is at another place in the same frames once the
                                            machine is faster, so instructions a second alone mislead)
    jit_profile.py look NAME F1 F2 ...      the screen at those frames (PNG), no profile

collect boots a workload (WORKLOADS below) on a copy of its volume, types
its keys, and between two frames records, with nothing changed in the
guest or in XT/GS:
  - every guest instruction fetched: a read tap on the direct page's bCS,
    taken when the 65816 is at `fetch`: counts by CS:IP and every pair of
    consecutive instructions (so every edge, with its count);
  - the time: every 1.37 ms of emulated time, where the 65816 is (PB:PC)
    and which guest instruction it is working for;
  - the guest's writes into pages it has executed code from.
The guest's memory is dumped at the end. Work files in build/jitprof/.
report decodes that (tools/x86dec.py) and prints where the time goes, the
blocks and loops it is in, and what a translator would need for them.
"""
import argparse
import os
import pickle
import shutil
import subprocess
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("XTGS_ROOT") or os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "tools", "mame"))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, HERE)
import x86dec  # noqa: E402

WORK = os.path.join(ROOT, "build", "jitprof")
PERIOD = 0.00137            # seconds of emulated time between two samples: no multiple of a frame
ZIP_HZ, STOCK_HZ = 16e6, 2.8636e6


def K(name, port):
    return (name, ":macadb:KEY%d" % port)


KEYS = {"down": K("Down Arrow", 3), "up": K("Up Arrow", 3), "left": K("Left Arrow", 3), "right": K("Right Arrow", 3),
        "ret": K("Return", 2), "tab": K("Tab", 3), "esc": K("Esc", 3), "space": K("Space", 3),
        "ctrl": K("Control", 3), "opt": K("Option / Solid Apple", 3)}

# name: image, what is typed at the DOS prompt (frame 2400 of a 16 MHz boot), then events
# (frame, what): a string is typed, ("tap", key) a key for 8 frames, ("hold", key, frames);
# window: the frames profiled; what: one line for the report.
WORKLOADS = {
    "thexder-tandy": dict(image="games.po", start="CD THEXDER{ENTER}THEXDER{ENTER}", events=[(3600, "n")],
                          window=(5600, 7400), what="Thexder, Tandy mode 09h, the game's own demo of level 1"),
    "thexder-cga": dict(image="gamescga.po", start="CD THEXDER{ENTER}THEXDER{ENTER}", events=[(3600, "n")],
                        window=(5600, 7400), what="Thexder, CGA mode 4, the game's own demo of level 1"),
    "keen-load": dict(image="gamesega.po", start="CD KEEN1{ENTER}KEEN1{ENTER}", events=[],
                      window=(4000, 5800), what="Commander Keen 1 decompressing its graphics as it starts (160 s of it)"),
    "keen-title": dict(image="gamesega.po", start="CD KEEN1{ENTER}KEEN1{ENTER}", events=[],
                       window=(17200, 19000), what="Commander Keen 1, its opening over a scrolling starfield, EGA mode 0Dh"),
    "arkanoid": dict(image="games.po", start="CD ARKANOID{ENTER}ARKANOID{ENTER}", events=[(3300, "t"), (3900, "k")],
                     window=(7800, 9600), what="Arkanoid, Tandy mode 09h, the game's own demo of round 1"),
    "lsl2": dict(image="games.po", start="CD LSL2{ENTER}SIERRA{ENTER}", events=[(9000, "7448{ENTER}")],
                 window=(12000, 13800),
                 what="Leisure Suit Larry 2, the title's animation (Sierra's SCI interpreter running the game's scripts), Tandy mode 09h"),
    "basic": dict(image="gamesega.po", start="GWBASIC{ENTER}",
                  events=[(3300, "10 FOR I=1 TO 30000:A=A+I*2:B=SQR(A)+B/3:NEXT:GOTO 10{ENTER}"), (3900, "RUN{ENTER}")],
                  window=(4200, 6000), what="GW-BASIC 3.23 running a FOR loop of floating-point arithmetic"),
    "boot": dict(image="gamesega.po", start="", events=[], window=(200, 1250),
                 what="FreeDOS booting from the shared folder, up to its prompt (the control)"),
    "prompt": dict(image="gamesega.po", start="", events=[], window=(1500, 2400),
                   what="FreeDOS's shell waiting at its prompt (an idle case)"),
}


def load_workloads():
    extra = os.path.join(WORK, "workloads.py")
    if os.path.exists(extra):
        ns = {"KEYS": KEYS}
        exec(open(extra).read(), ns)
        WORKLOADS.update(ns.get("WORKLOADS", {}))


def inputs_for(w):
    ev = []
    if w["start"]:
        ev.append({"at": 2400, "after": "start", "coded": w["start"]})
    for e in w["events"]:
        f, what = e
        if isinstance(what, str):
            ev.append({"at": f, "after": "start", "coded": what})
        else:
            name, port = KEYS[what[1]]
            n = 8 if what[0] == "tap" else what[2]
            ev.append({"at": f, "after": "start", "press": name, "port": port, "value": 1})
            ev.append({"at": f + n, "after": "start", "press": name, "port": port, "value": 0})
    return ev


LUA_TOP = r"""
local XP = {from=@FROM@, to=@TO@, on=false, done=false, n=0, nf=0, nw=0, cnt={}, edge={}, s={}, w={}, xpg={},
            cur=0, cs=0, ic0=0, ic1=0, f0=0, f1=0}
local xcpu = manager.machine.devices[":maincpu"]
local xsp = xcpu.spaces["program"]
local xPB, xPC, xY = xcpu.state["PB"], xcpu.state["PC"], xcpu.state["Y"]
local XSMC = @SMC@
local XJ, XJN = @JSTATS@, 14
local xj_prev, xj_acc = nil, {}
local function xj_poll()
    if XJ == 0 then return end
    local a = at(XJ)
    local now = {}
    for i = 0, XJN - 1 do now[i] = xsp:read_u16(a + 2 * i) end
    if xj_prev then
        for i = 0, XJN - 1 do xj_acc[i] = (xj_acc[i] or 0) + ((now[i] - xj_prev[i]) & 0xFFFF) end
    end
    xj_prev = now
end
local xt1, xt2, xt3 = nil, nil, nil
local XDP, XFETCH, XGUEST
local function xon()
    XDP = at(0x001000)
    XFETCH = at(@FETCH@) + 2             -- MAME's PC for the 65816 has the bank in it
    XGUEST = at(0x200000)
    XP.cs = xsp:read_u16(XDP + 0x12)
    XP.ic0 = xsp:read_u32(XDP + 0x48)
    XP.f0 = frame
    local cnt, edge, xpg = XP.cnt, XP.edge, XP.xpg
    xt1 = xsp:install_read_tap(XDP + 0x20, XDP + 0x20, "xfetch", function(o, d, m)
        if xPC.value == XFETCH then
            local y = xY.value
            local k = (XP.cs << 16) | y
            XP.nf = XP.nf + 1
            cnt[k] = (cnt[k] or 0) + 1
            local e = (XP.cur << 32) | k
            edge[e] = (edge[e] or 0) + 1
            XP.cur = k
            xpg[(((XP.cs << 4) + y) >> 8) & 0xFFF] = true
        end
    end)
    xt2 = xsp:install_write_tap(XDP + 0x12, XDP + 0x13, "xcs", function(o, d, m)
        if o == XDP + 0x12 then XP.cs = (XP.cs & 0xFF00) | (d & 0xFF)
        else XP.cs = (XP.cs & 0x00FF) | ((d & 0xFF) << 8) end
    end)
    if XSMC then
        local w = XP.w
        xt3 = xsp:install_write_tap(XGUEST, XGUEST + 0x9FFFF, "xwr", function(o, d, m)
            local a = o - XGUEST
            XP.nw = XP.nw + 1
            if xpg[a >> 8] then w[a] = (w[a] or 0) + 1 end
        end)
    end
    XP.on = true
    xj_poll()
end
local function xoff()
    xj_poll()
    XP.ic1 = xsp:read_u32(XDP + 0x48)
    XP.f1 = frame
    xt1:remove(); xt2:remove()
    if xt3 then xt3:remove() end
    XP.on, XP.done = false, true
end
local function xsample()
    local k = ((((xPB.value << 16) | xPC.value) & 0xFFFFFF) << 32) | XP.cur
    XP.s[k] = (XP.s[k] or 0) + 1
    XP.n = XP.n + 1
    if XP.n % 256 == 0 then xj_poll() end
end
xreport = function()
    if XP.on then xoff() end
    print(string.format("MAMERUN-X N %d %d %d %d %d %d %d", XP.n, XP.nf, XP.nw, XP.ic0, XP.ic1, XP.f0, XP.f1))
    for i = 0, XJN - 1 do print(string.format("MAMERUN-X J %d %d", i, xj_acc[i] or 0)) end
    for k, n in pairs(XP.cnt) do print(string.format("MAMERUN-X C %x %d", k, n)) end
    for k, n in pairs(XP.edge) do print(string.format("MAMERUN-X E %x %d", k, n)) end
    for k, n in pairs(XP.s) do print(string.format("MAMERUN-X S %x %d", k, n)) end
    for k, n in pairs(XP.w) do print(string.format("MAMERUN-X W %x %d", k, n)) end
end
"""
LUA_TAIL = r"""
while true do
    emu.wait(@PERIOD@)
    if not XP.on and not XP.done and frame >= XP.from then xon() end
    if XP.on and frame >= XP.to then xoff() end
    if XP.on then xsample() end
end
"""


# ---- count: how often, not how long. Taps where the sampler has a clock: the first byte of each of the
# translator's run-time routines as the 65816 fetches it (a call), every store of the lazy flags (vLP) with
# where it was made and whether anything read the flags before the next one, and every stub put in the map
# from the start of the run (a piece made, and for which address).
LUA_CTOP = r"""
local XC = {from=@FROM@, to=@TO@, on=false, done=false, c={}, fj=0, fo=0, dead=0, used=0, pj=false, rd=false,
            mk={}, made=0, mwin=0, mapon=false, f0=0, f1=0}
local xcpu = manager.machine.devices[":maincpu"]
local xsp = xcpu.spaces["program"]
local xPB, xPC = xcpu.state["PB"], xcpu.state["PC"]
local XR = {@ROUT@}
local xtaps = {}
local function xmap()
    local mp = at(@MAP@)
    if mp == nil then return end
    XC.mapon = true
    XC.xm = xsp:install_write_tap(mp, mp + 0xFFFF, "xmap", function(o, d, m)
        if (o & 1) == 1 and (d & 0xFF) >= 2 then
            local k = (o - mp) >> 1
            XC.mk[k] = (XC.mk[k] or 0) + 1
            XC.made = XC.made + 1
            if XC.on then XC.mwin = XC.mwin + 1 end
        end
    end)
end
local function xon()
    for i, a0 in ipairs(XR) do
        local a = at(a0)
        XC.c[i] = 0
        xtaps[#xtaps + 1] = xsp:install_read_tap(a, a, "xc" .. i, function(o, d, m) XC.c[i] = XC.c[i] + 1 end)
        if (a0 >> 16) == 7 then                             -- (and its copy in the second bank of code)
            local b = a + 0x20000
            xtaps[#xtaps + 1] = xsp:install_read_tap(b, b, "xd" .. i, function(o, d, m) XC.c[i] = XC.c[i] + 1 end)
        end
    end
    local dp = at(0x001000)
    local lo = at(@CACHE@)
    local hi = lo | 0xFFFF
    xtaps[#xtaps + 1] = xsp:install_write_tap(dp + @VLP@, dp + @VLP@, "xlp", function(o, d, m)
        if XC.pj then
            if XC.rd then XC.used = XC.used + 1 else XC.dead = XC.dead + 1 end
        end
        local pc = ((xPB.value << 16) | xPC.value) & 0xFFFFFF
        if (pc >= lo and pc <= hi) or (pc >= lo + 0x20000 and pc <= hi + 0x20000) then
            XC.pj = true
            XC.fj = XC.fj + 1
        else
            XC.pj = false
            XC.fo = XC.fo + 1
        end
        XC.rd = false
    end)
    xtaps[#xtaps + 1] = xsp:install_read_tap(dp + @VLP@, dp + @VLP@ + 3, "xlr", function(o, d, m) XC.rd = true end)
    local jp = at(@JRPLAIN@)
    if jp ~= 0 then                                         -- the interpreter given the run: why (X, twice), where (Y), under which CS
        XC.pl = {}
        xtaps[#xtaps + 1] = xsp:install_read_tap(jp, jp, "xjp", function(o, d, m)
            local k = (xcpu.state["X"].value << 32) | (xsp:read_u16(dp + 0x12) << 16) | xcpu.state["Y"].value
            XC.pl[k] = (XC.pl[k] or 0) + 1
            XC.free, XC.wrote, XC.fn = true, false, 0
        end)
        -- and what it wrote while it had the run: did any of it land on a page translated code was made from
        -- (pg_map)? That is what watching its stores would know, and the epoch would then go on for those alone.
        local pg, gb, je = at(@PGMAP@), at(0x200000), at(@JTENTER@)
        XC.runs, XC.dirty, XC.fins = 0, 0, 0
        xtaps[#xtaps + 1] = xsp:install_write_tap(gb, gb + 0xFFFFF, "xfw", function(o, d, m)
            if XC.free and not XC.wrote and (xsp:read_u8(pg + ((o - gb) >> 8)) & 1) == 1 then XC.wrote = true end
        end)
        xtaps[#xtaps + 1] = xsp:install_read_tap(dp + 0x20, dp + 0x20, "xfi", function(o, d, m)
            if XC.free then XC.fn = XC.fn + 1 end
        end)
        xtaps[#xtaps + 1] = xsp:install_read_tap(je, je, "xje", function(o, d, m)
            if XC.free then
                XC.runs = XC.runs + 1
                XC.fins = XC.fins + XC.fn
                if XC.wrote then XC.dirty = XC.dirty + 1 end
                XC.free = false
            end
        end)
    end
    XC.on, XC.f0 = true, frame
end
local function xoff()
    for _, t in ipairs(xtaps) do t:remove() end
    XC.f1 = frame
    XC.on, XC.done = false, true
end
xreport = function()
    if XC.on then xoff() end
    print(string.format("MAMERUN-X N %d %d %d %d %d %d", XC.f0, XC.f1, XC.fj, XC.fo, XC.dead, XC.used))
    for i, n in ipairs(XC.c) do print(string.format("MAMERUN-X K %d %d", i, n)) end
    local u, again, h = 0, 0, {}
    for k, n in pairs(XC.mk) do
        u = u + 1
        if n > 1 then again = again + 1 end
        local b = n > 8 and 9 or n
        h[b] = (h[b] or 0) + 1
    end
    print(string.format("MAMERUN-X M %d %d %d %d", XC.made, u, again, XC.mwin))
    for b = 1, 9 do print(string.format("MAMERUN-X H %d %d", b, h[b] or 0)) end
    for k, n in pairs(XC.pl or {}) do print(string.format("MAMERUN-X P %x %d", k, n)) end
    if XC.runs then print(string.format("MAMERUN-X R %d %d %d", XC.runs, XC.dirty, XC.fins)) end
end
"""
LUA_CTAIL = r"""
while true do
    emu.wait(0.05)
    if not XC.mapon then xmap() end
    if not XC.on and not XC.done and frame >= XC.from then xon() end
    if XC.on and frame >= XC.to then xoff() end
end
"""


def count(name, w, args):
    """count NAME: the workload with the translator, counted (above); kept in build/jitprof/jit/NAME.count."""
    import json
    import mamerun
    import symbols
    work = os.path.join(WORK, "jit")
    os.makedirs(work, exist_ok=True)
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    jit = symbols.read(os.path.join(ROOT, "build", "jit.lst"))
    f0, f1 = (args.frm, args.to) if args.frm else w["window"]
    names = ["jt_enter", "jt_enter_b", "jt_enter_s", "jt_enter_n", "jt_enter_r", "h_disp", "jt_look", "h_linkb",
             "h_linkf", "h_verify", "h_bailr", "h_hi", "pg_chk", "pg_dead", "cl_chk", "h_smc", "h_push", "h_pop",
             "h_retf", "smc0", "stale0", "give0", "jt_tr0", "jt_flush", "kill"]
    names += sorted(n for n in jit if n.startswith("ea_") and len(n) == 8 and n[5] == "_")
    names += ["jl_cnt", "h_miss", "h_gx"]
    names = [n for n in names if n in jit]
    core = symbols.read(os.path.join(ROOT, "build", "core.lst"))
    cnames = [n for n in ("jr_plain", "jr_guard", "jr_step", "jr_any", "jr_stack", "jr_pure", "jr_str", "jit_bk", "jit_hook",
                          "jh_bump", "jh_back", "jit_slotret") if n in core]
    for n in cnames:                                        # (the core's side of the ways out, counted the same way)
        jit["core:" + n] = core[n]
    names += ["core:" + n for n in cnames]
    copy = os.path.join(work, "run-%d.po" % os.getpid())
    shutil.copyfile(os.path.join(ROOT, "build", "boot", w["image"]), copy)
    refresh(copy, True)
    sub = {"@FROM@": str(f0), "@TO@": str(f1), "@ROUT@": ",".join(str(jit[n]) for n in names),
           "@MAP@": str((jit["jt_cache"] & 0xFF0000) + 0x10000), "@CACHE@": str(jit["jt_cache"]), "@VLP@": "0x4C",
           "@JRPLAIN@": str(core.get("jr_plain", 0)), "@PGMAP@": str(jit.get("pg_map", 0)),
           "@JTENTER@": str(jit.get("jt_enter", 0))}
    top, tail = LUA_CTOP, LUA_CTAIL
    for k, v in sub.items():
        top, tail = top.replace(k, v), tail.replace(k, v)
    try:
        r = mamerun.run(copy, waits=[(syms["mb_magic"], 0x5A5A)], dumps=[("jstats", jit["jt_stats"], 20)],
                        seconds=(f1 + 30) / 60.0, settle=5, zip=not args.stock, inputs=inputs_for(w),
                        extra={"top": top, "tail": tail}, timeout=7200)
    finally:
        os.remove(copy)
    out = dict(name=name, calls={}, hist={})
    for line in r.get("extra", []):
        t = line.split()
        if t[0] == "N":
            out["window"] = (int(t[1]), int(t[2]))
            out["flags"] = dict(translated=int(t[3]), other=int(t[4]), dead=int(t[5]), used=int(t[6]))
        elif t[0] == "K":
            out["calls"][names[int(t[1]) - 1]] = int(t[2])
        elif t[0] == "M":
            out["pieces"] = dict(made=int(t[1]), addresses=int(t[2]), again=int(t[3]), in_window=int(t[4]))
        elif t[0] == "H":
            out["hist"][t[1]] = int(t[2])
        elif t[0] == "P":
            out.setdefault("plain", {})[t[1]] = int(t[2])
        elif t[0] == "R":
            out["freeruns"] = dict(runs=int(t[1]), wrote_code_page=int(t[2]), fetches=int(t[3]))
    if "window" not in out:
        sys.exit("no counts came back: " + r["status"])
    # a read's entry for a word or four bytes goes on into the byte's: what is the byte's own
    for n in list(out["calls"]):
        if n.startswith("ea_") and n.endswith("rb"):
            out["calls"][n] -= out["calls"].get(n[:-1] + "w", 0) + out["calls"].get(n[:-1] + "f", 0)
    out["hz"] = STOCK_HZ if args.stock else ZIP_HZ
    with open(os.path.join(work, name + ".count"), "w") as f:
        json.dump(out, f, indent=1)
    secs = (out["window"][1] - out["window"][0]) / 60.0
    print("%s, frames %d-%d (%.1f s): a second" % (name, *out["window"], secs))
    for n, c in sorted(out["calls"].items(), key=lambda x: -x[1]):
        if c:
            print("  %-12s %9.0f" % (n, c / secs))
    fl = out["flags"]
    print("  the lazy flags stored by translated code %.0f a second; nothing read them before the next store %.1f%% of "
          "the time; stored by the interpreter and the routines %.0f" %
          (fl["translated"] / secs, 100.0 * fl["dead"] / max(fl["dead"] + fl["used"], 1), fl["other"] / secs))
    pc = out["pieces"]
    print("  pieces made since the run began %d, for %d addresses (%d of them more than once); %d in the window" %
          (pc["made"], pc["addresses"], pc["again"], pc["in_window"]))
    print("  made once, twice, ...: " + " ".join("%s:%d" % (k, out["hist"][k]) for k in sorted(out["hist"])))
    fr = out.get("freeruns")
    if fr and fr["runs"]:
        print("  the interpreter's runs by itself that ended back in translated code: %.0f a second, %.0f instructions "
              "each; in %.1f%% of them a store landed on a page translated code was made from" %
              (fr["runs"] / secs, fr["fetches"] / fr["runs"], 100.0 * fr["wrote_code_page"] / fr["runs"]))
    pl = sorted(((n, int(k, 16)) for k, n in out.get("plain", {}).items()), reverse=True)
    if pl:
        print("  the interpreter given the run (why, CS:IP, times a second): " +
              ", ".join("%d %04X:%04X %.1f" % ((k >> 33) & 0x7FFF, (k >> 16) & 0xFFFF, k & 0xFFFF, n / secs) for n, k in pl[:14]))


def refresh(image, jit):
    """The copy of a workload's volume gets this build's XTGS.SYSTEM, CORE and SVC (the listings the
    report reads are this build's), and for a run with the translator the file JIT and the line JIT=ON."""
    import subprocess
    import tempfile
    cadius = os.path.join(HERE, "cadius_strict.sh")
    stage = os.path.join(ROOT, "build", "stage")

    def run(*a):
        r = subprocess.run([cadius] + list(a), capture_output=True, text=True)
        return r.returncode
    for f in ("XTGS.SYSTEM#FF2000", "CORE#060000", "SVC#060000"):
        run("DELETEFILE", image, "/XTGS/" + f.split("#")[0])
        if run("ADDFILE", image, "/XTGS/", os.path.join(stage, f)):
            sys.exit("could not put %s on the copy of the volume" % f)
    run("DELETEFILE", image, "/XTGS/JIT")
    with tempfile.TemporaryDirectory(dir=WORK) as t:
        if run("EXTRACTFILE", image, "/XTGS/XTGS.CMD", t + "/"):
            sys.exit("no XTGS.CMD on the volume")
        got = [f for f in os.listdir(t) if f.upper().startswith("XTGS.CMD")]
        text = open(os.path.join(t, got[0]), "rb").read().replace(b"JIT=ON\r", b"")
        if jit:
            text += b"JIT=ON\r"
        out = os.path.join(t, "XTGS.CMD#040000")
        for f in got:
            os.remove(os.path.join(t, f))
        open(out, "wb").write(text)
        run("DELETEFILE", image, "/XTGS/XTGS.CMD")
        if run("ADDFILE", image, "/XTGS/", out):
            sys.exit("could not put XTGS.CMD back")
    if jit and run("ADDFILE", image, "/XTGS/", os.path.join(stage, "JIT#060000")):
        sys.exit("could not put JIT on the copy of the volume")


def collect(name, w, args):
    import mamerun
    import shr
    import symbols
    global WORK
    os.makedirs(WORK, exist_ok=True)
    if args.jit:
        WORK = os.path.join(WORK, "jit")
        os.makedirs(WORK, exist_ok=True)
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    core = symbols.read(os.path.join(ROOT, "build", "core.lst"))
    svc = symbols.read(os.path.join(ROOT, "build", "svc.lst"))
    f0, f1 = (args.frm, args.to) if args.frm else w["window"]
    look = getattr(args, "frames", None)
    copy = os.path.join(WORK, "run-%d.po" % os.getpid())
    shutil.copyfile(os.path.join(ROOT, "build", "boot", w["image"]), copy)
    refresh(copy, args.jit)
    jit = symbols.read(os.path.join(ROOT, "build", "jit.lst")) if args.jit else {}
    inputs = inputs_for(w)
    snaps = look or [f0, (f0 + f1) // 2, f1 - 1]
    for f in snaps:
        inputs.append({"at": f, "after": "start", "snap": "f%05d" % f})
    extra = None
    if not look:
        sub = {"@JSTATS@": str(jit.get("jt_stats", 0)), "@FROM@": str(f0), "@TO@": str(f1), "@FETCH@": str(core["fetch"]),
               "@SMC@": "false" if args.no_smc else "true", "@PERIOD@": repr(PERIOD)}
        top, tail = LUA_TOP, LUA_TAIL
        for k, v in sub.items():
            top, tail = top.replace(k, v), tail.replace(k, v)
        extra = {"top": top, "tail": tail}
    last = max(snaps) if look else f1
    dumps = [("m%X" % i, 0x200000 + i * 0x10000, 0x10000) for i in range(16)] if not look else []
    dumps.append(("bda", 0x200400, 0x100))
    if jit:
        dumps.append(("jstats", jit["jt_stats"], 20))
        if "jt_dbg" in jit:
            dumps.append(("jdbg", jit["jt_dbg"], 256))
        if "jt_bes" in jit:
            dumps.append(("jbes", jit["jt_bes"], 288))
            dumps.append(("jeslot", jit["e_slot"], 1000))
        if "jt_rej" in jit:
            dumps.append(("jrej", jit["jt_rej"], 384))
        if "jt_kil" in jit:
            dumps.append(("jkil", jit["jt_kil"], 256))
        if "jit_pl" in core:
            dumps.append(("cpl", core["jit_pl"], 384))
        if "jit_dbg" in core:
            dumps.append(("cdbg", core["jit_dbg"], 384))
    peeks = [tuple(int(v, 16) for v in t.split(",")) for t in os.environ.get("XTGS_PEEK", "").split(";") if t]
    for i, (a, n) in enumerate(peeks):                      # (XTGS_PEEK=addr,len;...: memory at the end, printed)
        dumps.append(("peek%d" % i, a, n))
    try:
        r = mamerun.run(copy, waits=[(syms["mb_magic"], 0x5A5A)], dumps=dumps, seconds=(last + 30) / 60.0,
                        settle=5, zip=not args.stock, inputs=inputs, extra=extra, timeout=7200)
    finally:
        os.remove(copy)
    for k in list(r["dumps"]):
        if k.startswith("shr_"):
            png = shr.render(bytes.fromhex(r["dumps"][k]["hex"]))[0]
            path = os.path.join(WORK, "%s_%s.png" % (name, k[4:]))
            open(path, "wb").write(png)
            print("screen", path)
    print("status", r["status"], "frame", r["frame"], "video mode %02X" % bytes.fromhex(r["dumps"]["bda"]["hex"])[0x49])
    for i, (a, n) in enumerate(peeks):
        print("peek %06X: %s" % (a, r["dumps"]["peek%d" % i]["hex"]))
    if look:
        return
    cnt, edge, samp, wr, meta, jwin = {}, {}, {}, {}, None, {}
    for line in r.get("extra", []):
        t = line.split()
        if t[0] == "N":
            meta = [int(x) for x in t[1:]]
        elif t[0] == "J":
            jwin[int(t[1])] = int(t[2])
        elif t[0] == "C":
            cnt[int(t[1], 16)] = int(t[2])
        elif t[0] == "E":
            v = int(t[1], 16)
            edge[(v >> 32, v & 0xFFFFFFFF)] = int(t[2])
        elif t[0] == "S":
            v = int(t[1], 16)
            samp[(v >> 32, v & 0xFFFFFFFF)] = int(t[2])
        elif t[0] == "W":
            wr[int(t[1], 16)] = int(t[2])
    if meta is None:
        sys.exit("no profile came back: " + r["status"])
    mem = b"".join(bytes.fromhex(r["dumps"]["m%X" % i]["hex"]) for i in range(16))
    data = dict(name=name, what=w["what"], window=(meta[5], meta[6]), n=meta[0], nf=meta[1], nw=meta[2],
                icount=(meta[3], meta[4]), cnt=cnt, edge=edge, samp=samp, wr=wr, mem=mem, period=PERIOD,
                hz=STOCK_HZ if args.stock else ZIP_HZ, smc=not args.no_smc,
                core={n: a for n, a in core.items()}, svc={n: a for n, a in svc.items()},
                jit={n: a for n, a in jit.items()}, jwin=jwin,
                jstats=bytes.fromhex(r["dumps"]["jstats"]["hex"]) if jit else b"",
                jdbg=bytes.fromhex(r["dumps"]["jdbg"]["hex"]) if "jdbg" in r["dumps"] else b"",
                cdbg=bytes.fromhex(r["dumps"]["cdbg"]["hex"]) if "cdbg" in r["dumps"] else b"",
                jrej=bytes.fromhex(r["dumps"]["jrej"]["hex"]) if "jrej" in r["dumps"] else b"",
                jkil=bytes.fromhex(r["dumps"]["jkil"]["hex"]) if "jkil" in r["dumps"] else b"",
                jbes=bytes.fromhex(r["dumps"]["jbes"]["hex"]) if "jbes" in r["dumps"] else b"",
                cpl=bytes.fromhex(r["dumps"]["cpl"]["hex"]) if "cpl" in r["dumps"] else b"",
                mode=bytes.fromhex(r["dumps"]["bda"]["hex"])[0x49])
    with open(os.path.join(WORK, (getattr(args, "save_as", None) or name) + ".pkl"), "wb") as f:
        pickle.dump(data, f)
    print("%d samples, %d instructions, %d distinct, %d edges, %d writes seen" %
          (meta[0], meta[1], len(cnt), len(edge), meta[2]))


# ---------------------------------------------------------------- report

def lin(k):
    return ((k >> 16) * 16 + (k & 0xFFFF)) & 0xFFFFF


def fmt(k):
    return "%04X:%04X" % (k >> 16, k & 0xFFFF)


class Labels:
    def __init__(self, table, lo, hi):
        self.items = sorted((a, n) for n, a in table.items() if lo <= a < hi and not n.startswith("_"))
        self.addrs = [a for a, _ in self.items]

    def find(self, a):
        import bisect
        i = bisect.bisect_right(self.addrs, a) - 1
        return self.items[i][1] if i >= 0 else "?"


SLOTNAMES = ("slot", "next_ct", "next_due", "next_owed", "irq_owed", "irq_soon", "irq_sti")
VIDEO_HINT = ("flush", "render", "cga", "ega", "eg_", "tdy", "gt_", "gs_", "txt", "t160", "blit", "vid", "cur", "pal")

# what a translator of each tier would take (docs/jit.md): T0 is src/core/jit2.s today
def tier(i):
    """0: jit2.s today; 1: register forms, direct jumps; 2: memory operands, the stack, near calls;
    3: left to the interpreter."""
    if i.kind == "hlt":
        return 0
    if i.prefixes and i.rep:
        return 3
    if i.kind == "jcc":
        return 0 if i.op in (0x74, 0x75) and not i.prefixes else 1
    if i.kind in ("jmp", "loop"):
        return 1
    if i.kind in ("call", "ret", "stack", "cind", "jind"):
        return 2
    if i.kind == "str":
        return 2                  # (no REP: a load or a store and a pointer's step)
    if i.kind == "flagio" and i.op in (0xF5, 0xF8, 0xF9, 0xFC, 0xFD, 0x9E, 0x9F):
        return 2                  # CMC CLC STC CLD STD SAHF LAHF
    if i.kind in ("seq", "shift"):
        if i.mem and i.op != 0x8D:
            return 2
        if i.prefixes:
            return 2
        if i.kind == "seq":
            if 0xB8 <= i.op <= 0xBF or 0x40 <= i.op <= 0x4F:
                return 0
            if i.op == 0x01 or (i.op == 0x83 and (i.modrm >> 3) & 7 in (0, 5, 7)) or \
                    (i.op == 0xF7 and (i.modrm >> 3) & 7 == 0):
                return 0
        return 1
    if i.kind == "muldiv":
        return 2
    return 3                      # int iret far io sreg str flagio bad


# Native cycles a translated instruction might take, by what it is. The register forms and the
# jumps are the hand translations' and M6.1's linked blocks' (docs/jit.md), with the two SEP/REP a
# byte operation needs and a share of the flags kept for an exit; a memory operand is the offset,
# the segment's base with its carry, the compare for video memory and a [dp] access, about what the
# hand-translated mem loop spends. Nothing here is measured on translated code of these kinds.
def native_cost(i):
    if i.kind in ("jcc", "jmp", "loop"):
        return 7
    if i.kind == "call":
        return 38                 # the return address pushed
    if i.kind in ("ret", "cind", "jind"):
        return 70                 # an indirect edge: popped or read, then looked up
    if i.kind == "stack":
        return 30
    if i.kind == "str":
        return 70 if i.op in (0xA4, 0xA5, 0xA6, 0xA7) else 42
    if i.kind == "flagio":
        return 8
    if i.kind == "muldiv":
        return 300
    c = 13 if i.wide else 14
    if i.mem and i.op != 0x8D:
        c += 34
    if i.kind == "shift":
        c += 22 if i.op in (0xD2, 0xD3) else 3
    return c


METRICS = {}
XFER_OPS = (0xE8, 0x9A, 0xC2, 0xC3, 0xCA, 0xCB, 0xCD, 0xCF)
FAR_OPS = (0x9A, 0xCA, 0xCB, 0xCD, 0xCF)


def report(name, args, quiet=False):
    d = pickle.load(open(os.path.join(WORK, name + ".pkl"), "rb"))
    m = METRICS[name] = {}
    out = []
    P = lambda s="": out.append(s)  # noqa: E731
    mem, cnt, edge, samp = d["mem"], d["cnt"], d["edge"], d["samp"]
    hz, period = d["hz"], d["period"]
    cyc = hz * period                      # cycles a sample stands for
    core = Labels(d["core"], 0x030000, 0x040000)
    svc = Labels(d["svc"], 0x040000, 0x050000)
    jitl = Labels(d.get("jit") or {}, 0x060000, 0x080000)
    N = d["n"]
    frames = d["window"][1] - d["window"][0]
    P("# %s" % name)
    P("%s. Frames %d-%d (%.1f s of emulated time at %.1f MHz), video mode %02Xh."
      % (d["what"], d["window"][0], d["window"][1], frames / 60.0, hz / 1e6, d["mode"]))
    P("%d samples (one every %.2f ms), %d guest instructions fetched (%.0f a second), %d distinct."
      % (N, period * 1000, d["nf"], d["nf"] / (frames / 60.0), len(cnt)))
    # the work done, by two counts that do not depend on who runs the guest's code: its writes to
    # conventional memory, and the calls, returns and interrupts (the interpreter's always)
    secs = frames / 60.0
    xfer = sum(n for k, n in cnt.items() if mem[lin(k)] in XFER_OPS)
    far = sum(n for k, n in cnt.items() if mem[lin(k)] in FAR_OPS)
    m["writes"], m["xfer"], m["far"] = d["nw"] / secs, xfer / secs, far / secs
    P("Work: %.0f guest writes to conventional memory a second; %.0f calls, returns and INTs a second (%.0f of them far)."
      % (m["writes"], m["xfer"], m["far"]))
    jl = d.get("jit") or {}
    if jl:
        st = d["jstats"]
        w16 = lambda i: st[i] | st[i + 1] << 8  # noqa: E731
        P("The translator was on: %d pieces of code translated, %d refused, %d found changed, the cache emptied %d times; "
          "%d stores beside code, %d pages of data and code, %d pieces given up, %d misses in the map."
          % (w16(0), w16(2), w16(6), w16(4), w16(8), w16(14), w16(10), w16(12)))
        jw = d.get("jwin") or {}
        if jw:
            per = lambda i: jw.get(i, 0) / secs  # noqa: E731
            m["nep"], m["nver"] = per(8) + per(10) + per(11) + per(12), per(9)
            P("  in the window, a second: %.0f pieces translated, %.0f stores beside code; the epoch went on %.0f times "
              "(%.0f the interpreter back at a jump, %.0f after an instruction of its own, %.0f a stack on a page of code, "
              "%.0f a REP MOVS or STOS onto one); pieces compared their bytes %.0f times."
              % (per(0), per(4), m["nep"], per(8), per(10), per(11), per(12), per(9)))
        g = d.get("cpl") or b""
        if g:
            w = lambda i: g[i] | g[i + 1] << 8  # noqa: E731
            pl = Counter((w(i + 2), w(i)) for i in range(0, len(g), 4))
            pl.pop((0, 0), None)
            P("  where the interpreter was last given the run (CS:IP, times among the last 96): " +
              ", ".join("%04X:%04X %d" % (c, i, n) for (c, i), n in pl.most_common(16)))
        g = d.get("jbes") or b""
        if g:
            w = lambda i: g[i] | g[i + 1] << 8  # noqa: E731
            bs = Counter(((w(i + 2) & 0x0F) << 16 | w(i), w(i + 4)) for i in range(0, len(g), 6) if w(i + 2))
            P("  the last stores beside code (linear address, the storing piece's entry * 2; times among the last 48): " +
              ", ".join("%05X %X %d" % (a, e, n) for (a, e), n in bs.most_common(24)))
        g = d.get("jrej") or b""
        if g:
            w = lambda i: g[i] | g[i + 1] << 8  # noqa: E731
            rj = [(w(i + 2), w(i), w(i + 4)) for i in range(0, len(g), 6) if w(i + 4)]
            P("  the last refusals (CS:IP why; 1 the scan, 2 a page of data and code, 3 no room): " +
              ", ".join("%04X:%04X %d" % t for t in rj[:40]))
        g = d.get("jkil") or b""
        if g:
            w = lambda i: g[i] | g[i + 1] << 8  # noqa: E731
            kl = Counter((w(i + 2), w(i), w(i + 4) & 0xFF, ((w(i + 4) >> 8) & 0x0F) << 16 | w(i + 6))
                         for i in range(0, len(g), 8) if w(i + 4) & 0xFF)
            P("  the last pieces to die (CS:IP, why: 1 a store into its bytes, 2 its page became one of data and code, "
              "3 found changed, 4 the EGA's planes; where the store was; times among the last 32): " +
              ", ".join("%04X:%04X %d %05X %d" % (c, i, y, a, n) for (c, i, y, a), n in kl.most_common(20)))
        g = d.get("cdbg") or b""
        if g:
            w = lambda i: g[i] | g[i + 1] << 8  # noqa: E731
            anyw = Counter((w(i + 2), w(i), w(i + 4)) for i in range(0, len(g), 6))
            anyw.pop((0, 0, 0), None)
            P("  the last instructions given to the interpreter as writing anywhere (CS:IP, bytes, times among the last 64): " +
              ", ".join("%04X:%04X %02X %02X %d" % (c, i, b & 0xFF, b >> 8, n) for (c, i, b), n in anyw.most_common(12)))
        g = d.get("jdbg") or b""
        if g:
            miss = Counter((g[i + 2] | g[i + 3] << 8, g[i] | g[i + 1] << 8) for i in range(0, len(g), 4))
            miss.pop((0, 0), None)
            P("  the last misses (CS:IP, times among the last 64): " +
              ", ".join("%04X:%04X %d" % (c, i, n) for (c, i), n in miss.most_common(12)))
    P()

    # --- 1. where the 65816 is
    host = Counter()
    rout = Counter()
    cpu_k = Counter()                      # CORE samples by guest instruction (the interpreter's time)
    oth_k = Counter()
    for (a, k), n in samp.items():
        bank = a >> 16
        if bank == 0x09 and jl:                              # (the second bank of code: the same routines, and more pieces)
            a, bank = a - 0x020000, 0x07
        if bank == 0x03:
            r = core.find(a)
            if r in SLOTNAMES:
                host["the slot (CORE)"] += n
            else:
                host["interpreter (CORE)"] += n
                cpu_k[k] += n
            rout["CORE " + r] += n
        elif bank == 0x04:
            r = svc.find(a)
            g = "video (SVC)" if any(h in r for h in VIDEO_HINT) else "other services (SVC)"
            host[g] += n
            rout["SVC  " + r] += n
            oth_k[k] += n
        elif bank in (0x06, 0x07) and jl:
            if a >= jl["jt_cache"]:
                host["translated code (JIT)"] += n
                rout["JIT  translated code"] += n
            elif bank == 0x07:
                host["the dispatcher and the translated code's routines (JIT)"] += n
                rout["JIT  " + jitl.find(a)] += n
            else:
                host["the translator (JIT)"] += n
                rout["JIT  " + jitl.find(a)] += n
            oth_k[k] += n
        else:
            g = "firmware and interrupts (banks $00, $E0/$E1, $FE/$FF)" if bank in (0, 0xE0, 0xE1, 0xFE, 0xFF) \
                else "bank $%02X" % bank
            host[g] += n
            rout["%02X:%04X" % (bank, a & 0xFF00)] += n
            oth_k[k] += n
    P("## Where the time goes")
    for g, n in host.most_common():
        P("  %5.1f%%  %s" % (100.0 * n / N, g))
    P("  the routines:")
    for r, n in rout.most_common(18):
        P("    %5.1f%%  %s" % (100.0 * n / N, r))
    cpu_n = sum(cpu_k.values())
    m["cpu_k"], m["cnt"], m["cyc1"], m["slot_n"] = cpu_k, cnt, cyc, host["the slot (CORE)"]
    m["interp"] = 100.0 * cpu_n / N
    m["video"] = 100.0 * host["video (SVC)"] / N
    m["slot"] = 100.0 * host["the slot (CORE)"] / N
    m["jitc"] = 100.0 * host["translated code (JIT)"] / N
    m["jitr"] = 100.0 * host["the dispatcher and the translated code's routines (JIT)"] / N
    m["jitt"] = 100.0 * host["the translator (JIT)"] / N
    m["top"] = [r for r, n in rout.most_common(3)]
    P()

    # --- 2. the instructions: merge a prefix with what it prefixes
    alias = {}
    for k in sorted(cnt):
        p = k - 1
        if (k & 0xFFFF) and p in cnt and mem[lin(p)] in (0x26, 0x2E, 0x36, 0x3E, 0xF2, 0xF3, 0xF0) \
                and edge.get((p, k), 0) == cnt[k]:
            alias[k] = alias.get(p, p)
    ins = {}
    icnt = Counter()
    for k, n in cnt.items():
        if k in alias:
            continue
        ins[k] = x86dec.decode(mem, lin(k))
        icnt[k] = n
    itime = Counter()
    for k, n in cpu_k.items():
        itime[alias.get(k, k)] += n
    isvc = Counter()
    for k, n in oth_k.items():
        isvc[alias.get(k, k)] += n
    edges = Counter()
    for (p, k), n in edge.items():
        p, k = alias.get(p, p), alias.get(k, k)
        if p != k or (p, k) not in ():
            if p == k and (p in alias.values()) and edge.get((p, k), 0) == 0:
                continue
            edges[(p, k)] += n
    # an edge from a prefix to its own instruction is no edge
    for k, p in alias.items():
        pass
    total_i = sum(icnt.values())

    def falls(p, k):
        i = ins.get(p)
        return i is not None and (k >> 16) == (p >> 16) and (k & 0xFFFF) == ((p & 0xFFFF) + i.length) & 0xFFFF

    # --- 3. blocks
    leader = set()
    for (p, k), n in edges.items():
        if p not in ins or k not in ins:
            continue
        if not falls(p, k) or ins[p].kind not in ("seq", "shift", "stack", "muldiv", "flagio", "sreg", "io", "str"):
            leader.add(k)
    blocks = {}                            # leader -> [keys]
    owner = {}
    for k in sorted(ins):
        if k in owner:
            continue
        if k not in leader and any(falls(p, k) for p in (k - j for j in range(1, 8)) if p in ins and p in owner
                                   and blocks[owner[p]][-1] == p
                                   and ins[p].kind in ("seq", "shift", "stack", "muldiv", "flagio", "sreg", "io", "str")):
            p = next(p for p in (k - j for j in range(1, 8)) if p in ins and p in owner and falls(p, k)
                     and blocks[owner[p]][-1] == p)
            blocks[owner[p]].append(k)
            owner[k] = owner[p]
        else:
            blocks[k] = [k]
            owner[k] = k
    bcount = {b: icnt[b] for b in blocks}
    btime = {b: sum(itime[k] for k in ks) for b, ks in blocks.items()}
    execs = sum(bcount.values())
    P("## The code")
    P("%d instructions executed in %d blocks (%d distinct blocks): %.2f instructions a block."
      % (total_i, execs, len(blocks), total_i / max(execs, 1)))
    P("Interpreter time: %.1f%% of the samples; %.0f cycles a guest instruction on average."
      % (100.0 * cpu_n / N, cpu_n * cyc / max(total_i, 1)))
    ranked = sorted(blocks, key=lambda b: -btime[b])
    m["ips"], m["cyc"], m["blen"] = d["nf"] / (frames / 60.0), cpu_n * cyc / max(total_i, 1), total_i / max(execs, 1)
    m["b64"] = 100.0 * sum(btime[b] for b in ranked[:64]) / max(cpu_n, 1)
    for top in (32, 64, 256):
        t = sum(btime[b] for b in ranked[:top])
        P("  the %3d hottest blocks: %5.1f%% of the interpreter's time, %5.1f%% of all time"
          % (top, 100.0 * t / max(cpu_n, 1), 100.0 * t / N))
    P()

    # --- 4. the mix, by count and by time
    kinds_c, kinds_t = Counter(), Counter()
    forms = Counter()
    tiers_c, tiers_t = Counter(), Counter()
    seg_over = prefixed = memops = 0
    for k, i in ins.items():
        n, t = icnt[k], itime[k]
        kk = i.kind
        if kk in ("seq", "shift"):
            kk = "ALU/MOV, memory operand" if (i.mem and i.op != 0x8D) else "ALU/MOV, registers"
        elif kk == "str":
            kk = "string, REP" if i.rep else "string, single"
        kinds_c[kk] += n
        kinds_t[kk] += t
        tr = tier(i)
        tiers_c[tr] += n
        tiers_t[tr] += t
        if i.mem and i.op != 0x8D:
            memops += n
            forms[i.memform + (" (override)" if i.seg else "")] += n
        if i.seg:
            seg_over += n
        if i.prefixes:
            prefixed += n
    P("## What it executes")
    P("  %-28s %7s %7s %9s" % ("kind", "count", "time", "cycles"))
    for kk, n in kinds_c.most_common():
        P("  %-28s %6.1f%% %6.1f%% %9.0f" % (kk, 100.0 * n / total_i, 100.0 * kinds_t[kk] / max(cpu_n, 1),
                                           kinds_t[kk] * cyc / max(n, 1)))
    P("  memory operands: %.1f%% of instructions; with a segment override %.1f%%; any prefix %.1f%%"
      % (100.0 * memops / total_i, 100.0 * seg_over / total_i, 100.0 * prefixed / total_i))
    P("  their forms: " + ", ".join("%s %.0f%%" % (f, 100.0 * n / max(memops, 1)) for f, n in forms.most_common(8)))
    names = ["tier 0: jit2.s today", "tier 1: + register forms, direct jumps", "tier 2: + memory, stack, near calls",
             "left to the interpreter"]
    io_t = sum(itime[k] + isvc[k] for k, i in ins.items() if i.kind in ("io", "int"))
    P("  IN, OUT and INT instructions with the services they call: %.1f%% of all time" % (100.0 * io_t / N))
    P("  by what a translator would have to cover:")
    for tr in range(4):
        P("    %-40s %5.1f%% of instructions, %5.1f%% of interpreter time"
          % (names[tr], 100.0 * tiers_c[tr] / total_i, 100.0 * tiers_t[tr] / max(cpu_n, 1)))
    left = Counter()
    for k, i in ins.items():
        if tier(i) == 3:
            left[("REP string" if i.kind == "str" else {"sreg": "segment load", "flagio": "PUSHF/POPF/CLI/STI",
                  "io": "IN/OUT", "int": "INT", "iret": "IRET", "retf": "far return", "callf": "far call",
                  "jmpf": "far jump", "hlt": "HLT"}.get(i.kind, i.kind))] += itime[k]
    P("    what is left, of interpreter time: " + ", ".join("%s %.1f%%" % (n_, 100.0 * t / max(cpu_n, 1))
                                                           for n_, t in left.most_common(8)))
    P()

    # --- 4b. the templates: an opcode with its form is one
    GROUPS = (0x80, 0x81, 0x82, 0x83, 0xD0, 0xD1, 0xD2, 0xD3, 0xF6, 0xF7, 0xFE, 0xFF)
    tmpl_t, tmpl_c, tmpl_tier = Counter(), Counter(), {}
    for k, i in ins.items():
        name_ = "%02X" % i.op
        if i.op in GROUPS:
            name_ += "/%d" % ((i.modrm >> 3) & 7)
        if i.modrm is not None:
            name_ += " mem" if i.mem else " reg"
        if i.rep:
            name_ = "REP " + name_
        tmpl_t[name_] += itime[k]
        tmpl_c[name_] += icnt[k]
        tmpl_tier[name_] = tier(i)
    P("## The opcodes, as a translator's templates (an opcode with its register or memory form is one)")
    acc = 0
    marks = m["marks"] = {}
    for j, (nm, t) in enumerate(tmpl_t.most_common(), 1):
        acc += t
        for pc in (50, 80, 90, 95, 99):
            if pc not in marks and acc >= pc / 100.0 * cpu_n:
                marks[pc] = j
    P("  %d distinct; the interpreter's time is covered to %s" % (len(tmpl_t), ", ".join(
        "%d%% by %d" % (pc, marks[pc]) for pc in sorted(marks))))
    P("  the first 30 (opcode, share of interpreter time, tier): " + ", ".join(
        "%s %.1f%% t%d" % (nm, 100.0 * t / max(cpu_n, 1), tmpl_tier[nm]) for nm, t in tmpl_t.most_common(30)))
    P()

    # --- 5. flags
    need = Counter()
    dead = live = out_ = 0
    for b, ks in blocks.items():
        n = bcount[b]
        for j, k in enumerate(ks):
            i = ins[k]
            if i.uses and i.kind in ("jcc", "loop", "seq", "shift", "flagio", "int"):
                src = "another block"
                for q in reversed(ks[:j]):
                    if ins[q].sets & i.uses:
                        src = "the instruction before" if q == ks[j - 1] else "earlier in the block"
                        break
                need[src] += icnt[k]
            if i.sets and i.kind in ("seq", "shift", "muldiv"):
                fate = "out"
                left = set(i.sets)
                for q in ks[j + 1:]:
                    if ins[q].uses & left:
                        fate = "live"
                        break
                    left -= ins[q].sets
                    if not left:
                        fate = "dead"
                        break
                if fate == "dead":
                    dead += icnt[k]
                elif fate == "live":
                    live += icnt[k]
                else:
                    out_ += icnt[k]
    tot = sum(need.values())
    m["flagprev"] = 100.0 * need["the instruction before"] / max(tot, 1)
    P("## Flags")
    P("  a flag read (Jcc, ADC, ...) finds its producer in: " +
      ", ".join("%s %.0f%%" % (s, 100.0 * n / max(tot, 1)) for s, n in need.most_common()))
    tf = dead + live + out_
    P("  a flag-setting instruction's flags are: read in its block %.0f%%, overwritten unread in its block %.0f%%, "
      "still there at the block's end %.0f%%" % (100.0 * live / max(tf, 1), 100.0 * dead / max(tf, 1),
                                                100.0 * out_ / max(tf, 1)))
    P()

    # --- 6. segments, interrupts, calls to the BIOS and DOS
    sload = sum(icnt[k] for k, i in ins.items() if i.kind == "sreg")
    far = sum(icnt[k] for k, i in ins.items() if i.kind in ("jmpf", "callf", "retf", "iret", "int"))
    css = Counter()
    for b in ranked[:256]:
        css[b >> 16] += btime[b]
    bylin = defaultdict(set)
    for k in ins:
        bylin[lin(k)].add(k >> 16)
    al = sum(1 for v in bylin.values() if len(v) > 1)
    P("## Segments")
    P("  segment register loads: %.2f a thousand instructions; far transfers and INT/IRET: %.2f"
      % (1000.0 * sload / total_i, 1000.0 * far / total_i))
    P("  the 256 hottest blocks run under %d values of CS: %s" %
      (len(css), ", ".join("%04X %.0f%%" % (c, 100.0 * n / max(cpu_n, 1)) for c, n in css.most_common(6))))
    P("  linear addresses executed under two values of CS: %d of %d" % (al, len(bylin)))
    ints = Counter()
    for k, i in ins.items():
        if i.kind == "int" and i.op == 0xCD:
            ints[mem[(lin(k) + i.length - 1) & 0xFFFFF]] += icnt[k]
    ivt = {}
    for v in range(256):
        o = mem[v * 4] | mem[v * 4 + 1] << 8
        s = mem[v * 4 + 2] | mem[v * 4 + 3] << 8
        ivt[(s << 16) | o] = v
    hw = Counter()
    for (p, k), n in edges.items():
        if k in ivt and ivt[k] in (8, 9, 0x0B, 0x0C, 0x0E, 0x1C) and not (p in ins and ins[p].kind == "int"):
            hw[ivt[k]] += n
    secs = frames / 60.0
    P("  INT instructions a second: " + (", ".join("%02Xh %.0f" % (v, n / secs) for v, n in ints.most_common(8)) or "none"))
    P("  hardware interrupts taken a second: " + (", ".join("%02Xh %.1f" % (v, n / secs) for v, n in hw.most_common()) or "none seen"))
    hlt = sum(icnt[k] for k, i in ins.items() if i.kind == "hlt")
    P("  HLT executed %d times" % hlt)
    P()

    # --- 7. self-modifying code
    if d["smc"]:
        cover = {}
        for k, i in ins.items():
            for j in range(i.length):
                cover[(lin(k) + j) & 0xFFFFF] = k
        hit = {a: n for a, n in d["wr"].items() if a in cover}
        pages_x = len({lin(k) >> 8 for k in ins})
        pages_w = len({a >> 8 for a in d["wr"]})
        P("## Writes into code")
        P("  %d guest writes to conventional memory in the window (%.0f a second); executed code lies in %d pages "
          "of 256 bytes, %d of them written to" % (d["nw"], d["nw"] / secs, pages_x, pages_w))
        P("  writes into pages that hold executed code: %d (%.0f a second, %.2f%% of all writes)"
          % (sum(d["wr"].values()), sum(d["wr"].values()) / secs, 100.0 * sum(d["wr"].values()) / max(d["nw"], 1)))
        P("  writes onto the bytes of an executed instruction: %d, at %d addresses" % (sum(hit.values()), len(hit)))
        byins = Counter()
        for a, n in hit.items():
            byins[cover[a]] += n
        for k, n in byins.most_common(6):
            P("    %s  %d writes, executed %d times, %.2f%% of interpreter time"
              % (fmt(k), n, icnt[k], 100.0 * itime[k] / max(cpu_n, 1)))
        P()

    # --- 8. loops: strongly connected components of the hot blocks over direct edges
    hot = set(ranked[:args.top])
    succ = defaultdict(Counter)
    for (p, k), n in edges.items():
        if p in owner and k in owner and k in blocks:
            bp = owner[p]
            if blocks[bp][-1] == p:
                succ[bp][k] += n
    def direct(bp, k):
        i = ins[blocks[bp][-1]]
        return i.kind in ("jcc", "jmp", "loop", "seq", "shift", "stack", "muldiv", "flagio", "sreg", "io", "str")
    # Tarjan, iterative
    index, low, onst, st, comps = {}, {}, set(), [], []
    counter = [0]
    for root in hot:
        if root in index:
            continue
        work = [(root, iter([k for k in succ[root] if k in hot and direct(root, k)]))]
        index[root] = low[root] = counter[0]
        counter[0] += 1
        st.append(root)
        onst.add(root)
        while work:
            v, it = work[-1]
            adv = False
            for wv in it:
                if wv not in index:
                    index[wv] = low[wv] = counter[0]
                    counter[0] += 1
                    st.append(wv)
                    onst.add(wv)
                    work.append((wv, iter([k for k in succ[wv] if k in hot and direct(wv, k)])))
                    adv = True
                    break
                elif wv in onst:
                    low[v] = min(low[v], index[wv])
            if adv:
                continue
            work.pop()
            if work:
                low[work[-1][0]] = min(low[work[-1][0]], low[v])
            if low[v] == index[v]:
                comp = []
                while True:
                    x = st.pop()
                    onst.discard(x)
                    comp.append(x)
                    if x == v:
                        break
                comps.append(comp)
    loops = []
    for comp in comps:
        cs_ = set(comp)
        if len(comp) == 1 and comp[0] not in succ[comp[0]]:
            continue
        t = sum(btime[b] for b in comp)
        inner = sum(n for b in comp for k, n in succ[b].items() if k in cs_)
        entries = sum(n for (p, k), n in edges.items() if k in cs_ and owner.get(p) not in cs_)
        ni = sum(icnt[k] for b in comp for k in blocks[b])
        tr = Counter()
        for b in comp:
            for k in blocks[b]:
                tr[tier(ins[k])] += itime[k]
        loops.append((t, comp, inner, entries, ni, tr))
    loops.sort(key=lambda x: -x[0])
    lt = sum(x[0] for x in loops)
    P("## Loops")
    P("Among the %d hottest blocks, joined by direct jumps and fall-throughs only (a call or a return ends a loop "
      "here): %d loops, %.1f%% of the interpreter's time." % (len(hot), len(loops), 100.0 * lt / max(cpu_n, 1)))
    P("  %-10s %6s %6s %9s %8s %7s  %s" % ("entry", "time", "blocks", "instr", "entries", "trips", "tiers 0/1/2/3 of its time"))
    for t, comp, inner, entries, ni, tr in loops[:14]:
        e = min(comp, key=lambda b: -sum(n for (p, k), n in edges.items() if k == b and owner.get(p) not in set(comp)))
        P("  %-10s %5.1f%% %6d %9d %8d %7.0f  %s" % (fmt(e), 100.0 * t / max(cpu_n, 1), len(comp), ni, entries,
                                                    inner / max(entries, 1),
                                                    "/".join("%.0f" % (100.0 * tr[x] / max(t, 1)) for x in range(4))))
    P()

    # --- 9. a model of what a translator would give
    P("## What a translator could give (a model, not a measurement)")
    P("An instruction is translated when its tier is covered and its block ran 50 times in the window. It is then "
      "charged the native cycles of its kind instead of the interpreter's measured time. Every time execution "
      "passes between a translated instruction and one that is not costs X cycles. Everything else is unchanged.")
    all_cpu = cpu_n * cyc
    for tr_max in (1, 2):
        ok = {k for b, ks in blocks.items() if bcount[b] >= 50 for k in ks if tier(ins[k]) <= tr_max}
        t_old = sum(itime[k] for k in ok) * cyc
        t_new = sum(icnt[k] * native_cost(ins[k]) for k in ok)
        cross = sum(n for (p, k), n in edges.items() if (p in ok) != (k in ok))
        cov = sum(icnt[k] for k in ok)
        P("  tier %d: %5.1f%% of instructions, %5.1f%% of interpreter time translated, at %.0f native cycles an "
          "instruction against %.0f; %d crossings a second" % (
              tr_max, 100.0 * cov / total_i, 100.0 * t_old / max(all_cpu, 1), t_new / max(cov, 1),
              t_old / max(cov, 1), cross / secs))
        m["cov%d" % tr_max] = 100.0 * t_old / max(all_cpu, 1)
        for X in (60, 150):
            new_cpu = all_cpu - t_old + t_new + cross * X
            m["cpu%d_%d" % (tr_max, X)] = all_cpu / new_cpu
            m["all%d_%d" % (tr_max, X)] = N * cyc / (N * cyc - all_cpu + new_cpu)
            P("      X=%3d: the interpreter's share %.2fx faster, all of the time %.2fx"
              % (X, all_cpu / new_cpu, N * cyc / (N * cyc - all_cpu + new_cpu)))
    P()

    # --- 10. the hottest blocks
    P("## The hottest blocks")
    P("  %-10s %6s %9s %5s %5s  %s" % ("block", "time", "runs", "instr", "tier", "first instructions"))
    binf = os.path.join(WORK, "dis.bin")
    for b in ranked[:args.blocks]:
        ks = blocks[b]
        ln = sum(ins[k].length for k in ks)
        open(binf, "wb").write(bytes(mem[(lin(b) + j) & 0xFFFFF] for j in range(ln)))
        txt = subprocess.run(["ndisasm", "-b16", "-o", str(b & 0xFFFF), binf], capture_output=True, text=True).stdout
        dis = [" ".join(l.split()[2:]) for l in txt.splitlines()]
        P("  %-10s %5.1f%% %9d %5d %5d  %s" % (fmt(b), 100.0 * btime[b] / max(cpu_n, 1), bcount[b], len(ks),
                                              max(tier(ins[k]) for k in ks), "; ".join(dis[:7]) + (" ..." if len(dis) > 7 else "")))
    if os.path.exists(binf):
        os.remove(binf)
    text = "\n".join(out)
    open(os.path.join(WORK, name + ".txt"), "w").write(text + "\n")
    if not quiet:
        print(text)


def compare(args):
    """Each workload collected in build/jitprof/ against the same one in build/jitprof/base/."""
    global WORK
    here, base = WORK, os.path.join(WORK, "base")
    if args.jit:
        return compare_jit(args)
    print("%-14s %9s %9s %7s %7s   %s" % ("workload", "base IPS", "IPS", "x", "same x", "interpreter / video / slot, base -> now"))
    for n in WORKLOADS:
        if not (os.path.exists(os.path.join(here, n + ".pkl")) and os.path.exists(os.path.join(base, n + ".pkl"))):
            continue
        WORK = base
        report(n, args, quiet=True)
        b = dict(METRICS[n])
        WORK = here
        report(n, args, quiet=True)
        m = METRICS[n]
        # the same instructions' cost, the slot's share of an instruction with it: every CS:IP run 200
        # times in both, weighted by the base's counts (so the mix is the base's whatever the new one did)
        tb = tn = wsum = 0.0
        for k, cb in b["cnt"].items():
            cn = m["cnt"].get(k, 0)
            if cb >= 200 and cn >= 200:
                tb += b["cpu_k"].get(k, 0) * b["cyc1"]
                tn += m["cpu_k"].get(k, 0) * m["cyc1"] * cb / cn
                wsum += cb
        tb += wsum * b["slot_n"] * b["cyc1"] / sum(b["cnt"].values())
        tn += wsum * m["slot_n"] * m["cyc1"] / sum(m["cnt"].values())
        print("%-14s %9.0f %9.0f %6.3fx %6.3fx   %4.1f%% -> %4.1f%%   %4.1f%% -> %4.1f%%   %3.1f%% -> %3.1f%%   (%.0f%% of the base's instructions compared: %.0f -> %.0f cycles each)" % (
            n, b["ips"], m["ips"], m["ips"] / b["ips"], tb / tn if tn else 0, b["interp"], m["interp"], b["video"], m["video"],
            b["slot"], m["slot"], 100.0 * wsum / sum(b["cnt"].values()), tb / max(wsum, 1), tn / max(wsum, 1)))


def compare_jit(args):
    """Each workload collected with the translator (build/jitprof/jit/) against the same one without."""
    global WORK
    here, new = WORK, os.path.join(WORK, "jit")
    print("%-14s %8s %8s %6s  %8s %8s %6s   %s" % ("workload", "writes/s", "with JIT", "x", "far/s", "with JIT", "x",
                                                   "with it: interpreter / translated code / its routines / translator / video"))
    for n in WORKLOADS:
        if not (os.path.exists(os.path.join(here, n + ".pkl")) and os.path.exists(os.path.join(new, n + ".pkl"))):
            continue
        WORK = here
        report(n, args, quiet=True)
        b = dict(METRICS[n])
        WORK = new
        report(n, args, quiet=True)
        m = METRICS[n]
        WORK = here
        print("%-14s %8.0f %8.0f %5.2fx  %8.0f %8.0f %5.2fx   %4.1f%% (was %4.1f%%) / %4.1f%% / %4.1f%% / %4.1f%% / %4.1f%% (was %4.1f%%)" % (
            n, b["writes"], m["writes"], m["writes"] / max(b["writes"], 1), b["far"], m["far"], m["far"] / max(b["far"], 1),
            m["interp"], b["interp"], m["jitc"], m["jitr"], m["jitt"], m["video"], b["video"]))


def summary(args):
    names = [n for n in WORKLOADS if os.path.exists(os.path.join(WORK, n + ".pkl"))]
    print("%-14s %6s %6s %5s %7s %5s %6s %6s %5s  %-11s %-11s %-11s" % (
        "workload", "interp", "video", "slot", "IPS", "cyc", "64blk", "tier2", "t95", "interp x", "all x", "tier1 all x"))
    for n in names:
        report(n, args, quiet=True)
        m = METRICS[n]
        print("%-14s %5.1f%% %5.1f%% %4.1f%% %7.0f %5.0f %5.1f%% %5.1f%% %5d  %-11s %-11s %-11s" % (
            n, m["interp"], m["video"], m["slot"], m["ips"], m["cyc"], m["b64"], m["cov2"], m["marks"].get(95, 0),
            "%.2f-%.2f" % (m["cpu2_150"], m["cpu2_60"]), "%.2f-%.2f" % (m["all2_150"], m["all2_60"]),
            "%.2f-%.2f" % (m["all1_150"], m["all1_60"])))
    print("interp/video/slot: share of all time; IPS: guest instructions a second; cyc: the interpreter's cycles an "
          "instruction; 64blk: the 64 hottest blocks' share of the interpreter's time; tier2: the share of it a "
          "tier-2 translator would take; t95: opcode templates for 95% of it; x: the model's speed-up of the "
          "interpreter's share and of all the time with a tier-2 translator, crossings at 150 and at 60 cycles; "
          "the last column the same for all the time with register forms only.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["list", "collect", "report", "look", "summary", "compare", "count"])
    ap.add_argument("name", nargs="?")
    ap.add_argument("frames", nargs="*", type=int)
    ap.add_argument("--from", dest="frm", type=int)
    ap.add_argument("--to", type=int)
    ap.add_argument("--no-smc", action="store_true")
    ap.add_argument("--stock", action="store_true")
    ap.add_argument("--jit", action="store_true",
                    help="collect: with the translator (JIT on the volume, JIT=ON), kept in build/jitprof/jit/; "
                         "report: that one; compare: those against the ones without")
    ap.add_argument("--as", dest="save_as", help="collect: keep the profile under this name")
    ap.add_argument("--top", type=int, default=256)
    ap.add_argument("--blocks", type=int, default=24)
    args = ap.parse_args()
    load_workloads()
    if args.cmd == "list":
        for n, w in WORKLOADS.items():
            print("%-16s %s (%s, frames %d-%d)" % (n, w["what"], w["image"], *w["window"]))
        return
    if args.cmd == "report":
        global WORK
        if args.jit:
            WORK = os.path.join(WORK, "jit")
        return report(args.name, args)
    if args.cmd == "summary":
        return summary(args)
    if args.cmd == "compare":
        return compare(args)
    w = WORKLOADS[args.name]
    if args.cmd == "count":
        return count(args.name, w, args)
    if args.cmd == "look":
        if not args.frames:
            sys.exit("look NAME FRAME...")
    else:
        args.frames = None
    collect(args.name, w, args)


if __name__ == "__main__":
    main()
