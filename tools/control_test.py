#!/usr/bin/env python3
"""control_test.py [soft|hard|state|drop|quit] [--show]: the desk accessory "XTGS Control"
(make test-control; docs/control.md).

FreeDOS boots from a copy of the folder third_party/freedos/fd/SHARED
(command S) whose AUTOEXEC.BAT runs MARK.COM (tests/demo/mark.asm: it prints
the word at F800:0000, which nothing else uses, and makes it BEEF). The harness then holds
Control-Apple-Esc, finds "XTGS Control" in the desk accessories' menu,
opens it, asks for the reboot, confirms and quits the menu. The PC must
start again (the front end's exit code for the request, the core running)
and MARK must print BEEF after a soft reboot, 0000 after a hard one.

Work files in build/control/. One boot, about 230 emulated seconds. Run it
under XTGS_LAYOUT=alt and XTGS_FRONT=s16 by hand, like test-share.
"""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "mame"))
import mamerun  # noqa: E402
import symbols  # noqa: E402

FD = os.path.join(ROOT, "third_party", "freedos", "fd", "SHARED")
K1, K2, K3 = ":macadb:KEY1", ":macadb:KEY2", ":macadb:KEY3"
MENU = 7200                       # FreeDOS is at its prompt well before
# The menu is in the order of the names: after the ROM's two, "XTGS Control"
# is the third line when ProDOS 8 was booted, and Quit the next. From GS/OS
# the system disk's own accessories are there too (the System 6 volume of
# the tests has three before it and one after): CONTROL_DOWNS and
# CONTROL_QUIT say otherwise for another disk.
S16 = os.environ.get("XTGS_FRONT") == "s16"
DOWNS = int(os.environ.get("CONTROL_DOWNS", "5" if S16 else "2"))
QUIT = int(os.environ.get("CONTROL_QUIT", "2" if S16 else "1"))
RES = 0x050000


def tap(at, name, port=K3, hold=8):
    return [{"at": at, "press": name, "port": port, "value": 1},
            {"at": at + hold, "press": name, "port": port, "value": 0}]


def page(dump):
    """The 40-column text page as its 24 lines."""
    rows = []
    for row in range(24):
        base = (row & 7) * 0x80 + (row >> 3) * 0x28
        rows.append("".join(chr(b & 0x7F) if 32 <= (b & 0x7F) < 127 else "." for b in dump[base:base + 40]))
    return rows


def menu(t, digit):
    """The keys from Control-Apple-Esc at frame t to the menu's Quit, with the
    accessory's choice `digit` between; and the frame they end at."""
    seq = tap(t, "Control", hold=40) + tap(t + 2, "Command / Open Apple", hold=36) + tap(t + 10, "Esc", hold=20)
    t += 200
    for _ in range(DOWNS):
        seq += tap(t, "Down Arrow")
        t += 40
    seq += tap(t, "Return", K2)                              # the accessory
    seq += tap(t + 80, digit, K1)                            # the choice
    seq += tap(t + 140, "Space")                             # "Press a key"
    t += 200
    for _ in range(QUIT):
        seq += tap(t, "Down Arrow")
        t += 40
    seq += tap(t, "Return", K2)                              # Quit
    return seq, t


