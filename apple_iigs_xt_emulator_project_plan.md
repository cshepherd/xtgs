# XT/GS: An 8088 PC Compatibility Environment for the Apple IIGS

**Status:** Proposal / architecture review  
**Target:** Apple IIGS with 8 MB RAM; accelerator strongly recommended  
**Implementation:** Native 65816 assembly, with optional host-side build/test tools  
**Guest ISA:** Intel 8086/8088 real mode (XT-class software compatibility)  
**Initial deliverable:** Run selected unmodified DOS `.COM` binaries, with a small DOS API shim and an 80×25 text display  
**Longer-term goal:** Boot and use an 8086-compatible DOS release from a virtual disk image

## 1. Executive summary

Build a **software-only 8088/8086 interpreter and PC-compatible runtime** for an 8 MB Apple IIGS. An 8088 is an 8086-family CPU with an 8-bit external bus; for normal instruction-level program compatibility, implement the 8086/8088 real-mode instruction set rather than simulating the 8088's bus at cycle accuracy.

The project should **not** begin as a cycle-accurate IBM PC/XT emulator. Its first release should load `.COM` files directly, execute the guest CPU accurately, and implement a documented subset of DOS `INT 21h` and BIOS services using native IIGS facilities. The second stage should support common direct video memory access and file operations. Booting genuine DOS becomes a separate, later hardware-compatibility project.

The key hypothesis is that 65816 16-bit operations, direct-page CPU state, simple physical-memory translation, and a carefully optimized interpreter can make text-mode DOS utilities usable on an accelerated IIGS. This is **not yet a performance claim**; measure instruction throughput before committing to a more elaborate system.

## 2. Goals and non-goals

### Goals

1. Correctly execute ordinary 8086/8088 real-mode programs, including segmented memory accesses, flags, stack operations, branches, and software interrupts.
2. Present **up to 640 KiB conventional guest RAM** and a coherent 1 MiB PC physical address map (including video and ROM regions).
3. Run unmodified small `.COM` programs and, later, a defined subset of `.EXE` (MZ) programs.
4. Implement a practical subset of DOS APIs (`INT 21h`) and BIOS services (`INT 10h`, `16h`, `1Ah`, etc.) with host-backed I/O.
5. Support standard PC 80×25 text-mode applications that use BIOS and/or write directly to `B800:0000`.
6. Produce reproducible correctness and speed measurements on stock and accelerated hardware.
7. Keep CPU execution, guest memory, DOS services, PC hardware emulation, and IIGS platform support cleanly separated.

### Non-goals for the initial release

- Cycle-accurate 8088 bus timing, instruction prefetch queues, or original XT performance.
- Running protected-mode 286/386 software, Windows, or programs that require x87 hardware.
- Full CGA/EGA/VGA graphics; PC speaker sound; serial, parallel, mouse, or network emulation.
- PC expansion-card or DMA emulation.
- Booting MS-DOS/FreeDOS on day one.
- Supporting arbitrary software that directly programs the PIT, PIC, DMA controller, CGA registers, or floppy controller.
- Dynamic recompilation until profiling justifies its complexity.

## 3. Target platform and implementation constraints

- **Host CPU:** WDC 65C816, executing native-mode 16-bit code where advantageous.
- **Host RAM:** 8 MB installed; verify **actual accessible banks and allocations** on target hardware rather than assuming that all banks are free to the program.
- **Host OS:** Choose between a GS/OS-hosted application and bare-metal execution early. Preferred first version: **GS/OS-hosted launcher with an assembly execution core**; long-running native routines must cooperate with host I/O and interrupt requirements. GS/OS details and possible restrictions should be validated during bring-up.
- **Build chain:** Existing user's preferred Apple IIGS assembler/linker/toolchain, with native-host tests built separately as appropriate. Do not make the emulator's core depend on a C compiler's code generation quality.
- **Storage:** Initially host-backed files. Later a disk image with a BIOS sector interface.
- **Output:** IIGS Super Hi-Res 640×200 offers a natural 8×8-pixel cell size for 80×25 text. Palette/attribute behavior will require adaptation.

