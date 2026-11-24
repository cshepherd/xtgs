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

# M6 revisited (2026-11-24)

`XTGS-M6-JIT-Revisited.md` reopens M6 as an opt-in accelerator for hot
regions of sustained gameplay, with the interpreter kept as the reference
and the default. It asks for two things before anything is built for real:
that linking blocks to each other recovers the ceiling the first experiment
only reached for a loop of one block (its Gate A), and that real programs,
profiled, have enough time in code a translator could take (its Gate B).
Both are done here, in MAME; nothing of it ran on a IIGS. The verdict above
stands as what was measured then: it was a verdict on the FreeDOS boot and on
a translator of register forms that returned to its dispatcher at every
block, and both halves of that turn out to matter.

## The baseline today

The first experiment's code, unchanged, measured again (stock clock, the
same three loops; `tools/jit_bench.py --engines B,J,K` on the tree before
this work):

| program | interpreter | hand translation | the translator (`K`) |
| --- | --- | --- | --- |
| reg | 28,238 IPS | 336,441 (11.9x) | 285,975 (10.1x) |
| mem | 22,553 IPS | 98,674 (4.4x) | 7,969 (0.35x) |
| jmp | 33,913 IPS | 619,238 (18.3x) | 26,859 (0.79x) |

The translated code runs exactly as fast as it did (the same IPS as in the
tables above). The interpreter is 1.5 to 1.9 times faster than it was then
(docs/benchmarks.md), so every ratio against it is that much smaller, and
the unlinked translator on `jmp` is now slower than interpreting.

## M6.1: every direct edge linked

`src/core/jit2.s` now links any conditional jump to any block. The letter
after `K` chooses what it does, so one build measures all of it:

| | |
| --- | --- |
| `K U` | unlinked: every block ends in the dispatcher |
| `K S` | a block's jump to its own entry stays native (the first experiment's link) |
| `K L` | every direct edge linked |
| `K G` | the same, with the guard (below); `K` alone is this |
| `K C` | `U`, translating again at every dispatch: what a translation costs |

How a linked block is made:

- A conditional jump whose target already has a native entry branches to
  it: a short branch when it reaches, an inverted branch over a `JMP` when
  it does not.
- One whose target has none goes through a *site*: a `JMP` to its own exit
  stub. The stub puts the target in `rIP` and returns the address of the
  `JMP`'s operand. The dispatcher translates the target, stores its entry
  at that address, and the edge is native from then on.
- After a conditional jump the translation goes on at the fall-through,
  which gets its own entry in the block map. The jump not taken costs one
  branch.
- Every entry has one contract: the guest's registers in the direct page,
  nothing in A or the native flags. So any edge may go to any entry.
- A translation that begins with the cache nearly full resets the whole
  cache (the map, the code, every link) and a site from before the reset is
  not patched. One longer than 1 KB is cut, with a site for the rest.

What `jmp`'s loop becomes (`tools/jit_bench.py --dump`; guest addresses on
the right):

```
0053  C6 02      dec rCX          010D  skip: dec cx
0055  F0 0C      beq $0063        010E  jnz inner (inverted)
0057  4C 66 00   jmp $0066              the site, patched: inner's entry
005A  ...                               its stub: rIP = $0106, A = $0058, rtl
0063  4C 3F 00   jmp $003F        0110  the fall-through has an entry
0066  A5 02      lda rCX          0106  inner: test cx,1
0068  29 01 00   and #$0001
006B  F0 E6      beq $0053        010A  jz skip: its entry is near
006D  4C 2D 00   jmp $002D        010C  the fall-through has an entry
...
002D  E6 00      inc rAX          010C  inc ax
002F  C6 02      dec rCX          010D  dec cx
0031  F0 0C      beq $003F        010E  jnz inner (inverted)
0033  4C 66 00   jmp $0066              the site, patched
```

Measured (`tools/jit_bench.py`, 7 x 65,536 iterations, stock clock; the
16 MHz Zip's ratios are the same to a percent; `docs/jitprof/bench-m61.txt`
is the whole run):

| program | interpreter | hand translation | `U` | `S` | `L` linked | `G` linked, guarded |
| --- | --- | --- | --- | --- | --- | --- |
| reg | 28,245 IPS | 11.9x | 1.23x | 10.1x | **10.9x** | 8.9x |
| mem | 22,666 IPS | 4.35x | 0.32x | 0.32x | 0.38x | 0.38x |
| jmp | 33,915 IPS | 18.3x | 0.69x | 0.69x | **15.9x** | 11.6x |

