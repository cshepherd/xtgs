# CGA graphics (SCREEN 1)

XT/GS renders **CGA 320x200x4** graphics (BIOS video modes 4 and 5, GW-BASIC
`SCREEN 1`) on the IIGS Super Hi-Res screen. The resolutions line up by design,
not coincidence: the IIGS 320 mode is 320x200 at 4 bits a pixel, a strict
superset of CGA's 320x200 at 2 bits a pixel, so the work is repacking a bitmap,
not scaling it.

## How it works (`src/svc/video.s`, `src/core/ops_misc.s`)

- **Mode set.** `INT 10h AH=00` (`v10_00` in `bios.s`) calls `vid_setmode`.
  Modes 4/5 go to `gfx_setup`: it puts the SHR in 320 mode (all 200 SCBs
  `$00`), loads palette 0 with the CGA colours (0 black, 1 cyan, 2 magenta, 3
  white), and clears both the SHR and the 16 KB CGA framebuffer. Any other mode
  restores 640-mode text (`init_shr` + `vid_clear`). GW-BASIC's `SCREEN 1` does
  reach this path (it sets mode **5**, the burst-off 4-colour variant).
- **The guest draws itself.** GW-BASIC (like most CGA software) bypasses
  `INT 10h` and writes pixels straight into the CGA framebuffer at B800:0000
  (host `$2B:8000`) - the same 16 KB aperture as text, but as a bitmap: 2 bits
  a pixel, 4 pixels a byte, 80 bytes a scanline, with the **CGA interleave**
  (even scanlines at B800:0000, odd at B800:2000).
- **Repack.** Each frame `gfx_flush` repacks only the scanlines that changed
  (see below); `gfx_blit_line` de-interleaves one screen line and expands each
  CGA byte into two SHR bytes through `cga320_tab` (a 256-entry 2bpp->4bpp
  table; CGA pixel value n maps to SHR palette index n). `shr.py` already
  understands 320 mode, so the headless screenshot renders correctly.
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

- **Modes 4/5 only** (`SCREEN 1`, 320x200x4). Mode 6 (`SCREEN 2`, 640x200
  mono) maps cleanly onto the IIGS 640 mode we already use for text but is not
  wired yet; EGA/VGA modes are out of scope.
- **Fixed palette** (black / cyan / magenta / white). The `COLOR` statement's
  palette and background selection (`INT 10h AH=0Bh`, port `3D9h`) is not
  honoured, so palette 0 (green/red/brown) and a non-black background don't
  show. The mode-control/colour ports (`3D8h`/`3D9h`) are still open-bus.
- **No composite artifact colour** (the NTSC-bleed trick some CGA games use);
  RGB-style CGA output is what renders.
- **One stray dotted row** at screen y~=96 (magenta dots every 8 px) appears
  under GW-BASIC. It is present before the program's own drawing, so it is a
  GW-BASIC graphics-init quirk, not the blit; cosmetic and uninvestigated.

## Try it

`make run-dos`, then at `A:\>` run `GWBASIC CGADEMO.BAS` (on the floppy) or
write your own `SCREEN 1` program. Headless proof: the FreeDOS floppy's
`AUTOEXEC` runs `CGADEMO.BAS`, and a boot renders `build/boot/boot.png`.