**Architecture review question:** Can the chosen 8 MB configuration reserve **16 contiguous 64 KiB host banks** for the full 1 MiB guest physical map, without conflicting with GS/OS, screen memory, or other allocations? If not, use a page/bank mapping table. A concrete base such as `$20:0000` is only a **candidate**, not a guaranteed allocation.

## 4. Proposed architecture

```text
                 +--------------------------+
                 | IIGS launcher / debugger |
                 +-------------+------------+
                               |
                   +-----------v------------+
                   | 8086/8088 CPU engine   |
                   | fetch/decode/execute   |
                   | registers, flags, IP   |
                   +-----+-------------+----+
                         |             |
               +---------v----+  +-----v------------------+
               | Guest memory |  | Interrupt / port layer |
               | 1 MiB map    |  | INT and IN/OUT hooks   |
               +----+---------+  +-----+------------------+
                    |                  |
          +---------v------+   +-------v------------------+
          | RAM + B800 text|   | DOS / BIOS compatibility |
          | ROM stubs/maps |   | host-backed services     |
          +---------+------+   +-------+------------------+
                    |                  |
                    +---------+--------+
                              |
                     +--------v--------+
                     | IIGS OS / video |
                     | keyboard / disk |
                     +-----------------+
```

### 4.1 Guest address calculation

For a segmented logical address `segment:offset`:

```text
physical = ((segment << 4) + offset) & 0xFFFFF
```

Wrap at 20 bits for baseline XT compatibility (A20 is not a feature of a stock XT). **Do not** assume that a 16-bit host arithmetic operation suffices to perform this calculation; its result needs up to 20 bits plus wrap logic. If direct guest RAM is backed by contiguous host memory, calculate an effective 24-bit pointer. Otherwise use a bank/page translation layer.

Word accesses at `FFFFFh` must wrap to physical zero for the second byte. Emulate unaligned guest words and boundary crossing correctly. Read/write paths should distinguish RAM, display memory, and special-mapped regions.

Suggested preliminary PC physical layout:

| PC physical range | Purpose | Backing |
|---|---|---|
| `00000h–9FFFFh` | Up to 640 KiB conventional RAM | Host RAM |
| `A0000h–BFFFFh` | Adapter / video memory | Guest backing store; `B8000h` text renderer |
| `C0000h–EFFFFh` | Option ROM / reserved | Stub ROM or mapped backing store |
| `F0000h–FFFFFh` | System BIOS region | Stub BIOS/interrupt entry points |

The 1 MiB map requires **16 × 64 KiB** host banks if allocated contiguously. This is only one-eighth of an 8 MiB RAM budget, leaving room in principle for code, buffers, and caches; practical GS/OS availability must be checked.

### 4.2 Guest CPU state

Hold guest state in an aligned, direct-page-accessible structure wherever possible:

```text
AX BX CX DX SI DI BP SP
CS DS ES SS IP FLAGS
internal: segment bases / memory pointer scratch / decode state
internal: pending interrupt state / halt state / execution counters
```

For correctness, model both the low and high halves of `AX/BX/CX/DX` (`AL/AH`, etc.). Do not equate 65816 native flags with guest FLAGS: the sets and semantics differ. A 256-byte parity lookup table may be useful. Preserve undefined flags according to a documented policy without overengineering incidental cases.

Recommended initial implementation: **explicit eager flags** for correctness, then benchmark lazy flags as a targeted optimization. Lazy flags can be subtle around partial flag updates (INC/DEC preserve carry; shifts/rotates and decimal-adjust instructions have special behavior).

### 4.3 Instruction decoder

