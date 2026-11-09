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
KERNEL.SYS (KERNL86), COMMAND.COM (FreeCOM), FDCONFIG.SYS, and (no AUTOEXEC)
GWBASIC.EXE + HELLO.BAS + CGADEMO.BAS.
`tools/boot_dos.py` stages it as the `DISK` file, boots with command `D`,
and reports the guest state, INT 13h count and screen.

## What works

- The loader claims 23 host banks ($50-$66) at startup and loads the disk
  image there; `svc_bootinit` builds the IVT (BIOS vectors to the hypercall
  stubs), the BIOS data area, and copies the image's sector 0 to 0000:7C00.
- The core enters the boot sector at 0000:7C00 with DL=0 (floppy A), and
  delivers the IRQ0 timer (INT 08h) to the guest from the slot check when
  interrupts are enabled: 18.2 times a second, or at the rate the guest
  programs into the 8253. The tick is the Ensoniq DOC's timer oscillator, and
  the PC speaker is two more of its oscillators (`docs/sound.md`).
- **INT 13h** (`src/svc/disk.s`): reset, read (AH=02, CHS), write, get
  params (AH=08), type (AH=15). The geometry (sectors/track) is read from the
  booted disk's BPB at `svc_bootinit`, so Mode B serves 320K/720K/1.2M/1.44M
  images alike (all PC floppies are 2-head); `chs_to_lba` and AH=08 use it.
  Reads and writes convert CHS to LBA and serve sectors from the image banks.
  LBA extensions (41h/42h) report absent, as a real floppy does.
- The real FreeDOS boot sector runs: it relocates itself to 1FE0:7C00,
  reads the whole root directory (LBA 19-32) through INT 13h, and the
  directory lands in the search buffer correctly (verified: the first entry
  reads "KERNEL  SYS").

- The boot sector finds KERNEL.SYS, loads it, and chains in. The FreeDOS
  kernel initialises, processes FDCONFIG.SYS, loads COMMAND.COM (FreeCOM
  0.85a), and reaches the `A:\>` prompt. There is no AUTOEXEC.BAT, so FreeCOM
  first shows its date/time prompt (press Enter twice). A full boot to the
  prompt takes roughly 240 s of emulated time at the stock ~15 K guest IPS
  (kernel init plus the COMMAND.COM load is a lot of guest work); it is not a
  hang.

- **Real DOS applications run.** GW-BASIC (`GWBASIC.EXE`, in
  `third_party/gwbasic/`, added to the floppy by `tools/build_freedos.py` when
  present) launches under FreeDOS and works: FreeDOS loads and relocates the
  `.EXE`, and XT/GS supplies only the CPU, INT 10h/16h and the direct video
  path. GW-BASIC bypasses INT 10h and writes straight to the B800 text buffer;
  those stores are caught by the core's `VID_DIRTY` page marks (`cpu.s`) and
  rendered by `svc_flush` (only the cells that changed: `render_row` keeps a
  shadow of what is on screen), so its output appears on the SHR screen. The binary
  is **tkchia's MIT-licensed rebuild** (gitlab.com/tkchia/GW-BASIC) of
  Microsoft's open-sourced source; it is FreeDOS-compatible, unlike the
  Microsoft 3.23 binary which errors "You can not SHELL to BASIC" when run
  interactively on FreeDOS (its SHELL recursion guard). The volume carries
  `GWBASIC.EXE`, `HELLO.BAS` and `CGADEMO.BAS`; at the `A:\>` prompt
  (`make run-dos`) run `GWBASIC` for the live `Ok` interpreter, or
  `GWBASIC HELLO.BAS`. FreeDOS **SETVER** (`SETVER.SYS`) is on the floppy and
  loaded via `DEVICE=A:\SETVER.SYS` in FDCONFIG.SYS, for faking the DOS version
  to older programs. (The CGA headless tests build their own floppy with a
  program-specific AUTOEXEC; see `tools/*` harnesses.)

- **CGA graphics (`SCREEN 1`, 320x200x4) render** (`docs/cga.md`). GW-BASIC's
  `LINE`/`CIRCLE`/etc. draw straight into the B800 bitmap and XT/GS repacks it
  onto the SHR screen in 320 mode. `GWBASIC CGADEMO.BAS` draws an X, a box and
  a circle. Modes 4/5 (`SCREEN 1`, 320x200x4) and 6
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

Root cause: `svc_tickdue` (then in `src/svc/disk.s`) saved the tick flag with a 16-bit
`pha` and then restored the data bank with a 1-byte `plb`, a width mismatch.
The `plb` pulled the high byte of the pushed tick value (0x00) into DBR
instead of the saved core bank ($03). Every timer tick therefore returned
with DBR=0x00, and because the dispatcher jumps through `optab` with PBR (not
DBR) the core kept running, but `flg_sub8_r`'s `lda p2f_sub,x` then read the
flag table from bank $00 (zeros). Result: ZF (and every arithmetic flag)
came out wrong after the first tick, so the comparison that follows a tick
mis-set ZF. The fix is to drop the `pha`/`pla`; a single `plb` restores DBR
and the tick flag already lives in A, which `plb` does not touch.

