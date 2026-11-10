# Minix 1.5: a system that drives the PC itself

Minix 1.5 boots from its 360K demonstration diskette to a root shell. It is
the first guest here that is not a DOS: once its kernel is up it never calls
the BIOS again. It programs the interrupt controller, reads the diskette
through the controller's own ports, writes the screen memory and moves the
6845's registers. What it needed is in this file; all of it is part of
Mode B and is there for any other guest that does the same.

Verified in MAME (`apple2gs`, ROM 3; `make test-minix`), under both front
ends and both layouts. **It has not been run on a real IIGS.**

The diskette image is in the tree, `third_party/minix/demo_dsk.ibm`, with
the BSD-style licence Minix has been under since April 2000 beside it.
`MINIX=path` names another.

## How to run

```
make run-minix                         # in Ample's MAME
make minix-image                       # only the volume, build/disk/disk.po
make test-minix [ZIP=1] [MINIX=path]   # headless, judged
```

`minix-image` is `make disk-image IMG=third_party/minix/demo_dsk.ibm`:
`disk-image` puts any PC diskette image on a ProDOS 8 volume as `DISK` with
the command `D` (docs/mode-b.md), and nothing in it is particular to Minix.
The volume is an ordinary 4 MB ProDOS one that boots to XT/GS.

At the boot menu press `=`. Minix loads its RAM disk from the diskette, asks
for the date (`MMDDYYhhmmss`, twelve digits and Return; it does not read the
PC's clock, so it does not get the IIGS's), and then for a login: `root`, no
password. The demonstration disk has `sh` and 25 commands in `/bin`: `cmp
comm cp date df echo head kill login lpr ls mined mkdir mkfs pwd rev rm
rmdir sleep sort sync tail tee time true`.

It is slow. Emulated seconds from power-on, in MAME:

| | boot menu | date prompt | `login:` | first `#` |
| --- | --- | --- | --- | --- |
| stock IIGS, 2.8 MHz | 18 | 182 | 244 | 264 |
| ZipGS, 16 MHz | 4 | 24 | 32 | 35 |

(The last two include the test's typing.) Loading the 192K RAM disk is most
of it, and on a stock machine about a third of all the time goes to Minix's
clock interrupt: it asks for 60 a second, each costs about 130 guest
instructions, and a stock IIGS runs 23,000 to 28,000 guest instructions a
second. (Before the interpreter's changes of 2026-11-10,
`docs/benchmarks.md`, the stock row read 18, 327, 452, 493, and after the
first four of them 18, 205, 279, 303; `ls -l` of the root directory took a
minute then, and that command has not been timed since.)

## What Minix asks of the PC

### The diskette's geometry, without a BPB

Minix's boot block has code where a DOS disk has its BIOS parameter block,
and finds out what disk it is on by trying: it reads sectors of rising
number and a cylinder past 40 through `INT 13h` and looks at which fail.
So the geometry comes from the image's size (`disk_geom`, `src/svc/disk.s`:
320K, 360K, 720K, 1.2M, 1.44M; any other size goes by the BPB as before),
and `INT 13h` refuses a sector or cylinder the disk has not.

The boot block then loads the kernel and the menu program with `INT 13h`
and the menu talks through `INT 10h`/`INT 16h`. That is the last of the BIOS.

### The 8259

Minix moves the hardware interrupts to vectors 28h-2Fh (`ICW2`), because
the 8088's own exceptions are at 8 and up, and its handler for a stray
vector 8 or 9 prints "Intel-reserved exception" and stops: with IRQ0 still
arriving at `INT 08h` the kernel died in a loop of those before it printed a
line. Every interrupt handler also masks its own line at port 21h while it
works and unmasks it after, reading the mask back each time.

`src/svc/ports.s` keeps the two things that matter in `PIC_BASE` and
`PIC_MASK` (`src/include/pc.s`), and the slot in `src/core/cpu.s` delivers
IRQ n at vector `PIC_BASE+n` when bit n of `PIC_MASK` is clear:

