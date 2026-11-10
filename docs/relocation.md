# Relocation: banks and bank-`$00` pages

XT/GS used to be assembled for fixed banks (`CORE` at `$03`, `SVC` at `$04`,
results in `$05`, the guest in `$20`-`$2F`, the disk image from `$50`), and
the loader refused to run when the Memory Manager would not give it exactly
those. That holds on a bare ProDOS 8 boot of an 8 MB machine, and nowhere
else: launched from GS/OS, banks `$03`-`$06` are already taken.

Now the banks are first choices. The loader claims each region wherever
there is room and fixes the two images to match (stage 1). The bank-`$00`
addresses `CORE` and `SVC` use are first choices too, a page number each,
fixed up by the same list (stage 2): the two images no longer say where
anything is, and everything that is still a ProDOS 8 fact lives in
`XTGS.SYSTEM`. A second front end, a native GS/OS application, supplies
the same things from GS/OS instead (stage 3, at the end).

## Regions

`src/include/layout.s` is the only place a bank number is written, and the
only place a bank-`$00` page is.

| Region | Assembled bank | Banks | Claimed |
| --- | --- | --- | --- |
| `CORE` | `$03` | 1 | always |
| `SVC` | `$04` | 1 | always |
| `RES` (results, trace ring, queues, capture) | `$05` | 1 | always |
| `JIT` (M6 code cache and block map) | `$06` | 1 | command `K` |
| `GUEST` (the PC's megabyte) | `$20` | 16 | always |
| `DATA` (the vector file) | `$30` | by file size | command `V` |
| `DISK` (Mode B disk image) | `$50` | 23 | command `D` |

The bank-`$00` areas, each a whole number of pages:

| Area | Assembled page | Size | What |
| --- | --- | --- | --- |
| `ZP` | `$10` | 1 page | the guest's CPU state: the direct page while the core runs (`GUEST_DP`) |
| `MBX` | `$20` | 1 page | the front page: the file-call entry and the mailbox (`MB_BASE`) |
| `PATH` | `$0C` | 1 page | pathnames and the prefix for file calls (`src/svc/files.s`) |
| `XFER` | `$40` | 8 KB | transfer buffer between a file and the guest's memory |
| `IOB` | `$60` | 8 KB | the MLI's 1 KB I/O buffers, one an open file |

Every other address in the tree derives from those equates (`CORE_BASE`,
`H_TXT = GUEST_BASE+$B8000`, `TRACE_BASE = RES_BASE+$4000`,
`GUEST_DP = ZP_PAGE*$100`, `MB_STAGE = MB_BASE+$10`, ...). Do not write a
bank literal or a bank-`$00` address anywhere else: the build cannot
relocate what it cannot see change (below).

The guest's megabyte must start at a bank that is a multiple of `$10`: the
20-bit wrap is `AND #$000F` / `ORA #GUEST_BANK`. The loader only offers it
such banks, and `layout.s` and the loader both assert it.

## How an image is made relocatable

Merlin32 here produces plain binaries, not OMF, so there are no relocation
records. `tools/gen_reloc.py` finds the bank bytes and the page bytes by
experiment instead:

1. Merlin32 assembles the link for the banks in `layout.s`
   (`build/core.bin`, `build/svc.bin`).
2. `gen_reloc.py` copies `src/` to `build/reloc/`, rewrites `layout.s`
   with every region moved by a different amount (region *r* by `1 << r`),
   assembles again, and does it a second time with other amounts
   (3, 5, 7, 11, 48, 13, 17). Then twice more with the banks back in place
   and the pages moved (area *a* by `1 << a`, then by 3, 5, 7, 11, 13).
3. A byte that differs must differ by exactly one region's amount in the
   first variant of a pair and by the same region's amount in the second.
   That byte holds that region's bank, or the high byte of an address in
   that area.
4. Anything else fails the build with the offsets: a length change, a byte
   that follows two regions or both a bank and a page, a bank shifted or
   doubled. Those are things a byte-add at load time could not fix.

The list is appended to the image (`build/core`, `build/svc`, and so the
`CORE` and `SVC` files on the volume):

```
groups   one per region or area the image names:
           region (u8, an RG_ index), assembled bank or page (u8),
           count (u16), count x offset (u16) into the image
u16      bytes of groups
u16      RELOC_MAGIC ($5258)
```

Today `CORE` has 79 bank bytes and 299 page bytes (788 bytes of list), `SVC`
262 and 124 (812 bytes). Run with everything at its assembled place, the
loaded images are byte-identical to what the fixed-address build produced.

What gets listed, typically: the bank byte of a long operand
(`lda >H_BDA+x`, `jsl SVC_BASE+15`), `#^label` immediates, `ora #GUEST_BANK`,
and the operands of `MVN`. A 16-bit `ora #GUEST_BANK` is fine: only its low
byte changes. For a page: the high byte of an absolute or long operand in
bank `$00` (`jmp (NEXTVEC)`, 142 of `CORE`'s 276 `ZP` bytes;
`sta >MB_RUNIDX`; `jsl MB_FILECALL`), of a 16-bit immediate (a register's
address for a ModR/M pointer, `lda #GUEST_DP+rAX`, most of the rest;
`lda #PATHBUF0`) and of a `da`. Direct-page operands (`lda rAX`) hold no page and need no
fixing: they follow D.

`XTGS.SYSTEM` goes through the same step (`build/xtgs.bin` is the plain
assembly, `build/xtgs` the file on the volume) for one area only, its own
front page: 104 bytes, used by the `+` layout below. `gen_reloc.py` also
writes the file's length into it at `MB_SELFLEN`, which is how the loader
finds the end of its own list.

## What the loader does

`claim_region` (`src/sys/xtgs.s`), for the guest first, then the disk image
(`D`), `CORE`, `SVC`, `RES`, the translator (`K`), and later the vector file:

1. Ask the Memory Manager for a fixed-address handle at the assembled bank.
2. If that fails, try each bank from `$02` to `$E0` in turn (multiples of
   `$10` only for the guest) and take the first that works.
3. Record the bank in `MB_LAYOUT` (`MB_BASE+$82`, one word a region in
   `RG_` order, 0 = not claimed).

The pages come from `set_pages`, before any of that: the assembled ones.
Under ProDOS 8 they are this program's to hand out (bank `$00` below
`$BF00` belongs to the system file, and the TN #27 reservation covers it on
a direct boot), so there is nothing to ask the Memory Manager for. They go
into `MB_LAYOUT` after the banks, one word an area.