def main():
    what = ([a for a in sys.argv[1:] if not a.startswith("--")] or ["soft"])[0]
    show = "--show" in sys.argv[1:]
    work = os.path.join(ROOT, "build", "control")
    os.makedirs(work, exist_ok=True)
    folder = os.path.join(work, "SHARED")
    shutil.rmtree(folder, ignore_errors=True)
    shutil.copytree(FD, folder)
    subprocess.run(["nasm", "-f", "bin", "-o", os.path.join(folder, "MARK.COM#060000"),
                    os.path.join(ROOT, "tests", "demo", "mark.asm")], check=True)
    with open(os.path.join(folder, "AUTOEXEC.BAT#040000"), "w", newline="\r\n") as f:
        f.write("@ECHO OFF\nMARK\n")
    cmd = os.path.join(work, "XTGS.CMD#040000")
    with open(cmd, "w") as f:
        f.write("S\rC=SHARED\r")
    stage = os.path.join(ROOT, "build", "stage")
    po = os.path.join(work, "control.po")
    subprocess.run([os.path.join(HERE, "make_image.sh"), po, os.path.join(stage, "XTGS.SYSTEM#FF2000"),
                    os.path.join(stage, "CORE#060000"), os.path.join(stage, "SVC#060000"), cmd, folder],
                   check=True, capture_output=True, env=dict(os.environ, VOLSIZE="4096KB"))
    syms = symbols.read(os.path.join(ROOT, "build", "xtgs.lst"))
    late = mamerun.GSOS_BOOT * 60 if S16 else 0
    if what == "state":
        # saved at the prompt; MARK twice (the word goes on, the screen fills);
        # restored; MARK once more, which must find what the first one left
        seq, t = menu(MENU, "3  #")
        seq += [{"at": t + 1800, "coded": "MARK{ENTER}"}, {"at": t + 2600, "coded": "MARK{ENTER}"}]
        more, t = menu(t + 3400, "4  $")
        seq += more + [{"at": t + 1800, "coded": "MARK{ENTER}"}]
        end = t + 2800
    elif what == "drop":
        # a state saved, then a soft reboot: the state must be gone with the PC it was of
        seq, t = menu(MENU, "3  #")
        more, t = menu(t + 1800, "1  !")
        seq += more
        end = t + 6600
    else:
        seq, t = menu(MENU, {"soft": "1  !", "hard": "2  @", "quit": "5  %"}[what])
        end = t + int(os.environ.get("CONTROL_AFTER", "6600"))   # (frames the PC has to start again)
    inputs = [dict(i, at=i["at"] + late, after="start") for i in seq]
    r = mamerun.run(po, waits=[(syms["mb_magic"], 0x5A5A)],
                    dumps=[("fb", 0x2B8000, 4000), ("text", 0xE00400, 0x400), ("mb", syms["mb_stage"], 8),
                           ("ctl", RES + 0x954, 4), ("stat", RES + 0xA80, 2), ("mark", 0x2F8000, 2),
                           ("shr", 0xE12000, 0x8000)],
                    seconds=end / 60, settle=5, inputs=inputs)
    if r["status"] == "no-output":
        print(r.get("mame_output", ""))
        sys.exit("control_test: MAME produced no result")
    fb = bytes.fromhex(r["dumps"]["fb"]["hex"])
    rows = [bytes(fb[y * 160 + x * 2] for x in range(80)).decode("cp437").rstrip("\0 ") for y in range(25)]
    text = page(bytes.fromhex(r["dumps"]["text"]["hex"]))
    mb = bytes.fromhex(r["dumps"]["mb"]["hex"])
    ctl = bytes.fromhex(r["dumps"]["ctl"]["hex"])
    stat = bytes.fromhex(r["dumps"]["stat"]["hex"])[0]
    stage_now, magic, code = mb[0], mb[2] | mb[3] << 8, mb[4] | mb[5] << 8
    if show:
        print("\n".join(rows))
        print("\n".join(x for x in text if x.strip()))
        print("the word at F800:0000:", r["dumps"]["mark"]["hex"])
        print(f"stage {stage_now:#x}, magic {magic:#06x}, exit code {code:#06x}, CTL_REQ/CTL_LIVE {ctl.hex()}, "
              f"CTL_STAT {stat}, {r['status']} at frame {r['frame']}")
    marks = [x for x in rows if x.startswith("MARK=")]
    bad = []
    if what == "quit":
        # (the GS/OS application gives its front page back as it quits, within
        # the frame, and the tests' launcher starts it again: what shows the
        # quit there is a PC booted a second time, MARK finding the first's word)
        if not ((magic == 0x5A5A and code == 0xB0C3) or
                (S16 and code == 0 and stage_now == 8 and marks == ["MARK=BEEF"])):
            bad.append(f"XT/GS did not quit by the request (magic {magic:#06x}, exit code {code:#06x})")
        if bad:
            sys.exit("FAIL control (quit): " + "; ".join(bad))
        print("PASS control: Control-Apple-Esc, XTGS Control, Quit: the front end left with the request's "
              "exit code and waited for no key")
        return
    if what == "state":
        import textshr
        if stat != 1:
            bad.append(f"no state is saved (CTL_STAT {stat})")
        if stage_now != 8 or ctl[2] != 1 or code != 0:
            bad.append(f"the PC did not just go on (stage {stage_now:#x}, CTL_LIVE {ctl[2]}, exit code {code:#06x})")
        if marks != ["MARK=0000", "MARK=BEEF"]:
            bad.append(f"the screen has {marks}: after the restore it should be the one saved, "
                       "['MARK=0000'], and MARK run once more, 'MARK=BEEF'")
        stale = textshr.mismatches(fb, bytes.fromhex(r["dumps"]["shr"]["hex"]))
        if stale:
            bad.append(f"{len(stale)} cells of the text screen are not what the SHR shows")
        if bad:
            sys.exit("FAIL control (state): " + "; ".join(bad) + "\n" + "\n".join(rows))
        print("PASS control: a state saved at the prompt, MARK run twice, the state restored: the screen and "
              "the memory are the saved ones, and MARK goes on from there (MARK=BEEF)")
        return
    if what == "drop":
        if code != 0xB0C1 or stage_now != 8 or marks != ["MARK=BEEF"]:
            bad.append(f"the PC was not restarted (exit code {code:#06x}, stage {stage_now:#x}, {marks})")
        if stat != 0:
            bad.append(f"the state saved before the reboot is still there (CTL_STAT {stat})")
        if bad:
            sys.exit("FAIL control (drop): " + "; ".join(bad))
        print("PASS control: a state saved, then a soft reboot: the PC started again and has no saved state")
        return
    hard = what == "hard"
    if code != (0xB0C2 if hard else 0xB0C1):
        bad.append(f"the core's last exit code is {code:#06x}: the request did not reach the front end")
    if stage_now != 8 or ctl[2] != 1:
        bad.append(f"no PC is running at the end (stage {stage_now:#x}, CTL_LIVE {ctl[2]})")
    want = "MARK=0000" if hard else "MARK=BEEF"
    if marks != [want]:
        bad.append(f"after the {what} reboot the screen has {marks}, not [{want!r}]")
    if bad:
        sys.exit(f"FAIL control ({what}): " + "; ".join(bad) + "\n" + "\n".join(rows))
    print(f"PASS control: Control-Apple-Esc, XTGS Control, a {what} reboot: FreeDOS started again and "
          f"{'its memory was cleared' if hard else 'its memory was kept'} ({want})")


main()
