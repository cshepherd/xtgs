#!/usr/bin/env python3
"""The layout (src/include/layout.s) for the host-side tools: the bank of
each region and the page of each bank-$00 area.

    layout.py                 print the assembled layout and the test layout

regions()   -> {NAME: (RG_ index, assembled bank or page)}; a name in
               PAGES is a bank-$00 area, the others are bank regions
equates()   -> the file's other equates
mailbox()   -> src/include/mailbox.s's

The harness works in ASSEMBLED addresses: the judges' constants and the
listings' labels (tools/symbols.py) all say where a thing is when every
region has its first choice, which is what a normal boot gives.

XTGS_LAYOUT in the environment says they are somewhere else:

    alt             the loader's test layout (below)
    probe           wherever the loader puts them: no translation and no
                    check; mamerun's result["layout"] says where (the first
                    of two runs under GS/OS, tools/check_gsos.py). The
                    mailbox itself is read at its assembled page.
    GUEST=40,...    an explicit list (hex banks and pages; spell() makes
                    one from a probe run's result)

With alt:

  * tools/make_image.sh puts a '+' before the command in XTGS.CMD. The
    loader then refuses each region its assembled bank and takes the
    first free one (claim_region in src/sys/xtgs.s), and puts each
    bank-$00 area at its NAME_ALTPG page (set_pages), its own front
    page with the mailbox included;
  * mamerun.run() passes every address it is given through to_actual()
    and the profile's addresses back through to_assembled(), and checks
    what the loader recorded in MB_LAYOUT against alt() below.

The banks of alt() are what a clean ProDOS 8 boot of an 8 MB machine
gives: the guest takes the first 1 MiB-aligned megabyte ($10), a disk
image the first 23 banks after it, and the one-bank regions fill in from
$02. The data region (VEC) is sized by its file and no tool reads it, so
it is not translated; its bank only has to differ from the assembled one.
The pages are layout.s's NAME_ALTPG equates.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LAYOUT_S = os.path.join(ROOT, "src", "include", "layout.s")

sys.path.insert(0, HERE)
import symbols  # noqa: E402  (evaluate(): Merlin32's left-to-right expressions)

# The lines tools/gen_reloc.py rewrites: NAME_BANK = $xx, NAME_PAGE = $xx.
PLACE_LINE = re.compile(r"^(\w+)_(BANK|PAGE)(\s*=\s*)\$([0-9A-Fa-f]{2})\b", re.M)
EQU_LINE = re.compile(r"^(\w+)[ \t]*=[ \t]*([^;\s]+)", re.M)

# banks a region spans (the data region: unknown here)
BANKS = {"CORE": 1, "SVC": 1, "RES": 1, "JIT": 4, "GUEST": 16, "DISK": 23}
# pages a bank-$00 area spans
PAGES = {"ZP": 1, "MBX": 1, "PATH": 1, "XFER": 32, "IOB": 32}
# the '+' banks on a clean 8 MB ProDOS 8 boot (JIT for K and for a PC, DISK only for D)
ALT_BANKS = {"GUEST": 0x10, "DISK": 0x20, "CORE": 0x02, "SVC": 0x03, "RES": 0x04, "JIT": 0x05}


def _text():
    with open(LAYOUT_S) as f:
        return f.read()


def _equates(text, env):
    out = dict(env)
    for name, expr in EQU_LINE.findall(text):
        v = symbols.evaluate(expr, out)
        if v is not None:
            out[name] = v
    return out


def equates():
    return _equates(_text(), {})


def mailbox():
    """The front page's addresses (src/include/mailbox.s), as assembled."""
    with open(os.path.join(ROOT, "src", "include", "mailbox.s")) as f:
        return _equates(f.read(), equates())


def regions():
    eq = equates()
    out = {}
    for name, kind, _, val in PLACE_LINE.findall(_text()):
        if f"RG_{name}" not in eq:
            sys.exit(f"layout.py: {name}_{kind} has no RG_{name} in layout.s")
        if (kind == "PAGE") != (name in PAGES):
            sys.exit(f"layout.py: {name}_{kind}: PAGES in layout.py says otherwise")
        if (kind == "PAGE") != (eq[f"RG_{name}"] >= eq["RG_BANKS"]):
            sys.exit(f"layout.py: RG_{name} is on the wrong side of RG_BANKS for a {kind}")
        out[name] = (eq[f"RG_{name}"], int(val, 16))
    if sorted(r for r, _ in out.values()) != list(range(eq["RG_COUNT"])):
        sys.exit("layout.py: the RG_ indexes in layout.s are not 0..RG_COUNT-1, one a region")
    return out


def alt():
    """{name: bank or page} of the loader's '+' layout."""
    eq = equates()
    return dict(ALT_BANKS, **{n: eq[f"{n}_ALTPG"] for n in PAGES})


