# XT/GS — M9: Optional 8087 Numeric Coprocessor

## Engineering handoff for Claude

### Objective

Implement an optional Intel 8087-compatible numeric coprocessor for XT/GS, using the Apple IIGS Standard Apple Numerics Environment (SANE) as the native arithmetic backend wherever its semantics match. The primary goals are compatibility with original XT-era coprocessor software and measurable acceleration over guest software floating point. Preserve the existing interpreter, JIT Turbofan, and M7 snapshot boot behavior when the option is disabled.

This is not a request to emulate a modern x87, implement an FPU from scratch, or reproduce asynchronous 8087 bus timing. Begin with a performance and semantic feasibility spike; do not commit to full coverage until the results are understood.

## 1. Context and architectural constraints

- Guest CPU: 8088; host CPU: 65816, including stock 2.8 MHz, 16 MHz ZipGS and faster accelerators.
- XT/GS already has an interpreter, optional selective native JIT, BIOS interception and machine-state serialization.
- The recent GW-BASIC floating-point workload improved 2.66x with JIT enabled. This is a useful software-floating-point baseline, but GW-BASIC's usual Microsoft Binary Format arithmetic is not an 8087 workload and should not be expected to accelerate merely by enabling M9.
- Use the documented SANE Tool Set ($0A), FP816 and, where appropriate, Elems interfaces. Verify actual tool availability, initialization, ABI, operand layout, environment handling and ROM/tool version on supported configurations before coding. Do not hardcode ROM entry addresses.
- The guest and host both have extended-precision formats, but do not assume identical byte layout, NaN encoding, unsupported encodings, denormal behavior, exception handling or precision-control semantics. Verify these against primary manuals and reference tests.
- Prefer standard Toolbox dispatch so that compatible host-side SANE patches or hardware accelerators can be inherited. Such acceleration is optional and unverified; no hardware card is required.

## 2. Configuration and scope

Proposed configuration:

```ini
FPU=8087
JIT=ON
```

Absence of `FPU` (or `FPU=OFF`) preserves the existing machine behavior. Reject unknown values clearly. Advertise the coprocessor through the BIOS equipment word (BDA 0040:0010, bit 1; ensure INT 11h is consistent). Verify actual XT/8087 detection sequences, including FNINIT/FNSTSW and WAIT behavior, rather than relying solely on the BIOS bit.

The first implementation executes numeric instructions synchronously at guest instruction boundaries. Document timing limitations, including lack of true coprocessor overlap, BUSY timing and asynchronous exception behavior. Do not claim full 8087 compatibility until the corresponding conformance tests pass.

## 3. M9.1 — Feasibility and performance spike

Before modifying the guest decoder, build a small native SANE test harness using the project's existing assembly/toolbox conventions.

1. Verify startup/shutdown and calling conventions on the supported GS/OS runtime; measure setup separately from steady-state calls.
2. Test extended add, subtract, multiply, divide, square root, compare and conversions to/from single, double and signed integer formats.
3. Establish a canonical guest 10-byte extended encoding and test conversion to/from SANE using known bit patterns: signed zero, one, negative values, extrema, subnormals, infinities and NaNs. Record any unrepresentable encodings.
4. Measure cycles per operation including Toolbox dispatch, operand conversion, register addressing and environment save/restore. Test both repeated identical environments and changing rounding modes.
5. Compare a fixed-work DOS floating-point program built for software arithmetic and 8087 arithmetic, first estimating the latter using the measured backend costs. Use Turbo Pascal 5.5 (`{$N-}` / `{$N+}`) or another verified 8088-compatible compiler; verify that the binary actually emits the desired ESC instructions. Avoid conflating different precision or algorithm choices with speedup.
6. Use MAME at stock and 16 MHz, then physical hardware when available. Include a native arithmetic baseline and the existing interpreter/JIT software paths.

**Gate A:** demonstrate correct basic arithmetic and conversions for ordinary finite values, and either a credible performance opportunity or a specific valuable compatibility target. A proposed performance target is 1.5x fixed-work acceleration versus JIT-enabled guest software arithmetic; this is an aspirational gate, not a measured result. If SANE is slower, report the result and consider compatibility-only support before proceeding. If SANE semantics cannot be adapted safely, stop and document the gaps.

## 4. M9.2 — Guest architecture and decoder

Maintain explicit guest state independent of SANE's ambient environment:

- Eight physical 80-bit registers (80 bytes total), with logical ST(i) mapped using TOP.
- 16-bit control, status and tag words; TOP in status bits 11–13; condition bits C0–C3; sticky exception flags and pending exception state.
- Last instruction/data pointers and opcode metadata as required by the original 8087 environment format. Derive layout, reset values and update rules from the original manual, not later 387 documentation.
- Any virtual BUSY/exception-latch state required by the chosen synchronous model.