Two follow-up errors in the same VBL-polled timer then made the guest clock
run fast: `plb` set Z from the restored bank rather than from the tick flag
the core tested, so INT 08h fired on every VBL edge; and the "VBL edge" was
detected on both transitions of the VBL bit (entering and leaving the blank),
which was papered over for a while with a recalibrated accumulator. All of
that code is gone. **IRQ0 is now the Ensoniq DOC's timer oscillator**
(`docs/sound.md`): its interrupt counts ticks owed in `vTICK`, the slot check
delivers one INT 08h for each while IF is set, and the rate is whatever the
guest programs into 8253 channel 0 (18.2 Hz by default). The once-a-frame work
(keyboard poll, screen flush) runs on one VBL edge a frame.

## Real applications

- **Lotus 1-2-3 Release 1A (1983)** boots from its original self-booting
  System disk image (a 320 KB PC-DOS 1.x floppy): PC-DOS 1.x loads and the
  **Lotus Access System** menu displays and is driven from the keyboard (zero
  unimplemented opcodes). The protected `123.EXE` then exits on its
  copy-protection check, which a sector image cannot satisfy; with that one
  `INT 13h` patched out of a copy of the image, 1-2-3 runs: the worksheet
  takes entries and recalculates, and `/Graph View` draws in CGA graphics
  (the driver sets the mode through port 3D8h; `docs/cga.md`). Details in the
  next section. (`XTIME` in the stock AUTOEXEC spins forever probing a
  clock/calendar card at I/O ports we don't emulate; booting past it needs an
  edited AUTOEXEC.)

## The hardware keyboard (IRQ1/INT 09h + ports 0x60/0x64)

Besides the BDA buffer / INT 16h path, XT/GS now presents a hardware keyboard,
for programs that install their own INT 09h handler and read scancodes from the
8042 data port (many DOS games). `kb_poll` (`keyboard.s`) enqueues each key's
make and break codes into a scancode ring (`KBD_Q*` in `pc.s`); the slot check
(`cpu.s`) delivers one as IRQ1/INT 09h (after any IRQ0 owed, so the timer
keeps priority), and the core serves port 0x60 (pop a scancode)
and 0x64 (status) in `port_in8`. The default INT 09h handler is `PUSH AX; IN
AL,60h; POP AX; IRET`, so the ring still drains when nothing hooks the vector.
`kb_poll` keeps filling the INT 16h ring too, so INT 16h programs are
unaffected (verified: GW-BASIC and FreeDOS still take input). Note this is a
make/break stream for the translated key; it does not yet inject separate
Shift/Ctrl make/break for shifted characters.

**Lotus 1-2-3 1A, as it happens, reads the keyboard through INT 16h** (its
`KB.DRV` calls INT 16h, not port 0x60), and our INT 16h is byte-exact (Enter
returns AX=1C0D as on a real PC). The Access System menu is **fully driven**
under XT/GS: the arrow keys move the highlight and Enter selects (verified by
reaching the Disk-Manager submenu, and confirmed by logging that the menu reads
the keys 4D00 4D00 1C0D). Selecting **1-2-3** launches `123.EXE`, which then
**self-terminates on its copy protection**: 123.EXE's entry does a single raw
`INT 13h` read of the original System disk's physically-formatted fingerprint
track (it is the only `INT 13h` in the 90 KB binary, and the program has no
standard `AH=4C`/`INT 20h` exit). A `.img` file stores only normal sector data
and cannot reproduce that non-standard formatting, so the check fails and
1-2-3 exits silently back to the menu. This is inherent to the protected 1A
binary on a sector image, not an XT/GS limitation. With the check removed
(the two bytes of that `INT 13h` replaced by NOPs in a copy of the image),
1-2-3 runs to the worksheet: `@SUM` over typed cells evaluates, and a bar
graph of a range renders through `/Graph View`. The first keystroke a fresh
worksheet receives is dropped.

## Not yet implemented (needed for a full boot)

- The 8259 PIC: no mask register and no EOI; IRQ0 and IRQ1 are delivered
  whenever IF is set. The 8253 PIT's channels 0 and 2 and port 61h are served
  by the DOC (`docs/sound.md`: the tick and the speaker), square-wave mode
  only, with synthetic counter reads.
- A20, and INT 15h beyond AH=84h (the joystick, answered "none"); the rest
  return CF set, AH=86h.
- Writes persist only to the in-memory image (no write-back to the volume).
