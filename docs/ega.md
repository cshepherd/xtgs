# EGA graphics: mode 0Dh

XT/GS has one EGA mode, **0Dh: 320x200 in 16 colours** (GW-BASIC's
`SCREEN 7`), with the card's planes, latches and graphics controller behind
it, eight display pages and the palette registers. It is the one EGA mode
the IIGS can show as it is: the Super Hi-Res 320 mode is 320x200 at four
bits a pixel, so a pixel is a pixel and a colour number is a colour number.
The 640-wide modes (0Eh, 10h) would need four bits a pixel at 640, which the
SHR does not have; they are not there, and the card says so the way a real
one does (below).

```
make test-com COM=ega          the planes and the BIOS, 107 cases, and the picture
make test-com COM=egap         the same picture after a palette change
```

## What a guest sees

- `INT 10h AH=00h AL=0Dh` sets the mode (`AL=8Dh`: without clearing the
  planes). The BDA says mode 0Dh, 40 columns, a page of 2000h bytes; every
  page's cursor goes home.
- `INT 10h AH=12h BL=10h` answers an EGA with 256K on a **200-line colour
  monitor** (`BH=0`, `BL=3`, `CL=7`): the switch setting that tells a
  program the 350-line modes are not to be had. `0040:0087` and `0088` hold
  the same (`60h`, `F7h`). `AH=11h AL=30h` gives the 8x8 font (at
  `F000:F000`, all 256 characters; `INT 1Fh` and `INT 43h` point into it).
  `AH=1Ah` is not answered (`AL` comes back as it went), so nothing takes
  the card for a VGA.
- **A000:0000** is the planes: 40 bytes a line, 8000 a page, eight pages of
  2000h. A read or a write there goes through the graphics controller as it
  does on the card:

  | Register | What works |
  | --- | --- |
  | Sequencer 2 (`3C4h`/`3C5h`) | the map mask |
  | Graphics 0, 1 (`3CEh`/`3CFh`) | set/reset and its enable |
  | Graphics 2, 7 | colour compare and colour don't care (read mode 1) |
  | Graphics 3 | the rotate count and the function (store, AND, OR, XOR) |
  | Graphics 4 | the read map |
  | Graphics 5 | write modes 0, 1 and 2; read modes 0 and 1 |
  | Graphics 8 | the bit mask |
  | Attribute 0-15 (`3C0h`, flip-flop reset by a read of `3DAh`) | the palette: each of the 16 colours is any of the CGA's 16 |
  | 6845 R12/R13 (`3D4h`/`3D5h`) | the start address: the page shown, or a scroll by whole bytes |
  | 6845 R13h | the offset: words from a line of the planes to the next (20 as the mode is set) |
  | Attribute 13h | the screen panned left by 0-7 pixels |

  The last three together are how a game scrolls: the screen is a window
  on a buffer wider than itself (Commander Keen: 48 bytes a line), moved a
  byte at a time by the start address and a pixel at a time by the
  panning. The planes go round at 64K under the window.

  The four latches are filled by every read and used by every write, so the
  usual idioms work: `OR [mem],al` to load the latches and write through the
  bit mask, a read and a store in write mode 2, `REP MOVSB` in write mode 1
  to copy screen to screen.
- The registers are write-only, as the EGA's are: a read of `3C0h`-`3CFh`
  returns `FFh`.
- `INT 10h` in the mode: `02h`/`03h` (a cursor for each page), `05h` (the
  page shown), `06h`/`07h` (a window scrolled, `BH` the fill colour),
  `08h` (the character read back from its pixels), `09h`/`0Ah`/`0Eh`/`13h`
  (characters drawn with the 8x8 font, `BL` the colour, bit 7 for XOR),
  `0Bh` (the CGA way to the palette), `0Ch`/`0Dh` (a pixel, `BH` its page),
  `0Fh`, `10h` (`AL=00h` one palette register, `01h` the overscan, taken
  and not shown, `02h` all of them), `11h AL=30h`, `12h BL=10h`.
  `02h`, `03h`, `08h`, `09h`, `0Ah` and `13h` work on the page `BH` names;
  the teletype and the scrolls on the page shown.
- DOS's console is the BIOS teletype, so `PRINT`, a prompt or `TYPE` in mode
  0Dh draw text, 40 columns of it.

## A PC without it: `VIDEO=CGA`