Decode D8–DF ESC instructions through the existing 8088 ModR/M and effective-address machinery; handle register and memory encodings separately. Respect segment overrides, default segments, 16-bit offset semantics and 20-bit physical wrapping exactly as required by the guest CPU and operand access rules. Audit standalone WAIT (9Bh), waiting/nonwaiting instruction pairs, and the current no-coprocessor behavior. Do not invent a modern invalid-opcode trap for unsupported original-8088 instructions.

Implement original-8087 reset and status/control access first (including FNINIT and memory forms of FNSTSW/FNSTCW). Ensure disabled mode remains unchanged. Do not implement later-only encodings such as FNSTSW AX merely because modern reference emulators accept them; identify the guest ISA explicitly.

**Gate B:** original coprocessor-detection programs correctly distinguish FPU=OFF and FPU=8087; decoder tests cover lengths, register indices, segment overrides and memory boundaries. No unrelated CPU regressions.

## 5. M9.3 — Arithmetic adapter and initial coverage

Create a small backend interface accepting guest operands and an explicit numeric environment, returning result bytes plus status/exception metadata. Keep guest stack semantics outside that interface.

### Initial instruction families

| Family | Operations to investigate/implement |
|---|---|
| Data transfer | FLD, FST, FSTP, FILD, FIST, FISTP; original supported encodings only |
| Arithmetic | FADD, FSUB, FSUBR, FMUL, FDIV, FDIVR; register, memory, integer and popping forms |
| Stack/sign | FXCH, FCHS, FABS, FFREE, FINCSTP, FDECSTP |
| Comparison | FCOM, FCOMP, FCOMPP, FTST, FXAM |
| Constants | FLD1, FLDZ and other original 8087 constant loads |
| Rounding | FRNDINT and precision/rounding control |

Build an encoding coverage matrix from original Intel documentation, with per-form tests. This table is a roadmap, not a declaration that all variants share identical semantics.

### Numeric environment

- Map guest precision control (24/53/64 significand bits where defined) and rounding direction to SANE where supported. Avoid accidental double rounding by calculating at the required precision and applying destination-format conversion at the correct architectural point.
- Save host SANE environment, establish guest environment, execute operation, collect exceptions, then restore host environment on every exit, including errors. Do not allow guest unmasked exceptions to invoke host application handlers. Consider amortizing setup only after proving isolation and measuring cost.
- Translate host exceptions into guest status; implement masked-result rules, sticky bits, C1/rounding behavior and stack/tag transitions according to original 8087 semantics. Do not assume every SANE exception maps one-to-one.
- Handle pure data movement and sign operations directly when semantically appropriate; preserve raw guest encodings where required. Verify endian conversion independently.
- Check integer overflow, signed 64-bit edge cases (including the most negative integer), and SANE Comp format differences. Never silently substitute an approximate conversion.
- Store through XT/GS's existing guest memory write paths so JIT invalidation and device semantics remain correct. Multi-byte 4/8/10-byte stores require actual write lengths and correct boundary handling; do not repeat the earlier byte-versus-word invalidation bug.

**Gate C:** differential tests for arithmetic, stack behavior, conversions, rounding and status pass for the declared subset. Unsupported instructions must produce an explicit documented outcome, not silently pretend success.

## 6. M9.4 — Transcendentals and remaining original instructions

Add only after the basic backend is stable. Investigate FSQRT, F2XM1, FYL2X, FYL2XP1, FPTAN, FPATAN, FPREM, FSCALE, FXTRACT and packed BCD operations (FBLD/FBSTP) as applicable to the original 8087.

SANE Elems may provide mathematical primitives but is not an instruction-level substitute. In particular, verify original operand domains, partial remainder iteration, quotient condition bits, stack result ordering, rounding and out-of-range behavior. Original FPTAN and FPATAN differ from later x87 conventions in important ways. Do not add FSIN, FCOS, FSINCOS, FPREM1 or other later instructions under the 8087 label.

Prefer dedicated small adapters over approximating architectural behavior with an unrelated high-level function. Where exact original transcendental results are implementation-dependent, define justified tolerances separately from exact architectural status and stack checks.

## 7. M9.5 — Exceptions, WAIT and environment instructions

Implement the original environment/control instructions, including waiting/nonwaiting forms, FSTENV/FLDENV and FSAVE/FRSTOR. Verify the original real-mode environment and full-save layouts (including pointer/opcode packing), byte order, register ordering, reset-after-save behavior and side effects on exception masks. Test round trips against a reference, not merely the emulator's own serializer.

Research how the original IBM PC/XT routes 8087 ERROR through NMI and the role of WAIT/TEST and exception clearing. Model the guest-visible path sufficiently for supported software, including pending exceptions and disabled/masked cases; do not substitute the later AT IRQ13 or modern #MF mechanism without an explicit machine-model distinction. If asynchronous timing is omitted, document exactly which exception and synchronization behaviors are supported.

