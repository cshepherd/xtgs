# XTGS: Tandy 1000 / PCjr Graphics and Sound Implementation Plan

**Status:** Proposal for Claude review — implement after XTGS EGA 320×200×16 is stable  
**Target:** Apple IIGS, GS/OS, native 65816 emulator, Super Hi-Res graphics, Ensoniq DOC audio  
**Primary machine profile:** Original Tandy 1000 / early Tandy-compatible PC, *not* an undifferentiated “PCjr = Tandy” device  
**Priority:** Graphics compatibility and performance first; PSG sound second  
**Date:** November 10, 2026

## 0. Context / request to Claude

XTGS already boots FreeDOS and MINIX and runs real DOS programs including GW-BASIC, Lotus 1-2-3, and Tunneler. It has CGA support, an EGA 320×200 implementation nearing completion, and **already uses the IIGS Ensoniq DOC for accurate 8253/PIT timing and PC-speaker sound**. Preserve all existing behavior, timer accuracy, oscillator allocation, and video code. Do **not** assume that a spare DOC oscillator can simply be enabled without adjusting the existing frequency/timing scheme.

Please audit this proposal against the *actual XTGS code* and the linked hardware documentation before implementing anything. In particular, confirm how the current emulator maps guest physical RAM, traps video memory writes, selects adapters, handles port I/O, schedules refreshes, and uses DOC oscillators. Prefer a coherent machine profile and reusable backend over quick BIOS-only mode hooks. Identify disagreements with the hardware references before writing code.

**Definition of success:** A DOS application that detects a Tandy 1000, selects mode 09h, writes directly to video memory, changes its palette, and flips pages displays correctly in SHR. Subsequent support should cover other Tandy modes and recognizable three-voice/noise output without regressions in PIT/PC-speaker functionality.

## 1. Executive assessment

- **Mode 09h (320×200×16) is the highest-value feature.** It is packed 4 bits/pixel, two pixels/byte, high nibble first. Apple IIGS 320-mode SHR has the same *pixel packing* and 160-byte scanline width. Copy/deinterleave rows rather than plotting individual pixels.
- **Caution:** Tandy memory is divided into four interleaved 8 KiB banks; it is **not** a linear 32,000-byte bitmap. A Tandy page occupies a 32 KiB memory window.
- **Mode 08h (160×200×16)** is also cheap: deinterleave two banks and horizontally duplicate 4-bit pixels. Modes 04/05 and 06 are familiar CGA-family formats; 0Ah (640×200×4) uses an **unusual bitplane-like even/odd-byte representation**, not ordinary packed 2bpp. Don't assume direct-copy for 0Ah.
- **Palette writes and video paging are critical.** A correct pixel renderer without programmable Video Array registers, CRT/processor page selection, and memory-window semantics will miss many games.
- **Sound is a natural follow-up.** The SN76496-compatible PSG has three programmable tone channels and a noise channel. Use DOC-driven square waves if feasible, but integrate with the existing DOC-based PIT emulation carefully; noise and timing exactness are separate issues.

## 2. Scope and machine profiles

Implement a named `TANDY_1000` machine/video profile alongside existing XT/CGA/EGA profiles. Avoid presenting simultaneously contradictory hardware identity unless explicitly supporting a hybrid configuration.

**In initial scope**

1. Original Tandy 1000-compatible BIOS video mode setup, especially mode 09h.
2. Correct guest-visible video memory in the `$B8000` window, including selected CPU page, display page, and direct VRAM reads/writes.
3. The original Tandy Video Array control/ palette I/O and CRTC basics sufficient for real applications.
4. Mode 09h SHR renderer; later 08h, 04h/05h, 06h, 0Ah.
5. Optional PSG sound (`0C0h`–`0C7h` writes), with accurate 8253/PC speaker coexistence.

**Explicitly deferred**

- Exact analog composite artifact colors, RF behavior, border geometry beyond SHR viewport.
- Cycle-perfect video bus contention or raster effects.
- Later Tandy SL/TL/RL-specific 640×200×16 mode 0Bh, PSSJ advanced features, DAC/sample playback.
- Fully accurate PCjr-specific RAM placement, chipset behavior, and detection until a separate PCjr profile is designed.
- Exact PSG analog filtering and all SN76496/NCR8496/PSSJ differences.