Some programs take the best card they find. One that asks `INT 10h AH=12h`
and then wants a mode XT/GS does not have (0Eh, 10h) is better off told
there is a CGA. A line `VIDEO=CGA` in `XTGS.CMD`, after the command line,
does that under `D` and `S`:

```
D
VIDEO=CGA
```

Then mode 0Dh is not set (`AH=00h AL=0Dh` is ignored, like any mode a card
lacks), `AH=11h` and `AH=12h` return with the registers as they were and
the BDA's EGA bytes are 0. The line may come before or after the shared
drive's (`C=...`, docs/share.md); SVC reads both (`rd_readcfg`). Command
`C` reads the `VIDEO` line as well (`svc_pcinit`), and `VIDEO=TANDY` is
the Tandy 1000 of docs/tandy.md.

## The window on a wider buffer

While a line is 40 bytes from the next and nothing is panned, the flush is
the one below: a flag a byte, by place on the screen. Otherwise
(`EGA_WINLEN` is not `EGA_LEN`; `ega_flush` works it out from the two
registers each frame) no byte has a place of its own, and the rule is
simpler: when the window moved, or anything was written inside it, **all
of the screen is drawn** (`eg_wide`: 200 lines of 40 bytes from where each
begins, through `eg_conv`, or `eg_convp` when panned, which takes each
plane's byte and the next and shifts). A write inside the window but past
the 8000th byte has no flag to set, so it sets `VID_DIRTY`'s first
(`eg_mark`, `eg_markrng` in the core, `eg_mk1` in SVC), and that is all the
wide path asks: is any of `VID_DIRTY`'s 32 set.

What that costs: a scroll step is a whole screen, some 2 million cycles
(0.7 s on the stock clock, a seventh of a second at 16 MHz). The split
screen (line compare) is not there, the start address is taken when the
frame's flush runs (a flush between a program's two writes of R12 and R13
draws one frame from a wrong place), and the BIOS's text and scrolls
(`INT 10h`) still take a line for 40 bytes.

`tests/com/egaw.asm` (`egaw`, `egaww`, `egawp`) is the test: 48 bytes a
line from `3604h` panned 3, the same from `FE00h` round the planes' end,
and 40 bytes panned 5; each draws, waits for the flush and then writes
past the 8000th byte, singly and by `REP STOSB`. `tools/egashr.py` takes
the offset register and the panning from the registers.

Minix 1.5 shows the difference: it asks `AH=12h`, and on an EGA it does not
let the 6845's start address go round at 16K but copies the screen back to
the buffer's start when it gets there. Both ways work and both are tested
(`make test-minix`, `make test-minix CGA=1`; docs/minix.md).

## How it works

### Where the planes are

Four host banks: plane 0 is the guest's own bank A (`H_EGA`,
`GUEST_BASE+$A0000`) and planes 1-3 are its banks C, D and E (`H_EGA1`-`3`,
`src/include/pc.s`), which a PC with no option ROMs leaves empty. A byte of
the screen is the same offset in each, so the BIOS and the flush index all
four with one X.

### The core: the trap (`src/core/ega.s`, `gen/egaw.s`)

While the mode is on (`ega_cur`), bank A is not memory to the guest.

