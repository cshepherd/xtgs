# The mouse

The IIGS's mouse is the PC's, through the Microsoft mouse driver's
`INT 33h`. There is no driver to load (no `MOUSE.COM`, no `CTMOUSE`): in
Mode B the BIOS answers `INT 33h` itself. `src/svc/mouse.s`.

The line `MOUSE=OFF` in `XTGS.CMD` leaves the PC without one (`INT 33h`
then answers nothing, as with no driver loaded), for a program that
misbehaves when it finds a mouse, or to load a driver of your own for a
mouse on a serial port (docs/serial.md).

## What a program sees

| `AX` | |
| --- | --- |
| 00h, 21h | reset: `AX` = FFFFh, `BX` = 2 buttons; the mouse in the middle, the cursor hidden, no handler |
| 01h, 02h | show and hide the cursor (hidden as many times as it was hidden) |
| 03h | `BX` the buttons (bit 0 left, bit 1 right), `CX`, `DX` the place |
| 04h | put the mouse at `CX`, `DX` |
| 05h, 06h | presses and releases of button `BX` since the last call, and where the last one was |
| 07h, 08h | the range across and down |
| 0Ah | the text cursor's two masks (`BX` = 0; the hardware cursor, `BX` = 1, is not done) |
| 0Bh | mickeys moved since the last call |
| 0Ch | a handler at `ES:DX` for the events in `CX` |
| 24h | `BX` = 0800h (driver 8.00), `CH` = 4 (a PS/2 mouse) |

Any other function returns with the registers as they came. Not done:
the graphics cursor (09h) and everything about its shape, the light pen
(0Dh, 0Eh), the mickey ratio and the speed threshold (0Fh, 13h, 1Ah,
1Bh: accepted, without effect), the exchange and the alternate handlers
(14h, 18h), saving the driver's state (15h-17h).

The place is in the driver's 640 by 200 whatever the mode: in an 80
column text mode a cell is 8 by 8, in a 320 pixel mode a pixel is 2
across. A count of the IIGS's mouse is two across and one down, and two
mickeys either way. The IIGS's mouse has one button, the left; a second
button on an ADB mouse is the right.

## The cursor

In the text modes the cursor is the driver's software cursor: the cell
under the mouse goes through the two masks (by default its colours are
turned round), in the guest's own buffer at B800, as a driver does it; so
a program that reads the screen while the cursor shows reads the cursor,
and one that writes under it should hide it first, as on a PC. The cell
is put back when the mouse moves on, unless the program has changed it.

There is no cursor in the graphics modes: a program that draws its own
from the place (Sierra's games) has one, a program that relies on the
driver's arrow has none.

## The handler

`ms_poll` reads the mouse once a frame. When something a handler asked
for has happened it raises `PIC_MOUSE`, and the core's slot enters the
stub at `F000:MS_OFF` as an interrupt enters a handler (FLAGS, CS and IP
pushed, IF clear), but by no vector: DOS keeps the hardware interrupts'
vectors for itself. The stub saves the registers, asks hypercall 259 for
the event (`AX` the events, `BX` the buttons, `CX`, `DX` the place, `SI`,
`DI` the mickeys), calls the handler far, tells hypercall 260 it is back,
restores and returns. The handler is called once at a time: events that
happen while it runs are joined into the next call. Sixty calls a second
at most.

## DOS and vector 33h

FreeDOS points vectors 20h-3Fh at an `IRET` of its own as it starts, 33h
among them, as DOS does before any driver is loaded. Half a second after
vector 33h has left the BIOS, `ms_poll` points it back, once: a program
that hooks `INT 33h` later keeps its hook.

## The IIGS's side

The ADB GLU's registers, read directly: `$C027` bit 7 says the mouse has
moved or its button changed, `$C024` then gives X and Y in turn, seven
bits signed, bit 7 a button (0 is down): the mouse's own in the Y byte, a
second one's in the X byte. Nothing is asked of the firmware; the mouse's
interrupt (`$C027` bit 6) is turned off while the PC runs, so that the
firmware does not take the data first, and put back as it was at the end
(`ms_close`). The driver costs two register reads a frame.

## Testing

`make test-mouse` (`tools/mouse_test.py`): FreeDOS runs `MOUSETST L`
(`tests/demo/mousetst.asm`, on the FreeDOS diskette and folder as
`MOUSETST.COM`) while the harness moves MAME's mouse right, down, presses
the button, moves up and left and releases it; the program's lines (the
place and buttons by function 03h, and what its handler was called with)
are held to that. `mouse_test.py MOUSE=OFF` must find no driver.
`MOUSETST` without the `L` shows the text cursor and one line.

Run in MAME only, from ProDOS 8, with the layout moved (`XTGS_LAYOUT=alt`)
and from GS/OS (`XTGS_FRONT=s16`). Not checked: a real ADB mouse's counts
and its second button, and the edge of MAME's own mouse fields (the
harness keeps away from it).