**Compatibility warning:** Tandy 1000 and PCjr overlap heavily but differ in RAM page layout, detection, audio routing, and chipset details. Choose a concrete baseline (the *original* Tandy 1000 or 1000 SX) and clearly identify which baseline each test targets. If current XTGS has a 640 KiB conventional-memory map, verify that a Tandy-like shared video-RAM reservation and BIOS memory report are coherent; do not blindly claim all 640 KiB is general RAM in every machine configuration.

## 3. Video mode catalog

| BIOS video mode | Pixels | Colors | Video page size | Pixel representation | Intended SHR path |
|---|---:|---:|---:|---|---|
| 04h/05h | 320×200 | 4 | 16 KiB | 2bpp, 4 pixels/byte, CGA-like two-way interleaving | Existing CGA conversion, palette mapped |
| 06h | 640×200 | 2 | 16 KiB | 1bpp, 8 pixels/byte, two-way interleaving | 640 SHR with suitable replicated palette |
| 08h | 160×200 | 16 | 16 KiB | 4bpp, 2 pixels/byte, two-way interleaving | Expand each pixel horizontally ×2 into 320 SHR |
| **09h** | **320×200** | **16** | **32 KiB** | **4bpp, 2 pixels/byte, four-way interleaving** | **Direct 160-byte row copies into 320 SHR** |
| 0Ah | 640×200 | 4 | 32 KiB | Two bitplanes carried in alternating bytes, four-way interleaving | Combine bits / convert to 640 SHR |
| 0Bh (later Tandy) | 640×200 | 16 | 64 KiB | Later-generation chipset | Out of scope initially |

The “page sizes” above are *allocations*, not visible pixel-byte totals: e.g. mode 09h holds 32,000 actual image bytes in a 32,768-byte page. Some old references call these 16K/32K banks. Distinguish KiB page granularity, 8 KiB interleave offsets, and active image bytes in implementation comments.

### 3.1 Mode 09h: exact memory-to-SHR conversion

Two consecutive pixels occupy each source byte: bits 7–4 = left color index; bits 3–0 = right color index. SHR 320 mode uses the same nibble order. In the **displayed** 32 KiB page:

- Bytes `0000h..1F3Fh`: scanlines 0,4,8,…,196.
- Bytes `2000h..3F3Fh`: scanlines 1,5,9,…,197.
- Bytes `4000h..5F3Fh`: scanlines 2,6,10,…,198.
- Bytes `6000h..7F3Fh`: scanlines 3,7,11,…,199.

Nominal address for displayed scanline `y` (0–199):

```c
size_t tandy09_row_offset(unsigned y) {
    return ((size_t)(y & 3) << 13) + ((size_t)(y >> 2) * 160);
}

for (unsigned y = 0; y < 200; ++y) {
    const uint8_t *src = displayed_video_page + tandy09_row_offset(y);
    uint8_t *dst = shr_320_pixels + 160 * y;
    copy_160_bytes(dst, src);
}
```

**This only describes the renderer, not how CPU addresses select RAM pages.** `displayed_video_page` must be resolved via the Tandy CRT page register; CPU accesses through `$B8000` can point at another page. Do not assume CPU page and display page match. If an existing 65816 block-move primitive is faster than the generic copy loop, benchmark it, but respect SHR bank layout and GS/OS display ownership.

### 3.2 Mode 08h: 160×200×16

- 80 actual source bytes per scanline; two-way 8 KiB interleaving (`y & 1`, `y >> 1`).
- Each byte encodes two 4-bit pixels; duplicate *each nibble* into one SHR byte (one pixel repeated twice):

```c
uint8_t a = src_byte >> 4;
uint8_t b = src_byte & 0x0F;
dst[0] = (a << 4) | a;
dst[1] = (b << 4) | b;
```

A **256-entry table of 16-bit outputs** allows this without shifts at runtime, provided endianness in the 65816 store is handled correctly. 80 source bytes become 160 SHR bytes.

### 3.3 Modes 04h/05h and 06h

Reuse tested CGA conversion/row scheduling, but apply the Tandy palette registers rather than assuming CGA fixed palettes. For 640-mode SHR, each group of four 2-bit pixels addresses *four different four-color subpalettes*; replicate the same two or four target colors into all subpalette groups. Note that simply copying CGA 1bpp bytes to SHR 640-mode memory is **not** sufficient: each SHR pixel is 2bpp and must be expanded. (Correction to an overly optimistic “direct copy” shortcut.)

### 3.4 Mode 0Ah: 640×200×4

