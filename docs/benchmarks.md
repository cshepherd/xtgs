# Benchmarks

Measured, not estimated. `make bench` (tools/bench.py) assembles
`tests/bench/*.asm` with nasm, boots each as the loader's B command, and
times it by MAME's emulated frame count between the core's start and done
marks, so no guest timer is involved and host speed does not matter. The
instruction count is the program's own.

## 2026-11-08, M1 core (eager flags, no fast paths)

MAME 0.284 `apple2gs` (ROM 03), 8 MB, stock 2.8 MHz and the ZipGS 16 MHz
setting (`a2_config`). OUTER=4 (65,536 iterations a loop).

| program | what an iteration is | instructions | stock s | stock IPS | Zip 16 MHz s | Zip IPS |
|---|---|---:|---:|---:|---:|---:|
| reg | `add ax,bx / sub bx,1 / dec cx / jnz` | 1,048,576 | 66.6 | 15,700 | 11.9 | 88,000 |
| mem | `add [bx],ax / mov ax,[si+2] / mov [bx+4],ax / dec cx / jnz` | 1,310,720 | 83.8 | 15,700 | 15.0 | 87,500 |
| jmp | `test cx,1 / jz / inc ax / dec cx / jnz` | 1,310,720 | 56.3 | 23,300 | 10.1 | 130,000 |
| str | `rep movsw`, one word an instruction | 32,768 | 3.4 | 9,600 | 0.6 | 53,100 |

Reading: a stock IIGS retires a guest instruction every ~180 65816 cycles
(~1/19 of a 4.77 MHz 8088 on this kind of code), a 16 MHz Zip every ~180
cycles of its own clock (~1/3.4 of an XT). The Zip/stock ratio of 5.6 is the
clock ratio: nothing here is memory-bound in a way MAME models.

Where the cycles go (BOOTSTRAP.md section 5 estimates, now bracketed by
measurement): fetch and dispatch ~22, ModR/M and pointer formation 35-60 for
a memory operand, the operation 15-30, the eager flag computation ~90 (the
P-to-FLAGS translation, parity, AF, the two-byte split of `rFL`). The flag
cost is the lever for M4: lazy evaluation or a leaner eager form would take
the common ALU path from ~180 toward ~100 cycles. `REP MOVS` has no `MVN`
fast path yet: the generic path recomputes both pointers and checks the
segment wrap every word.

## What the M5 gate asks

A DOS kernel's boot runs a few million instructions: at these speeds that
is two to three minutes on a stock machine and under half a minute on a
Zip, before any optimisation. Usable, not comfortable; M4 decides.
