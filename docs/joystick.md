# The joystick

The IIGS's joystick (paddles 0 and 1, buttons 0 and 1) is the PC's: its
game port at 201h, and the BIOS's `INT 15h AH=84h`. `src/svc/joystick.s`;
the port reaches it in Mode B (`svc_portin`/`svc_portout`), the BIOS call
in both modes. A Tandy's joystick port is the same port.

## What a PC program sees

| | |
| --- | --- |
| a write to 201h | the paddles are read (`joy_sample`), and each axis's bit is given a number of reads to stay 1 |
| a read of 201h | bit 0 (X) and bit 1 (Y) while those reads last; bits 2 and 3 always 1 (no second stick); bit 4 and bit 5 are buttons 0 and 1, 0 while down; bits 6 and 7 are 1 |
| `INT 15h AH=84h DX=0` | the buttons in `AL` bits 4-7, as the port has them |
| `INT 15h AH=84h DX=1` | `AX`, `BX` = the paddles as they read, 0-255 (about 127 at rest); `CX`, `DX` = 0 |

The IIGS's buttons are also its Open-Apple and Option keys: holding one is
pressing the button. Option is XT/GS's key for the function keys and the
keypad as well (docs/keyboard.md), so Option+1 (F1) is also the second
button down for as long as Option is held, once a stick has been seen.

With no joystick the paddles read 255. A stick is taken to be there from
the first reading in which either axis is under 250 (`JOY_HAVE`); until
then the port reads FFh, as a PC with no game adapter does, the BIOS
answers zeros and buttons up, and a write looks at the paddles only once
in sixteen. (A stick held hard in the corner from the start is not seen
until it moves.)

## How long a bit lasts

On a PC the bit falls after a time, 24 us and 11 us for each kilohm of the
stick, and a program counts the turns of its own loop until it does. So
what a program reads depends on how fast the PC is and how long its loop
is, and programs of the PC's first years have their thresholds written in
for 4.77 MHz: Boulder Dash (1984) takes a count of 17 to 35 as the stick
at rest across, 16 and under as left, 36 and over as right.

The time this machine takes for the guest's loop says nothing of a PC's,
so the port counts in reads, and works out how many from the loop itself:

- the time is `T = 24 us + 3.6 us * paddle` (0-255: a stick of 85K; a
  PC's are 100K with a trimmer);
- an 8088 is held up by fetching its code, 4 cycles a byte, so a loop of
  `L` bytes turns in about `4L + 10` cycles of 0.2095 us;
- `reads = (paddle + 7) * 60 / (14 L + 35)`, 1 at least.

`joy_loop` finds `L` at the first read after a write: the first short jump
backwards after the `IN` (a `LOOP`, a `Jcc`, a `JMP`) that lands on the
`IN` or within 16 bytes before it, looking 48 bytes on. If there is none,
`L` is 5 (`IN`, `TEST`, `LOOPNZ`). The count is then the same at any
speed of the IIGS.

| loop | bytes | at rest | end to end |
| --- | --- | --- | --- |
| `IN AL,DX` / `TEST AL,1` / `LOOPNZ` | 5 | 77 | 4-149 |
| JOYTEST's (`tests/demo/joytest.asm`) | 12 | 39 | 2-77 |
| Boulder Dash's | 19 | 26 | 1-52 |

## Reading the paddles

`joy_sample` is John Brooks's `GetJoyXY` (by way of `../ddiigs`): `$C070`
starts the paddles' timers and one loop counts both, a count every 11
cycles on average, with the processor at 1 MHz for as long (the speed
register's bit 7 shifted out and back) and interrupts off: 3 ms at most,
0.2 ms with the stick hard left and up. It runs at each write to 201h and
each `INT 15h AH=84h DX=1`.

## Its test

`make test-joy` (`tools/joy_test.py`): FreeDOS runs `JOYTEST L`, MAME has
its Apple joystick in the game port (`XTGS_GAMEIO=joy`, which
`tools/mame/mamerun.py` passes on), and the harness puts the stick in
twelve places and presses the buttons; `JOYTEST` starts a line at each
change, and the lines must show every state in order, by the port and by
the BIOS. `JOYTEST.COM` is on the FreeDOS folder and floppy: on a IIGS it
shows what the stick reads.

## Not done

- A real IIGS and a real stick: run in MAME only. An accelerator that
  does not slow down for the paddles reads them short.
- The loop is found by its bytes, not by decoding: a loop that goes back
  by a near jump, or one whose jump is further on than 48 bytes, is
  taken for 5 bytes long, and reads long. A program that measures the
  bit with the 8253 instead of counting reads gets this machine's own
  time, which is not a PC's.
- No second stick (the IIGS's paddles 2 and 3), no calibration by the
  user, no keyboard stand-in for a stick.
- Under the .COM runner (Mode A) the port is not there; the BIOS call is.