The original Tandy manual describes 8 pixels across **two bytes**, with one byte carrying one bitplane and the other byte carrying the other bitplane. Confirm the precise byte ordering and pixel bit significance against primary documentation or a known-good emulator before coding. Deinterleave rows and combine the two source bytes into four 2bpp SHR bytes per 8 pixels, then duplicate the four-entry palette in each of SHR's 640-mode mini-palette groups.

A small `pair_to_shr[65536]` lookup would cost considerable memory (128–256 KiB depending on packing), potentially fine with 8 MB, but benchmark a smaller 2×256 byte expansion/merge or nibble table first. **Do not precommit memory or code complexity until tests establish the workload.**

### 3.5 SHR palette and display details

- 320 SHR: 4bpp, 160 bytes/scanline, up to 16 colors in one selected palette per line. Load RGBI-to-12-bit-RGB colors (including brown as appropriate), respecting actual Tandy index mapping and palette mask behavior.
- For 640 SHR: 2bpp per pixel, 160 bytes/scanline, with *four position-dependent groups* of four palette entries. Configure all groups to represent the Tandy's same two/four selected colors.
- Update SHR palette entries on Tandy palette changes without rewriting framebuffer data when possible; preserve the actual Tandy palette lookup (source pixel index → RGBI entry) as a separate stage from physical SHR color entries.
- Ensure SCBs (scanline control bytes), palette ownership, and any mixed 320/640 display transitions are initialized consistently.
- Blanking, borders, and scanline-specific palette limitations can be approximated initially, but track them as compatibility differences.

## 4. Guest-visible I/O registers and VRAM semantics

**Verify port decode against the original Tandy 1000 or SX technical reference.** Main starting points:

| Port | Purpose | Implementation notes |
|---|---|---|
| `03D4h` / `03D5h` | 6845-compatible CRTC index/data | Cursor/start address/page-related values; preserve existing behavior where valid |
| `03D8h` | Mode control | Graphics, high-res, video enable, etc. |
| `03D9h` | Color select | CGA-like foreground/background/mode controls |
| `03DAh` read | Video status | Retrace status; software may spin waiting for vertical retrace |
| `03DAh` write | Video Array register index | **Read and write have different meanings at same port** |
| `03DEh` write | Indexed Video Array data | Palette mask, border, mode control, 16 palette entries |
| `03DFh` write | CRT / Processor Page Register | Display page, CPU page, video addressing mode |

**Important correction:** Some OCRed manuals render `03DFh` as `30F` and `03D8h` as `308`. The full hex ports, confirmed in the Tandy 1000 SX technical reference and contemporary programming examples, are **3DF/3D8**, not 30F/308.

The Tandy Video Array index set includes: `01h` palette mask, `02h` border, `03h` mode control, and `10h–1Fh` color-register entries (see manual). Write to `3DAh` to select index; write to `3DEh` to update it. Do not conflate `3DAh` status reads with index writes.

### 4.1 3DFh page register

The original documented register assigns bits 0–2 to CRT/display page, bits 3–5 to CPU/processor page, and bits 6–7 to video address mode. In 32 KiB modes, some low page bits are ignored/forced to alignment; in 16 KiB modes, CPU window size can vary with selected page. **Implement its behavior from a specific machine's manual rather than pretending `$B8000` maps an always-present flat 128 KiB framebuffer.**

For mode 09h, resolve both the CPU address window and the current display page against the underlying emulated Tandy video/shared RAM. If guest VRAM is represented inside the current 1 MB guest physical-address image, ensure CPU writes, guest reads, and renderer all observe the *same bytes* even after a page switch.

### 4.2 BIOS and machine detection

Tandy software may make hardware decisions using BIOS mode support, ROM bytes, `INT 10h` behavior, machine-specific calls, equipment/memory reporting, or direct port probing. A BIOS-only renderer is insufficient if games refuse to select Tandy modes.

- Add a configurable machine identity: normal XT/CGA or XT/EGA vs Tandy 1000 (and later PCjr, if desired).
- Decide whether to boot an authentic Tandy BIOS or synthesize just enough compatible identity and `INT 10h` behavior. Document exactly which identifier bytes and BIOS functions were verified; **do not fabricate a universal detection signature**.
- Ensure `INT 10h/AH=00h` accepts modes 08h/09h/0Ah, clears/initializes VRAM and controller registers appropriately, and updates BIOS Data Area video state in the expected form.
- BIOS pixel read/write and text output in graphics modes are useful as smoke tests, but direct memory-mapped writes must work independently.
- Vertical retrace reads should return plausible transitions, not permanently zero or permanently set (otherwise polling loops can hang). Use XTGS's existing timer architecture rather than busy spinning or changing PIT state.
- Preserve boot compatibility with FreeDOS and any Tandy-specific DOS utilities/drivers used for testing.

