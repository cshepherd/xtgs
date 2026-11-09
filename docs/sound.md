# Sound and the timer: the Ensoniq DOC as the PC's 8253

The IIGS's Ensoniq DOC (ES5503) stands in for two of the PC's 8253 timer
outputs (`src/svc/sound.s`):

- **channel 2, gated by port 61h** is the PC speaker: a square wave from two
  DOC oscillators;
- **channel 0** is IRQ0: a third, silent oscillator whose wrap interrupt is the
  18.2 Hz tick (or whatever rate the guest programs).

Both are live in Mode A (`C`) and Mode B (`D`). The core opens the DOC before
`run_guest` and closes it after (`svc_sndopen` / `svc_sndclose`, SVC entries
+27 and +30); every guest `OUT` to ports 40h-61h goes to `svc_sndport` (+33).

Everything below is verified in MAME (`apple2gs`, ROM 3). **It has not been run
on a real IIGS.**

## Ports

| Port | Write | Read |
| --- | --- | --- |
| 40h | channel 0 count (LSB/MSB per the access mode) -> the timer oscillator's rate | synthetic free-running counter (`port_in8`, not the DOC) |
| 42h | channel 2 count -> the speaker's pitch | synthetic, as 40h |
| 43h | control word: access mode for channel 0 or 2. Latch commands and channel 1 are ignored | - |
| 61h | bit 0 = timer-2 gate, bit 1 = speaker data. Tone when both are set and the count is playable | the last value written |

The 8253's mode bits are not modelled: both channels are treated as square-wave
generators (modes 2 and 3 are the same to us), which is what the BIOS, DOS,
GW-BASIC and every speaker routine uses. With the gate low and bit 1 toggled
(the "drive the cone directly" technique) each toggle clicks the IIGS's own
speaker (`$C030`); PWM digitised sound that way is far beyond the guest's
speed and is not attempted.

## The oscillators

Three oscillators are enabled, so the DOC visits each at
7,159,090 / 8 / 5 = **178,977 Hz**. All three free-run the same 256-byte
square wave at DOC RAM `$0000` (128 x `$FF`, 128 x `$01`; a `$00` sample would
halt an oscillator).

| Osc | Use |
| --- | --- |
| 0, 1 | the speaker, on DOC channels 1 and 0 (both sides of a stereo card), volume `SPK_VOL`, started and stopped together |
| 2 | the timer: volume 0, interrupt enabled |

A 256-byte table at resolution `r` plays at `SR * FC / 2^(17+r)`, and the PIT's
clock is 7,159,090 / 6 Hz, so for a count `n`

```
FC = 2^(17+r) * 20 / (3 * n)        ($06AAAAAB / n at r = 7)
```

`pit_fc` does the division and drops `r` by one for each halving needed to
bring FC under 16 bits. The IIGS's master clock and the PC's are both multiples
of the NTSC colour burst, which is why the conversion is an exact ratio.

Limits:

- `SPK_MINDIV = 64`: a channel-2 count under 64 (over 18.6 kHz) is silence.
  Programs use that as "off" (`SOUND 32767,n`).
- `TMR_MINDIV = 2048`: channel 0 is never run faster than 583 Hz. GW-BASIC
  asks for 400 Hz while it plays music; anything much faster would spend the
  whole machine in the guest's INT 08h handler.

## The timer interrupt

The oscillator's interrupt arrives through the firmware's sound vector
(`$E1:002C`) at `snd_irq`, which acknowledges it (reads the DOC's
oscillator-interrupt register until it is empty) and counts it in `vTICK` in
the guest direct page. Nothing else happens at interrupt time. Then:

- **Mode B**: the core's slot check (`cpu.s`, every `SLOT_N` = 16 guest
  instructions) delivers one INT 08h per count when the guest's IF is set.
  The default INT 08h (`disk.s`) increments the BDA tick count and calls
  INT 1Ch, as a PC BIOS does.
- **Mode A**: nothing is delivered to the guest; `vbl_work` drains `vTICK`
  into the BDA tick count once a frame.

This replaced polling the VBL bit and deriving 18.2 Hz from the frame rate.
The tick rate is now the PIT's own: a guest that reprograms channel 0 gets
its interrupts at the rate it asked for.

A PIC holds one pending IRQ0. `vTICK` holds up to `TICK_MAX` = 16, because a
BIOS service here (a screen scroll, a disk read) can take several tick periods
of host time that are none of the guest's, and losing them would make the
guest's clock run slow. Interrupts past that are dropped and counted in
`DOC_DROPS`. When channel 0 is reprogrammed `vTICK` falls back to one: ticks
owed at the old rate are not owed at the new one (without this, GW-BASIC's
return from 400 Hz to 18.2 Hz delivered a burst of stale ticks to the BIOS
clock).

Housekeeping the interrupt needs:

- The firmware services an interrupt taken with S outside page 1 on page 1 at
  the same low byte. The core's stack is at `$0BFF`, so page 1 is saved at
  open and restored at close (`snd_pg1`).