- **Instructions with a ModR/M operand.** The effective-address tails
  already compare the operand's bank with the text buffer's for the dirty
  mark; that compare is now with `#^H_EGA` and its taken side (`ea_hi`,
  `ef_vid`) sorts out the text buffer from the planes. So with the mode off,
  and for every operand below A000 with it on, nothing was added to the
  path: `make bench` is where it was (28.2K/22.6K/33.9K IPS).
  An operand in the planes goes to `ega_trap` with the ModR/M byte. The
  trap finds the opcode (the ModR/M byte's length back from IP) and looks up
  what that instruction does with its operand (`eg_class`, from
  `tools/gen_cpu.py`: read, write, both, by group for `80`-`83`, `F6`/`F7`,
  `FE`/`FF`). A read is done at once: `ega_rd` loads the latches and
  returns the byte the read mode gives, into `vBOUNCE`, and `pEA` is pointed
  there. For a write `NEXTVEC` is pointed at `ega_retire`: the handler runs
  as always, stores into `vBOUNCE`, and on its way out the byte (or the two
  of a word, low then high, as an 8088 does it) goes through `ega_wr`. No
  handler knows about any of it.
- **`ega_rd` / `ega_wr`** are generated, one straight line of code for each
  plane. A write with nothing in the way (write mode 0, bit mask `FFh`, no
  set/reset, no function, no rotate: `eg_plain`) is four stores under the
  map mask; anything else builds each plane's byte from the data, the
  set/reset bit, the latch and the mask. `eg_derive` recomputes what they
  need whenever a register is written (`ega_out`, ports `3C0h`-`3CFh` in
  `ops_misc.s`).
- **String instructions.** For as long as the mode lasts their opcodes
  point at `eg_strop` (`ega_sync` swaps the table entries), which looks at
  SI and DI and goes on to the ordinary handler unless one is in the planes.
  Then an element at a time through `ega_rd`/`ega_wr` (`eg_movsb`...), or,
  for what a program does a screen at a time, a block move in each plane
  the map mask enables:

  | Instruction | When | How |
  | --- | --- | --- |
  | `REP STOSB`/`STOSW` | a plain write | the first element stored, an overlapping `MVN` for the rest |
  | `REP MOVSB`/`MOVSW`, memory to planes | a plain write | `MVN` into each plane |
  | `REP MOVSB`/`MOVSW`, planes to memory | read mode 0 | `MVN` from the plane the read map names |
  | `REP MOVSB`, planes to planes | write mode 1 | `MVN` within each plane, the latches left as the last byte's |

  with DF clear and no wrap of SI, DI or a bank in the run.
- **Dirty marks.** Every byte written on the shown page sets its flag in
  `EGA_DIRTY` (8000 flags, by place on the screen, so a moved start address
  does not confuse them) and the flag's 256 in `VID_DIRTY`.
- The BIOS changes the mode and some registers from the other bank; it
  raises `EGA_SYNC` and the hypercall's return runs `ega_sync`, as do the
  PC's start and a reboot.

### SVC: the picture and the BIOS (`src/svc/ega.s`, `gen/egatab.s`)

- **`ega_enter`** (from `vid_setmode`) clears the registers and the planes,
  sets the default palette, puts the SHR in 320 mode and asks for a full
  draw. **`ega_leave`** undoes it for whatever mode comes next.
- **`ega_flush`**, each frame: the palette if a register changed
  (`ega_setpal`: a register's bits 0-2 and bit 4 pick one of the CGA's 16
  colours, `cga_rgb`), the whole page if the start address moved or
  `EGA_ALLD` asks, otherwise the flagged bytes, found through the 32
  `VID_DIRTY` bytes. Four plane bytes are eight pixels, which is four SHR
  bytes: eight table lookups (`eg_tNlo`/`eg_tNhi`, each plane's byte to its
  bit in those pixels) ORed into two words.
- **The BIOS's own drawing** (`eg_cell`, `eg_draw`, `eg_read`, `eg_setpix`,
  `eg_getpix`, `egs_copy`, `egs_fill`, called from `gtext.s`'s dispatch)
  writes the planes directly, whatever the guest left in the graphics
  controller, and marks what it wrote. A scroll of the whole width is an
  `MVN` in each plane, and the drawn pixels move with it on the SHR.
- **Pages.** `05h` sets the 6845's start address to the page's offset
  (`eg_setpage`); the flush sees the start has moved and draws the page.
  Each page has its cursor in the BDA; a service that names a page in `BH`
  works on that one (`eg_curin`/`eg_curout` swap its cursor into the first
  slot for the call, where every routine looks).

## Tests

- `tests/com/ega.asm` (`ega`, and `egap` with another palette): 107 cases,
  each printed as bad if a byte read back from the planes, a latch, a
  register's effect, a string instruction's result, a BIOS call's answer or
  a cursor is not what the card would give. Every write mode and read mode,
  the functions, rotate, set/reset, the map mask, words, `XCHG`, `XLAT`, the
  groups, `REP` both directions and across the fast paths, pages and their
  cursors. It ends on a picture and `tools/egashr.py` compares all 64000
  pixels of the SHR with the planes and the palette registers
  (`"video": "ega"` in the manifest; `"ega_ac"` the registers expected).
- `make test-minix` and `make test-minix CGA=1`: the two ways Minix scrolls.
- `tools/share_test.py --cfg $'C=SHARE\rVIDEO=CGA'` (and the other order):
  the two lines of `XTGS.CMD` together.
- `tools/check_long.py` (in every build) now refuses an address operand
  that adds before it multiplies. Merlin32 has no precedence, so
  `sta htab+3*8` is `(htab+3)*8`: `files.s` had two of those, which stored
  into the middle of SVC, harmlessly until `ega.s` put code there.

## What it costs

On the stock 2.8 MHz clock, measured in MAME with a program timing itself
by the tick count and the real-time clock:

| Work | Time |
| --- | --- |
| The mode set (planes cleared, screen drawn) | 0.84 s |
| `REP STOSB` over a page, and the redraw | 0.31 s |
| `REP MOVSB` memory to a page, four planes, and the redraw | 0.35 s |
| `REP MOVSB` page to page in write mode 1 | 0.08 s |
| `mov [es:di],al` in a three-instruction loop | 0.33 ms a pass (0.12 ms on ordinary memory) |
| `or [es:di],al` in the same loop | 0.38 ms |
| A read and a store in write mode 2 (a pixel) | 0.59 ms a pass, 1700 pixels a second |
| `INT 10h AH=0Ch` in a twelve-instruction loop | 1.5 ms a pixel |
| `INT 10h AH=0Eh` | 2.9 ms a character |
| `REP MOVSB` over a page an element at a time (write mode 2, say) | 1.5 s |

A trapped store is about three times an ordinary one. A Zip at 16 MHz
divides all of it by five or so.

## Limits

- **Modes 0Eh and 10h are not there**, nor the EGA's text modes' extras
  (fonts loaded with `AH=11h`, 43 lines). A program that needs them wants
  `VIDEO=CGA`.
- The mode is set through `INT 10h`. A program that sets it by writing the
  card's registers itself gets the registers and no mode.
- The trap is in the ModR/M tails and the string instructions. Not caught:
  a word at offset `FFFFh` of its segment, the stack or code in A000,
  `LES`/`LDS` and the far `FF` forms with the pointer in the planes, a
  `REP` run that starts below A000 and runs into it, and a DOS read or
  write whose buffer is the planes (the file service stores straight to
  memory: plane 0 gets the bytes).
- A guest that reads C000-EFFF in the mode sees planes 1-3.
- `REP MOVSW` planes to planes goes an element at a time (a word in write
  mode 1 is two bytes through one set of latches).
- A `REP` that goes an element at a time is still one instruction: nothing
  else happens until it ends (no tick, no key, no frame), 1.5 s for a page
  at the stock clock. The ticks are made up afterwards (`clk_sync`).
- The BIOS's text and pixel services write the planes directly: they do
  not go through the guest's bit mask or function (a real BIOS sets the
  registers it wants and leaves them changed; this one leaves them alone).
