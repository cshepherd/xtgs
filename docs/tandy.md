# Tandy 1000: video modes 08h, 09h and 0Ah, and the three-voice sound

With the line `VIDEO=TANDY` in `XTGS.CMD` the PC is a **Tandy 1000**: its
BIOS's two identifying bytes, its page register and video array, and its
three graphics modes of 200 lines. Mode **09h is 320x200** in 16 colours: four bits a
pixel, the left pixel a byte's high four, 160 bytes a line: the Super
Hi-Res 320 mode a byte for a byte, so a line goes to the screen with one
block move and a colour number is a colour number. Mode **08h is
160x200**: the same pixels twice as wide, 80 bytes a line in one page of
16K laid out as the CGA's graphics are, each byte through a table to two
of the SHR's. Mode **0Ah is 640x200 in four colours**, in mode 09h's
32K: a line is eighty pairs of bytes, the even byte of a pair one bit of
eight pixels' colours and the odd byte the other, which the SHR's 640
mode, two bits a pixel, takes as a pair woven into a word. The array's **palette registers and mask** stand behind the
CGA's modes too (4, 5, 6 and the 160x100 text mode), as on the machine: a
program that never leaves mode 4 can show its four colours as any four
of the sixteen. And the **BIOS's text** is drawn in the three modes
(`INT 10h`'s character services, and so DOS's console): 40 columns in
mode 09h, 20 in mode 08h and 80 in mode 0Ah, the prompt there after a
program that leaves the mode set.

And the machine's **sound chip** is there, the SN76496 at port C0h:
three square waves and a noise, each a pair of the Ensoniq DOC's
oscillators beside the speaker's and the timer's (The sound chip, below;
docs/sound.md has the whole of it).

These are the steps of `XTGS_Tandy_1000_Graphics_and_Sound_Plan.md`.

