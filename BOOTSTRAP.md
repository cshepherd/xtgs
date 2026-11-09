# XT/GS bootstrap: Merlin32 + the MAME harnesses

**Status:** M0-M4 done; M5 (Mode B disk boot) substantially built (2026-11-08). `make boot-dos` boots a real FreeDOS kernel from a disk image: the boot sector runs, INT 13h serves the disk, and the kernel's root-directory read succeeds; it stops in the boot sector's find-file search (docs/mode-b.md has the diagnosis and the next step). M4 characterized the interpreter (`tools/profile.py`), added the `MVN` fast path for `REP MOVS` (23x on string moves), and published measured throughput in `docs/benchmarks.md`; lazy flags is the identified, scoped next optimization. `make test-com` runs the
nasm `.COM` programs; `make test-dos` runs independently sourced DOS
utilities (MS-DOS 2.0 and FreeDOS, fetched into `third_party/`). See
`docs/dos-api.md`, `docs/keyboard.md`, `docs/compatibility-matrix.md`. The tree follows this plan; what
was measured since is in `docs/benchmarks.md` (guest instructions a second)
and `docs/cpu-compatibility.md` (8088 behaviour the vectors forced). Section
8's numbers are the pre-measurement hypothesis and are superseded by
`docs/benchmarks.md`. Written against the tools actually installed on this
machine and the harnesses in `../somi-iigs-port/iigs`, `../fgx` and
`../combatchess_iigs`.  Companion to `apple_iigs_xt_emulator_project_plan.md`
(referred to below as "the plan").  Everything marked *measure* is a
hypothesis until M0/M1 produce a number.

## 1. Recommendations in one screen

The plan's §10 asks ten questions.  Answers, each argued below:

