#!/usr/bin/env python3
"""M2 judge: assemble a .COM test with nasm, boot it as the C command,
and compare what it wrote to the console, its exit code, and (optionally)
screen rows, against tests/com/NAME.json:

    {"com": "hello.asm", "name": "HELLO.COM", "args": "", "exit": 0,
     "stdout": "hello.out",                       # tests/expected/, exact bytes
     "screen": {"10": {"col": 20, "text": "..."}},  # row 10 from column 20
     "keys": [{"at": 90, "key": "xtgs"}, {"at": 150, "coded": "{ENTER}"}]}

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
    src = os.path.join(ROOT, "tests", "com", t["com"])
    binary = os.path.join(workdir, t["name"])
    subprocess.run(["nasm", "-f", "bin", "-o", binary, src], check=True)
    staged = os.path.join(workdir, t["name"] + "#060000")
    os.replace(binary, staged)
    cmd = os.path.join(workdir, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write(f"C {t['name']} {t.get('args', '')}".rstrip() + "\r")
    stage = os.path.join(ROOT, "build", "stage")
    image = os.path.join(workdir, name + ".po")
    subprocess.run([os.path.join(HERE, "make_image.sh"), image,
                    os.path.join(stage, "XTGS.SYSTEM#FF2000"), os.path.join(stage, "CORE#060000"),
                    os.path.join(stage, "SVC#060000"), staged, cmd], check=True, capture_output=True)
    r = mamerun.run(image, waits=[(syms["mb_magic"], 0x5A5A)],
                    dumps=[("mb", syms["mb_stage"], 0x70), ("caplen", CAP_LEN, 8), ("cap", CAP_BUF, CAP_MAX),
                           ("txt", TXT_BASE, 4000), ("shr", shr.SHR_BASE, shr.SHR_LEN)],
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
    print(f"{name}: exit {exit_v:#x}, {caplen} bytes of console output, "
          f"{unhn} unhandled calls{f' (first {unh:#06x})' if unhn else ''}, last INT 21h AH={last:#04x}, frames {r['frame']}")
    with open(os.path.join(ROOT, "tests", "expected", t["stdout"]), "rb") as f:
        want = f.read()
    if cap != want:
        problems.append("console output differs")
        print("  expected: " + repr(want))
        print("  got:      " + repr(cap))
    if exit_v != t.get("exit", 0):
        problems.append(f"exit code {exit_v:#x}, expected {t.get('exit', 0):#x}")
    if stage_v != 10:
        problems.append(f"loader stopped at stage {stage_v:#x} (error {err:#x})")
    for row, spec in t.get("screen", {}).items():
        got = rows[int(row)][spec.get("col", 0):spec.get("col", 0) + len(spec["text"])]
        if got != spec["text"]:
            problems.append(f"screen row {row}: {got!r} != {spec['text']!r}")
    for i, row in enumerate(rows):
        if row.strip():
            print(f"  {i:2d}|{row.rstrip()}")
    png, _lines = shr.render(bytes.fromhex(r["dumps"]["shr"]["hex"]))
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
