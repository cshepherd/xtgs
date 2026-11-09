# DOS program compatibility matrix

Independently sourced, era-appropriate DOS programs run unmodified under
XT/GS Mode A (`make test-dos`; `tools/fetch_dos.py` fetches them into
`third_party/`, which is git-ignored). "Unmodified" means the exact
published binary, byte for byte. Status as of M3 (2026-11-08).

| Program | Source | License | Type | Result | Services used beyond M2 |
|---|---|---|---|---|---|
| FIND.EXE | MS-DOS 2.0 (microsoft/MS-DOS) | MIT | MZ .EXE | **pass** — filters file lines to stdout | 3Dh open, 3Fh read, 3Eh close, parse |
| DEBUG.COM | MS-DOS 2.0 | MIT | .COM | **pass** — register dump, disassembly, `q` | 25h/35h vectors, get-in-vars (52h) |
| EDLIN.COM | MS-DOS 2.0 | MIT | .COM | **pass** — loads a file, lists lines, quits | FCB open 0Fh, FCB random block read 27h, SET_DMA 1Ah |
| TREE.COM | FreeDOS 1.3 | GPL-2.0 | .COM | **pass** — directory tree of C:\ | 47h getcwd, 4Eh/4Fh find first/next, 19h drive |
| DEBUG.COM | FreeDOS 1.3 (DEBUG/X) | MIT | .COM | **pass** — register dump, disassembly | 25h/35h, 48h alloc |
| FIND.COM | FreeDOS 1.3 | GPL-2.0 | .COM | **partial** — exits after reading the DOS version; no output | 30h; stops before opening the file |
| SORT.EXE | MS-DOS 2.0 | MIT | MZ .EXE | **fail** — reads stdin, then writes memory garbage and jumps into the BIOS segment; a memory-management assumption not yet met | 3Fh on redirected stdin works; the crash is after reading |

Redirection (`< FILE`, `> FILE`), handle-based file I/O, FCB file I/O
(sequential and random, single and block), find first/next and `.EXE`
relocation are all exercised by the passing programs and by the test
programs in `tests/com/` (`typefile`, `fcbread`, `catin`).

## Reproducing

```
make test-dos                 # every program above
make test-dos DOS=edlin       # one
```

The verdicts are the judge's `stdout_contains` checks plus the exit code
and the "unhandled service calls" count; a program that calls an
unimplemented INT 21h function is reported (function number named) so the
next function to implement is always visible.

## Known gaps driving the remaining failures

- **SORT.EXE** dumps memory to stdout, which points at a memory-control
  assumption (likely `INT 21h/4Ah` resize semantics or the MCB chain the
  program walks). Handle reads from its redirected stdin are correct
  (`tests/com/catin` passes on the same redirect).
- **FreeDOS FIND.COM** checks the DOS version (we report 3.30) and exits
  before opening its file; it likely needs a different reported version or
  an LFN/IOCTL probe we answer in a way it dislikes.