## 5. Rendering architecture and 65816 optimization

Recommend a common **visible SHR output interface** rather than attempting to make different adapters share one fake VRAM organization:

```text
Guest CPU/BIOS/OUT instructions
       |
       +-- CGA guest VRAM + register model -------+
       +-- EGA planes/latches + register model ---+--> adapter renderer --> SHR bytes/SCBs/palettes
       +-- Tandy RAM/pages + Video Array model ---+
```

Each adapter retains authoritative guest-facing state. The output backend knows packed SHR layouts, dirty lines, and palette uploads.

**Suggested optimizations, in order:**

1. **Correct page and register semantics first.** Do not optimize an incorrect RAM aliasing model.
2. For mode 09h, implement whole-row 160-byte copies, not per-pixel drawing. Start with a full-frame conversion to validate behavior.
3. Add dirty-line tracking: a guest write within displayed page of mode 09h dirties `y = 4 * (offset_in_8KiB_bank / 160) + bank`, where `bank = (page_offset >> 13) & 3`, excluding inter-row slack/unused bytes. Dirty tracking must honor CPU page mapping, display page, CRTC offsets, and possible multiple-byte writes.
4. Coalesce writes and refresh at existing frame cadence. Page switches should mark everything dirty or redirect displayed-page reference immediately.
5. On palette-only writes, update palettes without repainting rows where possible.
6. Precompute mode 08h nibble-doubling and 0Ah bitplane merge tables only after representative profiling.
7. If cache RAM/accelerator is available, benchmark copies vs plotting, but **do not make extra cache RAM a baseline requirement**.

**Risks:** A video memory write may already have side effects in the EGA implementation; avoid duplicating traps or silently breaking alternate machine modes. Self-modifying guest code does not necessarily require special display logic, but guest memory aliases and CPU page mapping must be coherent. Interrupt-driven refresh, NDA/GS/OS tool calls, and DOC timing should remain nonblocking.

## 6. Tandy PSG / PCjr sound engine

### 6.1 Hardware specification

Original Tandy 1000: SN76496-family programmable sound generator, nominal reference clock **3,579,545 Hz**; three square-wave tone channels plus one periodic/white-noise channel, with 4-bit attenuation per channel. Write-only PSG ports on the original Tandy are **`0C0h`–`0C7h` aliases**; IBM PCjr uses `0C0h`. Later Tandy models can substitute NCR8496 or PSSJ-related hardware; exact noise behavior differs.

For nonzero tone period `N`:

`frequency_hz = 3,579,545 / (32 * N)`.

Tone period is 10 bits; each attenuation register is four bits (`0` loudest, `15` mute). Noise supports white/periodic selection and fixed clock divisions or tracking tone 2 (third tone channel). Don't hardcode an undocumented rule for zero divisor or LFSR feedback until the chosen chip model has been validated.

### 6.2 PSG byte protocol (correct latch/continuation handling)

A byte with bit 7 **set** latches the target register (`bits 6..4`) and supplies the low 4 data bits; a subsequent byte with bit 7 **clear** generally supplies six additional tone-frequency bits to the currently selected tone register. For other latched register types, continuation semantics can differ among chip variants: implement the documented target profile rather than blindly treating every continuation as tone data.

```c
void tandy_psg_write(uint8_t b) {
    if (b & 0x80) {
        latched_reg = (b >> 4) & 7;
        // tone/noise/volume low nibble according to selected register
    } else {
        // extend tone divisor for latched tone register, where applicable
    }
    // commit only changed channel parameters to audio backend
}
```

Register order conventionally alternates tone period and volume for channels 0, 1, and 2; the last pair are noise control and noise volume.

### 6.3 DOC mapping without damaging PIT timing

XTGS's **existing DOC-based PIT implementation takes precedence**. Before assigning channels:

