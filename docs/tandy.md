# Tandy 1000 video: modes 08h and 09h

With the line `VIDEO=TANDY` in `XTGS.CMD` the PC is a **Tandy 1000**: its
BIOS's two identifying bytes, its page register and video array, and its
two 16-colour modes of 200 lines. Mode **09h is 320x200**: four bits a
pixel, the left pixel a byte's high four, 160 bytes a line: the Super
Hi-Res 320 mode a byte for a byte, so a line goes to the screen with one
block move and a colour number is a colour number. Mode **08h is
160x200**: the same pixels twice as wide, 80 bytes a line in one page of
16K laid out as the CGA's graphics are, each byte through a table to two
of the SHR's.

These are the first steps of `XTGS_Tandy_1000_Graphics_and_Sound_Plan.md`.
Mode 0Ah, the BIOS's characters in modes 08h and 09h and the three-voice
sound are not built (Limits, below).

```
make test-com COM=tandy        mode 09h: the pages, the array, the BIOS: 51 cases and a picture
make test-com COM=tandyp       the same, the mode set by the ports, the screen's page not the CPU's
make test-com COM=tandy8       mode 08h: 36 cases and a picture
make test-com COM=tandy8p      the same, the mode set by the ports, the screen's page at BC00
make test-com COM=gtextt       CGA mode 4 and the BIOS's text in it, on the Tandy
```

## The line in `XTGS.CMD`

```
S
VIDEO=TANDY
```

