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

So the next candidates were the string instructions without `REP` or outside
the `MVN` case, which worked out both host pointers for every element, and
the count in `next`: the next section.

## Two more: the slot count and the string instructions (2026-11-10)

The two candidates the profile above named, in the order they were done,
stock clock (`strs` is a new program, below; the whole SingleStepTests sweep
was run after the second, with the same 173 failures):

| | reg IPS | mem IPS | jmp IPS | strs IPS | FreeDOS from the folder |
|---|---:|---:|---:|---:|---:|
| after the four changes | 26,501 | 21,353 | 32,244 | 4,774 | 90.3 s |
| 5. the slot counted on control transfers | 28,251 | 22,664 | 33,913 | | 87.2 s |
| 6. the string instructions | 28,238 | 22,664 | 33,913 | 15,635 | 72.9 s |

5. **The slot count.** Every instruction used to retire through `next`,
   `dec vSLOT / bne fetch`, so that the interrupt lines and the frame's work
   were looked at every `SLOT_N` instructions. The retire vector is now
   `fetch` itself, and only what can close a loop counts: a taken jump, a
   call, a return, `LOOP`, `INT`, `IRET`, a `REP` string instruction, the
   hypercall and `HLT` retire through `next_ct` (three lines, inline in the
   common ones), and the slot runs every fourth of them. Straight-line code
   pays nothing. `STI` with an interrupt waiting makes the instruction after
   it retire through the slot (`next_owed`), as the 8086 does.
6. **The string instructions** (`src/core/ops_str.s`). Each element used to
   be a call that worked out both host pointers from the segment bases,
   with or without `REP`; `MVN` was taken only by a `REP MOVSW` that stayed
   inside one 64K block. Counted over a FreeDOS boot from the folder:

   | | alone | under `REP` | elements under `REP` |
   |---|---:|---:|---:|
   | `MOVSB` | 17,846 | 13,638 | 99,037 (7.3 a run) |
   | `MOVSW` | 30 | 781 | 83,241 (8 runs hold 77,851) |
   | `STOSB` | 155 | 4 | 364 |
   | `STOSW` | 0 | 55 | 17,309 |
   | `LODSB` | 1,863 | 0 | |
   | `SCASB` | 0 | 226 | 1,526 |
   | `CMPSB` | 0 | 18 | 66 |

   So the work is in short `REP MOVSB` runs, `MOVSB` alone and a few long
   `REP MOVSW` runs that cross a block's end. Now an instruction alone adds
   the offset to the segment's base once for each pointer (the bank word
   worked out only when that add carries) and tests DF once; under `REP`,
   `MOVS` is `MVN` or `MVP` and `STOS` an overlapping `MVN`, in runs that
   end where SI, DI or either host pointer would wrap, with the old element
   routine for a word that lies across a wrap; `REPE`/`REPNE` `SCASB` and
   `CMPSB` are loops on `[ptr],y`. The rest (`LODS` under `REP`, the word
   compares, DF set for a fill or a compare) still go an element at a time.

`tests/com/strrep.asm` was written for this: 211 cases of every string
instruction, alone and under `REP`, each run twice from the same memory, as
the instruction and by a routine of ordinary instructions, then eight long
runs and five strips of the text screen. Three faults of the old code came
out of the work, none of which a SingleStepTests vector or a boot had shown.
The test fails the old core on the first two; the counts above showed the
third.

- `REP MOVSW` upwards with the destination one byte above the source went
  to `MVN`, which is a byte move: every byte became the first, where the
  8086 moves words (cases 101 and 109).
