#!/usr/bin/env python3
"""state_test.py [--show] [--only STEP,...]: the boot state (make test-state; docs/state.md).

FreeDOS boots from a copy of the folder third_party/freedos/fd/SHARED whose
AUTOEXEC.BAT runs MARK.COM, with STATE=ON in XTGS.CMD. The steps, a boot of
MAME each (work files in build/state/; about ten boots):

  make     a cold boot (no state yet), then Control-Apple-Esc, XTGS Control,
           "6 Save to start from": XTGS.STATE must be on the volume, and
           sound by this tool's own reading of it (header, regions, sums)
  load     the volume started again with the PC stopped as soon as the state
           is in its places (the harness pokes BS_CFG to 2 for that): the
           guest's megabyte, the direct page, the results bank, the SHR and
           the XMS memory must be the file's, but for the fields a start
           makes anew (EXPECTED below names each)
  go       started again and left to run: MARK, a file written and typed,
           DIR; the text screen must be the one a cold boot gives for the
           same keys, the file must be on the ProDOS volume, and the SHR
           must show the text
  cold     that cold boot (the same volume, XTGS.CMD without the line STATE=ON)
  quit     (the last: it makes its own volume) "6" and then the accessory's
           Quit without leaving the desk accessories between: the state is
           written before XT/GS quits, and the next start is from it
  again    from the state: MARK, the desk accessory's soft reboot, which
           starts from the state again, MARK; then its Quit
  hard     from the state, the accessory's hard reboot: FreeDOS boots (the
           way to a boot with a good state on the disk)
  files    the state held to the files the PC was started from (M7.3):
           AUTOEXEC.BAT replaced, changed in place with its length and date
           kept, KERNEL.SYS with another date, MARK.COM gone: a boot each
           time; a new file of no concern to the boot: the state, and the
           PC reads the file; and a PC that has changed AUTOEXEC.BAT is
           not saved, one that has made a file of its own is
  day      the days since the state was written (M7.4): its day is the
           host's; DATE and TIME after it are the host's; a state made 40
           and 250 days old in its header gives DOS's date that many days
           on; one 251 days old, or of tomorrow, is not used
  ega      not a prompt: a state taken while EGADEMO shows mode 0Dh; started
           from it the SHR must be the planes' picture, the palette must go
           on turning (the clock's interrupt), and a key must end the
           program at the prompt
  disk     a PC booted from a diskette image (command D): no state is looked
           for, and the sixth choice writes none
  bad      the state cut short, a byte longer, a byte of its data, its map,
           its sums or its header changed, another build's, and XTGS.CMD
           changed: a cold boot each time, with BS_BOOT saying why (a byte
           of the data is found as the state is loaded, and the PC is begun
           again from nothing: 7)
  time     how long a cold boot takes to the prompt and how long the state
           takes, at stock speed and with a 16 MHz ZipGS

Run it under XTGS_LAYOUT=alt, XTGS_FRONT=s16, XTGS_JIT=1 and XTGS_FPU=1 by hand.
"""
import os
import shutil
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "mame"))
import mamerun  # noqa: E402
import symbols  # noqa: E402

FD = os.path.join(ROOT, "third_party", "freedos", "fd", "SHARED")
WORK = os.path.join(ROOT, "build", "state")
PO = os.path.join(WORK, "state.po")
CADIUS = os.path.join(HERE, "cadius_strict.sh")
K1, K2, K3 = ":macadb:KEY1", ":macadb:KEY2", ":macadb:KEY3"
S16 = os.environ.get("XTGS_FRONT") == "s16"
DOWNS = int(os.environ.get("CONTROL_DOWNS", "5" if S16 else "2"))
QUIT = int(os.environ.get("CONTROL_QUIT", "2" if S16 else "1"))
RES = 0x050000
BS_CFG, BS_STAT, BS_BOOT = RES + 0x8B8, RES + 0x8BA, RES + 0x8BC
MARKW = 0x2F8000
TICKS = 0x20046C                                            # 0040:006C
CRTC_START, EGA_AC = RES + 0x88C, RES + 0x970               # src/include/pc.s: CRTC_REG+12, EGA_AC
VOLDIR = "/XTGS/XTGS" if S16 else "/XTGS"
WHY = {0: "a boot (the state not asked for)", 1: "from the boot state", 2: "no file", 3: "another PC's",
       4: "damaged", 5: "no memory", 6: "its data damaged: the PC to be begun again",
       7: "a boot, the data having been found damaged as it was loaded",
       8: "a boot: the files the PC was started from are not as they were",
       9: "a boot: the state is of a later day than the clock's, or too old",
       10: "a boot: asked for (the hard reboot)"}
SAVED = {1: "written", 2: "not now: a file or a port open", 3: "no memory", 4: "the disk", 5: "not a PC from the folder",
         6: "the PC has changed a file it was started from", 7: "too many files opened"}
KIND = {1: "not there", 2: "a file", 3: "a directory"}
PIECE = 32                                                  # pages of data a sum (state.s: BS_CH)
REGIONS = ["direct page", "results bank", "SHR", "guest", "XMS", "CORE", "SVC"]
# What a start makes anew, by region: (from, to) offsets that may differ from the file.
EXPECTED = {
    "direct page": [(0xFE, 0x100,   "vTICK: the IRQ0s owed, none at a start"),
                    (0xB6, 0xB8,    "vPCMODE: cleared as the run ends")],
    "guest":       [(0x46C, 0x471,  "the BIOS's tick count and its midnight flag: the time it is now")],
    "results bank": [(0x8A8, 0x8AC, "CLK_PAID, CLK_MADE: the clock's accounts, begun again"),
                     (0x8B8, 0x8BE, "BS_CFG, BS_STAT, BS_BOOT: this start's own"),
                     (0x954, 0x958, "CTL_REQ, CTL_LIVE: no request, and no PC once the run has ended"),
                     (0xA80, 0xA82, "CTL_STAT: no state in memory"),
                     (0x878, 0x87C, "DOC_IRQS, DOC_DROPS: the sound's counts since it was opened"),
                     (0x9D6, 0x9DA, "DOC_SUM, DOC_LOGN: the log of the DOC's registers"),
                     (0xB00, 0xC00, "DOC_REG: the registers as written again"),
                     (0xE000, 0x10000, "DOC_LOG")],
}


