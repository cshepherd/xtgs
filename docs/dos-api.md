# BIOS and DOS services (Mode A)

What a `.COM` program gets from XT/GS's stub BIOS and DOS, as of M2. Every
interrupt vector points at a five-byte stub in segment `F000h` (`FE 38 vec 00`,
the hypercall, then `IRET`), so programs that hook and chain vectors keep
working; the handlers live in `src/svc/bios.s` and `src/svc/dos.s` and read
and write the guest registers directly. Flags returned to the caller are set
in the FLAGS word the `IRET` restores.

Unlisted functions do nothing but are counted: the judge reports them
("unhandled calls", first one named), which is how M3's list is built.

## INT 10h (video)

| AH | Function | Notes |
| --- | --- | --- |
| 00 | set mode | text modes only; clears unless bit 7 of AL |
| 01 | cursor shape | stored |
| 02 / 03 | set / get cursor position | page ignored |
| 06 / 07 | scroll window up / down | AL lines (0 clears), BH attribute |
| 08 | read char/attr at cursor | |
| 09 / 0A | write char (+attr) CX times | cursor stays |
| 0E | teletype | BEL BS CR LF, wrap, scroll; attribute kept |
| 0F | get mode | AL mode, AH 80, BH 0 |
| 13 | write string | ES:BP, CX, DH/DL; AL bit 0 moves the cursor, bit 1 inline attributes |

Direct writes to `B800:0000` are stored (the buffer is real guest memory)
but not yet detected for rendering: M3.

## INT 16h (keyboard), 11h, 12h, 1Ah, 29h

| INT/AH | Function |
| --- | --- |
| 16h/00,10 | read key (waits; the screen keeps updating) |
| 16h/01,11 | key available? ZF |
| 16h/02,12 | shift flags |
| 16h/05 | push key |
| 11h | equipment word (`0021h`) |
| 12h | memory size (640) |
| 1Ah/00,01 | get/set tick count (18.2 Hz, from the VBL) |
| 1Ah/02,04 | RTC time/date: fixed 12:00:00, 1987-01-01 until M3 |
| 29h | fast console output |

## INT 20h / INT 21h (DOS)

| AH | Function | Notes |
| --- | --- | --- |
| INT 20h, 00, 4C | terminate | exit code to the loader |
| 01, 07, 08 | character input (echo / none) | |
| 02, 06, 09, 40 | character, direct, `$`-string, write handle 1/2 | TAB expands to 8 |
| 0A | buffered line input | Backspace, Enter echoes CR |
| 0B, 0C | input status, flush + input | |
| 3F | read handle 0 | a line, CR LF appended |
| 0D, 0E, 19 | disk reset, select (3 drives), current drive (C:) | |
| 1A, 2F | set / get DTA | default PSP:0080 |
| 25, 35 | set / get interrupt vector | real IVT |
| 2A, 2C | date, time | fixed until M3 |
| 30 | version | 3.30 |
| 33 | Ctrl-Break flag | off |
| 36 | disk free space | a fixed plausible disk |
| 44/00 | IOCTL device info | handles 0-2: console |
| 47 | current directory | root |
| 48, 49, 4A | allocate, free, resize memory | bump allocator above the program, up to A000h |
| 4D, 51, 62, 54 | return code, PSP (x2), verify flag | |
| 3C, 3D, 3E, 41, 42, 43, 4B, 56 | file and process functions | fail with CF (M3) |

## The PSP and environment

`PSP_SEG = 1000h`: `INT 20h` at 0, top of memory `A000h`, the CP/M call-5
entry, the three vector copies, a job file table with handles 0-2 open,
the environment at `0FF0h` (`PATH=C:\`, `COMSPEC=C:\COMMAND.COM`, then the
program path `C:\NAME.COM`), blank FCBs, and the command tail from
`XTGS.CMD` at 80h. Entry: CS=DS=ES=SS=PSP, IP=100h, SP=FFFEh with a zero
word pushed, IF set.
