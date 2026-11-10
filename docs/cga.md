# CGA graphics

XT/GS renders CGA graphics on the IIGS Super Hi-Res screen:

- **Mode 4/5** (`SCREEN 1`): 320x200, 4 colours. The IIGS 320 mode is 320x200
  at 4 bits a pixel, a strict superset of CGA's 2 bits a pixel.
- **Mode 6** (`SCREEN 2`): 640x200, black and one colour. Maps onto the IIGS 640 mode (the same
  mode the text screen uses).

- **160x100, 16 colours**: the "text-cell" mode some CGA games use (Tunneler,
  for one). It is 80-column text with the character rows cut to two scan
  lines; see [its own section](#160x100-16-colours) below.

The resolutions line up by design, not coincidence, so the work is repacking a
bitmap, not scaling it. The colours are the colour-select register's
(`3D9h`, `INT 10h AH=0Bh`, the `COLOR` statement): the background and the
three palettes of the 320 modes, and in mode 6 the colour of the pixels
that are set. On a Tandy 1000 (`VIDEO=TANDY`) they go through the video
array's palette as well (docs/tandy.md).

## How it works (`src/svc/video.s`, `src/core/ops_misc.s`)

- **Mode set.** `INT 10h AH=00` (`v10_00` in `bios.s`) calls `vid_setmode`.
  Modes 4/5 and 6 go to `gfx_setup`, which configures the SHR and clears it and
  the 16 KB CGA framebuffer; any other mode restores 640-mode text (`init_shr`
  + `vid_clear`). For 320 (4/5) it sets every SCB to `$00` and the palette from
  the CGA colour state (below). For 640 (6) it sets every SCB to `$80` and a
  two-colour palette (`cga_setpal6`): `cga640_tab` emits pixel value 3 or 0,
  and in 640 mode the four pixel positions read palette groups based at
  entries 8/12/0/4, so entries 3/7/11/15 are the foreground and the rest
  black. GW-BASIC's `SCREEN 1` sets mode 4 (the tree's interpreter does
  for `SCREEN 1,1` as well: the BDA's mode is 04h after either) and
  `SCREEN 2` mode 6. The mode set leaves the two registers as
  a PC's BIOS does: mode control (`3D8h`) `2Ah` in mode 4, `2Eh` in mode 5
  and `1Eh` in mode 6, colour select (`3D9h`) `30h`, and `3Fh` in mode 6;
  and their copies in the BDA at `40:65` and `40:66` (`cga_bda`).
- **The guest draws itself.** GW-BASIC (like most CGA software) bypasses
  `INT 10h` for its drawing and writes pixels straight into the CGA
  framebuffer at B800:0000
  (host `$2B:8000`) - the same 16 KB aperture as text, but as a bitmap, 80
  bytes a scanline, with the **CGA interleave** (even scanlines at B800:0000,
  odd at B800:2000). Mode 4/5 is 2 bits a pixel (4 px/byte); mode 6 is 1 bit a
  pixel (8 px/byte). Its text is another matter: that goes through the BIOS
  ([below](#text-in-the-graphics-modes)).
- **Repack.** Each frame `gfx_flush` repacks only the scanlines that changed
  (see below); `gfx_blit_line` de-interleaves one screen line and expands each
  CGA byte into two SHR bytes - through `cga320_tab` in 320 mode or `cga640_tab`
  in 640 mode. Both modes are 80 CGA bytes -> 160 SHR bytes a line, so the blit
  structure is identical. `shr.py` understands both SHR modes, so the headless
  screenshot renders correctly.
- **Palette / `COLOR`.** The CGA colour-select state (`cga_bg`, `cga_pal`,
  `cga_int`) is fed by **both** `INT 10h AH=0Bh` (`v10_0B`: `BH=0`, bits 0-3
  of `BL` the background and bit 4 the intensity; `BH=1`, bit 0 of `BL` the
  palette; `40:66` kept as the BIOS keeps it) and a write to port **`3D9h`**
  (`port_out`: bits 0-3 background, bit 4 intensity, bit 5 palette), so
  GW-BASIC's `COLOR` statement works whichever path it uses. A change sets
  `cga_pd`, and `gfx_flush` applies it via `cga_setpal`, which writes SHR
  palette 0 entries 0-3: entry 0 = `cga_rgb[background]`, entries 1-3 = the
  selected palette's three colours (`fg_tab`: palette 0 = green/red/brown,
  palette 1 = cyan/magenta/white, dim or intensified). The palette lives
  separately from the pixels, so a `COLOR` change recolours the screen with
  no re-blit.
  - **Mode 5** (bit 2 of `3D8h`, the colour burst off) has one palette
    whatever bit 5 of `3D9h` says: cyan, red and white (3, 4, 7, or 11, 12,
    15 with the intensity bit). `3D8h` written again with only that bit
    changed changes the colours and nothing else.
  - **Mode 6**: a pixel that is clear is black and one that is set is the
    colour in bits 0-3 of `3D9h`. The BIOS's mode set makes that white
    (`3Fh`); a program that enters the mode by `3D8h` alone has whatever
    `3D9h` held, as on a CGA (from text that is `30h`: black on black until
    it writes the register, which such programs do).
  - The BIOS's `30h` is palette 1 with the intensity bit: modes 4 and 5
    start in the bright colours. `AH=0Bh` with `BH=0` and a `BL` below 16
    clears the bit, so a program that sets a background that way gets the
    dim ones, as on a PC.
  - On a Tandy each of these colours is then a number put through the video
    array's mask and palette registers (`cga_ent`, `tdy_col`): docs/tandy.md.
- **`3DAh` status register** (`port_in8`): returns a free-running value so the
  guest's retrace/display-enable poll loops terminate instead of spinning on a
  constant open-bus read.

## Dirty-region blitting

A full-screen repack is ~880 K 65816 cycles. Run every VBL it saturated the
IIGS CPU and starved the 8086 interpreter - measured: the guest crawled at
~1 pixel/second, drawing only ~230 framebuffer bytes before the frame was
captured. So the blit is **per-scanline dirty**: only the lines the guest
actually changed are repacked each frame.

- The core already notes guest writes to the B800 bank. `vid_mark` (`cpu.s`)
  sets a bit in `VID_DIRTY` (in the RES bank) per 256-byte page written. That
  mask was widened from the 16 pages of the 4 KB text aperture to the **64
  pages** of the 16 KB graphics aperture (`and #$3F00`); text still falls in
  pages 0-15, so it is unaffected.
- Each frame `gfx_flush` walks the 64 page bits. A dirty page maps to a short
  run of rows in its field via the precomputed `gpg_r0`/`gpg_r1` tables (page
  p<32 is the even field, p>=32 the odd; screen line = row*2 + parity), and
  each such scanline is repacked by `gfx_blit_line` and the bit cleared. A line
  that straddles two pages is fully re-blitted when either page is dirty, so
  nothing is missed.
- Cost is now O(changed scanlines), not O(screen): a small moving sprite
  dirties a handful of lines a frame and the interpreter keeps running, with no
  update lag. The old full-screen cost only recurs when the guest actually
  rewrites the whole screen in one frame (e.g. a `CLS`), which is one frame's
  work. **Measured** (stock clock, GW-BASIC running a continuous localized
  animation, `vICOUNT` deltas over a 100 s window): **~8,800 guest IPS with
  dirty-region vs ~330 IPS blitting the whole screen every frame - a ~26x
  speedup** on the identical workload. The full-screen version barely advances
  the guest at all; that is why the first spike needed the ~1 Hz throttle, now
  removed.

## Text in the graphics modes

In modes 4, 5 and 6 B800 holds pixels, and a PC's BIOS draws its characters
into them from an 8x8 font. `src/svc/gtext.s` does the same for every text
service of `INT 10h`; `bios.s` and `video.s` go there when `gt_on` says the
screen is CGA graphics (the 160x100 mode is text cells and does not).

GW-BASIC depends on all of it. In `SCREEN 1` it clears the screen with
`AH=06h` (`AL=0`, `BH=0`, the window 0,0 to 24,79), writes every character
of a `PRINT`, of a typed line and of the function-key line with `AH=09h`
(`CX=1`, `BL=3`) after putting the cursor in the BDA, reads the line under
the cursor back with `AH=08h` when Return is pressed, and takes the width of
the screen from the BDA.

- **A cell** is 8x8 pixels: four lines of the even field and the same four
  of the odd one, `row*320 + column*2` into each in the 320 modes (40
  columns, two bytes a cell) and `row*320 + column` in mode 6 (80 columns, a
  byte a cell). `v10_00` sets `BDA_COLS` to 40 or 80 with the mode, and
  `AH=0Fh` answers from it.
- **Write character** (`AH=09h`, `0Ah`: `gt_write`, `gt_draw`). In the 320
  modes a font bit becomes a pixel of colour `BL` (0-3) through `exp_tab`,
  the table the text screen uses; in mode 6 the font byte is the pixels.
  Bit 7 of `BL` XORs the glyph into the screen. `CX` characters from the
  cursor, which stays; the run stops at the end of its row.
- **Teletype** (`AH=0Eh`, and DOS's console output: `gt_tty`). Colour `BL`
  from `INT 10h`, 3 from DOS. CR, LF, BS and BEL as in text; past the last
  column the cursor wraps, and past row 24 the screen moves up a row.
- **Scroll and clear** (`AH=06h`, `07h`: `gt_scroll`). The window is clamped
  to the screen, its rows are moved a field line at a time in both fields
  (`MVN`) and the freed lines are filled with the byte in `BH`, which in a
  graphics mode is pixels, not an attribute.
- **Read character** (`AH=08h`: `gt_read`). The cell's pixels, any colour but
  the background a set bit, are compared with the font from character 0 up;
  `AL` is the first match and 0 when there is none (a blank cell is
  character 0).
- **Pixels** (`AH=0Ch` write, bit 7 of `AL` XOR; `AH=0Dh` read).

Every byte these write sets its page's mark in `VID_DIRTY`, as a guest store
does, so `gfx_flush` draws them with the frame.

Before `gtext.s` the text services stored character cells whatever the mode.
In `SCREEN 1` that put a faint stipple on the top half of the screen (the
blank cells of a cleared 80x25 screen: `20h 00h` over the first 4,000
bytes) and, when the function-key line was on, a row of dashes across the
middle (text row 24 at offset `F00h`, which as pixels is scanlines 96 and
98), and `PRINT` showed nothing readable. GW-BASIC draws the key line when
it is started alone and a program is then loaded and run; `GWBASIC
PROG.BAS` from the DOS prompt runs the program with the key line off, which
is why the headless test never showed the dashes.

`tests/com/gtext.asm` (manifests `gtext` and `gtext6`) puts each service
through its cases in modes 4 and 6 by what is in B800 afterwards, and ends
on a picture that the judge compares with the SHR pixels (`tools/cgashr.py`,
`"video": "cga4"` or `"cga6"`: all 200 lines rebuilt from the two fields).
The same services draw in the EGA's mode 0Dh (docs/ega.md) and in a Tandy's
modes 08h, 09h and 0Ah (docs/tandy.md), where `gtext.s` hands the cell and
the glyph's bytes to those modes' routines.

Limits: there is no cursor in a graphics mode (a PC has none either; a
program draws its own). The font is the built-in one for all 256
characters: `INT 1Fh`'s table for characters 80h-FFh is not consulted, and
the font is not in the guest's ROM at `F000:FA6E`. Characters 01h-1Fh have
no glyphs in it (nor in text mode), so the arrows on GW-BASIC's key line
are blank. In mode 6 the colour in `BL` is ignored but for the XOR bit.

## 160x100, 16 colours

The CGA has no 16-colour graphics mode, but its 80-column text mode has 16
colours, and a program can shrink the character rows. With the 6845's maximum
scan line register (R9) at 1 a row is two scan lines high, so 100 rows fit on
the screen: 8,000 cells, 16,000 bytes at B800:0000. A cell then shows only the
top two rows of its glyph. With the half-block characters `DDh` and `DEh` a
cell is two pixels, one in the foreground colour and one in the background
colour, and with blink turned off (mode-control bit 5 clear) both can be any
of the 16 colours: 160x100 in 16 colours.

Tunneler sets it this way, after `INT 10h` mode 3: `3D8h` = 01h (video off),
6845 R4 = 7Fh, R6 = 64h, R7 = 70h, R9 = 01h, then `3D8h` = 09h (80-column
text, video on, blink off).

- **Detection** (`apply_cgamode` in `video.s`). `port_out` keeps the 6845's
  registers as the guest writes them (`3D4h` index, `3D5h` data, also as one
  word `OUT`; `CRTC_REG` in `pc.s`) and flags a write to R9 or to `3D8h`.
  Once a frame, and before a flush, `mode_poll` looks: mode control saying
  text with video enabled, and R9 = 1, enters the mode; text with video
  enabled and any other R9 leaves it for 80x25. Nothing happens while video
  is off, which is how a program brackets its register writes. `INT 10h
  AH=00` puts R9 back to 7, so any BIOS mode set leaves the mode too. B800 is
  not cleared either way.
- **Display** (`t160_enter`). SHR 320 mode, with the 16 CGA colours as palette
  0. Row r is SHR lines 2r and 2r+1, and a cell is four SHR pixels on each:
  half the CGA's horizontal resolution in this mode (640), which is exact for
  the half blocks, the full block and blanks - what such programs draw with.
  Any other character is shown as its top two glyph rows squeezed to half
  width, a pixel pair that is half set becoming a checkerboard of the two
  colours (`t160_masks` in `tools/gen_tables.py`, which writes
  `src/svc/gen/t160.s`).
- **Drawing** (`t160_flush`). The core's dirty marks are per 256-byte page of
  B800, 128 cells. For a dirty page each cell is compared with a shadow of
  what the screen shows (`T160_SHD`, 16,000 bytes in the results bank) and
  only the cells that differ are drawn, from three tables: the glyph's mask
  for its two rows and the attribute's foreground-xor-background and
  background as pixel words (pixels = mask AND d, XOR background). A game
  that rewrites its whole view every frame pays about 26 cycles for a cell
  that did not change and about 130 for one that did.
- **Limits.** Blink is ignored (the attribute's high bit is always background
  intensity). There is no cursor and no border colour in this mode. R9 is
  known only from what the guest wrote, and the 40-column variant is not
  distinguished. `INT 10h` text services still write cells, as on a CGA.

`tests/com/t160.asm` sets the mode through the ports, fills all 100 rows and
then changes single cells and a row; the judge (`tools/t160shr.py`) rebuilds
the expected SHR pixels from B800 and requires every cell to match.
`t160x` enters the mode and leaves it again for text.

## The colours' test

What a pixel is shown in cannot be read back by a program, so
`tests/com/cgapal.asm` checks what it can (the BIOS's copies of the two
registers at `40:65` and `40:66` after each call) and the judge does the
rest: for every `"video": "cga4"` or `"cga6"` test `tools/judge_com.py`
works the colours out from the registers as the core and SVC hold them
(`tools/cgashr.py`'s `colours`, written from the description of the
hardware and not from `fg_tab`), prints them, and compares the SHR's
palette with them; a manifest's `"cga_colours"` says what they must come
to. Each run draws a picture, lets it be shown, and ends on a write that
changes colours only.

| Manifest | Mode | Ends on | Colours |
| --- | --- | --- | --- |
| `cgapal4` | 4 | `AH=0Bh` six times: a blue background with the bright bit and without, each palette; last palette 0, bright | 1, 10, 12, 14 |
| `cgapal5` | 5 | `3D9h` = `06h`; `3D8h`'s bit 2 off (green, red, brown) and on again | 6, 3, 4, 7 |
| `cgapal6` | 6 | the foreground by `AH=0Bh` and then by `3D9h` | 0, 10 |

With mode 5's row of `fg_tab` made wrong, or a change of a Tandy's palette
register not noticed by `gfx_flush`, the tests concerned fail on the
palette.

## Status and limitations

- **Modes 4/5/6 and the 160x100 text-cell mode only** (the EGA's mode 0Dh
  is docs/ega.md's). A write to the mode-control port `3D8h` switches between modes
  4/5, 6 and (with R9) 160x100, without clearing B800; 1-2-3's graphics driver
  sets its mode that way. Other text settings written to `3D8h` (40 columns,
  blink) are not acted on: text modes come from `INT 10h AH=00`.
- **The border** (the overscan, which on a CGA is `3D9h`'s colour in text
  and in the 320 modes) is not drawn, so `3D9h` does nothing in 80x25 text.
- **No composite artifact colour** (the NTSC-bleed trick some CGA games use);
  RGB-style CGA output is what renders.

## Try it

`make run-dos`, then at `C:\>` run `GWBASIC CGADEMO.BAS` (in the folder) or
write your own `SCREEN 1` program. To load it from inside the interpreter,
quote the name: `LOAD "CGADEMO.BAS"` then `RUN` (the function-key line then
stays on the last row of the picture; `KEY OFF` removes it). GW-BASIC's `LOAD` takes a
string, so an unquoted `LOAD CGADEMO.BAS` is parsed as a numeric variable and
errors `Type mismatch` (standard GW-BASIC, not an XT/GS limitation). Headless
proof: `python3 -I tools/cga_test.py PROG.BAS 500` builds a floppy whose
AUTOEXEC runs GW-BASIC on the given program and renders the SHR screen to
`build/cgatest/PROG.png`; in a CGA graphics mode it also prints the two
registers and the colours they make, and judges B800 and the palette
against the SHR. `CGADEMO.BAS` ends with `3D9h` = `30h`, the BIOS's
(colours 0, 11, 13, 15: bright cyan, magenta and white on black); with a
`COLOR 1,0` after its `SCREEN 1` GW-BASIC leaves `01h` there (1, 2, 4, 6:
green, red and brown on blue).