if os.environ.get("XTGS_JIT"):
    EXPECTED["direct page"].append((0xC8, 0xE0, "the translator's own (jG, jEP...): it begins again, with no code"))


def tap(at, name, port=K3, hold=8):
    return [{"at": at, "press": name, "port": port, "value": 1},
            {"at": at + hold, "press": name, "port": port, "value": 0}]


def menu(t, digit):
    """Control-Apple-Esc at frame t, the accessory, its choice, and out again."""
    seq = tap(t, "Control", hold=40) + tap(t + 2, "Command / Open Apple", hold=36) + tap(t + 10, "Esc", hold=20)
    t += 200
    for _ in range(DOWNS):
        seq += tap(t, "Down Arrow")
        t += 40
    seq += tap(t, "Return", K2)
    seq += tap(t + 80, digit, K1)
    seq += tap(t + 140, "Space")
    t += 200
    if digit.startswith("6"):                               # (the accessory stays up, to say that the state waits
        seq += tap(t, "Esc")                                # to be written, or why it cannot be: out of it)
        t += 60
    for _ in range(QUIT):
        seq += tap(t, "Down Arrow")
        t += 40
    seq += tap(t, "Return", K2)
    return seq, t


def cadius(*args, check=True):
    r = subprocess.run([CADIUS] + list(args), capture_output=True, text=True)
    if check and r.returncode:
        sys.exit("state_test: cadius %s failed:\n%s" % (" ".join(args[:1]), r.stdout + r.stderr))
    return r


def config():
    """What the volume in build/state/ was built for: the front end, the layout, the translator."""
    return "|".join(os.environ.get(k, "") for k in ("XTGS_FRONT", "XTGS_LAYOUT", "XTGS_JIT", "XTGS_FPU"))


