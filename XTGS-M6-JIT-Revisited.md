# XT/GS — M6 Revisited: Selective Dynamic Recompilation

## Objective

Reopen M6 as an experimental, opt-in accelerator for hot guest execution regions, particularly sustained DOS gameplay. Do not replace the existing 8088 interpreter or optimize primarily for FreeDOS boot. The interpreter remains the correctness reference, default engine, and fallback.

The goal is a repeatable improvement on real workloads on 16 MHz Apple IIGS accelerators, with additional measurements on stock hardware and 48 MHz AppleSqueezer where available. No release should depend on the JIT succeeding.

## 1. Prior work and evidence

The original M6 spike (`src/core/jit.s`, monitor command `J`) hand-translated benchmark loops. The subsequent runtime translator (`src/core/jit2.s`, command `K`) generated native 65816 code in bank $06, used a direct-mapped guest linear-IP block map, and supported a limited subset of register ALU instructions and branches. The interpreter baseline is command `B`. Reproduce using `make`, `tools/bench.py`, and `python3 -I tools/jit_spike.py` as appropriate; inspect the current tree before assuming these interfaces still exist.

| Benchmark | Hand-translated ceiling | Runtime JIT, unlinked | Runtime JIT, self-loop linked |
|---|---:|---:|---:|
| `reg` | 22.4x | 2.62x | 18.93x |
| `jmp` | 28.2x | 1.22x | 1.22x |
| `mem` | 6.7x | 0.52x | 0.52x |

These are stock-clock measurements relative to the interpreter, not end-to-end game speedups. Hand translations are ceilings for those specific loops, not general performance targets. The runtime translator's flag elision was correct for the benchmark loops only, not arbitrary guest code.

The original FreeDOS boot profile measured 3.33 instructions per basic block, 30% control transfers, 28% memory forms among ModR/M instructions, 7.2% segment loads, 2.5% prefixes, and approximately 10.5% hard fallback instructions. Its estimated no-overhead Amdahl ceiling was approximately 6.3x under a roughly equal interpreter cost per guest instruction assumption. The actual transition overhead invalidated the initial expectation of a 2–4x boot speedup. No full boot-capable translator was demonstrated.

Interpretation:

- Native code generation can be highly profitable: self-loop linking recovered most of the register-loop ceiling.
- `jmp` exposes the cost of repeatedly crossing basic-block boundaries; the existing self-loop optimization cannot link its distinct blocks.
- `mem` measures repeated fallback overhead, not the speed of translated memory operands.
- FreeDOS boot is a useful regression and negative-control workload, but not sufficient evidence about sustained gameplay.
- Whether games contain sufficiently profitable hot regions is a hypothesis to test, not an established fact.

## 2. Design principles and non-goals

- Preserve the shipped interpreter and its existing CPU, BIOS, video and I/O semantics.
- Prefer cheap template emission and small bounded analyses over a general-purpose optimizing compiler.
- Admit regions selectively; unsupported or unprofitable code stays interpreted without repeatedly attempting compilation.
- Avoid per-block dispatcher round trips inside linked regions.
- Treat guest timing, interrupts, flags, segmented addressing and self-modifying code as correctness requirements, not optional optimizations.
- Keep experimental code isolated behind build/runtime switches. Preserve original benchmark results and maintain a clean rollback path.
- Do not pursue comprehensive opcode coverage, persistent compiled-code caches, whole-program compilation or title-specific patches unless later data justifies them.

## 3. M6.1 — Recover the inter-block linking opportunity

Start by inspecting the existing M6 sources and repository history. If removed, recover the old implementation on an experimental branch rather than rewriting it. Reproduce the original three benchmarks with identical workloads, clock settings and measurement methodology; record any deviations from the historical baseline.

Implement general direct-edge linking for the existing supported opcode subset:

- Emit patchable exits for statically known taken and fall-through targets.
- On first encounter, resolve/translate the target through a slow path. Backpatch the edge once a compatible native entry exists.
- For the initial benchmark-only prototype, use one code bank and local absolute `JMP` where appropriate; conditional branches can select a patchable jump using an inverted short branch. Do not assume arbitrary targets are within relative-branch range.
- Preserve guest state and flag assumptions at entry/exit. Do not link incompatible entry contracts.
- Bound execution with a guest-time/instruction budget and ensure exits at appropriate guest interrupt boundaries. Benchmark-only shortcuts must be explicitly isolated and never enabled for general execution.
- Initially reset the whole cache between benchmark runs; do not implement partial eviction just to prove the linking concept.

