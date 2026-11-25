# XTGS Control: the desk accessory

While a PC runs (commands `D` and `S`), **Control-Apple-Esc** brings up the
IIGS's desk accessories as it does anywhere, and **XTGS Control** is among
them:

```
XTGS Control

  1  Soft reboot (as Ctrl-Alt-Del)
  2  Hard reboot (memory cleared)
  3  Save state
  4  Restore state
  5  Quit to ProDOS            (or: Quit to GS/OS)
  6  Save to start from

  Esc  Back
```

A choice is confirmed with any key (Esc: not after all) and takes effect
when the desk accessories' menu is left (its `Quit`).

- **Soft reboot**: the PC starts again as it did when XT/GS was launched:
  its BIOS, its devices and DOS from the disk image or the folder. What is
  in its memory is not cleared, as after Ctrl-Alt-Del. A diskette image
  (`D`) keeps what the PC wrote to it.
- **Hard reboot**: the same with the PC's megabyte cleared first, as after
  the power switch. With `STATE=ON` this is the reboot that boots FreeDOS
  for real: a soft reboot starts from the boot state when there is one
  (docs/state.md).
- **Save state**: the PC as it is at that moment, kept in the IIGS's
  memory: its megabyte, its CPU and devices, the screen, the XMS memory
  in use. One state; a new save takes the place of the last. It lasts
  until XT/GS quits or the PC is restarted (either reboot): it is not on
  any disk.
- **Restore state**: the PC is again as it was saved, and goes on from
  there. The line says `(none saved)` while there is nothing to restore.
- **Quit**: XT/GS leaves, to ProDOS or to GS/OS, whichever started it,
  without the key it otherwise waits for.
- **Save to start from**: the same state as choice 3, written to the file
  `XTGS.STATE` beside `CORE` and then let go of in memory. With the line
  `STATE=ON` in `XTGS.CMD`, later starts (and reboots) put the PC back
  from that file in place of booting FreeDOS (docs/state.md). Only for a
  PC booted from the folder (command `S`), and not while it has a file or
  a serial port open: the line under the menu says which it was: written,
  a file or a port open, no memory, the disk, not a PC from a folder, or
  a PC that has changed the files it was booted from (reboot it first).
  The file is written when the desk accessories are left (the PC stands
  still for as long as that takes: some twenty seconds under GS/OS at 16
  MHz in MAME, three from ProDOS 8). Until then the menu says "Start
  state: written as you leave."; a reason it cannot be written at all is
  said as the choice is made; and Quit or a reboot chosen before leaving
  is done after the state is written, not in its place.

Files the PC had open on the shared drive are closed before a reboot, so
what DOS had not finished writing is not finished: a reboot is a reboot.

What a restored state cannot bring back is outside the PC:

- **The disk.** What the PC wrote to the shared folder after the save
  stays written. A file it had open when saved and still has open is the
  same file, at the place DOS knows; one it has closed since is closed
  (its handle fails from then on), and one it has opened since is closed
  for it.
- **The time.** The tick count is set to the time of day, as at a boot:
  the PC's clock does not go back.
- **The serial ports** keep whatever speed and format the SCC has now.

```
make test-control      soft, hard, a state saved and restored, quit: a boot each
```

Tested in MAME only (ROM 3).

## How it works