```
make test-com COM=tandy        mode 09h: the pages, the array, the BIOS: 51 cases and a picture
make test-com COM=tandyp       the same, the mode set by the ports, the screen's page not the CPU's
make test-com COM=tandy8       mode 08h: 36 cases and a picture
make test-com COM=tandy8p      the same, the mode set by the ports, the screen's page at BC00
make test-com COM=tandya       mode 0Ah: 42 cases and a picture
make test-com COM=tandyap      the same, the mode set by the ports, pages 2 and 3, the palette turned round
make test-com COM=tandyax      out of it by the array's mode register: mode 6 on the same bytes
make test-com COM=tandyat      out of it by 3D8h: text
make test-com COM=ttext        the BIOS's text in mode 09h: 83 cases and a picture
make test-com COM=ttext8       ... in mode 08h, ttexta in mode 0Ah
make test-com COM=ttextp       ... in mode 09h on the CPU's pages while the screen shows two others
make test-com COM=gtextt       CGA mode 4 and the BIOS's text in it, on the Tandy
make test-com COM=tandyc4      the array's palette and mask behind mode 4's colours
make test-com COM=tandyc5      ... mode 5's, tandyc6 mode 6's, tandyct the 160x100 mode's
make test-com COM=tandyc9      INT 10h 0Bh in mode 09h: palette register 0
make test-com COM=psg          the sound chip: 129 bytes to it, every DOC register they lead to judged
make test-com COM=psgpc        the same program on a PC: nobody at port C0h
make test-psg                  fourteen sounds recorded by MAME and measured
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
this is there: modes 08h, 09h and 0Ah are not modes, ports 3DAh-3DFh are
the CGA's.

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
  `03h` the mode register (bit 4: 16 colours; bit 3: four colours at 640
  across), `10h`-`1Fh` the sixteen
  palette registers, each one of the CGA's sixteen colours. A pixel's
  four bits go through the mask and then through the palette, in every
  graphics mode and in the 160x100 text mode (the CGA's modes: the last
  bullets here). The registers are write-only, as the Tandy's are.
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
- `INT 10h AH=00h AL=0Ah` sets mode 0Ah (`AL=8Ah`: without clearing): the
  page register `F6h` as in mode 09h, the array's mask `0Fh` and palette
  0-15 (so the four colours are black, blue, green and cyan until the
  program writes registers 0-3), its mode register `0Ch`, `3D8h` = `3Bh`,
  `3D9h` = `3Fh`, the 32K cleared, the BDA mode 0Ah and 80 columns.
- **The modes by the ports**: `3D8h` with bit 1 (graphics) while the
  array's mode register has bit 4 is a 16-colour mode, 09h with bit 0
  (320 across) and 08h without, entered at the next frame without
  clearing anything, as on the machine. A program that sets one this way
  sets the page register itself. `3D8h` written again with the other
  value of bit 0 goes from one to the other, the bytes as they are.
  Without bit 4 of the mode register, its bit 3 with `3D8h`'s bits 1 and 4
  (graphics, 640 across) is mode 0Ah, entered the same way; take the
  mode register's bit away and the same bytes are the CGA's mode 6 (their
  first 16K, as two fields), take `3D8h`'s bit 1 and they are text.
- In mode 09h line `y` is in the 8K bank `y & 3` of the 32K, at
  `(y >> 2) * 160`. The screen is the two pages the register's low three
  bits name (the even one and the next), wherever the CPU's are: draw on
  pages 4 and 5 while 6 and 7 are shown, then show 4 and 5.
- In mode 08h line `y` is at `(y & 1) * 2000h + (y >> 1) * 80` of one
  page, a byte two pixels, the left one its high four bits. The screen
  is the page the register's low three bits name, any of the eight, and
  again not necessarily the CPU's: eight pictures fit, and with an even
  CPU page the screen's can be the one at `BC00`.
- In mode 0Ah the lines are where mode 09h's are (the bank `y & 3`,
  `(y >> 2) * 160`) and the screen is the same two pages. A line's 160
  bytes are 80 pairs, a pair eight pixels with bit 7 the leftmost: pixel
  `x` is bit `7 - (x & 7)` of the bytes at `(x >> 3) * 2` and the one
  after, the **even byte the colour's low bit and the odd byte its high
  bit**. The colour, 0-3, goes through the mask and names a palette
  register, as everywhere.
- `INT 10h` in the modes: `0Ch`/`0Dh` (a pixel, in the CPU's pages; bit 7
  of `AL` for XOR; in mode 08h `CX` is 0-159, in mode 0Ah 0-639 and the
  colour `AL`'s low two bits), `0Fh`, `05h` with `AL=80h` (`BH` the screen's page,
  `BL` the CPU's), `81h` (the CPU's from `BL`), `82h` (the screen's from
  `BH`), `83h` (both), and `10h` with `AL=00h` (palette register `BL` from
  `BH`), `01h` (the border), `02h` (all sixteen and the border from the 17
  bytes at `ES:DX`). `05h` and `10h` are there in every mode on a Tandy.
- **The BIOS's text in the three modes**: `INT 10h` `06h`-`0Ah`, `0Eh` and
  `13h`, and DOS's console through them. A character is the 8x8 font in
  a cell of eight pixels by eight lines, so the screen is 25 rows of
  **40 columns in mode 09h, 20 in mode 08h and 80 in mode 0Ah** (the
  BDA's count, and what `0Fh` answers). `09h`/`0Ah` draw `CX` characters
  in colour `BL` (0-15; in mode 0Ah its low two bits) on colour 0, bit 7
  of `BL` XORing the glyph into what is there; the teletype draws in
  `BL` and DOS's console in 7 (3 in mode 0Ah); `06h`/`07h` move the
  window's pixels and fill the freed rows with **the colour in `BH`**
  (its low four bits; in mode 0Ah its low two); `08h` reads the cell
  back as a character, a pixel of any colour but 0 a set bit. The text
  goes to the pages the CPU has at `B800`, as the pixel calls do: with
  the page register showing two others it is drawn unseen. The cursor
  is the BDA's (page 0's) and is not drawn.
- The CGA's modes are there (4, 5, 6, the 160x100 text mode, the BIOS's
  text in them): a Tandy runs CGA programs. Their colours are the CGA's
  **put through the array**. The CGA's logic gives each pixel one of the
  sixteen colours (docs/cga.md): in mode 4 the background in `3D9h`'s low
  four bits for pixel 0 and 2/4/6 or 3/5/7 (10/12/14, 11/13/15 with the
  intensity bit) for pixels 1-3; in mode 5 cyan, red and white for those;
  in mode 6 colour 0 for a clear pixel and `3D9h`'s for a set one; in the
  160x100 mode the attribute's two halves. That number is ANDed with the
  mask and names the palette register whose colour is shown. With the
  registers as a mode set leaves them (mask `0Fh`, register n = n) nothing
  changes; a game written for the 1000 writes three or four of them and
  has a mode 4 in colours no CGA shows. Note that mode 6's clear pixels are
  register 0 and not black, and that the mask applies to the background
  too.
- `INT 10h AH=0Bh` is the CGA's, and with `BH=0` also writes the border
  register (not in mode 6) and, in modes 08h and 09h, palette register 0
  from `BL`'s low four bits: the background of a 16-colour picture. In
  mode 0Ah it writes the border register and the BDA's copy of `3D9h`
  and no colour changes.

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
if the half of the window it is in holds a page that is shown, the two
or three rows its 256 bytes lie in (`tdy_r0`/`tdy_r1`) are moved, a row
that two flags share once (`tdy_nx`, the 8K's first row not yet drawn).
A row is 160 bytes by `MVN` from the page to `$E1:2000` (`tdy_row`). A store to a page
that is the CPU's and not the screen's costs a flag and nothing more.
A frame in which no flag is set, which is most of them, costs the look
at the flags eight at a time (`tdy_dirty`: some 0.7 ms of the frame's 17
at the stock clock).

Mode 0Ah is drawn by the same routine: the same pages, flags and rows,
the SHR's lines in 640 mode (`tdy_show` sets the two hundred SCBs), and
`tdy_row` on its other path. There a row is not a move: for each pair
the even byte and the odd byte go through `cga640_tab` (mode 6's table:
a byte's eight bits each doubled, a word of the 640 mode's eight
two-bit pixels) and the row's word is the even one's low bits and the
odd one's high bits, `(tab[even] & $5555) | (tab[odd] & $AAAA)`. The
640 mode gives the four pixels of a byte four different quarters of the
palette (entries 8-11, 12-15, 0-3 and 4-7), so `tdy_setpal` makes all
sixteen entries in this mode from four: entry `n` is the colour of
`n & 3` (through the mask and the registers), and a pixel's two bits
mean the same colour in every column.

Mode 08h (`tdy_flush8`) is the same with one page and the CGA's rows:
the page shown is found in its slot, and a set flag counts when its half
of the window holds that page; its 256 bytes lie in three or four of the
8K's hundred rows of 80 (`gpg_r0`/`gpg_r1`, the CGA's table), and a row
two flags share is drawn once (`tdy_nx`). A row is not a block move: each
byte is two pixels and the SHR wants each twice, so `tdy_row8` takes a
byte through `tdy8_tab` (`src/svc/gen/tdytab.s`, 256 words: the high four
bits as the first byte, the low four as the second) to a word of the
line, some 41 cycles a byte where mode 09h's move is 7.

### The array behind the CGA's colours (`tdy_col`)

`cga_setpal` and `cga_setpal6` (`video.s`) make the SHR's palette from
colour numbers, and every number goes through `cga_ent`, which asks
`tdy_col`: on a PC the number itself, on a Tandy
`palette[number & mask]`. The 160x100 mode's sixteen entries are
`tdy_setpal`'s, the routine of modes 08h and 09h (entry `n` is
`cga_rgb[tdy_col(n)]`). A write of a palette register or of the mask
raises `tdy_pald` in any mode, and `gfx_flush` and `t160_flush` make
their palette again when it or the CGA's own flag (`cga_pd`) is up:
nothing is drawn again, the SHR's palette being apart from its pixels.
`tdy_0B` is the Tandy's part of `INT 10h AH=0Bh`.

### The mode and the ports

The core sends ports 3DAh-3DFh to SVC in both modes of running
(`port_out`, `svc_portout`, `tdy_port`); the others the CGA has are the
core's as before. A write of `3D8h` or of the array's mode register raises
`CGA_MODECHG`, and at the frame `apply_cgamode` asks `tdy_mode` first:
it enters mode 08h, 09h or 0Ah (`tdy_show`; `gfx_mode` is `GFX_TDY8`,
`GFX_TDY9` or `GFX_TDYA`), or leaves them for the CGA's logic: with
`3D8h`'s graphics bit still set the CGA's mode 4 or 6 is made of the
bytes at `B800`, and without it and with the enable bit, text.
`vid_setmode` calls `tdy_modeset` for every mode (the registers the BIOS
resets) and `tdy_enter` for 08h, 09h and 0Ah. The pixel calls are
`tdy_pixel` for the three (the byte's place) and then `tdy_setpix`, or in
mode 0Ah `tdy_setpixA`, which writes one bit in each byte of the pair.

### The BIOS's text (`src/svc/gtext.s`, `tdy_cell`, `tdy_draw`)

`gtext.s` is the BIOS's text in every graphics mode (docs/cga.md): the
services' logic (the cursor, the wrap, the control characters, the
window's clamping, the rows a scroll moves) is one, and what differs by
mode is where a cell is and what a glyph's line is in bytes. For
`gfx_mode` 8 to 0Ah (`tdy_gm`) its routines hand those to `tandy.s`:

- `tdy_lnoff` is a line's offset in the bank of `B800` (modes 09h and
  0Ah: the 8K bank `y & 3`, `(y >> 2) * 160`; mode 08h: the bank
  `y & 1`, `(y >> 1) * 80`), which `tdy_pixel` uses too. `tdy_cell`
  makes a cursor position the cell's first line (`row * 8`) and its byte
  in a line: `column * 4` in the 16-colour modes, where a cell is eight
  pixels of four bits, and `column * 2` in mode 0Ah, where it is one
  pair of bytes.
- `tdy_draw` writes the eight lines. In the 16-colour modes a line of
  the font is four bytes, two bits of it a byte (`tdy_ntab`: `00`, `0F`,
  `F0`, `FF`) ANDed with the colour in both halves; in mode 0Ah the even
  byte is the font's line when the colour has bit 0 and nothing when it
  has not, and the odd byte the same for bit 1. The four bytes of a line
  are in one 256 (a cell's offset is a multiple of four) and one mark
  (`tdy_pmark`) covers them.
- `tdy_read` gathers the cell's eight lines as a glyph (a nibble, or
  either byte of a pair, that is not 0 is a set bit) for `gt_find`.
- `gt_scroll` makes the window's width and left edge bytes (four a
  column, two in mode 0Ah) and its rows lines, and `tdys_copy` and
  `tdys_fill` move or fill one line of it with an `MVN` or a loop,
  marking the 256s of its first and last byte (a line's bytes are at
  most 160, so in two at most). `tdy_fillw` makes `BH` the two bytes
  that are eight pixels of that colour.

Everything is written through the window at `B800`, so it lands on the
CPU's pages wherever the page register has them, and the marks are the
core's marks: `tdy_flush` draws what changed at the next frame if those
pages are the ones shown. `int_10` no longer turns the character
services away in the three modes, `vid_tty` no longer skips the
drawing, and `con_out`'s tab goes to the next column of eight there as
in text.

## The sound chip (`src/svc/sound.s`, docs/sound.md)

A byte written to any of ports C0h-C7h is a byte to the SN76496
(`psg_write`, by `svc_portout` from the core in both modes of running):
three tones of 3,579,545 / 32n Hz for a ten-bit period n, a noise that is
a 15-bit shift register's output (white) or one bit in fifteen
(periodic) at one of three rates or at tone 2's, and an attenuation of
2 dB a step for each. The IIGS's DOC plays them: on a Tandy it runs
eleven oscillators where a PC has three, the speaker's two, a pair for
each tone and for the noise (one on each of the DOC's channels) and the
timer's. A tone is the speaker's square wave at the chip's frequency (to
0.002 %); the white noise is the shift register's 32,767 bits written
out to DOC RAM at the start and played at the chip's rate, so the
sequence itself and not a likeness of it; the periodic noise is a pulse
a fifteenth of a cycle wide. docs/sound.md has the arithmetic, what is
kept for the harness and what was measured.

The speaker and the timer are as on a PC, at the constant eleven
oscillators need. On a PC that is not a Tandy the ports are nobody's.

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
  7 at `B800`. `tandy8p` enters from text by the ports (`3D8h` = `2Bh` for
  a frame, which is mode 09h, then `2Ah`) with pages 6 and 7
  the CPU's and 7 the screen's, so that the picture is at `BC00`; gives
  the CPU pages 2 and 3 for a while and fills them; brings 7 back and
  writes it over, so that the lines drawn piece by piece from `BC00` are
  what the judge sees; and fills page 6, at `B800` and not shown. With
  the odd lines' rows drawn as the even ones' (one line of `tdy_flush8`
  taken out) both fail, `tandy8p` by 281 bytes.
- `tests/com/tandya.asm` (`tandya`, and `tandyap`, `tandyax`, `tandyat`
  with the command lines `P`, `X` and `T`): 42 cases in mode 0Ah: the
  mode and the BDA (80 columns, `3Bh` and `3Fh` at `40:65` and `40:66`,
  pages 6 and 7), the 32K as memory, the pixel calls (the two bytes of a
  pair each alone and together, the first and last of the screen, XOR,
  a colour over another, the read, off the screen at x = 640 and y =
  200), the pages, the mode set that keeps the screen, `AH=0Bh` (the
  BDA's copy and nothing else), text again and back. Then a picture:
  sixteen bars of forty pixels, the colour one on every eight lines,
  half of the bars with every other pixel a colour on and half with two
  pixels in four two colours on, so that the two bytes of the pairs
  differ and an exchange of them or of the bits' order is seen; left for a frame and written over (a
  diagonal by the pixel call through all 200 lines, the ends of each
  bank, a word across two 256s, `REP STOSB` over a line, `REP STOSW`
  across the 16K, `REP MOVSW` of a row). The judge (`"video": "tandyA"`)
  wants all 200 SCBs in 640 mode, makes each line's 160 SHR bytes from
  the two pages shown, and wants the sixteen palette entries to be the
  four colours four times. `tandya` ends in the BIOS's mode on pages 6
  and 7 with the first four registers written (0, 12, 14, 3). `tandyap`
  enters from text by the ports (the mode register `0Ch`, `3D8h` =
  `3Bh`), draws on pages 2 and 3 with the palette turned round behind a
  mask of `0Eh` (which makes the four colours two), and at the end gives
  the CPU pages 6 and 7 and fills them, which must not show. `tandyax`
  draws the picture and takes the mode register's bit away: the screen
  must be mode 6 of the same bytes in colours 0 and 15 (`"video":
  "cga6"`, `tools/cgashr.py`). `tandyat` fills the window with blanks and
  takes `3D8h`'s graphics bit: the text screen must show them. With the
  two bytes of a pair exchanged in `tdy_row` `tandya` fails by 27,866
  bytes; with `tdy_setpixA` not marking what it wrote, by 141; with
  `tdy_setpal` taking three bits of an entry's number, `tandyap` by
  eight palette entries.
- `tests/com/ttext.asm` (`ttext` in mode 09h, `ttext8` with the command
  line `8` in mode 08h, `ttexta` with `A` in mode 0Ah, `ttextp` with `P`
  in mode 09h after `out 3DFh, E6h`: the CPU on pages 4 and 5, the
  screen on 6 and 7): 83 cases, by what is in the window afterwards.
  The test has eleven glyphs of the font of its own and draws a cell
  with ordinary instructions to compare (the line's place by the mode's
  rule, the glyph's bits as nibbles or as the two bytes of a pair). The
  cases: the columns and the BDA; a clear and a window filled in a
  colour; `09h` in several colours, with XOR, with a count that runs
  past the row's end, off the screen; `0Ah`; `08h` on what was written,
  on a blank and on pixels that are no character; the teletype (CR, LF,
  BS, BEL, the wrap at the last column, the scroll at row 24); a window
  scrolled up and down, cleared, clamped; `13h`; DOS's console (its
  colour, a tab to column 8); the pixel calls on a cell. It ends on a
  picture: drawn, left for two ticks, written over by `09h`, scrolled
  by the teletype, the result printed on row 24, two more ticks and
  three last characters, so that each service's marks are what puts
  its bytes on the screen. `tools/tandyshr.py` judges it as it does the
  modes' own tests (`ttextp`: pages 6 and 7 are judged, and must still
  be the picture as it was drawn, with nothing of what came after).
  With `tdy_draw` not marking, the picture fails in the three modes by
  87, 120 and 54 bytes; with `tdys_copy` not
  marking, by thousands; with a fill a byte short, seven or eight cases; with
  `tdy_read`'s low nibble not looked at, one; with XOR not done, four.
- The modes' own tests (`tandy`, `tandy8`, `tandya` and the rest) print
  their result through DOS when the picture is done: it is now drawn on
  the picture's last rows, and the judge compares the screen with the
  memory as before.
- `gtextt` is `gtext` (mode 4, the BIOS's text) with the line: the CGA's
  modes on the Tandy.
- `tests/com/cgapal.asm` with the line (docs/cga.md has the test without
  it): a picture in the mode, then registers written by `INT 10h AX=1000h`
  and by the ports with frames between, ending on a write that changes
  colours only. The judge works out what the screen's colours must be
  from `3D8h`, `3D9h`, the mask and the sixteen registers
  (`tools/cgashr.py`'s `colours`) and compares the SHR's palette; the
  manifest gives the colours (`"cga_colours"`), the registers
  (`"tandy_pal"`) and the mask (`"tandy_mask"`) expected.

  | Manifest | Mode | What is written | Colours shown |
  | --- | --- | --- | --- |
  | `tandyc4` | 4, colours 1, 10, 12, 14 | registers 1, 10, 12, 14; then a mask of `0Dh`, which makes 10 register 8 and 14 register 12 | 5, 8, 2, 2 |
  | `tandyc5` | 5, colours 6, 3, 4, 7 | a mask of 7, registers 3, 4, 6, and 7 a frame later | 0, 13, 10, 1 |
  | `tandyc6` | 6, foreground 10 | register 0 (the ground), register 10 | 1, 11 |
  | `tandyct` | 160x100 | registers 4 and 15, a mask of 7, register 2 a frame later | all 8,000 cells in the sixteen entries |
  | `tandyc9` | 09h | `INT 10h AH=0Bh`, `BX=0013h` | register 0 is 3 |

  With `gfx_flush` not looking at `tdy_pald` the first three fail on the
  palette.
- A manifest's `"cmd"` is the lines of `XTGS.CMD` after the command's.
- Under FreeDOS: `VIDEO=TANDY CAP=1 python3 -I tools/cga_test.py
  path/TANDY.COM 420` prints the same 51 cases and judges the screen the
  same way (`CAP=1`: the end of what the teletype printed); with
  `TANDY8.COM` the 36, the screen judged as mode 08h, and with
  `TANDYA.COM` the 42 as mode 0Ah (the tool reads which of the three
  from the mode registers). `TTEXT.COM` the same way (`ARGS=8`,
  `ARGS=A`) prints its 83 cases and leaves the mode set: FreeDOS's
  prompt is on the picture.

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
| `REP STOSW` over the 32K, and the redraw | 0.21 s |
| `mov [es:di],al` in a three-instruction loop | 0.21 ms a pass |
| `INT 10h AH=0Ch` in a six-instruction loop | 1.0 ms a pixel |

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

Mode 0Ah:

| Work | Time |
| --- | --- |
| The mode set (32K cleared, the screen drawn) | 0.54 s |
| The whole screen drawn (after the page register changes) | 0.46 s |
| The screen's page changed (`AX=0582h`) | 0.46 s: the drawing |
| The CPU's two pages changed for two others (`AX=0581h`) | 0.62 s: four moves and the drawing |
| `REP STOSW` over the 32K, and the redraw | 0.55 s |
| `mov [es:di],al` in a three-instruction loop | 0.33 ms a pass |
| `INT 10h AH=0Ch` in a six-instruction loop, a pixel a line | 3.6 ms a pixel |

The memory is mode 09h's and the screen costs four times as much: a
row is eighty pairs through the table twice, 2.3 ms where mode 09h's
move is 0.6. The pixel call's own work is under a millisecond; the rest
of the 3.6 is the row each pixel is on, and its neighbours in the same
256 bytes, drawn again.

The BIOS's text, the three modes side by side (a call's time is what it
takes more than an `INT 10h` that does nothing, 0.5 ms):

| Work | 09h | 08h | 0Ah |
| --- | --- | --- | --- |
| A character by the teletype (`AH=0Eh`), eighty in a loop | 5.9 ms | 6.0 ms | 7.3 ms |
| A row written by one `AH=09h` (40, 20, 80 characters), and its redraw | 71 ms | 51 ms | 110 ms |
| The whole screen up a row (`AX=0601h`) | 0.24 s | 0.35 s | 0.57 s |
| The whole screen cleared (`AX=0600h`) | 0.23 s | 0.34 s | 0.56 s |

A scroll of the whole screen is a move of the 32K (or 16K) and then
the whole screen drawn again, since every byte changed: the second
part is the table above's "whole screen drawn", and in mode 0Ah it is
four fifths of the time. A listing that scrolls at the bottom of a
mode 0Ah screen comes at under two lines a second on the stock clock.
The teletype's characters are slower than `09h`'s because each is a
call, and because the frames that pass meanwhile each draw the lines
of the cell being written again.

## Limits

- **Mode 0Ah is built from what two emulators do, and they differ.**
  Which byte of a pair is which bit of the colour is MAME's reading
  (DOSBox's drawing was not read). By the ports MAME wants `3D8h`'s bit 4 with the
  mode register's bit 3, and so does this; DOSBox takes the mode
  register's bit alone. What the BIOS's mode set leaves in the registers
  is DOSBox's (its BIOS is its own): the palette 0-15, so black, blue,
  green and cyan, which a real 1000's BIOS may not leave. `AH=0Bh` does
  nothing to the colours in the mode (DOSBox leaves that undone as
  well). And one page of a Tandy 1000 HX manual says of the mode "only
  supported on the IBM PCjr", where MAME, DOSBox and the mode tables
  give it to the 1000: on a PCjr the same bit of the mode register is
  said to be a two-colour 640. None of it has been held against a real
  machine or a program written for the mode.
- **The BIOS's text in the three modes is this BIOS's, not a Tandy's
  read.** What is certain is the cell (8x8, so 40, 20 and 80 columns)
  and that the services draw. Decided here and not held against a
  Tandy's BIOS: that a scroll's `BH` is a colour whose low four bits
  fill each pixel (two bits in mode 0Ah), that the teletype from DOS is
  colour 7 (3 in mode 0Ah), that `09h`'s ground is colour 0 and bit 7
  of `BL` XORs in all three, and that `08h` takes any pixel that is not
  0 as set. One cursor, the BDA's first, whatever page `BH` names; no
  cursor is drawn (a PC draws none in graphics either). The font is the
  built-in one, characters 01h-1Fh blank, and `INT 1Fh`'s and `INT
  44h`'s tables are not consulted. The text is drawn on the CPU's
  pages, which a real BIOS may or may not do when the screen shows
  others. A scroll redraws the whole screen (the costs above).
- In text and in the CGA's modes the screen is the CPU's page: a program
  that shows one page and writes another there sees what it writes. The
  border is not shown.
- The array's palette is not applied to 80x25 text. While the array's
  index (the last byte written to `3DAh`) is a palette register's, the
  real machine shows that register's colour for every pixel (MAME models
  it; programs write the registers in the retrace or put the index back):
  not here. On whether the mask applies to the background and to mode 6
  the two emulators read differ; this follows MAME, which masks both.
- Which of the two 16-colour modes the ports mean is read from `3D8h`'s
  bit 0 alone, as DOSBox reads it; the array's mode register is looked
  at for bits 4 and 3 only.
- With an odd CPU page the real machine shows the same 16K again at
  `BC00`; here `BC00` is nobody's memory then.
- The page register's bits 6-7 are kept and not acted on; the array's
  other registers (`00h`, `04h`-`0Fh`) are not kept. `3DAh` reads as the
  CGA's status.
- The sound chip's limits are in docs/sound.md (Not done): no tone
  period under 6 and so no sampled sound through the chip, TI's noise
  sequence and not the NCR part's, a voice's cycle begun again at each
  new period, port 61h's multiplexer and the BIOS's sound services not
  there, and none of it heard on a real IIGS.
- The Tandy's keyboard and the PCjr's differences (its cartridge-less
  ID, its 3DAh flip-flop) are not there.
- A `REP` over the 32K is one instruction (some 90 ms of nothing else at
  the stock clock, by the cycles of a block move), and a page move is 40
  ms with nothing else: a tick that falls in them is made up afterwards
  (`clk_sync`).
- No Tandy program has been run here. The registers, the layout of the
  lines and what the BIOS sets are from the Tandy 1000 SX Technical
  Reference, Ralf Brown's interrupt list and a reading of what MAME's and
  DOSBox's Tandy video do; the test's cases and the judge's decoding are
  written from the same, and no other emulator is in the loop. The three
  modes have been run in MAME only.

## Try it

`TDYDEMO.COM` (`tests/demo/tdydemo.asm`, 468 bytes, on the FreeDOS
diskette and in the folder `SHARED`): a picture on pages 6 and 7, another
drawn on pages 4 and 5 while the first is shown, then the screen from one
to the other and the palette round until a key. `TDYDEMO 8` is the same
in mode 08h, a page a picture (7 and 5), in cells of four of its wide
pixels: the same pictures, and the difference to see is the time each
change of the screen takes. `TDYDEMO A` is mode 0Ah: the same cells in
sixteen shades made of four colours (each colour, and three mixtures
with the next in two, four and six pixels of eight), and the palette's
turn brings the colours through registers 1-3. On a PC
that is not a Tandy it says so and ends.

```
VIDEO=TANDY python3 -I tools/cga_test.py third_party/freedos/fd/TDYDEMO.COM 200
VIDEO=TANDY ARGS=8 python3 -I tools/cga_test.py third_party/freedos/fd/TDYDEMO.COM 200
VIDEO=TANDY ARGS=A python3 -I tools/cga_test.py third_party/freedos/fd/TDYDEMO.COM 200
```

or add the line `VIDEO=TANDY` to the volume's `XTGS.CMD` and run `TDYDEMO`
(or `TDYDEMO 8`, `TDYDEMO A`) at the prompt.

`TDYSND.COM` (`tests/demo/tdysnd.asm`, 466 bytes, in the same places) is
the sound chip: "Frere Jacques" as a round, the three tones coming in
two bars apart (the third an octave up), each note struck and let fall
by its attenuation register, the noise ticking the beat; 26 seconds by
the BIOS's tick, or until a key. In MAME's recording of it the bars one
voice sings alone are at their pitches eighth by eighth and the others
show each voice's line where it should be. Where two voices meet on one
note (the second "Frere Jacques" against the first "ding dang dong")
what is heard depends on how far apart their cycles started, as on the
chip: here the two all but cancel for four eighths, and the octave above
is what is left.
