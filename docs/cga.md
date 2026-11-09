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
- **Repack.** `gfx_blit` de-interleaves the two fields and expands each CGA
  byte into two SHR bytes through `cga320_tab` (a 256-entry 2bpp->4bpp table;
  CGA pixel value n maps to SHR palette index n). `shr.py` already understands
  320 mode, so the headless screenshot renders correctly.
- **`3DAh` status register** (`port_in8`): returns a free-running value so the
  guest's retrace/display-enable poll loops terminate instead of spinning on a
  constant open-bus read.

## Throttling (important)

A full-screen repack is ~880 K 65816 cycles. Run every VBL it would saturate
the IIGS CPU and starve the 8086 interpreter (measured: the guest crawled at
~1 pixel/second). `gfx_blit` is therefore **throttled to ~1 Hz**
(`GFX_THROTTLE` in `video.s`), which keeps the interpreter near full speed for
a static graphics screen. This is the spike's deliberate shortcut: smooth
animation at full guest speed needs **dirty-region (per-scanline) blitting**
instead - extend the core's `VID_DIRTY` page marks (today 16 pages over the
4 KB text aperture, `cpu.s` `vid_mark`) to the 16 KB graphics aperture and
repack only changed scanlines.

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
