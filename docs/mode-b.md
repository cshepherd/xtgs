# Mode B: booting a real DOS from a disk image

Mode B is the PC/XT boot environment (the plan's M5). Instead of the
Mode A shim handling INT 21h, a real DOS kernel boots from a disk image
and installs its own INT 21h; XT/GS supplies only the BIOS and hardware:
INT 13h disk, the IRQ0 timer, keyboard, and the INT 10h/16h/1Ah services
Mode A already had.

Target: **FreeDOS** with the 8086 kernel (KERNL86.SYS), which has no 286/386
instructions and suits the XT guest.

## How to run

```
make boot-dos        # builds the FreeDOS floppy and boots it headless
```

`tools/build_freedos.py` fetches the FreeDOS kernel and shell (GPL/MIT,
git-ignored under `third_party/`), assembles the real FreeDOS FAT12 boot
sector, and builds a 1.44 MB floppy with `tools/make_fat12.py`:
KERNEL.SYS (KERNL86), COMMAND.COM (FreeCOM), FDCONFIG.SYS, AUTOEXEC.BAT.
`tools/boot_dos.py` stages it as the `DISK` file, boots with command `D`,
and reports the guest state, INT 13h count and screen.

## What works

- The loader claims 23 host banks ($50-$66) at startup and loads the disk
  image there; `svc_bootinit` builds the IVT (BIOS vectors to the hypercall
  stubs), the BIOS data area, and copies the image's sector 0 to 0000:7C00.
- The core enters the boot sector at 0000:7C00 with DL=0 (floppy A), and
  delivers the IRQ0 timer (INT 08h) to the guest ~18.2 times a second from
  the slot check when interrupts are enabled.
- **INT 13h** (`src/svc/disk.s`): reset, read (AH=02, CHS), write, get
  params (AH=08, 1.44 MB geometry), type (AH=15). Reads and writes convert
  CHS to LBA and serve sectors from the image banks. LBA extensions (41h/42h)
  report absent, as a real floppy does.
- The real FreeDOS boot sector runs: it relocates itself to 1FE0:7C00,
  reads the whole root directory (LBA 19-32) through INT 13h, and the
  directory lands in the search buffer correctly (verified: the first entry
  reads "KERNEL  SYS").

- The boot sector finds KERNEL.SYS, loads it, and chains in. The FreeDOS
  kernel initialises, processes FDCONFIG.SYS, loads COMMAND.COM (FreeCOM
  0.85a), runs AUTOEXEC.BAT, and reaches the `A:\>` prompt. A full boot to
  the prompt takes roughly 240 s of emulated time at the stock ~15 K guest
  IPS (kernel init plus the COMMAND.COM load is a lot of guest work); it is
  not a hang.

- **Real DOS applications run.** GW-BASIC 3.23 (`GWBASIC.EXE`, 80 KB; in
  `third_party/gwbasic/`, added to the floppy by `tools/build_freedos.py` when
  present) launches under FreeDOS and works: FreeDOS loads and relocates the
  `.EXE`, and XT/GS supplies only the CPU, INT 10h/16h and the direct video
  path. GW-BASIC bypasses INT 10h and writes straight to the B800 text buffer;
  those stores are caught by the core's `VID_DIRTY` page marks (`cpu.s`) and
  rendered by `svc_flush`, so its output appears on the SHR screen. The default
  `AUTOEXEC.BAT` runs `GWBASIC HELLO.BAS`, which prints and computes, then
  `SYSTEM` returns to `A:\>`; a headless `make boot-dos` captures the result.
  At the `A:\>` prompt (`make run-dos`) typing `GWBASIC` gives the live `Ok`
  interpreter with real keyboard input.

- **CGA graphics (`SCREEN 1`, 320x200x4) render** (`docs/cga.md`). GW-BASIC's
  `LINE`/`CIRCLE`/etc. draw straight into the B800 bitmap and XT/GS repacks it
  onto the SHR screen in 320 mode. `AUTOEXEC` runs `CGADEMO.BAS` (an X, a box,
  a circle) as the headless proof. Modes 4/5 (`SCREEN 1`, 320x200x4) and 6
  (`SCREEN 2`, 640x200 mono); the `COLOR` palette/background is honoured. The
  repack is per-scanline dirty-region (only changed lines each frame), ~26x the
  guest throughput of blitting the whole screen every frame.

## The find-file bug (fixed)

For a long time the boot sector's `repe cmpsb` in the find-file loop returned
ZF=0 on a byte-for-byte match ("KERNEL  SYS" vs the directory entry), so the
kernel was never found. The operands, segment bases and CX were all correct,
and the compare passed in the vector suite and in isolation. The trigger was
the IRQ0 timer: with it disabled the boot worked, with it enabled find-file
failed, and the outcome depended on exactly which instruction the first tick
landed on.

Root cause: `svc_tickdue` (`src/svc/disk.s`) saved the tick flag with a 16-bit
`pha` and then restored the data bank with a 1-byte `plb`, a width mismatch.
The `plb` pulled the high byte of the pushed tick value (0x00) into DBR
instead of the saved core bank ($03). Every timer tick therefore returned
with DBR=0x00, and because the dispatcher jumps through `optab` with PBR (not
DBR) the core kept running, but `flg_sub8_r`'s `lda p2f_sub,x` then read the
flag table from bank $00 (zeros). Result: ZF (and every arithmetic flag)
came out wrong after the first tick, so the comparison that follows a tick
mis-set ZF. The fix is to drop the `pha`/`pla`; a single `plb` restores DBR
and the tick flag already lives in A, which `plb` does not touch.

## Not yet implemented (needed for a full boot)

- The 8259 PIC and 8253 PIT ports are open-bus; a kernel that programs them
  for exact timing may need real behaviour.
- A20, the keyboard controller (port 0x60/0x64) beyond INT 16h, and INT 15h
  services.
- Writes persist only to the in-memory image (no write-back to the volume).