def build(cmd_lines=("S", "C=SHARED", "STATE=ON")):
    os.makedirs(WORK, exist_ok=True)
    open(os.path.join(WORK, "config"), "w").write(config())
    folder = os.path.join(WORK, "SHARED")
    shutil.rmtree(folder, ignore_errors=True)
    shutil.copytree(FD, folder)
    subprocess.run(["nasm", "-f", "bin", "-o", os.path.join(folder, "MARK.COM#060000"),
                    os.path.join(ROOT, "tests", "demo", "mark.asm")], check=True)
    with open(os.path.join(folder, "AUTOEXEC.BAT#040000"), "w", newline="\r\n") as f:
        f.write("@ECHO OFF\nMARK\n")
    cmd = os.path.join(WORK, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write("".join(l + "\r" for l in cmd_lines))
    stage = os.path.join(ROOT, "build", "stage")
    subprocess.run([os.path.join(HERE, "make_image.sh"), PO, os.path.join(stage, "XTGS.SYSTEM#FF2000"),
                    os.path.join(stage, "CORE#060000"), os.path.join(stage, "SVC#060000"), cmd, folder],
                   check=True, capture_output=True, env=dict(os.environ, VOLSIZE="4096KB"))


def set_cmd(image, cmd_lines):
    cmd = os.path.join(WORK, "XTGS.CMD#040000")
    if os.environ.get("XTGS_JIT"):                          # (as tools/make_image.sh writes the file)
        cmd_lines = tuple(cmd_lines) + ("JIT=ON",)
    if os.environ.get("XTGS_FPU"):
        cmd_lines = tuple(cmd_lines) + ("FPU=8087",)
    with open(cmd, "w") as f:
        f.write(("+" if os.environ.get("XTGS_LAYOUT") == "alt" else "") + "".join(l + "\r" for l in cmd_lines))
    cadius("DELETEFILE", image, VOLDIR + "/XTGS.CMD")
    cadius("ADDFILE", image, VOLDIR + "/", cmd)


def state_of(image):
    """XTGS.STATE off the volume, or None."""
    out = os.path.join(WORK, "out")
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    r = cadius("EXTRACTFILE", image, VOLDIR + "/XTGS.STATE", out + "/", check=False)
    got = [f for f in os.listdir(out) if f.startswith("XTGS.STATE")]
    if r.returncode or not got:
        return None
    return open(os.path.join(out, got[0]), "rb").read()


def put_state(image, data):
    path = os.path.join(WORK, "XTGS.STATE#060000")
    open(path, "wb").write(data)
    cadius("DELETEFILE", image, VOLDIR + "/XTGS.STATE", check=False)
    cadius("ADDFILE", image, VOLDIR + "/", path)


def files_of(sec):
    """The records of the files the PC was started from: [(name, kind, date, time, length, sum)]."""
    out, at = [], 0
    while at < len(sec):
        n = sec[at]
        idat = at + ((n + 2) & ~1)
        if not 0 < n < 64 or idat + 12 > len(sec):
            raise ValueError("the records of the boot's files")
        kind, date, time, length, bsum = struct.unpack_from("<HHHIH", sec, idat)
        out.append((sec[at + 1:at + 1 + n].decode("ascii"), kind, date, time, length, bsum))
        at = idat + 12
    return out


def decode(f):
    """The file as this tool reads it, apart from state.s: (header fields, {region: bytes}), or a complaint."""
    if len(f) < 256 or f[:8] != b"XTGSboot":
        raise ValueError("no header")
    ver, hlen = struct.unpack_from("<HH", f, 8)
    if ver != 2 or hlen != 256:
        raise ValueError(f"version {ver}, a header of {hlen}")
    rg = [struct.unpack_from("<HHH", f, 170 + 6 * i) for i in range(7)]
    mapb, pages, tabb, msum, mfb, day = struct.unpack_from("<HHHIHH", f, 212)
    hsum = struct.unpack_from("<H", f, 254)[0]
    if sum(struct.unpack_from("<127H", f, 0)) & 0xFFFF != hsum:
        raise ValueError("the header's sum")
    mapat = 256 + mfb
    data = mapat + mapb + tabb
    if (mapb != 2 * sum(r[2] for r in rg) or tabb != 4 * ((pages + PIECE - 1) // PIECE) or mfb & 1
            or len(f) != data + 256 * pages):
        raise ValueError(f"the lengths: records of {mfb}, a map of {mapb}, sums of {tabb}, {pages} pages, {len(f)} bytes")
    if sum(struct.unpack_from("<%dH" % ((mfb + mapb + tabb) // 2), f, 256)) & 0xFFFFFFFF != msum:
        raise ValueError("the sum of the records, the map and the pieces' sums")
    for n, want in enumerate(struct.unpack_from("<%dI" % (tabb // 4), f, mapat + mapb)):
        piece = f[data + n * PIECE * 256:data + (n + 1) * PIECE * 256]
        if sum(struct.unpack_from("<%dH" % (len(piece) // 2), piece)) & 0xFFFFFFFF != want:
            raise ValueError(f"the sum of piece {n} of the data")
    words = struct.unpack_from("<%dH" % (mapb // 2), f, mapat)
    if any(w >> 8 > 1 for w in words):
        raise ValueError("a word of the map that is neither a page of data nor a page of one byte")
    at, out, w = data, {}, 0
    for name, (bank, off, n) in zip(REGIONS, rg):
        buf = bytearray()
        for _ in range(n):
            if words[w] >> 8:
                buf += bytes([words[w] & 0xFF]) * 256
            else:
                buf += f[at:at + 256]
                at += 256
            w += 1
        out[name] = bytes(buf)
    if at != len(f):
        raise ValueError("pages the map does not name")
    hdr = dict(build=struct.unpack_from("<I", f, 12)[0], layout=f[16:42], cmd=f[42:170].rstrip(b"\0"),
               regions=rg, mapb=mapb, tabb=tabb, mapat=mapat, data=data, pages=pages, day=day,
               files=files_of(f[256:mapat]), raw=sum(1 for x in words if not x >> 8))
    return hdr, out


def boot(image, seconds, inputs=(), zip=True, dumps=(), extra=None, stop=False, traces=True, more_traces=()):
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    late = mamerun.GSOS_BOOT * 60 if S16 else 0
    inputs = [dict(i, at=i["at"] + late, after="start") for i in inputs]
    base = [("fb", 0x2B8000, 4000), ("bs", BS_CFG, 8), ("mark", MARKW, 2), ("mb", syms["mb_stage"], 8),
            ("shr", 0xE12000, 0x8000)]
    # (XTGS_GARBAGE=n: the machine's memory full of leftovers when it is switched on, as it is in a session
    # that has run other things: nothing here may depend on its being zeroes)
    garbage = int(os.environ["XTGS_GARBAGE"]) if os.environ.get("XTGS_GARBAGE") else None
    r = mamerun.run(image, waits=[(syms["mb_magic"], 0x5A5A)], dumps=base + list(dumps), garbage=garbage,
                    seconds=seconds + late / 60, settle=5, inputs=inputs, zip=zip, extra=extra,
                    traces=[("boot", BS_BOOT), ("mark", MARKW), ("stat", BS_STAT)] + list(more_traces) if traces else ())
    if r["status"] == "no-output":
        print(r.get("mame_output", ""))
        sys.exit("state_test: MAME produced no result")
    fb = bytes.fromhex(r["dumps"]["fb"]["hex"])
    r["rows"] = [bytes(fb[y * 160 + x * 2] for x in range(80)).decode("cp437").rstrip("\0 ") for y in range(25)]
    bs = bytes.fromhex(r["dumps"]["bs"]["hex"])
    r["cfg"], r["stat"], r["bootw"], r["where"] = bs[0], bs[2], bs[4], bs[6]
    return r


def first(r, name, value):
    """The frame the traced word first had the value, or None."""
    for f, v in r.get("traces", {}).get(name, []):
        if v == value:
            return f
    return None


def step_make(show):
    build()
    seq, t = menu(3000, "6  ^")
    r = boot(PO, (t + 2400) / 60, seq)
    f = state_of(PO)
    bad = []
    if r["stat"] != 1:
        bad.append(f"BS_STAT is {r['stat']}, not 1 (written)")
    if r["bootw"] != 2:
        bad.append(f"the first start's BS_BOOT is {r['bootw']} ({WHY.get(r['bootw'])}), not 2 (no file)")
    if f is None:
        bad.append("XTGS.STATE is not on the volume")
    hdr = None
    if f is not None:
        try:
            hdr, _ = decode(f)
        except ValueError as e:
            bad.append(f"XTGS.STATE is not sound: {e}")
    if f is not None and len(f) > 650000:
        bad.append(f"XTGS.STATE is {len(f)} bytes: more than a PC at its prompt after a boot is (what the machine "
                   "had in memory before is in it?)")
    if show or bad:
        print("\n".join(r["rows"]))
    if bad:
        sys.exit("FAIL state (make): " + "; ".join(bad))
    open(os.path.join(WORK, "XTGS.STATE.good"), "wb").write(f)
    save = (first(r, "stat", 1) or 0)
    print(f"PASS state (make): XTGS.STATE written from the desk accessory, {len(f)} bytes: {hdr['raw']} pages of data "
          f"and {hdr['mapb'] // 2 - hdr['raw']} of one byte each ({hdr['regions'][4][2]} pages are XMS memory); "
          f"its header and its sums are sound (the save was done by frame {save}); the files it is held to: "
          + ", ".join(f"{n} ({KIND.get(k, k)}{', %d bytes' % ln if k == 2 else ''}{', summed' if k == 2 and 0 < ln <= 8192 else ''})"
                      for n, k, _d, _t, ln, _s in hdr["files"]))


LUA_ONLY = """
local XS = {}
XS.sp = manager.machine.devices[":maincpu"].spaces["program"]
"""
LUA_ONLY_TAIL = """
emu.wait(0.05)
XS.b, XS.c = at(@BOOT@), at(@CFG@)
while XS.b == nil or XS.c == nil do                         -- (the GS/OS front end: no layout yet)
    emu.wait(0.25)
    XS.b, XS.c = at(@BOOT@), at(@CFG@)
end
XS.tap = XS.sp:install_write_tap(XS.b, XS.b, "bsboot", function(o, d, m)
    if (d & 0xFF) == 1 then XS.sp:write_u16(XS.c, 2) end
end)
while true do emu.wait(1.0) end
"""


def step_load(show):
    good = open(os.path.join(WORK, "XTGS.STATE.good"), "rb").read()
    put_state(PO, good)
    hdr, want = decode(good)
    dumps = [("r_dp", 0x001000, 0x100), ("r_res", RES, 0x10000), ("r_core", 0x030000, 0x10000),
             ("r_svc", 0x040000, 0x10000)]
    dumps += [("r_g%X" % i, 0x200000 + i * 0x10000, 0x10000) for i in range(16)]
    xms = hdr["regions"][4][2] * 256
    dumps += [("r_x%X" % i, 0x500000 + i * 0x10000, min(0x10000, xms - i * 0x10000)) for i in range((xms + 0xFFFF) >> 16)]
    import layout
    act = (lambda a: a) if S16 else layout.to_actual        # (under s16 the harness's at() finds the banks)
    extra = {"top": LUA_ONLY, "tail": LUA_ONLY_TAIL.replace("@BOOT@", str(act(BS_BOOT))).replace("@CFG@", str(act(BS_CFG)))}
    r = boot(PO, 40, dumps=dumps, extra=extra, traces=False)
    d = {k: bytes.fromhex(v["hex"]) for k, v in r["dumps"].items()}
    have = {"direct page": d["r_dp"], "results bank": d["r_res"], "SHR": d["shr"], "CORE": d["r_core"], "SVC": d["r_svc"],
            "guest": b"".join(d["r_g%X" % i] for i in range(16)),
            "XMS": b"".join(d["r_x%X" % i] for i in range((xms + 0xFFFF) >> 16))}
    bad, notes = [], []
    if r["status"] != "hit" or r["bootw"] != 1:
        bad.append(f"the PC was not stopped after the state's load (status {r['status']}, BS_BOOT {r['bootw']}: "
                   f"{WHY.get(r['bootw'])}, the look at the file got to step {r['where']})")
    else:
        for name in REGIONS:
            a, b = want[name], have[name]
            if len(a) != len(b):
                bad.append(f"{name}: {len(b)} bytes dumped, {len(a)} in the file")
                continue
            diff = [i for i in range(len(a)) if a[i] != b[i]]
            if name in ("CORE", "SVC"):
                notes.append(f"{name} {len(diff)}")           # (the host's own fields: counted, not judged)
                continue
            left = [i for i in diff if not any(lo <= i < hi for lo, hi, _ in EXPECTED.get(name, []))]
            if left:
                bad.append(f"{name}: {len(left)} bytes are not the file's, the first at +{left[0]:#x} "
                           f"({b[left[0]]:#04x}, the file has {a[left[0]]:#04x})")
            notes.append(f"{name} {len(diff)}")
    if show:
        print("\n".join(r["rows"]))
    if bad:
        sys.exit("FAIL state (load): " + "; ".join(bad))
    print("PASS state (load): started from XTGS.STATE and stopped before an instruction: the guest's megabyte, the "
          "direct page, the results bank, the SHR and the XMS memory are the file's but for the fields a start makes "
          "anew (bytes that differ: " + ", ".join(notes) + ")")


KEYS = [(0, "MARK{ENTER}"), (300, "ECHO SAVED>T.TXT{ENTER}"), (600, "TYPE T.TXT{ENTER}"), (900, "MARK{ENTER}"),
        (1200, "DIR T*.*{ENTER}")]


def step_go(show, cold=False):
    import textshr
    good = open(os.path.join(WORK, "XTGS.STATE.good"), "rb").read()
    put_state(PO, good)                                     # (there both times: the volume's free space is on the screen)
    set_cmd(PO, ("S", "C=SHARED") if cold else ("S", "C=SHARED", "STATE=ON"))
    cadius("DELETEFILE", PO, VOLDIR + "/SHARED/T.TXT", check=False)
    t0 = 3000 if cold else 900
    seq = [{"at": t0 + t, "coded": k} for t, k in KEYS]
    r = boot(PO, (t0 + 2100) / 60, seq, more_traces=[("tick", TICKS)])
    want_boot = 0 if cold else 1
    bad = []
    if r["bootw"] != want_boot:
        bad.append(f"BS_BOOT is {r['bootw']} ({WHY.get(r['bootw'])}), not {want_boot}")
    cat = cadius("CATALOG", PO).stdout
    if "T.TXT" not in cat:
        bad.append("T.TXT, which the PC wrote, is not on the ProDOS volume")
    stale = textshr.mismatches(bytes.fromhex(r["dumps"]["fb"]["hex"]), bytes.fromhex(r["dumps"]["shr"]["hex"]))
    if stale:
        bad.append(f"{len(stale)} cells of the text screen are not what the SHR shows")
    since = first(r, "boot", want_boot) or 0
    ticks = [f for f, _ in r.get("traces", {}).get("tick", []) if f > since + 60]
    if len(ticks) < 100:
        bad.append(f"the BIOS's tick count changed {len(ticks)} times after the start: the timer's interrupt is not "
                   "being delivered")
    path = os.path.join(WORK, "screen.cold" if cold else "screen.go")
    open(path, "w").write("\n".join(r["rows"]) + "\n")
    if show or bad:
        print("\n".join(r["rows"]))
    name = "cold" if cold else "go"
    if bad:
        sys.exit(f"FAIL state ({name}): " + "; ".join(bad))
    if cold:
        set_cmd(PO, ("S", "C=SHARED", "STATE=ON"))
        print(f"PASS state (cold): the same keys after a cold boot (MARK's word set at frame {first(r, 'mark', 0xBEEF)})")
        return
    print(f"PASS state (go): started from XTGS.STATE (in its places by frame {first(r, 'boot', 1)}) and run: MARK, a "
          "file written and typed, DIR; the file is on the ProDOS volume, the SHR shows the text and the timer's "
          f"interrupt goes on ({len(ticks)} ticks counted)")


def step_again(show):
    """From the state: MARK, the accessory's soft reboot (which starts from the state again), MARK; then its Quit."""
    put_state(PO, open(os.path.join(WORK, "XTGS.STATE.good"), "rb").read())
    set_cmd(PO, ("S", "C=SHARED", "STATE=ON"))
    seq = [{"at": 900, "coded": "MARK{ENTER}"}]
    more, t = menu(1500, "1  !")
    seq += more + [{"at": t + 1500, "coded": "MARK{ENTER}"}]
    # The Quit only where the harness can see it: the GS/OS tests' launcher starts XT/GS again at
    # once (from the state: the screen would be the state's), and under the alt layout ProDOS's
    # quit code is loaded over the front page the harness reads the layout from.
    quit = not S16 and os.environ.get("XTGS_LAYOUT") != "alt"
    t += 2100
    if quit:
        more, t = menu(t, "5  %")
        seq += more
    r = boot(PO, (t + 900) / 60, seq)
    mb = bytes.fromhex(r["dumps"]["mb"]["hex"])
    stage_now, magic, code = mb[0], mb[2] | mb[3] << 8, mb[4] | mb[5] << 8
    marks = [x for x in r["rows"] if x.startswith("MARK=")]
    typed = [x for x in r["rows"] if x.endswith(">MARK")]
    bad = []
    if marks != ["MARK=0000", "MARK=BEEF"] or len(typed) != 1:
        bad.append(f"the screen has {marks} and {len(typed)} typed MARKs: after the reboot it should be the state's "
                   "['MARK=0000'] and the one MARK typed since, 'MARK=BEEF'")
    if r["bootw"] != 1:
        bad.append(f"BS_BOOT is {r['bootw']} ({WHY.get(r['bootw'])}): the reboot did not start from the state")
    if quit and (magic != 0x5A5A or code != 0xB0C3):
        bad.append(f"XT/GS did not quit by the accessory's request (magic {magic:#06x}, exit code {code:#06x})")
    if show or bad:
        print("\n".join(r["rows"]))
    if bad:
        sys.exit("FAIL state (again): " + "; ".join(bad))
    print("PASS state (again): from the state, MARK, the desk accessory's soft reboot, which starts from the state "
          "again, MARK"
          + ("; and its Quit leaves XT/GS as it does a PC that was booted" if quit else ""))


def step_ega(show):
    """Not a prompt: the state taken while EGADEMO shows mode 0Dh and turns its palette by the clock."""
    import egashr
    import textshr
    cadius("DELETEFILE", PO, VOLDIR + "/XTGS.STATE", check=False)
    set_cmd(PO, ("S", "C=SHARED", "STATE=ON"))
    more, t = menu(3900, "6  ^")
    r = boot(PO, (t + 2400) / 60, [{"at": 3000, "coded": "EGADEMO{ENTER}"}] + more)
    f = state_of(PO)
    if r["stat"] != 1 or f is None:
        sys.exit(f"FAIL state (ega): no state was written from inside EGADEMO (BS_STAT {r['stat']})")
    try:
        decode(f)
    except ValueError as e:
        sys.exit(f"FAIL state (ega): XTGS.STATE is not sound: {e}")
    dumps = [("pl%d" % i, 0x200000 + a, 0x10000) for i, a in enumerate(egashr.PLANES)]
    dumps += [("crtc", CRTC_START, 2), ("ac", EGA_AC, 16), ("crtcoff", CRTC_START + 7, 1), ("acpan", EGA_AC + 0x13, 1)]
    r = boot(PO, 1200 / 60, dumps=dumps, more_traces=[("ac1", EGA_AC + 1)])
    d = {k: bytes.fromhex(v["hex"]) for k, v in r["dumps"].items()}
    bad = []
    since = first(r, "boot", 1)
    if r["bootw"] != 1 or since is None:
        bad.append(f"BS_BOOT is {r['bootw']} ({WHY.get(r['bootw'])})")
    elif not egashr.is_ega(d["shr"]):
        bad.append("the screen is not in mode 0Dh (SHR 320, one palette)")
    else:
        start = d["crtc"][0] << 8 | d["crtc"][1]
        wrong = egashr.mismatches([d["pl%d" % i] for i in range(4)], start, d["shr"], (d["crtcoff"][0] or 20) * 2,
                                  d["acpan"][0] & 7)
        if wrong:
            bad.append(f"{len(wrong)} of the 8000 bytes of the screen are not the planes' (first line,byte {wrong[0]})")
        turns = [fr for fr, _ in r.get("traces", {}).get("ac1", []) if fr > since]
        if len(turns) < 3:
            bad.append(f"the palette was turned {len(turns)} times after the start: the program is not going on")
    if bad:
        sys.exit("FAIL state (ega): " + "; ".join(bad))
    r2 = boot(PO, 1500 / 60, [{"at": 700, "coded": "X"}])
    stale = textshr.mismatches(bytes.fromhex(r2["dumps"]["fb"]["hex"]), bytes.fromhex(r2["dumps"]["shr"]["hex"]))
    prompt = [x for x in r2["rows"] if x.strip()]
    if show:
        print("\n".join(r2["rows"]))
    if r2["bootw"] != 1 or not prompt or prompt[-1] != "C:\\>" or stale:
        sys.exit(f"FAIL state (ega): after a key the program should have ended at the prompt in text mode: BS_BOOT "
                 f"{r2['bootw']}, the last line {prompt[-1:]!r}, {len(stale)} cells that are not what the SHR shows")
    print(f"PASS state (ega): a state taken inside EGADEMO (mode 0Dh, {len(f)} bytes): started from it the SHR is the "
          f"four planes' picture, the program goes on turning its palette by the clock ({len(turns)} turns), and "
          "a key ends it at the prompt in text mode")


def step_disk(show):
    """A PC booted from a diskette image has written to a copy of it in memory: no state of that one."""
    img = os.path.join(ROOT, "third_party", "freedos", "fd", "freedos.img")
    disk = os.path.join(WORK, "DISK#060000")
    shutil.copyfile(img, disk)
    cmd = os.path.join(WORK, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write("D\rSTATE=ON\r")
    po = os.path.join(WORK, "disk.po")
    stage = os.path.join(ROOT, "build", "stage")
    subprocess.run([os.path.join(HERE, "make_image.sh"), po, os.path.join(stage, "XTGS.SYSTEM#FF2000"),
                    os.path.join(stage, "CORE#060000"), os.path.join(stage, "SVC#060000"), cmd, disk],
                   check=True, capture_output=True, env=dict(os.environ, VOLSIZE="4096KB"))
    seq, t = menu(4500, "6  ^")
    r = boot(po, (t + 900) / 60, seq)
    f = state_of(po)
    os.remove(po)
    os.remove(disk)
    if show:
        print("\n".join(r["rows"]))
    if r["stat"] != 5 or r["bootw"] != 2 or f is not None:
        sys.exit(f"FAIL state (disk): a PC booted from a diskette image: BS_STAT is {r['stat']} (wanted 5, not this "
                 f"PC), BS_BOOT {r['bootw']} (wanted 2), and XTGS.STATE is {'on' if f is not None else 'not on'} the volume")
    print("PASS state (disk): a PC booted from a diskette image (command D) looks for no state and is not saved as one")


def step_hard(show):
    put_state(PO, open(os.path.join(WORK, "XTGS.STATE.good"), "rb").read())
    set_cmd(PO, ("S", "C=SHARED", "STATE=ON"))
    seq, t = menu(900, "2  @")
    r = boot(PO, (t + 2400) / 60, seq)
    mb = bytes.fromhex(r["dumps"]["mb"]["hex"])
    code = mb[4] | mb[5] << 8
    marks = [x for x in r["rows"] if x.startswith("MARK=")]
    if show:
        print("\n".join(r["rows"]))
    if r["bootw"] != 10 or marks != ["MARK=0000"] or first(r, "boot", 1) is None or (not S16 and code != 0xB0C2):
        sys.exit(f"FAIL state (hard): after the hard reboot BS_BOOT is {r['bootw']} ({WHY.get(r['bootw'])}), wanted 10; "
                 f"the screen has {marks}; exit code {code:#06x}; the first start "
                 f"{'was' if first(r, 'boot', 1) is not None else 'was not'} from the state")
    print("PASS state (hard): from the state, the desk accessory's hard reboot: FreeDOS boots, though the state is there")


def patched(image, old, new):
    """The one place the image has `old`, made `new` (the same length): a file changed with its date kept."""
    data = open(image, "rb").read()
    if len(old) != len(new) or data.count(old) != 1:
        sys.exit(f"state_test: the image has {old!r} {data.count(old)} times")
    open(image, "wb").write(data.replace(old, new))


def put_file(image, name, data, when=None):
    """A file of the folder SHARED put on the volume in place of the one there (when: its date, seconds)."""
    path = os.path.join(WORK, name)
    open(path, "wb").write(data)
    if when:
        os.utime(path, (when, when))
    cadius("DELETEFILE", image, VOLDIR + "/SHARED/" + name.split("#")[0], check=False)
    cadius("ADDFILE", image, VOLDIR + "/SHARED/", path)
    os.remove(path)


def step_files(show):
    import time
    good = open(os.path.join(WORK, "XTGS.STATE.good"), "rb").read()
    folder = os.path.join(WORK, "SHARED")
    auto = open(os.path.join(folder, "AUTOEXEC.BAT#040000"), "rb").read()
    kernel = open(os.path.join(folder, "KERNEL.SYS#060000"), "rb").read()
    mark = open(os.path.join(folder, "MARK.COM#060000"), "rb").read()
    pristine = os.path.join(WORK, "pristine.po")

    def fresh():
        shutil.copyfile(pristine, PO)

    put_state(PO, good)
    set_cmd(PO, ("S", "C=SHARED", "STATE=ON"))
    shutil.copyfile(PO, pristine)
    out = []
    # The folder changed from outside, between the save and the start.
    cases = [("AUTOEXEC.BAT replaced by a longer one",
              lambda: put_file(PO, "AUTOEXEC.BAT#040000", auto + b"REM\r\n"), 8),
             ("AUTOEXEC.BAT changed in place, its length and its date kept",
              lambda: patched(PO, b"@ECHO OFF\r\nMARK\r\n", b"@ECHO OFF\r\nMARK \n"), 8),
             ("KERNEL.SYS the same bytes with another date",
              lambda: put_file(PO, "KERNEL.SYS#060000", kernel, time.time() - 3 * 86400), 8),
             ("MARK.COM gone", lambda: cadius("DELETEFILE", PO, VOLDIR + "/SHARED/MARK.COM"), 8),
             # (and the command file: the sign-on says which it was)
             ("XTGS.CMD with a line more", lambda: set_cmd(PO, ("S", "C=SHARED", "STATE=ON", "VIDEO=CGA")), 3)]
    said = {8: "Boot state not used: a file DOS boots from has changed", 3: "Boot state not used: XTGS.CMD has changed"}
    for what, change, why in cases:
        fresh()
        change()
        r = boot(PO, 3000 / 60)
        if r["bootw"] != why:
            if show:
                print("\n".join(r["rows"]))
            sys.exit(f"FAIL state (files): {what}: BS_BOOT is {r['bootw']} ({WHY.get(r['bootw'])}), wanted {why} "
                     f"({WHY[why]})")
        if said[why] not in r["rows"]:
            print("\n".join(r["rows"]))
            sys.exit(f"FAIL state (files): {what}: the sign-on does not say {said[why]!r}")
        out.append(what)
    # A file the boot never looked at, and a save that was cut off: the state, and the PC reads what is there.
    fresh()
    put_file(PO, "NEWFILE.TXT#040000", b"FROM OUTSIDE\r\n")
    open(os.path.join(WORK, "XTGS.STATE.NEW#060000"), "wb").write(good[:5000])
    cadius("ADDFILE", PO, VOLDIR + "/", os.path.join(WORK, "XTGS.STATE.NEW#060000"))
    r = boot(PO, 1500 / 60, [{"at": 900, "coded": "TYPE NEWFILE.TXT{ENTER}"}])
    if r["bootw"] != 1 or "FROM OUTSIDE" not in r["rows"]:
        if show:
            print("\n".join(r["rows"]))
        sys.exit(f"FAIL state (files): a new file the boot has nothing to do with: BS_BOOT is {r['bootw']} "
                 f"({WHY.get(r['bootw'])}), wanted 1, and TYPE should show it")
    # The PC itself: one that has changed a file it was started from is no boot state; a file of its own making is.
    fresh()
    cadius("DELETEFILE", PO, VOLDIR + "/XTGS.STATE")
    seq, t = menu(3900, "6  ^")
    r = boot(PO, (t + 900) / 60, [{"at": 3000, "coded": "ECHO REM>>AUTOEXEC.BAT{ENTER}"}] + seq)
    if r["stat"] != 6 or state_of(PO) is not None:
        sys.exit(f"FAIL state (files): a PC that has added to AUTOEXEC.BAT: BS_STAT is {r['stat']} "
                 f"({SAVED.get(r['stat'])}), wanted 6, and no XTGS.STATE")
    # (and one with a file open, which is said in the accessory as the choice is made: no state, and the old
    # one is left as it was)
    fresh()
    seq, t = menu(3900, "6  ^")
    r = boot(PO, (t + 900) / 60, [{"at": 3000, "coded": "COPY CON OPEN.TXT{ENTER}"}] + seq)
    if r["stat"] != 2 or state_of(PO) != good:
        sys.exit(f"FAIL state (files): a PC with a file open (COPY CON): BS_STAT is {r['stat']} "
                 f"({SAVED.get(r['stat'])}), wanted 2, and XTGS.STATE as it was")
    fresh()
    cadius("DELETEFILE", PO, VOLDIR + "/XTGS.STATE")
    seq, t = menu(4500, "6  ^")
    r = boot(PO, (t + 2400) / 60, [{"at": 3000, "coded": "ECHO MINE>OWN.TXT{ENTER}"},
                                   {"at": 3400, "coded": "TYPE OWN.TXT{ENTER}"},
                                   {"at": 3800, "coded": "DEL OWN.TXT{ENTER}"}] + seq)
    f = state_of(PO)
    names = [n for n, *_ in decode(f)[0]["files"]] if f else None
    if r["stat"] != 1 or f is None or "OWN.TXT" in names:
        sys.exit(f"FAIL state (files): a PC that has made, read and deleted a file of its own: BS_STAT is {r['stat']} "
                 f"({SAVED.get(r['stat'])}), wanted 1, and the state's files are {names}")
    fresh()
    os.remove(pristine)
    print("PASS state (files): a boot, and BS_BOOT and the sign-on say why, with " + "; ".join(out)
          + ". A new file of no concern to the boot (and what a cut-off save left): the state, and TYPE shows the "
          "file. A PC that has added to AUTOEXEC.BAT is not saved; one that has made, read and deleted a file of its "
          "own is, and is held to none of that; one with a file open is told so in the accessory")


def aged(f, days):
    """The state as if written `days` days ago: its header's day, and the header's sum."""
    day = (struct.unpack_from("<H", f, 224)[0] - days) & 0xFFFF
    h = bytearray(f[:256])
    struct.pack_into("<H", h, 224, day)
    struct.pack_into("<H", h, 254, sum(struct.unpack_from("<127H", h, 0)) & 0xFFFF)
    return bytes(h) + f[256:]


def step_day(show):
    import datetime
    import re
    good = open(os.path.join(WORK, "XTGS.STATE.good"), "rb").read()
    hdr, _ = decode(good)
    set_cmd(PO, ("S", "C=SHARED", "STATE=ON"))
    made = datetime.date.fromtimestamp(os.path.getmtime(os.path.join(WORK, "XTGS.STATE.good")))
    want = (made - datetime.date(1900, 1, 1)).days
    if hdr["day"] != want:
        sys.exit(f"FAIL state (day): the state's day is {hdr['day']}, and {made} is day {want} from 1900-01-01")
    keys = [{"at": 900, "coded": "DATE{ENTER}"}, {"at": 1100, "coded": "{ENTER}"},
            {"at": 1300, "coded": "TIME{ENTER}"}, {"at": 1500, "coded": "{ENTER}"}]
    out = []
    for days in (0, 40, 250):
        put_state(PO, aged(good, days))
        now = datetime.datetime.now()
        r = boot(PO, 1800 / 60, keys)
        text = "\n".join(r["rows"])
        d = re.search(r"Current date is \w+ (\d+)-(\d+)-(\d+)", text)
        t = re.search(r"Current time is\s+(\d+):(\d+):(\d+)\.\d+ ?([ap]?)", text)
        if show:
            print(text)
        if r["bootw"] != 1 or not d or not t:
            sys.exit(f"FAIL state (day): a state {days} days old: BS_BOOT {r['bootw']} ({WHY.get(r['bootw'])}), "
                     f"DATE {'answered' if d else 'did not answer'}, TIME {'answered' if t else 'did not answer'}")
        got = datetime.date(int(d.group(3)), int(d.group(1)), int(d.group(2)))
        expect = (now + datetime.timedelta(seconds=1300 / 60)).date() + datetime.timedelta(days=days)
        hour = int(t.group(1)) % 12 + (12 if t.group(4) == "p" else 0) if t.group(4) else int(t.group(1))
        secs = hour * 3600 + int(t.group(2)) * 60 + int(t.group(3))
        clock = now + datetime.timedelta(seconds=1300 / 60)     # (MAME's clock is the host's as the run starts)
        off = (secs - (clock.hour * 3600 + clock.minute * 60 + clock.second) + 43200) % 86400 - 43200
        if got != expect or abs(off) > 90:
            sys.exit(f"FAIL state (day): a state {days} days old: DOS's date is {got}, wanted {expect}; its time is "
                     f"{off:+d} s from the clock's")
        out.append(f"{days} days old: {got}")
    for days, what in ((251, "251 days old"), (-1, "of tomorrow")):
        put_state(PO, aged(good, days))
        r = boot(PO, 3000 / 60)
        if r["bootw"] != 9:
            sys.exit(f"FAIL state (day): a state {what}: BS_BOOT is {r['bootw']} ({WHY.get(r['bootw'])}), wanted 9")
    put_state(PO, good)
    print(f"PASS state (day): the state's day is the host's ({made}); DOS's date after it, " + ", ".join(out)
          + "; its time the clock's each time; a state 251 days old, or of tomorrow: a boot")


def step_same():
    a = open(os.path.join(WORK, "screen.go")).read().split("\n")
    b = open(os.path.join(WORK, "screen.cold")).read().split("\n")
    # the lines DIR prints the time of the file's making on are the two runs' own
    diff = [(i, x, y) for i, (x, y) in enumerate(zip(a, b)) if x != y and "T.TXT" not in x.replace(" ", ".") and "T        TXT" not in x]
    if diff:
        sys.exit("FAIL state (same): the screen after the state is not the cold boot's for the same keys:\n" +
                 "\n".join(f"  row {i}: {x!r}\n      cold {y!r}" for i, x, y in diff))
    print("PASS state (same): the text screen after the state and the keys is the cold boot's, line for line")


def step_bad(show):
    good = open(os.path.join(WORK, "XTGS.STATE.good"), "rb").read()
    hdr, _ = decode(good)
    at = hdr["data"] + 256 * (hdr["pages"] // 2) + 77
    late = len(good) - 300                                  # (in SVC's bank, the last put back)
    tab = hdr["mapat"] + hdr["mapb"] + 9

    def flip(i, bit=0x40):
        return good[:i] + bytes([good[i] ^ bit]) + good[i + 1:]
    cases = [("cut short", good[:-1000], None, 4),
             ("a byte longer", good + b"\0", None, 4),
             ("a byte of its data changed", flip(at), None, 7),
             ("a byte of its last piece changed", flip(late), None, 7),
             ("a byte of its map changed", flip(hdr["mapat"] + 44, 1), None, 4),
             ("a byte of its files' records changed", flip(258), None, 4),
             ("a byte of its pieces' sums changed", flip(tab), None, 4),
             ("its header's sum wrong", flip(214, 1), None, 4),
             ("another build's", flip(12, 0xFF), None, 3),
             ("XTGS.CMD changed", good, ("S", "C=SHARED", "STATE=ON", "VIDEO=CGA"), 3),
             ("no file", None, None, 2)]
    out = []
    for what, data, cmd, why in cases:
        if data is None:
            cadius("DELETEFILE", PO, VOLDIR + "/XTGS.STATE", check=False)
        else:
            put_state(PO, data)
        set_cmd(PO, cmd or ("S", "C=SHARED", "STATE=ON"))
        r = boot(PO, 3000 / 60)
        marks = [x for x in r["rows"] if x.startswith("MARK=")]
        if r["bootw"] != why or marks != ["MARK=0000"]:
            if show:
                print("\n".join(r["rows"]))
            sys.exit(f"FAIL state (bad): with the state {what}, BS_BOOT is {r['bootw']} ({WHY.get(r['bootw'])}), "
                     f"wanted {why} ({WHY[why]}), and the screen has {marks} (a cold boot's is ['MARK=0000'])")
        out.append(f"{what}: {WHY[why]}")
    set_cmd(PO, ("S", "C=SHARED", "STATE=ON"))
    print("PASS state (bad): a cold boot each time, and BS_BOOT says why: " + "; ".join(out))


def step_time(show):
    good = open(os.path.join(WORK, "XTGS.STATE.good"), "rb").read()
    lines = []
    for zip_, name in ((False, "stock (2.8 MHz)"), (True, "a 16 MHz ZipGS")):
        cadius("DELETEFILE", PO, VOLDIR + "/XTGS.STATE", check=False)
        r = boot(PO, 6600 / 60, zip=zip_)
        cold = first(r, "mark", 0xBEEF)
        put_state(PO, good)
        r2 = boot(PO, (1500 if zip_ else 6600) / 60, zip=zip_)
        fast = first(r2, "boot", 1)
        tried = first(r, "boot", 2)
        if cold is None or fast is None:
            sys.exit(f"FAIL state (time): no time at {name} (cold {cold}, the state {fast})")
        base = tried or 0
        lines.append(f"{name}: a cold boot has run AUTOEXEC.BAT's MARK by frame {cold} ({cold / 60:.1f} s; the PC "
                     f"was begun at frame {base}), the state is in its places by frame {fast} ({fast / 60:.1f} s): "
                     f"{(cold - base) / max(fast - base, 1):.1f} times as fast from the PC's beginning")
    print("PASS state (time): " + "\n                   ".join(lines))


def step_quit(show):
    """The start state asked for and, in the same visit to the desk accessories, the quit: the state is
    written first, and the next start is from it."""
    build()
    t = 3000
    seq = tap(t, "Control", hold=40) + tap(t + 2, "Command / Open Apple", hold=36) + tap(t + 10, "Esc", hold=20)
    t += 200
    for _ in range(DOWNS):
        seq += tap(t, "Down Arrow")
        t += 40
    seq += tap(t, "Return", K2)                              # XTGS Control
    seq += tap(t + 80, "6  ^", K1) + tap(t + 140, "Space")   # the start state; its menu again, which says it waits
    seq += tap(t + 220, "5  %", K1) + tap(t + 280, "Space")  # the quit; the desk accessories again
    t += 340
    for _ in range(QUIT):
        seq += tap(t, "Down Arrow")
        t += 40
    seq += tap(t, "Return", K2)
    r = boot(PO, (t + 2400) / 60, seq)
    f = state_of(PO)
    code = struct.unpack_from("<H", bytes.fromhex(r["dumps"]["mb"]["hex"]), 4)[0]
    bad = []
    if f is None:
        bad.append("XTGS.STATE is not on the volume: the quit took the save's place")
    else:
        try:
            decode(f)
        except ValueError as e:
            bad.append(f"XTGS.STATE is not sound: {e}")
    # (the GS/OS application gives its front page back as it quits and is launched again by the test's
    # startup program: there the file and the start after it are the judge)
    if not S16 and r["status"] != "hit":
        bad.append(f"XT/GS did not quit ({r['status']})")
    elif not S16 and code != 0xB0C3:
        bad.append(f"the exit code is {code:#06x}, not the quit's 0xb0c3")
    if show or bad:
        print("\n".join(r["rows"]))
    if bad:
        sys.exit("FAIL state (quit): " + "; ".join(bad))
    r = boot(PO, 900 / 60)
    if r["bootw"] != 1:
        sys.exit(f"FAIL state (quit): the start after it: BS_BOOT is {r['bootw']} ({WHY.get(r['bootw'])}), not 1")
    print(f"PASS state (quit): \"6\" and then the quit in one visit to the desk accessories: XTGS.STATE written "
          f"({len(f)} bytes) before XT/GS quit, and the next start is from it")


def main():
    args = sys.argv[1:]
    show = "--show" in args
    only = None
    if "--only" in args:
        only = args[args.index("--only") + 1].split(",")
    steps = [("make", lambda: step_make(show)), ("load", lambda: step_load(show)), ("go", lambda: step_go(show)),
             ("cold", lambda: step_go(show, cold=True)), ("same", step_same), ("again", lambda: step_again(show)),
             ("hard", lambda: step_hard(show)), ("files", lambda: step_files(show)), ("day", lambda: step_day(show)),
             ("ega", lambda: step_ega(show)), ("disk", lambda: step_disk(show)), ("bad", lambda: step_bad(show)),
             ("time", lambda: step_time(show)), ("quit", lambda: step_quit(show))]
    if only is not None and "make" not in only:
        try:
            was = open(os.path.join(WORK, "config")).read()
        except OSError:
            was = None
        if was != config():
            sys.exit("state_test: build/state/ holds another configuration's volume and state (or none): "
                     "run the step make first")
    for name, fn in steps:
        if only is None or name in only:
            fn()


if __name__ == "__main__":
    main()