The loader prints the result (`BANKS 03 04 05 00 20 00 00` and
`PAGES 10 20 0C 40 60`), loads each file into the bank its region got, and
then `reloc_all` walks the list at the end of `CORE` and of `SVC`
(`reloc_image`), adding (actual - assembled) to each listed byte. A group
for a region that was not claimed is left alone. The `JSL` into the core is
patched the same way.

The loader also sets the ProDOS prefix to the directory of its own pathname
when a launcher left one at `$0280`, so `CORE`, `SVC`, `XTGS.CMD` and the
disk image are found beside `XTGS.SYSTEM` whatever the launcher's prefix was.

Loader error stages:

| Stage | Meaning |
| --- | --- |
| `$43`-`$46` | a TN #27 range could not be reserved (direct boot only) |
| `$47` + `RG_` index | no room for that region anywhere (`$47` CORE ... `$4B` GUEST ... `$4D` DISK); `MB_DBG_*` names the block in the way of the first choice |
| `$70` | `XTGS.SYSTEM` has no valid relocation list of its own (`+` only) |
| `$71` / `$72` | `CORE` / `SVC` has no valid relocation list |

## What `CORE` and `SVC` expect of a front end

`XTGS.SYSTEM` is one front end and the GS/OS application `XTGS` the
other; this is the whole of what the two images need from either.

- **Memory.** A bank for each region the command needs and pages for the
  five areas, recorded in `MB_LAYOUT`; the images loaded and their lists
  applied. The guest's megabyte starts at a multiple of `$10`. `ZP` is the
  direct page, so like any direct page it must be page-aligned; the list
  can only move whole pages anyway.
