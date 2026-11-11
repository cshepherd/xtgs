# Sound and the timer: the Ensoniq DOC as the PC's 8253 and the Tandy's SN76496

The IIGS's Ensoniq DOC (ES5503) stands in for two of the PC's 8253 timer
outputs (`src/svc/sound.s`):

- **channel 2, gated by port 61h** is the PC speaker: a square wave from two
  DOC oscillators;
- **channel 0** is IRQ0: a third, silent oscillator whose wrap interrupt is the
  18.2 Hz tick (or whatever rate the guest programs).

On a Tandy 1000 (`VIDEO=TANDY`) eight more oscillators are the machine's
three-voice sound chip: The Tandy 1000's three voices, below.

Both are live in Mode A (`C`) and Mode B (`D`, `S`). The core opens the DOC before
`run_guest` and closes it after (`svc_sndopen` / `svc_sndclose`, SVC entries
+27 and +30); every guest `OUT` to ports 40h-61h goes to `svc_sndport` (+33).

Everything below is verified in MAME (`apple2gs`, ROM 3). **The sound has not
been confirmed on a real IIGS.**

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

Three oscillators are enabled on a PC (eleven on a Tandy, below), so the DOC visits each at
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

- **Mode B**: the core's slot check (`cpu.s`, every `SLOT_N` = 4 control
  transfers of the guest) delivers one INT 08h per count when the guest's IF is set.
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

## The Tandy 1000's three voices (`VIDEO=TANDY`)

On a Tandy (docs/tandy.md) the DOC is also the machine's sound chip, the
TI SN76496 at ports C0h-C7h (one register, eight addresses): three square
waves and a noise, each with an attenuation. A byte with bit 7 set names
a register in bits 6-4 and gives its low four bits; a byte without gives
the high six bits of the tone period last named, or the four again for
the other registers.