Rerun `reg`, `jmp`, and `mem` using interpreter, original JIT, and linked JIT. Measure warm execution separately from cold compilation. Count dispatcher entries, direct edges taken, compiled bytes, and compile cost where feasible.

**Gate A:** `jmp` should show a substantial gain over 1.22x and approach a meaningful fraction of its 28.2x hand-translated ceiling; a provisional target is at least 5x over interpreter, with `reg` retaining most of its previous 18.93x result under comparable benchmark-only conditions. These are proposed engineering targets, not predictions. If linking fails, inspect cycle costs and generated code before expanding coverage. Report separately the cost of correctness safeguards.

## 4. M6.2 — Profile real gameplay before broadening the translator

Instrument the interpreter in a separate profiling build. Prefer host-side collection via the existing MAME harness when feasible; avoid permanent expensive profiling in the release execution loop. Use reproducible inputs, fixed gameplay intervals and a warm-up period. Profile startup separately from active gameplay and idle/menu periods.

Suggested workloads (subject to available test images and compatibility): Commander Keen, a representative CGA game, a distinct EGA workload, a DOS application, and FreeDOS boot as control. Select actual titles after reviewing the existing test corpus. Record game/version, scene, input sequence, configuration, guest clock/timing mode and host accelerator.

Capture:

- Guest CS:IP and physical fetch address, execution counts, basic-block lengths and hot edge frequencies.
- Interpreter time/cycles by block or region (or calibrated handler-cost estimates, clearly labeled); opcode counts alone are insufficient.
- Top 32/64/256 blocks and their cumulative share of CPU-emulation time; identify strongly connected hot regions and loop trip counts.
- Existing JIT opcode eligibility, unsupported instructions, memory forms, flag producer/consumer chains, segment stability, effective-address patterns, and guest writes overlapping fetched code.
- Time spent in CPU interpretation versus video conversion/blitting, audio, disk, BIOS and other host services.
- Interrupt frequency and exit opportunities; distinguish polling/idle loops from useful computation.

Produce a report listing candidate regions with entry points, representative disassembly, hot edges, estimated coverage, likely native cost and required new opcode support. Estimate speedup with measured time shares, not instruction shares. If instrumentation distorts timing, use a separate uninstrumented baseline and explain the methodology.

**Gate B:** Identify at least one recurring real-game workload with sufficient eligible CPU time to justify a selective compiler. For example, 50% of CPU-emulation time at 10x regional acceleration has an ideal CPU-only ceiling of 1.82x. If the hottest time is mostly video or unsupported memory operations, prioritize that bottleneck instead.

## 5. M6.3 — Interpreter-led admission and region execution

The interpreter owns execution. The JIT is a service it calls for eligible regions, not an alternative main loop that repeatedly single-steps unsupported instructions.

Suggested architecture:

```text
Interpreter
  -> cheap hot-entry detection / cached entry lookup
  -> eligible and compiled? enter native region
  -> hot but not compiled? bounded analysis and compilation
  -> unsupported / unprofitable? interpret; cache rejection
Native region
  -> direct internal edges
  -> bounded execution / interrupt / invalidation / side exit
  -> reconstruct exact guest state and resume interpreter
```

- Consider sampling or saturating counters at backward branches instead of hashing every guest instruction. Measure the cold-path tax.
- Compile only after sufficient reuse is demonstrated; bound region size, compilation work and code-cache allocation.
- Negative-cache unsupported or unprofitable entries; retry only on relevant code/context change or deliberate policy change.
- End a region before an unsupported instruction. Resume the interpreter at that instruction, without immediately attempting to re-enter the JIT unless a separately admitted entry is encountered.
- Prefer small cyclic regions with known direct edges. Initially use memory-backed guest registers and a canonical entry contract; do not add native register allocation until measurements justify it.
- Track entry/exit counts, region execution length, rejected regions, cache hit rates, compile cost and eviction frequency. Use hysteresis or disable regions that repeatedly side-exit before earning back their cost.

A simple cost model: compile only when expected future savings exceed compilation, entry/exit, guards and maintenance costs. Retain a conservative margin and tune thresholds empirically rather than hardcoding assumptions from the microbenchmarks.

## 6. M6.4 — Correctness substrate (required before arbitrary guest execution)

Develop this alongside M6.3; real-game JIT execution is gated on it. Benchmark-only unsafe shortcuts are not acceptable in gameplay.

### Guest state and flags