- **Entry.** `JSL` to offset 0 of `CORE`, native mode, 16-bit A and index,
  with a stack of its own (`XTGS.SYSTEM` gives `$0800`-`$0BFF`). `CORE`
  sets D and the data bank itself and `RTL`s with its exit code in A; the
  caller restores its own D, DBR and stack.
- **The front page** (`src/include/mailbox.s`), at `MBX`: `+$04` is
  `MB_FILECALL`, a `JSL` target callable in native mode at any register
  width, and from `+$10` the mailbox: the command line (`MB_CMD`), the
  file-call parameters, `MB_LAYOUT`, and the results the judges read. The
  first four bytes and `+$08` are the front end's own.
- **Files.** `MB_FILECALL` performs the ProDOS 8 MLI call whose command
  byte is in `MB_MLI_CMD` with the parameter list at `MB_MLI_PARMS`, and
  returns the MLI's error in A and `MB_MLI_RES` (0 = done), preserving D,
  DBR and P. `SVC` (`src/svc/files.s`, the only caller) builds ordinary
  MLI lists - `CREATE`, `OPEN`, `READ`, `WRITE`, `CLOSE`, `GET_MARK`,
  `SET_EOF`, `GET_EOF`, `SET_FILE_INFO` and the like - whose pointers are
  bank-`$00` addresses in `PATH` (pathnames), `XFER` (data) and `IOB` (the
  buffer `OPEN` wants). A front end without an MLI under it has to honour
  those lists; the buffers are where it is told, not where ProDOS likes.
- **Interrupts** are on while a guest runs (`docs/sound.md`). The DOC
  timer's handler is `SVC`'s own, entered through `$E1:002C`; the firmware
  gets there on page 1 of bank `$00`, which `SVC` saves and restores
  around a run (`>$000100,x` in `src/svc/sound.s`). That page and the
  interrupt vector are machine facts, not layout, and stay literal.

`XTGS.SYSTEM` keeps to itself the things that are not on that list: its
load address, the native stack, the buffers it reads `CORE` and `SVC`
through (`IOBUF`, `BOUNCE`: used only before the core runs, they lie where
`PATH` and `XFER` were assembled), and the MLI glue, which switches to
emulation mode on the loader's own page-1 stack with interrupts off.

## Testing it

**The `+` layout.** A `+` before the command in `XTGS.CMD` (`+P`, `+C HELLO`)
tells the loader to refuse every region its assembled bank and go straight
to the scan, so the relocation runs on a plain ProDOS 8 boot. On an 8 MB
machine `+P` prints `BANKS 02 03 04 00 10 00 00` (the translator would get
`$05`, a disk image `$20`): nothing is where it was assembled.

The pages move as well, to `layout.s`'s `NAME_ALTPG` equates:
`PAGES 11 12 13 60 40`. The direct page goes to `$1100`, pathnames to
`$1300`, and the two 8 KB buffers trade places. The front page moves to
`$1200`, and since that page is the loader's, the loader moves itself:
`set_pages` copies the page it was loaded with to `$1200` and applies its
own list, after which every mailbox reference in `XTGS.SYSTEM` and the
`JMP` behind `MB_FILECALL` are at the new page. The page at `$2000` is
never written again; a judge that looked there would find stage 1 and no
magic.

