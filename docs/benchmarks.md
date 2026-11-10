# Benchmarks

Measured, not estimated. `make bench` (`tools/bench.py`) assembles
`tests/bench/*.asm` with nasm, boots each as the loader's B command, and
times it by MAME's emulated frame count between the core's start and done
marks, so no guest timer is involved and host speed does not matter. The
instruction count is the program's own. `tools/profile.py` attributes
MAME's PB:PC samples to core routines.

## Characterization (M4, 2026-11-08)

Where the cycles go, from `tools/profile.py` over each benchmark:

| bench | dominant cost | share |
|---|---|---|
| reg (register ALU) | flag computation (`flg_incdec16` + `flg_sub16_r` + `flg_add16`) | ~35% |
| reg | fetch/dispatch (`fetch` + `next`) | ~20% |
| mem (memory operands) | effective-address (`ea_seg_w` + `modrm_w` + `ea_ds_w`) | ~35% |
| mem | flag computation | ~18% |
| str (REP MOVSW) | per-word pointer recomputation (now replaced by MVN) | nearly all |

Two conclusions drove the M4 tuning:

1. **String moves** recomputed both host pointers every word. A single
   65816 `MVN` block move replaces the whole loop when `REP MOVSB`/`MOVSW`
   runs forward and the copy stays inside one source bank and one
   destination bank. Implemented in `src/core/ops_str.s`; `MOVS` sets no
   flags, so only SI/DI/CX change.
2. **Eager flags** are the biggest compute cost. For add/sub/inc-dec the
   65816's own N/V/Z/C after the native op already carry the 8086 SF/OF/ZF/CF,
   so the eager path (capture P, translate through a 512-byte table, parity
   table, AF) is close to minimal per call. The remaining win is **lazy
   flags** (compute a flag only when a `Jcc`/`PUSHF`/`ADC`/… reads it); on
   the register loop, three flag-setting ops share one branch, so lazy
   evaluation would save roughly two-thirds of the ~35% flag cost. (Done
   on 2026-11-10, the second of the four changes below.)

## Four changes to the interpreter (2026-11-10)

Each was measured on its own, stock clock, with the whole SingleStepTests
sweep run after the second and the fourth (2,883,807 vectors; the 173 that
fail are `IN` from the ports the core serves in Mode B, as before:
`tests/cpu/EXCLUDE.md`).

| | reg IPS | mem IPS | jmp IPS |
|---|---:|---:|---:|
| before | 15,080 | 14,780 | 22,023 |
| 1. the retire path | 16,223 | 15,926 | 24,370 |
| 2. lazy flags | 21,800 | 18,272 | 32,244 |
| 3. register forms dispatched on the ModR/M byte | 26,490 | 16,722 | 32,231 |
| 4. the effective address | 26,501 | 21,353 | 32,244 |
| all four | +76% | +44% | +46% |

1. **The retire path.** `next` cleared the prefix state and tested for the
   trace after every instruction before it counted it. It is now `dec vSLOT
   / bne fetch`: a prefix handler points the retire vector at `next_pfx`,
   so only an instruction that had a prefix pays for clearing one, and a
   traced run has a vector of its own (`next_trace`).
2. **Lazy flags** (`src/core/flags.s`). An arithmetic instruction stores
   the 65816's P, its result and its operands (`vLP`, `vLRES`, `vFS`,
   `vFD`) and builds nothing. `Jcc` tests `vLP`; `flags_get` assembles the
   FLAGS word for `PUSHF`, an interrupt, `LAHF` and the test harness.
3. **Register forms.** The ALU opcodes, `TEST`, `MOV` and the immediate
   groups 80-83 fetch the ModR/M byte themselves and, for a register
   operand, jump through a 64-entry table of their own to a routine with
   the operands as direct-page addresses (`MOV` has one for each pair of
   registers). The memory forms were slower for a while, through an
   interim tail; step 4 is what the row above lacks.
4. **The effective address.** 48 routines (`emb_xx`, `emw_xx` in
   `gen/eatab.s`), one for each addressing mode and operand size, with the
   default segment's base a direct operand and the segment override one
   `bit vOVR`. The bank word of a host pointer is worked out only when the
   offset's add carries. `PUSH` and `POP` of a register are inline.

CORE grew from 23 KB to 47 KB of its bank.

What it does for a whole system, emulated seconds from power-on at the stock
clock: FreeDOS from the folder to FreeCOM's date prompt 114.5 -> 90.3; from
the floppy image 172 -> 138; Minix to its shell 493 -> 303 (16 MHz: 50 ->
39). A boot gains less than the loops do because less of it is arithmetic.
PC samples of the FreeDOS boot from the folder, one a frame, after the four
changes:

| where | share |
|---|---:|
| `fetch`, `next` and the slot | 18% |
| string instructions an element at a time (`str_src`, `str_dst`, `movsb`, `adv_si`...) and the `MVN` path | 19% |
| bank `$00` and the ROM: firmware and ProDOS (file reads, interrupts) | 12% |
| `push16`/`pop16` (calls, returns, `PUSH` of a segment or memory) | 5% |
| SVC (the text screen, mostly) | 5% |
| everything else, no routine over 3% | 41% |

So the next candidates are the string instructions without `REP` or outside
the `MVN` case, which work out both host pointers for every element, and the
count in `next`.

## Throughput

MAME 0.284 `apple2gs` (ROM 03), 8 MB, stock 2.8 MHz and the ZipGS 16 MHz
setting. OUTER=4 (65,536 iterations a loop).

| program | what an iteration is | instructions | stock IPS | Zip 16 MHz IPS |
|---|---|---:|---:|---:|
| reg | `add ax,bx / sub bx,1 / dec cx / jnz` | 1,048,576 | 26,500 | 148,000 |
| mem | `add [bx],ax / mov ax,[si+2] / mov [bx+4],ax / dec cx / jnz` | 1,310,720 | 21,400 | 119,200 |
| jmp | `test cx,1 / jz / inc ax / dec cx / jnz` | 1,310,720 | 32,200 | 180,000 |
| str | `rep movsw` (MVN fast path) | 32,768 | **197,000-218,000** | **983,000** |

(`str` runs for nine or ten frames at the stock clock, so its figure moves by
a frame from run to run.) Before the four changes above the rows read
15,600 / 87,100, 15,300 / 85,200 and 23,000 / 128,500.

The MVN fast path made `REP MOVSW` 23x faster (was 9,400 / 53,000 IPS). It
helps memory copies and screen scrolls.

Reading the compute rows: a stock IIGS retires a register instruction every
~105 65816 cycles and one with a memory operand every ~130, between 1/11 and
1/14 of a 4.77 MHz 8088 on this kind of code; a 16 MHz Zip is about half an
XT on register code and 2/5 on memory operands.

## What the M5 gate asks

A DOS kernel's boot runs a few million instructions; measured, FreeDOS is at
its prompt 90 emulated seconds after a stock machine starts it from a folder
(above). The plan's own gate (is a measured speed sufficient to pursue a full
boot) was met at 15,600 IPS for an accelerated machine, and the boot has been
done since (`docs/mode-b.md`, `docs/share.md`).