- Implement all base 8086/8088 opcodes needed for broad real-mode compatibility, not just a handful of example programs.
- Support instruction prefixes (`LOCK`, `REP/REPE/REPNE`, segment overrides), ModR/M decoding, 8-bit and 16-bit operands, and all 16-bit effective-address forms.
- Use a 256-entry primary opcode dispatch table and helper tables for operand decoding; consider opcode-specific fast paths.
- Implement string operations with correct `DS:SI`/`ES:DI`, direction flag, repeat count, and conditional repeat semantics.
- Handle `INT`, `INT3`, `INTO`, `IRET`, `CALL`, `RET`, `JMP`, near/far transfers, and stack behavior.
- Handle `IN`, `OUT`, `HLT`, and `CLI/STI` through the virtualization layer. For initial `.COM` mode, explicitly define unsupported ports and interrupt behavior.
- Implement 8086-compatible behavior for invalid/undocumented opcodes as needed for test coverage; document where behavior is intentionally unspecified.
- **Interrupt interception:** For the DOS shim, dispatch selected `INT nn` calls to host handlers. For a bootable guest, preserve normal interrupt-vector-table semantics and route through emulated BIOS entry points or precise traps. Avoid treating every interrupt as a high-level BIOS call.

**Accuracy caveats:** 8088 prefetch-queue side effects, cycle timings, and some undocumented behaviors can matter to specific games or copy-protection routines. These are outside initial scope. Correct general-purpose 8086 integer behavior is in scope.

### 4.4 DOS/BIOS interface design

Use **two distinct operating modes**:

**Mode A — DOS-compatible program runner (first target):** Create a valid Program Segment Prefix (PSP), load `.COM` bytes at offset `0100h` of a chosen segment, set guest registers/stack according to documented DOS conventions, and implement selected `INT 20h/21h` (and other relevant) services natively. No external DOS kernel is running. A loader must reject oversized programs and handle DOS-compliant termination.

**Mode B — virtual PC/XT boot (later):** Present a BIOS-compatible guest boot environment, disk-sector services, interrupt vector table, BIOS data area, timer tick, keyboard behavior, and enough hardware semantics for an actual DOS kernel to initialize. In this mode, **the guest DOS kernel handles `INT 21h`**; the host primarily supplies BIOS/hardware behavior. Do not mix the shim's `INT 21h` dispatch with a real DOS kernel without a deliberate design.

Proposed Mode A API priorities:

| Priority | Interface | Initial behavior |
|---|---|---|
| P0 | `INT 20h`, `INT 21h/AH=00h,4Ch` | Program termination and return code |
| P0 | `INT 21h/AH=02h,09h` | Character and `$`-terminated string output |
| P0 | `INT 21h/AH=01h,07h,08h,0Ah` | Basic keyboard/console input |
| P0 | `INT 10h` | Text mode setup, teletype output, cursor routines |
| P0 | `INT 16h` | Keyboard read and status |
| P1 | `INT 21h/AH=3Ch–42h,3Eh,3Fh,40h` | Basic handle-based file create/open/close/read/write/seek |
| P1 | `INT 21h/AH=48h–4Ah` | Allocate/free/resize guest memory blocks |
| P1 | `INT 21h/AH=30h,19h,2Ah,2Ch` | DOS version, drive, date, time |
| P1 | `INT 21h/AH=4Bh` | Child program execution; only after process model is established |
| P2 | `INT 13h` | Virtual-disk sector I/O (particularly for Mode B) |
| P2 | `INT 1Ah`, `INT 11h`, `INT 12h` | Clock, equipment and RAM reporting |

This table is an implementation guide, **not** a claim of complete DOS API compatibility. File path parsing, handles, errors, drive letters, current directories, DOS memory-control blocks, and device conventions must be specified and tested.

### 4.5 Video

- Map text mode `B800:0000` (`B8000h`) to a guest memory buffer. An 80×25 color text display contains 2,000 character/attribute pairs (4,000 bytes).
- Use an 8×8 bitmap font to render 80 columns × 25 rows onto a 640×200 IIGS Super Hi-Res screen.
- First target: monochrome or reduced-color attributes, cursor, clear screen, scrolling, and direct memory writes.
- Compare a **dirty-cell/dirty-row model** with periodic scanning for performance; guest memory writes are already mediated by the interpreter, so can mark dirty regions cheaply.
- Support text operations through both `INT 10h` and direct `B8000h` writes. Treat CGA hardware register I/O, alternate pages, and color fidelity as later compatibility work.
- Recognize that the IIGS 640-mode palettes limit faithful per-character 16-color CGA attributes; prioritize legibility and functionality.