| # | Question | Recommendation |
|---|---|---|
| 1 | Host architecture | **ProDOS 8 direct boot**, somi-style `.SYSTEM` loader that takes the machine over (TN #27 reservations, Memory Manager fixed handles).  A GS/OS launcher is a later wrapper, as somi did it. |
| 2 | 1 MiB guest region | Ask the Memory Manager for one locked, fixed-address 1 MiB block at **`$20:0000`** (banks `$20`–`$2F`).  A 1 MiB-*aligned* base makes the 20-bit wrap one `AND`/`ORA`.  Fail loudly if refused; M0 proves it in MAME, real hardware re-proves it. |
| 3 | Toolchain | **Merlin32 1.1.10** (`/usr/local/bin/merlin32`), one link per bank, `cadius` images, `make`.  Python generates the regular parts of the CPU core as Merlin source.  fgx's `check_mx.py` runs on every listing as a build gate. |
| 4 | CPU implementation | **Hybrid.**  Generated: the 256-entry opcode table, the 256-entry ModR/M effective-address table, and the 48 regular ALU opcodes.  Hand-written: flags glue, string ops, MUL/DIV, shifts/rotates, control transfer, INT/IRET, prefixes, the hypercall. |
| 5 | Flags | **Eager, table-driven**: capture the 65816's P after the native op, translate N/Z/C/V to SF/ZF/CF/OF with a 512-byte table, PF from a 256-byte table, AF from `a^b^r`.  Lazy flags are the M4 experiment, not the M1 design. |
| 6 | DOS shim | **IVT fidelity from day one, shim breadth later.**  Interrupt vectors point into a stub BIOS segment whose entries are a reserved *hypercall* opcode.  Programs that hook and chain `INT 21h` just work, and Mode B replaces the stubs with a real DOS without touching the core. |
| 7 | Video | **Dirty-on-write.**  With the base at `$20:0000`, every write to `B800:xxxx` lands in host bank `$2B`, so the write path's "is this video?" test is one 16-bit compare.  Flush dirty 256-byte pages of the text buffer on VBL. |
| 8 | Performance gate for M5 | Decide after the M1 microbenchmarks; see §8 for the arithmetic that says a stock IIGS lands around a tenth of an XT and a 16 MHz Zip around a third to a half (*measure*). |
| 9 | Reference tests | **SingleStepTests/8088** (MIT, hardware-derived, ~10k vectors per opcode, undefined-flag masks supplied).  Reachable now.  Packed by Python, executed by a 65816 harness inside MAME, judged by Python. |
| 10 | Success definition | The plan has it right: an unmodified `.COM` runner is release one. |

The 8086 oracle is the test suite itself, not another emulator.  There is no
x86 assembler on this machine yet; `brew install nasm` is needed before M2's
`.COM` test programs can be built.

## 2. What the sibling projects hand us

Nothing below needs to be designed; it needs to be copied and trimmed.

| Source | What it is | Use in xtgs |
|---|---|---|
| `somi/iigs/tools/mame/mamerun.py` | Headless MAME runner: boots a `.po`, Lua `-autoboot_script` polls a u16 at an address until it equals a value, dumps memory ranges, the text screen and the 65816 registers as JSON.  Also: input injection, `poke`, `save`/`load_state`, PC sampling profiler, read/write taps on address ranges, a ZipGS 16 MHz config switch (`zip=True`). | Copy as-is.  It is the whole test transport.  The tap and profile features are M4's profiler for free. |
| `somi/iigs/tests/common/check_probe.py` | Judge pattern: a probe program fills `PREFIX_val[]`, `PREFIX_stage`, `PREFIX_magic`; Python reads them through mamerun, prints per-case ok/FAIL/"CRASHED HERE?". | The shape of every xtgs test judge. |
| `somi/iigs/tools/mame/shr.py` | Renders a dumped SHR buffer to PNG. | Screenshots of the 80×25 frame in CI.  It renders 320-mode only; needs a 640-mode branch (small). |
| `somi/iigs/tools/mame/{run-mame.sh,mame-lua,claudebridge/}` | Interactive MAME with a Lua command bridge over `/tmp` files. | Copy.  Poke guest registers, single-step the loop, read `B800` live. |
| `somi/iigs/asm/loader.s` lines 486–560, 793–849, 1008–1040, 1096–1160 | `tools_up` (TLStartUp, MTStartUp, GetNewID, TN #27 reservations), `mm_startup`, `new_handle`, `mli_glue` (native→emulation MLI trampoline with stack switch). | Lift into `XTGS.SYSTEM`.  This is the proven way to own memory under a direct ProDOS 8 boot on a IIGS. |
| `somi/iigs/tools/{make_image.sh,cadius_strict.sh}`, `res/PRODOS` | 32 MB ProDOS volume builder; cadius wrapper that turns its silent "Error :" lines into exit codes. | Copy.  Volume holds `XTGS.SYSTEM`, `CORE`, `SVC`, test vectors, `.COM` files. |
| `fgx/tools/check_mx.py` | Parses `merlin32 -V` listings; flags every branch whose source M-width disagrees with the target's deduced width, plus two local shapes (MX contradicting a just-executed SEP/REP, 8-bit load feeding TAX/TAY/TCD/TCS). | Build gate from the first commit.  An 8086 interpreter flips M between byte and word ops constantly; this is the exact bug class Merlin32's linear MX tracking produces. |
| `fgx/build.ninja` rules `kernel`, `kernelfar` | The merlin32 invocation discipline: clear stale `error_output.txt` first, capture the exit status, always move the listing into `build/`, print the log on failure, publish the binary only on success. | Reproduce in the Makefile.  fgx lost an afternoon to a `; true` that hid assembly failures. |
| `fgx/src/kernel/link/core/fgx.link.s` | Merlin32 link file: `TYP $06 / DSK name / ORG $xxxxxx / ASM file / SNA segname`. | One link per xtgs bank. |
| `combatchess/CLAUDE.md` "Assembly conventions", "Clock under ProDOS 8" | Merlin32 rules of thumb; the VBL/heartbeat finding. | Seed for xtgs's `CLAUDE.md` (§6.4). |

Installed and verified today: `merlin32` 1.1.10, `cadius` 1.4.2, Homebrew
`mame` 0.284 and Ample's `mame64`, Ample's ROM set
(`~/Library/Application Support/Ample/roms/apple2gs.zip`), Python 3.14,
`ninja` (not needed), `claudebridge` and `fgxdebug` already in Ample's
`plugins/`.  Not installed: `nasm`, any DOS emulator, py65816.

## 3. Where the plan needs correcting or sharpening

**Word wrap (plan §4.1).**  "Word accesses at `FFFFFh` must wrap to physical
zero" is true but is the rare sub-case of the rule that matters: on an
8086/8088 the *offset* wraps at 16 bits within the segment.  A word read at
`DS:FFFF` fetches `DS:FFFF` and `DS:0000`, not the next linear byte; `PUSH`
with `SP=1` writes to `SS:FFFF` and `SS:0000`.  One test, `offset == $FFFF`,
routes a word access to a two-byte slow path and covers the `FFFFFh` case as
well.  Instruction fetch wraps `IP` at 16 bits too, which the 65816 gives us
free if `IP` lives in a 16-bit `Y` (§5.2).

**65816 flags (plan §4.2).**  "Do not equate 65816 flags with guest FLAGS" is
right as a rule and wrong as a plan: for `ADD/ADC`, the 65816's N, Z, C and V
after `ADC` *are* SF, ZF, CF and OF, in 8-bit mode for byte ops and 16-bit
mode for word ops; for `SUB/SBB/CMP`, the same with CF = NOT C.  Only PF and
AF need computing.  That is why eager flags can be cheap (§5.5).

**Hosting (plan §3).**  The plan prefers a GS/OS-hosted launcher.  Both
sibling projects boot ProDOS 8 directly, and their headless harnesses depend on
it: a `.po` boots into the `.SYSTEM` in roughly 20 s of emulated time at
`-nothrottle`; a GS/OS boot is 60 s or more and needs Finder scripting.  ProDOS
8 also gives the DOS shim a filesystem whose names (15 chars, letters, digits,
periods, uppercase) map onto 8.3 trivially.  Its one real cost, that MLI data
buffers must sit in bank `$00`, is a bounce buffer somi already wrote.  Do M0
through M4 under ProDOS 8; wrap a GS/OS S16 launcher around it later.

**Mode A versus Mode B (plan §4.4).**  The plan worries about mixing the
shim's `INT 21h` dispatch with a real DOS kernel.  The hypercall design (§5.6)
dissolves the worry: the core never special-cases `INT nn`.  It executes the
guest's interrupt sequence exactly, and the *stub BIOS* at `F000:xxxx` is
where host services are entered.  Mode A fills the IVT with stubs for `20h`,
`21h`, `10h`, `16h`, `1Ah`; Mode B leaves the BIOS stubs and lets the loaded
DOS install its own `21h`.

**The 8 MB figure.**  MAME's `apple2gs` takes `-ramsize 8M`, giving banks
`$00`–`$7F` plus `$E0`/`$E1`.  Banks `$E0`/`$E1` are 1 MHz and hold I/O and
the SHR screen; bank `$01` shadows; a storage card may claim a bank through
the Memory Manager at boot (somi met the MicroDrive's buffer in `$02`).  So the
usable pool is `$02`–`$7F` minus whatever the firmware or cards took, which is
exactly what the M0 probe reports.

**Stub BIOS, not "ROM stubs or mapped backing store" (plan §4.1 table).**  The
`F0000h`–`FFFFFh` region is ordinary guest RAM that the loader fills with the
hypercall stubs, the BIOS data area is at `0040:0000` in ordinary RAM, and the
IVT at `0000:0000`.  Nothing in the address map is special except the text
buffer, and that only on the write path.

**SHR stores are slow.**  Writes to bank `$E1` run at 1 MHz.  A full 80×25
redraw is 2,000 cells × 16 bytes = 32,000 slow stores, about 50 ms with the
font expansion.  Dirty tracking is therefore not an optimisation to defer; a
program that repaints the whole screen per line of output is capped near 20
frames a second even on an accelerator.

## 4. Host memory layout

Fixed addresses, all verified by the M0 probe and guarded by `ERR` lines in the
sources.

| Host range | Owner | Notes |
|---|---|---|
| `$00:0000–00FF` | ProDOS 8 / firmware zero page | Untouched.  Core runs with `D=$1000`. |
| `$00:0100–01FF` | 6502 stack for the loader and MLI calls | IRQs scribble here (combatchess/somi finding); nothing of ours survives on it. |
| `$00:0800–0BFF` | Core native stack | `S=$0BFF`.  Switched to page 1 by `mli_glue` around each MLI call. |
| `$00:0C00–0FFF` | ProDOS 8 I/O buffer | File opens for `CORE`, `SVC`, vectors, `.COM`. |
| `$00:1000–10FF` | **Guest CPU state, direct page** | Layout in §5.1. |
| `$00:1100–11FF` | Host globals, mailbox for the test judge | `stage`, `magic`, error words, instruction counters. |
| `$00:1200–1213` | Heartbeat task record | If the Misc Tools tick is used (combatchess: VBL interrupts stay enabled only while a heartbeat task is registered). |
| `$00:2000–3FFF` | `XTGS.SYSTEM`, resident | Loader, TN #27 code, `mli_glue`, mailbox ABI. |
| `$00:4000–5FFF` | MLI bounce buffer | 8 KB.  Guest file I/O copies through here. |
| `$00:6000–BEFF` | Free | Reserved with the rest of `$0800–$BEFF` (TN #27). |
| `$03:0000–FFFF` | **`CORE`**: dispatch loop, opcode and ModR/M tables, all instruction handlers, flag tables, parity table | One Merlin32 link.  `JMP (abs,X)` dispatch requires handlers in bank K. |
| `$04:0000–FFFF` | **`SVC`**: stub-BIOS/DOS hypercall handlers, text renderer, font, keyboard translation, timer | Second link.  Entered by `JSL` through a fixed vector table at `$04:0000`. |
| `$05:0000–FFFF` | Trace ring buffer | Optional, on when tracing (§7.5). |
| `$20:0000–$2F:FFFF` | **Guest physical memory, 1 MiB** | `physical = host − $200000`.  `B8000h` is `$2B:8000`; the IVT is `$20:0000`; the stub BIOS `$2F:0000`. |
| `$30:0000–$7F:FFFF` | Free | Test vectors (M1) are loaded here. |
| `$E1:2000–9FFF` | SHR frame buffer, 640 mode | Written directly; QuickDraw is not started. |

Why bank `$03` for the core and not `$02`: a card may own `$02` at boot.  Both
banks are requested as fixed-address Memory Manager blocks; a refusal is a
loud loader error, not a silent relocation.

## 5. CPU core design

### 5.1 Guest state in the direct page (`D=$1000`)

Registers sit in the 8086's own encoding order so ModR/M fields index them.

```
$00 AX   $02 CX   $04 DX   $06 BX   $08 SP   $0A BP   $0C SI   $0E DI
     (AL=$00 AH=$01 CL=$02 CH=$03 DL=$04 DH=$05 BL=$06 BH=$07)
$10 ES   $12 CS   $14 SS   $16 DS            ; sreg encoding ES=0 CS=1 SS=2 DS=3
$18 IP (spilled copy; Y holds it while the loop runs)
$1A FLAGS
$1C ES_base  $20 CS_base  $24 SS_base  $28 DS_base   ; 4 bytes each: 24-bit host
                                                      ; pointer = $200000 + (seg<<4),
                                                      ; wrapped to 20 bits, byte 3 = 0
$2C EA        ; 16-bit offset from the ModR/M routine
$2E EA_ptr    ; 24-bit host pointer for the current memory operand (+pad)
$32 modrm     $33 opcode
$34 seg_ovr   ; 0, or the DP offset of the override's base ($1C/$20/$24/$28)
$35 rep       ; 0, $F2, $F3
$36 ea_seg    ; DP offset of the default base for this EA (SS for BP forms)
$38 reg_off   ; DP offset of the ModR/M reg operand
$3A rm_off    ; DP offset of the rm operand when mod=3
$3C tmp0 … $42 tmp3
$44 int_pending  $45 halted  $46 slot_countdown (16)
$48 icount (32)  ; instructions executed, for the benchmarks
```

Writing a segment register (any path: `MOV`, `POP`, far `JMP/CALL/RET/IRET`,
`LDS/LES`) also recomputes its `_base`.  Four shifts and a mask, paid only on
segment loads, so that every memory access pays none.

### 5.2 Register allocation in the loop

**Y is IP.**  The 16-bit `Y` holds the guest `IP` throughout fetch and decode.
`LDA [CS_base],Y` fetches at `CS:IP`; `INY` advances and wraps at 16 bits
exactly as the 8086 does.  Handlers that need a second index spill it with
`STY $18` and reload before returning to `fetch`.  **X** is the dispatch and
register index.  **A** is data.  `DBR=$03` so tables are `LDA abs,X`.
Decimal mode stays off; the firmware IRQ handlers assume it.

### 5.3 Fetch and dispatch

```
fetch     LDA  [CS_base],Y     ; 16-bit load; low byte is the opcode (7)
          INY                  ; IP++ (2)
          AND  #$00FF          ; (3)
          ASL                  ; (2)
          TAX                  ; (2)
          JMP  (optab,X)       ; (6)
```

About 22 cycles before the handler runs.  The 16-bit load reads one byte past
the opcode; harmless, and the following immediate or ModR/M byte is usually
what it is.  A 16-bit immediate is `LDA [CS_base],Y / INY / INY`.

Prefix opcodes (`26 2E 36 3E F0 F2 F3`) set their DP byte and `JMP fetch`.
Every other handler ends by clearing `seg_ovr` and `rep` and jumping to the
*slot check*, which decrements `slot_countdown` and, every 64 instructions,
polls `$C019` for a VBL edge, `$C000` for a key, and `int_pending`.  That is
where the timer tick, keyboard buffer, video flush and (Mode B) guest `INT 08h`
are driven from.

### 5.4 ModR/M and effective addresses

The ModR/M byte indexes a second 256-entry `JMP (eatab,X)` table of *generated*
routines, one per byte value.  A routine for `mod≠3` computes the offset into
`EA` from the registers and displacement, sets `ea_seg` (SS for the `BP`
forms, DS otherwise, overridden by `seg_ovr`), and forms the host pointer:

```
          CLC
          LDA  EA
          ADC  seg_base          ; (seg_base = the chosen *_base, via ea_seg)
          STA  EA_ptr
          LDA  seg_base+2        ; $00bb
          ADC  #0
          AND  #$000F
          ORA  #$0020            ; 20-bit wrap: banks $20–$2F only
          STA  EA_ptr+2
```

Because `$200000` is 1 MiB-aligned, the wrap is that `AND/ORA` and nothing
else.  A routine for `mod=3` stores the rm register's DP offset in `rm_off`.
Every routine stores the reg field's DP offset (word or byte table, by the
opcode's `w` bit) in `reg_off`.  Byte registers need the `{0,2,4,6,1,3,5,7}`
mapping; a 256-entry table indexed by the ModR/M byte supplies it directly.

Memory operands are then `LDA [EA_ptr]` / `STA [EA_ptr]`, in M=1 for byte ops
and M=0 for word ops.  Word ops test `EA == $FFFF` first and take a two-byte
path when it holds (§3).  Stack accesses use `SS_base` with `SP` the same way.

### 5.5 Flags

After the native `ADC`/`SBC`/`AND`/`ORA`/`EOR`:

```
          PHP                    ; capture N V Z C
          STA  result            ; (16-bit or 8-bit by M)
          PLA
          AND  #$00C3            ; keep N V Z C
          TAX
          LDA  p2flags,X         ; 512-byte table: SF ZF CF OF in 8086 positions
          ORA  parity,X'         ; 256-byte table on the result's low byte: PF
          ORA  af_bit            ; AF = ((a ^ b ^ result) & $10)
          ORA  FLAGS masked to TF IF DF (and CF for INC/DEC)
          STA  FLAGS
```

Two variants of `p2flags`: one for add-type (CF = C) and one for sub-type
(CF = NOT C).  Logic ops skip AF and force CF=OF=0.  Around 30 cycles, a third
of a typical instruction.  Lazy evaluation (record op, operands and result;
compute when `Jcc`, `PUSHF`, `LAHF`, `SAHF`, `ADC/SBB/RCL/RCR` or an `INT`
reads them) is the obvious M4 experiment and the harness of §7.2 is what makes
it safe to try.

Shifts and rotates, `MUL/IMUL/DIV/IDIV`, `DAA/DAS/AAA/AAS/AAM/AAD`, `INC/DEC`
(CF preserved; OF from the result), and `NEG` are hand-written with their own
flag code.  Undefined flags follow whatever is cheapest; the test suite's
per-opcode masks say which bits are compared.

### 5.6 Interrupts and the hypercall

`INT n`, `INT3`, `INTO`, divide error and (later) hardware interrupts all run
the real 8086 sequence: push FLAGS, CS, IP; clear IF and TF; load CS:IP from
`0000:n*4`.  `IRET` pops them.  No vector is special to the core.

The loader fills the IVT so each serviced vector points at a stub in the BIOS
segment:

```
F000:xxxx   FE 38 lo hi      ; hypercall `lo hi` (8086: FE /7, undefined)
            CF               ; IRET
```

`FE /7` is undefined on the 8086 and unused by software (its real-hardware
behaviour is a known quirk, so the suite's vectors for `FE` are run with that
encoding excluded).  The core's `FE` handler, on `reg=7`, reads the 16-bit
number and `JSL`s the service vector table in `SVC`.  Handlers read and write
guest registers in the direct page and return.  This is the DOSBox callback
model; it costs the core one branch in one rarely used handler and buys
complete IVT fidelity.

Mode A services: `INT 20h`, `21h` (the plan's P0/P1 list), `10h`, `16h`,
`1Ah`, `11h`, `12h`.  The BIOS data area at `0040:0000` is kept honest
(equipment word, memory size 640, keyboard head/tail and buffer, video mode 3,
80 columns, cursor positions, tick count at `0040:006C`, rows−1 at
`0040:0084`) because real programs read it directly.

### 5.7 String operations

`REP MOVSB/MOVSW` with `DF=0` and both ranges inside one host bank and not
wrapping their 16-bit offsets take a **`MVN` fast path**: 7 cycles a byte
against a hundred or more for an interpreted iteration.  `REP STOSW` takes a
tight `STA [ptr],Y` loop.  Everything else, and every edge case, runs the
generic per-element loop, which checks `int_pending` each iteration so Mode B
interrupt delivery during a long `REP` stays correct.  The fast paths are the
single biggest lever on screen scrolling and memory copies and should exist
from M1, verified by the same vectors as the slow path.

### 5.8 Generated sources

`tools/gen_cpu.py` emits, into `src/core/gen/`:

- `optab.s`: 256 `DA handler` entries.
- `eatab.s` and `ea_routines.s`: the 256 ModR/M routines of §5.4.
- `alu.s`: the 48 regular ALU opcodes (`00`–`3F` minus the segment/BCD slots)
  plus the `80`–`83` group, each in byte and word form and reg/mem direction,
  as instances of a few macros.
- `regtab.s`: the reg-field → DP-offset tables.

Generated files are committed so a listing diff is reviewable, and regenerated
by a Makefile rule when the generator changes.  Both sibling projects already
generate Merlin source from Python (`gen_boards.py`, `gen_title_art.py`,
`gen_syscall_table.py`), so this is house style.

## 6. Build

### 6.1 Tree

```
xtgs/
  Makefile
  CLAUDE.md                     Merlin32 and harness rules (§6.4)
  src/sys/xtgs.s                XTGS.SYSTEM: loader, TN #27, mli_glue, mailbox
  src/core/core.link.s          ORG $030000; ASM main.s
  src/core/{main,fetch,modrm,flags,string,muldiv,shift,ctrl,int}.s
  src/core/gen/*.s              generated (§5.8)
  src/svc/svc.link.s            ORG $040000
  src/svc/{vectors,bios,dos,video,font,keyboard,timer}.s
  src/include/{guest.s,hw.s,mailbox.s}   EQUs shared by all links
  tests/cpu/harness.s           the vector runner (§7.2), a build variant of CORE
  tests/com/*.asm               nasm sources for .COM test programs
  tests/expected/*.txt          expected 80×25 text or stdout per .COM
  tools/gen_cpu.py  tools/vectors.py  tools/judge_cpu.py  tools/judge_com.py
  tools/mame/{mamerun.py,shr.py,run-mame.sh,mame-lua,install-plugin.sh,claudebridge/}
  tools/{check_mx.py,cadius_strict.sh,make_image.sh}
  res/PRODOS                    ProDOS 8 (from somi/res)
  assets/font8x8.bin            a licensed 8×8 CP437 font (not IBM's ROM font)
  build/
```

### 6.2 Merlin32 invocation

One rule shape, from fgx's hard-won version:

```make
build/core: src/core/core.link.s $(CORE_SRCS) $(CORE_GEN)
	@mkdir -p build
	@rm -f src/core/error_output.txt src/core/_FileInformation.txt
	@rc=0; (cd src/core && merlin32 -V core.link.s) > build/core.log 2>&1 || rc=$$?; \
	 [ -f src/core/_Output.txt ] && mv src/core/_Output.txt build/core.lst; \
	 [ -f src/core/error_output.txt ] && mv src/core/error_output.txt build/core.err; \
	 if [ $$rc -ne 0 ]; then cat build/core.log; exit $$rc; fi; \
	 mv src/core/core $@
	python3 -I tools/check_mx.py build/core.lst
```

Merlin32 has no dependency output, so `CORE_SRCS` lists every `PUT` file
explicitly (fgx computes the closure at generation time; a `grep -h '^ *PUT'`
in the Makefile is enough here).  `ERR` lines guard every fixed layout
assumption (`ERR *-start-$FFFF` style, verified today to fail the build with
exit 1).

### 6.3 Images and targets

```
make                 build/xtgs.po   XTGS.SYSTEM + CORE + SVC (+ a .COM)
make test-m0         bank probe + 80×25 test frame (§7.1)
make test-cpu OP=01  SingleStepTests vectors for one opcode, or all (§7.2)
make test-com        every tests/com/*.asm, judged against tests/expected (§7.3)
make bench           guest IPS at 2.8 MHz and 16 MHz Zip (§7.4)
make run             Ample MAME + claudebridge, interactive
make debug           MAME -debug on the image
make test            test-m0 test-cpu test-com
```

Images are built by `make_image.sh` (cadius through `cadius_strict.sh`);
file types `XTGS.SYSTEM#FF2000`, `CORE#060000`, `SVC#060000`,
`VEC#060000`, `HELLO.COM#060000`.

### 6.4 Merlin32 rules for `CLAUDE.md`

Collected from the three repos and today's probe.

- MX is tracked linearly and does not follow `XCE` or branches.  Put an
  explicit `MX` at the top of every routine and at every label reached with a
  different width.  `tools/check_mx.py` on every listing is a build gate.
- `@label` and `:label` are both local to the enclosing global label (verified
  with 1.1.10); pick `@` to match fgx and `check_mx.py`'s parser.
- No operator precedence: `$E19E00+SLOT*2` is `($E19E00+SLOT)*2`.  `*` in an
  expression is the current PC.
- `PUT` refuses two-letter filenames.
- `-V` writes `<name>_Output.txt` beside the source, `error_output.txt` only on
  failure; a successful build leaves a *stale* `error_output.txt` from the last
  failure unless it is removed first.  The exit status is reliable; capture it.
- `ERR expr` fails the build when `expr` is non-zero.
- `BIT $C019` and other soft-switch tests need 8-bit A.
- Branches reach ±128 bytes; beyond that invert and `JMP`.
- `JMP (abs,X)` indexes in bank K: dispatch tables live in the core bank.
- `TAX/TAY/TCD/TCS` move all 16 bits of C regardless of M; an 8-bit `LDA`
  before them leaves B stale (`check_mx.py` flags this).
- Link files: `TYP $06 / DSK name / ORG $bb0000 / ASM file / SNA name`.  One
  image per link; cross-link symbols go through fixed vector tables at bank
  offset 0, never through shared addresses.

## 7. Test harness

### 7.1 M0: the probe

`XTGS.SYSTEM` built with `PROBE=1`: `tools_up`, request `$03`, `$04` and
`$20:0000`×1 MiB as fixed Memory Manager blocks; write a distinct byte to
every 4 KB of the guest region and at every bank boundary (`$2x:FFFF`,
`$2x+1:0000`), read it all back, count mismatches; switch on SHR 640 mode and
render the full glyph set plus an attribute test into the frame buffer; fill
the mailbox at `$1100`: `stage`, `mm_error`, `banks_got`, `mismatches`,
`magic=$5A5A`.

```
mamerun.py --image build/m0.po --wait 0x00110E=0x5A5A \
           --dump mb:0x001100:16 --dump shr:0xE12000:0x8000
```

Judge: `mm_error==0`, `mismatches==0`; `shr.py` (with a 640-mode branch)
writes the PNG for the eye and a golden hash for CI.  That is the plan's M0
exit criterion, mechanised.

### 7.2 M1: the CPU vector harness

`tools/vectors.py` reads `SingleStepTests/8088/v2/<op>.json.gz` and
`8088.json` (the per-opcode undefined-flag masks) and packs vectors:

```
u8  nbytes, u8 bytes[nbytes]          ; the instruction (also present in ram[])
u16 regs[14]                          ; AX CX DX BX SP BP SI DI ES CS SS DS IP FLAGS
u16 nram,  {u24 phys, u8 val}[nram]   ; initial memory
u16 xregs[14]                         ; expected
u16 nxram, {u24 phys, u8 val}[nxram]  ; expected memory
u16 flags_mask
```

`tests/cpu/harness.s` (the core bank built with `HARNESS=1`) walks the
packed block at `$30:0000+`: writes initial RAM into guest memory, loads the
DP registers and recomputes the four bases, runs the loop until one whole
instruction (prefixes and `REP` iterations included) has retired, compares
registers with `FLAGS & mask`, compares expected RAM, sets a bit in a pass
bitmap, and on the first failure copies the actual state beside the expected
one in the mailbox.  Then `magic`.  `tools/judge_cpu.py` reads the bitmap and
the first-failure record through `mamerun.py` and prints the vector index,
the register or address that differed, and the instruction bytes.

Throughput: a few thousand host cycles per vector at `-nothrottle` means a
whole opcode's vectors in well under the 20 s boot (*measure*).  Two ways to
make the loop fast: save a MAME state once the harness is waiting for a
command word (`mamerun.py` `save`/`load_state`) and poke each opcode's block
into `$30:0000+` from Lua instead of rebuilding the image.  Start with the
image route because every piece exists today; add the state route when the
turnaround hurts.

Known exclusions, documented in `tests/cpu/EXCLUDE.md` rather than silently
skipped: `FE /7` (our hypercall), `F4` (`HLT`), `9C/9D` bits 12–15 of FLAGS
(the 8086 reads them as set), `0F` (`POP CS`) if we choose not to support it,
`D4/D5` with non-10 immediates if the test corpus has them.

### 7.3 M2: `.COM` tests

`nasm -f bin tests/com/hello.asm -o build/HELLO.COM`.  The image carries the
`.COM`; the shim picks a program segment, builds the PSP at its offset 0,
loads the file at offset `0100h`,
sets `SP=FFFEh` with a zero word pushed, and jumps.  The judge dumps
`$2B:8000` (4,000 bytes, char/attribute pairs) and decodes it to 25 lines of
text, compares with `tests/expected/hello.txt`, and reads the exit code from
the mailbox.  `INT 21h/09h` and `02h` output is also appended to a
host-side capture buffer in `SVC`'s bank so the judge can compare exact byte
streams independent of the renderer.

### 7.4 M4: benchmarks

Three `.COM`s assembled by nasm: a register-only loop, a memory-operand loop,
and a `REP MOVSW` of 32 KB; each runs for a fixed count and exits.  The core
counts retired instructions in `icount` and VBL edges in the slot check;
Python divides.  `mamerun.py zip=True` switches MAME to the 16 MHz ZipGS
configuration, so both columns of the plan's performance table come from the
same run script.  `mamerun.py`'s PC-sampling profiler and read/write taps
give the hot-handler histogram for free.

### 7.5 Diagnostics

Trace ring in bank `$05`: 16 bytes per retired instruction (`CS`, `IP`,
opcode, `AX`, `BX`, `CX`, `DX`, `FLAGS`), 4,096 entries, on when a mailbox
byte is set.  Dumped with `--dump`, decoded by Python.  For the interactive
loop: `make run` with `claudebridge`, then `mame-lua` to read `$1000`–`$10FF`
as the guest registers, poke a breakpoint word, or `manager.machine:save`.
`make debug` gives MAME's own debugger on the 65816 with `build/core.lst`
as the symbol source.

## 8. Performance hypothesis (*measure* in M1)

Cycle estimates from §5 for an eager-flags interpreter: fetch and dispatch
22, ModR/M and pointer formation 35–60 when a memory operand is present,
operation 15–30, flags 30, slot check 7.

| Instruction class | Est. 65816 cycles |
|---|---|
| ALU reg,reg | 110–130 |
| ALU reg,mem | 190–230 |
| Jcc | 50–60 |
| MOV reg,imm | 50 |
| REP MOVSW fast path | 7 per byte |

| Host | Guest IPS at ~130 cycles | Fraction of a 4.77 MHz 8088 (~0.3 MIPS) |
|---|---|---|
| Stock 2.8 MHz | ~20,000 | ~1/15 |
| 7 MHz TransWarp | ~50,000 | ~1/6 |
| 16 MHz ZipGS | ~120,000 | ~1/3 |

A DOS kernel boots through a few million instructions, so Mode B on a stock
machine is a minute of waiting and on a Zip under ten seconds; that number,
not an aesthetic judgement, is the M5 gate the plan asks for.

## 9. Order of work for M0 and M1

1. Copy the harness files of §2 into `tools/`; `brew install nasm`.
2. `XTGS.SYSTEM` from somi's loader sections: banner, `tools_up`, fixed
   blocks for `$03`, `$04`, `$20`–`$2F`, mailbox, load `CORE`/`SVC` through
   the bounce buffer, `JSL` entry, `mli_glue`, clean shutdown and `QUIT`.
3. M0 probe (§7.1) and `shr.py` 640-mode rendering.  **M0 exit.**
4. `gen_cpu.py`: tables first, then the ModR/M routines, then the ALU family.
5. Core loop, prefixes, flags glue, `MOV` family, `PUSH/POP`, `INC/DEC`,
   `Jcc/JMP/CALL/RET`, `HLT` as "stop and raise magic".
6. `vectors.py`, `harness.s`, `judge_cpu.py`; run opcodes `00`–`3F` and
   `88`–`8F`, fix until green.
7. Shifts, rotates, `MUL/DIV`, BCD, string ops with the `MVN` path, `INT/IRET`,
   `XLAT`, `LEA/LDS/LES`, flag instructions; run the whole suite.  **M1 exit.**
8. Benchmarks (§7.4), both clocks.  Write `docs/benchmarks.md` with the real
   numbers and retire §8 of this file.

## 10. Open items

- **Real hardware:** whether `$20:0000`–`$2F:FFFF` and `$03`/`$04` are free on
  the target 8 MB machine with its actual cards.  The probe reports it; MAME
  cannot answer it.
- **Font licence:** IBM's ROM font is not redistributable.  Candidates: a
  public-domain CP437 8×8, or the Ultimate Oldschool PC Font Pack (CC BY-SA
  4.0, attribution in `assets/`).
- **Keyboard map:** IIGS left arrow is `$08`, the same byte as PC Backspace;
  the IIGS Delete key (`$7F`) must become PC Backspace (`0E08h`) and `$08` the
  Left arrow (`4B00h`).  Function keys need a modifier chord.  Write the table
  in `docs/keyboard.md` before `INT 16h`.
- **Y=IP spill discipline:** generated handlers must declare whether they
  clobber Y; the generator enforces it, hand-written ones are reviewed.
- **Mode B oracle:** FreeDOS has 8086-compatible kernel builds under GPL; pick
  the version when M5 starts, not before.