- Inventory all active DOC oscillators, sound RAM regions, IRQ handlers, timing calibration, and any assumptions about total enabled oscillators/scan rate.
- The DOC's effective oscillator sample rate depends on enabled oscillator configuration; adding voices may change frequency calibration. Freeze or rederive PIT timing parameters explicitly, and verify channel 0/2 interrupt behavior and PC speaker pitch after PSG initialization.
- Use shared oscillator allocation and one audio subsystem owner; don't have separate Tandy code reset the DOC, clobber wave RAM, or reprogram global oscillator state.
- If using a DOC wavetable for square waves, use waveform bytes that don't accidentally invoke special zero-sample halt behavior; verify loop mode and volume/DC offset.
- For tone periods, a 1024-entry 16-bit LUT per *actual DOC configuration* can translate divisor directly into DOC FC values. Recompute/select LUT when oscillator scan parameters change. Check representable pitch range and aliasing at extreme divisors.
- A 16-entry amplitude lookup approximates ~2 dB PSG attenuation steps to DOC amplitude; scale for multi-channel mixing and output clipping. Don't interpret 4-bit PSG attenuation as linear.
- For noise, begin with validated white- and periodic-noise waveforms if acceptable, but document that looping short noise samples will sound unlike a true LFSR. Later consider a correct variant-specific LFSR and a longer wavetable or event-driven noise updates.
- Preserve PIT channel 2 audio routing: on original Tandy, it reaches the PSG AUDIO IN, and audio output mux selection involves 8255 port `61h` bits 5–6. PCjr routing isn't identical. Test simultaneous PSG and PC speaker behavior rather than simply muting one when the other plays.
- Consider the original Tandy PSG write wait states only if guest timing or game compatibility proves they matter; functional correctness comes first.

**Implementation shape:** `psg_register_model` (accurate 8088 I/O register model) → `tandy_audio_backend` (DOC frequency/volume and noise) → existing shared DOC/timer driver. No floating point at runtime; all cheap tables.

## 7. Suggested milestones and go/no-go gates

### T0 — Audit existing XTGS (must precede implementation)

- Document video adapter abstraction, guest memory map, port handlers, BIOS video code, BDA identity, timing source, and DOC oscillator topology.
- Select exact original Tandy 1000 hardware profile and identify nontrivial compromises.
- Confirm the hardware port/register map from source documents.

**Gate:** No ambiguity about where guest `$B8000` writes land, how display and processor page selection work, or how DOC resources are shared.

### T1 — Mode 09h minimum viable graphics

- BIOS sets mode 09h; test program writes a known 320×200 color-index pattern directly into page 0.
- Deinterleave four 8 KiB scanline banks and copy 160 bytes per visible row to SHR.
- Validate RGBI palette indices, left/right nibble order, scanline order, screen edges, and full-frame output.

**Gate:** Pixel-perfect comparison against a trusted Tandy emulator test pattern (allow only clearly documented RGB analog-color differences).

### T2 — Video Array and page compatibility

- Implement 3DA/3DE index+palette, 3DF CPU/display page selection, relevant 3D8/3D9 and CRTC behavior.
- Support palette cycling, separate draw/display pages, page flip, retrace polling.
- Add dirty-line rendering and measure frame time.

**Gate:** Real direct-to-VRAM Tandy program/game can animate and flip pages without stale frames or hangs.

### T3 — Remaining early Tandy modes

- 08h: horizontally doubled 160×200×16.
- 04h/05h and 06h: correct color remapping and CGA-style interleave through Tandy profile.
- 0Ah: distinct two-byte bitplane combination and 640-mode SHR output.

**Gate:** Every mode passes deterministic framebuffer and palette tests, including a cross-line and bank-boundary pattern.

### T4 — PSG tone engine

- Port C0–C7 handler, register latch, 10-bit periods, four attenuation controls.
- DOC integration using a shared owner, square waveforms, calibration-aware FC and volume tables.
- Test all three voices independently and simultaneously with existing PIT clock/PIT channel 2.

**Gate:** Note pitches and volume envelopes are credible; XTGS timer unit tests and PC speaker regressions remain green.

### T5 — Noise, real games, and polish

- Implement noise modes and audio routing more accurately.
- Test Sierra AGI Tandy variants and other known-compatible games; verify *specific releases* rather than assuming every game/version has Tandy support.
- Confirm startup, mode reset, palette restoration, exit to DOS, and returning to GS/OS.

**Gate:** At least one substantial game/session (ideally a full representative gameplay test) with correct graphics, sound, and clean exit; no regressions in existing XT/CGA/EGA support.

## 8. Focused test matrix