`XTGS_LAYOUT=alt` in the environment does this for any test: the image
builder adds the `+`, and `tools/mame/mamerun.py` translates every address a
tool gives it (waits, dumps, traces, taps) to where the region or area is,
and profile samples back. The tools keep speaking assembled addresses
(`0x2B8000` is still "the text buffer", `0x001000` the guest's registers,
the listing's `mb_magic` the magic). Every run dumps `MB_LAYOUT` and stops
with an error if the loader's banks and pages are not the ones the harness
translated for. Each layout builds its own image (`build/xtgs-alt.po`).
`python3 -I tools/layout.py` prints both layouts.

```
make test-layout                        probe, .COM programs, a spread of CPU vectors
make XTGS_LAYOUT=alt test-dos           any other target the same way
XTGS_LAYOUT=alt python3 -I tools/boot_dos.py --seconds 600
```

Results under `alt` match the assembled layout: the probe, every `.COM`
test (the file tests use all of `PATH`, `XFER` and `IOB`), the sampled CPU
vectors, the FreeDOS boot to FreeCom's first prompt, and the `J` and `K`
translators (same results, same speedups). Write taps on the assembled
direct page and mailbox while a `+` image runs see nothing once the loader
has moved: no stray reference survives.

**From GS/OS.** `make test-gsos` copies a System 6 volume (`SYSTEM6=`, by
default `../ddiigs/assets/system6.hdv`; not part of this tree), puts
`XTGS.SYSTEM`, `CORE`, `SVC` and `XTGS.CMD` in a folder `XTGS` on the copy,
and replaces `System/Start` with a 121-byte S16 (`tests/gsos/start.s`) that
calls GS/OS `Quit` with `*/XTGS/XTGS.SYSTEM`, which is how the Finder
launches a ProDOS 8 system file. `tools/check_gsos.py` then boots it twice in
MAME (with a CFFA card; GS/OS 6.0.1 does not start from MAME's SCSI card):

1. With `XTGS_LAYOUT=probe` (no translation, no check): wait for the loader
   to finish, press a key so it quits back to GS/OS, and wait for GS/OS to
   launch it again. `OS_BOOT` must say GS/OS, both runs must end cleanly
   with the same banks (the first released what it claimed), and at least
   one region must be away from its assembled bank.
2. `tools/judge_m0.py` with `XTGS_LAYOUT` set to the banks the first boot
   reported (`CORE=07,SVC=08,RES=09,GUEST=20,ZP=10,...`): the memory probe
   and the 80x25 test frame.

Under GS/OS 6.0.1 on 8 MB, `CORE`, `SVC` and `RES` land in `$07`-`$09`; the
guest and the disk image still get `$20` and `$50`. A FreeDOS boot from that
launch (command `D`, the disk image in the `XTGS` folder) reaches the same
FreeCom prompt as the direct boot; that was run by hand, not by a make
target. (This is `XTGS.SYSTEM` launched from GS/OS. The native application
is the last section, with its own `make test-s16`.)

`XTGS_LAYOUT` also takes an explicit list (`GUEST=40,CORE=12`, hex banks) for
a layout neither of the above produces.

## The GS/OS application (stage 3)

`CORE` and `SVC` are done: no bank and no bank-`$00` address of theirs is
a constant. What stays fixed in `XTGS.SYSTEM` is what makes it a ProDOS 8
system file, which is also why launching it from GS/OS means GS/OS
shutting down into ProDOS 8 and coming back afterwards:

| What | Where | Whose |
| --- | --- | --- |
| The loader | `$2000` | ProDOS 8 loads a SYS file there |
| The native stack | `$0800`-`$0BFF` | the loader's choice |
| The five areas | their assembled pages | the loader's to give: a ProDOS 8 program owns bank `$00` below `$BF00` |
| File calls | the MLI at `$BF00` | ProDOS 8 |

`XTGS` (`src/gs/xtgs16.s`, type `$B3`) is the second front end: a native
GS/OS application that runs the same `CORE` and `SVC` files, byte for
byte, without leaving GS/OS. Merlin32 writes it as a relocatable OMF load
file (`rel`), so the System Loader puts it anywhere. It keeps to the
contract above and owns only what it is given:

- **Bank `$00`.** One Memory Manager block of 35 pages (locked, fixed,
  page-aligned, attributes `$C005`) holds `ZP`, `MBX`, `PATH` and `XFER`,
  in that order; their pages go to `MB_LAYOUT`. `IOB` is not claimed:
  it is the buffer the MLI's `OPEN` wants, and there is no MLI. The stack
  is the one GS/OS started it with; its direct page is the front page.
- **Regions.** As the ProDOS 8 loader claims them: the assembled bank when
  it is free, else the first that is; the SHR screen as a block at
  `$E1:2000`. Everything is allocated under an auxiliary user ID and given
  back before quitting (`DisposeHandle` for the screen and each region,
  `DisposeAll` for the rest).
- **The front page.** Built in the block: `"XTGS"` at `+0`, a `JML` to
  `filecall` at `MB_FILECALL`, then the mailbox. Nothing outside knows
  where it is, so `tools/mame/mamerun.py` finds it: it scans the pages of
  bank `$00` for the signature and the `JML`, reads `MB_LAYOUT` there, and
  translates the tools' assembled addresses from that, while the run goes.
  The signature is cleared before the page is given back.
- **Files.** `XTGS.CMD`, `CORE`, `SVC` and the command's file come from
  the application's own folder (prefix 1). `filecall` carries out the MLI
  list in the mailbox with GS/OS calls - the class 0 ones, whose parameter
  blocks and error codes are ProDOS's, so `SVC` cannot tell. File
  references are slot numbers of the front end's, not GS/OS's. A
  directory, which `SVC` reads as ProDOS 8 blocks of 13 entries, is read
  raw where GS/OS allows it (the ProDOS FST does) and otherwise built
  from `GetDirEntry`; `+` forces the built kind so that it is tested.
- **Leaving.** `QuitGS` with no pathname. Both front ends close whatever
  the guest left open when the core returns, before the key wait: until
  then a file's length is not on the disk (`tests/com/leaveopen.asm`).

`XTGS_FRONT=s16` builds and tests with it:

```
XTGS_FRONT=s16 make                     build/xtgs-s16.po: a GS/OS volume that starts XTGS
make test-s16                           probe, .COM programs, sampled vectors, both layouts, relaunch
XTGS_FRONT=s16 make test-dos            any other target the same way
XTGS_FRONT=s16 python3 -I tools/boot_dos.py third_party/freedos/fd/freedos.img
```

`tools/make_image.sh` then calls `tools/gsos_image.sh`: ProDOS and the
System folder of the System 6 volume (`SYSTEM6=`) on a fresh 8 MB volume,
the files in a folder `XTGS`, and `tests/gsos/start16.s` as
`System/Start`, so the volume boots into XT/GS with no Finder. To install
it by hand, put `XTGS` (S16, `build/xtgs16`), `CORE`, `SVC` and `XTGS.CMD`
in one folder, with whatever the command names (`DISK`, a `.COM` file).
`build/xtgs16` is the data fork alone; the icon is in the resource fork
(below), so to keep it copy the folder `XTGS` under GS/OS from a volume
built here, `make finder`'s for one.

`Start16` launches `*/XTGS/XTGS` as the Finder launches an application:
`QuitGS` with the flag that asks to be returned to. So each time XT/GS
quits it is started again, and `tools/check_s16.py` uses that: three runs
in one boot, each of which must finish, find the front page of the run
before gone, and get the same banks and pages as the first. (Launched
without that flag, System 6.0.1 puts up its own Program Launcher when the
application quits. A do-nothing S16 gets the same, and XT/GS relaunches
from that launcher too.)

What has been run this way, all in MAME under System 6.0.1 with 8 MB:
the probe and every `.COM` test in both layouts, the sampled CPU vectors,
`make test-dos` (the same results as the ProDOS 8 front end), the
benchmarks (the same instructions a second), the `K` translator, and a
FreeDOS boot to FreeCom's first prompt with the BIOS tick count advancing
at 18.2 Hz - the DOC timer's interrupt arrives through `$E1:002C` under
GS/OS as it does on the bare firmware. `CORE`, `SVC` and results land in
`$07`-`$09`, the four areas at `$1800`-`$3AFF`.

### The Finder icon

`XTGS` has a resource fork (`build/xtgs16.rfork`, written by
`tools/gsos_rfork.py`, which is the reference's): an `rBundle` that
matches file type `$B3` and the name `XTGS`, two `rIcon`s from the
QuickDraw II icon records in `icon/` (`dos_32x32.qdicon.bin`,
`dos_16x16.qdicon.bin`), an `rVersion` (`XTGS_VERSION` in the Makefile,
0.1) and an `rComment`. The data fork is the load file as before. cadius
adds the fork of `XTGS#B30000` from `XTGS#B30000_ResourceFork.bin` beside
it, and the Makefile puts it there.

The Finder shows a bundle's icon only once the bundle is in the volume's
`Icons/Desktop` file, which it writes the first time the program is
launched from it. `tools/gsos_image.sh` builds that file too
(`gsos_rfork.py desktop`) for the volumes it makes, so the icon is there
at the first boot. On any other disk `XTGS` has the generic application
icon until it has been opened once.

The files in `icon/` are used as they are, with two changes made as the
records go into the fork, both for what the Finder's 640 mode did with
them unchanged:

- The rows above and below the drawing in which the mask is clear are
  dropped (32x32 becomes 32x22, 16x16 becomes 16x9; `--no-trim` keeps
  them). The Finder stands an icon on its name and a row of a window has
  room for about 20 lines, so the 32-line record lost its top half in the
  first row of a new folder, where no scrolling reaches it. At 22 lines
  it loses its top line or two there until the icon is moved.
- Pixel value `$9` is written as `$4` (`ICON_REMAP` in the Makefile;
  empty for none). In 640 mode a 4-bit icon pixel is two 2-bit screen
  pixels, the left from black/red/green/white and the right from
  black/blue/yellow/white: sixteen dithered colours, not the sixteen
  entries of the 640-mode colour table the records were drawn against.
  `$E`, `$A` and `$D` come out pale yellow, yellow-green and light blue,
  near enough what was meant; `$9` is green and blue, an aqua D where a
  red one was drawn. `$4` (red and black) is the dithered red.

`make finder` builds `build/xtgs-finder.po`: the folder on a volume that
keeps System 6's own `Start` and its `Icons/FType.*` (the Finder refuses
to start without a file type descriptor file), so it boots to the Finder.
The folder there is the one a user wants: `XTGS`, `CORE`, `SVC`, the
FreeDOS floppy as `DISK` (docs/mode-b.md; `GWBASIC.EXE`, `HELLO.BAS` and
`CGADEMO.BAS` on it) and an `XTGS.CMD` of `D`, so opening `XTGS` boots
FreeDOS. GW-BASIC is not fetched: the rule fails without
`third_party/gwbasic/GWBASIC.EXE`.

There, in MAME under System 6.0.1: the folder `XTGS` shows the
application under the DOS icon (red D, yellow O, green S, blue shadow) in
the icon and small-icon views; Icon Info shows the icon, `XT/GS 0.1` and
the `rVersion`'s second line. Open boots FreeDOS to FreeCOM's date
prompt, about 200 seconds of emulated time after the click (the boot is
as slow as it is from ProDOS 8), and after two Returns `A:\>`; `GWBASIC`
gives `Ok` and computes, `GWBASIC CGADEMO` draws in 320 mode. With an
`XTGS.CMD` of `P` instead, Open runs the probe and a key returns to the
Finder. Nothing checks any of this in `make test-s16`: it was looked at
(screenshots driven through `tools/mame/mamerun.py`'s inputs).

Not done or not known:

- It has not been run on a real IIGS. The Finder has launched it only in
  MAME.
- A booted disk has no way back to the Finder: Mode B ends only when the
  guest halts with interrupts off, which FreeDOS does not do. Restart
  the machine (the same under ProDOS 8).
- It is a text-and-SHR program that takes the screen without QuickDraw
  and reads the keyboard directly, as the ProDOS 8 front end does: no
  desk accessories, no menu bar.
- In the small-icon view the 16-pixel small icon runs into the file's
  name (the Finder's own are 8 to 10 wide).
- A guest sees what the MLI lists can name: ProDOS pathnames of up to 64
  characters. The built directory blocks, meant for file systems that
  will not hand over a directory raw, have only been exercised by `+`, on
  a ProDOS volume.

`../somi-iigs-port/iigs` made the same move and was the reference:
`docs/GSOS_PLAN.md`, `asm/crt0gs.s` and `asm/gs_glue.s` (startup, Toolbox
glue, `QuitGS`), `src/platform/gsos/gsfile.c` (files over GS/OS calls).
