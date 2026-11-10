# XT/GS

An 8086/8088 real-mode interpreter and PC-compatible runtime for an 8 MB
Apple IIGS, in 65816 assembly (Merlin32), booted directly from ProDOS 8.
`apple_iigs_xt_emulator_project_plan.md` is the project plan;
`BOOTSTRAP.md` is the toolchain and M0/M1 design that this tree follows.

## Build and test

```
make              build/xtgs.po (XTGS.SYSTEM + CORE + SVC, command P)
make test-m0      headless MAME: memory probe + 80x25 test frame -> build/m0.png
make test-com [COM=hello]
                  the .COM programs in tests/com (nasm) against tests/expected;
                  in text mode the SHR pixels must also show the text buffer
                  (tools/textshr.py), and under a manifest's "video": "t160"
                  the 160x100 cells (tools/t160shr.py)
make test-cpu OP="00 01" [COUNT=300]
                  SingleStepTests vectors for those opcodes (a group sub-opcode
                  is OP=80.3); the judge explains the first failure
python3 -I tools/sweep_cpu.py --ops 00-3F --tag A
                  every file in a range, four a boot; build/vec/sweep_A.json
make bench        guest instructions/second, stock and 16 MHz Zip (tools/bench.py;
                  tests/bench: reg, mem, jmp, str one long REP MOVSW, strs short
                  string instructions)
python3 -I tools/profile.py reg|mem|jmp|str
                  attribute MAME PC samples to core routines (tools/profile.py)
make lint         assemble every bank and run tools/check_mx.py on the listings
make test-layout  probe, .COM programs and sampled CPU vectors with every region
                  away from its assembled bank and every bank-$00 area away
                  from its assembled page; XTGS_LAYOUT=alt does the same for
                  any other target or tool (docs/relocation.md)
make test-share [LETTER=E] [FULL=1] [BOOT=1]
                  the shared drive (docs/share.md): FreeDOS booted with a
                  ProDOS folder as C:, an AUTOEXEC.BAT that works on it, the
                  console and the volume judged (tools/share_test.py; work
                  files in build/share/). BOOT=1 boots FreeDOS from that
                  folder instead (command S, no floppy). Not part of
                  test-layout or test-s16: run it under XTGS_LAYOUT=alt and
                  XTGS_FRONT=s16 by hand
make test-clock [DOS=1]
                  the IIGS clock as the guest's (docs/clock.md):
                  tests/com/clock.asm under the stub DOS, or under FreeDOS
                  booted from a folder, judged against this machine's clock
                  (tools/clock_test.py; work files in build/clock/). Like
                  test-share, run it under XTGS_LAYOUT=alt and XTGS_FRONT=s16
                  by hand
make test-minix [ZIP=1] [MINIX=path]
                  Minix 1.5's demonstration diskette (in the tree,
                  third_party/minix/demo_dsk.ibm) booted under D to its
                  shell, a command line typed, the scrolled screen judged
                  (docs/minix.md; tools/minix_test.py; work files in
                  build/minix/; 378 emulated seconds at stock speed, 53 with
                  ZIP=1). Like test-share, run it under XTGS_LAYOUT=alt and
                  XTGS_FRONT=s16 by hand
make disk-image IMG=path
                  build/disk/disk.po: XT/GS and any PC diskette image as
                  DISK, command D (make run-disk boots it in Ample's MAME);
                  make minix-image / run-minix: the same with Minix's
make boot-shared  FreeDOS booted from the folder third_party/freedos/fd/SHARED
                  (tools/boot_dos.py with a folder; work files in
                  build/bootdos/); make boot-dos is the floppy image
make dos-image    build/boot/boot.po: XT/GS and that folder as SHARED,
                  command S (make run-dos boots it in Ample's MAME)
make test-gsos    launch XTGS.SYSTEM from GS/OS (a System 6 volume, SYSTEM6=,
                  default ../ddiigs/assets/system6.hdv; tools/check_gsos.py)
make test-s16     the GS/OS application (src/gs/xtgs16.s) on the same volume:
                  probe, .COM programs, sampled vectors, both layouts, then
                  three launches in one boot (tools/check_s16.py);
                  XTGS_FRONT=s16 does the same for any other target or tool
                  (image build/xtgs-s16.po, a GS/OS volume)
make finder       build/xtgs-finder.po: a System 6 volume (named XTGS) that
                  boots to the Finder, the application and its icon in the
                  folder XTGS with FreeDOS in the folder SHARED below it
                  (GW-BASIC in it, required) and command S: opening XTGS
                  boots FreeDOS from that folder as C:
make run          Ample's MAME with the claudebridge Lua bridge
```