| Test | What it detects |
|---|---|
| Four-band color bars, with each successive row a different color | Incorrect 4-way scanline interleave |
| Alternating nibble colors across row | Reversed pixel nibble order |
| Last 8 pixels and final line | Pitch/offset errors, off-by-one and bank-end mishandling |
| Writes to video RAM page not currently displayed | Incorrect CPU/display page coupling |
| 3DF page flip with no subsequent writes | Cached page/dirty-frame invalidation bug |
| Write 3DA index then 3DE palette entry | Incorrect port direction or indexed register logic |
| Read 3DA retrace in wait loop | Infinite hang or unstable timing |
| Mode 08h stripe pattern | Horizontal doubling correctness |
| Mode 0Ah alternating plane bits | Wrong plane order/bit position |
| PSG frequency sweep 3 tones | Divider decoding and DOC FC calibration |
| PSG attenuation sweep | Logarithmic volume translation |
| PSG white/periodic noise and tone-follow clock | Noise implementation and coupling |
| PSG playing concurrently with PIT/PC speaker and guest timer interrupts | DOC resource conflicts and port 61 routing |
| Switch Tandy → CGA/EGA → Tandy, then exit to GS/OS | State leakage and graphics/palette restoration |

For each regression record: machine profile, program version, accelerator clock, exact guest timer settings, audio osc configuration, output image/audio evidence, and measured emulated performance. Benchmark on stock 2.8 MHz and current accelerator if practical; the forthcoming 48 MHz unit is a performance target, not a correctness dependency.

## 9. Technical questions Claude should answer before coding

1. Does XTGS currently map video RAM directly into guest physical RAM, or is each video write trapped? Can a Tandy CPU page be aliased while keeping reads correct?
2. Is the EGA renderer already producing a packed 320×200 SHR frame? Can the adapter-specific renderers share **only the output path**, not guest VRAM storage?
3. Which BIOS/machine signature(s) does the selected real Tandy baseline require? Which target games actually check them?
4. Does XTGS emulate `3DAh` retrace dynamically already? If not, what's the least intrusive correct-ish implementation?
5. How many DOC oscillators are currently enabled, which are reserved for PIT/PC speaker, and does enabling 4 more affect the timing calibration?
6. Which initial Tandy model's PSG variant and `61h` audio mux semantics do we intend to match?
7. What is the minimum real-game compatibility target that justifies first release of Tandy support?

## 10. Reference sources (read these, especially the primary manuals)

1. **Tandy 1000 original technical reference / service manual**, video graphics storage, register map and palette control:  
   https://www.manualslib.com/manual/887518/Tandy-1000.html?page=53  
   https://www.manualslib.com/manual/887518/Tandy-1000.html?page=61  
   https://www.manualslib.com/manual/887518/Tandy-1000.html?page=63  
   https://www.manualslib.com/manual/887518/Tandy-1000.html?page=75
2. **Tandy 1000 SX Technical Reference** (confirms `03DFh` register numbering and page bits):  
   https://www.lo-tech.co.uk/downloads/manuals/tandy/Tandy_1000SX_Technical_Reference_Manual.pdf
3. **Original Tandy 1000 service manual** (PSG, 8255/audio mux, and video timing):  
   https://ftp.oldskool.org/pub/drivers/Tandy/1000/Tandy_1000_Service_Manual.pdf
4. **PC/Tandy mode capacities and pages (secondary cross-check)**:  
   https://www.classicdosgames.com/tutorials/grafix/chapter4.html
5. **Apple IIGS Super Hi-Res graphics modes (Apple technical note)** — note 640-mode's position-dependent 4-color groups:  
   https://savagetaylor.com/TIL/TIL01225.pdf
6. **PCjr/Tandy SN76496 technical summary with citations to original manuals**:  
   https://tanepiper.github.io/game-frame/hardware/tandy-psg
7. **DOSBox-X / MAME SN76496 variant differences** (secondary implementation evidence; treat exact noise behavior as variant-dependent):  
   https://dosbox-x.com/doxygen/html/sn76496_8h_source.html  
   https://github.com/mamedev/historic-mame/blob/master/src/emu/sound/sn76496.c

## 11. Proposed instruction to Claude

> Review this document against the XTGS source tree, with particular attention to Tandy 1000 page mapping and the current Ensoniq DOC-based 8253 implementation. Correct any inaccurate assumptions before implementation. Then propose the smallest architectural patch that adds a real Tandy machine profile and makes mode 09h work with direct guest VRAM writes, palette changes, and page flips, without EGA/CGA regressions. Implement graphics milestones T1–T3 before PSG sound, and test on real or trusted emulated 8088 workloads. Treat correctness, performance, and clean GS/OS integration as release gates rather than stopping when a demo boots.