after the command's line, before or after the shared drive's (`C=...`);
`rd_readcfg` reads it under `D`, `S` and (unlike the share's) `C`. A Tandy
has no EGA: the line does what `VIDEO=CGA` does (docs/ega.md) and the
EGA's banks hold the Tandy's pages instead. Without the line nothing of
this is there: modes 08h and 09h are not modes, ports 3DAh-3DFh are the
CGA's.

## What a guest sees

- `F000:FFFE` is `FFh` and `F000:C000` is `21h`, which is how programs
  tell a 1000 from a PCjr (`FDh`) and a PC.
- **Eight pages of 16K** and the **page register at 3DFh**: bits 3-5 the
  page the CPU has at `B800:0000`, bits 0-2 the page the screen shows,
  bits 6-7 kept. An even CPU page brings the next one with it at
  `BC00:0000` (32K, what mode 09h needs); with an odd one only the 16K at
  `B800` is that page. Pages keep their bytes while they are away. The
  BIOS's copy of the register is at `0040:008A`.
- **The video array**: the register chosen by a write to `3DAh`, written
  at `3DEh`. `01h` the palette mask, `02h` the border (kept, not shown),
  `03h` the mode register (bit 4: 16 colours), `10h`-`1Fh` the sixteen
  palette registers, each one of the CGA's sixteen colours. A pixel's
  four bits go through the mask and then through the palette. The
  registers are write-only, as the Tandy's are.
- `INT 10h AH=00h AL=09h` sets the mode (`AL=89h`: without clearing): the
  page register `F6h` (pages 6 and 7 for the CPU and the screen), the
  array as the BIOS leaves it (mask `0Fh`, palette 0-15, mode register
  `14h`), `3D8h` = `2Bh`, the 32K cleared, the BDA mode 09h and 40
  columns. Any other mode set puts the page register back to `3Fh`
  (page 7, where the text is) and the palette to 0-15.
- `INT 10h AH=00h AL=08h` sets mode 08h (`AL=88h`: without clearing): the
  page register `3Fh` (page 7 for the CPU and the screen), the array the
  same, `3D8h` = `2Ah`, the window cleared, the BDA mode 08h and 20
  columns.
- **The modes by the ports**: `3D8h` with bit 1 (graphics) while the
  array's mode register has bit 4 is a 16-colour mode, 09h with bit 0
  (320 across) and 08h without, entered at the next frame without
  clearing anything, as on the machine. A program that sets one this way
  sets the page register itself. `3D8h` written again with the other
  value of bit 0 goes from one to the other, the bytes as they are.
- In mode 09h line `y` is in the 8K bank `y & 3` of the 32K, at
  `(y >> 2) * 160`. The screen is the two pages the register's low three
  bits name (the even one and the next), wherever the CPU's are: draw on
  pages 4 and 5 while 6 and 7 are shown, then show 4 and 5.
- In mode 08h line `y` is at `(y & 1) * 2000h + (y >> 1) * 80` of one
  page, a byte two pixels, the left one its high four bits. The screen
  is the page the register's low three bits name, any of the eight, and
  again not necessarily the CPU's: eight pictures fit, and with an even
  CPU page the screen's can be the one at `BC00`.
- `INT 10h` in the modes: `0Ch`/`0Dh` (a pixel, in the CPU's pages; bit 7
  of `AL` for XOR; in mode 08h `CX` is 0-159), `0Fh`, `05h` with `AL=80h` (`BH` the screen's page,
  `BL` the CPU's), `81h` (the CPU's from `BL`), `82h` (the screen's from
  `BH`), `83h` (both), and `10h` with `AL=00h` (palette register `BL` from
  `BH`), `01h` (the border), `02h` (all sixteen and the border from the 17
  bytes at `ES:DX`). `05h` and `10h` are there in every mode on a Tandy.
- The CGA's modes are as they were (4, 5, 6, the 160x100 text mode, the
  BIOS's text in them): a Tandy runs CGA programs.

## How it works

### The pages are moved, not mapped (`tdy_setpage`, `src/svc/tandy.s`)

The core knows one thing about video memory: a store into `B800-BFFF`
marks its 256 bytes in `VID_DIRTY`. To leave it at that, **`B800-BFFF` in
the guest's megabyte is always what the CPU has**, and a write of the page
register moves 16K pieces between that window and where the other pages
wait. Nine places hold eight pages (`src/include/pc.s`):

| Slot | Guest address | |
| --- | --- | --- |
| 0-3 | `A0000`, `A4000`, `A8000`, `AC000` | `H_TDYA`, the EGA's plane 0 |
| 4, 5 | `C0000`, `C4000` | `H_TDYC`, the EGA's plane 1 |
| 6, 7 | `B8000`, `BC000` | the window |
| 8 | `C8000` | `H_TDYC` again |

One slot is always empty. To bring a page to a half of the window, what
is there goes to the empty slot and the page comes in (two block moves of
16K); with an odd CPU page the second half is emptied. `tdy_where` is the
slot of each page, `tdy_held` the page in each slot, and `TDY_SLOT` in the
results bank is the same for the judge. `B0000` is left alone (a program
that looks for a monochrome card writes there), and `A000` and `C000` are
not memory on a real 1000, so nothing a program is entitled to read sees
the pages in them.

After a move the bytes at `B800` are other bytes: a text screen is marked
whole (`mark_all`) and CGA graphics too, so the screen follows the CPU's
page in those modes (which is right when both pages are the same, the
usual case; Limits).

### The picture (`tdy_flush`)

Each frame in mode 09h: the SHR palette if a palette register or the mask
changed (`tdy_setpal`: entry `n` is `cga_rgb[palette[n & mask]]`), then
the lines. The two pages shown are found in their slots. After a mode set
or a write of the page register all 200 lines are moved (`tdy_alld`);
otherwise, for each set flag of `VID_DIRTY` (128 now: the whole 32K),
if the half of the window it is in holds a page that is shown, the one or
two rows its 256 bytes lie in (`tdy_r0`/`tdy_r1`) are moved. A row is 160
bytes by `MVN` from the page to `$E1:2000` (`tdy_row`). A store to a page
that is the CPU's and not the screen's costs a flag and nothing more.
A frame in which no flag is set, which is most of them, costs the look
at the flags eight at a time (`tdy_dirty`: some 0.7 ms of the frame's 17
at the stock clock).

Mode 08h (`tdy_flush8`) is the same with one page and the CGA's rows:
the page shown is found in its slot, and a set flag counts when its half
of the window holds that page; its 256 bytes lie in three or four of the
8K's hundred rows of 80 (`gpg_r0`/`gpg_r1`, the CGA's table), and a row
two flags share is drawn once (`tdy_nx`). A row is not a block move: each
byte is two pixels and the SHR wants each twice, so `tdy_row8` takes a
byte through `tdy8_tab` (`src/svc/gen/tdytab.s`, 256 words: the high four
bits as the first byte, the low four as the second) to a word of the
line, some 41 cycles a byte where mode 09h's move is 7.

