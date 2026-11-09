# CGA graphics

XT/GS renders CGA graphics on the IIGS Super Hi-Res screen:

- **Mode 4/5** (`SCREEN 1`): 320x200, 4 colours. The IIGS 320 mode is 320x200
  at 4 bits a pixel, a strict superset of CGA's 2 bits a pixel.
- **Mode 6** (`SCREEN 2`): 640x200, mono. Maps onto the IIGS 640 mode (the same
  mode the text screen uses).

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

## Status and limitations

- **Modes 4/5/6 only.** EGA/VGA modes are out of scope. The mode-control port
  `3D8h` is still open-bus - the mode comes from `INT 10h AH=00`, which
  GW-BASIC uses; a program that sets the mode by banging `3D8h` directly would
  not switch.
- **Mode 6 is white-on-black.** `SCREEN 2`'s `COLOR` foreground selection is
  ignored (the 320-mode `COLOR` path is fully honoured).
- **No composite artifact colour** (the NTSC-bleed trick some CGA games use);
  RGB-style CGA output is what renders.
- **One stray dotted row** at screen y~=96 (magenta dots every 8 px) appears
  under GW-BASIC. It is present before the program's own drawing, so it is a
  GW-BASIC graphics-init quirk, not the blit; cosmetic and uninvestigated.

## Try it

`make run-dos`, then at `A:\>` run `GWBASIC CGADEMO.BAS` (on the floppy) or
write your own `SCREEN 1` program. Headless proof: the FreeDOS floppy's
`AUTOEXEC` runs `CGADEMO.BAS`, and a boot renders `build/boot/boot.png`.
