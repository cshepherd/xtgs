# XT/GS — M7: Machine State Serialization and Instant Boot

## Objective

Bypass the expensive FreeDOS boot sequence by restoring a validated, pristine machine snapshot captured after initialization, then synchronize guest time with the Apple IIGS host. Keep cold boot available and retain the existing interpreter as the reference execution engine.

M7 complements M6: selective dynamic translation targets recurring computation; snapshots eliminate nonrecurring initialization. M7 must not depend on a JIT. The primary target is a materially faster launch on 16 MHz hardware, with stock and 48 MHz measurements where practical.

## M7.0 — Audit and baseline

Before changing code, inspect the current CPU, memory, BIOS traps, video, interrupt/timer, keyboard, disk and GS/OS integration implementations. Identify every mutable guest-visible field and every host-only resource. Do not assume that XT/GS implements a physical XT peripheral model where a BIOS trap or higher-level abstraction actually exists.

Measure cold boot from launch to a usable FreeDOS prompt with the same disk, configuration and hardware used for subsequent restore tests. Record elapsed time, bytes read, guest instructions where available, and memory footprint. Separate emulator startup from guest boot. Preserve existing CPU and game regression tests.

Deliverable: state inventory, baseline results and a list of unsafe or unimplemented state boundaries.

## M7.1 — Versioned machine-state serialization

Implement an explicit, deterministic serializer/deserializer for the guest-visible machine. Start with raw memory; do not optimize the format prematurely.

| State | Requirements |
|---|---|
| CPU | All guest registers, CS:IP, FLAGS, halted state, interrupt inhibition, pending events and any execution state needed to resume at an instruction boundary. |
| Memory | All writable guest memory, including conventional RAM, BIOS data, IVT and any separately mapped memory. Preserve actual mapping semantics. |
| Video | VRAM, mode, cursor, palette, CRTC, EGA registers/latches and other guest-visible state as implemented. Rebuild native display caches and force a redraw. |
| Timers and interrupts | Implemented PIT/PIC state, pending interrupts, masks, timer phases and guest-visible counters. Rebase host timing on restore. |
| Keyboard | Guest keyboard buffer, controller state and pending events as implemented. A pristine checkpoint should have no unintended queued input. |
| BIOS/device state | Mutable BIOS trap state, drive configuration, controller state and other guest-visible fields discovered in the audit. |
| Storage | Media identity, geometry, logical mappings and any necessary guest-visible device state. No native file handles. |
| Execution caches | Discard and rebuild decoded instruction caches, JIT blocks, host pointers and derived mappings. |

Use explicit little-endian fields, section identifiers and lengths. Never serialize raw native pointers, GS/OS handles or compiler-dependent structures. Restore into a freshly initialized emulator instance. Reopen host resources and reestablish mappings before resuming guest execution.

Suggested file header: magic, format version, emulator state ABI/build compatibility identifier, machine configuration fingerprint, media identity manifest, section count, payload length and checksum. Include per-section validation where useful. Reject unsupported versions, malformed lengths, duplicate mandatory sections, invalid register/device values and truncated or corrupted payloads. A checksum detects corruption; it is not an authenticity guarantee.

Initially support only trusted, locally generated snapshots. Write to a temporary file, close successfully, then publish using the safest replacement operation supported by GS/OS. Never destroy the previous valid snapshot until the replacement has been written and verified. On restore failure, discard partial state, initialize cleanly and cold boot.

### Gate

Save at a known safe instruction boundary, restore into a new emulator instance, and compare canonical guest state before executing further instructions. With identical deterministic input and virtual time, compare subsequent CPU/device state and output against an uninterrupted reference run. Include tests for bank crossings, video state, interrupts and malformed files.

## M7.2 — Pristine FreeDOS checkpoint

First implement an explicit menu/debug command to save a boot checkpoint after the operator confirms a usable DOS prompt. Require a quiescent storage boundary: no active BIOS disk request, outstanding host writes or in-flight device operation. A visible prompt is not by itself proof that guest filesystem caches are clean.