| Port | Write | Read |
| --- | --- | --- |
| 20h | bit 4 set: `ICW1` (starts the sequence, clears the mask); anything else (an EOI, `OCW3`) is accepted and means nothing | 0: nothing requested, nothing in service |
| 21h | after `ICW1`: `ICW2` (the vector of IRQ0, low three bits dropped), then `ICW3` unless `ICW1` said "single", then `ICW4` if it said one follows; otherwise the mask | the mask |

There is no in-service register and no priority: an interrupt is held back
by IF, by its mask bit, and by nothing else. A masked IRQ0 stays owed
(`vTICK`, up to 16: docs/sound.md), a masked key stays in the scancode
queue. `svc_bootinit` sets the base to 8 and the mask to 0, a PC after its
BIOS.

### The diskette controller

Minix reads and writes the diskette with its own driver: the 765's ports
for the commands and the 8237's channel 2 for where the data goes. Both are
in `ports.s`, on top of the image that `INT 13h` serves (`disk.s`); there is
one drive, and it holds that disk.

| Port | |
| --- | --- |
| 3F2h | the digital output register. Bit 2 going from 0 to 1 ends a reset: the controller interrupts, and SENSE INTERRUPT STATUS then answers `C0h`. Bit 3 lets its interrupts out. The motor bits are kept and ignored |
| 3F4h | main status: `80h` ready for a command, `90h` part of one taken, `D0h` a result byte waiting; `00h` while held in reset |
| 3F5h | command bytes in, result bytes out |
| 04h, 05h | the 8237's channel 2 address and count, low byte then high (0Ch resets which) |
| 81h | channel 2's page: bits 16-19 of the address |
| 08h | the 8237's status: bit 2 after a transfer, cleared by the read |

| Command | |
| --- | --- |
| SPECIFY (03h) | taken, no result |
| SENSE DRIVE STATUS (04h) | ST3: ready, two sides, track 0 when the head is there |
| RECALIBRATE (07h), SEEK (0Fh) | the head is there at once; interrupt; "seek end" for SENSE INTERRUPT STATUS |
| SENSE INTERRUPT STATUS (08h) | ST0 and the cylinder; `80h` alone when there is nothing to report |
| READ DATA (06h), WRITE DATA (05h) | the 8237's count + 1 bytes between the image and the guest address it holds, all at once; interrupt; seven result bytes with C/H/R moved past the last sector (to the other side with the multi-track bit, else to the next cylinder) |
| READ ID (0Ah), FORMAT TRACK (0Dh) | answered as done; a format changes nothing |
| anything else | ST0 = `80h` |

A transfer ends "abnormal, no data" (ST0 `40h`, ST1 `04h`) when the disk has
no such sector, when the head is not on the cylinder the command names, or
when the sector size is not 512; a drive other than 0 is "not ready". Those
are the answers a driver that tries one format after another needs, which
is how Minix's finds a 360K disk in what might be a 1.2M drive.

Nothing takes time: the command is done when its last byte is written, and
the interrupt (IRQ6, `PIC_IRQ6`) is taken at the next slot where IF and the
mask allow. Writes go to the image in memory and are lost at power-off, as
`INT 13h`'s are (`mkfs /dev/fd0 360` and `df /dev/fd0` after it work).

Without a disk image (command `S`) there is no controller: 3F4h reads `FFh`.

### Ports nobody answers

In Mode B a port the core does not serve itself goes to `svc_portout` and
`svc_portin` (`ports.s`), and what they do not know reads `FFh` and takes
writes without effect. Minix's probes for a hard disk, serial lines and a
printer all end there, as they would on a PC without the cards.

### The screen: the 6845's start address and cursor

Minix writes characters straight into `B800`, and scrolls the way a CGA can
without moving any: it adds 80 to the 6845's start address (R12/R13), so
the screen begins one row further into the 16K of display memory, and
writes the new last row there. The memory goes round at 16K, which is not a
whole number of rows (102.4), so after 78 scrolled rows the screen has the
end of the memory somewhere in it, and once per 512 rows in the middle of
a row. The cursor is wherever R14/R15 say, in cells from `B800:0000`.

