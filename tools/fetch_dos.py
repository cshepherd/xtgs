#!/usr/bin/env python3
"""Fetch the independently sourced DOS programs the M3 tests run, into
third_party/ (git-ignored): the MS-DOS 2.0 utilities Microsoft published
under the MIT license (github.com/microsoft/MS-DOS, v2.0/bin), unmodified.

    fetch_dos.py            fetch what is missing
"""
import os
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MSDOS = "https://raw.githubusercontent.com/microsoft/MS-DOS/main/"
FREEDOS = "https://www.ibiblio.org/pub/micro/pc-stuff/freedos/files/repositories/1.3/base/"
FILES = {
    "freedos": [(n + ".zip", FREEDOS + n + ".zip") for n in
                ("kernel", "freecom", "debug", "tree", "find", "sort")],
    "msdos2": [("LICENSE", MSDOS + "LICENSE")] +
              [(n, MSDOS + "v2.0/bin/" + n) for n in
               ("DEBUG.COM", "EDLIN.COM", "FIND.EXE", "SORT.EXE", "MORE.COM", "EXE2BIN.EXE",
                "FC.EXE", "COMMAND.COM", "CHKDSK.COM", "README.DOC", "UTILITY.DOC")],
}


def main():
    for d, items in FILES.items():
        out = os.path.join(ROOT, "third_party", d)
        os.makedirs(out, exist_ok=True)
        for name, url in items:
            path = os.path.join(out, name)
            if os.path.exists(path):
                continue
            with urllib.request.urlopen(url, timeout=60) as r, open(path + ".part", "wb") as f:
                f.write(r.read())
            os.replace(path + ".part", path)
            print(f"{d}/{name}: {os.path.getsize(path)} bytes")


if __name__ == "__main__":
    main()