For automatic creation, consider a small `XTGREADY.COM` helper invoked at the end of AUTOEXEC.BAT (using an existing private BIOS trap or a reserved, documented emulator service). The helper may notify the host, but must not itself be the checkpoint: let it return, let COMMAND.COM finish processing startup, and capture at a verified idle/input-wait boundary. If the input wait is represented by a suspended BIOS trap rather than ordinary guest instructions, either serialize that continuation explicitly or choose a checkpoint immediately before it is entered. Do not guess at a fixed CS:IP or screen contents.

Ensure dirty guest filesystem buffers are flushed through a verified FreeDOS-compatible mechanism before capture; host flushes alone do not flush guest DOS buffers. If this cannot be guaranteed for a configuration, restrict automatic snapshots to a controlled, known boot environment. Do not add guest-side hooks that affect ordinary non-XT/GS DOS installations unexpectedly.

Treat the boot snapshot as immutable: normal sessions must never overwrite it on exit. Provide explicit commands to create/rebuild/delete it and force a cold boot. Automatic refresh after a successful cold boot may be added once the checkpoint protocol is reliable.

### Gate

Restore the pristine image repeatedly, obtain a usable prompt, run DIR and ordinary DOS commands, launch representative games, exit to DOS and reboot. Verify that repeated launches never accumulate state from prior sessions.

## M7.3 — Storage consistency and invalidation

This is the principal correctness risk. DOS caches filesystem metadata in guest RAM; a cleanly flushed snapshot can still contain stale *clean* cached sectors. Reopening host files does not invalidate those caches. Never blindly restore a pristine RAM snapshot against arbitrary changed writable media.

Start with a conservative policy:

- Bind the snapshot to the exact boot media and all mounted guest-visible storage, drive ordering, geometry, ROM/BIOS identity, emulator state ABI and relevant configuration.
- Reject snapshots when media identity cannot be established or when guest-visible storage has changed. Metadata (name, size, mtime) alone is not a reliable content identity. A whole-image hash is a useful reference implementation, but measure its cost on the IIGS.
- If XT/GS exposes a ProDOS-backed filesystem, audit its mapping and caching semantics separately from raw disk images. Do not assume external directory changes are equivalent to a disk-image write.
- Ensure the guest and host disk write paths mark affected media generations dirty before modifications. Persistent generation metadata must survive crashes safely; external modifications must be detected or the fast path disabled.
- Use exclusive control of media where feasible; avoid a validation-to-use race. Revalidate or reject if mounted resources change during restore.

A conservative exact-media policy may invalidate the snapshot after ordinary DOS writes. That is acceptable for the first correctness prototype but could severely limit practical usefulness. Measure actual hit rate across repeated game sessions before calling M7 complete.

If necessary, investigate these follow-on designs in order of simplicity:

1. An immutable boot image (or read-only base with a disposable per-session overlay), with any writable secondary media governed by a separate safe validation policy. Never silently discard user writes.
2. A guest-cooperative, version-tested mechanism to flush and invalidate DOS/driver caches after restore and refresh removable-media state. Do not patch undocumented FreeDOS structures without proving compatibility. This must address cached directory/FAT data, drive parameters, open handles and current-directory assumptions where applicable.
3. A snapshot coupled to a specific persistent disk generation or explicit copy-on-write checkpoint. This is more relevant to future general save states than pristine boot.

Avoid shipping arbitrary session restoration until disk consistency is solved. For pristine boot, do not roll user files back to their capture-time contents.

### Gate

Test unchanged media, DOS-created/modified/deleted files, external edits, same-size edits, replaced images, changed drive mappings, and interrupted writes. On uncertainty, cold boot. Verify subsequent DOS reads/writes against the actual backing storage, not merely a successful prompt.

## M7.4 — Clock synchronization and event rebasing

After loading state and before normal guest execution resumes, obtain the current host local date/time using the existing IIGS time facilities. Reuse existing XT/GS BIOS clock integration wherever possible.

Audit the XT BIOS tick counter at 0040:006C and midnight rollover state at 0040:0070, the FreeDOS date/time implementation, and any emulated RTC. Synchronize guest-visible BIOS time and DOS date consistently. XT-class systems need not expose an AT RTC; do not introduce one merely for this feature.