- Define an explicit canonical guest state and host ABI: registers, CS:IP, segment values/bases, FLAGS, cycle/timing state, 65816 M/X widths, direct page, data bank and stack assumptions.
- Track flag liveness per flag, not as a single FLAGS value. INC/DEC preserve CF; TEST and logical operations have different semantics from arithmetic; subtraction carry/borrow conventions differ. Follow the interpreter's established behavior for undefined flags.
- Reuse native N/V/Z/C only when mathematically equivalent and not clobbered by intervening code. Calculate PF/AF and other guest flags when required, or use a validated lazy representation with all necessary operands/results.
- At every observable boundary (including interrupts, fallback, side exits, PUSHF/LAHF and other flag consumers), ensure the correct flags and guest IP can be reconstructed. A flag is dead only if no reachable observer can consume it before it is overwritten.
- Initially prefer canonical flags at external region exits. Cross-block flag elision inside a region is a later optimization, subject to precise side-exit and interrupt semantics.

### Addressing and code identity

- Preserve 8088 segment:offset semantics, 16-bit offset wrap, 20-bit physical address behavior and the interpreter's handling of accesses spanning boundaries.
- Linear fetch address alone is not necessarily sufficient as a block key: aliased CS:IP pairs can differ in IP-relative and segment-sensitive semantics. Use CS:IP plus any specialization context required, or prove a more compact key safe.
- Initially load dynamic segment bases from canonical guest state; only specialize stable bases with guards or a validated key. Segment-register changes must not leave stale assumptions.
- Preserve memory map and video/ROM/I/O side effects. Do not assume that all guest RAM addresses map to contiguous host RAM.

### Self-modifying code and cache lifecycle

- Track all guest physical pages covering each translated region, including blocks crossing page boundaries and segment aliases.
- Audit every guest-memory write path (interpreter, generated code, BIOS/device helpers, disk transfers, bulk/string operations, and any other direct writes).
- A coarse page bitmap or generation scheme is a reasonable first design. On a write overlapping translated pages, invalidate affected code and links. A whole-cache flush is acceptable initially if measured costs are tolerable.
- If a write can affect the currently executing region, force an exit before executing any potentially stale translated instruction. Do not defer invalidation until an arbitrary region exit.
- Never reuse native cache storage while any reachable patched edge still targets it. Initially use whole-cache reset with execution stopped; add finer eviction only if needed.
- Measure write-path overhead even with no active JIT regions. Honor actual host executable-memory/cache requirements on supported accelerators.

### Interrupts and timing

- Use the interpreter's existing guest timing model as the reference; do not equate host elapsed cycles with guest cycles.
- Maintain guest instruction/cycle accounting and bounded execution across native backedges. Service pending interrupts at architecturally valid boundaries, including interrupt inhibition semantics, trap/single-step behavior and other existing timing constraints.
- If precise delivery cannot be guaranteed within a candidate region, reject it or insert appropriate checks; polling only once per region is not automatically correct.
- Ensure host interrupts, scheduler callbacks and native code emission/patching cannot corrupt execution state or expose partially emitted code.

## 7. M6.5 — Expand coverage only from profile evidence

For each candidate opcode or addressing-mode extension, document the hot regions it unlocks and measure the incremental improvement. Do not implement the whole 8088 ISA again.

Potential priorities, to be reordered by actual profiles:

1. Register MOV and common 8/16-bit ALU forms; relevant conditional branches.
2. Frequent memory ModR/M forms, especially register-indirect accesses with stable segment bases. Use existing memory helpers where necessary; inline safe RAM fast paths only with appropriate guards.
3. Common near transfers and stack operations if they unlock recurring regions without excessive state overhead.
4. Native register retention across several instructions or blocks, with precise writeback and side exits.
5. Cross-block per-flag liveness and redundant load/store elimination.
6. Hot string/copy/fill operations and pixel loops. Evaluate interpreter-native fast handlers versus generated code first. `MVN`/`MVP` are possible only when bank, direction, wrap, overlap, timing, flags and memory-side-effect semantics are preserved.

Keep unsupported instructions in the interpreter. Complex I/O, far transfers, interrupt instructions and unusual prefixes need not be translated merely to improve coverage statistics.

## 8. M6.6 — Differential testing and real-workload benchmarking

Use existing CPU tests and add targeted tests. Compare interpreter and JIT from identical guest states with deterministic interrupt/device inputs. Verify at every external region exit and selected internal boundaries in a diagnostic build; compare guest registers, FLAGS, CS:IP, memory changes and relevant device/timing state. Include randomized operands and control-flow paths for supported templates. Avoid comparing only final benchmark register values.

Required adversarial cases include:

- Taken and untaken branches, multi-block loops, side exits, live flags across edges, carry/borrow, parity and auxiliary carry, partial register updates.
- Segment aliases, segment changes, offset/physical wrapping, page/bank boundaries, stack accesses, RAM versus video/ROM paths.
- Self-modifying writes from native and interpreted code, external helper writes, active-region invalidation, cache reset and stale-edge prevention.
- Interrupts during long-running loops, interrupt inhibition, TF behavior, fallback and timing-sensitive polling.
- Repeated compilation failures, full cache, eviction/reset, and JIT disable/re-enable.

Benchmark matrix:

| Mode | Purpose |
|---|---|
| Interpreter, JIT compiled out | Shipped baseline |
| Interpreter, JIT present but disabled | Isolation/regression |
| Profiling enabled | Identify measurement overhead |
| Selective JIT, cold cache | Real startup/amortization cost |
| Selective JIT, warm cache | Sustained throughput |

Test stock clock and 16 MHz configurations using the existing emulator methodology; test 48 MHz hardware and actual 16 MHz hardware where available. Clearly label modeled/emulated versus physical hardware results. Record guest IPS, useful gameplay progression per wall-clock second, frame time/FPS where meaningful, CPU versus display time, compile stalls, cache footprint and variance across at least three comparable runs. Avoid claiming speedup from bypassed guest timing, dropped frames or changed game behavior. Preserve configured timing policies; measure headroom separately if guest speed is capped.

## 9. Proposed acceptance and stop criteria

These are new proposed gates; adjust after baseline measurements and document the reason for changes.

- No CPU-test regressions or known correctness failures in admitted regions. Interpreter remains the default until correctness review and real-workload validation are complete.
- JIT disabled: no meaningful regression versus the shipped interpreter (target within 2% measurement noise/overhead); measure rather than assume.
- JIT enabled but workload rejected: aim for no more than 5% slowdown after warm-up, including admission and invalidation checks.
- At least two representative gameplay workloads demonstrate repeatable end-to-end useful-work improvement, with a provisional target of >=25% on 16 MHz. Report CPU-only gains separately. A stronger target is >=1.5x on a favorable workload.
- FreeDOS still boots and runs correctly; faster boot is not required. No persistent fallback churn during boot.
- Document memory budget, worst-case compile pauses, and behavior under cache pressure. Reject or disable the feature on configurations that cannot support it safely.

If linked microbenchmarks fail Gate A, stop and diagnose. If real gameplay fails Gate B, stop expanding the JIT and optimize the dominant interpreter/video bottleneck instead. If only one class of loop benefits, consider a narrowly scoped fast path or superinstruction rather than maintaining a general compiler. Do not ship merely because microbenchmarks improve.

## 10. Alternative experiments if full native regions are not worthwhile

- Cached decoded operands / direct-threaded or specialized dispatch, subject to invalidation requirements.
- Profile-selected superinstructions such as compare/conditional-branch and decrement/conditional-branch pairs; preserve intermediate observable state where required.
- Hand-optimized interpreter string or memory-copy/fill handlers.
- Host-side, offline translation of benchmark regions as a feasibility oracle; not a requirement for distributing or running games.

Compare these alternatives against selective JIT on the same workloads and memory budget.

## 11. Deliverables and execution order

1. Experimental branch, recovered M6 baseline and reproducible measurement log.
2. General inter-block linking prototype and Gate A results.
3. Gameplay profiling harness, representative traces and Gate B report.
4. Selective admission design, correctness substrate, and differential tests before general guest execution.
5. Minimal profile-driven opcode/region extensions and measured optimization increments.
6. Final benchmark matrix, memory/latency costs, known limitations, and ship/retain/discard recommendation.

Update the existing M6 documentation rather than erasing its negative result. Keep each stage independently reviewable and commit the benchmark harness/results with the implementation. Record actual cycle measurements, generated native disassembly and reasons for rejected regions.

### Initial instruction to the implementing agent

Begin with M6.1 only: inspect the current repository, recover the historical translator if necessary, reproduce the baseline, and implement the smallest general direct-edge linking experiment that can accelerate `jmp`. Do not expand opcode coverage or change the shipped interpreter during this experiment. Report the measurements and explain any difference between generated code and the hand-translated ceiling. Then proceed to gameplay profiling; defer the production region compiler until the two feasibility gates are met.

## Source and scope

Historical measurements and implementation details are from the original **M6: dynamic translation (JIT)** experiment report supplied by the XT/GS author. All new phases, thresholds, architecture recommendations and correctness requirements in this document are proposed follow-up work, not claims of completed implementation or measured gameplay gains.
