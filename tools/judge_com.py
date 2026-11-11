#!/usr/bin/env python3
"""M2 judge: assemble a .COM test with nasm, boot it as the C command,
and compare what it wrote to the console, its exit code, and (optionally)
screen rows, against tests/com/NAME.json:

    {"com": "hello.asm", "name": "HELLO.COM", "args": "", "exit": 0,
     "stdout": "hello.out",                       # tests/expected/, exact bytes
     "screen": {"10": {"col": 20, "text": "..."}},  # row 10 from column 20
                                                  # (and the SHR pixels must show the text buffer)
     "video": "t160",                             # the screen it ends on: "text", or "t160"
                                                  # (160x100: the pixels must show all of B800),
                                                  # or "cga4"/"cga6" (CGA graphics, the same),
                                                  # or "ega" (mode 0Dh: the four planes),
                                                  # or "tandy9" (a Tandy's mode 09h: the two
                                                  # pages shown, wherever they are kept),
                                                  # or "tandy8" (its mode 08h: the one page),
                                                  # or "tandyA" (its mode 0Ah: the two pages)
     "ega_ac": "00141503...",                     # with "ega": the attribute controller's
                                                  # sixteen palette registers at the end
     "tandy_pal": "000C0E03...", "tandy_page": "F6",  # with those two: the array's sixteen palette
                                                  # registers and the page register at the end
                                                  # ("tandy_pal" with any "video", and
     "tandy_mask": "07",                          # the array's palette mask)
     "cga_colours": [0, 11, 13, 15],              # with "cga4"/"cga6": which of the sixteen
                                                  # colours pixels 0-3 (0-1) are shown in. The
                                                  # SHR palette is always judged against the
                                                  # registers (tools/cgashr.py colours)
     "cmd": ["VIDEO=TANDY"],                      # XTGS.CMD's lines after the command's
     "psg": {"writes": 150,                       # a Tandy's sound chip: the bytes it took, and
             "speaker": [[0, 0], [140, 1193]],    # every write to the DOC judged against a
             "timer": [[0, 0]]},                  # model of it; the speaker's and the timer's
                                                  # counts from those bytes on (tools/psgdoc.py).
                                                  # Without it: the oscillators enabled and the
                                                  # timer's rate, as channel 0 was at the start
     "keys": [{"at": 90, "key": "xtgs"}, {"at": 150, "coded": "{ENTER}"}],
     "disk": {"LEFT.TMP": 5}}                     # a file's length on the volume afterwards
    {"bin": "third_party/msdos2/DEBUG.COM", "name": "DEBUG.COM",  # a real program
     "files": ["hello.txt"],                      # tests/data/ copied onto the volume
     "stdout_contains": ["AX=0000"], "show_output": true, "no_unhandled": false}

    judge_com.py tests/com/hello.json [...]        exit 0 only if all pass

Keys are mamerun inputs, frames after the program starts (MB_RUNIDX =
$BE57). Everything the program writes through INT 21h/10h/29h console
output is captured in bank $05 by the services bank (CAP_BUF).
"""
import json
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, "mame"))
sys.path.insert(0, HERE)
import mamerun  # noqa: E402
import shr  # noqa: E402
import symbols  # noqa: E402
import textshr  # noqa: E402
import t160shr  # noqa: E402
import cgashr  # noqa: E402
import egashr  # noqa: E402
import tandyshr  # noqa: E402
import psgdoc  # noqa: E402

RES_BASE = 0x050000
CAP_LEN, DIAG_UNH, DIAG_UNHN, DIAG_LAST = RES_BASE + 0x800, RES_BASE + 0x802, RES_BASE + 0x804, RES_BASE + 0x806
CAP_BUF, CAP_MAX = RES_BASE + 0x1000, 0x7000
TXT_BASE = 0x2B8000
GUEST_BASE = 0x200000
CRTC_START, EGA_AC = RES_BASE + 0x88C, RES_BASE + 0x970     # src/include/pc.s: CRTC_REG+12, EGA_AC


def text_rows(buf):
    return [bytes(buf[r * 160 + c * 2] for c in range(80)).decode("cp437") for r in range(25)]