- No cursor is drawn in graphics modes (the EGA draws none either).
- The start address counts whole bytes: no pixel panning, no split screen,
  no vertical retrace interrupt.
- GW-BASIC: `third_party/gwbasic/GWBASIC.EXE` is built from the 1983
  source, which has no `SCREEN 7`. Microsoft's 3.2x does, and 3.23 was run
  here: `LINE`, `CIRCLE`, `PAINT`, `GET`/`PUT`, `DRAW`, `POINT`, `PALETTE`
  and the pages (`SCREEN 7,,1,0`) come out right, with the program named
  on GW-BASIC's command line (started bare under FreeDOS that binary
  refuses, docs/mode-b.md). `EGADEMO.BAS` on the FreeDOS diskette and in
  `SHARED` is for it.

## Try it

`EGADEMO.COM` (`tests/demo/egademo.asm`, 408 bytes, on the FreeDOS diskette
and in the folder `SHARED`): sixteen bars drawn with set/reset and
`REP STOSB`, a lattice over them in write mode 2, a line of BIOS text, and
the palette going round through `INT 10h AX=1000h` until a key. On a PC
with no mode 0Dh (`VIDEO=CGA`) it says so and ends.

```
python3 -I tools/cga_test.py third_party/freedos/fd/EGADEMO.COM 300
GWBASIC=/path/to/GWBASIC.EXE python3 -I tools/cga_test.py third_party/freedos/fd/EGADEMO.BAS 500
VIDEO=CGA python3 -I tools/cga_test.py third_party/freedos/fd/EGADEMO.COM 300
```

`tools/cga_test.py` takes a `.COM` as well as a `.BAS`, another interpreter
in `GWBASIC`, `VIDEO=CGA` for the `XTGS.CMD` line and `TEXT=1` to print the
text screen a program ends on.