def active():
    """The layout the run is asked for, as XTGS_LAYOUT spells it: None
    (assembled), "alt", "probe" or an explicit "NAME=bank,..." list."""
    v = os.environ.get("XTGS_LAYOUT", "")
    if v not in ("", "alt", "probe") and target(v) is None:
        sys.exit(f"XTGS_LAYOUT={v}: want 'alt', 'probe' or NAME=hex,... (a bank or "
                 f"a page) with names from {sorted(BANKS) + sorted(PAGES)}")
    return v or None


def front():
    """The front end the run boots: None (XTGS.SYSTEM, ProDOS 8) or "s16"
    (XTGS, the GS/OS application; XTGS_FRONT in the environment). Under
    s16 the Memory Manager decides every place, so XTGS_LAYOUT translates
    nothing: mamerun's script reads MB_LAYOUT as the run goes."""
    v = os.environ.get("XTGS_FRONT", "")
    if v not in ("", "p8", "s16"):
        sys.exit(f"XTGS_FRONT={v}: want 's16' (or nothing: ProDOS 8)")
    return "s16" if v == "s16" else None


def from_words(words):
    """MB_LAYOUT's words as {name: bank or page}, the claimed ones."""
    return {n: words[rid] for n, (rid, _) in regions().items()
            if (n in BANKS or n in PAGES) and words and words[rid]}


def mover(src, dst):
    """A function taking an address under layout src to layout dst."""
    spans = _spans(src, dst)
    return lambda addr: _move(addr, spans)


def target(v=None):
    """{name: bank or page} the active layout puts each region and area
    at; None when it is the assembled one, or unknown ("probe")."""
    if v is None:
        v = active()
    if v == "alt":
        return alt()
    if not v or v == "probe":
        return None
    out = {}
    for item in v.split(","):
        m = re.fullmatch(r"(\w+)=([0-9A-Fa-f]{1,2})", item.strip())
        if not m or (m.group(1) not in BANKS and m.group(1) not in PAGES):
            return None
        out[m.group(1)] = int(m.group(2), 16)
    return out


def spell(words):
    """MB_LAYOUT's words as an XTGS_LAYOUT value (a probe run's result)."""
    return ",".join(f"{n}={words[rid]:02X}" for n, (rid, _) in
                    sorted(regions().items(), key=lambda kv: kv[1][0])
                    if (n in BANKS or n in PAGES) and words[rid])


def _spans(src, dst):
    """([(first bank, banks, delta)], [(first page, pages, delta)]) mapping
    layout src onto dst."""
    return tuple([(src[n], size[n], dst[n] - src[n]) for n in size if n in src and n in dst]
                 for size in (BANKS, PAGES))


def _move(addr, spans):
    banks, pages = spans
    if addr >> 16:
        for first, count, delta in banks:
            if first <= addr >> 16 < first + count:
                return addr + (delta << 16)
        return addr
    for first, count, delta in pages:
        if first <= addr >> 8 < first + count:
            return addr + (delta << 8)
    return addr


def to_actual(addr):
    """An assembled address, where the active layout has it."""
    if not target():
        return addr
    asm = {n: b for n, (_, b) in regions().items()}
    return _move(addr, _spans(asm, target()))


def to_assembled(addr):
    """The reverse (profile samples, write logs)."""
    if not target():
        return addr
    asm = {n: b for n, (_, b) in regions().items()}
    return _move(addr, _spans(target(), asm))


def check(words):
    """words: MB_LAYOUT as the run left it (RG_COUNT u16s). The problems
    with it under the active layout, as strings (none: [])."""
    out = []
    if active() == "probe":                 # the caller is asking where things are
        return out
    if front() == "s16":                    # GS/OS placed them; '+' still means "not there"
        for name, (rid, asm) in sorted(regions().items(), key=lambda kv: kv[1][0]):
            if words[rid] == asm and active() == "alt":
                out.append(f"{name} is at its assembled {'page' if name in PAGES else 'bank'} "
                           f"${asm:02X} under the '+' layout")
        return out
    tgt = target()
    for name, (rid, asm) in sorted(regions().items(), key=lambda kv: kv[1][0]):
        got = words[rid]
        what = "page" if name in PAGES else "bank"
        if got == 0:                        # not claimed (or the loader stopped first)
            continue
        if name not in BANKS and name not in PAGES:     # the data region: no tool reads it
            if got == asm and active() == "alt":
                out.append(f"{name} is at its assembled bank ${asm:02X} under the '+' layout")
            continue
        want = tgt.get(name, asm) if tgt else asm
        if got != want:
            out.append(f"{name} is at {what} ${got:02X}, the harness expects ${want:02X}")
    return out


def main():
    print(f"layout: {active() or 'assembled'}")
    a = alt()
    for name, (rid, asm) in sorted(regions().items(), key=lambda kv: kv[1][0]):
        what = "page" if name in PAGES else "bank"
        other = f"${a[name]:02X}" if name in a else "(by size)"
        print(f"  {rid:2d} {name:6s} assembled {what} ${asm:02X}   '+' layout {other}")


if __name__ == "__main__":
    main()
