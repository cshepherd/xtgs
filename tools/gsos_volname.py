#!/usr/bin/env python3
"""gsos_volname.py OLD NEW DIR - a System folder copied to a volume of
another name: the GS/OS pathnames in its files that begin with the old
volume's name get the new one.

Only a pathname in a GS/OS result buffer is touched: a word with the
buffer's size, a word with the text's length, the text ":OLD:..." (any
case), and zeros to the buffer's end. The text and its length are rewritten
in place, so the file keeps its size and nothing in it moves; a name too
long for the buffer is refused. A pathname held any other way (packed
between other fields, as a launcher's list has them) is left as it is:
there is no telling what follows it. Files over 64 KB and resource forks are
not read. Each change is printed; with no difference between the names
nothing is done.

Why: GS/OS asks for the disk by name, and waits, when something in the
System folder opens a file on a volume that is not there. DeskMaker's
System/DeskConfig holds the pathname of the desktop picture that way.
"""
import os
import sys


def patch(data, old, new):
    """The data with the ":old:..." of every result buffer renamed, and how many."""
    key = b":" + old.lower() + b":"
    low = data.lower()
    out = bytearray(data)
    n = 0
    at = low.find(key)
    while at >= 0:
        if at >= 4:
            size = data[at - 4] | data[at - 3] << 8
            length = data[at - 2] | data[at - 1] << 8
            text = data[at:at + length]
            end = at - 4 + size
            if (len(key) <= length <= size - 4 and end <= len(data) and all(32 <= c < 127 for c in text)
                    and not any(data[at + length:end])):
                path = b":" + new + text[len(key) - 1:]
                if len(path) > size - 4:
                    sys.exit(f"gsos_volname: no room for the longer name in {text.decode()}")
                out[at - 2:at] = len(path).to_bytes(2, "little")
                out[at:end] = path + bytes(end - at - len(path))
                n += 1
        at = low.find(key, at + len(key))
    return bytes(out), n


def main():
    old, new, top = sys.argv[1].encode(), sys.argv[2].encode(), sys.argv[3]
    if old.lower() == new.lower():
        return
    for folder, _, names in os.walk(top):
        for name in sorted(names):
            p = os.path.join(folder, name)
            if name.endswith("_ResourceFork.bin") or name == "_FileInformation.txt" or os.path.getsize(p) > 65536:
                continue
            with open(p, "rb") as f:
                data = f.read()
            got, n = patch(data, old, new)
            if n:
                with open(p, "wb") as f:
                    f.write(got)
                print(f"gsos_image: {os.path.relpath(p, top).split('#')[0]}: {n} pathname(s) on "
                      f"/{old.decode()} now on /{new.decode()}")


if __name__ == "__main__":
    main()
