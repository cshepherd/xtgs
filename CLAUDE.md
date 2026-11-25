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
                  (tools/textshr.py), under a manifest's "video": "t160"
                  the 160x100 cells (tools/t160shr.py), under "cga4" or
                  "cga6" the CGA graphics lines and the palette the
                  registers call for (tools/cgashr.py; "cga_colours") and under
                  "ega" the planes of mode 0Dh through the palette
                  registers (tools/egashr.py; "ega_ac" the registers) and
                  under "tandy9" the two pages a Tandy shows in mode 09h
                  and under "tandy8" the one of mode 08h and under
                  "tandyA" mode 0Ah's 640 pixels in four colours
                  (tools/tandyshr.py; "tandy_pal", "tandy_mask",
                  "tandy_page"); a
                  manifest's "cmd" is XTGS.CMD's lines after the first;
                  every test's DOC registers are judged as well
                  (tools/psgdoc.py: the oscillators enabled, the noise
                  table, the timer's rate; under a manifest's "psg" every
                  register write the Tandy's sound chip led to)
make test-cpu OP="00 01" [COUNT=300]
                  SingleStepTests vectors for those opcodes (a group sub-opcode
                  is OP=80.3); the judge explains the first failure. COUNT is
                  for the whole run, and a run of more than 65,535 vectors
                  overflows the harness's count (every vector then fails with
                  zeroes): to sample several opcodes, run tools/judge_cpu.py
                  --op X --count N once for each, as test-layout does
python3 -I tools/sweep_cpu.py --ops 00-3F --tag A
                  every file in a range, four a boot; build/vec/sweep_A.json
make bench        guest instructions/second, stock and 16 MHz Zip (tools/bench.py;
                  tests/bench: reg, mem, jmp, str one long REP MOVSW, strs short
                  string instructions)
python3 -I tools/profile.py reg|mem|jmp|str
                  attribute MAME PC samples to core routines (tools/profile.py)
python3 -I tools/jit_bench.py [--only reg,jmp,jlink] [--engines B,J,U,S,L,G,C]
                  the bench loops by the interpreter (B), the hand translation
                  (J) and the translator's modes (K x), timed like make bench,
                  the registers compared with the interpreter's, the
                  translator's counts (docs/jit.md; work files in build/jitbench/;
                  tests/bench/jlink.asm is its test of the links, not a
                  benchmark)
python3 -I tools/jit_profile.py list | collect NAME | report NAME | summary | compare
                  a real workload profiled from MAME's side, nothing changed
                  in the guest (docs/jit.md "M6.2"): every instruction fetched
                  and every edge, the time by where the 65816 is and by guest
                  instruction, writes into executed pages; report decodes it
                  (tools/x86dec.py). The workloads are games on the games
                  volumes (make games-image, games-ega-image, and
                  build/boot/gamescga.po by hand with --cmd VIDEO=CGA),
                  built from the same CORE as build/core.lst; work files in
                  build/jitprof/, the reports kept in docs/jitprof/. compare
                  is each workload against its copy in build/jitprof/base/
                  (before and after a change: copy the .pkl files there
                  first); Thexder's demo takes a different course from run
                  to run, the others do the same work every time
python3 -I tools/jit_profile.py count NAME; python3 -I tools/jit_look.py
                  the same workload with the translator, counted and not
                  timed: calls of each run-time routine, the lazy flags
                  stored and never read, pieces made by address (kept in
                  build/jitprof/jit/NAME.count); jit_look.py puts the
                  counts beside the samples of `collect NAME --jit` and the
                  run without it: cycles a call, what a look at the code a
                  piece goes on to would show of the flags, the cache a
                  window's code needs (docs/jit.md "A closer look";
                  docs/jitprof/closer-look.txt)