`src/svc/video.s` follows both:

- `flush` reads R12/R13 each frame into `txt_org`. `render_row` takes the
  row's cells from `txt_org + row*160` on, round the end of the 16K, and
  `pages_to_rows` turns the core's dirty marks (all 64 pages of the 16K
  now) into rows from the same origin.
- A new origin marks every row. `txt_shadow` is kept by place on the
  screen, not in the buffer, so a row is compared with what is on the glass
  and only the cells that differ are drawn. A scroll therefore costs the
  compare (about 26 ms for 25 rows) plus the cells that changed, and several
  scrolls in one frame cost one. No pixels are moved.
- The core notes a write to R14 or R15 in `CRTC_CUR`. While it is set the
  cursor is drawn where the 6845 has it (`cur_where`: off the screen, or
  with R10's "no cursor" bits, it is not drawn); when the BIOS's cursor in
  the BDA next moves, the BIOS has the cursor again. A mode set through
  `INT 10h` puts the start address and the cursor back.

The BIOS's own text services still write from `B800:0000`: a program that
moved the start address and then called `INT 10h` gets what it would on a
PC, which is text somewhere else.

That is Minix on a CGA. It asks the BIOS once which card there is (`INT 10h
AH=12h`), and XT/GS now has an EGA to report (docs/ega.md), whose display
memory does not go round at 16K. There Minix moves the start address the
same way until the screen would run off the end of the 16K (the start at
cell 6160 and one more row to go) and then copies the 25 rows back to
`B800:0000` and starts again from 0. The same code draws it: a new origin
marks every row and the compare finds nothing changed. With `VIDEO=CGA` in
`XTGS.CMD` the PC has no EGA and Minix scrolls round the end as above.

### What was there already

The 8253's channel 0 at 60 Hz (the DOC timer takes any rate up to 583 Hz),
the keyboard's scancodes at port 60h with the strobe at 61h, and the 8088
itself: Minix asks which processor it has and gets the right answer.

## The test

`tools/minix_test.py` (`make test-minix`) builds the volume, and walks the
boot by waiting for the cursor at each prompt: the boot menu's (the BDA),
then the date's, the login's and the shell's (R14/R15), typing when it is
there. The shell gets one line, `ls -l; ls /bin /dev; ls /dev; echo round
the end; date`, which scrolls 84 rows. On the EGA that is one copy back to
the buffer's start and six rows more (the start address ends at cell 480);
with `--cga` (`make test-minix CGA=1`, which writes the `VIDEO=CGA` line)
it leaves the end of the 16K in the middle of row 18. Judged at the end:

- IRQ0 is at vector 28h (and the run got here: every prompt needed the
  clock, the keyboard and the diskette interrupts to arrive);
- the start address and the cursor are where 84 rows leave them;
- the last rows are the echo, a date and `#`, and the date is later than
  the one typed, by no more than the run took (Minix's clock is the 60 Hz
  interrupt);
- the SHR pixels are the text buffer's from the start address, all 2000
  cells (`tools/textshr.py`), and the cursor, when the dump caught it lit,
  is on the cell the 6845 names.

The date typed is this machine's, so the weekday Minix works out is checked
with it. `build/minix/minix.png` and `minix.txt` are the last screen.

## Limits

- MAME only so far.
- Speed, above. Minix's clock would cost a stock machine less if IRQ0 were
  held to a lower rate than the guest asks for; that would make Minix's time
  run slow, and is not done.
- The 8259 has no priorities and no in-service register, and only IRQ0,
  IRQ1 and IRQ6 exist. There is no second 8259 (Minix on an AT is another
  matter: this is the XT's).
- One diskette drive, no hard disk, serial line or printer. Diskette writes
  are not kept.
- The 765 never fails for a reason a real one has (no timing, no overrun,
  no door); a driver's error paths are not exercised.
- The date has to be typed.