def run_test(path, syms, workdir, seconds):
    with open(path) as f:
        t = json.load(f)
    name = os.path.splitext(os.path.basename(path))[0]
    staged = os.path.join(workdir, t["name"] + "#060000")
    if "com" in t:                                   # assembled here from nasm source
        src = os.path.join(ROOT, "tests", "com", t["com"])
        binary = os.path.join(workdir, t["name"])
        subprocess.run(["nasm", "-f", "bin", "-o", binary, src], check=True)
        os.replace(binary, staged)
    else:                                            # an independently sourced binary
        with open(os.path.join(ROOT, t["bin"]), "rb") as f, open(staged, "wb") as g:
            g.write(f.read())
    cmd = os.path.join(workdir, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write(f"C {t['name']} {t.get('args', '')}".rstrip() + "\r" + "".join(l + "\r" for l in t.get("cmd", [])))
    extra = []                                       # data files on the volume: NAME#TTAAAA from tests/data
    for fn in t.get("files", []):
        srcf = os.path.join(ROOT, "tests", "data", fn)
        dst = os.path.join(workdir, fn.upper() + "#040000")
        with open(srcf, "rb") as f, open(dst, "wb") as g:
            g.write(f.read())
        extra.append(dst)
    stage = os.path.join(ROOT, "build", "stage")
    image = os.path.join(workdir, name + ".po")
    subprocess.run([os.path.join(HERE, "make_image.sh"), image,
                    os.path.join(stage, "XTGS.SYSTEM#FF2000"), os.path.join(stage, "CORE#060000"),
                    os.path.join(stage, "SVC#060000"), staged, cmd] + extra, check=True, capture_output=True)
    r = mamerun.run(image, waits=[(syms["mb_magic"], 0x5A5A)],
                    dumps=[("mb", syms["mb_stage"], 0x70), ("caplen", CAP_LEN, 8), ("cap", CAP_BUF, CAP_MAX),
                           ("txt", TXT_BASE, cgashr.LEN), ("shr", shr.SHR_BASE, shr.SHR_LEN),
                           ("maps", RES_BASE + 0x810, 48), ("crtc", CRTC_START, 2), ("ac", EGA_AC, 16)] +
                          [(f"pl{i}", GUEST_BASE + a, 0x4000) for i, a in enumerate(egashr.PLANES)
                           if t.get("video") == "ega"] +
                          [("tdy", RES_BASE + tandyshr.STATE, tandyshr.STATE_LEN),
                           ("tdymr", RES_BASE + tandyshr.MODEREQ, 2),
                           ("csel", syms["GUEST_DP"] + syms["cga_bg"], 6)] + psgdoc.dumps(syms) +
                          ([(f"tm{a:x}", GUEST_BASE + a, n) for a, n in tandyshr.REGIONS]
                           if t.get("video") in ("tandy8", "tandy9", "tandyA") else []),
                    seconds=seconds, settle=5, ready=(syms["mb_runidx"], 0xBE57), inputs=t.get("keys", []))
    if r["status"] == "no-output":
        print(r.get("mame_output", ""))
        return False
    mb = bytes.fromhex(r["dumps"]["mb"]["hex"])
    stage_v, magic, exit_v, err = struct.unpack_from("<HHHH", mb, 0)
    problems = []
    if r["status"] != "hit":
        print("  text screen: " + " / ".join(l for l in r["text"] if l.strip()))
        problems.append(f"timed out at frame {r['frame']} (loader stage {stage_v})")
    caplen, unh, unhn, last = struct.unpack_from("<HHHH", bytes.fromhex(r["dumps"]["caplen"]["hex"]), 0)
    cap = bytes.fromhex(r["dumps"]["cap"]["hex"])[:caplen]
    rows = text_rows(bytes.fromhex(r["dumps"]["txt"]["hex"]))
    cga = {"cga4": 4, "cga6": 6}.get(t.get("video"))
    maps = bytes.fromhex(r["dumps"]["maps"]["hex"])
    fns = [f"{i:02X}" for i in range(128) if maps[i >> 3] >> (i & 7) & 1]
    ints = [f"{i:02X}" for i in range(256) if maps[16 + (i >> 3)] >> (i & 7) & 1]
    print(f"{name}: exit {exit_v:#x}, {caplen} bytes of console output, "
          f"{unhn} unhandled calls{f' (first {unh:#06x})' if unhn else ''}, last INT 21h AH={last:#04x}, frames {r['frame']}")
    if fns or ints:
        print(f"  unhandled INT 21h functions: {' '.join(fns) or '-'}; other INTs: {' '.join(ints) or '-'}")
    if "stdout" in t:
        with open(os.path.join(ROOT, "tests", "expected", t["stdout"]), "rb") as f:
            want = f.read()
        if cap != want:
            problems.append("console output differs")
            print("  expected: " + repr(want))
            print("  got:      " + repr(cap))
    for needle in t.get("stdout_contains", []):
        if needle.encode("cp437") not in cap:
            problems.append(f"console output lacks {needle!r}")
    if t.get("show_output") or any(p.startswith("console output lacks") for p in problems):
        print("  console: " + repr(cap[:600]))
    if unhn and t.get("no_unhandled", True):
        problems.append(f"{unhn} unhandled service calls (first {unh:#06x})")
    if exit_v != t.get("exit", 0):
        problems.append(f"exit code {exit_v:#x}, expected {t.get('exit', 0):#x}")
    if stage_v != 10:
        problems.append(f"loader stopped at stage {stage_v:#x} (error {err:#x})")
    for fn, want_len in t.get("disk", {}).items():      # a file the program left on the volume
        cat = subprocess.run(["cadius", "CATALOG", image], capture_output=True).stdout.decode("latin-1")
        got = [int(w[3]) for w in (line.split() for line in cat.splitlines()) if len(w) > 3 and w[0] == fn]
        if got != [want_len]:
            problems.append(f"{fn} on the volume is {got[0] if got else 'missing'}, expected {want_len} bytes")
    for row, spec in t.get("screen", {}).items():
        got = rows[int(row)][spec.get("col", 0):spec.get("col", 0) + len(spec["text"])]
        if got != spec["text"]:
            problems.append(f"screen row {row}: {got!r} != {spec['text']!r}")
    ega = t.get("video") == "ega"
    tandy = {"tandy8": 8, "tandy9": 9, "tandyA": 0x0A}.get(t.get("video"))
    for i, row in enumerate(rows if not cga and not ega and not tandy else []):
        if row.strip():
            print(f"  {i:2d}|{row.rstrip()}")
    shr_dump = bytes.fromhex(r["dumps"]["shr"]["hex"])
    tstate = bytes.fromhex(r["dumps"]["tdy"]["hex"])  # the Tandy's array, when the PC is one
    tregs = tandyshr.regs(tstate) if tstate[0] else None
    if cga:                                          # the pixels are B800's two fields
        csel = bytes.fromhex(r["dumps"]["csel"]["hex"])   # cga_bg, cga_pal, cga_int: 3D9h
        assert syms["cga_pal"] == syms["cga_bg"] + 2 and syms["cga_int"] == syms["cga_bg"] + 4
        sel = csel[0] & 15 | (csel[4] & 1) << 4 | (csel[2] & 1) << 5
        modereq = bytes.fromhex(r["dumps"]["tdymr"]["hex"])[0]
        cols = cgashr.colours(sel, modereq, cga, tregs)
        print(f"  colours {' '.join(map(str, cols))} (3D9h {sel:02X}, 3D8h {modereq:02X}" +
              (f", a Tandy's palette {tregs[16:32].hex().upper()} through {tregs[1]:02X}" if tregs else "") + ")")
        if not cgashr.is_cga(shr_dump, cga):
            problems.append(f"the screen is not in CGA mode {cga} (SHR {640 if cga == 6 else 320})")
        else:
            bad = cgashr.mismatches(bytes.fromhex(r["dumps"]["txt"]["hex"]), shr_dump, cga)
            if bad:
                problems.append(f"{len(bad)} of the 16000 bytes of B800 are not on the screen (first line,byte {bad[0]})")
            badp = cgashr.palette(shr_dump, cga, cols)
            if badp:
                problems.append("palette: " + ", ".join(f"{i}: {g:04X} not {w:04X}" for i, g, w in badp))
        if "cga_colours" in t and cols != t["cga_colours"]:
            problems.append(f"the colours are {cols}, expected {t['cga_colours']}")
    elif ega:                                        # the pixels are the four planes'
        crtc = bytes.fromhex(r["dumps"]["crtc"]["hex"])
        ac = bytes.fromhex(r["dumps"]["ac"]["hex"])
        start = crtc[0] << 8 | crtc[1]                 # (in bytes: R12, R13)
        if not egashr.is_ega(shr_dump):
            problems.append("the screen is not in mode 0Dh (SHR 320, one palette)")
        elif start + egashr.LEN > 0x4000:
            problems.append(f"the screen starts at {start:#x}, past what the judge reads")
        else:
            bad = egashr.mismatches([bytes.fromhex(r["dumps"][f"pl{i}"]["hex"]) for i in range(4)], start, shr_dump)
            if bad:
                problems.append(f"{len(bad)} of the 8000 bytes of the planes are not on the screen "
                                f"(first line,byte {bad[0]}; the screen starts at {start:#x})")
            badp = egashr.palette(ac, shr_dump)
            if badp:
                problems.append("palette: " + ", ".join(f"{i}: {g:04X} not {w:04X}" for i, g, w in badp))
        if "ega_ac" in t and ac.hex().upper() != t["ega_ac"].upper():
            problems.append(f"the palette registers are {ac.hex().upper()}, expected {t['ega_ac'].upper()}")
    elif tandy:                                      # the pixels are the pages shown
        state = bytes.fromhex(r["dumps"]["tdy"]["hex"])
        modereq = bytes.fromhex(r["dumps"]["tdymr"]["hex"])[0]
        mem = {a: bytes.fromhex(r["dumps"][f"tm{a:x}"]["hex"]) for a, _n in tandyshr.REGIONS}
        pal = tandyshr.regs(state)[16:32].hex().upper()
        print(f"  page register {tandyshr.page_reg(state):02X}, pages in slots {tandyshr.slots(state)}, "
              f"{state[6] | state[7] << 8} moves of 16K, palette {pal} through {tandyshr.regs(state)[1]:02X}")
        if not state[0]:
            problems.append("the PC is not a Tandy (TDY_ON)")
        elif not tandyshr.shows(shr_dump, tandy):
            problems.append(f"the screen is not in mode {tandy:02X}h (SHR {640 if tandy == 0x0A else 320}, one palette)")
        elif tandyshr.mode(state, modereq) != tandy:
            problems.append(f"the mode registers are not mode {tandy:02X}h's (3D8h {modereq:02X}, "
                            f"the array's mode {tandyshr.regs(state)[3]:02X})")
        else:
            bad = tandyshr.mismatches(mem, state, shr_dump, tandy)
            if bad:
                problems.append(f"{len(bad)} of the 32000 bytes the screen should show are not on it "
                                f"(first line,byte {bad[0]}, last {bad[-1]})")
            badp = tandyshr.palette(state, shr_dump, tandy)
            if badp:
                problems.append("palette: " + ", ".join(f"{i}: {g:04X} not {w:04X}" for i, g, w in badp))
        if "tandy_page" in t and tandyshr.page_reg(state) != int(t["tandy_page"], 16):
            problems.append(f"the page register is {tandyshr.page_reg(state):02X}, expected {t['tandy_page']}")
    elif textshr.is_text(shr_dump):                  # the pixels are the text buffer's
        bad = textshr.mismatches(bytes.fromhex(r["dumps"]["txt"]["hex"]), shr_dump)
        if bad:
            problems.append(f"{len(bad)} screen cells do not show the text buffer (first row,col {bad[0]})")
    elif t.get("video") == "text":
        problems.append("the screen is not in text mode")
    if "tandy_pal" in t or "tandy_mask" in t:        # the array as the program left it
        if tregs is None:
            problems.append("the PC is not a Tandy (TDY_ON)")
        else:
            if "tandy_pal" in t and tregs[16:32].hex().upper() != t["tandy_pal"].upper():
                problems.append(f"the palette registers are {tregs[16:32].hex().upper()}, expected {t['tandy_pal'].upper()}")
            if "tandy_mask" in t and tregs[1] != int(t["tandy_mask"], 16):
                problems.append(f"the palette mask is {tregs[1]:02X}, expected {t['tandy_mask']}")
    if t.get("video") == "t160":
        if tregs:
            print(f"  a Tandy's palette {tregs[16:32].hex().upper()} through {tregs[1]:02X}")
        if not t160shr.is_t160(shr_dump, tregs):
            problems.append("the screen is not in the 160x100 mode (SHR 320, the CGA palette" +
                            (" as the Tandy's array has it)" if tregs else ")"))
        else:
            bad = t160shr.mismatches(bytes.fromhex(r["dumps"]["txt"]["hex"]), shr_dump)
            if bad:
                problems.append(f"{len(bad)} of the 8000 cells do not show B800 (first row,col {bad[0]})")
    # the DOC: the oscillators and the timer, and with "psg" every write against the chip
    bad, notes = psgdoc.judge({k: bytes.fromhex(r["dumps"][k]["hex"]) for k, _a, _n in psgdoc.dumps(syms)},
                              syms, t.get("psg"))
    for line in notes:
        print("  sound: " + line)
    problems += ["sound: " + b for b in bad]
    png, _lines = shr.render(shr_dump)
    with open(os.path.join(workdir, name + ".png"), "wb") as f:
        f.write(png)
    if problems:
        print("  FAIL: " + "; ".join(problems))
        return False
    print("  ok")
    return True


def main():
    paths = sys.argv[1:] or sorted(os.path.join(ROOT, "tests", "com", f)
                                   for f in os.listdir(os.path.join(ROOT, "tests", "com")) if f.endswith(".json"))
    paths = [p if os.path.exists(p) else os.path.join(ROOT, p) for p in paths]
    workdir = os.path.join(ROOT, "build", "com")
    os.makedirs(workdir, exist_ok=True)
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    svc = symbols.read(os.path.join(ROOT, "build", "svc.lst"))   # the colour-select register's
    syms.update({k: svc[k] for k in ("GUEST_DP", "cga_bg", "cga_pal", "cga_int")})   # three fields
    syms.update({k: svc[k] for k in ("DOC_LOG", "DOC_LOGM", "DOC_LOGN", "DOC_MARK", "DOC_REG", "PSG_REG",
                                     "PSG_LATCH", "TDY_ON", "PSG_VOL", "SPK_VOL", "N_OSC",
                                     "N_OSCT")})                 # the sound's (tools/psgdoc.py)
    ok = True
    for p in paths:
        ok &= run_test(p, syms, workdir, seconds=120)
    print("COM tests:", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
