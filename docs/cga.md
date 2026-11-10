# CGA graphics

XT/GS renders CGA graphics on the IIGS Super Hi-Res screen:

- **Mode 4/5** (`SCREEN 1`): 320x200, 4 colours. The IIGS 320 mode is 320x200
  at 4 bits a pixel, a strict superset of CGA's 2 bits a pixel.
- **Mode 6** (`SCREEN 2`): 640x200, mono. Maps onto the IIGS 640 mode (the same
  mode the text screen uses).

- **160x100, 16 colours**: the "text-cell" mode some CGA games use (Tunneler,
  for one). It is 80-column text with the character rows cut to two scan
  lines; see [its own section](#160x100-16-colours) below.

The resolutions line up by design, not coincidence, so the work is repacking a
bitmap, not scaling it. The CGA palette and background colour (the `COLOR`
statement) are honoured in 320 mode.

## How it works (`src/svc/video.s`, `src/core/ops_misc.s`)

- **Mode set.** `INT 10h AH=00` (`v10_00` in `bios.s`) calls `vid_setmode`.
  Modes 4/5 and 6 go to `gfx_setup`, which configures the SHR and clears it and
  the 16 KB CGA framebuffer; any other mode restores 640-mode text (`init_shr`
  + `vid_clear`). For 320 (4/5) it sets every SCB to `$00` and the palette from
  the CGA colour state (below). For 640 (6) it sets every SCB to `$80` and a
  mono palette (`cga_setpal6`): `cga640_tab` emits pixel value 3 or 0, and in
  640 mode the four pixel positions read palette groups based at entries
  8/12/0/4, so entries 3/7/11/15 are white and the rest black. GW-BASIC's
  `SCREEN 1` sets mode **5** (the burst-off 4-colour variant); `SCREEN 2` sets
  mode 6.
- **The guest draws itself.** GW-BASIC (like most CGA software) bypasses
  `INT 10h` and writes pixels straight into the CGA framebuffer at B800:0000
  (host `$2B:8000`) - the same 16 KB aperture as text, but as a bitmap, 80
  bytes a scanline, with the **CGA interleave** (even scanlines at B800:0000,
  odd at B800:2000). Mode 4/5 is 2 bits a pixel (4 px/byte); mode 6 is 1 bit a
  pixel (8 px/byte).
- **Repack.** Each frame `gfx_flush` repacks only the scanlines that changed
  (see below); `gfx_blit_line` de-interleaves one screen line and expands each
  CGA byte into two SHR bytes - through `cga320_tab` in 320 mode or `cga640_tab`
  in 640 mode. Both modes are 80 CGA bytes -> 160 SHR bytes a line, so the blit
  structure is identical. `shr.py` understands both SHR modes, so the headless
  screenshot renders correctly.
- **Palette / `COLOR`.** The CGA colour-select state (`cga_bg`, `cga_pal`,
  `cga_int`) is fed by **both** `INT 10h AH=0Bh` (`v10_0B`: `BH=0` background,
  `BH=1` palette) and a write to port **`3D9h`** (`port_out`: bits 0-3
  background, bit 4 intensity, bit 5 palette), so GW-BASIC's `COLOR` statement
  works whichever path it uses. A change sets `cga_pd`, and `gfx_flush` applies
  it via `cga_setpal`, which writes SHR palette 0 entries 0-3: entry 0 =
  `cga_rgb[background]`, entries 1-3 = the selected palette's three colours
  (`fg_tab`: palette 0 = green/red/brown, palette 1 = cyan/magenta/white, dim
  or intensified). The palette lives separately from the pixels, so a `COLOR`
  change recolours the screen with no re-blit.
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

## Status and limitations

- **Modes 4/5/6 and the 160x100 text-cell mode only.** EGA/VGA modes are out
  of scope. A write to the mode-control port `3D8h` switches between modes
  4/5, 6 and (with R9) 160x100, without clearing B800; 1-2-3's graphics driver
  sets its mode that way. Other text settings written to `3D8h` (40 columns,
  blink) are not acted on: text modes come from `INT 10h AH=00`.
- **Mode 6 is white-on-black.** `SCREEN 2`'s `COLOR` foreground selection is
  ignored (the 320-mode `COLOR` path is fully honoured).
- **No composite artifact colour** (the NTSC-bleed trick some CGA games use);
  RGB-style CGA output is what renders.
- **A faint stipple on the top half** (dots every 8 px on alternate lines,
  down to y~=98) appears under GW-BASIC after `SCREEN 1` or `SCREEN 2`, with
  or without a `CLS`. The dots are in B800 itself, not made by the blit: one
  byte in two over the first 4,000, which is what blank text cells look like
  as pixels, so the likely source is the BIOS text services, which still
  write text cells in graphics modes (README, Known limits). A program that
  paints its own background (`LINE (0,0)-(319,199),0,BF`) covers it. The
  160x100 mode and held-key changes did not cause it: the build before them
  draws the same picture, pixel for pixel.

## Try it

`make run-dos`, then at `A:\>` run `GWBASIC CGADEMO.BAS` (on the floppy) or
write your own `SCREEN 1` program. To load it from inside the interpreter,
quote the name: `LOAD "CGADEMO.BAS"` then `RUN`. GW-BASIC's `LOAD` takes a
string, so an unquoted `LOAD CGADEMO.BAS` is parsed as a numeric variable and
errors `Type mismatch` (standard GW-BASIC, not an XT/GS limitation). Headless
proof: `python3 -I tools/cga_test.py PROG.BAS 500` builds a floppy whose
AUTOEXEC runs GW-BASIC on the given program and renders the SHR screen to
`build/cgatest/PROG.png`.