(`U` and `S` are a little slower than the first experiment's `K` on `jmp`
and `mem`: the dispatcher now counts its entries and tests the mode.)

- **Linking recovers the ceiling.** `jmp` goes from 0.79 to 15.9 times the
  interpreter, 87% of the hand translation; in the first experiment's terms
  (its interpreter was 22,035 IPS) that is 24.5x against a ceiling of 28.2x.
  `reg` keeps its gain and adds a little (10.1x to 10.9x): its loop was the
  one case the old link caught.
- **Where the rest of the ceiling is.** Two iterations of `jmp` cost the
  hand translation 46 cycles and the linked blocks 53. The seven are three
  `JMP`s: two fall-throughs to entries that already existed, and a patched
  site, which stays an inverted branch over a `JMP` (5 cycles) where a
  branch would do (3). `reg` costs 37 cycles an iteration against 34: `sub
  bx,1` is translated as `SEC / SBC #1` and written by hand as `DEC`.
  Patching a near site into a plain branch and translating a fall-through
  again instead of jumping to it would close most of it; neither is done.
- **`mem` is not about linking.** Its three memory instructions are not
  covered, and each is a round trip to the interpreter. It measures that
  round trip, as before.
- **A translation costs about 500 cycles a guest instruction** (`C` against
  `U`: 1,230 to 1,980 cycles a block of 2 to 4 instructions, 57 cycles an
  emitted byte). An interpreted instruction costs 85 to 125, so a block has
  paid for itself after it has run six times or so.

### The guard

Linked blocks never come back to the dispatcher by themselves, and the
interpreter's slot (the interrupt lines, the frame's work) has to be met. A
loop has a backward edge, so in mode `G` every backward edge counts X down
and the block returns at 0, status 3, with `rIP` the target; the dispatcher
gives it 64 again (`JIT_GUARD_N`). X costs nothing to keep: the templates
use A only. What it costs to count:

- in the loop, 4 cycles a backward edge (`DEX` and a branch), 7 where the
  plain branch was 3;
- at 0, the way back through the dispatcher: about 300 cycles for a guard
  stub and about 380 through a site, which is looked up and patched again.
  At 64 edges that is 5 or 6 cycles an edge, more than the count itself. A
  stub that named its target's entry would bring it to about 80, and a
  larger count divides it; neither is done.

So the guard is `reg` 10.9x to 8.9x and `jmp` 15.9x to 11.6x as it stands,
and about half of that loss is the return path, not the count. `K` has no
slot to run: this is the cost of meeting one, not of running it.

### What is judged, and what is still for the loops only

`tools/jit_bench.py` compares the guest's registers after every run with
the interpreter's (not SP: `K` sets its own). The three loops and
`tests/bench/jlink.asm` (forward and backward jumps, taken and not, a
target further than a native short branch, loops that share a tail, a loop
of one block, two instructions the translator does not cover) agree in
every mode, at both clocks, and with the regions moved (`XTGS_LAYOUT=alt`).
Mode `C` on them goes through 20 to 280 cache resets.

Still only right for these loops, exactly as before:

- **Flags.** The translator elides them and gives the interpreter's lazy
  flags nothing at an exit. A jump reads the native Z of the instruction
  before it, in the same block, or the block is not translated that far.
  `jlink.asm` is written to that rule. General code needs the proposal's
  M6.4.
- **Coverage.** `mov r16,imm16`, `inc`/`dec r16`, `add r16,r16`, `add`/`sub`
  /`cmp r16,imm8`, `test r16,imm16`, `jz`/`jnz`, `hlt`. Nothing was added.
- **No memory is written by translated code**, so nothing is known yet
  about video memory, the EGA's trap or code that is written over.

**Gate A** asked for `jmp` at 5x or more with `reg` keeping most of its
gain. Met: 15.9x and 10.9x, or 11.6x and 8.9x with the guard.

## M6.2: what real programs spend their time on