- The `MVN` path marked only the first 256-byte page of a run into the text
  buffer, so a scroll done with one `REP MOVSW` could leave rows undrawn
  until something else touched them (160 cells of the test's strips).
- `REP MOVSB` never took `MVN`: the test for it read the Z flag of the
  wrong load. Correct, and slow.

From power-on the test takes 111 emulated seconds on the old core and 74 on
the new.

CORE is 49 KB of its bank. Emulated seconds from power-on at the stock
clock, before the two and after: FreeDOS from the folder to FreeCOM's date
prompt 90.3 -> 72.9; from the floppy image 138 -> 113.7; Minix to its shell 303 -> 264 (16 MHz: 39 -> 35).
PC samples of the FreeDOS boot from the folder, one a frame, now:

| where | share |
|---|---:|
| `fetch` | 14% |
| bank `$00` and the ROM: firmware and ProDOS (file reads, interrupts) | 14% |
| string instructions | 5% (was 17%) |
| `push16`/`pop16` | 5% |
| `jcc_taken` (with its count) | 4.5% |
| the slot (`next_due`, `slot`) | 2.4% |
| SVC (the text screen, mostly) | 7% |
| everything else, no routine over 4% | 48% |

## The EGA's trap (2026-11-10)

Mode 0Dh (docs/ega.md) added a compare of the operand's bank to every
effective-address tail, where the text bank's compare was already. With
the mode off the five programs measure what they did before it: stock
28,251 / 22,592 / 33,913 / 196,608 / 15,641 IPS for `reg`, `mem`, `jmp`,
`str` and `strs`. What an access to the planes costs in the mode is in
docs/ega.md.

## The slot's look, a string instruction alone, the stack's carry (2026-11-24)

The profiles of real programs (docs/jit.md, "M6 revisited") showed three
costs that every program pays and no benchmark here had measured, because
the benchmarks run with no PC behind them.

- **The slot.** Every fourth control transfer it looked at each interrupt
  line in turn: five long loads and their tests, about 130 cycles a look,
  3.5% to 7.5% of all time in a running program. Now the lines other than
  IRQ0 are behind one word, `PIC_PEND`, which whoever raises a line sets,
  and a look that finds it clear (and no IRQ0 owed) goes straight to the
  vertical blank's test. `irq_owed`, which `IRET`, `POPF` and `STI` call,
  takes the same short way. The count the slot keeps for `B` is of slots
  now, an `INC`, made into transfers at the end.
- **`MOVS`, `STOS` and `LODS` without `REP`.** A destination in the text
  buffer's bank (a Tandy's or a CGA's screen) was worked out twice, once
  inline and once more by `str_dst` on the way to marking its page, and so
  was any pointer whose add carried into the next bank. Both are finished
  on the spot now, the word forms' test for offset `$FFFF` is the load the
  add uses, and the pointers step by a load and a store.
- **The stack's carry.** A push or a pop whose `SS:SP` add carries into the
  next host bank called `stk_carry` for three instructions; a stack that
  sits across a bank's end takes that path every time (10% of Keen's start
  was pushes and pops). They are inline, in `push16`/`pop16` and in the
  generated `PUSH`/`POP r16`.

Measured on the real workloads of docs/jit.md at 16 MHz (`tools/jit_profile.py
compare`: the interpreter's cycles for the same guest instructions, weighted
as the earlier run executed them, the slot's share with them; instructions
a second agree where the program does the same thing in both runs):

| workload | faster by | the slot's share of all time |
|---|---:|---|
| Commander Keen 1 decompressing its graphics | 4.0% | 4.4% -> 2.7% |
| GW-BASIC's arithmetic loop | 4.5% | 7.1% -> 4.2% |
| FreeDOS booting | 3.1% | 7.1% -> 4.5% |
| FreeDOS's shell at its prompt | 3.2% | 7.5% -> 4.9% |
| Thexder, CGA | 5.6% | 5.1% -> 3.2% |
| Thexder, Tandy | 6.9% | 6.4% -> 4.2% |
| Arkanoid, Tandy | 2.7% | 1.9% -> 1.4% |

Thexder's demo does not take the same course twice (it depends on the tick
count the machine starts with and on a cycle here or there), so its row
compares two runs that happened to take the same one; the first four rows
are programs that do exactly the same work every run. The gain is small
because most of what the slot does is still there: the count, the test of
the vertical blank, the way in from `next_ct`.

## Three video paths (2026-11-24)

Three of the profiled games spent more of the machine on video than on the
8088 (docs/jit.md, "Where the time goes"). What was changed, and what the
same 30 seconds of each look like before and after at 16 MHz
(`tools/jit_profile.py compare`; the guest's instructions a second, which
for these programs is how fast the game runs):

