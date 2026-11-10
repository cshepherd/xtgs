# The clock: the IIGS's date and time as the PC's

The guest's date and time are the IIGS's own (`src/svc/clock.s`). Nothing is
configured: whatever the IIGS's clock says (the Control Panel sets it) is
what `DATE`, `TIME`, `DATE$`, a file's new timestamp and `INT 1Ah` say in
the guest, in Mode A and Mode B alike.

Verified in MAME (`apple2gs`, ROM 3; `make test-clock`), under both front
ends and both layouts. **It has not been run on a real IIGS.**

## What the guest sees

| Interface | Answer |
| --- | --- |
| `INT 1Ah AH=02` | the time, BCD: CH hour, CL minute, DH second, DL=0 (no daylight flag), CF clear |
| `INT 1Ah AH=04` | the date, BCD: CH century, CL year, DH month, DL day, CF clear |
| `INT 1Ah AH=00` | the tick count in CX:DX, and in AL the midnights passed since the last call (then cleared) |
| `INT 1Ah AH=01` | sets the tick count, clears the midnight flag |
| `INT 1Ah AH=03, 05` | accepted (CF clear) and ignored: the clock is read-only |
| `0040:006C`, `0040:0070` | the BIOS tick count and its midnight flag |
| `INT 21h AH=2Ah` (Mode A) | CX year, DH month, DL day, AL weekday (0 = Sunday) |
| `INT 21h AH=2Ch` (Mode A) | CH hour, CL minute, DH second, DL=0 (no hundredths) |

In Mode B the DOS functions are the guest DOS's. FreeDOS reads the real-time
clock once as it starts (`INT 1Ah AH=04/02`), sets the tick count from it,
and from then on keeps its time from the tick count alone and its date from
the midnight flag.

**The guest cannot set the IIGS's clock.** `DATE` and `TIME` under FreeDOS
change DOS's own idea of the time (it sets the tick count, which XT/GS keeps:
below) until the next boot; the calls that would write the real-time clock
are swallowed. Mode A has no `INT 21h AH=2Bh/2Dh`.

## Reading the clock

`clk_read` calls the Misc Tools' ReadTimeHex (`$0D03`) through the Toolbox
dispatcher: eight bytes, which come off the stack as four words - minute and
second; year less 1900 and hour; month and day, both counted from 0; weekday
(1 = Sunday) in the high byte of the last. Both front ends leave the Tool
Locator and the Misc Tools started while the core runs (the ProDOS 8 loader
starts them in `tools_up`; GS/OS has them up before an application runs),
and that is all the call needs: no interrupt, no memory of the caller's. In MAME one call costs
about 5 ms, so it is made when asked for and once every two seconds, never
per tick.

The year is `1900 + byte`, good to 2155.

## The tick count

At PC init (`clk_init`, from `build_bda` and again from `svc_sndopen` as the
timer starts, so that the time a program or a kernel took to load is not
missing) the count at `0040:006C` is set to the time of day in ticks. A
day is `$1800B0` ticks, 1,193,180 / 65,536 = 18.2065 a second, and
`clk_ticks` gets there without a division:

    ticks = hour * 65543 + minute * 1092 + second * 18
          + (hour * 85 + minute * 100 + second * 53) / 256

which is within a tick of the exact figure all day and never runs backwards.

From then on IRQ0 counts (`clk_tick`: the BIOS's `INT 08h` in Mode B, the
frame's work in Mode A). At `$1800B0` the count goes back to 0 and the
midnight flag goes up by one, as the PC's BIOS does.

## Lost ticks, and making them up

A PC keeps time by counting interrupts, and here interrupts are lost. The
DOC's timer interrupt (`docs/sound.md`) counts the IRQ0s owed to the guest
in `vTICK`, up to `TICK_MAX` (16) and no further - a guest cannot be handed
a hundred `INT 08h` in a row after a slow call. But one BIOS call can take
seconds here (a file read on the shared drive, a scroll, FreeCOM printing a
line), and a guest that keeps interrupts off loses ticks too. A FreeDOS boot
to the prompt loses about one tick in nine: left alone, DOS's clock is 2.5
seconds slow by the time the first program runs, and slower with every
long call after that.

So the count is held to the clock (`clk_sync`, from `vbl_work` every 128
frames, about two seconds, whenever a PC is running):

- the clock is read and turned into ticks; the difference from the last
  reading (through midnight if need be) is what went by;
- less the ticks that were counted in that time (`clk_seen`), and less the
  change in the IRQ0s held for the guest (`vTICK`: those are late, not
  lost);
- the remainder adds to what is owed (`clk_owed`). When that reaches
  `CLK_STEP` (20 ticks) it is added to the tick count at once - through
  midnight, with the flag, if it comes to that - and owed starts again at
  0.

The clock reads in whole seconds, so what went by is known to a second
(18.2 ticks) and no better. `CLK_STEP` is just above that: a count that
keeps up on its own is never touched, and one that has been moved runs
within a second of where an unbroken count would be.

What is compared is always amounts gone by, never the tick count with the
time of day. That is what lets the guest have a time of its own: after
`TIME 12:00` under DOS (or `INT 1Ah AH=01`, which also restarts the
reckoning: `clk_mark`), or a direct write to `0040:006C`, the count carries
on from the new value at the clock's rate. Other cases:

- a count that runs ahead (a guest that speeds IRQ0 up and passes every
  interrupt on to the BIOS) makes owed negative; nothing is taken back, and
  owed is held at -64 so that such a spell is forgotten soon after;
- half a day or more between two readings means the IIGS's clock was set
  under us: that interval is dropped;
- a count already past a day's ticks (a guest's own doing) is added to
  without the midnight wrap.

