# M6: dynamic translation (JIT)

M6 is the plan's optional experiment: translate hot guest basic blocks into
native 65816 code and adopt it only if it shows "a repeatable, meaningful net
speed gain on real programs without CPU-test regressions." This document
records the spike that opened M6 and the design a full translator would follow.

## The spike (done)

The plan says to start "with preassembled templates." The spike is a
hand-written native 65816 translation of the `reg` benchmark's two basic
blocks (`src/core/jit.s`), run by the `J` command, measured against the
interpreter running the identical workload with the `B` command.

`reg.asm` inner loop and its translation (guest registers live in the direct
page at AX=$00, CX=$02, DX=$04, BX=$06):

| guest instruction | native 65816 | note |
| --- | --- | --- |
| `add ax, bx` | `lda rAX / clc / adc rBX / sta rAX` | flags dead, value only |
| `sub bx, 1`  | `lda rBX / dec / sta rBX` | flags dead, value only |
| `dec cx`     | `dec rCX` | native Z = guest ZF |
| `jnz inner`  | `bne :inner` | reads the DEC's native Z |

The two design levers the spike exercises:

- **No dispatch.** The loop body is straight-line native code. There is no
  fetch, no ModR/M decode, no `jmp (optab,x)`, and no per-instruction
  bookkeeping.
- **Dead-flag elision.** `add` and `sub` here set flags that the next
  flag-setter overwrites before any branch reads them, so no flag work is
  emitted at all. The one live flag is `dec cx`'s zero flag, and the 65816's
  own Z after `dec` already is the 8086 ZF, so `bne` consumes it directly with
  no table lookup. This is the project's eager-flag mapping (BOOTSTRAP: the
  65816 N/V/Z/C after `ADC` are the 8086 SF/OF/ZF/CF) used in reverse.

### Measurement: the per-class ceilings

`tools/jit_spike.py` hand-translates all three bench loops (`reg`, `mem`,
`jmp`) and times each against the interpreter running the same loop, by MAME's
frame count between `MB_RUNIDX` = $BE57 and $D04E (the `tools/bench.py`
method). These are **ceilings**: one hot loop, no block boundaries, no
fallback.

| code type | interpreter IPS | JIT IPS | ceiling |
| --- | --- | --- | --- |
| register ALU (`reg`) | 15,012 | 336,441 | 22.4x |
| memory operands (`mem`) | 14,769 | 98,674 | 6.7x |
| compare-and-branch (`jmp`) | 21,992 | 619,238 | 28.2x |

(16 MHz Zip gives the same ratios: 22.7x / 6.7x / 29.1x.) For context a
4.77 MHz 8088 runs ~300K IPS, so translated register and branch code beats a
real XT on a **stock** IIGS. Reproduce: `make`, then
`python3 -I tools/jit_spike.py`.

The spread is the whole story. Register and branch code win big because the
interpreter spends most of its time on dispatch and flags there, and the JIT
elides both. Memory code wins far less (6.7x) because the JIT still computes
the effective address and does the 24-bit host access every time; dispatch is
a small part of that cost. So the ceiling depends entirely on what the code
does.

## Does it help the FreeDOS boot?

The microbench ceilings do not transfer to a real boot, so the boot was
profiled directly (an opcode histogram and a ModR/M reg/mem counter wired into
the interpreter's fetch path, over ~2 million boot instructions to `INT 13h`
call 167). The boot looks nothing like a hot loop:

| measured property | value | why it matters |
| --- | --- | --- |
| average basic block | **3.33 instructions** | 30% of instructions are control transfers, so a block JIT transitions ~every 3 instructions |
| ModR/M operands | 72% register, **28% memory** | memory forms (12% of all instructions) cap at 6.7x |
| segment loads / prefixes | 7.2% / 2.5% | `mov sreg`, `les`/`lds`, overrides: a base change keys/invalidates a block |
| hard fallback | **~10.5%** | `INT`, string+REP, far transfers, I/O: run on the interpreter, with a transition each way |

Weighting the measured mix by the measured per-class ceilings (and treating
interpreter time per instruction as roughly equal) gives an **Amdahl ceiling
of ~6.3x** for the boot, *before* any block-transition or invalidation cost:

```
1 / (0.339/22.4 + 0.132/6.7 + 0.424/22 + 0.105/1) = 6.3x
```

The 10.5% fallback term alone is two-thirds of that denominator: even a
perfect JIT of everything else caps the boot near 9.5x, and the memory and
register costs bring the no-overhead ceiling to ~6x. The 3.33-instruction
blocks then pull the realizable number down, because a block JIT must look up
and enter a block, and reconcile flags, roughly every three instructions;
with blocks this short that per-block overhead is a large fraction of the
per-instruction saving. A fair estimate for a real block JIT on this boot is
**~2-4x**, with the exact figure set by the unmeasured block-transition and
self-modifying-code-invalidation overhead.

