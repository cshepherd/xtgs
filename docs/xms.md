# XMS: extended memory for the guest

XT/GS's PC has **1472 KB of XMS memory** when FreeDOS boots from the shared
folder (command `S`). The driver is built in: nothing is loaded, no
`HIMEM.SYS`. What it is for first of all is FreeDOS's own `COMMAND.COM`,
which without XMS stays in conventional memory whole, about 94 KB of it,
while a program runs, and with it moves into a block and leaves 2 KB:

| At the `C:\>` prompt's programs | Largest free block |
| --- | --- |
| without XMS (`XMS=OFF`) | 474 KB |
| with it | 566 KB |

That is the difference for a game that wants most of 640 KB (Commander
Keen stops with "Out of memory" without it).

```
make test-xms        XMSTEST under FreeDOS, and XMS=OFF
```

Tested in MAME only.

## What a guest sees

- `INT 2Fh AX=4300h` returns `AL=80h` and `AX=4310h` the driver's entry in
  `ES:BX` (`F000:05C0`), to be called far with the function in `AH`, as the
  XMS specification has it. The version is 2.00.

  | Function | |
  | --- | --- |
  | `00h` | version 2.00, driver 1.00, `DX=0`: no high memory area |
  | `08h` | the largest free block and all that is free, in KB |
  | `09h`, `0Ah` | a block of `DX` KB allocated (32 handles), freed |
  | `0Bh` | bytes moved: between blocks, and between a block and real memory (`handle 0`, a segment and an offset) |
  | `0Ch`, `0Dh` | a block locked (an address above the megabyte is returned, where a PC with the memory would have it; nothing can be reached there), unlocked |
  | `0Eh` | a block's size and lock count, the handles free |
  | `0Fh` | a block made smaller, or larger where it is if the room after it is free |
  | `01h`-`06h` | fail: there is no high memory area (`90h`) and no A20 line (`82h`): an 8088's addresses wrap at 1 MiB |
  | `07h` | A20 is off |
  | `10h`, `11h` | no upper memory blocks (`B1h`, `B2h`) |

- A move's length must be even (`A7h`), must fit its blocks (`A4h`, `A6h`)
  and, for real memory, must end within the megabyte.
- So a program gets at the memory by function `0Bh` only. That is what
  FreeCOM does, and what a program written for XMS on any PC must be able
  to do; one that wants the HMA, or to run code above the megabyte, has no
  such machine here.

## `XMS=OFF`, and when there is none

A line `XMS=OFF` in `XTGS.CMD` takes the driver away. There is none under
`D` either (the memory is the disk image's), nor when the Memory Manager
could not give the front end the 23 banks (under GS/OS on a full machine:
FreeDOS boots all the same, with the shell resident).

## How it works (`src/svc/xms.s`)

- **The memory** is the region the disk image has under `D` (`DISK_BASE`,
  `DISK_BANKS` banks: 23, the size of a 1.44 MB diskette). Under `S` both
  front ends now ask for it too, last and without making a failure of it
  (`claim_xms` in `src/sys/xtgs.s`, the same lines in `src/gs/xtgs16.s`),
  and `MB_LAYOUT`'s word for the region says whether they got it
  (`xms_setup`).
- **INT 2Fh** is the shared drive's hook (`rd_stub`'s `hook2F`, in before
  the shell starts), which now makes its hypercall for every function and
  lets `rd_int2f` look at `AH`: `11h` the drive's, `43h` `xms_int2f`, any
  other down the chain.
- **The entry** is a stub at `F000:XMS_OFF`: the five bytes a driver begins
  with (a short jump and three NOPs), hypercall 261 (`xms_call`) and a far
  return.
- **Blocks** are a start and a length in KB a handle; a new one goes in
  the first gap that holds it (`xm_find`: the region's start and each
  block's end are the candidates, `xm_gap` the room from one).
- **A move** (`xm_move`) is `MVN` in runs that end where either pointer's
  bank does. A handle's pointer is the region's bank plus its KB and
  offset; real memory's is the guest's, the same way every service forms
  one.

## Tests

`make test-xms` (`tools/xms_test.py`): FreeDOS boots from a copy of the
folder whose `AUTOEXEC.BAT` runs `XMSTEST.COM` (`tests/demo/xmstest.asm`):
twelve steps, each a failure by its number: the version, two blocks, what
is free, 4096 bytes out to a block at three places and back, block to
block, the refused moves (past the end, an odd length, no such handle), a
block's size and a larger one, lock and unlock, free and free again, the
HMA, A20 and UMB answers. The harness then wants most of the 1472 KB free
(FreeCOM is in a block as the program runs). A second boot with `XMS=OFF`
must find no driver. Run it under `XTGS_LAYOUT=alt` and `XTGS_FRONT=s16`
by hand, like `test-share`.
