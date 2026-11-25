# The boot state (M7)

`XTGS-M7-Instant-Boot.md` is the proposal. This is what stands of it:
M7.0 (the audit and the baseline), M7.1 (the PC written to a file and
started from it), M7.3 (the state held to the files the PC was started
from) and M7.4 (DOS's date and time after it). A checkpoint taken without
the operator (M7.2's second half) is not built, and the feature is off
unless `XTGS.CMD` asks for it.

## What it does

With the line `STATE=ON` in `XTGS.CMD` and FreeDOS booted from the shared
folder (command `S`):

- the desk accessory XTGS Control (Control-Apple-Esc) has a sixth choice,
  **6 Save to start from**: the PC as it is at that moment is written to
  the file `XTGS.STATE` beside `CORE`;
- every start after that looks for the file, and when it is this build's,
  this layout's and this configuration's, is sound, is of today or of one
  of the 250 days before, and the files the PC was started from are what
  they were, the PC is put back from it in place of the boot. Anything
  else and FreeDOS boots as ever.

Without the line nothing is looked for, and the sixth choice still writes
the file. `BS_BOOT` (`src/include/pc.s`) says how the PC was started and
`BS_STAT` how the last save went; `BS_WHERE` is how far the look at the
file got.

The first PC of a run boots in memory that has been cleared, from
0060:0000 to the end of the BIOS's segment (`mem_clear`, `PC_BEGUN`): what
the machine had there before (another program's, the PC's of the launch
before) is not the PC's, and it was in every state taken after a boot. A
megabyte a game had been in made a state of 691 KB of what is 404 KB on
memory that was empty, and one of every page of it would be 1.3 MB. A soft
reboot keeps the PC's memory as it always did, a hard one has it cleared
by the front end, and a start from a state fills every page.

When there is a file and the PC boots all the same, the sign-on says why,
on a line of its own before the drive's (`bs_said`):

| | `BS_BOOT` | |
| --- | --- | --- |
| Boot state not used: XTGS.CMD has changed | 3 | a line added, taken away or changed since the PC that was saved was started; the file is as that PC read it |
| Boot state not used: XT/GS is elsewhere in memory | 3 | another layout: saved after a start from ProDOS 8 and now opened from GS/OS, or the other way, or GS/OS gave other banks or pages |
| Boot state not used: another build of XT/GS | 3 | `CORE` and `SVC` are not the ones that wrote it |
| Boot state not used: the file is damaged | 4, 7 | |
| Boot state not used: no memory | 5 | |
| Boot state not used: a file DOS boots from has changed | 8 | |
| Boot state not used: its date | 9 | |

(The first that applies, in that order.) A state written from that PC, at
its prompt, takes the old one's place. With no file there is no line, and
none after the desk accessory's hard reboot, which asks for the boot.

| `BS_BOOT` | |
| --- | --- |
| 0 | a boot: the state was not asked for |
| 1 | from the boot state |
| 2 | a boot: no file (or not command `S`) |
| 3 | a boot: the file is another build's, layout's or configuration's |
| 4 | a boot: the file is damaged (header, map, sums or length) |
| 5 | a boot: no memory for the map |
| 6 | the data was found damaged as it was loaded: the PC is to be begun again |
| 7 | a boot, after 6 |
| 8 | a boot: a file the PC was started from is not what it was |
| 9 | a boot: the state is of a later day than the clock's, or more than 250 days old |
| 10 | a boot: asked for (the desk accessory's hard reboot) |

`BS_STAT`, the last save: 1 written, 2 not now (the PC has a file or a
serial port open), 3 no memory, 4 the disk would not take it, 5 not a PC
from the folder, 6 the PC has changed a file it was started from, 7 it has
opened more files than are kept track of. The desk accessory shows it as a
line under its menu. The state is written when the desk accessories are
left, where the PC is between two instructions, so 1, 3 and 4 are there to
be read the next time the accessory is opened; 2, 5, 6 and 7 are known
before anything is written, and the accessory says them as the choice is
made (`bs_can`) and takes no request. Once the choice is confirmed the
accessory stays on its menu with the line "Start state: written as you
leave.", and a restart, the Quit or a save chosen then does not take the
state's place: `CTL_REQ` holds one request, so the later one goes there
with bit 7 set, and `ctl_poll` writes the state before it does it. (It
used to take its place, without a word: "6" and then "5 Quit" left no
file.) A game is where 2 is met: one that
keeps a file of its own open while it runs (Arkanoid does) cannot be
written, and the state to start from is one taken at the prompt.

The desk accessory's soft reboot starts from the state too when there is
one. Its hard reboot boots FreeDOS, whatever state there is (`BS_SKIP`):
that is the way to a boot with a good state on the disk, and after it the
sixth choice writes the state anew. The state is never written but by that
choice.

## Who owns what (M7.0)

XT/GS is not a model of an XT's chips with a state structure for each. What
a PC is at an instruction boundary lies in seven places, and the desk
accessory's saved state (`control.s`, `st_rg`) already named them:

| Region | Pages | What is there |
| --- | --- | --- |
| the direct page | 1 | the 8088's registers, the lazy flags, the bases, the slot's count, `vTICK`, the services' scratch |
| the results bank | 256 | the devices as `src/include/pc.s` lists them: the 6845, the 8259's base, mask and pending lines, the EGA's and the Tandy's registers, the DOC's registers as written, the redirector's and the clock's accounts, the dirty flags |
| the SHR | 128 | the picture, its line control bytes and palettes |
| the guest's megabyte | 4096 | conventional memory, the vectors, the BIOS's data, B800, the EGA's planes and the Tandy's page slots (guest banks A, C, D, E), the BIOS's stubs |
| the XMS memory in use | varies | FreeCOM swapped out, as a rule (372 pages at a prompt) |
| CORE's bank | 256 | the interpreter, and its variables among its code (`optab` as the mode has it, the hooks) |
| SVC's bank | 256 | the services, and their variables among their code: the keyboard's, the redirector's, the handles, the mouse driver's, the XMS driver's tables, the text shadow |

The last two are the finding that shapes everything else: CORE and SVC keep
their mutable state among their code, some hundreds of variables in thirty
source files, so the PC cannot be told from the program that runs it
without naming every one. The state therefore holds the two banks whole,
and is good for the build that wrote it and for the same layout (the
banks' bytes are in the code and in the pointers), and for nothing else.
That is the proposal's "state ABI" at its narrowest. It is not the
explicit, field by field serializer the proposal asks for: see "What is
not as the proposal has it".

What is not the PC's but the host's, and must be this start's:

| | |
| --- | --- |
| the 65816's stack | not kept: the state is taken in the slot's frame work (`svc_vbl`), and the PC goes on from the slot's end (`run_resume`, `slot_x`) |
| the sound's saved page 1, vector, P and volume (`snd_*`), the mouse's interrupt (`ms_irq`) | kept across the load (`bs_keep`) |
| the paths (`rd_root`, `bs_home`), `XTGS.CMD` as read, this file's handles | kept across the load |
| the DOC's registers, its RAM, its timer | the sound is opened as for any PC, then the registers are written again from `DOC_REG` (`st_docs`) |
| the tick count at `0040:006C` | the time it is now (`clk_init`); `vTICK` cleared, so no burst of ticks; the days gone by added to the midnight count at `0040:0070` |
| the translator's cache and map | not in the file: emptied (`jit_start`), as after the accessory's restore |
| ProDOS's open files | none: a state is refused while the PC has a file open |
| the serial hook | none: refused while a port is open |
| the Memory Manager's blocks, the desk accessory's own saved state | not kept (`CTL_STAT` 0) |
| the front end, the mailbox, the layout | this start's; the layout must be the file's |

A PC booted from a disk image (command `D`) has written to a copy of the
image in memory that no file holds, so the state is for command `S` only.

SVC had 131 bytes left of its bank when M7.1 was done. The text screen's
shadow, 4000 bytes of cells, went to the results bank (`TXT_SHADOW`, where
the capture buffer gave up its last 4K), and M7.3 and M7.4 took 1.5 KB of
what that freed. SVC has 2.6 KB left of its bank (`state.s` is 3.6 KB of
it).

## The file

```
+0    "XTGSboot"
+8    version 2, +10 the header's length (256)
+12   the build: a CRC-32 of CORE's, SVC's and the 8087's sources (tools/gen_buildid.py)
+16   MB_LAYOUT and MB_LAYALT: where every region and area is
+42   XTGS.CMD as this start read it (the first 124 bytes, then how much
      was read and the sum of all of it)
+170  the seven regions: bank, offset, pages
+212  the map's bytes, +214 the data's pages, +216 the bytes of the
      pieces' sums, +218 the sum of the words of all that lies between the
      header and the data, +222 the bytes of the files' records,
+224  the day it was written (days from the first of January 1900)
+254  the sum of the header's words
+256  the files' records: a name (Pascal, to an even length) and what
      the file was: 1 not there / 2 a file / 3 a directory; its date; its
      time; its length (four bytes); the sum of its bytes
      the map: a word a page ($01vv: the page is the byte vv 256 times;
      0: its 256 bytes are in the data)
      the sum of each piece of the data (32 pages a piece, 32 bits)
      the data
```

Everything is little-endian words; the sums are of 16-bit words into 32
bits. They find a file that is damaged; they prove nothing about who wrote
it.

The save writes `XTGS.STATE.NEW`, closes it, and only then destroys the
old file and gives the new one its name (ProDOS 8 has no replace: between
the two calls there is no state, and the next start boots).

The start checks the header, the regions against its own, the day, the
lengths, the file's end, and the records, the map and the sums against
their sum, and then the folder against the records, before a byte of
memory is changed. Then the data is read once, a piece of 8K at a time
into the transfer buffer, added up and held to its sum, and only then
copied to its places: nothing that failed a sum is ever put in memory, so
the code doing the load stays its own even as it puts SVC's bank over
itself (the same bytes, the build being the same). A piece that fails, or
is not read, leaves the PC half another's: the core stops with the hard
reboot's code, the front end loads CORE and SVC again and clears the
guest's memory, and that start boots (`BS_BOOT` 6, then 7).

## The boot's files (M7.3)

A PC booted from the folder has no disk of its own. Drive C: is the
network redirector, DOS keeps no sectors of it, and every directory and
file is read from ProDOS as it is asked for: the stale cache the proposal
fears is not there to be stale. What a state can be wrong about is the
boot itself: the files that made the PC what it is.

So while such a PC runs, SVC keeps the name of every file it opens for it,
or looks for and does not find (`mf_do`, from `p_open` and `p_getinfo` in
`files.s`; the table `MF_TAB` in the results bank, and so in the state).
For the test's volume that is `KERNEL.SYS`, `FDCONFIG.SYS`, `SETVER.SYS`,
`COMMAND.COM`, `AUTOEXEC.BAT` and `MARK.COM`: found by what was opened,
not by a list. The table knows three kinds: looked for and not there,
opened, and the PC's own making (a file it made before it ever read it).

- **At the save** each entry of the first two kinds is written with what
  the file is then (`mf_ident`): there or not; its modification date and
  time; its length; and, when it is no longer than the transfer buffer
  (8K), the sum of its bytes. A directory is only "there".
- **At the start** the same is asked of the folder again, and any
  difference is a boot (`BS_BOOT` 8).
- **The PC's own changes.** A PC that writes a file it was started from,
  makes it anew, destroys it or renames it (`mf_wr`, `p_create`,
  `p_destroy`, `p_rename`) is no longer what a boot would make of the
  folder: the entry is marked, and the save is refused (`BS_STAT` 6) until
  the PC has been booted again. Files of its own making are its own
  affair: it may write and delete them, and the state is held to none of
  them. The table is 506 bytes, some forty names: a PC that has opened
  more is not saved either (`BS_STAT` 7).

What this does not see: a file longer than 8K changed to the same length
within the minute of its date (ProDOS's dates are to the minute; reading
`KERNEL.SYS` and `COMMAND.COM` to add them up would cost 5 s of a 17 s
start at stock speed, 1 s at 16 MHz); and a file that was not there for
the boot and that a boot would now find by a search of a directory and not
by its name (a new `MARK.BAT` that FreeCOM would have run instead: FreeCOM
finds programs by reading the directory, and a directory is held to
nothing, or every file written in the folder would undo the state).

## The date (M7.4)

The time of day is the tick count at `0040:006C`, which every start sets
from the IIGS clock (`clk_init`), the state's start like any other. The
date is FreeDOS's own: its clock driver read the BIOS's clock once, as it
began, and since then counts the midnights that `INT 1Ah` function 00h
hands over in AL, adding that count to its day. XT/GS's BIOS already kept
that byte (`0040:0070`) as a count.

So the state has the day it was written (`clk_days`), and the start adds
the days gone by since to the byte, on top of a midnight DOS had not yet
been told of. The first time DOS asks the time, its date is today's.
The day is taken from the same reading of the clock as the tick count, so
a start across midnight counts the midnight once. A state of a later day
than the clock's, or more than 250 days old (the byte is a byte), is not
used (`BS_BOOT` 9). A date the operator had set by hand in DOS before the
save stays as far from the clock's as it was; a time set by hand does
not, as after any start.

Files' dates on the shared drive are ProDOS's, from the IIGS clock, and
have nothing to do with any of this.

This leans on FreeDOS adding AL and not 1 (its `rdpcclk.asm`), which the
test holds it to with the kernel in the tree; only FreeDOS boots from a
folder at all.

## Measurements (M7.0 and M7.1)

MAME, the 4 MB test volume on the SCSI card, FreeDOS from the folder, an
`AUTOEXEC.BAT` of one program; times are from power on, in emulated
seconds (`make test-state ONLY=time`).

| | Stock (2.8 MHz) | 16 MHz ZipGS |
| --- | --- | --- |
| ProDOS, the loader, CORE and SVC: the PC is begun | 6.9 s | 2.0 s |
| cold: `AUTOEXEC.BAT` has run its program | 76.9 s | 15.7 s |
| from the state: the PC is in its places | 24.5 s | 5.2 s |
| the boot alone / the load alone | 70.0 s / 17.6 s | 13.6 s / 3.2 s |
| | 4.0 times | 4.3 times |

A cold boot reads about 133 KB (`KERNEL.SYS` 46 KB, `COMMAND.COM` 85 KB,
the two small files) and is the interpreter's time. The state is 458,328
bytes and its load is the disk's time: 26 KB a second at stock speed. Looking
at the six files the PC was started from made the start 0.4 s longer at
stock speed (24.1 s before, 24.5 s with it).

| Region | Pages | In the data | One byte each |
| --- | --- | --- | --- |
| the direct page | 1 | 1 | 0 |
| the results bank | 256 | 26 | 230 |
| the SHR | 128 | 62 | 66 |
| the guest's megabyte | 4096 | 839 | 3257 |
| XMS | 372 | 356 | 16 |
| CORE | 256 | 223 | 33 |
| SVC | 256 | 239 | 17 |
| | 5365 (1.37 MB) | 1746 (447 KB) | 3619 |

Memory: the start takes one block of 12 KB (the files' records, the map,
the sums, a page, the host's fields) for the length of the load. The save
takes the desk accessory's two blocks, the map and all of the data (447 KB
here), until the file is written.

Where the file's bytes could go, none of it done: about 450 of CORE's and
SVC's pages are the same as the files CORE and SVC (but a page is only
safely left out if the start has not changed it either, which a compare
with the file at the save does not show); 500 of the guest's pages are
what the boot left behind in memory DOS has since freed (the kernel's
load address, the top of the 640K); the rest would take a real packer. A state taken in mode 0Dh (the test's)
is 492,672 bytes: the planes are 32 KB more.

## The test

`make test-state` (`tools/state_test.py`; work files in `build/state/`;
`ONLY=make,load,...`; under `XTGS_LAYOUT=alt`, `XTGS_FRONT=s16` and
`XTGS_JIT=1` by hand; all four pass):

- **make**: a cold boot, the save from the desk accessory, the file read
  by the tool's own decoder (written apart from `state.s`);
- **load**: started from the file and stopped before an instruction (the
  harness sets `BS_CFG` to 2): every region is compared with the file,
  byte for byte. The direct page, the results bank, the SHR, the guest's
  megabyte and the XMS memory must be the file's but for the fields named
  in the tool's `EXPECTED` (the tick count and its midnight flag, `vTICK`,
  the clock's accounts, the DOC's registers and log, the request and
  state flags); CORE's and SVC's differences are counted, not judged (the
  host's fields above);
- **go**, **cold**, **same**: the same keys (MARK, a file written and
  typed, MARK, DIR) after the state and after a cold boot of the same
  volume: the two text screens must be the same line for line, the file
  must be on the ProDOS volume, the SHR must show the text, the tick must
  be counting;
- **again**, **hard**: from the state, the accessory's soft reboot (the
  state again) and its Quit; its hard reboot (FreeDOS boots);
- **files** (M7.3): `AUTOEXEC.BAT` replaced by a longer one; changed in
  place in the image, its length and its date kept; `KERNEL.SYS` the same
  bytes with another date; `MARK.COM` gone: a boot each time (`BS_BOOT`
  8). A new file the boot has nothing to do with, and the half-written
  file of a save that was cut off: the state, and `TYPE` shows the new
  file. A PC that has added a line to `AUTOEXEC.BAT` is not saved; one
  that has made, read and deleted a file of its own is, and its state is
  held to none of that;
- **day** (M7.4): the state's day is the host's; `DATE` and `TIME` after
  it are the host's; a state made 40 and 250 days old in its header gives
  DOS that many days on (into the next year); one 251 days old, or of
  tomorrow, is a boot. (MAME's clock cannot be set, so the days gone by
  are made by the header and the date DOS shows is that much ahead of the
  host's.);
- **ega**: not a prompt: a state taken inside `EGADEMO`, mode 0Dh. Started
  from it the SHR must be the four planes' picture, the palette must go
  on turning by the clock, a key must end the program at the prompt;
- **disk**: a PC booted from a diskette image: no state is looked for,
  and the sixth choice writes none;
- **bad**: the file cut short, a byte longer, a byte of its data changed
  (in the middle, and in SVC's bank), of its map, of its files' records,
  of its sums, of its header, another build's, `XTGS.CMD` changed, no
  file: a cold boot each time, and `BS_BOOT` says why;
- **time**: the table above.

## What is not safe yet

- **The boot's files**, as far as the two cases at the end of "The boot's
  files" go: a large file changed to the same length in the same minute,
  and a new file that a directory search would now find first.
- **The moment.** The operator picks it. A state taken inside a program is
  that program again at every start, which is a save state by another
  name; open files, open serial ports and a PC that has changed its own
  boot files are refused, and no more. A key held or queued at the save
  would be in it (at a prompt the buffer is empty).
- **The host's fields are a list** (`bs_keep`). A new variable in SVC or
  CORE that is the host's and is not on it comes back as the file had it.
- **The machine.** The state is for the machine that wrote it: what SVC
  found out about the hardware at its start is in its bank. The layout's
  check catches other memory; nothing catches another ROM or card. Under
  GS/OS the Memory Manager chooses the banks, and a state from another
  arrangement is refused (a boot, and no more than that).
- **The written file is not read back** before the old one is destroyed.
- **Real hardware**: MAME only.

## What is not as the proposal has it

- No checkpoint without the operator (M7.2's `XTGREADY`, a prompt found
  by itself), and no command that deletes the state: the hard reboot goes
  round it and the sixth choice writes it anew.
- The files' identity is their dates and lengths, with their bytes added
  up only for the small ones, not a hash of everything the boot read.
- No section for each device with explicit fields: the regions are raw
  memory, CORE's and SVC's banks among them, for the reason above. The
  build's identity stands in for a state ABI, so a state never outlives
  the build that wrote it. A serializer by field would want CORE's and
  SVC's variables gathered out of the code first.
- The comparison with an uninterrupted run is of the screen and the
  volume after the same keys, not of the CPU's state instruction by
  instruction: the two runs do not see the same clock.
- Nothing is compressed beyond a page of one byte, which the desk
  accessory's state already had.