python3 -I tools/jit_fuzz.py --micro | --seed N [--cases C] [--runs R] [--small]
                  the translator against the interpreter (docs/jit.md "M6.3"):
                  a program of loops run without and with JIT=ON, a sum of
                  the registers, the flags and a buffer after each loop
                  compared; --micro is one instruction form a loop from a
                  fixed list (add the form there with its template), a seed
                  is random loops; both end on a wait for the clock's tick
                  (work files in build/jitfuzz/). --small has the harness
                  set the translator's c_lim so that its first bank of
                  code holds a few pieces: everything else is made in the
                  second, and what runs crosses between them all the time.
                  XTGS_JIT=1 puts the
                  translator on the volume of any other test or tool
                  (tools/make_image.sh: the file JIT and the line JIT=ON):
                  XTGS_JIT=1 make test-com, test-share BOOT=1...
                  tools/jit_profile.py collect NAME --jit is a workload with
                  it (kept in build/jitprof/jit/), compare --jit those
                  against the ones without, by the guest's writes a second
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
make test-minix [ZIP=1] [CGA=1] [MINIX=path]
                  Minix 1.5's demonstration diskette (in the tree,
                  third_party/minix/demo_dsk.ibm) booted under D to its
                  shell, a command line typed, the scrolled screen judged
                  (docs/minix.md; tools/minix_test.py; work files in
                  build/minix/; 378 emulated seconds at stock speed, 53 with
                  ZIP=1). CGA=1 is the PC with no EGA (XTGS.CMD's VIDEO=CGA):
                  Minix then scrolls round the end of the 16K, and without
                  it copies the screen back to the buffer's start. Like test-share, run it under XTGS_LAYOUT=alt and
                  XTGS_FRONT=s16 by hand
make test-psg     the Tandy's sound chip by ear: tests/snd/psgwav.asm's fourteen
                  sounds recorded by MAME (the DOC's two channels) and
                  measured: frequencies, levels, the noise's bits against
                  the shift register, the timer by their spacing
                  (tools/psg_test.py; work files in build/psg/; KEEP=1 keeps
                  the 20 MB recording; docs/sound.md)
make disk-image IMG=path
                  build/disk/disk.po: XT/GS and any PC diskette image as
                  DISK, command D (make run-disk boots it in Ample's MAME);
                  make minix-image / run-minix: the same with Minix's
make boot-shared  FreeDOS booted from the folder third_party/freedos/fd/SHARED
                  (tools/boot_dos.py with a folder; work files in
                  build/bootdos/); make boot-dos is the floppy image
make dos-image    build/boot/boot.po: XT/GS and that folder as SHARED,
                  command S (make run-dos boots it in Ample's MAME)
make tandy-image  build/boot/tandy.po: the same volume with the line
                  VIDEO=TANDY, a Tandy 1000 (TDYSND, TDYDEMO at the prompt;
                  make run-tandy boots it in Ample's MAME)
make release      build/release/xtgs-VERSION.po (XTGS_VERSION in the Makefile):
                  the volume to hand out, an 800K ProDOS disk (VOLSIZE=
                  another size) that boots from ProDOS 8 into FreeDOS
                  (command S) and has the GS/OS application with its icon
                  beside XTGS.SYSTEM, CORE, SVC and XTGS.CMD in the root;
                  SHARED is third_party/freedos/fd/SHARED without
                  EGADEMO.BAS, plus release/shared/ and its subfolders, as
                  they are (names ProDOS and DOS can both hold, or the
                  build stops; a file whose extension and bytes are text
                  gets DOS's line ends and type TXT, any other is BIN),
                  and release/READ.ME is on it
                  (tools/release_image.py); make run-release boots it in
                  Ample's MAME
make games-image  build/boot/games.po: the release volume as a Tandy 1000
                  (VIDEO=TANDY) on an 8 MB disk (GAMESIZE=), with the games'
                  folders of release/shared on it (the Makefile's GAMES:
                  lsl2, a Sierra game whose RESOURCE.CFG names TANDY320.DRV
                  and JR.DRV, outrun, arkanoid, keen1, mech, sub688, carmen, thexder: whichever are there), which
                  make release leaves out and .gitignore keeps out of the
                  tree (release_image.py's --without and --cmd); make
                  run-games boots it in Ample's MAME; lsl-image and run-lsl
                  are the older names
make games-ega-image
                  build/boot/gamesega.po: the same volume without
                  VIDEO=TANDY, a PC with the EGA (keen1, mech, and OutRun's and
                  Arkanoid's EGA choices); make run-games-ega boots it
make games-test-image
                  build/boot/gamestest.po: the EGA games volume with the
                  lines JIT=ON and STATE=ON and no boot state on it (the
                  translator, a state written from XTGS Control, and under
                  GS/OS as a second volume a program opened from the
                  Finder, docs/finder.md); make run-games-test boots the
                  one that is there and builds only when there is none: it
                  is the user's working volume, with their boot state and
                  their XTGS.CMD on it. Never rebuild it (games-test-image)
                  or write to it unasked; work on a copy
make test-joy     the IIGS's joystick as the PC's game port (docs/joystick.md):
                  JOYTEST L under FreeDOS, MAME's joystick (XTGS_GAMEIO=joy)
                  moved by the harness, its lines judged (tools/joy_test.py;
                  work files in build/joy/)
make test-mouse   the IIGS's mouse by INT 33h (docs/mouse.md): MOUSETST L under
                  FreeDOS, MAME's mouse moved and its button pressed by the
                  harness, the program's lines judged (tools/mouse_test.py;
                  work files in build/mouse/; an argument is a line of
                  XTGS.CMD: MOUSE=OFF must find no driver)
make test-control the desk accessory XTGS Control (docs/control.md): FreeDOS
                  from a folder, Control-Apple-Esc, and a boot each for the
                  accessory's soft reboot, its hard one, a state saved and
                  restored, its quit, and the menu's own name for the quit
                  ("Quit to ProDOS" or "Quit to GS/OS": a constant of two
                  characters has its FIRST in the low byte, `cmp #'XT'` for
                  "XT"), judged by MARK.COM's lines (tools/control_test.py; build/control/;
                  under XTGS_LAYOUT=alt and XTGS_FRONT=s16 by hand)
make test-state [ONLY=make,load,go,cold,same,again,hard,files,day,ega,disk,bad,time,quit]
                  the boot state (docs/state.md, M7): FreeDOS booted from a
                  folder with STATE=ON, XTGS.STATE written from the desk
                  accessory's sixth choice and read by the tool's own
                  decoder, the PC started from it and every region compared
                  with the file before an instruction runs, the same keys
                  after it and after a cold boot, the boot's files changed
                  from outside and by the PC (files), states made days old
                  (day), a state taken in mode 0Dh, damaged files, the
                  times (tools/state_test.py; work files in build/state/;
                  under XTGS_LAYOUT=alt, XTGS_FRONT=s16 and XTGS_JIT=1 by
                  hand)
make test-xms     the XMS driver (docs/xms.md): FreeDOS booted from a folder
                  (command S) whose AUTOEXEC.BAT runs XMSTEST, its line
                  judged, then the same with XMS=OFF (tools/xms_test.py;
                  work files in build/xms/). Like test-share, run it under
                  XTGS_LAYOUT=alt and XTGS_FRONT=s16 by hand
make test-open [ONLY=sub,root,outside,noname,nodos,state,drive,bas]
                  a document opened with XT/GS (docs/finder.md): the GS/OS
                  application launched as the Finder launches it for a .BAT,
                  a .COM or a .BAS of the folder DOS has (tests/gsos/start16.s puts
                  the pathname in the volume's file ARG into the Message
                  Center), the keys CD and the name typed at the prompt
                  after a boot, after a boot state and under D with the
                  folder as E:, and the files refused (tools/open_test.py;
                  work files in build/open/; always the GS/OS front end;
                  XTGS_JIT=1 and XTGS_LAYOUT=alt by hand). The Finder itself
                  is not in it: build/xtgs-finder.po driven by hand
make test-serial  the IIGS's serial ports as COM1 and COM2 (docs/serial.md):
                  COMTEST1/COMTEST2 under FreeDOS, MAME's modem and printer
                  ports looped back (XTGS_MODEM, XTGS_PRINTER), then COM2
                  alone and neither (tools/com_test.py; build/serial/)
make test-release copies of that volume booted headless: from ProDOS 8 to
                  C:\> and, in a second boot, GWBASIC HELLO (judged by the
                  screen: NANSI.SYS is the console there, so the teletype's
                  capture has none of DOS's text), and its XTGS launched from a
                  GS/OS volume's Start as the second disk
                  (tools/release_test.py; --show prints the console)
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
the M6 runtime block translator on `BENCH` (`src/core/jit2.s`; docs/jit.md;
a letter after it is its mode, `K U`, `K S`, `K L`, `K G`, `K C`: unlinked,
the old self-loop link, every direct edge linked, linked with the guard's
count in X, and translating at every dispatch; it elides flags and is right
for the bench loops only).
The loaders read the first line only. A later line `X=path` (`C=/VOL/DIR`,
or `C=DIR` below the launch folder) is the shared drive, which SVC reads
for itself under `D` and `S` (`rd_readcfg`; under `S` the drive is always
`C:` and the folder `SHARED` when no line names one). A line `VIDEO=CGA`,
before or after that one, is a PC with no EGA (`eg_none`, `ega_off`: mode
0Dh is not set, `INT 10h` 11h and 12h answer nothing; docs/ega.md) and
`COM1=MODEM` and `COM2=PRINTER` give the PC the IIGS's serial ports (`com_cfg`, `com_bda`; docs/serial.md), `MOUSE=OFF` takes the mouse driver away (`ms_cfg`; docs/mouse.md), `XMS=OFF` the XMS driver (`xms_cfg`; docs/xms.md), and
`VIDEO=TANDY` a Tandy 1000 (`tdy_setup`: no EGA either, the page register,
the video array and modes 08h, 09h and 0Ah; docs/tandy.md), and `JIT=ON`
turns the translator on (`JIT_CFG`; the file `JIT` must be on the volume,
which the release and the games volumes have; `make games-image JIT=1`
writes the line; docs/jit.md), and `STATE=ON` starts the PC from the file
`XTGS.STATE` beside `CORE` when there is one that is this build's, this
layout's and this `XTGS.CMD`'s, no more than 250 days old, and the files
the PC was booted from are what they were (`BS_CFG`, `bs_try`; under `S`
only; off unless the line is there; docs/state.md). The same routine reads both,
and command `C` calls it too (`svc_pcinit`), for the `VIDEO` line only.
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
| `src/gs/xtgs16.s` | `XTGS` (S16, `build/xtgs16`): the GS/OS front end, the same job as `XTGS.SYSTEM` from GS/OS, and the one a document can be opened with (`get_arg`: the Message Center's message 1; `arg_refused`; docs/finder.md). Relocatable OMF (`rel`); one Memory Manager block in bank `$00` for `ZP`/`MBX`/`PATH`/`XFER`, its front page marked `"XTGS"` at `+0` (the harness finds it by that); `filecall` answers the MLI lists with GS/OS calls |
| `src/core/` | `CORE` at `$03:0000`: the CPU (dispatch, handlers, lazy flags in `flags.s`), the EGA's planes as the guest reaches them (`ega.s`, docs/ega.md: the trap in the ModR/M tails, `ega_retire`, the string instructions' `eg_strop`, the registers at ports 3C0h-3CFh in `ega_out`) and the M0 probe; 52 KB of the bank's 64 used |
| `src/jit/` | `JIT`, the translator (docs/jit.md "M6.3"): its own image at `JIT_BASE`, loaded by both front ends when the file is there, used when `JIT=ON`. `jit.s` (the translator's side: `jt_init`, `jt_tr0`, the entries' tables, `kill`, `smc0`; and, assembled for the bank at `JIT_RT` and moved there and to `JIT_RT2` by `jt_init`, the run-time routines: the dispatcher `jt_look`/`h_disp`, the links, `h_verify`, `h_push`/`h_pop`, `h_smc`), `scan.s` (a piece's instructions, the jumps among them, which flags are read: `sc_scan`, `sc_resolve`, `sc_live`), `emit.s` (the piece's record and stub, a template for each instruction: `em_region`, `stamp`), `gen/jtab.s` and `gen/jrt.s` from `tools/gen_jit.py` (the templates as bytes with their fixups, the opcode tables, the pointer routines; never edit). A template is 65816 code assembled by the generator, not by Merlin: nothing checks it but `tools/jit_fuzz.py`, so a new template gets its line in that tool's `MICRO` list. `src/core/jitc.s` is the core's side: the probe at a taken jump back (`jit_bk`; `jit_start` patches a `JMP` to it into `jcc_hook` and `e9_hook`), what a run of translated code comes back with (`jit_ret`: the interpreter does one instruction through `jit_hook` and the dispatcher is asked again), the guard's look at the slot (`jr_guard`, `slot_x`) |
| `src/core/gen/` | generated by `tools/gen_cpu.py`: the opcode table, the ModR/M routines (the general set `eab_`/`eaw_` and the fast set `emb_`/`emw_`), the ALU, `TEST`, `MOV r/m`, `PUSH`/`POP r16` and `Jcc` handlers, and `egaw.s` (`eg_class`, what each opcode does to a memory operand, and `ega_rd`/`ega_wr`, a byte through the graphics controller). Never edit; change the generator |
| `src/svc/` | `SVC` at `$04:0000`: text screen, CGA graphics and the 160x100 text-cell mode (`video.s`, docs/cga.md; `gen/t160.s` from `tools/gen_tables.py`; the colours are `cga_setpal`/`cga_setpal6` from `cga_bg`/`cga_pal`/`cga_int` and `3D8h`'s bit 2, every colour number through `cga_ent`, which on a Tandy is the array's mask and palette (`tdy_col`): a new palette path goes through it too, and whoever changes the two registers for the BIOS keeps `40:65`/`40:66` by `cga_bda`), the BIOS's text in the graphics modes (`gtext.s`: every `INT 10h` character service draws the font into B800's pixels when `gt_on`, and marks `VID_DIRTY`; never store a text cell there in a graphics mode; the EGA's and the Tandy's modes take its cell, glyph and scroll-line routines for their own, and a new mode's go in the same places: `gt_cols`, `gt_cell`, `gt_draw`, `gt_read`, `gs_copy`, `gs_fill`, the pixel calls), the EGA's mode 0Dh (`ega.s`, docs/ega.md: the mode set, `ega_flush` from the four planes to the SHR by `gen/egatab.s`, the palette registers, eight pages each with its cursor (`eg_curin`/`eg_curout` around an `INT 10h` that names a page in BH), `gtext.s`'s cell, pixel and scroll routines for the planes, `INT 10h` 05h/10h/11h/12h; `eg_none` is the PC without it), the Tandy 1000's video (`tandy.s`, docs/tandy.md: `TDY_ON` from `VIDEO=TANDY`; the page register at 3DFh: B800-BFFF is always what the CPU has, a copy of its pages, so the core only marks `VID_DIRTY`; each page has a home slot and in modes 09h and 0Ah a page goes home with only the 256s written and comes compared where it may differ (`tdy_setpage`, `tdy_hv`, `tdy_wback`, `tdy_load`; the flags `tdy_wr`, `tdy_df`/`tdy_dh`, and `tdy_sd` for the screen: read the note at `tdy_setpage` before touching them, and call `tdy_unsync` wherever the window is changed without `VID_DIRTY` being marked or another mode's drawing takes the flags); the video array at 3DAh/3DEh; mode 09h, 320x200 in 16 colours, drawn a line an `MVN` by `tdy_flush` from the two pages shown, wherever they are; mode 08h, 160x200 in 16, one page in the CGA's layout, a byte through `gen/tdytab.s` to two by `tdy_flush8`/`tdy_row8` (`gfx_mode` is `GFX_TDY8` or `GFX_TDY9`; by the ports the two differ in 3D8h's bit 0); mode 0Ah, 640x200 in four colours, in mode 09h's 32K and by its flush, the SHR in 640 mode: a line is 80 pairs of bytes, the even one the low bit of eight pixels' colours and the odd one the high bit, `tdy_row`'s other path weaving a pair through `cga640_tab` into a word, `tdy_setpal` making the sixteen entries of colours 0-3 (`tdy_pm`), `tdy_setpixA` the pixel call (`GFX_TDYA`; by the ports the array's mode register bit 3 without bit 4, and 3D8h's bits 1 and 4); `INT 10h` 05h AL=80h-83h, 10h, 0Ch/0Dh; the BIOS's text in the three modes, which `gtext.s` hands over when `tdy_gm` says so: `tdy_lnoff` a line's place, `tdy_cell` a cell's (40, 20 and 80 columns: four bytes a cell, in mode 0Ah a pair), `tdy_draw`, `tdy_read`, `tdys_copy`/`tdys_fill` a scroll's line, `tdy_fillw` BH as a colour; all through the window at B800, so on the CPU's pages, each write marked by `tdy_pmark`/`tdy_mkln`), the PC's structures (`pcinit.s`), BIOS (`bios.s`) and DOS (`dos.s`) hypercall handlers, keyboard and frame work (`keyboard.s`), the shared drive (`redir.s`, docs/share.md: a ProDOS folder as a DOS network drive in Mode B, `INT 2Fh AH=11h` answered through `files.s`; guest stubs at `F000:RD_OFF`, hypercalls 256-258 from `svc_hypercall`, `rd_poll` each frame, and under `S` before every hypercall while `rd_early` is set, which is how the redirector gets in before FreeDOS's kernel reads `FDCONFIG.SYS`), the DOC as PC speaker and IRQ0 timer and, on a Tandy, as its SN76496 at ports C0h-C7h (`sound.s`, docs/sound.md: three oscillators on a PC, eleven on a Tandy, so the speaker's and the timer's constant is `snd_k` and the timer's oscillator `snd_to`, never a number; `psg_write` from `svc_portout`; a voice is a pair of oscillators halted, written and keyed on back to back (`pv_setfreq`, `pv_gate`), only a volume written as they run; the white noise is the chip's shift register in DOC RAM `$8000-$FFFF` (`psg_ntab`), the periodic the pulse at page 1; every DOC register write goes through `doc_w`, which keeps `DOC_REG` and the log `DOC_LOG` the judge replays: a new write path that goes round it fails `psg`), the 8259, the 8237's channel 2 and the 765 diskette controller for a guest that drives them itself (`ports.s`, docs/minix.md: `svc_portout`/`svc_portin`, entries 36 and 39, where the core sends a port it does not serve in Mode B), the IIGS's joystick as the PC's game port at 201h and `INT 15h AH=84h` (`joystick.s`, docs/joystick.md: a write reads the paddles with interrupts off (`joy_sample`), a read counts down the reads an axis's bit lasts, which `joy_loop` scales by the length of the guest's read loop, found from the IP in Y at `svc_portin`: keep Y the guest's IP down to `joy_read`), the IIGS's serial ports as COM1 and COM2 (`serial.s`, docs/serial.md: `COM1=MODEM` and `COM2=PRINTER` in `XTGS.CMD`; 8250s at 3F8h/IRQ4 and 2F8h/IRQ3 and `INT 14h` on the SCC's channels B and A; a port is its index 0 or 2 (`com_p`) everywhere; `com_irq` sits on the firmware's interrupt manager vector `$E1/0010` while a port is open, serves our channels into the rings `COM_BUF` and returns with `RTI`, and jumps on to the firmware for anything else: it must keep every register and the mode, and must not pass a served interrupt on (ProDOS 8 dies at 255 unclaimed); every SCC access is under `SEI`), the IIGS's mouse as the PC's behind `INT 33h` (`mouse.s`, docs/mouse.md: no driver to load, `MOUSE=OFF` in `XTGS.CMD` for none; `ms_poll` each frame reads the ADB GLU's `$C027`/`$C024`; positions are the driver's 640 by 200 in every mode; the text cursor is the cell through the two masks in the guest's own buffer; a handler set by function 0Ch is called from the stub at `F000:MS_OFF`, which the core's slot enters when `PIC_MOUSE` is raised, by no vector (FreeDOS takes 70h-77h), hypercalls 259 and 260 around the far call; DOS points vector 33h at its own `IRET` as it starts and `ms_poll` takes it back once, half a second later), XMS memory for the guest (`xms.s`, docs/xms.md: under `S` the disk image's region, which both front ends then claim last and may fail to (`claim_xms`; `MB_LAYOUT`'s word says); `INT 2Fh AH=43h` through the shared drive's hook, `rd_int2f`, which now sees every `INT 2Fh`; the entry a stub at `F000:XMS_OFF`, hypercall 261; blocks, and moves by `MVN`: no A20, no HMA, no UMBs; FreeCOM swaps into it, which is the 90 KB a large program needs), a document the GS/OS application was opened with (`ghost.s`, docs/finder.md: the Finder opens `XTGS` for a file named `*.EXE`, `*.COM`, `*.BAT` or `*.BAS`, the bundle's document records from `tools/gsos_rfork.py --doc`, and the front end's `get_arg` leaves its pathname at `MB_ARG`; `gh_check`, from `svc_bootinit` after `rd_setup` and before `bs_try`, holds it to the shared folder and makes of it the keys `CD \DIR` Return `NAME.EXT` Return, each name through `rd_unname`, a `NAME.BAS` after `\GWBASIC ` (`gh_basic`: without the `\` when no `GWBASIC.EXE` is in the drive's root), or refuses it with `MB_ARGN` `$8000` + why and `svc_bootinit`'s answer 3, which starts no PC and the front end's `arg_refused` says in a text alert; `gh_poll`, from `kb_poll` when the IIGS has no key, types them as `kb_poll`'s own keys, the first when the guest has asked an empty keyboard (`gh_ask`, from `INT 16h`'s two waits in `bios.s`) for thirty frames with a `>` before the cursor of a text screen: a new way for the guest to wait for a key calls `gh_ask`; the keys and their index are in the front end's page, `MB_ARG`/`MB_ARGI`, and never in SVC or the PC, so a state saved or loaded has nothing of them), the desk accessory XTGS Control (`control.s`, docs/control.md: `svc_cda`, SVC's entry 14, which both front ends install with the Desk Manager around the core's run (`cda_on`, `cda_off`); it runs inside whatever was interrupted, so it only draws on the text page, reads the keyboard and leaves `CTL_REQ`, which `svc_vbl` returns to the core with the carry set (`ctl_poll`); the core stops with `CTL_EXIT` + the request and the front end loads CORE and SVC again and runs the PC anew, `boot_pc`, after `zero_guest` for a hard reboot: a new piece of state that must not survive a reboot is fine in CORE or SVC, and one kept by a front end must be reset there; request 3 is the quit with no key; `CTL_REQ` holds one request, and a start state that waits to be written (6) is not dropped for a restart, the quit or a save chosen after it in the same visit: that one is stored with bit 7 set and `ctl_poll` does `bs_save` first, so a new kind of request goes through the same store; 4 and 5 save and restore the PC's state in Memory Manager blocks without stopping the core (`st_save`, `st_restore`: the direct page, the results bank, the SHR, the guest's banks, the XMS in use and CORE's and SVC's banks, a page at a time, a uniform page as one word of the map; `st_walk` runs in SVC as SVC is put back, so its three passes must keep the same things in the same variables at every step and what differs goes on the stack: read the note in `control.s` before touching it; a new piece of PC state that lives outside those regions, in a front end, in hardware or in bank `$00`, needs a line in `st_rg` or in `st_restore`'s resync), the boot state (`state.s`, docs/state.md, M7: `bs_save`, the desk accessory's sixth choice, writes the accessory's saved state, `st_rg`'s seven regions, to `XTGS.STATE` with a header that binds it to the build (`gen/buildid.s` from `tools/gen_buildid.py`: a CRC of CORE's and SVC's sources), to `MB_LAYOUT` and to `XTGS.CMD`; `bs_try` from `svc_bootinit` checks the header, the map and the pieces' sums before anything is changed, and `svc_stload`, SVC's entry 15, which the core's `boot_state` calls in place of the boot, reads the data a piece of 8K at a time, holds each to its sum and only then copies it to its places, SVC's own bank last: it keeps everything it needs in the direct page and changes no code of its own; the host's own variables in SVC's bank are kept across the load by the list `bs_keep`: a new variable of SVC's that is the host's and not the PC's, a saved vector, a handle, a path, goes on that list; a piece that fails stops the core with the hard reboot's code, `BS_BOOT` 6, and the start after that boots; `BS_BOOT`, `BS_STAT` and `BS_WHERE` say what happened, and when there was a file and the PC boots, `bs_said` puts the reason on the sign-on, "Boot state not used: XTGS.CMD has changed" and the like (a new reason for refusing a state gets its line in `bs_tt`); the files the PC was started from are kept in `MF_TAB` by `mf_do`, which `files.s`'s `p_open`, `p_getinfo`, `p_create`, `p_destroy`, `p_rename`, `p_write` and `p_seteof` call: a new way for SVC to open, look for or change a file by a partial pathname goes through those helpers or calls `mf_do` itself, and anything of the state's own that looks at files does it with `MF_ON` 0 or by a full pathname; `mf_ident` is what a file is, written by `mf_put` at the save and held to by `mf_chk` at the start; the day of the save is in the header and `svc_stload` adds the days since to the BIOS's midnight count, which is how FreeDOS learns the date: `clk_days` in `clock.s`; the desk accessory's hard reboot sets `BS_SKIP`, and the start after it boots), the IIGS clock as the PC's date, time and tick count (`clock.s`, docs/clock.md: ReadTimeHex, read-only to the guest; `clk_sync` every 128 frames adds the IRQ0s the guest lost to `0040:006C`), host capture (`capture.s`). Entry table at `$04:0000`, 3 bytes an entry |
| `tests/com/` | nasm `.COM` programs with `NAME.json` manifests (keys in `tools/judge_com.py`); `tests/expected/NAME.out` is the exact console output. `fileops` is the handle file functions end to end; `strrep` is the string instructions (219 cases against the same work done by ordinary instructions: block ends, segment wraps, overlaps, the text buffer; it takes 75 emulated seconds of the judge's 120); `clock` prints the date and time every way a PC can ask (only its shape is judged there: `make test-clock` judges the values); `t160` and `t160x` enter and leave the 160x100 mode through the 6845; `gtext` and `gtext6` (one source) are `INT 10h`'s text and pixel services in modes 4 and 6, ending on a picture the judge compares with the SHR; `ega` and `egap` (one source, 107 cases) are mode 0Dh: every write and read mode, the string instructions' paths, the BIOS and its pages, ending on a picture; `egaw`, `egaww`, `egawp` and `egawe` (one source) are the mode as a window on a wider buffer (the 6845's offset register, the start address, the attribute controller's panning, odd and even; round the planes' end; writes past the 8000th byte after the first draw), judged by the picture; `egaf` and `egafn` (one source) are two parts of the planes shown in turn by the start address, thirty times, something drawn in the hidden one each turn (the lines that differ are all that is drawn: `eg_lcmp`); `tandy` and `tandyp` (one source, 51 cases) are the Tandy's pages, array and mode 09h, ending on a picture (`tandyp`: the mode by the ports, the screen's pages not the CPU's), `tandyf` (171 cases) is two pairs of pages changed over forty times as a game does that shows one and draws the other (a page's home, the 256s written, the compare: `tdy_wback`, `tdy_load`), `tandy8` and `tandy8p` (one source, 36 cases) its mode 08h (`tandy8p`: by the ports, the screen's page at BC00), `tandya`, `tandyap`, `tandyax` and `tandyat` (one source, 42 cases) its mode 0Ah (`tandyap`: by the ports, pages 2 and 3, the palette turned round behind a mask; `tandyax`: left by the array's mode register, the same bytes judged as mode 6; `tandyat`: left by 3D8h for text), and `ttext`, `ttext8`, `ttexta` and `ttextp` (one source, 83 cases) the BIOS's text in the three modes (`ttextp`: in mode 09h on pages 4 and 5 while the screen keeps 6 and 7, which must not change), and `gtextt` is `gtext` on the Tandy; `psg` is the Tandy's sound chip (129 bytes to port C0h and its other addresses, then the speaker and the timer; the judge is `tools/psgdoc.py` on the DOC's log, the manifest's `"psg"` naming what the speaker and the timer play from which byte) and `psgpc` the same program on a PC; `cgapal4`, `cgapal5`, `cgapal6` (one source, `cgapal.asm`) are the CGA's colours (the BDA's copies as cases, the SHR's palette by the judge) and `tandyc4`, `tandyc5`, `tandyc6`, `tandyct` (the 160x100 mode; prints nothing) and `tandyc9` the same on a Tandy, the array's palette and mask behind them. `tests/demo/egademo.asm`, `tdydemo.asm`, `tdysnd.asm`, `joytest.asm`, `mousetst.asm` and `xmstest.asm` are not tests: `tools/build_freedos.py` assembles them as `EGADEMO.COM`, `TDYDEMO.COM`, `TDYSND.COM` (the sound chip: a round for three voices), `MARK.COM` is `tools/control_test.py`'s own (`tests/demo/mark.asm`, assembled by the test), `XMSTEST.COM` (the XMS driver's calls, twelve steps, for `tools/xms_test.py`), `MOUSETST.COM` (the mouse by `INT 33h`, `MOUSETST L` a line a change, for `tools/mouse_test.py`; nasm programs there start with `cpu 8086`: without it a far conditional jump is assembled as a 386's, which an 8088 runs as `POP CS`) and `JOYTEST.COM` (the joystick as the port and the BIOS give it; `JOYTEST L` a line a change, for `tools/joy_test.py`) for the FreeDOS diskette and folder |
| `src/include/` | `layout.s` (the bank of each region and the page of each bank-`$00` area: the only place either is written), `hw.s` (soft switches, ROM, Toolbox), `mailbox.s` (the front page: file-call entry and loader mailbox), `guest.s` (guest CPU state in the direct page, `GUEST_DP`) |
| `tools/` | `gen_reloc.py` (appends each image's list of bank bytes and page bytes), `layout.py` (the layout for the host tools, `XTGS_LAYOUT`), `make_image.sh` (the ProDOS volume, named `XTGS`; a directory argument becomes a folder on it), `gsos_image.sh` (a GS/OS boot volume from a System 6 one, named `XTGS` or `GSOS_VOL`, cached in `build/gsos/`; `gsos_volname.py` renames the old volume in the pathnames the copied System folder holds, without which GS/OS waits at startup for the disk of the old name) + `check_gsos.py` (GS/OS launch test; `tests/gsos/start.s` is its launcher, `start16.s` the S16's) + `check_s16.py` (relaunch test), `build_freedos.py` (the FreeDOS floppy image and the same files as the folder `third_party/freedos/fd/SHARED`), `symbols.py` (listing -> addresses), `gen_tables.py` (font, pixel table), `judge_m0.py`, `textshr.py` (text buffer vs SHR pixels), `t160shr.py` (the same for the 160x100 mode), `cgashr.py` (B800's two fields vs SHR in modes 4/5/6; `colours`, what the registers and a Tandy's array make of the palette, worked out apart from `fg_tab`, vs the SHR's), `egashr.py` (the four planes and the palette registers vs SHR in mode 0Dh), `tandyshr.py` (the pages shown, from their slots, and the array's palette vs SHR in modes 08h, 09h and 0Ah), `psgdoc.py` (a model of the SN76496 and of the DOC's registers, written apart from `sound.s`: replays `DOC_LOG` and holds every voice, the speaker and the timer to it after each byte the guest gave the chip; `judge_com.py` runs it on every test) and `psg_test.py` (`make test-psg`: the same sounds measured in MAME's recording), `share_test.py` (the shared drive's test: builds its own FreeDOS floppy and volume), `clock_test.py` (the clock's test: MAME's IIGS clock is the host's at the start of a run), `state_test.py` (the boot state's test: its `decode` is the file's format written apart from `state.s`, its `EXPECTED` the fields a start makes anew; a new one goes there with its reason), `minix_test.py` (Minix's boot, by the cursor at each prompt), `cga_test.py` (a GW-BASIC program or a `.COM` under FreeDOS, SHR to `build/cgatest/NAME.png`; `GWBASIC=path` another interpreter, `VIDEO=CGA` or `VIDEO=TANDY` that `XTGS.CMD` line (the Tandy's mode 08h, 09h or 0Ah is then judged by `tandyshr.py`; a CGA graphics mode's registers and colours are printed and judged by `cgashr.py` on any PC), `ARGS=...` the `.COM`'s command line, `TEXT=1` prints the text screen, `CAP=1` the end of the teletype's capture; one run at a time), `check_mx.py`, `mame/` (`mamerun.run`'s `extra` is a caller's own Lua in the run: a tap, a clock in emulated time by `emu.wait`, lines back as `result["extra"]`; `jit_profile.py` is its user. MAME's `PC` for the 65816 has the bank in it) |
| `icon/` | the Finder icon of the GS/OS application: QuickDraw II icon records (`dos_32x32.qdicon.bin`, `dos_16x16.qdicon.bin`) and their generator. `tools/gsos_rfork.py` wraps them in `XTGS`'s resource fork (`build/xtgs16.rfork`: `rBundle`, `rIcon`s, `rVersion`; empty rows trimmed, `ICON_REMAP` in the Makefile) and builds the volume's `Icons/Desktop`; docs/relocation.md |
| `tests/cpu/EXCLUDE.md` | which vectors the packer drops and why; known deviations |
| `tests/bench/*.asm` | nasm benchmark programs (`-DOUTER=n`) |
| `tests/snd/psgwav.asm` | the fourteen sounds `make test-psg` records; its table is repeated in `tools/psg_test.py` (`SOUNDS`): change the two together |
| `third_party/` | `8088/` SingleStepTests vectors (fetched, git-ignored), `font8x8/` public-domain font, `minix/` the Minix 1.5 demonstration diskette and its licence (distributed with the tree; keep the image unmodified, its sha256 is in the README there) |

## Memory

Everything CORE and SVC touch is a first choice (docs/relocation.md), set in
`src/include/layout.s` and nowhere else.

Bank `$00` areas, by page: `ZP` `$1000-$10FF` guest CPU state (the direct
page, `GUEST_DP`; `$00-$7F` core, `$80-$FF` services), `MBX` `$2000` the
front page (`MB_FILECALL` at `+$04`, the mailbox from `+$10`: `MB_STAGE`
`$2010`, `MB_MAGIC` `$2012`, `MB_LAYOUT` `$2082`, and after it `MB_ARG`,
`MB_ARGN` and `MB_ARGI`, a document the GS/OS front end was opened with:
docs/finder.md), `PATH` `$0C00` pathnames,
`XFER` `$4000-$5FFF` file transfer buffer, `IOB` `$6000-$7FFF` the MLI's I/O
buffers. The loader's own, not layout: `$0800-$0BFF` core native stack
(`S=$0BFF`), `$2000-$3FFF` the loader, its load-time `IOBUF` `$0C00` and
`BOUNCE` `$4000`. `$E1:2000` SHR, written directly.

Banks: `$03` CORE, `$04` SVC, `$05` results/trace (and the PC's device
state from `src/include/pc.s`: the 6845 registers `CRTC_REG` (R12-R17 read back at 3D5h, `crtc_data`: a program finds the adapter by the cursor's address) and `CRTC_CUR`,
the 8259's `PIC_BASE`/`PIC_MASK` and the diskette's `PIC_IRQ6`, the shared
drive's `RD_STATE`/`RD_DIAG`/`RD_CALLS`/`RD_LAST`/`RD_LOG`, the EGA's
registers `EGA_SEQ`/`EGA_GC`/`EGA_AC` and its flags `EGA_ON`/`EGA_SYNC`, the
160x100 mode's shadow `T160_SHD` and the EGA's dirty bytes `EGA_DIRTY` in
its upper half, the Tandy's `TDY_ON`/`TDY_PAGE`/`TDY_SLOT`/`TDY_REG`, its
sound chip's `PSG_REG`/`PSG_LATCH`/`PSG_WRITES`, the boot state's `BS_CFG`/`BS_STAT`/`BS_BOOT`/`BS_WHERE`/`BS_SKIP` and the files the PC was started from `MF_ON`/`MF_BAD`/`MF_LEN`/`MF_TAB`, the text screen's shadow `TXT_SHADOW` (the teletype's capture `CAP_BUF` is `CAP_MAX`, 24K, below it), the DOC's registers as
written `DOC_REG`, their log `DOC_LOG`/`DOC_LOGN` and `DOC_NOSC`/`DOC_SUM`, and
`VID_DIRTY`, 128 flags: a 256 of B800-BFFF each), `$06` the JIT (four
banks: the translator, its run-time routines and code at `JIT_RT`, its
map at `JIT_MAP`, the routines again and more code at `JIT_RT2`; K's old
cache is the first; a PC claims them last but XMS and does without when
it cannot),
`$20-$2F` the guest's 1 MiB (`B800:0000` is `$2B:8000`; in mode 0Dh the
EGA's four planes are the guest's banks A, C, D and E, `H_EGA`,
`H_EGA1`-`H_EGA3`: nothing more is claimed, and the guest reads planes 1-3
at C000-EFFF; on a Tandy the pages that are not at B800 wait in banks A
and C, `H_TDYA`/`H_TDYC`, the slots of `src/include/pc.s`), `$30+` the vector
file, `$50+` the disk image (D; under S the same banks are the guest's XMS memory, claimed last and done without if they cannot be had). The loader claims each region where the
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
- The results bank is cleared by the front end at the first start
  (`zero_res`) and by nothing after it: its contents go from one PC to the
  next across a reboot (`BS_BOOT`, `BS_SKIP`, `CTL_REQ`, `PC_BEGUN`). So a
  variable there is 0 at the first PC and whatever the last PC left at a
  reboot: one that must begin anew with every PC is set in
  `svc_bootinit`. The PC's megabyte is cleared before the first PC of a
  run boots (`mem_clear`, the BIOS's segment before its stubs are built),
  not for a soft reboot and not for a start from a state. Nothing may
  count on memory being zeroes otherwise: `XTGS_GARBAGE=7` with
  `tools/state_test.py` fills the machine with leftovers first.
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
- The shared drive spells a DOS name ProDOS cannot hold another way on the
  volume (docs/share.md: a `_` is a dot, `X..` goes before a leading digit;
  `dp_prefix`/`dp_under`/`dp_close` in `files.s` while `dp_pfx` is set,
  `rd_unname` in `redir.s` back). Anything that turns a ProDOS name into a
  DOS one, or the other way, goes through those; `tools/release_image.py`'s
  `prodos_name` is the same rule for the host.
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
MAME's es5503 plays a 256-byte table 256/255 sharp (the timer too): a
measurement of its recording allows for that, a judge of the registers
does not.

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
(0, 1, COM2's 3, COM1's 4 and the diskette's 6) at vector `PIC_BASE+n` and only when bit n of
`PIC_MASK` is clear: never write `INT 08h`/`09h` into the core as a number.
It looks at the lines other than IRQ0 only while `PIC_PEND` is set (the look
clears it and sets it again for every line it finds raised, delivered or
not): whoever raises a line (`PIC_IRQ3`/`4`/`6`, `PIC_MOUSE`, a scancode
queued) sets `PIC_PEND` too, or the slot never sees it.
The BIOS's INT 09h (`F000:KB9_OFF`, `int_09` in `keyboard.s`) stores the
last key again when a guest handler before it emptied the buffer
(`kb_owed`; docs/keyboard.md): whatever takes a key out of the BDA's ring
for the guest clears `kb_owed`, as `kb_pop` and `kb_flush` do.
IRQ1 alone has an in-service state (`PIC_KBIS`): from its delivery until
the guest reads port 60h or writes an EOI to port 20h the slot brings no
other, because a handler that begins with `STI` (Sierra's keyboard driver)
would otherwise be entered again before it had taken the scancode, for
ever. The other lines are cleared as they are delivered.

The text screen is drawn from the 6845's start address (`txt_org`,
`src/svc/video.s`; `B800` goes round at 16K, mid-row) and `txt_shadow`
(`TXT_SHADOW`, in the results bank) is by place on the screen, not in
the buffer. The cursor is the BDA's unless
the guest wrote R14/R15 (`CRTC_CUR`, `cur_where`), and it is nowhere when
either puts it outside the 80 by 25 (a program's way of hiding it: a cell
drawn at row 25 lands in the SHR's line control bytes and palettes;
`tests/com/curhide.asm`). `render_cell` takes the
cell's word in A. A text-mode judge must read the buffer from the start
address (`tools/minix_test.py` does; `tools/textshr.py` takes the cells).

A source file added to `src/svc/` or `src/core/` also goes in the
Makefile's `SVC_SRCS`/`CORE_SRCS`, or edits to it do not rebuild (and the
boot state's build number, `src/svc/gen/buildid.s`, is a CRC of those two
lists: a state is refused by any build but the one that wrote it).

SVC is nearly a whole bank: the image and its relocation list are 64,306
bytes of the 65,536 (`gen_reloc.py` stops the build past that), and that only since
the text screen's shadow went to the results bank (`TXT_SHADOW`). What
needs no initial value goes in the `dum` block at the end of
`src/svc/svc.s` (`snd_pg1`, `bs_hdr`, `bs_home`, `mf_rec`): it lies past
the image, where the list was loaded, and costs the file nothing, but the
image and that block together must fit the bank too. A buffer of any size
belongs in the results bank (`src/include/pc.s` has the map; long
addressing), not in SVC.

The desk accessory's saved state and the boot state are the same seven
regions (`st_rg`, control.s): PC state that lives anywhere else needs a
line there or in the resync (`st_restore`, `svc_stload`), and after a
change to `st_save`, `st_walk` or `state.s` run `make test-control` and
`make test-state` (plain, `XTGS_LAYOUT=alt`, `XTGS_FRONT=s16`,
`XTGS_JIT=1`).

## The translator and everything else

With `JIT=ON` (docs/jit.md) guest code also runs as translated pieces, and
what the rest of the tree owes it is this:

- Translated code trusts the guest's memory only as far as it can see who
  writes it. Its own stores it looks at; the interpreter running by itself
  puts the epoch on (`jEP`, in the direct page), after which every piece
  compares its bytes before it runs. SVC code that writes the guest's
  conventional memory outside a hypercall (in the frame's work, behind a
  port) must `inc jEP`, unless what it writes is the interrupt vectors or
  the BIOS's data, which no piece is made from (`ports.s`'s diskette
  transfer does). A hypercall puts the epoch on by itself, except the ones
  `svc_hypercall` marks (`jCLN`): add a vector there only when its service
  writes nothing but registers, the BIOS's data and the stack's frame.
- The slot leaves through `slot_x`, which the translator repoints for a
  slot it asks for: a new way out of the slot goes through it too.
- An instruction the interpreter does for a piece retires into `jit_hook`
  by `vNEXT`/`vnext0`: a handler that retires any other way (as `irq_sti`
  with an interrupt owed) only loses the piece its return, which is safe.
- A restored state (control.s) empties the translator (`jsl JIT_BASE`):
  its code is of the PC that was.
- Translated code and the translator's run-time routines run with the
  data bank register their own bank (`sp_sync` at every entry from the
  core, `x_go` across to the other bank of code; `jit_ret` takes the
  core's back). There are two banks of code with the same routines at the
  same addresses: a routine reaches a piece's record or stub by its
  address alone (`rt_start+n,x`, never `>JIT_RT`), another bank's by
  `st_same`/`st_go`/`st_far`, and the translator's side by `c_get`/`c_set`
  with the piece's bank (`e_cb`, bit 0 of its word in the map). A new
  routine that takes an address in the code needs the bank with it
  (`wh_bank`). `jit_fuzz.py --small` is the test of all of it.
- A store that translated code makes is looked at by its length
  (`h_smcb`, `h_smc`, `h_smcf`; `sm_len`): a new store path names its own,
  and a new piece of the translator that marks bytes as a piece's (as the
  look ahead at a way out does: `sc_look`, runs of the record) keeps them
  inside one of the piece's three bounds (`e_lo`, `e_xlo`, `e_ylo`), never
  one pair round everything.
- `$C8`-`$DF` of the direct page are the translator's when it is on (`jG`,
  `jEP`, `jT`, `jSV`, `jCLN`, `jSPM`, `jtmp`, `jtmp2`, `jSPS`, `jSPO`,
  `jSPO2`; the JIT spike's when K runs): never both.
- A template's `JSR` to a helper that can give the instruction back
  (`h_push`, `h_pop`, `h_retf`, the pointer routines) has `LDY #IP`
  straight before it: the helper reads the IP out of the code
  (`h_bailr`). Keep the two together in a new template.
- `tools/jit_profile.py report NAME --jit` prints the translator's own
  counts over the window (why the epoch went on, pieces compared) and its
  rings (the last addresses the interpreter was given the run at, the
  last refusals, the last stores beside code): look there before guessing
  why a workload is slow with it.
- After a change to `src/jit`, `tools/gen_jit.py` or `jitc.s`: `jit_fuzz.py
  --micro`, `--micro --small` and three seeds (one of them `--small`), `XTGS_JIT=1 make test-com`, `XTGS_JIT=1 make
  test-share BOOT=1`, and the micro run under `XTGS_LAYOUT=alt`.

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
- The EGA (`src/core/ega.s`, docs/ega.md). The effective-address tails
  compare the operand's bank word with `#^H_EGA` and leave by `ea_hi` or
  `ef_vid` for A000 and above: the text bank is marked there, and in mode
  0Dh (`ega_cur`) an operand in A000 goes to `ega_trap`, which gives the
  handler a bounce byte or word for `pEA` (what `ega_rd` read through the
  graphics controller) and makes the instruction retire through
  `ega_retire`, where the bounce goes to the planes by `ega_wr`. Handlers
  know nothing of it, so a new handler with a memory operand needs its
  opcode's row in `eg_class` (`tools/gen_cpu.py`: read, write or both, byte
  or word), and a new inline EA path the same compare. The string
  instructions' opcodes point at `eg_strop` while the mode lasts
  (`ega_sync` repoints `optab`), which goes on to the ordinary handler
  unless SI or DI is in the planes. SVC raises `EGA_SYNC` when it changes
  the mode or a register, and the core calls `ega_sync` on the way back
  from a hypercall and from the frame's work (`svc_vbl`, where a mode set
  through 3D8h ends the mode): its copies (`eg_derive`) are stale until then.
  A byte's flag in `EGA_DIRTY` is by its place on a screen of 40-byte
  lines from `EGA_START`; when the 6845's offset register or the
  attribute controller's panning make the screen a window on a wider
  buffer (`EGA_WINLEN` is not `EGA_LEN`; a game's scrolling), a write
  within the window sets `VID_DIRTY`'s flag for the 256 of its place in
  the window instead (128 of them) and `eg_wide` draws the lines of the
  flagged 256s; when only the start address changed it draws the lines
  that are not the same where the screen was and where it is (`eg_lcmp`,
  `eg_from`: a game that draws off the screen and changes over). A new
  path that writes the planes marks both ways, as `eg_mark` and
  `eg_markrng` do.
  `tests/com/ega.asm` is the test; add the case with the path.
- Video memory to the core is two things: the EGA's trap above, and a
  flag in `VID_DIRTY` for the 256 bytes of B800-BFFF a store touched
  (`vid_mark`, `vid_mark_dst`, `vid_mark_rng`: 128 flags, the Tandy's 32K;
  text and the CGA's modes look at the first 64). A word across two 256s
  marks both. On a Tandy these flags are also what takes a page home from
  the window (`tdy_hv`), so a path that writes B800 and does not mark
  every 256 it touched loses the bytes, not only the picture. The Tandy's page register never
  changes what the core addresses (docs/tandy.md). Ports 3DAh-3DFh go to
  SVC in both modes of running (`port_out`, entry 36, `tdy_port`), and so
  do C0h-C7h, the Tandy's sound chip (`psg_write`); the CGA's other ports
  are the core's.
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
- No operator precedence: expressions evaluate left to right, so
  `sta tab+3*8` is `(tab+3)*8` and assembles without a word: write
  `3*8+tab`. `tools/check_long.py` refuses an address operand that adds
  before it multiplies (`files.s` had two, which stored into SVC's code).
  `*` is the current PC. `err *-1-CORE_BASE/$10000` asserts a bank-sized image.
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