The core's command comes from `XTGS.CMD` on the volume: `P` probe, `V` run
the vectors in `VEC`, `B` run `BENCH` at 0000:0100 until HLT, `C NAME args`
run the .COM file NAME under the stub BIOS/DOS (docs/dos-api.md), `D` boot the
`DISK` image (Mode B, `make boot-dos` / `tools/boot_dos.py`; docs/mode-b.md),
`S` boot FreeDOS from the shared folder with no image (`KERNEL.SYS` read
from it by `svc_bootinit`; docs/share.md),
`J` the M6 JIT spike (hand-translated `BENCH` loop; `tools/jit_spike.py`), `K`
the M6 runtime block translator on `BENCH` (`src/core/jit2.s`; docs/jit.md).
The loaders read the first line only. A later line `X=path` (`C=/VOL/DIR`,
or `C=DIR` below the launch folder) is the shared drive, which SVC reads
for itself under `D` and `S` (`rd_readcfg`; under `S` the drive is always
`C:` and the folder `SHARED` when no line names one).
A `+` before the command (`+P`) is the layout test: no region may have its
assembled bank, and the bank-`$00` areas go to their `NAME_ALTPG` pages.
Never rebuild while a sweep is running: it reads `build/stage/` and
`build/xtgs.lst`.

Toolchain: `merlin32` 1.1.10, `cadius`, Homebrew `mame` (headless runs) and
Ample's `mame64` with its ROM set in `~/Library/Application Support/Ample`,
`python3`, `nasm` (the `.COM` test programs). `tools/mame/mamerun.py`,
`shr.py`, `claudebridge/`, `tools/cadius_strict.sh` and `tools/gsos_rfork.py`
come from `../somi-iigs-port/iigs`; `tools/check_mx.py` from `../fgx`.

## Layout