### 4.6 Keyboard, timers, and storage

- Translate IIGS key events into PC ASCII/scancode pairs sufficient for BIOS `INT 16h`. Implement extended keys deliberately, with a documented mapping.
- For the shim, wall-clock time and timeout polling can use native host facilities. For boot mode, synthesize a PC-compatible BIOS timer tick (approximately 18.2 Hz) and appropriate interrupts/PIC semantics.
- Map DOS file APIs to host files in Mode A with a **sandboxed guest root**; avoid unintentional access to arbitrary GS/OS paths. Define case-insensitive 8.3 aliases and DOS error codes where needed.
- In Mode B, add a virtual floppy image backed by a host file and expose BIOS `INT 13h` reads/writes. Use explicit write protections or a copy-on-write overlay during development.

## 5. Work breakdown and milestones

### M0 — Feasibility / design freeze

**Deliverables:** Memory map probe, assembly execution harness, agreed OS hosting model, baseline performance harness, instruction test strategy.

- Confirm bank availability and guest memory allocation on the target machine.
- Decide whether video and OS calls require crossing between emulator execution and host services.
- Choose executable/container format and debugging instrumentation.
- Write down 8086-accurate CPU semantics and list exceptional cases.

**Exit criterion:** Reserve or map at least 1 MiB guest address space, write/read across 64 KiB bank boundaries, and render a test 80×25 frame.

### M1 — CPU core, pure computational programs

**Deliverables:** CPU state, fetch/decode loop, arithmetic, memory, branches, stack, prefixes, and core instruction tests.

- Start with `MOV`, `XCHG`, `PUSH/POP`, `ADD/SUB/CMP`, logical operations, `INC/DEC`, calls/returns, conditional jumps, and required addressing modes.
- Implement full flags and more complex classes including shifts, rotates, decimal adjustments, string operations, multiply/divide, and interrupts.
- Build a **host-side differential harness** that runs identical guest instruction sequences against an established 8086 model and the new core, comparing registers, FLAGS (masking genuinely undefined bits), and modified RAM.
- Include segment wrap, offset wrap, far calls, stack wrapping, instruction prefixes, and unaligned words.

**Exit criterion:** Agreed 8086 CPU tests pass with known exceptions documented. No DOS or BIOS needed.

### M2 — Minimal `.COM` executable environment

**Deliverables:** DOS PSP builder, `.COM` loader, handful of DOS services, terminal output.

- Establish the program's PSP, command tail, initial stack and registers.
- Implement clean termination and error reporting.
- Implement basic DOS console services, including `$`-string display and line input.
- Supply several small **unmodified** 8086 DOS `.COM` test programs, assembled externally.

**Exit criterion:** `HELLO.COM` and at least two nontrivial integer/string `.COM` programs complete successfully without binary patches.

### M3 — Useful text-mode DOS subset

**Deliverables:** 80×25 screen, keyboard, basic filesystem, guest-memory allocator.

- Support direct writes to `B8000h` plus enough `INT 10h` video API for common text tools.
- Add DOS handle-based file operations, path resolution, basic attributes, and reasonable error handling.
- Implement enough DOS allocation and process environment behavior to run selected real utilities.
- Capture screenshots and regression output.

**Exit criterion:** At least three independently sourced, era-appropriate DOS text-mode utilities run unmodified. Publish their versions, required services, and compatibility status.

### M4 — Performance characterization and tuning

**Deliverables:** Opcode counters, profiler output, reproducible CPU benchmark, optimized hot paths.