`tools/jit_profile.py` profiles a workload from MAME's side. Nothing is
changed in the guest or in XT/GS, and the taps only look. (Not quite
"exactly as it would": the sampling clock ends MAME's time slices at other
instants, and a guest whose course depends on a cycle here or there takes
another one. Thexder's demo does, and it also follows the tick count the
machine starts with, so two runs of it are two different thirty seconds,
one of them 8% cheaper an instruction than the other; a comparison of two
builds on it is only good between runs that took the same course. The
other workloads do the same work every run. With the write tap on or off
the guest's memory at the end is byte for byte the same.) Between two
frames it records

- every guest instruction fetched, by a read tap on the direct page's
  `bCS` taken when the 65816 is at `fetch`: a count for every CS:IP and for
  every pair of consecutive instructions, so every edge with its count;
- the time: every 1.37 ms of emulated time, where the 65816 is and which
  guest instruction it is working for (22,000 samples in 30 seconds);
- every guest write into a page it has executed code from;

and at the end it dumps the guest's memory, which `tools/x86dec.py` decodes
(lengths checked against `ndisasm` on 70,000 instructions). The time a
guest instruction takes is therefore measured, not estimated from a count.

The workloads, each 30 seconds at 16 MHz (the Zip) unless said, reached
from a cold boot by typed keys only; where a game has a demo of its own
that is the gameplay (`jit_profile.py list`; the whole reports are in
`docs/jitprof/`):

| workload | what |
| --- | --- |
| thexder-tandy, thexder-cga | Thexder's own demo of level 1, in Tandy mode 09h and in CGA mode 4 |
| arkanoid | Arkanoid's own demo of round 1, Tandy mode 09h |
| keen-load | Commander Keen 1 decompressing its graphics as it starts: 160 seconds of it at 16 MHz |
| keen-title | Keen's opening over a scrolling starfield, EGA mode 0Dh |
| lsl2 | Leisure Suit Larry 2's title animation: Sierra's SCI interpreter running the game's scripts |
| basic | GW-BASIC running `FOR I=1 TO 30000:A=A+I*2:B=SQR(A)+B/3:NEXT` |
| boot | FreeDOS booting, up to its prompt (17 s): the control |
| prompt | FreeDOS's shell waiting at its prompt (15 s): an idle case |

### Where the time goes

Shares of all the time; `64 blocks` is the share of the interpreter's time
in the 64 hottest basic blocks:

| workload | interpreter | video | the slot | cycles an instruction | instructions a block | 64 blocks |
| --- | --- | --- | --- | --- | --- | --- |
| thexder-tandy | 77.7% | 13.9% | 6.4% | 104 | 2.95 | 94% |
| thexder-cga | 57.2% | 37.0% | 5.1% | 98 | 2.87 | 93% |
| arkanoid | 28.4% | 67.8% | 1.9% | 122 | 3.55 | 90% |
| keen-load | 95.0% | 0.1% | 4.4% | 132 | 5.98 | 100% |
| keen-title | 38.9% | 58.5% | 1.3% | 213 | 5.57 | 70% |
| lsl2 | 92.7% | 2.4% | 3.5% | 134 | 4.03 | 66% |
| basic | 92.3% | 0.0% | 7.1% | 111 | 3.31 | 74% |
| boot | 85.0% | 0.8% | 7.1% | 106 | 1.76 | 54% |
| prompt | 90.7% | 0.1% | 7.5% | 125 | 3.91 | 100% |

- **Four of the workloads are the interpreter's** (78% to 95%): Thexder on
  a Tandy, Keen's start, Larry 2, GW-BASIC. A faster CPU is the only thing
  that helps them.
- **Three are video's.** Arkanoid shows a new Tandy page every frame, and
  moving 16K pages for the page register (`tdy_move`) is 39% of all its
  time, `tdy_row` another 28%. Keen's scrolling title is `eg_conv` and
  `eg_wide`, 58%: the whole screen redrawn at every scroll step. Thexder
  in CGA mode 4 is `gfx_blit_line`, 36%. A translator would give these 1.2
  to 1.7 times at best; their bottleneck is in `src/svc/`.
- **The hot code is small.** In the games 64 basic blocks hold 90% and more
  of the interpreter's time, and in Thexder one loop of 13 blocks holds
  44%. The boot is the opposite (5,700 blocks, 54% in the 64 hottest),
  which is why it was the wrong program to judge by.
- **The interpreter's fixed costs are visible.** `fetch`, the six
  instructions every guest instruction passes through, is 15% to 18% of
  all time wherever the interpreter dominates, and the slot 3.5% to 7.5%:
  about one guest instruction in twelve meets it. Making the slot cheaper
  is worth about as much as it costs to look at, with no translator at all.
- **Blocks are short everywhere** (1.8 to 6 instructions), so a translator
  that returns to a dispatcher at each block's end loses on all of them.
  That was M6.1's question, and the reason it came first.

### What the hot code is made of

By what a translator would have to cover, as shares of the interpreter's
time. Tier 0 is `jit2.s` today; tier 1 adds every register form and the
direct jumps; tier 2 adds memory operands, the stack, near calls and
returns, the string instructions without `REP`, and `CLC`/`STC`/`CLD`/
`STD`; the rest (segment loads, far transfers, `INT`/`IRET`, `IN`/`OUT`,
`REP` strings, `PUSHF`/`POPF`/`CLI`/`STI`) stays the interpreter's.

| workload | tier 0 | + tier 1 | + tier 2 | left | templates for 95% |
| --- | --- | --- | --- | --- | --- |
| thexder-tandy | 18.9% | 31.7% | 47.3% | 2.2% | 60 |
| thexder-cga | 23.0% | 31.7% | 42.2% | 3.1% | 61 |
| arkanoid | 11.8% | 26.3% | 50.3% | 11.7% | 59 |
| keen-load | 2.4% | 44.6% | 39.3% | 13.7% | 53 |
| keen-title | 6.7% | 14.1% | 55.1% | 24.1% | 43 |
| lsl2 | 8.7% | 27.7% | 53.0% | 10.6% | 94 |
| basic | 7.5% | 56.3% | 33.7% | 2.4% | 82 |
| boot | 14.9% | 31.0% | 44.9% | 9.1% | 107 |

(A template is an opcode with its register or its memory form, a group's
sub-operation counted apart: `8B mem`, `83/7 reg`. 80 to 300 distinct ones
are executed; the count is how many cover 95% of the interpreter's time.)

- **Register forms are not enough.** Tiers 0 and 1 together are a third to
  two thirds of the time, and they are interleaved with the rest: a
  register-only translator crosses to the interpreter and back 15,000 to
  50,000 times a second.
- **Memory operands are the bulk of what is missing**, an instruction in
  seven in Thexder and its most expensive (166 cycles against 98 for a
  register form). Thexder alone spends 12% of the interpreter's time in
  single `MOVSW`s; a string instruction without `REP` costs it 196 cycles.
- **What is left is mostly segment loads** (8% in Keen's start, with its
  far returns 5.5%: Borland's long-arithmetic helpers, called far, working
  through huge pointers) and `REP` strings, which the interpreter already
  runs as block moves.
- **Flags are local.** A flag read finds its producer in the instruction
  just before it 95% to 100% of the time in five workloads, 73% to 83% in
  Arkanoid, BASIC and the shell, and half the time in the boot (a call
  that returns a carry). Of the instructions that set flags, a third to a
  half have them overwritten unread within the block in the games (a
  quarter in BASIC, a sixth in the boot), and 7% to 20% leave them standing
  at the block's end (43% in Arkanoid, half in the boot). The interpreter's
  lazy flags are the natural form for those ends.
- **Segments move, CS little.** 9 to 54 segment register loads a thousand
  instructions in the games (1 in BASIC, 97 in the shell). A game's hot
  blocks are nearly all under one value of CS (two in Keen's title, three
  that matter in Larry 2), and no linear address was executed under two
  values of CS in any game.
- **Nothing wrote over its own code** in any game or in BASIC: no write
  landed on the bytes of an executed instruction. But writes into the
  256-byte *pages* that hold executed code are common: none in Thexder on
  a Tandy, 73 to 1,560 a second in the others (data beside code; 73 a
  second, the figure in three of them, is four writes at each timer tick).
  So an invalidation by page would fire constantly, and has to look closer
  before it throws anything away. The boot does write over code, 8,560
  times: programs being loaded, and one instruction at the top of memory
  rewritten before each of its 2,994 executions. (A write counts only once
  its page has been executed from in the window, so code written and then
  run for the first time is not in these figures.)
- **Interrupts are few**: 6 to 150 timer interrupts a second, nothing
  else. The guard's count is a matter of latency, not of load.

### What a translator could give: a model

Not a measurement. Each translated instruction is charged an estimate of
its native cycles instead of the interpreter's measured time for it: 13 to
14 for a register form, 34 more for a memory operand (the offset, the
segment's base with its carry, the compare for video memory, a `[dp]`
access), 7 for a jump, 30 for a push or pop, 38 for a near call, 70 for a
return (an indirect edge), 42 or 70 for a string instruction. An
instruction is translated when its tier is covered and its block ran 50
times in the window. Every passage between a translated instruction and one
that is not costs X cycles, taken at 150 and at 60. The first two columns
are a tier-2 translator, the last what register forms alone would give:

| workload | the interpreter's share | all of the time | tier 1 only, all of the time |
| --- | --- | --- | --- |
| thexder-tandy | 3.7x - 4.0x | 2.3x - 2.4x | 0.93x - 1.21x |
| thexder-cga | 3.5x - 3.9x | 1.7x | 0.95x - 1.16x |
| arkanoid | 2.5x - 2.9x | 1.2x | 0.96x - 1.04x |
| keen-load | 2.0x - 2.6x | 1.9x - 2.4x | 1.10x - 1.37x |
| keen-title | 2.0x - 2.3x | 1.2x - 1.3x | 0.91x - 1.01x |
| lsl2 | 2.8x - 3.1x | 2.5x - 2.7x | 0.87x - 1.13x |
| basic | 4.1x - 4.3x | 3.3x - 3.5x | 1.05x - 1.50x |
| boot | 2.1x - 2.5x | 1.8x - 2.0x | 0.86x - 1.16x |

What the model leaves out, all of it against the translator: the cost of
translating (small: the hot code is a few hundred instructions), the guard,
the flags stored at exits, whatever the check for a write over code costs
every store, and the fact that none of the tier-2 templates exists, so
their cycles are estimates where tier 0's are measured. What it leaves out
in the translator's favour: a memory operand whose segment base is known
when the block is made needs no base arithmetic at all. Halve the model's
gain and the four interpreter-bound workloads still pass the proposal's
1.5x.

**Gate B** asked for one recurring real-game workload with enough eligible
CPU time. Met, with a condition: Thexder on a Tandy, Keen's start, Larry 2
and BASIC are 78% to 95% interpreter, and 86% to 98% of that is code a
tier-2 translator would take. It is not met by the translator that exists:
tier 0 is 2% to 23%, and nothing short of memory operands pays.

## What this says to do

1. **A selective translator is worth building only at tier 2**, as the
   proposal's M6.3 and M6.4: led by the interpreter, admitted by a count,
   with flags, video memory, writes over code and the slot handled. The
   templates wanted first are in each report's list; 60 cover 95% of
   Thexder. It is most of the common instruction set again, as templates.
2. **Three of the workloads want video work instead**: the Tandy's page
   moves (Arkanoid), the EGA's wide-window redraw (Keen scrolling) and the
   CGA mode 4 blit (Thexder in CGA).
3. **Two things would help every program without a translator**: a cheaper
   slot (4% to 7.5%), and a faster single `MOVS`/`LODS`/`STOS` (16% of
   Thexder's interpreter time is string instructions without `REP`).

Not done, and what the proposal asks for before real code runs translated:
its M6.3 (admission, regions), M6.4 (flags, addressing, invalidation,
interrupts), differential tests, and any measurement on a real IIGS.

# M6.3 and M6.4: a translator for real programs (2026-11-24)

Built: `src/jit/` (its own image, the file `JIT`), `src/core/jitc.s` (the
core's side), `tools/gen_jit.py` (the templates), `tools/jit_fuzz.py` (the
test). It is off unless `XTGS.CMD` has the line `JIT=ON` and the file `JIT`
is beside `CORE`; a run without it executes none of it but one three-byte
`JMP` at the slot's end. Nothing below has run on a real IIGS.

## What it is

The interpreter owns the run. At a taken jump back it looks the target up
in a map (`jit_bk`); an address come to sixteen times is translated, and
from then on its code is run instead. What is translated is a *piece*: the
instructions from that address in the order they lie, with the jumps among
them, up to 48, each as a template of 65816 code with the guest's registers
where the interpreter keeps them, in the direct page (`scan.s`, `emit.s`,
`gen/jtab.s`). A piece ends where control leaves it: a jump out, a call, a
return, or an address that has a piece of its own already. A jump's target
is taken into the piece only when it lies within 48 bytes of the piece's
end so far (`sc_ahead`): a piece is code that lies together.

From a piece's end the *dispatcher* (`h_disp`, `jt_look`) looks the next
address up and goes straight to its piece; an address that is in the code (a
jump's or a call's target, the instruction after the last) is asked for
once, and the place that asked is then patched into a `JMP` to the piece (a
*link*: `h_linkf`, `h_linkb`). So a program's hot paths run from piece to
piece, calls and returns included, without the interpreter. An address with
no piece counts toward its sixteen, and the interpreter goes on from it.

An instruction that has no template ends its piece with a way out that
says how the core is to go on (`jit_ret` in `jitc.s`): the interpreter does
that one instruction (its retire vector points at `jit_hook` for it) and
the dispatcher is asked again for wherever it lands. An address whose first
instruction is such a one has no piece: its word of the map says which way
out it is (`M_STEP` and up). A few that write no
memory and jump nowhere (`MUL`, `DIV`, `IN`, `OUT`, `LAHF`, the decimal
adjusts...) are done by the interpreter *inside* a piece, which then goes
on.

Three banks, the JIT region: the translator and its tables; a bank of
run-time routines and the code cache (62K); a bank of map, a word for an
address at `(IP + CS) * 2` and, when that one is another address's, the
word 8000h from it. A full cache or 500 pieces empties everything.

| | |
| --- | --- |
| translated | `MOV`, `ADD` `OR` `ADC` `SBB` `AND` `SUB` `XOR` `CMP` `TEST`, `INC` `DEC` `NEG` `NOT`, `XCHG`, `LEA`, the shifts and rotates by 1 and (on a register) by `CL`, `PUSH` `POP` of registers and segment registers, `MOV` to and from a segment register, `LES` `LDS`, `CBW` `CWD`, `CLC` `STC` `CMC` `CLD` `STD`, `Jcc` (not the parity pair), `JMP`, `LOOP`, `JCXZ`, `CALL`, `RET`, `RET n`, `RETF` to the same CS, `JMP` and `CALL` through a register or a word, `MOVS` `STOS` `LODS` alone; every ModR/M form, segment overrides |
| the interpreter's, inside a piece | `MUL` `IMUL` `DIV` `IDIV`, `IN` `OUT`, `LAHF` `SAHF`, `DAA` `DAS` `AAA` `AAS` `AAM` `AAD`, `XLAT`, `CMPS` `SCAS` alone, `POP SP`, `WAIT` |
| the interpreter's, and the piece ends | far `CALL` `JMP` `RETF`, `INT` `IRET`, `REP` and what it repeats, `PUSHF` `POPF`, `CLI` `STI`, `HLT`, the hypercall, a shift of memory by `CL`, `POP` to memory, `LOOPE` `LOOPNE`, `JP` `JNP`, the opcodes an 8088 has twice |

## Flags

The interpreter's lazy flags (`vLP`, `vLRES`, `vFS`, `vFD`) are the
contract at every way out of a piece. Inside one, an instruction stores
them only when a flag it sets can be read before it is set again (two
passes back over the piece, `sc_live`; everything is read outside it). A
`Jcc` straight after the instruction that made its flags branches on the
65816's own (`jf_tab`, by that instruction's class: a subtraction's carry
is the other way up, a logic operation has no carry or overflow, `INC`
keeps the carry, a shift has no overflow); an `ADC`, `SBB`, `RCL` or `RCR`
on a register straight after one that left a carry takes it from the
65816's carry. So `shl bx,1 / rcl dx,1 / rcl di,1 / rcl bp,1` is four
65816 instructions.

Known deviation: none in what the guest can read. (The first design let an
interrupt see stale arithmetic flags; this one stores what any way out can
be asked for.)

## Memory

A memory operand's host pointer is made by a routine of the run-time bank,
one for each segment base, read or write, byte, word or four bytes
(`gen/jrt.s`): the interpreter's own steps (base plus offset, the bank past
a carry, the megabyte's wrap). An operand that is only read is fetched
without it when the segment is based below 9000:0 (it then reaches no video
memory and no wrap): the base is the pointer and the offset the index
(`fetch` in `gen_jit.py`), and the instruction's register form is stamped
with the fetched value for its r/m. A word at offset FFFFh is the interpreter's
(the piece gives the instruction back: `ea_bail`). The text bank is marked
in `VID_DIRTY` as the interpreter marks it, both 256s for a word across
two; A000 while the screen is the EGA's mode 0Dh is the interpreter's (the
trap), and a piece that comes to it sixteen times is given up.

## Code that is written over

Every piece keeps the guest bytes it was made from and compares them
(`h_verify`) on entry whenever the *epoch* (`jEP`) is not the one it last
compared in. The epoch goes on whenever something that is not translated
code may have written memory anywhere: the interpreter running on its own,
a hypercall (but the timer's, the keyboard's and the clock's, which write
the BIOS's data and say so: `jCLN`), a `REP MOVS`, the diskette
controller's transfer behind an `OUT`. An instruction that writes the
stack at most (a far call, an `INT`, `PUSHF`) puts it on only when the
stack is on a page of code; the slot does the same for an interrupt's
frame, and the frame's work writes only what is never code (the vectors
and the BIOS's data, which no piece is made from: SVC's promise).

Translated code's own stores are looked at as they are made. A store into
a bank that translated code was made from (`bk_code`) looks its page up
(`pg_map`), then its sixteen bytes (`cl_map`: a bit for each sixteen that a
run of some piece's code is in); only then is every piece asked (`smc0`,
against the runs of bytes in its record, not the span from its first to
its last): the ones the word lands in are dead, their entries made jumps to
the dispatcher so that whatever was linked to them asks the map again; if
the running piece is among them the interpreter does the store. A store
that lands beside code is remembered (`bc_lo`: the same store, with no
piece made since, is let by at once: a counter next to a handler). Eight
different ones on a page make it a page of data and code together: its
pieces go, each a life less, and its stores are looked at no more, until
code on it is wanted again, when it is a page of code once more. (The
stores are as often a program being loaded past the code of the one before
it, whose pieces nothing has told that their code is gone.) A push looks
the sixteen bytes it writes up once and remembers them by SS and offset
(`jSPS`, `jSPO`). A `REP MOVS` or `STOS` is the interpreter's, and the
bytes between the two values of DI are then held against `pg_map`.

A helper that has to give the instruction back to the interpreter (a word
at FFFFh, the EGA's planes, a store into the running piece) needs its IP:
every `JSR` to a helper has `LDY #IP` straight before it, and the helper
reads it from the code (`h_bailr`).

A piece found changed gives its address a life less; at the seventh the
address is the interpreter's for good.

## Interrupts

A piece counts its jumps back and every pass through the dispatcher or a
link back (`jG`, 24). At nothing the core asks what the slot would ask
(`jr_guard`: a line that can be delivered, the vertical blank's edge);
with nothing to do translated code goes on, else the slot runs and comes
back to the dispatcher (`slot_x`), at the handler when it delivered one.
`STI`, `POPF` and `IRET` are the interpreter's, with its own way of
bringing an owed interrupt forward (`jit_hook` makes the guard's next count
its last when the slot is wanted).

## The ways out

What a piece, or the dispatcher, hands the core (`jit_ret`): A is why, Y
the IP.

| A | |
| --- | --- |
| 0 | the interpreter goes on from Y by itself (no piece is to be made there, or a helper gave the instruction back); translated code is come to again at the next jump back that is taken, and the epoch goes on |
| 2 | the guard ran out: `jr_guard` |
| 3 | the instruction at Y is the interpreter's and the piece goes on after it (`jtmp`), if the IP then is the one expected |
| 5 | the instruction at Y is the interpreter's and the dispatcher is asked again; it may have written anywhere (a hypercall that is not marked clean, an instruction with no template that writes memory): the epoch goes on |
| 6 | the same; it wrote the stack at most (a far `CALL`, `INT`, `PUSHF`): the epoch goes on if the stack is on a page of code |
| 7 | the same; it wrote nothing (`RETF`, `IRET`, `JMP` far, `CLI`, `STI`, `POPF`, `REP` with `CMPS` `SCAS` `LODS`) |
| 8 | the same, a `REP MOVS` or `STOS`: the epoch goes on if what it wrote is on a page of code |

## Tests

`tools/jit_fuzz.py`: programs of loops run without and with the
translator, a sum of every register, the flags and a buffer compared after
each. `--micro` is 201 loops of one form each (every template family, the
jumps on every condition after every class, calls and returns of each
kind, code that changes itself in the running piece, in another piece,
beside code); without it, random loops from a seed. Both end with a wait
on the clock's tick, which only the slot can end. `XTGS_JIT=1` puts the
translator on any test's volume (`tools/make_image.sh`).

## Measurements

MAME, a 16 MHz ZipGS, the workloads of M6.2 (`tools/jit_profile.py collect
NAME --jit`, then `compare --jit`; the reports are `docs/jitprof/NAME-jit.txt`
and `compare-jit.txt`). The translator changes what the interpreter fetches,
so the measure of work is one that does not depend on who runs the code: the
guest's writes to conventional memory a second, counted by a tap on the
memory. Thirty seconds each, the same thirty of the same boot.

| workload | writes a second | with `JIT=ON` | | where the time goes with it: interpreter / translated code / its run-time routines / translator / video |
| --- | ---: | ---: | ---: | --- |
| Keen 1 decompressing its graphics | 44,526 | 119,718 | **2.69x** | 0.8% (was 96.6%) / 60.1% / 38.3% / 0.0% / 0.1% |
| GW-BASIC, a `FOR` loop of floating point | 31,544 | 83,807 | **2.66x** | 15.3% (was 95.3%) / 48.6% / 35.0% / 0.0% / 0.1% |
| Larry 2, the title's animation | 38,849 | 56,555 | **1.46x** | 44.2% (was 93.8%) / 18.9% / 24.8% / 7.0% / 2.6% |
| Thexder on a Tandy, its demo | 15,548 | 21,096 | **1.36x** | 4.1% (was 79.0%) / 43.6% / 26.8% / 0.6% / 21.5% (was 14.5%) |
| Arkanoid on a Tandy, its demo | 23,444 | 26,517 | 1.13x | 6.4% (was 65.2%) / 16.2% / 29.6% / 0.3% / 46.0% (was 31.2%) |

- **Keen's start and BASIC** are the interpreter's own kind of work, and
  nearly all of it is translated. What is left of the time is the stack
  (`h_push`, `h_pop`, `h_retf`: 23% of Keen's) and the dispatcher's looks
  for returns.
- **Larry 2** has more warm code than the cache holds: 3709 pieces made
  and the cache emptied eighteen times in the four minutes before the
  window was over, 25 pieces a second made in it, and each time the
  interpreter has run, the pieces compare their bytes (12% of the time).
  It is the case the 62K is too small for.
- **Thexder** is a fifth video now, and its demo takes a different course
  from run to run (M6.2), so its figure is the least exact.
- **Arkanoid** waits for its timer: the translator takes its processor
  time from 65% to 52% and the screen takes the rest. No faster to play.
- The model of M6.2 said 1.9x to 3.5x for the interpreter-bound four at
  25 native cycles an instruction. Keen and BASIC are in it; a translated
  instruction costs some 45 cycles there with its share of the helpers,
  not 25. Larry 2 and Thexder are under it, for the cache and for the
  screen.
- FreeDOS booting from the folder to the end of `make test-share BOOT=1`:
  17,288 frames without, 17,565 and 16,870 with (two builds): no
  difference that the test can show.
- Without `JIT=ON` the interpreter is where it was: `make bench` reg
  28,150 IPS (28,200 before), mem 22,547 (22,700), jmp 33,971 (33,900) at
  stock speed; the slot's one more `JMP` is all that a run without the
  translator executes of this.
- Not measured: stock speed, a real IIGS, the time a translation takes
  out of a game's frame (about 500 cycles a guest instruction was M6.1's
  figure for a simpler translator; the pieces here are made at two a
  second in Thexder's demo once it has warmed up).

Tests on the build measured, all with the translator on: `jit_fuzz.py
--micro` (215 loops) and seeds 1 to 4, the micro run under
`XTGS_LAYOUT=alt`, `XTGS_JIT=1` with `make test-com` (also `strrep` and
`fileops` under `XTGS_FRONT=s16`), `test-share` and `test-share BOOT=1`,
`test-control` (a state saved and restored), `test-mouse`, `test-xms`,
`test-clock DOS=1` and `test-minix ZIP=1`. Without it: the same list,
`test-layout`, `test-s16`, `test-release`, and the three sweeps (E4, E5 and
ED the only failures, as before).

## What it does not do, and what is left

- **Flags at a piece's end.** Everything is read outside a piece, so the
  last instruction that sets flags before each way out stores them the
  lazy way (some 40 cycles), though the code it goes to nearly always sets
  them again first. To leave that out the piece must know the piece it goes
  to and die with it; nothing of that is built.
- **A store costs more than a read.** A read is fetched through the
  segment's base; a store still goes through the pointer routine and its
  look at `bk_code`.
- **The interpreter is not watched.** Whenever it has run by itself, every
  piece compares its bytes before it runs again: some 600 to 1200 cycles a
  piece. A program that leaves translated code often (code the translator
  will not take, a cache that keeps filling) pays that every time. The
  report's line "the epoch went on" is the count.
- **62K of cache.** A piece is its stub and record (some 55 bytes) and some
  18 bytes an instruction; about 300 pieces fit. A program with more warm
  code than that empties the cache again and again (Larry 2: fifteen times
  in four minutes), and after the fourth time an address has to be asked
  for sixteen times, not four, before it gets a piece. Two cache banks
  would need links across banks.
- **Pieces of code that is gone** stay until a store lands in them or the
  cache is emptied: a program loaded where another was pays the walks.
- Far calls and returns to another CS, `INT`, `REP` and the port
  instructions are the interpreter's, one instruction each time; a
  hypercall other than the timer's, the keyboard's and the clock's puts
  the epoch on.
- Not run on a real IIGS. The run-time routines patch code in their own
  bank and the core patches three of its own jumps; nothing here depends on
  the accelerator, but none of it has met one.