| Path | What |
| --- | --- |
| `src/sys/xtgs.s` | `XTGS.SYSTEM`: ProDOS 8 loader. Owns memory (TN #27 + fixed Memory Manager blocks), reads `XTGS.CMD`, places the regions and pages, loads and relocates `CORE`/`SVC`/`VEC`, runs the core. Its first page is the front page: the file-call entry (`MB_FILECALL`, the MLI glue) and the mailbox |
| `src/gs/xtgs16.s` | `XTGS` (S16, `build/xtgs16`): the GS/OS front end, the same job as `XTGS.SYSTEM` from GS/OS. Relocatable OMF (`rel`); one Memory Manager block in bank `$00` for `ZP`/`MBX`/`PATH`/`XFER`, its front page marked `"XTGS"` at `+0` (the harness finds it by that); `filecall` answers the MLI lists with GS/OS calls |
| `src/core/` | `CORE` at `$03:0000`: the CPU (dispatch, handlers, lazy flags in `flags.s`) and the M0 probe; 49 KB of the bank's 64 used |
| `src/core/gen/` | generated by `tools/gen_cpu.py`: the opcode table, the ModR/M routines (the general set `eab_`/`eaw_` and the fast set `emb_`/`emw_`), the ALU, `TEST`, `MOV r/m`, `PUSH`/`POP r16` and `Jcc` handlers. Never edit; change the generator |
| `src/svc/` | `SVC` at `$04:0000`: text screen, CGA graphics and the 160x100 text-cell mode (`video.s`, docs/cga.md; `gen/t160.s` from `tools/gen_tables.py`), the PC's structures (`pcinit.s`), BIOS (`bios.s`) and DOS (`dos.s`) hypercall handlers, keyboard and frame work (`keyboard.s`), the shared drive (`redir.s`, docs/share.md: a ProDOS folder as a DOS network drive in Mode B, `INT 2Fh AH=11h` answered through `files.s`; guest stubs at `F000:RD_OFF`, hypercalls 256-258 from `svc_hypercall`, `rd_poll` each frame, and under `S` before every hypercall while `rd_early` is set, which is how the redirector gets in before FreeDOS's kernel reads `FDCONFIG.SYS`), the DOC as PC speaker and IRQ0 timer (`sound.s`, docs/sound.md), the 8259, the 8237's channel 2 and the 765 diskette controller for a guest that drives them itself (`ports.s`, docs/minix.md: `svc_portout`/`svc_portin`, entries 36 and 39, where the core sends a port it does not serve in Mode B), the IIGS clock as the PC's date, time and tick count (`clock.s`, docs/clock.md: ReadTimeHex, read-only to the guest; `clk_sync` every 128 frames adds the IRQ0s the guest lost to `0040:006C`), host capture (`capture.s`). Entry table at `$04:0000`, 3 bytes an entry |
| `tests/com/` | nasm `.COM` programs with `NAME.json` manifests (keys in `tools/judge_com.py`); `tests/expected/NAME.out` is the exact console output. `fileops` is the handle file functions end to end; `strrep` is the string instructions (219 cases against the same work done by ordinary instructions: block ends, segment wraps, overlaps, the text buffer; it takes 75 emulated seconds of the judge's 120); `clock` prints the date and time every way a PC can ask (only its shape is judged there: `make test-clock` judges the values); `t160` and `t160x` enter and leave the 160x100 mode through the 6845 |
| `src/include/` | `layout.s` (the bank of each region and the page of each bank-`$00` area: the only place either is written), `hw.s` (soft switches, ROM, Toolbox), `mailbox.s` (the front page: file-call entry and loader mailbox), `guest.s` (guest CPU state in the direct page, `GUEST_DP`) |
| `tools/` | `gen_reloc.py` (appends each image's list of bank bytes and page bytes), `layout.py` (the layout for the host tools, `XTGS_LAYOUT`), `make_image.sh` (the ProDOS volume, named `XTGS`; a directory argument becomes a folder on it), `gsos_image.sh` (a GS/OS boot volume from a System 6 one, named `XTGS` or `GSOS_VOL`, cached in `build/gsos/`; `gsos_volname.py` renames the old volume in the pathnames the copied System folder holds, without which GS/OS waits at startup for the disk of the old name) + `check_gsos.py` (GS/OS launch test; `tests/gsos/start.s` is its launcher, `start16.s` the S16's) + `check_s16.py` (relaunch test), `build_freedos.py` (the FreeDOS floppy image and the same files as the folder `third_party/freedos/fd/SHARED`), `symbols.py` (listing -> addresses), `gen_tables.py` (font, pixel table), `judge_m0.py`, `textshr.py` (text buffer vs SHR pixels), `t160shr.py` (the same for the 160x100 mode), `share_test.py` (the shared drive's test: builds its own FreeDOS floppy and volume), `clock_test.py` (the clock's test: MAME's IIGS clock is the host's at the start of a run), `minix_test.py` (Minix's boot, by the cursor at each prompt), `cga_test.py` (a GW-BASIC program under FreeDOS, SHR to `build/cgatest/NAME.png`; one run at a time), `check_mx.py`, `mame/` |
| `icon/` | the Finder icon of the GS/OS application: QuickDraw II icon records (`dos_32x32.qdicon.bin`, `dos_16x16.qdicon.bin`) and their generator. `tools/gsos_rfork.py` wraps them in `XTGS`'s resource fork (`build/xtgs16.rfork`: `rBundle`, `rIcon`s, `rVersion`; empty rows trimmed, `ICON_REMAP` in the Makefile) and builds the volume's `Icons/Desktop`; docs/relocation.md |
| `tests/cpu/EXCLUDE.md` | which vectors the packer drops and why; known deviations |
| `tests/bench/*.asm` | nasm benchmark programs (`-DOUTER=n`) |
| `third_party/` | `8088/` SingleStepTests vectors (fetched, git-ignored), `font8x8/` public-domain font, `minix/` the Minix 1.5 demonstration diskette and its licence (distributed with the tree; keep the image unmodified, its sha256 is in the README there) |

## Memory

Everything CORE and SVC touch is a first choice (docs/relocation.md), set in
`src/include/layout.s` and nowhere else.

Bank `$00` areas, by page: `ZP` `$1000-$10FF` guest CPU state (the direct
page, `GUEST_DP`; `$00-$7F` core, `$80-$FF` services), `MBX` `$2000` the
front page (`MB_FILECALL` at `+$04`, the mailbox from `+$10`: `MB_STAGE`
`$2010`, `MB_MAGIC` `$2012`, `MB_LAYOUT` `$2082`), `PATH` `$0C00` pathnames,
`XFER` `$4000-$5FFF` file transfer buffer, `IOB` `$6000-$7FFF` the MLI's I/O
buffers. The loader's own, not layout: `$0800-$0BFF` core native stack
(`S=$0BFF`), `$2000-$3FFF` the loader, its load-time `IOBUF` `$0C00` and
`BOUNCE` `$4000`. `$E1:2000` SHR, written directly.

Banks: `$03` CORE, `$04` SVC, `$05` results/trace (and the PC's device
state from `src/include/pc.s`: the 6845 registers `CRTC_REG` and `CRTC_CUR`,
the 8259's `PIC_BASE`/`PIC_MASK` and the diskette's `PIC_IRQ6`, the shared
drive's `RD_STATE`/`RD_DIAG`/`RD_CALLS`/`RD_LAST`/`RD_LOG`, the 160x100
mode's shadow `T160_SHD` in its upper half), `$06` the JIT (K),
`$20-$2F` the guest's 1 MiB (`B800:0000` is `$2B:8000`), `$30+` the vector
file, `$50+` the disk image (D only; S claims none). The loader claims each region where the
Memory Manager has room (under GS/OS: CORE/SVC/results at `$07-$09`), hands
out the pages (`set_pages`: the assembled ones, which a ProDOS 8 program
owns), records both in `MB_LAYOUT` and fixes the bank bytes and page bytes of
CORE and SVC from the list `tools/gen_reloc.py` appended to them
(`build/core.bin` is the plain assembly, `build/core` the relocatable image;
likewise `build/xtgs.bin` and `build/xtgs`, whose list moves the loader's own
front page for `+`).

- Never write a bank number, a `$xx0000` literal or a bank-`$00` address
  outside `src/include/layout.s`; derive from `CORE_BASE`, `GUEST_BASE`,
  `RES_BASE`, `GUEST_DP`, `MB_BASE`... `gen_reloc.py` finds bank and page
  bytes by reassembling with the layout moved, so a literal it cannot move
  is a bug only a relocated run shows. (Machine addresses are not layout:
  soft switches, `$E1:xxxx`, page 1.)
- A bank may be used only as a whole byte that follows one region (a long
  operand, `#^label`, `ora #GUEST_BANK`, `MVN`); a page only as the high
  byte of an address in one area. Arithmetic on them (a difference of two
  banks, a shifted bank, a byte that follows both a bank and a page) fails
  the build in `gen_reloc.py`.
- An area moves by whole pages: keep `NAME_PAGE*$100` the only way an area's
  address is formed. A new mailbox field goes in `mailbox.s` and in the
  loader's `dum` block alike (`src/sys/xtgs.s` asserts one against the
  other, and the page's length against `MB_END`).
- CORE and SVC reach files only through `jsl MB_FILECALL` (MLI-shaped:
  `MB_MLI_CMD`, `MB_MLI_PARMS`, `MB_MLI_RES`); nothing but the loader may
  call the MLI or know where the loader is.
- There are two front ends, `src/sys/xtgs.s` (ProDOS 8) and
  `src/gs/xtgs16.s` (GS/OS), and `docs/relocation.md` lists what CORE and
  SVC expect of one. A change to the mailbox, the regions, the command
  letters or the file calls SVC makes goes in both; run `make test-s16` as
  well as the ProDOS 8 tests. Under `XTGS_FRONT=s16` the Memory Manager
  places everything (CORE/SVC/results at `$07-$09`, the areas from `$1800`
  in MAME), `IOB` is not claimed, and `+` still refuses the assembled
  banks and makes `filecall` build directory blocks from `GetDirEntry`.
- Under `S` the PC has no disk: `int_13` answers "no drive" (`disk_have`),
  the kernel is entered at `KERNEL_SEG:0` with `BL=80h`, and the redirector
  hooks itself in at the kernel's first `INT 21h` that DOS can answer
  (`rd_early`, unhooked at the shell's `AX=4B00h`). It depends on FreeDOS's
  kernel (its entry convention and its use of its own `INT 21h` during
  startup); no other DOS boots this way.
- The shared drive makes its folder the ProDOS prefix (`SET_PREFIX`; GS/OS
  prefix 1) and sends partial pathnames, and issues `FLUSH`: both front
  ends answer those. After a change to `redir.s`, `files.s` or a front
  end's file calls run `make test-share` three ways: plain,
  `XTGS_LAYOUT=alt`, `XTGS_FRONT=s16`; and the same three with `BOOT=1`.
- The guest's first bank is a multiple of `$10`; the 20-bit wrap depends on it.
- Host tools speak assembled addresses (`0x2B8000`, `0x001000`, the
  listing's `mb_magic`); `mamerun.run()` translates under `XTGS_LAYOUT` and
  checks `MB_LAYOUT` on every run (under `XTGS_FRONT=s16` it translates
  from the live `MB_LAYOUT`, once the front page's signature appears). `python3 -I tools/layout.py` prints the
  layouts.

Interrupts are live while a guest runs: the DOC timer oscillator's interrupt
(`snd_irq`, through `$E1:002C`) counts IRQ0s into `vTICK`. The firmware
services it on page 1 (`$0100-$01FF`, saved at `svc_sndopen` and restored at
`svc_sndclose`), and any code that touches the sound GLU (`$C03C-$C03E`) or
read-modify-writes `vTICK` outside one instruction must do it under `SEI`.

The core looks for IRQ0/IRQ1 (and does the frame's work) at the slot, and
the slot is counted by control transfers, not by instructions: a taken
jump, call, return, `LOOP`, `INT`, a `REP` string instruction, the
hypercall and `HLT` retire through `next_ct` (`dec vSLOT / beq next_due /
jmp (NEXTVEC)`, or those lines inline), and every `SLOT_N` (4) of them the
slot runs. A new handler that changes IP or CS must retire the same way, or
a loop through it never meets the slot. `IRET`, `POPF` and `STI` bring the
slot forward when an interrupt is owed in Mode B (`irq_soon`; `irq_sti`
makes the instruction after the `STI` retire through `next_owed`,
`src/core/cpu.s`): without that a guest loop can meet the slot only with IF
clear, for ever. A new instruction that can set IF must do the same. The
slot delivers IRQ n
(0, 1 and the diskette's 6) at vector `PIC_BASE+n` and only when bit n of
`PIC_MASK` is clear: never write `INT 08h`/`09h` into the core as a number.

The text screen is drawn from the 6845's start address (`txt_org`,
`src/svc/video.s`; `B800` goes round at 16K, mid-row) and `txt_shadow` is
by place on the screen, not in the buffer. The cursor is the BDA's unless
the guest wrote R14/R15 (`CRTC_CUR`, `cur_where`). `render_cell` takes the
cell's word in A. A text-mode judge must read the buffer from the start
address (`tools/minix_test.py` does; `tools/textshr.py` takes the cells).

A source file added to `src/svc/` or `src/core/` also goes in the
Makefile's `SVC_SRCS`/`CORE_SRCS`, or edits to it do not rebuild.

## The CPU core

What a handler may assume and must keep (`src/core/cpu.s`, `flags.s`,
`tools/gen_cpu.py`; the measurements are in docs/benchmarks.md):

- A handler ends with `jmp (NEXTVEC)`, and one that changed IP or CS with
  `next_ct` (above). The vector is `fetch` itself unless the instruction
  had a prefix: a prefix handler points it at `next_pfx`, which clears
  `vSEGOVR`, `vOVR` and `vREP` and puts `vnext0` back (`next_due` does the
  same for a prefixed instruction that retires through `next_ct`). Whoever
  sets `vNEXT` for a run sets `vnext0` and `vnextb` too (`run_guest`, the
  harness, the JIT's fallback); when the base vector is not `fetch`,
  `next_due` leaves the slot to that vector's owner.
- Flags are lazy. Arithmetic leaves `vLP` (the 65816's P after the native
  operation, with the 8086's sense of carry: a subtraction inverts C before
  it stores), `vLRES` (the result) and `vFS`/`vFD` (the operands, for AF);
  `rFL` holds TF, IF and DF only. Read a flag from `vLP` (`LP_CF`, `LP_ZF`,
  `LP_SF`, `LP_OF`), never from `rFL`; the FLAGS word is `flags_get` and
  `flags_set`. A hand-written handler tail-calls a `flg_*` routine or
  stores all four itself. An instruction that keeps CF (`INC`, `DEC`) or
  changes one flag must leave the others readable: see `flg_incdec16` and
  `flg_cfof` for the pattern.
- `vOVR` is `$8000` while a segment override is in force and 0 otherwise.
  Anything that sets or clears `vSEGOVR` does the same to `vOVR`: the fast
  ModR/M routines test only `vOVR` (`bit vOVR / bmi`).
- Two sets of ModR/M routines. `modrm_b`/`modrm_w` (`eab_xx`/`eaw_xx`) set
  `vMODRM`, `vREGOFF`, `vEA`, `vEASEG` and `pEA`, with a register operand
  as a direct-page `pEA`: any handler may use them, and `LEA`, `LES`/`LDS`
  and the far `FF` forms need `vEA`. The generated fast handlers fetch the
  ModR/M byte themselves (X = ModR/M * 2) and call `(emb_tab,x)` or
  `(emw_tab,x)` for a memory operand only: those leave `pEA`, keep X and
  set none of the other four. `regb_tab`/`regw_tab` give the reg field's
  direct-page offset for the same X.
- The effective-address tails (`ea_ds_b`, `ea_ss_w`, `ea_seg_b`...) are
  entered with the offset in A. The base's bank word is stored as it is
  unless the low word's add carried (`ea_carry`, `ef_carry`, `stk_carry`):
  keep the bases' bank words whole host banks (`set_ds`).
- A word at offset `$FFFF` is split across the segment's end (`ea_split`
  and its bounce word; `push16`/`pop16` for the stack): a new inline path
  must test for it and take the slow one.
- The string instructions (`src/core/ops_str.s`) work on host pointers:
  alone, one add for each pointer and the direction tested once; under
  `REP`, `MVN`/`MVP` for `MOVS` and `STOS` (an overlapping `MVN` is the
  fill) and a `[ptr],y` loop for `SCASB`/`CMPSB`, in runs that end where
  SI, DI or either host pointer would wrap (`lim_fb`...), the element
  routine (`movsw`...) taking a word that lies across a wrap. A word move
  whose destination is one byte from its source is not a byte move
  (`rep_slow`). A run into the text bank marks every 256-byte page it
  touched (`vid_mark_rng`), not the first. `tests/com/strrep.asm` is the
  test for all of it: add the case when a path is added.
- After a change to the generator or a handler, sample with `make test-cpu`
  and then sweep all three ranges (`tools/sweep_cpu.py --ops 00-3F`,
  `40-BF`, `C0-FF`). The sweep's only failures are `E4`, `E5` and `ED`
  (173 vectors: the ports the core serves in Mode B, tests/cpu/EXCLUDE.md).

## Merlin32 rules

- MX is tracked linearly and does not follow `XCE` or branches. Put an
  explicit `MX` at the top of every routine and at every label reached with a
  different width. `tools/check_mx.py` runs on every listing in the build.
- Local labels are `:name`, scoped to the enclosing global label. `@name` is
  NOT scoped (verified: duplicate-label error). Merlin32 renames `:name` to
  `ozunid_N` in listings.
- No operator precedence: expressions evaluate left to right. `*` is the
  current PC. `err *-1-CORE_BASE/$10000` asserts a bank-sized image.
- A label and `=`/`EQU` need whitespace between them.
- In 16-bit mode `#<x` is the low word, `#^x` the bank, and `#>x` is `x>>8`
  (not the high word). Avoid `#>` outside 8-bit code.
- `MVN src,dst` (Merlin order); the opcode encodes dst then src. `LDA dp,X`
  assembles as direct page automatically when the operand is under `$100`.
- `PUT` refuses two-letter filenames. `-V` writes `<name>_Output.txt` beside
  the source and `error_output.txt` only on failure; the Makefile moves both
  into `build/` and clears the stale one first.
- `TAX/TAY/TCD/TCS` move all 16 bits of C regardless of M; an 8-bit `LDA`
  before them leaves B stale.
- After a `JSR` to a routine that returns in a different width (the `flg_*_r`
  routines return with 16-bit A), restate it with `mx` before any
  immediate: `check_mx.py` cannot see across a call. An `and #$FE` assembled
  8-bit but executed 16-bit swallowed the next opcode (ops_grp.s, M1).
- `ERR expr` fails the build (exit 1) when `expr` is non-zero.
- `LDX/LDY/STX/STY/CPX/CPY` (and the read-modify-write ops) have no long
  addressing mode; Merlin32 assembles `ldx >addr` as absolute and drops the
  bank without a word. Go through A (`lda >addr` / `tax`). The build runs
  `tools/check_long.py` over the sources for this.
- `sta long,y` does not exist either (only `,x`); use a `[dp],y` pointer.
- `BIT $C019` and other soft-switch tests need 8-bit A.

## Harness conventions

- The loader sets `MB_MAGIC` to `$5A5A` only after the core has
  returned and shutdown is done, then waits for a key before `QUIT`, so a
  headless run (`mamerun.py --wait`) dumps stable memory.
- Results live in memory, never only on screen: mailbox fields, the guest text
  buffer at `$2B:8000`, bank `$05` for harness results.
- Judges read label addresses from the Merlin listing via `tools/symbols.py`;
  no address is duplicated into Python by hand.
- A MAME save state does not bring the DOC timer interrupt back: after a
  load the IRQ0 tick stands still, and a guest that waits on it (a game
  loop on `0040:006C`) hangs. Run anything tick-driven from a cold boot.
- A Mode B test that needs many DOS commands puts them in the floppy's
  `AUTOEXEC.BAT` and reads the BIOS teletype capture (`CAP_BUF`), as
  `tools/share_test.py` does (it ends the run with a `REBOOT.COM`, `INT
  19h`); typing them through the harness is slow and loses keys.
- The redirector's `RD_LOG` ring (`share_test.py --show`) names each
  `INT 2Fh AH=11h` function DOS made and its DOS error; `$FF` is a call
  left to DOS.
- Keys for a Mode B guest: the harness's `"key"` strings cannot hold a
  return or a quote; use `"coded": "...{ENTER}"`. A held key is a
  `"press"` input with `"value"` 1, then 0 some frames later (the field
  `"d  D"` on `:macadb:KEY0`, `"Control"` on `:macadb:KEY3`); `kb_poll`
  keeps a key down for `KB_MINHOLD` frames at least.
