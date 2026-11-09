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
   evaluation would save roughly two-thirds of the ~35% flag cost. It is a
   large, correctness-sensitive change and is the identified next step,
   gated by the 2.88M-vector suite; the eager path stays until it is done.

## Throughput

MAME 0.284 `apple2gs` (ROM 03), 8 MB, stock 2.8 MHz and the ZipGS 16 MHz
setting. OUTER=4 (65,536 iterations a loop).

| program | what an iteration is | instructions | stock IPS | Zip 16 MHz IPS |
|---|---|---:|---:|---:|
| reg | `add ax,bx / sub bx,1 / dec cx / jnz` | 1,048,576 | 15,600 | 87,100 |
| mem | `add [bx],ax / mov ax,[si+2] / mov [bx+4],ax / dec cx / jnz` | 1,310,720 | 15,300 | 85,200 |
| jmp | `test cx,1 / jz / inc ax / dec cx / jnz` | 1,310,720 | 23,000 | 128,500 |
| str | `rep movsw` (MVN fast path) | 32,768 | **218,000** | **983,000** |

The MVN fast path made `REP MOVSW` 23x faster (was 9,400 / 53,000 IPS). It
helps memory copies and screen scrolls; the register and memory loops are
unchanged because they use no string instructions.

Reading the compute rows: a stock IIGS retires a general instruction every
~180 65816 cycles, about 1/19 of a 4.77 MHz 8088 on this kind of code; a
16 MHz Zip is about 1/3 of an XT. Lazy flags is the lever that would move
these.

## What the M5 gate asks

A DOS kernel's boot runs a few million instructions. At ~15,600 IPS stock
that is two to three minutes, and under half a minute on a Zip, before lazy
flags. String-heavy and scroll-heavy code is already much faster. The
numbers justify M5 as a usable, if unhurried, experiment; the plan's own
gate (is a measured speed sufficient to pursue a full boot) is met for an
accelerated machine.