`CLK_PAID` and `CLK_MADE` in the results bank (`src/include/pc.s`) count the
times the count was moved and the ticks added, beside `DOC_IRQS` and
`DOC_DROPS`.

Mode A is treated the same, though less hangs on it there: its ticks are
counted once a frame from the same `vTICK` with no `INT 08h` to deliver,
and its DOS answers `2Ah/2Ch` from the clock itself.

## An interrupt the guest never took

The test for this found a fault in the core that had nothing to do with
clocks. The core looks for interrupts every 16 guest instructions (the
slot). A program that waits for the tick count to change by polling
`INT 1Ah` in a loop whose length divides 16 - eight instructions, the BIOS's
`IRET` among them - met the slot at the same instruction every time, and that
instruction was inside the BIOS's stub, where interrupts are off. IRQ0 was
owed for ever and never delivered: the count moved only when ticks were
made up, a second's worth at a time, and with the catch-up off it stood
still and the loop never ended.

Now the instructions that can turn interrupts on ask for a look themselves
(`irq_soon`, `irq_sti` in `src/core/cpu.s`): in Mode B, with an IRQ0 owed or
a scancode waiting, `IRET` and `POPF` bring the slot to the next instruction
and `STI` to the one after it, which is when an 8088 takes an interrupt
after `STI`. The cost is a test of `vPCMODE` on those three instructions.

## The test

`tests/com/clock.asm` prints the date and time every way a PC program can
ask for them (`D` DOS date, `T` DOS time, `R` real-time clock, `K` tick count
and midnight flag), waits for 20 ticks in the eight-instruction loop above
(`W`: the count must have changed tick by tick), keeps interrupts off for
ten of the clock's seconds, and prints everything again. It runs in
`make test-com` with only the shape of its output judged.

`tools/clock_test.py` (`make test-clock`, `DOS=1` for `--dos`) judges the
values. MAME's IIGS starts with the host's local date and time and counts
emulated seconds from there, so the guest's clock must lie between the
moment the run began and the moment it ended plus the seconds it emulated;
DOS's date and time must be the real-time clock's to within three seconds,
the weekday right, and the tick count within three seconds of the time of
day. Without `--dos` the program runs under the stub DOS (command `C`);
with it FreeDOS boots from a folder (command `S`) and runs it from
`AUTOEXEC.BAT`, and the three seconds must hold again after the ten with
interrupts off - which they do only with the lost ticks made up (with
`CLK_STEP` out of reach DOS is 2.5 seconds behind at the first reading and
11.3 at the second). `XTGS_LAYOUT=alt` and `XTGS_FRONT=s16` apply as for
the other tools.

## Limits

- Read-only, as above. Writing the IIGS's clock from the guest
  (WriteTimeHex from `INT 1Ah AH=03/05`) would be small, and is not done:
  a DOS program setting the date on the machine it is a guest of seemed
  the wrong default.
- No hundredths: Mode A's `2Ch` returns DL=0. FreeDOS makes its own from
  the tick count.
- No alarm (`INT 1Ah AH=06/07`), no CMOS at ports 70h/71h: a program that
  reads the AT's clock chip itself gets nothing. An XT had none either.
- After a step the count has jumped by a second or more. A program timing
  something short across a jump sees it; one that waits for N ticks waits
  less. The jump happens only when ticks were lost, when such a program was
  already wrong by as much the other way.
