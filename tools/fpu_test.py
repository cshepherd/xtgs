#!/usr/bin/env python3
"""fpu_test.py [--show]: the 8087 as a program of the time finds it (make test-fpu;
docs/8087.md, M9.2).

FreeDOS boots from a copy of the folder third_party/freedos/fd/SHARED
(command S) whose AUTOEXEC.BAT runs Norton Utilities 6.01's System
Information, SYSINFO /SUMMARY (release/shared/SYSINFO.EXE: the test is
skipped without it), once with no line FPU= and once with FPU=8087. Its
line "Co-Processor:" must say None and then 8087, and with the line the
8087 must be there with the control word its reset leaves.

tests/com/fpudet.asm (make test-com COM=fpudet, COM=fpunone) is the same
question asked by a program of this tree, and every form of operand.

Work files in build/fputest/. Two boots, some 150 emulated seconds each at 16 MHz.
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
SI = os.path.join(ROOT, "release", "shared", "SYSINFO.EXE")
WORK = os.path.join(ROOT, "build", "fputest")           # (build/fpu is the image)
FPU = 0x050A86                                              # FPU_CFG (src/include/pc.s), and the words after it


def boot(lines):
    folder = os.path.join(WORK, "SHARED")
    shutil.rmtree(folder, ignore_errors=True)
    shutil.copytree(FD, folder)
    shutil.copyfile(SI, os.path.join(folder, "SYSINFO.EXE#060000"))
    with open(os.path.join(folder, "AUTOEXEC.BAT#040000"), "w", newline="\r\n") as f:
        f.write("@ECHO OFF\nSYSINFO /SUMMARY\n")
    cmd = os.path.join(WORK, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write("S\rC=SHARED\r" + "".join(l + "\r" for l in lines))
    stage = os.path.join(ROOT, "build", "stage")
    po = os.path.join(WORK, "fpu.po")
    subprocess.run([os.path.join(HERE, "make_image.sh"), po, os.path.join(stage, "XTGS.SYSTEM#FF2000"),
                    os.path.join(stage, "CORE#060000"), os.path.join(stage, "SVC#060000"), cmd, folder],
                   check=True, capture_output=True, env=dict(os.environ, VOLSIZE="4096KB"))
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    r = mamerun.run(po, waits=[(syms["mb_magic"], 0x5A5A)], dumps=[("fb", 0x2B8000, 4000), ("fpu", FPU, 0x1A)],
                    seconds=150, settle=5, zip=True)
    if r["status"] == "no-output":
        print(r.get("mame_output", ""))
        sys.exit("fpu_test: MAME produced no result")
    fb = bytes.fromhex(r["dumps"]["fb"]["hex"])
    rows = [bytes(fb[y * 160 + x * 2] for x in range(80)).decode("cp437").rstrip("\0 ") for y in range(25)]
    names = ("cfg", "on", "cw", "sw", "top", "ip", "ip2", "opc", "dp", "dp2", "bad", "last", "sane")
    return rows, dict(zip(names, struct.unpack("<13H", bytes.fromhex(r["dumps"]["fpu"]["hex"]))))


def main():
    show = "--show" in sys.argv
    if not os.path.exists(SI):
        print("SKIP fpu: no release/shared/SYSINFO.EXE (Norton Utilities 6.01's System Information) to ask")
        return
    os.makedirs(WORK, exist_ok=True)
    said = {}
    for lines in ((), ("FPU=8087",)):
        rows, w = boot(lines)
        if show:
            print("\n".join(x for x in rows if x.strip()))
            print(w)
        line = [x for x in rows if "Co-Processor:" in x]
        if len(line) != 1:
            sys.exit(f"FAIL fpu: no Co-Processor line on the screen with {lines or 'no line'}\n" + "\n".join(rows))
        said[lines] = line[0].split("Co-Processor:")[1].split()[0]
        if lines and (w["cfg"], w["on"], w["cw"]) != (1, 1, 0x03FF):
            sys.exit(f"FAIL fpu: with FPU=8087 the 8087 is not there, or its control word is not the reset's ({w})")
        if not lines and (w["cfg"] or w["on"]):
            sys.exit(f"FAIL fpu: with no line FPU= there is an 8087 ({w})")
        if lines:
            met = (f"{w['bad']} instructions it has no arithmetic for yet were met, the last D{8 + (w['last'] >> 11):X} "
                   f"{w['last'] & 0xFF:02X}") if w["bad"] else "every instruction it met is done"
            sane = w["sane"]
    if said[()] != "None" or said[("FPU=8087",)] != "8087":
        sys.exit(f"FAIL fpu: Norton SI says Co-Processor: {said[()]} with no line and {said[('FPU=8087',)]} "
                 "with FPU=8087; wanted None and 8087")
    print(f"PASS fpu: Norton SI 6.01 says \"Co-Processor: None\" without the line and \"Co-Processor: 8087\" with "
          f"FPU=8087 (SANE ${sane:04X} answers; {met})")


main()