### The mode and the ports

The core sends ports 3DAh-3DFh to SVC in both modes of running
(`port_out`, `svc_portout`, `tdy_port`); the others the CGA has are the
core's as before. A write of `3D8h` or of the array's mode register raises
`CGA_MODECHG`, and at the frame `apply_cgamode` asks `tdy_mode` first:
it enters mode 08h or 09h (`tdy_show`; `gfx_mode` is `GFX_TDY8` or
`GFX_TDY9`), or leaves them for the CGA's logic. `vid_setmode` calls
`tdy_modeset` for every mode (the registers the BIOS resets) and
`tdy_enter` for 08h and 09h.

## Tests

- `tests/com/tandy.asm` (`tandy`, and `tandyp` with the command line `P`):
  51 cases: the identifying bytes, the mode and the BDA, the 32K as memory
  (no wrap at 16K, `REP STOSW` over all of it, `REP MOVSB` to a line), the
  pixel calls on four lines of different banks, XOR, off-screen, the page
  register through the port and through `INT 10h` (every page written with
  its number at `B800` and read back, an even one with the next behind
  it), the mode set that keeps the screen, text again. Then a picture,
  left for a frame and written over in places (pixels down a diagonal
  through every line, the first and last byte of each bank, a word across
  two 256s, runs across the two halves). `tools/tandyshr.py` reads the two
  pages shown from their slots and compares all 32000 bytes with the SHR,
  and the palette through the mask (`"video": "tandy9"`; `"tandy_pal"` and
  `"tandy_page"` the registers expected). `tandy` ends in the BIOS's mode
  on pages 6 and 7; `tandyp` enters the mode from text by the ports, draws
  on pages 2 and 3 with the palette turned round behind a mask of 7, and
  at the end gives the CPU pages 6 and 7 and fills them, which must not
  show.
- `tests/com/tandy8.asm` (`tandy8`, and `tandy8p` with the command line
  `P`): 36 cases in mode 08h: the mode and the BDA (20 columns, page 7),
  the 16K as memory, the pixel calls (the two pixels of a byte, the
  first and last of the screen, an odd line in the second 8K, XOR, the
  read, off the screen at x = 160 and y = 200), a pixel on a page that
  is the CPU's and not the screen's, pages 4 and 5 together, the mode
  set that keeps the screen, the mode after 09h and after text. Then a
  picture of bars in which the two pixels of some bytes differ, left for
  a frame and written over (a diagonal through all 200 lines, the ends
  of each 8K's rows, a word across two 256s, a run over the 192 bytes of
  an 8K that are no line and on into the next). The judge decodes the
  page shown from its slot (`"video": "tandy8"`) and wants the mode
  registers to be mode 08h's. `tandy8` ends in the BIOS's mode with page
  7 at `B800`. `tandy8p` enters from text by the ports with pages 6 and 7
  the CPU's and 7 the screen's, so that the picture is at `BC00`; gives
  the CPU pages 2 and 3 for a while and fills them; brings 7 back and
  writes it over, so that the lines drawn piece by piece from `BC00` are
  what the judge sees; and fills page 6, at `B800` and not shown. With
  the odd lines' rows drawn as the even ones' (one line of `tdy_flush8`
  taken out) both fail, `tandy8p` by 281 bytes.