**Gate D:** environment round trips, masked/unmasked exception tests, WAIT sequences and representative detection/runtime libraries work. Explicitly list remaining incompatibilities if the gate is only partially met.

## 8. M9.6 — M7 snapshots and JIT Turbofan integration

### Snapshots

Add versioned FPU state to the machine-state serializer. Include FPU configuration in snapshot compatibility checks. Save raw guest registers, tags, control/status, pointers and pending architectural state, not host SANE environment or native pointers. Reject incompatible old snapshots or provide an explicit migration; fall back to cold boot. Restore must not leak the guest numeric environment into GS/OS.

### JIT

Initially treat ESC and WAIT as interpreter boundaries. Reuse existing state reconciliation, slot scheduling and invalidation rules. Avoid adding FPU-specific checks to every normal integer instruction. Ensure translated pieces do not elide flags or reorder memory across an FPU exit incorrectly.

Profile transition costs after the interpreter implementation works. Only if material, add direct calls to shared FPU helpers from generated code, with predecoded operands and a clear native ABI. Preserve scheduling and exception exit paths, and invalidate any specialized assumptions. Avoid duplicating numeric semantics in two engines.

Test all four combinations of FPU OFF/8087 and JIT OFF/ON, including snapshot restore in each supported configuration.

## 9. M9.7 — Application validation and release gates

### Test strategy

- Use original Intel 8087 documentation as the ISA authority. Use an independently validated emulator or real 8087 hardware for differential tests where possible; later x87 emulators and SoftFloat-like arithmetic references are useful but not authoritative for original instruction semantics.
- Compare raw result encodings, stack/TOP/tags, control/status, exception behavior, pointer state and guest memory. Include directed edge cases plus reproducible randomized finite operands.
- Test all rounding directions and supported precisions, empty stack operations, underflow/overflow, divide by zero, invalid operations, denormals, NaNs/infinities, integer conversion limits and memory operands spanning guest boundaries.
- Test SANE environment isolation before and after execution and snapshot restoration, including error paths.
- Run existing CPU, JIT, video, BIOS and storage regressions with FPU disabled and enabled.

### Application benchmarks

| Workload | Purpose |
|---|---|
| Small hand-written 8087 COM test | Detection, arithmetic and architectural status |
| Turbo Pascal 5.5 numeric workload, software and 8087 builds | Fixed-work performance and correctness |
| 8088-compatible floating-point Whetstone or Mandelbrot benchmark | Repeatable compute throughput |
| Period-appropriate Fractint floating-point mode | Real application, verify CPU/FPU requirements |
| Compatible Lotus 1-2-3 version | Recalculation and runtime detection |
| Compatible AutoCAD or scientific application | Compatibility target, only if verified to support 8088/8087 |
| Existing GW-BASIC benchmark | Regression control, not expected to use the FPU |

Record exact application version, options, input, output, accelerator, emulator build, FPU/JIT configuration, elapsed wall-clock time and host cycles where available. Prefer fixed-work completion times over guest memory writes/second for numeric workloads: coprocessor instructions change the amount of guest memory traffic per unit of mathematical work. Report cold/warm timings separately and distinguish MAME from physical hardware.

### Proposed acceptance criteria

1. FPU disabled: no material regression in existing benchmarks (suggested threshold 1% or measured noise floor), and no changed BIOS detection behavior.
2. FPU enabled: declared original-8087 subset passes differential and application tests; unsupported semantics explicitly documented.
3. At least one verified application that benefits from or requires the coprocessor works correctly; demonstrate fixed-work performance against software arithmetic where comparable.
4. No host SANE state leakage, snapshot corruption, guest memory bypass, or JIT correctness regression.
5. Publish measured results separately from projected results. Keep FPU opt-in until confidence warrants reconsideration.

## 10. Deliverables and first action

Produce `docs/8087.md` documenting architecture, primary references, coverage matrix, known limitations and reproducible benchmark results; a native SANE spike harness; guest conformance tests; optional configuration and BIOS detection integration; and a snapshot-format compatibility note. Follow the repository's existing naming and test conventions rather than introducing a parallel build system.

**Start with M9.1 only.** Inspect the current XT/GS source and supported SANE interface, obtain the original Intel 8087 and Apple numerics documentation, and build a minimal native arithmetic benchmark. Return the measured operation costs, representation/exception findings, and a go/no-go recommendation before undertaking a full decoder. Compatibility may justify proceeding even when the performance hypothesis does not hold, but make that tradeoff explicit.

The desired result is a useful optional numeric coprocessor, not a synthetic benchmark victory or a claim of cycle-accurate x87 emulation.
