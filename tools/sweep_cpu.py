#!/usr/bin/env python3
"""Run judge_cpu.py over a range of opcodes, a few vector files per boot,
and tabulate. Keeps going past failures.

    sweep_cpu.py --ops 00-3F [--ops C0-FF] [--per 4] --tag A

Writes build/vec/sweep_<tag>.json and prints one line per file:
    NAME  run pass fail  ok|FAIL|ERROR
"""
import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import vectors  # noqa: E402

LINE = re.compile(r"^\s+(\S+)\s+(\d+) run\s+(\d+) pass\s+(\d+) fail\s+(ok|FAIL)")


def expand(ranges, meta):
    files = []
    for r in ranges:
        lo, _, hi = r.partition("-")
        hi = hi or lo
        for op in range(int(lo, 16), int(hi, 16) + 1):
            if meta.get(f"{op:02X}", {}).get("status") == "prefix":
                continue              # no vectors exist for a prefix byte
            files += vectors.files_for(f"{op:02X}", meta)
    return files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ops", action="append", required=True)
    ap.add_argument("--per", type=int, default=4)
    ap.add_argument("--tag", default="sweep")
    ap.add_argument("--seconds", default="240")
    args = ap.parse_args()
    meta = vectors.metadata()
    files = expand(args.ops, meta)
    results = {}
    workdir = os.path.join(ROOT, "build", "vec", args.tag)
    for i in range(0, len(files), args.per):
        group = files[i:i + args.per]
        cmd = [sys.executable, "-I", os.path.join(HERE, "judge_cpu.py"), "--workdir", workdir,
               "--list", "6", "--seconds", args.seconds]
        for f in group:
            cmd += ["--op", f]
        p = subprocess.run(cmd, capture_output=True, text=True)
        seen = set()
        for line in p.stdout.splitlines():
            m = LINE.match(line)
            if m:
                name, run, ok, fail, verdict = m.groups()
                results[name] = {"run": int(run), "pass": int(ok), "fail": int(fail), "verdict": verdict}
                seen.add(name)
                print(f"  {name:6s} {run:>5s} run {ok:>5s} pass {fail:>5s} fail  {verdict}", flush=True)
        for f in group:
            if f not in seen:
                if f.split(".")[0] in seen:
                    continue              # a group file the suite names without a sub-index
                if not vectors.load(f):
                    results[f] = {"run": 0, "pass": 0, "fail": 0, "verdict": "none"}
                    print(f"  {f:6s} no vectors in the suite", flush=True)
                    continue
                tail = (p.stdout + p.stderr).strip().splitlines()[-3:]
                results[f] = {"run": 0, "pass": 0, "fail": 0, "verdict": "ERROR", "detail": tail}
                print(f"  {f:6s} ERROR: {' | '.join(tail)}", flush=True)
        if any(results[f]["verdict"] != "ok" for f in group):
            detail = p.stdout[p.stdout.find("first failure"):] if "first failure" in p.stdout else ""
            if detail:
                results[group[0] + "_detail"] = detail.splitlines()[:40]
        with open(os.path.join(ROOT, "build", "vec", f"sweep_{args.tag}.json"), "w") as out:
            json.dump(results, out, indent=1)
    total = sum(v["run"] for v in results.values() if isinstance(v, dict) and "run" in v)
    passed = sum(v["pass"] for v in results.values() if isinstance(v, dict) and "pass" in v)
    bad = [k for k, v in results.items() if isinstance(v, dict) and v.get("verdict") not in ("ok", "none") and "verdict" in v]
    print(f"sweep {args.tag}: {len(files)} files, {total} vectors, {passed} passed; not ok: {' '.join(bad) or 'none'}")


if __name__ == "__main__":
    main()