- The GLU's control and address registers (`$C03C`-`$C03E`) are shared with
  the interrupt handler: every foreground routine touches them inside `SEI`.
- `svc_sndclose` halts every oscillator, restores the firmware's vector and
  the caller's I bit.

Counters for the harness, in the results bank (`src/include/pc.s`):
`DOC_IRQS` (interrupts taken), `DOC_DROPS` (not counted into `vTICK` because
it was full), `SPK_PORT` (port 61h's last value).

## Measured (MAME)

MAME's es5503 runs its oscillators 256/255 sharp: a programmed 440 Hz comes out
at 441.7 Hz, and the 18.2065 Hz tick at 18.28 Hz. The numbers below are from
MAME's WAV output and carry that factor.

A `.COM` that programs the PIT directly (Mode A), one second each:

| Asked | Measured |
| --- | --- |
| 440 Hz | 441.7 Hz |
| 880 Hz | 884.7 Hz |
| gate off | silence |
| 262 Hz | 262.6 Hz |
| 3000 Hz | 2994 Hz |

GW-BASIC under FreeDOS (Mode B):

| Statement | Measured |
| --- | --- |
| `SOUND 440,18.2` | 441.4 Hz for 1.00 s |
| `SOUND 880,18.2` | 882.9 Hz for 1.00 s |
| `SOUND 32767,9` | silence |
| `PLAY "MF T120 O3 L4 C E G"` | 524.7 / 660.7 / 780.5 Hz, 0.45-0.50 s each, 0.10-0.15 s apart |
| `BEEP` | 801.9 Hz for 0.30 s |
| `PLAY "MB T180 O3 L8 CDEFGAB"` then more statements | seven notes, 524.6 to 991.8 Hz, 1.25 s in all (0.18 s each; 0.167 s nominal) |

One capture in fourteen of the same run showed a single pulse at a speaker
oscillator's level on DOC channel 2 (the silent timer's). The emulated machine
was identical in all of them (same tick, interrupt and port traces); MAME's
es5503 fills its mix buffer interleaved and reads it back planar, which only
agrees while each stream update is one sample long, so this is taken to be a
capture artifact rather than a register write of ours. Not seen again.

BDA ticks and DOC interrupts both run at 18.28 Hz at the FreeDOS and GW-BASIC
prompts with no drops, and stay at 18-19 Hz through GW-BASIC's switches to
400 Hz and back.

## What GW-BASIC does with the timer

For `SOUND` and `PLAY` GW-BASIC reprograms channel 0 to a count of 2983
(400 Hz) and installs its own INT 08h handler, which counts note durations and
chains to the previous handler once in 22 ticks (so the BIOS clock still
advances at 18.2 Hz). In foreground `PLAY` it switches channel 0 between 2983
and 0 around each note. That handler costs about 19 guest instructions a tick;
at 400 Hz that is some 7,600 instructions a second out of the ~14,000-18,000
this interpreter manages at an idle prompt, so:

- foreground music keeps time (the interpreter is just waiting for the note);
- **background music (`MB`) with the program still running loses about 6 % of
  the 400 Hz ticks**, so notes run about 8 % long, and the BASIC program
  itself gets what is left of the machine.

Two behaviours that look like bugs here but are this GW-BASIC build's own
(reproduced under QEMU): `TIMER` returns 0, and `PLAY` with `>` in a string
variable gives "Illegal function call".

GW-BASIC also polls the joystick from its INT 1Ch hook through INT 15h
AH=84h. That is answered (`bios.s` `int_15`: no switches pressed, no sticks);
other INT 15h functions return CF set, AH=86h.

## Related: the text renderer's shadow

Timer interrupts at 400 Hz only work if the host is not busy elsewhere, and
it was: GW-BASIC's idle loop rewrites the status line and cursor cell with
unchanged contents, each write marks the page dirty, and the flush re-rendered
whole rows every frame (65 % of host time; the idle prompt ran at ~2,000
guest instructions a second). `render_row` (`video.s`) now keeps a shadow of
what each row's pixels show and draws only cells that differ, and INT 10h
AH=09h/0Ah mark the cursor's row instead of the whole screen. The idle prompt
runs at ~18,300 instructions a second and fast typing no longer loses keys.

`tools/textshr.py` checks the result: it renders the text buffer the way
`render_cell` does and compares it to the SHR pixels. `tools/judge_com.py`
runs it on every text-mode test, so a shadow that goes stale fails the suite.

## Not done

- Real hardware. In particular the 256/255 pitch error is MAME's; a real DOC
  should be exact.
- 8253 modes other than the square wave; reads of the counters are synthetic.
- The 8259 PIC: no mask register, no EOI. IRQ0 is delivered whenever IF is
  set and a tick is owed.
- Early in a FreeDOS boot some ticks are still dropped (long BIOS disk reads
  with more than `TICK_MAX` periods owed).