- Measure **guest instructions/sec**, native cycles/guest instruction (where possible), rendering overhead, and file-I/O time separately.
- Benchmark register-only loops; memory/address-heavy loops; string moves; branches; and realistic applications.
- Compare stock 2.8 MHz and actual accelerated clock rates, noting memory wait states and display overhead.
- Optimize fast paths for register operands, ModR/M decoding, cached segment bases, dispatch, and flags.
- Consider a parity table and instruction-template specialization; only then explore block translation.

**Exit criterion:** Publish measured throughput and representative application behavior. Decide whether full DOS boot is worth pursuing.

### M5 — PC/XT boot environment (stretch goal)

**Deliverables:** BIOS stubs/entry points, virtual disk, IVT/BDA, timer, IRQ/PIC and any required PIT behavior, floppy-image boot support.

- Pick an **8086-compatible DOS distribution and exact version**, confirm its hardware requirements and license, and build a known-good boot image.
- Instrument initialization to identify missing BIOS services and direct hardware port accesses.
- Implement hardware-facing semantics only as demanded by boot tracing.
- Preserve guest `INT 21h` control flow into DOS rather than hijacking it with the Mode A shim.

**Exit criterion:** An authentic DOS kernel reaches an interactive command prompt from a disk image. This is a separate project-level milestone, not a prerequisite for M3.

### M6 — Optional dynamic translation experiment

Translate hot guest basic blocks into 65816 code, initially with preassembled templates. Design guest-code-write invalidation, fallbacks for unsafe instructions, flags synchronization, and transitions to interpreted code. Compare the speedup to memory cost and complexity before adopting this as the default engine.

**Exit criterion:** Demonstrate a repeatable, meaningful net speed gain on real programs without CPU-test regressions; otherwise retain the interpreter.

## 6. Testing strategy

### CPU correctness

Use a vetted 8086 instruction test suite where licensing and formats permit, plus small targeted tests. A host-side reference interpreter can accelerate diagnosis, but **do not assume that another emulator is an infallible oracle**. Test:

- Every ModR/M addressing combination and displacement case.
- All register width/high-byte combinations.
- Carry/zero/sign/overflow/auxiliary/parity behavior and instructions that preserve selected flags.
- Segment defaults (`BP` uses `SS`), segment override behavior, and `ES` destination semantics for string operations.
- `REP` zero-count behavior, `DF`, conditional string repeat and wraparound.
- Stack, near/far branches, interrupt entry/return, divide errors, and 20-bit memory wrapping.
- Guest instructions that cross an instruction-fetch boundary or host RAM bank boundary.

### DOS compatibility

Keep a matrix with each tested binary, build/version, whether unmodified, execution result, missing `INT` functions, direct port use, crashes, and performance. Distinguish **DOS-shim compatible** from **hardware/boot compatible**.

### Performance

Report measured results, not estimates. Any speculative throughput numbers from the preliminary discussion must be treated as hypotheses. Record machine clock, accelerator, memory configuration, video mode, debug build, and test program alongside numbers.

### Failure diagnostics

Provide an optional trace of `CS:IP`, opcode bytes, register state, FLAGS, memory/port operations, and the most recent interrupt. Make traces bounded (ring buffer or host serial/file dump) to avoid consuming all RAM or swamping execution.

## 7. Main technical risks and mitigations

| Risk | Why it matters | Mitigation |
|---|---|---|
| Slow instruction decode/addressing | Could make most software unusable | Benchmark M1 early; specialize common paths |
| Inaccurate flags | Causes silent control-flow errors | Differential tests; initially eager flags |
| Host bank and pointer boundaries | 65816's 24-bit addressing is not a flat C-like pointer model | Explicit 20-bit guest/24-bit host translation and bank-crossing tests |
| DOS API breadth | A few `INT 21h` functions do not equal DOS compatibility | Document shim subset; advance from tested binaries |
| Direct hardware access | Many DOS apps bypass BIOS | Prioritize direct text RAM; detect/report unsupported ports |
| GS/OS hosting/interrupt constraints | Long-running core and display updates may conflict with OS | Prove host integration at M0; consider bare-metal fallback |
| Boot complexity | Real DOS may expect PIC/PIT/keyboard-controller behavior | Treat full boot as M5, instrument startup |
| Self-modifying guest programs | Code caching/JIT invalidation gets hard | Interpreter first; later write barriers/invalidation |
| Licensing of DOS/ROM/test binaries | Redistributing historical images may be restricted | Use properly licensed OS and self-created BIOS stubs |