- **The accessory** is `src/svc/control.s` (`svc_cda`, SVC's entry 14). It
  runs inside whatever Control-Apple-Esc interrupted, the core in the
  middle of an instruction as likely as not, so it does nothing to the PC:
  it draws on the 40-column text screen the Desk Manager has put up
  (straight into the page at `$E0/0400`), reads the keyboard at `$C000`,
  and leaves a request in `CTL_REQ`. It uses no direct page and no
  firmware, and gives back the mode it was entered in.
- **The front end installs it** just before it runs the core and removes
  it as soon as the core returns (`cda_on`, `cda_off` in `src/sys/xtgs.s`
  and `src/gs/xtgs16.s`): a block from the Memory Manager holding the
  Desk Manager's header (the name, the start and shutdown routines) and
  those two routines themselves, a `JML` to SVC's entry and an `RTL`.
  `RemoveCDA` is not in every Desk Manager (ROM 01 booted without a
  system disk's tools has none); when it fails the block is left, its
  `JML` made an `RTL`, and the menu's line does nothing from then on.
- **The request** is found by `svc_vbl` at the next frame (`ctl_poll`),
  which returns to the core with the carry set and the exit code
  `CTL_EXIT` + the request; the core stops as it does when a program
  ends (`HALTVEC`), which closes the sound, the serial ports and the
  mouse as any exit does.
- **The front end starts the PC again** (`boot_pc`): the prefix as it was
  at the launch (the shared drive had made its folder the prefix), `CORE`
  and `SVC` loaded from the disk again and relocated, so that every
  variable of theirs is as assembled, and the core entered. A hard reboot
  clears the guest's sixteen banks first (`zero_guest`). The data file is
  not loaded again: a disk image stays as the PC left it.
- `CTL_LIVE` says a PC is running that can be started again
  (`svc_bootinit` sets it, `svc_sndclose` clears it); without it the
  accessory says "No PC is running." and a request is dropped.
- **Quit** is the same road as a reboot with another exit code: the front
  end goes through its ordinary shutdown and skips the key.

## The saved state

Save and restore do not stop the core: `ctl_poll` does them there and
then (`st_save`, `st_restore`), at the slot, where the core is between
two instructions, and the core goes on.

- **What is kept** (`st_rg`, seven regions): the direct page, the results
  bank, the SHR screen with its line controls and palettes, the guest's
  sixteen banks (the EGA's planes and the Tandy's pages are in them), the
  XMS region as far as its last block reaches, and CORE's and SVC's own
  banks, because their variables live among their code.
- **How**: a 256-byte page at a time. A page that is one byte 256 times
  is a word in the map (`$01vv`); any other is a word of 0 there and its
  bytes in the data. That is the run-length scheme: a PC's memory is
  largely pages of one value, and a page of anything else is not worth
  looking into. Two blocks from the Memory Manager (`st_new`: the map,
  two bytes a page; the data, as many pages as the first pass counted),
  so a save that finds no room says so (`CTL_STAT` 2, and the menu's
  line) and changes nothing.
- **The walk** (`st_walk`) is one routine for the counting pass, the copy
  out and the copy back, and has to stay one. On the way back it runs in
  SVC while SVC's pages are put back, and keeps its pointers in the
  direct page while that is put back. What arrives is what was there when
  the copy out passed the same place, so nothing changes under it, but
  only because both copies hold the same things in the same variables at
  every step. The one thing that differs, which pass it is, is on the
  stack, which is not saved: save and restore are both reached from
  `svc_vbl` at the slot, so the stack has the same shape both times.
- **After the copy back** the hardware is brought into line: each DOC
  oscillator's registers written again from `DOC_REG`, its control last;
  the tick count set (`clk_init`); `EGA_SYNC` raised; and the files
  reconciled against the handle table as it was a moment before
  (`ST_OLD`, in the transfer buffer, which is not the PC's): a handle is
  the same file when its ProDOS reference and its pathname are
  (`st_same`).
- `st_drop`, from `svc_sndclose`, gives the blocks back at every exit: a
  reboot loads SVC again, and SVC is where the handles are.


## The test

`tools/control_test.py soft|hard|state|quit`: FreeDOS from a folder whose
`AUTOEXEC.BAT` runs `MARK.COM` (`tests/demo/mark.asm`), which prints the
word at `F800:0000`, memory nothing in this PC uses, and makes it `BEEF`
(or one more, if it was not 0).
The harness holds Control-Apple-Esc, goes down the menu to the accessory,
picks the reboot, confirms and quits. The front end's exit code must be
the request's, a PC must be running at the end, and `MARK` must have
printed `BEEF` after the soft reboot and `0000` after the hard one. The
menu is in the order of the names, and a GS/OS system disk has accessories
of its own in it: `CONTROL_DOWNS` and `CONTROL_QUIT` are the presses of
the down arrow to the accessory and from it to `Quit` (5 and 2 on the
tests' System 6 volume). `state` saves at the prompt, runs `MARK` twice,
restores and runs it once more: the screen must be the saved one with
`MARK=BEEF` under it, and the SHR must show that text. `quit` wants the
front end's exit code and no key (from GS/OS, where the front page goes
as the program quits and the tests' launcher starts it again: a second
boot). Run it under `XTGS_LAYOUT=alt` and `XTGS_FRONT=s16` by hand.