### Model verdict (before building the translator)

Weighting the mix by the per-class ceilings gave a ~6.3x optimistic Amdahl
ceiling and, after short-block overhead, a guessed ~2-4x. That guess assumed
per-block overhead was a modest fraction of the per-instruction saving. The
runtime translator, built next, measured that overhead directly and showed the
assumption was too optimistic.

## Runtime translator: built and measured

`src/core/jit2.s` is a real runtime block translator, driven by the `K`
command. It translates a basic block at the guest IP into native 65816 in a
code cache (bank $06), keys it in a direct-mapped block map (bank $06 high) by
guest linear IP, runs it, and returns to the dispatcher at each block end;
anything outside its opcode set ends the block with a fallback exit that the
interpreter single-steps. Coverage: `mov r16,imm`, `inc`/`dec r16`,
`add`/`sub`/`cmp r/m16,imm8` and `add r/m16,r16` reg-form, `test r/m16,imm16`,
`jz`/`jnz`, `hlt`. It elides the benchmark loops' dead flags and reads the
native Z the preceding op leaves for the terminating `jz`/`jnz`, so it is
correct for those loops; `tools/jit_spike.py`-style register checks confirm the
JIT (`K`) and interpreter (`B`) produce identical results.

Measured on the emulator, stock clock, same workload each way:

| program | interpreter | hand-translated ceiling | **real JIT, unlinked** | **real JIT, self-loop linked** |
| --- | --- | --- | --- | --- |
| reg | 15,106 IPS | 22.4x | 2.62x | **18.93x** |
| jmp | 22,035 IPS | 28.2x | 1.22x | 1.22x |
| mem | 14,783 IPS | 6.7x | 0.52x | 0.52x |

What this proves, with real numbers rather than a model:

- **Per-block dispatch overhead is the dominant cost.** Unlinked, a block JIT
  returns to the dispatcher (hash the IP, enter, run, return) at every block
  end. On reg's 4-instruction loop that collapses the 22.4x ceiling to 2.62x.
- **Linking the loop recovers the ceiling - but only for self-loops.** Making a
  backward branch whose target is the block's own entry jump natively back into
  the cache instead of returning takes reg from 2.62x to 18.93x, near its
  ceiling. jmp's loop cycles through *different* blocks (`test`/`jz` then
  `dec`/`jnz`), so self-loop linking does not catch it and it stays at 1.22x;
  it needs general inter-block linking.
- **Fallback-heavy code is slower than the interpreter.** mem's memory operands
  fall back, and each fallback is a JIT->interpreter->JIT round trip. The
  result (0.52x) is worse than just interpreting.

## Verdict for the FreeDOS boot

The boot's measured profile is the jmp/mem profile, not the reg profile:
3.33-instruction blocks, 30% control transfers, ~10% hard fallback, 7% segment
work, and its loops run through the kernel's call/branch structure rather than
tight self-loops. The two things the real JIT needs to win - long blocks or
self-loops, and little fallback - are exactly what the boot lacks.

So the measured conclusion is **negative for the boot**: a block JIT of this
design would not meaningfully speed up the FreeDOS boot and, over its
fallback-heavy and segment-heavy stretches, would run slower than the
interpreter (mem's 0.52x is the warning). The 22x microbench never transfers,
because it is a tight self-loop and the boot has none. Recovering even the ~6x
model ceiling would require general inter-block linking, near-complete opcode
coverage (so fallback is rare), and flag materialization at block exits for
correctness - a large build whose own transition costs, measured here at the
block level, argue it would still land well short of the microbench and
possibly short of 1x on the boot's worst stretches.

The exit criterion ("meaningful net gain on real programs ... otherwise retain
the interpreter") is therefore **not met for the boot**. The interpreter stays
the default engine. A JIT remains worthwhile only for a guest that is a tight
compute kernel (where reg's 18.93x applies), not for booting and running DOS.

## Remaining work (if a boot-capable JIT is ever pursued)

- **General inter-block linking**, not just self-loops: back-patch each
  inter-block branch to the target's native entry once translated, with a
  translate-and-enter stub until then, so multi-block loops stay in the cache.
- **Flag materialization at block exits** so elision is correct when a
  successor or a fallback reads flags the block left native-only (today's
  translator is correct only for loops with no flags live across a boundary).
- **Near-complete opcode coverage** including the memory-operand ModR/M forms,
  `mov`/`push`/`pop`, near `call`/`ret`, and the segment ops, so fallback is
  rare; each fallback measured here costs more than interpreting.
- **Self-modifying-code invalidation** (a per-4K-page "has translated code"
  bit on the write path) and a code-cache eviction policy.
