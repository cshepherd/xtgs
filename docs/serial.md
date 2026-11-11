# The serial ports

The IIGS's two serial ports can be the PC's: the modem port as COM1, the
printer port as COM2. Each is asked for by a line of `XTGS.CMD`:

```
COM1=MODEM
COM2=PRINTER
```

Either, both or neither. Without its line a port is not there: nothing in
the BDA, FFh at its addresses, and the IIGS's port is never touched.
`src/svc/serial.s`; Mode B for the ports themselves, `INT 14h` in both modes.

## What a PC program sees

| | COM1 | COM2 |
| --- | --- | --- |
| the IIGS's port | modem (SCC channel B) | printer (SCC channel A) |
| the 8250's registers | 3F8h-3FFh | 2F8h-2FFh |
| its interrupt | IRQ4 (`INT 0Ch`) | IRQ3 (`INT 0Bh`) |

The BDA lists the ports that are there from 40:00 on, as a PC lists the
ones it finds: with `COM2=PRINTER` alone, the BDA's first port is 2F8h
and DOS calls it `COM1`. `INT 14h`'s DX is an index into that list (AH=0
set the line, 1 send, 2 receive with a second's wait, 3 status).

The registers are an 8250's (no FIFO):

- **3F8h** a write transmits, a read takes the next received character;
  with DLAB set, the divisor latch (and 3F9h its high byte).
- **3F9h** interrupt enable: received data (bit 0) and transmitter empty
  (bit 1). Modem-status and line-status interrupts are not made.
- **3FAh** interrupt identification: 04h received data, 02h transmitter
  empty (reading it clears that one), 01h none.
- **3FBh** line control: 5 to 8 data bits, 1 or 2 stop bits, parity,
  break, DLAB.
- **3FCh** modem control: DTR (bit 0) is the port's handshake output;
  OUT2 (bit 3) must be set for the port to interrupt, as on a PC. RTS is
  kept as written and not put on a pin: the SCC's RTS enables the
  IIGS's line driver and stays on.
- **3FDh** line status: data ready, transmitter empty, and overrun (once)
  when a character was lost.
- **3FEh** modem status: CTS is the port's handshake input, DCD its
  general-purpose input, DSR always on; the delta bits are since the
  last read.
- **3FFh** scratch.

The baud rate is the divisor's: 115200 / divisor, from 300 to 57600. The
SCC's generator divides the same 115200 (the 3.6864 MHz crystal, x16) by
its time constant + 2, so every divisor from 2 up is exact; a divisor of
1 (115200) is run at 57600.

## How it works

**Receiving.** The SCC interrupts for every character, and `com_irq` puts
it in the port's ring of 256 (`COM_BUF`); the guest reads from the ring.
So nothing is lost while a service call runs (a file read, a screen
redraw: tens of milliseconds, and the SCC itself holds three characters),
as long as the guest takes characters at the line's rate on the whole. A
full ring, or an overrun in the SCC, counts in `COM_LOST` and shows once
as the line status's overrun bit.

**The interrupt.** The IIGS's firmware does not pass an SCC interrupt on
while its own serial firmware is idle: left to it, a received character
interrupts for ever. So while a port is open the firmware's interrupt
manager vector (`$E1/0010`) points at `com_irq`, which reads the SCC's RR3:
a character on one of our channels is taken and the interrupt returns to
what was interrupted (the firmware has pushed nothing by then); anything
else, another device's interrupt or the other channel's, goes on to the
firmware's manager untouched. It is not passed on after being served
because under ProDOS 8 the firmware hands an interrupt with no cause to
ProDOS, which stops the machine at the 255th.

**Transmitting.** A write to 3F8h waits for the SCC's transmit buffer and
writes the byte there. The transmitter-empty interrupt is the 8250's
rule, not the SCC's: it is waiting after each write and when it is
enabled.

**The PC's interrupt.** `PIC_IRQ4` (COM1) and `PIC_IRQ3` (COM2) are what
the core's slot looks at, beside the timer, keyboard and diskette: set
while OUT2 is on and an enabled cause is there, delivered at the 8259's
vector when the mask allows. A guest handler that takes one character
and returns is called again for the next one in the ring.

**Taking and giving back.** A channel is programmed at the guest's first
use of its port or of `INT 14h` for it (`com_open`; FreeDOS's kernel asks
`INT 14h` about its `AUX` as it starts, so under DOS that is at boot), following Apple's
Technical Note #18 and `../fgx`'s serial driver: no hardware reset, WR9
written 0Ah only, RR3 read on channel A, channel A keeping the crystal,
every two-step register access with interrupts off. `com_close` (from
`svc_sndclose`, when the guest ends) turns the channels' interrupts off
and puts the vector back.

## Its test

`make test-serial` (`tools/com_test.py`): MAME's modem and printer ports
are each looped back (`XTGS_MODEM=loopback`, `XTGS_PRINTER=loopback`,
which `tools/mame/mamerun.py` passes on), and `COMTEST1`/`COMTEST2`
(`tests/serial/comtest.asm`) run under FreeDOS, seven cases a port: the
BDA, `INT 14h` (with its timeout), the registers read back, 32 bytes one
at a time, 200 bytes sent before any is read, 64 bytes by the port's
interrupt, and the transmitter-empty interrupt. Then `COM2=PRINTER`
alone, and neither line. With a plug that joins a port's transmit data
to its receive data, `COMTEST` does the same on a IIGS.

## Not done

- A real IIGS, a real modem, another machine at the other end: run in
  MAME only. Besides the loopback (where a wrong baud rate or frame would
  not show: both directions are the same SCC) COM1 was once run against
  MAME's null modem and a socket, by hand: at 9600 8N1, 211 bytes sent to
  the PC in one burst all came back in order from a program that echoes
  each byte plus one. No other rate has been checked against anything
  but itself. The sense of CTS and DCD on the IIGS's connector is as the
  SCC reports them and has not been checked against a cable.
- AppleTalk: a port AppleTalk is using must not be given to the PC (the
  Technical Note's check is not made).
- No 16550 FIFO, no modem-status or line-status interrupts, no
  loopback bit (MCR bit 4), no RTS pin, 115200 baud.
- Transmit is not buffered: a write waits for the SCC, up to one
  character's time (33 ms at 300 baud).
- At stock speed the guest is the limit: a terminal program that does
  much work for each character will fall behind a fast line, and the
  ring then fills.
- Under the .COM runner (Mode A) the ports' registers are not there;
  `INT 14h` is.
