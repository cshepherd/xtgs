#!/usr/bin/env python3
"""M2 judge: assemble a .COM test with nasm, boot it as the C command,
and compare what it wrote to the console, its exit code, and (optionally)
screen rows, against tests/com/NAME.json:

    {"com": "hello.asm", "name": "HELLO.COM", "args": "", "exit": 0,
     "stdout": "hello.out",                       # tests/expected/, exact bytes
     "screen": {"10": {"col": 20, "text": "..."}},  # row 10 from column 20
                                                  # (and the SHR pixels must show the text buffer)
     "video": "t160",                             # the screen it ends on: "text", or "t160"
                                                  # (160x100: the pixels must show all of B800)
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

RES_BASE = 0x050000
CAP_LEN, DIAG_UNH, DIAG_UNHN, DIAG_LAST = RES_BASE + 0x800, RES_BASE + 0x802, RES_BASE + 0x804, RES_BASE + 0x806
CAP_BUF, CAP_MAX = RES_BASE + 0x1000, 0x7000
TXT_BASE = 0x2B8000


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
        f.write(f"C {t['name']} {t.get('args', '')}".rstrip() + "\r")
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
                           ("txt", TXT_BASE, t160shr.CELLS), ("shr", shr.SHR_BASE, shr.SHR_LEN),
                           ("maps", RES_BASE + 0x810, 48)],
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
    for i, row in enumerate(rows):
        if row.strip():
            print(f"  {i:2d}|{row.rstrip()}")
    shr_dump = bytes.fromhex(r["dumps"]["shr"]["hex"])
    if textshr.is_text(shr_dump):                    # the pixels are the text buffer's
        bad = textshr.mismatches(bytes.fromhex(r["dumps"]["txt"]["hex"]), shr_dump)
        if bad:
            problems.append(f"{len(bad)} screen cells do not show the text buffer (first row,col {bad[0]})")
    elif t.get("video") == "text":
        problems.append("the screen is not in text mode")
    if t.get("video") == "t160":
        if not t160shr.is_t160(shr_dump):
            problems.append("the screen is not in the 160x100 mode (SHR 320, the CGA palette)")
        else:
            bad = t160shr.mismatches(bytes.fromhex(r["dumps"]["txt"]["hex"]), shr_dump)
            if bad:
                problems.append(f"{len(bad)} of the 8000 cells do not show B800 (first row,col {bad[0]})")
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
    ok = True
    for p in paths:
        ok &= run_test(p, syms, workdir, seconds=120)
    print("COM tests:", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
