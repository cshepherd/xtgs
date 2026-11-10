#!/usr/bin/env python3
"""Launch the GS/OS front end over and over in one boot (make test-s16).

The volume (tools/gsos_image.sh, XTGS_FRONT=s16) starts tests/gsos/start16.s,
which launches /VOL/XTGS/XTGS the way the Finder does: asking GS/OS to come
back to it. So every time XT/GS quits it is launched again, in a system that
has already run it. A key press ends each run. Checks, over RUNS launches:

  - every run finishes: loader stage 10, MB_DONE set, the core's exit code 0;
  - OS_BOOT says GS/OS;
  - the front page disappears between runs (XT/GS clears its signature and
    gives the page back), and every run gets the same banks and pages as the
    first: what a run claimed, it released.

mamerun finds the front page by its signature and reads MB_LAYOUT live, so
the addresses here are the assembled ones.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "mame"))
os.environ["XTGS_FRONT"] = "s16"
import layout  # noqa: E402
import mamerun  # noqa: E402

RUNS = 3


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True)
    ap.add_argument("--seconds", type=float, default=150)
    args = ap.parse_args()

    mb = layout.mailbox()
    regions = sorted(layout.regions().items(), key=lambda kv: kv[1][0])
    r = mamerun.run(args.image, waits=[(mb["MB_MAGIC"], 0x5A5A)], dumps=[("mb", mb["MB_BASE"], 0xA0)],
                    seconds=args.seconds, settle=30, occurrence=RUNS,
                    triggers={"done": (mb["MB_MAGIC"], 0x5A5A)},
                    inputs=[{"at": 60, "key": " ", "after": "done", "n": n} for n in range(1, RUNS)],
                    traces=[("magic", mb["MB_MAGIC"]), ("stage", mb["MB_STAGE"]), ("done", mb["MB_DONE"]),
                            ("exit", mb["MB_EXIT"]), ("osboot", mb["MB_OSBOOT"]),
                            *((f"lay{rid}", mb["MB_LAYOUT"] + 2 * rid) for _, (rid, _) in regions)])
    if r["status"] == "no-output":
        print(r.get("mame_output", ""))
        sys.exit("check_s16: MAME produced no result")
    tr = r["traces"]

    def at(name, frame):                    # a traced word's value at a frame
        return ([v for f, v in tr.get(name, []) if f <= frame] or [0])[-1]
    done = [f for f, v in tr["magic"] if v == 0x5A5A]
    gone = [f for f, v in tr["magic"] if v == 0 and f > 1]

    def show(frame):
        return " ".join(f"{n}=${at(f'lay{rid}', frame):02X}" for n, (rid, _) in regions if at(f"lay{rid}", frame))
    print(f"GS/OS front end: status {r['status']}, {len(done)} of {RUNS} runs finished "
          f"(frames {', '.join(map(str, done))})")
    problems = []
    if len(done) < RUNS:
        problems.append(f"wanted {RUNS} runs (launch, key, quit, launched again); stage trace {tr['stage'][-8:]}")
    for i, d in enumerate(done):
        print(f"  run {i + 1}: {show(d)}")
        if at("stage", d) != 10 or at("done", d) != 0xA5A5 or at("exit", d) != 0:
            problems.append(f"run {i + 1} ended at stage {at('stage', d):#x}, MB_DONE {at('done', d):#x}, "
                            f"exit {at('exit', d):#x} (want 0xa, 0xa5a5, 0)")
        if at("osboot", d) == 0:
            problems.append(f"run {i + 1}: OS_BOOT is 0, not a GS/OS launch")
        if i and show(d) != show(done[0]):
            problems.append(f"run {i + 1} is not where run 1 was: did the run before release its memory?")
    if len(gone) < len(done) - 1:
        problems.append(f"the front page was still there after a quit (magic trace {tr['magic']})")
    if problems or not done:
        print("S16: FAIL\n  " + "\n  ".join(problems))
        sys.exit(1)
    print("S16: PASS")


if __name__ == "__main__":
    main()
