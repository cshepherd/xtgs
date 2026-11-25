#!/usr/bin/env python3
"""release_image.py IMAGE VERSION [--without NAME]... [--cmd LINE]...: the
release volume (make release).

--without NAME leaves release/shared's entry NAME (a file or a folder, by
its name there in capitals) off the volume; --cmd LINE is one more line of
XTGS.CMD after C=SHARED (VIDEO=TANDY). make lsl-image is the two: the
volume with release/shared/lsl2 on it and a Tandy 1000, which make release
leaves out.

One ProDOS volume, named XTGS (VOLSIZE in the environment, default 800KB:
a 3.5-inch disk), that a IIGS boots from and that GS/OS can launch from:

    PRODOS, XTGS.SYSTEM   ProDOS 8 boots into XT/GS
    XTGS                  the GS/OS application, its resource fork (the
                          Finder icon) with it
    CORE, SVC, XTGS.CMD   what both front ends load; the command is S
    READ.ME               release/READ.ME, @VERSION@ filled in
    SHARED/               drive C:, the folder FreeDOS boots from:
                          third_party/freedos/fd/SHARED (the kernel,
                          FreeCOM, GW-BASIC, the demos) without
                          EGADEMO.BAS, which the GW-BASIC here cannot run,
                          and with release/shared/ and the folders in
                          it, to any depth (AUTOEXEC.BAT, more demos,
                          programs). A file there is text, and given
                          DOS's line ends and the ProDOS type TXT, when
                          its extension says so (TEXT_EXT) and its bytes
                          are text; any other goes as it is, type BIN.
                          A name must be one that both ProDOS and DOS
                          can hold: letters, digits and _, 8 at most, and
                          an extension of 3 at most; one with a _ or a
                          digit at its start is stored the way the
                          shared drive spells it (prodos_name)
    Icons/Desktop         names the application for the Finder, so that
                          its icon shows before the first launch

It takes the built files from build/ (the Makefile's rule sees to them).
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CADIUS = os.path.join(HERE, "cadius_strict.sh")
B = os.path.join(ROOT, "build")
FD = os.path.join(ROOT, "third_party", "freedos", "fd", "SHARED")
REL = os.path.join(ROOT, "release")
VOL = "XTGS"
LEFT_OUT = {"EGADEMO.BAS"}
NEEDED = {"KERNEL.SYS", "COMMAND.COM", "FDCONFIG.SYS", "GWBASIC.EXE"}
TEXT_EXT = {"BAT", "BAS", "TXT", "ME", "DOC", "INI", "CFG", "SYS"}
NAME = re.compile(r"(?=[A-Z0-9_]{1,8}(\.|$))[A-Z0-9][A-Z0-9_]*(\.[A-Z0-9]{1,3})?$")
SKIP = {".DS_Store"}


def is_text(name, data):
    """A text file by its extension, and nothing in it that text does not have
    (a tokenized .BAS and a device driver named .SYS are not)."""
    ext = name.rsplit(".", 1)[1] if "." in name else ""
    return ext in TEXT_EXT and all(b in (9, 10, 13) or 32 <= b < 127 for b in data)


def prodos_name(name):
    """The shared drive's ProDOS spelling of a DOS name (docs/share.md): a _ is
    a dot (and a name with one and no extension ends in a dot), and X.. goes
    before a digit that starts it."""
    if "_" in name:
        name = name.replace("_", ".") + ("" if "." in name else ".")
    return "X.." + name if name[0].isdigit() else name


def add_tree(src, dst, without=()):
    """release/shared and what is below it, into the staged folder."""
    for entry in sorted(os.listdir(src)):
        if entry in SKIP or entry.upper() in without:
            continue
        path, name = os.path.join(src, entry), entry.upper()
        if not NAME.match(name):
            sys.exit(f"release_image: {path}: not a name ProDOS and DOS can both hold "
                     "(letters, digits and _: 8, and 3 letters or digits after one dot)")
        name = prodos_name(name)
        if os.path.isdir(path):
            os.makedirs(os.path.join(dst, name), exist_ok=True)
            add_tree(path, os.path.join(dst, name))
            continue
        with open(path, "rb") as f:
            data = f.read()
        for old in os.listdir(dst):                 # it replaces the FreeDOS folder's file of the name
            if old.split("#")[0] == name:
                os.remove(os.path.join(dst, old))
        if is_text(name, data):
            data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
            name += "#040000"
        else:
            name += "#060000"
        with open(os.path.join(dst, name), "wb") as f:
            f.write(data)


def cadius(*args):
    subprocess.run([CADIUS, *args, "--quiet"], check=True, stdout=subprocess.DEVNULL)


def main():
    image, version = sys.argv[1], sys.argv[2]
    without, lines, rest = set(), [], sys.argv[3:]
    while rest:
        if len(rest) < 2 or rest[0] not in ("--without", "--cmd"):
            sys.exit(__doc__)
        if rest[0] == "--without":
            without.add(rest[1].upper())
        else:
            lines.append(rest[1])
        rest = rest[2:]
    size = os.environ.get("VOLSIZE", "800KB")
    stage = tempfile.mkdtemp()
    try:
        def put(src, name):
            shutil.copyfile(src, os.path.join(stage, name))
            return os.path.join(stage, name)

        root = [put(os.path.join(ROOT, "res", "PRODOS"), "PRODOS#FF0000"),
                put(os.path.join(B, "xtgs"), "XTGS.SYSTEM#FF2000"),
                put(os.path.join(B, "xtgs16"), "XTGS#B30000"),
                put(os.path.join(B, "core"), "CORE#060000"),
                put(os.path.join(B, "svc"), "SVC#060000"),
                put(os.path.join(B, "jit"), "JIT#060000")]      # (used only when a line of XTGS.CMD says JIT=ON)
        if "FPU=8087" in lines:                                 # the 8087 only on a volume that asks for it, as long
            root.append(put(os.path.join(B, "fpu"), "FPU#060000"))  # until M9.4/M9.5 and a real IIGS (docs/8087.md)
        fork = put(os.path.join(B, "xtgs16.rfork"), "XTGS#B30000_ResourceFork.bin")
        with open(os.path.join(stage, "XTGS.CMD#040000"), "w", newline="") as f:
            f.write("".join(l + "\r" for l in ["S", "C=SHARED"] + lines))
        root.append(os.path.join(stage, "XTGS.CMD#040000"))
        with open(os.path.join(REL, "READ.ME")) as f:
            text = f.read().replace("@VERSION@", version)
        with open(os.path.join(stage, "READ.ME#040000"), "w", newline="") as f:
            f.write(text.replace("\n", "\r"))
        root.append(os.path.join(stage, "READ.ME#040000"))

        shared = os.path.join(stage, "SHARED")
        os.mkdir(shared)
        have = set()
        for name in sorted(os.listdir(FD)):
            dos = name.split("#")[0]
            if dos in LEFT_OUT:
                continue
            shutil.copyfile(os.path.join(FD, name), os.path.join(shared, name))
            have.add(dos)
        missing = NEEDED - have
        if missing:
            sys.exit(f"release_image: {FD} lacks {', '.join(sorted(missing))}")
        add_tree(os.path.join(REL, "shared"), shared, without)

        if os.path.exists(image):
            os.remove(image)
        cadius("CREATEVOLUME", image, VOL, size)
        for f in root:
            cadius("ADDFILE", image, f"/{VOL}/", f)
        cadius("ADDFOLDER", image, f"/{VOL}/SHARED", shared)
        # the Finder's Desktop file for this volume, from the bundle in the fork
        open(os.path.join(stage, "Desktop#C90003"), "w").close()
        subprocess.run([sys.executable, "-I", os.path.join(HERE, "gsos_rfork.py"), "desktop",
                        "--fork", fork, "--path", f":{VOL}:XTGS",
                        "-o", os.path.join(stage, "Desktop#C90003_ResourceFork.bin")],
                       check=True, stdout=subprocess.DEVNULL)
        cadius("CREATEFOLDER", image, f"/{VOL}/Icons")
        cadius("ADDFILE", image, f"/{VOL}/Icons/", os.path.join(stage, "Desktop#C90003"))
    finally:
        shutil.rmtree(stage, ignore_errors=True)
    out = subprocess.run([CADIUS, "CATALOG", image], check=True, capture_output=True, text=True).stdout
    for line in out.splitlines():
        if line.strip() and not line.startswith("-"):
            print(line[:78].rstrip())


if __name__ == "__main__":
    main()
