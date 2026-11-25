#!/usr/bin/env python3
"""tp_bench.py TPDIR [--jit] [--zip]: Turbo Pascal 5.5 and the 8087 (docs/8087.md, M9.7).

TPDIR holds TPC.EXE and TURBO.TPL (Turbo Pascal 5.5's disk 1; not in the tree). One
boot at 16 MHz compiles tests/tp/BENCH.INC twice under FreeDOS, as BENCHR ({$N-}: Turbo
Pascal's 6-byte software Real) and BENCHD ({$N+,E+}: Double, the 8087 when there is
one and Turbo Pascal's emulator when there is not), and tests/tp/FPERR.PAS. Then two
boots run them, with FPU=8087 and without: the programs time their parts by the BIOS's
tick count, and FPERR must end in run-time error 200 both ways (with the 8087, through
its interrupt, INT 2). --jit runs the two with the translator, --zip at 16 MHz.

Prints the table of seconds and the checks; work files in build/tpbench/.
"""
import glob, os, shutil, struct, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "mame"))
import mamerun, symbols  # noqa: E402

WORK = os.path.join(ROOT, "build", "tpbench")
RES = 0x050000                                             # RES_BASE: CAP_LEN +800h, CAP_BUF +1000h, FPU_CFG +A86h
PARTS = ("POLY", "DIV", "SQRT", "SINEXP", "LNATAN")


def boot(files, bat, lines, zip_, seconds):
    folder = os.path.join(WORK, "SHARED")
    shutil.rmtree(folder, ignore_errors=True)
    shutil.copytree(os.path.join(ROOT, "third_party", "freedos", "fd", "SHARED"), folder)
    files = dict(files, **{"REBOOT.COM#060000": bytes([0xCD, 0x19]),
                           "AUTOEXEC.BAT#040000": ("@ECHO OFF\r\n" + "".join(l + "\r\n" for l in bat)
                                                   + "REBOOT\r\n").encode()})
    for name, data in files.items():
        with open(os.path.join(folder, name), "wb") as f:
            f.write(data)
    cmd = os.path.join(WORK, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write("S\rC=SHARED\r" + "".join(l + "\r" for l in lines))
    st = os.path.join(ROOT, "build", "stage")
    po = os.path.join(WORK, "tp.po")
    img = [os.path.join(st, n) for n in ("XTGS.SYSTEM#FF2000", "CORE#060000", "SVC#060000")] + [cmd]
    if "JIT=ON" in lines:
        img.append(os.path.join(st, "JIT#060000"))
    subprocess.run([os.path.join(HERE, "make_image.sh"), po] + img + [folder], check=True, capture_output=True,
                   env=dict(os.environ, VOLSIZE="4096KB"))
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    r = mamerun.run(po, waits=[(syms["mb_magic"], 0x5A5A)], dumps=[("len", RES + 0x800, 2),
                    ("cap", RES + 0x1000, 0x6000)], seconds=seconds, settle=5, zip=zip_)
    if r["status"] != "hit":
        sys.exit(f"tp_bench: the run did not end ({r['status']})")
    n = struct.unpack("<H", bytes.fromhex(r["dumps"]["len"]["hex"]))[0]
    return po, bytes.fromhex(r["dumps"]["cap"]["hex"])[:n].decode("cp437").replace("\r", "")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args or not os.path.exists(os.path.join(args[0], "TPC.EXE")):
        sys.exit(__doc__)
    tp = args[0]
    os.makedirs(WORK, exist_ok=True)
    src = os.path.join(ROOT, "tests", "tp")
    body = open(os.path.join(src, "BENCH.INC"), "rb").read()
    files = {"TPC.EXE#060000": open(os.path.join(tp, "TPC.EXE"), "rb").read(),
             "TURBO.TPL#060000": open(os.path.join(tp, "TURBO.TPL"), "rb").read(),
             "BENCHR.PAS#040000": b"{$N-}\r\nprogram BenchR;\r\n" + body,
             "BENCHD.PAS#040000": b"{$N+,E+}\r\n{$DEFINE USE87}\r\nprogram BenchD;\r\n" + body,
             "FPERR.PAS#040000": open(os.path.join(src, "FPERR.PAS"), "rb").read()}
    po, cap = boot(files, ["TPC BENCHR", "TPC BENCHD", "TPC FPERR"], [], True, 300)
    exes = {}
    out = os.path.join(WORK, "out")
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    for name in ("BENCHR.EXE", "BENCHD.EXE", "FPERR.EXE"):
        subprocess.run([os.path.join(HERE, "cadius_strict.sh"), "EXTRACTFILE", po, "/XTGS/SHARED/" + name, out + "/"],
                       capture_output=True)
        got = glob.glob(os.path.join(out, name + "#*"))
        if not got:
            sys.exit(f"tp_bench: {name} was not made:\n{cap[-1500:]}")
        exes[name + "#060000"] = open(got[0], "rb").read()
    extra = ["JIT=ON"] if "--jit" in sys.argv else []
    table = {}
    ok = True
    for label, lines in (("8087", ["FPU=8087"]), ("none", [])):
        _po, cap = boot(exes, ["BENCHR", "BENCHD", "FPERR"], lines + extra, "--zip" in sys.argv, 2000)
        runs = cap.split("Test8087=")[1:]
        if len(runs) != 3:
            sys.exit(f"tp_bench: the programs did not all run:\n{cap[-1500:]}")
        for prog, text in zip(("Real", "Double"), runs[:2]):
            col = "Real" if prog == "Real" else ("8087" if label == "8087" else "emulator")
            vals = {}
            for l in text.splitlines():
                w = l.split()
                if w and w[0] in PARTS:
                    vals[w[0]] = (int(w[1]) * 0.054925, w[2])
            table.setdefault(col, []).append(vals)
        want87 = "1" if label == "8087" else "0"
        t87 = runs[1].split()[0]
        err = "Runtime error 200" in runs[2]
        print(f"{label}: Test8087={t87} (want {want87}), FPERR {'ends in run-time error 200' if err else 'did NOT end in error 200'}")
        ok &= t87 == want87 and err
    cols = ("Real", "emulator", "8087")
    print(f"\n{'seconds':10s}" + "".join(f"{c:>12s}" for c in cols) + "   values (Real / Double)")
    for p in PARTS + ("total",):
        row = []
        for c in cols:
            v = table[c][0]
            row.append(sum(x[0] for x in v.values()) if p == "total" else v[p][0])
        vals = "" if p == "total" else f"   {table['Real'][0][p][1]} / {table['8087'][0][p][1]}"
        print(f"{p:10s}" + "".join(f"{x:12.1f}" for x in row) + vals)
    sys.exit(0 if ok else 1)


main()