- `gtextt` is `gtext` (mode 4, the BIOS's text) with the line: the CGA's
  modes on the Tandy.
- A manifest's `"cmd"` is the lines of `XTGS.CMD` after the command's.
- Under FreeDOS: `VIDEO=TANDY CAP=1 python3 -I tools/cga_test.py
  path/TANDY.COM 420` prints the same 51 cases and judges the screen the
  same way (`CAP=1`: the end of what the teletype printed); with
  `TANDY8.COM` the 36, the screen judged as mode 08h (the tool reads
  which of the two from the mode registers).

## What it costs

On the stock 2.8 MHz clock, in MAME, by the frames a run takes with and
without the work:

| Work | Time |
| --- | --- |
| The mode set (32K cleared, two pages moved, the screen drawn) | 0.28 s |
| A page moved (16K) | 40 ms |
| The whole screen drawn (after the page register changes) | 0.12 s |
| The screen's page changed (`AX=0582h`) | 0.12 s: the drawing |
| The CPU's two pages changed for two others (`AX=0581h`) | 0.28 s: four moves and the drawing |
| `REP STOSW` over the 32K, and the redraw | 0.26 s |
| `mov [es:di],al` in a three-instruction loop | 0.20 ms a pass |
| `INT 10h AH=0Ch` in a six-instruction loop | 1.8 ms a pixel |

A program that draws on a hidden page and then shows it pays 0.12 s a
picture; one that changes the CPU's page for every picture pays 0.28 s
more. A Zip at 16 MHz divides all of it by five or so.

Mode 08h, measured the same way:

| Work | Time |
| --- | --- |
| The mode set (32K cleared, the screen drawn) | 0.35 s |
| The whole screen drawn (after the page register changes) | 0.27 s |
| The screen's page changed (`AX=0582h`) | 0.27 s: the drawing |
| The CPU's page changed for another (`AX=0581h`) | 0.39 s: two moves and the drawing |
| `REP STOSW` over the 16K, and the redraw | 0.32 s |
| `mov [es:di],al` in a three-instruction loop | 0.32 ms a pass |
| `INT 10h AH=0Ch` in a six-instruction loop | 2.2 ms a pixel |

The screen is half the bytes of mode 09h's and costs twice as much to
draw, because a row goes through the table; and a byte stored costs more
than there because the three or four rows its 256 bytes lie in are drawn
in every frame the loop lasts (1.2 ms a row).

## Limits

- **Modes 08h and 09h only.** Mode 0Ah (640x200 in four colours) is not
  built: set by `INT 10h` it is a text screen, and its bits written to
  the ports (the array's mode register bit 3) are not looked at.
- **The BIOS's characters draw nothing in modes 08h and 09h**: `INT 10h`
  `06h`-`0Ah`, `0Eh` and `13h`, and so DOS's console (the teletype is
  still captured for the harness). A program that prints in the modes, or
  a prompt after a program that leaves one set, is not seen. `02h`/`03h`
  move the BIOS's cursor as ever.
- In text and in the CGA's modes the screen is the CPU's page: a program
  that shows one page and writes another there sees what it writes. The
  array's palette and mask apply in modes 08h and 09h only (the CGA's
  modes keep the CGA's colours), and the border is not shown.
- Which of the two 16-colour modes the ports mean is read from `3D8h`'s
  bit 0 alone, as DOSBox reads it; the array's mode register is looked
  at for bit 4 only.
- With an odd CPU page the real machine shows the same 16K again at
  `BC00`; here `BC00` is nobody's memory then.
- The page register's bits 6-7 are kept and not acted on; the array's
  other registers (`00h`, `04h`-`0Fh`) are not kept. `3DAh` reads as the
  CGA's status.
- The three-voice sound (port C0h), the Tandy's keyboard, and the PCjr's
  differences (its cartridge-less ID, its 3DAh flip-flop) are not there.
- A `REP` over the 32K is one instruction (some 90 ms of nothing else at
  the stock clock, by the cycles of a block move), and a page move is 40
  ms with nothing else: a tick that falls in them is made up afterwards
  (`clk_sync`).
- No Tandy program has been run here. The registers, the layout of the
  lines and what the BIOS sets are from the Tandy 1000 SX Technical
  Reference, Ralf Brown's interrupt list and a reading of what MAME's and
  DOSBox's Tandy video do; the test's cases and the judge's decoding are
  written from the same, and no other emulator is in the loop. Modes
  08h and 09h have been run in MAME only.

## Try it

`TDYDEMO.COM` (`tests/demo/tdydemo.asm`, 330 bytes, on the FreeDOS
diskette and in the folder `SHARED`): a picture on pages 6 and 7, another
drawn on pages 4 and 5 while the first is shown, then the screen from one
to the other and the palette round until a key. On a PC that is not a
Tandy it says so and ends.

```
VIDEO=TANDY python3 -I tools/cga_test.py third_party/freedos/fd/TDYDEMO.COM 200
```

or add the line `VIDEO=TANDY` to the volume's `XTGS.CMD` and run `TDYDEMO`
at the prompt.