| Register | What |
| --- | --- |
| 0, 2, 4 | a tone's period `n`, ten bits: 3,579,545 / 32n Hz (0 is 1024) |
| 1, 3, 5 | its attenuation, 2 dB a step, 15 silent |
| 6 | the noise: bits 0-1 the shift rate (the chip's clock / 512, / 1024, / 2048, or once a cycle of tone 2), bit 2 white or periodic |
| 7 | the noise's attenuation |

The core sends the ports to `svc_portout` in both modes of running
(`port_out`, `src/core/ops_misc.s`) and that to `psg_write`; on a PC that
is not a Tandy nobody is there. A read answers FFh, and a word `OUT` is
its low byte.

Eleven oscillators are enabled instead of three, so the DOC visits each
at 7,159,090 / 8 / 13 = **68,837 Hz**, and the speaker's and the timer's
frequency constant is the Tandy's (`FC_KT`, 52/3 where a PC has 20/3):

| Osc | Use |
| --- | --- |
| 0, 1 | the speaker, as on a PC |
| 2-7 | the three tones, a pair each |
| 8, 9 | the noise |
| 10 | the timer |

A voice is a pair of oscillators, one on each DOC channel, at the volume
its attenuation gives (`psg_vtab`: 136 with none, 2 dB a step; the
speaker's two are 112). The pair is halted while there is nothing to hear
and keyed on back to back, which keeps the two in phase: so a new period
halts them, writes it and starts them again, and an attenuation alone is
written as they run.

- **A tone** is the speaker's square wave at `FC = 2^21 * 13 / n` for
  `r` = 7 (`psg_tone`; `fc_div` drops `r` as `pit_fc` does), which is the
  chip's frequency to 0.002 %. A period under `PSG_MINDIV` = 6 (over
  18.6 kHz) is silence: the DOC's visits are too few for it, and the
  programs that set one mean a level, not a pitch (Not done, below).
- **White noise** is the chip's shift register written out: DOC RAM
  `$8000-$FFFF` holds 32,768 steps of it, a bit a byte (`psg_ntab` at
  open: fifteen bits, the exclusive-or of the lowest two coming in at
  the top, x^15 + x + 1 from one bit set, 32,767 states). At the three
  fixed rates the whole table plays (FC 52, 26, 13: the rates exactly),
  so what is heard is the chip's sequence with one bit more each time
  round. With tone 2 as the clock the rate may be anything; a slow one
  plays a shorter table from the same place (`psg_noise`: the DOC's
  frequency has the precision of the table's length), never under two
  seconds of the sequence, and the rate is right to 1.6 %.
- **Periodic noise** is one bit in fifteen: a pulse a fifteenth of a
  cycle wide (DOC RAM page 1) played as a tone of fifteen times the
  period, at `psg_ptab`'s volumes, which make its height a square wave's.
- A write to register 6 starts the chip's shift register again, and here
  the table (or the pulse) from its start.

For the harness every DOC register written is kept in `DOC_REG` (256
bytes, the results bank) and logged in order in `DOC_LOG`, a ring of
4096 entries (`DOC_LOGN` counts them all), with each byte the guest gave
the chip marked in it (`DOC_MARK`); `PSG_REG` is the chip's eight
registers, `PSG_LATCH` the one last named, `PSG_WRITES` the bytes,
`DOC_NOSC` the oscillators enabled and `DOC_SUM` the noise table's
checksum.

### Its tests

`make test-com COM=psg` (`tests/com/psg.asm`, 129 bytes to the chip
through each of the port's addresses and both forms of `OUT`: the three
tones, attenuation sweeps of a tone, the pulse and the noise, a period's
two halves each alone, period 0 and periods 1-7, a data byte to an
attenuation, every noise setting and its restart, then the speaker and
the timer reprogrammed with the chip running). `tools/psgdoc.py` is the
judge: a model of the chip and of the DOC's registers written from the
data sheets, apart from `sound.s`, which replays the log and after each
of the guest's bytes holds every voice to what the chip would be
playing: its pair running if and only if it is audible, the two
oscillators alike and on different channels, free-running with no
interrupt, the frequency (a tone to 0.02 %, the fixed noise rates
exactly), the table, the volume; no frequency written to a running
oscillator, the partner's key-on next in the log, nothing written to a
voice the byte did not concern, a restart of the noise where the chip
restarts. The speaker and the timer are held to the manifest's `"psg"`
key (what count each plays from which byte), and the noise table to the
model's by its checksum. `psgpc` is the same program on a PC: no byte
reaches the DOC, three oscillators. Every other `.COM` test gets the
short form (the oscillator count, the checksum, the timer's rate at the
end).

`make test-psg` (`tools/psg_test.py`, `tests/snd/psgwav.asm`) is the
other end: fourteen sounds recorded by MAME and measured, below.

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

### The Tandy's chip (`make test-psg`)

`tests/snd/psgwav.asm` plays fourteen sounds, nine ticks each and four
apart; `tools/psg_test.py` records them (MAME's WAV: 48 kHz, the DOC's
two channels) and measures each on both channels. A 256-byte table is
256/255 sharp as above; the noise's 32K table is not.

| Sound | Asked | Measured |
| --- | --- | --- |
| tone 0, period 254 | 440.40 Hz | 442.12 Hz (x 256/255: 442.12) |
| tone 1, period 170 | 658.00 Hz | 660.57 Hz |
| tone 2, period 1023 | 109.35 Hz | 109.77 Hz |
| the three together (254, 202, 170) | three lines of one tone's strength | 442.1, 555.9, 660.6 Hz at 1.00, 0.99, 1.00 |
| tone 0, attenuation 5 | 10 dB down: 0.316 | 0.316 |
| tone 0, attenuation 10 | 20 dB down: 0.100 | 0.103 (the volume is a whole number: 14 of 136) |
| white noise, clock / 512 | 6991.3 shifts a second | 3366 of 3366 bits the shift register's, at 6991.3 |
| white noise, clock / 2048 | 1747.8 | 869 of 869 bits, at 1747.8 |
| periodic, clock / 512 | 466.08 Hz, a square wave's height, high 1/15 | 467.92 Hz, height 1.00, high 6.0 % |
| white, tone 2 the clock (period 20) | 5593.0 shifts a second | 2636 of 2636 bits, at 5579.6 (FC 166 for 166.4) |
| periodic, tone 2 the clock | 372.87 Hz | 374.32 Hz |
| the speaker, count 1193 | 1000.15 Hz at 112/136 = 0.824 of a tone | 1004.06 Hz at 0.823 |
| the speaker and tone 0 | both lines | 1004.1 Hz at 0.82, 442.1 Hz at 0.99 |
| tone 0, period 32 | 3495.65 Hz | 3509.32 Hz, level 0.985 |

The sounds' spacing gives the timer with eleven oscillators: 18.30 ticks
a second (18.2065 x 256/255 = 18.28; the sounds start on the guest's
tick, a frame's jitter in nine seconds). By its registers the timer is
FC 4437 where 4437.33 is exact, 18.2051 Hz, and `clk_sync` makes up the
tick that costs every two hours. The three tones together peak at 21 % of
MAME's full scale, so nothing clips.

The measurement was turned against six deliberate faults in `sound.s`
(a volume table entry, the tone constant 0.24 % off, the shift
register's taps, the pulse's volume, the timer constant, the noise
constant 4 % off): each failed the test at the sound it concerns. (The
noise constant 0.24 % off did not, rightly: the frequency registers it
makes are the same whole numbers.)

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
  should be exact. How loud eleven oscillators are against three on a real
  DOC's output is not known either (the DOC time-shares one DAC).
- The Tandy's chip: a tone period under 6 is silence, so sampled sound
  played through a voice's attenuation (a period of 1 and the level
  written at speed) is not heard, and would be far beyond the guest's
  speed besides. The sequence is TI's SN76496's; a Tandy's NCR 8496 and
  the PSSJ's have another shift register by MAME's reading of them
  (noise all the same, not the same bits). A new period starts the voice's cycle again, the chip
  carries on from where it was: a program that sweeps a pitch byte by
  byte hears the same pitches, each from its edge, and the period half
  written between a tone's two bytes plays for that moment as on the
  chip. A voice's two oscillators are keyed on some 40 us apart. Port
  61h's multiplexer bits (which of the chip and the speaker reach the
  amplifier) and the BIOS's sound services are not there: both always
  sound. Opening the DOC takes about a second longer on a Tandy (the
  noise table), and `svc_sndclose` leaves the oscillator count as it was.
- 8253 modes other than the square wave; reads of the counters are synthetic.
- The 8259 PIC: no mask register, no EOI. IRQ0 is delivered whenever IF is
  set and a tick is owed.
- Early in a FreeDOS boot some ticks are still dropped (long BIOS disk reads
  with more than `TICK_MAX` periods owed).