## 8. Suggested source tree

```text
xtgs/
  README.md
  docs/
    architecture.md
    memory-map.md
    cpu-compatibility.md
    dos-api.md
    compatibility-matrix.md
    benchmarks.md
  src/
    app/           # startup, host glue, UI/debug shell
    cpu/           # CPU state, dispatch, instruction handlers
    memory/        # guest memory and mappings
    dos/           # Mode A loader, PSP, DOS shim
    bios/          # BIOS service layer / boot-mode stubs
    devices/       # keyboard, clock, video, ports, virtual disk
    platform/iigs/ # native IIGS display, keyboard, filesystem
  tests/
    cpu/
    com/
    integration/
    benchmark/
  tools/           # host-side test generators, trace analysis
  assets/          # legally distributable fonts/boot assets
```

## 9. Immediate proof-of-concept sprint

1. Establish the 1 MiB guest memory mapping and verify all physical address boundaries.
2. Implement guest state, `CS:IP` fetch, and a primary opcode dispatch loop.
3. Support only enough instructions for a self-contained instruction-counted test (e.g., register moves, arithmetic, compare, conditional branches, `HLT`).
4. Add a trace mode and a host-side test generator.
5. Extend the interpreter to `.COM` program essentials: memory operands, stack, near calls/returns, string support as needed, `INT` dispatch.
6. Implement `INT 21h/AH=09h` and `4Ch`, with a proper PSP and loader; successfully run `HELLO.COM`.
7. Measure interpreter overhead in guest instructions/second before introducing an elaborate video or DOS subsystem.

**Smallest convincing demonstration:** An externally assembled, unmodified `HELLO.COM` prints a string and exits with a code; a second `.COM` performs arithmetic, memory reads/writes, a loop, and calls/returns; the emulator's register/memory state matches the test oracle.

## 10. Decisions for review with Claude

1. **Host architecture:** GS/OS-hosted first or bare-metal, based on feasibility and achievable throughput?
2. **Memory:** Is a contiguous 1 MiB region actually reserveable in this 8 MB IIGS? Which banks are safe, and how are they obtained?
3. **Assembler/toolchain:** Which assembler, linker, and file formats should the codebase use?
4. **CPU implementation:** Hand-authored 65816 handlers, generated opcode tables/handlers, or a hybrid?
5. **Flags:** Eager correctness first, then lazy evaluation, or a hybrid from day one?
6. **DOS shim:** Minimal `INT 21h` subset versus early investment in PSP/MCB/handle fidelity?
7. **Video:** Dirty-cell updates, periodic scan, or a hybrid given IIGS display transfer costs?
8. **Performance gate:** What measured speed is sufficient to justify M5 (full DOS boot)?
9. **Reference tests:** Which specific legal, trustworthy 8086 test vectors and binaries should be adopted?
10. **Success definition:** Is the first public release a useful DOS `.COM` runner, or is booting a real DOS kernel essential?

## 11. Proposed first request to Claude

> Review this project plan as a 65816/Apple IIGS systems engineer. Challenge the CPU correctness assumptions, the feasibility of a 1 MiB guest memory allocation on an 8 MB machine, and the GS/OS hosting strategy. Identify any incorrect 8086 semantics, problematic 65816 addressing/interrupt assumptions, and missing DOS `.COM` loader requirements. Then propose an M0/M1 implementation plan with concrete data structures, memory layout, and a minimal CPU instruction-test harness. Do **not** jump straight to a full PC/XT hardware emulator or a JIT. Separate verified platform facts from assumptions requiring hardware measurement.

---

**Recommended project rule:** Build correctness first, instrument immediately, optimize only with benchmarks, and treat a genuine DOS boot as an explicit expansion rather than a hidden dependency of the first milestone.