| workload | what it was doing | video's share | instructions a second |
|---|---|---|---:|
| Arkanoid, Tandy | shows two pages, draws two others, changes them over 14 times a second: four 16K moves and a whole screen each time | 69% -> 30% | 40,800 -> 98,900 (2.4x) |
| Commander Keen 1, its title | draws each picture in a part of the EGA's planes that is not shown, then moves the start address there: a whole screen converted each time | 58% -> 41% | 34,900 -> 47,700 (1.37x) |
| Thexder, CGA | redraws most of a mode 4 screen every frame: 52 cycles a byte of it | 38% -> 32% | 98,400 -> 108,600 (1.10x) |

- **The Tandy's pages** (docs/tandy.md, "The pages have homes"): a page
  goes home with only the 256s that were written, comes back compared in
  the 256s that may differ, and the screen is drawn where the two pairs
  differ.
- **The EGA's start address** (docs/ega.md, "The window on a wider
  buffer"): a line is drawn when it is not the same where the screen was
  and where it is now. Lines are done whole, through the stack, and an odd
  pan is a one-bit shift where it was a loop.
- **The CGA's line** (`gfx_blit_line`): the source by `Y` and the
  destination's pointer stepped once a byte, 38 cycles where there were 52.

What is left in each: Arkanoid's 17% is the copying and comparing of the
256s it draws in, twice a picture; Keen's 24% is the comparing of 200
lines a picture, which knowing what was written in the hidden part would
mostly save; Thexder's 30% is still the blit, which only a faster way to
put bytes on the SHR would change. On a IIGS itself the SHR is slow
memory, about a microsecond a byte whatever the accelerator, so there the
drawing that was avoided is worth more than these figures say.

## Throughput

MAME 0.284 `apple2gs` (ROM 03), 8 MB, stock 2.8 MHz and the ZipGS 16 MHz
setting. OUTER=4 (65,536 iterations a loop).

| program | what an iteration is | instructions | stock IPS | Zip 16 MHz IPS |
|---|---|---:|---:|---:|
| reg | `add ax,bx / sub bx,1 / dec cx / jnz` | 1,048,576 | 28,200 | 158,100 |
| mem | `add [bx],ax / mov ax,[si+2] / mov [bx+4],ax / dec cx / jnz` | 1,310,720 | 22,700 | 126,600 |
| jmp | `test cx,1 / jz / inc ax / dec cx / jnz` | 1,310,720 | 33,900 | 189,500 |
| str | `rep movsw` of 16 KB (`MVN`) | 32,768 | **197,000-218,000** | (a frame or two) |
| strs | short string instructions, as a DOS kernel's: `rep movsb` of 7, `lodsb`/`stosb` twice, `rep movsw` of 16, `repne scasb` of 8, `rep stosw` of 32, and the loop | 655,360 | 15,600 | 87,400 |

(`str` runs for nine or ten frames at the stock clock, so its figure moves by
a frame from run to run, and at 16 MHz it is over in one or two. `strs`
counts a `REP` instruction as one: 20 instructions an iteration, 9 of them
string instructions on 115 bytes; before the string instructions were
rewritten it read 4,800 / 26,700.) Before any of the six changes above the
first three rows read 15,600 / 87,100, 15,300 / 85,200 and 23,000 / 128,500.

The MVN fast path made `REP MOVSW` 23x faster (was 9,400 / 53,000 IPS). It
helps memory copies and screen scrolls.

Reading the compute rows: a stock IIGS retires a register instruction every
~100 65816 cycles and one with a memory operand every ~125, between 1/11 and
1/13 of a 4.77 MHz 8088 on this kind of code; a 16 MHz Zip is about half an
XT on register code and 2/5 on memory operands.

## What the M5 gate asks

A DOS kernel's boot runs a few million instructions; measured, FreeDOS is at
its prompt 73 emulated seconds after a stock machine starts it from a folder
(above). The plan's own gate (is a measured speed sufficient to pursue a full
boot) was met at 15,600 IPS for an accelerated machine, and the boot has been
done since (`docs/mode-b.md`, `docs/share.md`).

## With the translator (2026-11-24)

`JIT=ON` (docs/jit.md, "M6.3 and M6.4") is measured by the guest's writes a
second, on a 16 MHz ZipGS in MAME: Keen 1's start 2.69x, a GW-BASIC `FOR`
loop 2.66x, Larry 2's title 1.46x, Thexder on a Tandy 1.36x, Arkanoid 1.13x
(it waits for its timer). The numbers above are without it and have not
moved (reg 28,150, mem 22,547, jmp 33,971 IPS at stock speed).