One possible implementation is a controlled guest-side trampoline or helper using INT 21h AH=2Bh (set date) and AH=2Dh (set time), provided DOS is at a safe, non-reentrant boundary. Do not call DOS recursively from inside its keyboard wait or an interrupt handler. Preserve guest registers, stack and continuation; validate returned status. Alternatively, use a supported clock-driver integration if the existing architecture provides one. Avoid undocumented kernel date fields unless explicitly versioned and tested.

Reset/rebase the host scheduling epoch so time spent with the emulator closed does not create a burst of catch-up PIT interrupts. Preserve guest-visible timer modes and valid pending state; do not indiscriminately clear interrupts. Choose a documented policy for fractional ticks and midnight rollover so the date is not advanced twice. Do not treat the snapshot timestamp as the current date.

### Gate

Verify DOS DATE/TIME, BIOS time services, file creation timestamps, midnight/year rollover, long intervals between capture and restore, and continued timer/keyboard behavior. Test leap days and host clock adjustments where practical. Compare against a cold boot at the same host time.

## M7.5 — Fast boot integration and performance

Launch sequence:

1. Initialize host resources and determine the requested machine/media configuration.
2. Locate the pristine snapshot; validate format, compatibility and storage identity.
3. Restore canonical guest state, reopen/rebind host resources and rebuild derived state.
4. Synchronize guest time and rebase timing; invalidate any JIT/decoded-code cache.
5. Redraw the display and resume at the verified guest boundary.
6. On any failure, reset completely and perform the ordinary boot path; report the reason concisely.

Start with raw bank-aware sequential I/O into guest memory. Measure restore time broken down into file open, validation, reads, checksums, state rebuild, clock sync and first usable input. Include all costs, not just payload reads.

Only if measurements justify it, test sparse zero-page encoding (e.g. 4 KiB chunks), simple RLE or a lightweight LZ decoder. Compare actual end-to-end times on stock, 16 MHz and 48 MHz hardware where available. Avoid a full memory staging buffer if it would materially increase RAM requirements; streaming restore is fine if failures reliably reset all guest state before cold boot.

Suggested provisional acceptance targets (revise after baseline measurements): at least 3x faster launch-to-prompt on 16 MHz with valid snapshots, no material regression to cold boot, no increase in minimum RAM configuration without justification, and a useful snapshot hit rate across normal sessions. An aspirational target is a usable prompt within a few seconds, not a guaranteed measured result.

## M7.6 — Regression suite and release gate

- Round-trip state and differential execution tests with deterministic clocks/input.
- Existing CPU, BIOS, DOS and game regressions; interpreter remains the reference.
- Repeated restore, keyboard input, directory navigation, file writes, graphics mode changes and timer interrupts.
- Truncated/corrupted snapshots, incompatible versions, missing files, changed media and failed host reads.
- Forced cold boot, snapshot regeneration, graceful fallback and interrupted snapshot creation.
- Boot-to-prompt measurements, snapshot size, memory overhead and hit rate on representative hardware/storage.
- If M6 is present, prove snapshots restore with the JIT disabled and enabled; generated native code must never be serialized.

Ship only when correctness gates pass and actual end-to-end launch improvement is repeatable. Keep the feature optional if any hardware or media combination is not validated. Document compatibility and invalidation behavior.

## Future work (explicitly outside initial M7 scope)

General save states, suspend/resume, game checkpoints, multiple boot profiles, portable bug reproductions and differential M6 testing all benefit from the same serializer. Arbitrary save states need additional guarantees for active I/O, suspended BIOS calls, DOS open handles, guest timers and backing-store consistency. Do not advertise these merely because pristine boot snapshots work.

## Initial instruction to Claude

Begin with M7.0 and M7.1 only. Audit the actual codebase, identify state ownership, measure a cold boot, and implement a raw checkpoint/restore proof of concept with deterministic round-trip tests. Use a manually selected pristine FreeDOS checkpoint and unchanged media. Report what was serialized, what was reconstructed, what remains unsafe, snapshot size and measured restore time. Do not implement compression, automatic prompt detection, broad DOS cache manipulation or general save states until the basic proof is sound. Then address storage consistency and clock synchronization before enabling automatic fast boot by default.
