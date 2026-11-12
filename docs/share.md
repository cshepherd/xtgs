# The shared drive: a ProDOS folder as a DOS drive

In Mode B a folder of a ProDOS (or GS/OS) volume can be a drive of DOS.
DOS reads, writes, creates, renames and deletes the folder's files where
they are; nothing is copied into a disk image and nothing is lost when the
run ends, unlike writes to a floppy image's `A:` (`docs/mode-b.md`). It is
the way to get files into and out of the PC.

The folder can also be the drive FreeDOS boots from, with no disk image at
all: [Booting from the folder](#booting-from-the-folder). That is what
`make dos-image` and `make finder` build.

## Setting it up

`XTGS.CMD`'s first line is the command. A line after it of the form
`letter=pathname` names the folder and the drive (another kind of line,
`VIDEO=CGA`, is docs/ega.md's; the two may come in either order):

```
D
C=/HARD1/DOSFILES
```

- The letter is the drive, `C` to `Z`. FreeDOS's `LASTDRIVE` must reach it
  (the floppy `make boot-dos` builds says `LASTDRIVE=Z`).
- A pathname that starts with `/` is a full one. Any other is below the
  folder XT/GS was started from: `C=SHARE` is the folder `SHARE` beside
  `XTGS.SYSTEM`. `C=/HARD1` is a whole volume.
- The folder has to exist. Case does not matter; blanks and a `/` at the end
  are dropped; the full pathname is at most 63 characters.
- One drive. The first such line counts, and only commands `D` and `S`
  read it.

By hand, for a volume that boots a floppy image (`tools/make_image.sh` adds
the files, and a folder given to it goes on the volume with what it holds;
`cadius` adds to it afterwards):

```
mkdir -p build/my/SHARE
printf 'D\rC=SHARE\r' > 'build/my/XTGS.CMD#040000'
cp third_party/freedos/fd/freedos.img 'build/my/DISK#060000'
tools/make_image.sh build/my/my.po 'build/stage/XTGS.SYSTEM#FF2000' \
    'build/stage/CORE#060000' 'build/stage/SVC#060000' \
    'build/my/DISK#060000' 'build/my/XTGS.CMD#040000' build/my/SHARE
tools/cadius_strict.sh ADDFILE build/my/my.po /XTGS/SHARE/ 'README.TXT#040000'
```

The sign-on screen says what was found, before DOS starts:

```
XT/GS 65816 Native BIOS Active
640 KB RAM OK
Drive C: is /XTGS/SHARE
```

`(not found)` after the pathname means there is no such folder; DOS then has
no drive `C:`.

## Booting from the folder

Command `S` in place of `D` boots FreeDOS from the shared folder. There is
no `DISK` file: the kernel, the shell and everything else are ProDOS files
in the folder, which is drive `C:`, the boot drive.

```
S
C=SHARED
```

The folder must hold FreeDOS's `KERNEL.SYS` (the 8086 kernel, `KERNL86.SYS`
under that name) and `COMMAND.COM`, and may hold `FDCONFIG.SYS` or
`CONFIG.SYS`, `AUTOEXEC.BAT` and whatever they name, on `C:`
(`SHELL=C:\COMMAND.COM /P`, `DEVICE=C:\SETVER.SYS`).
`tools/build_freedos.py` makes such a folder, `third_party/freedos/fd/SHARED`,
with the files' ProDOS types in their names as `cadius` wants them;
`make dos-image` puts it on a ProDOS 8 volume, `make finder` beside the
GS/OS application, and `make boot-shared` boots it headless.

- The setting line may be left out: the folder is then `SHARED` beside
  XT/GS. Its letter is not used: FreeDOS boots from `C:`.
- Nothing is loaded at startup but `KERNEL.SYS` (46 KB), where command `D`
  reads the whole disk image into memory first, and the 23 banks (1.44 MB)
  that image occupies are not claimed: XT/GS then needs the PC's sixteen
  banks and three of its own. In MAME at stock speed, from ProDOS 8,
  FreeCOM's date prompt is up 73 seconds after XT/GS starts, against 114
  from the floppy image with the same files.
- The PC has no disk drives. `INT 13h` reports none, the equipment word has
  no floppy, and FreeDOS's `A:` and `B:` answer "drive not ready" (`DIR A:`
  gets its Abort, Ignore, Retry, Fail). Everything DOS writes is a ProDOS
  file and stays.
- Without `KERNEL.SYS` in the folder (or without the folder) the sign-on
  screen says `No KERNEL.SYS there to boot.` and XT/GS ends.

How: `svc_bootinit` reads `KERNEL.SYS` to `0060:0000` and the core enters
it there with `BL` = 80h, as FreeDOS's boot sector does for a kernel it read
from the first hard disk; the kernel takes that for boot drive `C:`. The
kernel reads `FDCONFIG.SYS` long before it loads the shell, so the
redirector cannot wait for the first `EXEC` as it does after a floppy boot.
Instead (`rd_early`):

1. The `INT 21h` stub goes in front of DOS at the first BIOS call after the
   kernel has set the vector (`svc_hypercall` runs `rd_poll` then, without
   waiting for the next frame), and is put back whenever the kernel sets
   the vector again.
2. The install stub runs at the kernel's first `INT 21h` call of its own
   that is not one of the few answered before its data is ready
   (`AH`=33h, 50h, 51h, 62h, 64h), and again at the next if DOS has no
   version to report yet. `INT 2Fh` is taken at once.
3. The kernel builds its drive table, wipes it and builds it again while it
   reads `CONFIG.SYS`. So until the shell's `EXEC` every `INT 21h` call first
   makes sure `C:`'s entry is the network drive (`rd_mark`): the kernel's
   `open("fdconfig.sys")`, its `DEVICE=` loads and the `EXEC` itself all find
   `C:` there. At that `EXEC` the stub comes out of `INT 21h` for good, as
   after a floppy boot.

This leans on how FreeDOS's kernel starts (`init_kernel` in its `main.c`):
that it calls its own `INT 21h` for its files, and that a drive marked as a
network drive is one it leaves to the redirector even then. Another DOS's
kernel would need its own way in; only FreeDOS 2043 boots like this.

## What DOS sees

| DOS | ProDOS |
| --- | --- |
| a file | a file with one fork, of any type, whose name reads as a DOS name (below): at most 8 characters, and at most 3 after one dot. Others are not listed and cannot be opened (`XTGS.SYSTEM`, `LONG.NAME.FILE`, a file with a resource fork) |
| a directory | a folder (the same rule for its name) |
| a new file | type `TXT`, auxiliary type 0. A name with a character other than letters, digits, `_` and the dot fails with "access denied", and one that starts with `_` or has one in its extension with "path not found" |
| size, date and time | the file's end of file and its modification date. DOS cannot set them: a copied file gets the time it was copied |
| read-only attribute | the file is locked (ProDOS's access byte has no write, rename or destroy). `ATTRIB +R` locks, `-R` unlocks. Hidden, system and archive are not kept |
| volume label | none |
| free space | the volume's free blocks, as 512-byte clusters |

### Names ProDOS cannot hold

A ProDOS name is a letter, then letters, digits and dots, 15 at most. DOS
programs also name files `6X6.FNT` and `MW_MAIN.EXE`, so the drive spells two
kinds of name differently on the volume (`dp_prefix`, `dp_under`, `dp_close`
in `files.s`; `rd_unname` in `redir.s` reads them back for a directory search
and for the name DOS keeps of an open file):

| DOS | ProDOS | |
| --- | --- | --- |
| `MW_MAIN.EXE` | `MW.MAIN.EXE` | a `_` in the name's first part is a dot: every dot but the last is an underscore |
| `A_B` | `A.B.` | with no extension, the name ends in the dot that is the last |
| `6X6.FNT` | `X..6X6.FNT` | `X..` before a name that starts with a digit |
| `1_2.TXT` | `X..1.2.TXT` | both |

So a ProDOS file `A.B.TXT` is DOS's `A_B.TXT` (it was not listed before), and
the longest DOS name still fits in 15 characters. Two things follow that are
not put right: DOS's `X__6.TXT` is stored as `X..6.TXT` and then listed as
`6.TXT`, and a name with a `_` first or in the extension cannot be made.
`tools/release_image.py` stores a folder's files the same way
(`prodos_name`), and `make test-share` has a case of each.

Up to 8 files of the drive can be open at once (the files `A:` has open do
not count), and a directory search needs one of the 8 for the moment it
reads. `REN` renames within a directory; it does not move a file to another.
A path below the drive's root is at most 63 characters.

## How it works

DOS has an interface for drives it does not own: the network redirector. A
drive whose entry in the current directory structure (CDS) is marked as a
network drive is never looked at by the kernel's FAT code; every file call
for it is handed to `INT 2Fh` with `AH=11h` and a function number in `AL`,
its arguments in the kernel's swappable data area (SDA) and system file
table entries. `src/svc/redir.s` answers those calls from ProDOS, through
the handle table and MLI lists Mode A's DOS already had (`src/svc/files.s`).
Nothing is loaded into the guest: no driver in `CONFIG.SYS`, no TSR, no
memory taken from the 640 KB.

The folder becomes the ProDOS prefix (`SET_PREFIX`), so the path DOS gives,
`C:\SUB\FILE.TXT`, is the partial pathname `SUB/FILE.TXT`.

Three pieces of 8086 code, 76 bytes in all, sit in the BIOS segment at
`F000:0540` (`rd_stub`):

1. `rd_poll` runs once a frame. When DOS's kernel has pointed `INT 21h`
   away from the BIOS and the vector has stood still for a frame, it puts
   the first stub in front: hypercall 256, then a far jump to DOS.
2. That hypercall (`rd_int21`) waits for the kernel's first `EXEC`
   (`AX=4B00h`: the shell being loaded). By then DOS is whole: its drive
   table is built and `CONFIG.SYS` has been read. It points the guest at the
   second stub in place of the far jump.
3. The second stub asks DOS for its version (`AH=30h`), its list of lists
   (`AH=52h`) and its SDA (`AX=5D06h`) with ordinary `INT 21h` calls, then
   hypercall 258 (`rd_install`). That checks the version and that the drive
   is below `LASTDRIVE` and not in use, writes the CDS entry (`C:\`, flags
   `C000h`), points `INT 2Fh` at the third stub, gives `INT 21h` back, and
   the `EXEC` goes on to DOS as if nothing had happened. (Under command `S`
   steps 1 to 3 happen earlier and more than once: above.)
4. The third stub is the `INT 2Fh` handler: `AH=11h` is hypercall 257
   (`rd_int2f`); a call that is not answered goes down the chain.

| `AL` | Function | Handler |
| --- | --- | --- |
| `01h`, `03h`, `05h` | remove, make, change directory | `rd_rmdir`, `rd_mkdir`, `rd_chdir` |
| `06h`, `07h` | close, commit | `rd_close`, `rd_commit` |
| `08h`, `09h` | read, write (a write of 0 bytes truncates) | `rd_read`, `rd_write` |
| `0Ah`, `0Bh` | lock, unlock a region | `rd_lock` (always succeeds) |
| `0Ch` | disk space | `rd_space` |
| `0Eh`, `0Fh` | set, get attributes | `rd_setattr`, `rd_getattr` |
| `11h`, `13h` | rename, delete | `rd_rename`, `rd_delete` |
| `16h`, `17h`, `2Eh` | open, create, extended open | `rd_open`, `rd_create`, `rd_extopen` |
| `1Bh`, `1Ch` | find first, find next | `rd_ffirst`, `rd_fnext` |
| `21h` | seek from the end | `rd_seek` |

Anything else (`23h` qualify a name, `1Dh`/`22h` at a program's end, the
printer calls) is left to DOS's own answer.

A search reads the ProDOS directory file itself, a 512-byte block a call,
and keeps its place (entry, block, and which directory) in the 21-byte
search block DOS holds for the caller, so any number of searches can be
under way; the pathnames of the last 8 directories searched are kept on the
host side. Under GS/OS with a file system that has no directory blocks to
read, the front end builds them (`docs/relocation.md`).

The kernel structures are DOS 4's and later: the SDA (the first filename at
`+9Eh`, the second at `+11Eh`, the search attribute at `+24Dh`, the
extended open's words at `+2DDh`), the 58h-byte CDS and the SFT. FreeDOS
(kernel 2043) is the DOS it was written against and tested with.

### What a front end has to answer

Two more MLI calls than before reach `MB_FILECALL`: `SET_PREFIX` (`$C6`)
and `FLUSH` (`$CD`). `XTGS.SYSTEM` passes them to the MLI like any other;
the GS/OS application sets prefix 1, resolves partial pathnames against it,
and answers `FLUSH` with success without doing anything (GS/OS writes a
file out when it is closed). The prefix stays changed until XT/GS quits.

## Diagnostics

In the results bank (`src/include/pc.s`):

| Field | |
| --- | --- |
| `RD_STATE` | 0 no share, 1 waiting for DOS's `INT 21h`, 2 for its `EXEC`, 3 installing, 4 the drive is there, 5 it could not be installed |
| `RD_DIAG` | why not: 1 a DOS before 4.0, 2 the letter is past `LASTDRIVE` (or there is no drive table), 3 the drive is already in use (a hard disk partition, say) |
| `RD_CALLS` | redirector calls seen |
| `RD_LAST` | the last one: function, and the DOS error in the high byte (`FFh`: left to DOS) |
| `RD_LOG` | the last 32, the same way |

## Testing

```
make test-share                      # ProDOS 8
XTGS_LAYOUT=alt make test-share      # every region and page moved
XTGS_FRONT=s16 make test-share       # the GS/OS application
make test-share LETTER=E FULL=1      # another letter, a full pathname
make test-share BOOT=1               # FreeDOS booted from the folder (command S)
make test-share BOOT=1 FULL=1        # the same with the folder named in XTGS.CMD
```

`tools/share_test.py` builds a FreeDOS floppy whose `AUTOEXEC.BAT` works on
the drive: `DIR`, `TYPE`, `COPY` in both directions (an 85 KB file among
them), `MD`, `CD`, `REN`, `DEL`, `RD`, `IF EXIST`, `>` and `>>`, a batch
file on the drive, `tests/com/fileops.asm` run from the drive with the drive
current, and, when GW-BASIC is there, GW-BASIC copied to the drive, loaded
from it and run on a program that writes, appends, renames and deletes files
there. It compares what DOS printed with what is expected, then reads the
volume with `cadius` and compares the files DOS wrote byte for byte.

With `BOOT=1` there is no floppy: the kernel, the shell, `FDCONFIG.SYS` and
that batch file (as `C:\AUTOEXEC.BAT`, its copies from `A:` made from `C:`
instead) are in the folder `SHARED`, and `XTGS.CMD` is `S` alone, or with
`FULL=1` `S` and `C=/XTGS/SHARED`. The same checks follow, and that `DIR C:`
lists `KERNEL.SYS`.

## Limits

- Mode B only, one drive, and a DOS with the DOS 4+ structures. Only
  FreeDOS has been tried. MS-DOS 3.x has a different SDA and is refused
  (`RD_DIAG` 1); MS-DOS 4 to 6 should have the layout this uses but have
  not been run.
- Booting from the folder is FreeDOS's kernel only, the boot drive is
  always `C:`, and there is no floppy drive then: a program that wants a
  disk in `A:` needs command `D` and an image.
- Tested in MAME (ProDOS 8, GS/OS on a ProDOS volume, both layouts), not
  yet on a real IIGS.
- ProDOS's names, as in the table above: files DOS cannot name are
  invisible, and DOS cannot create a name ProDOS refuses.
- Dates and times cannot be set, attributes other than read-only are not
  kept, and there is no volume label.
- A file is not shared between two opens with any checking: sharing modes
  and region locks are accepted and ignored.
- A disk error or a full volume is a failed call with a DOS error code
  (27h for a full volume), not a critical-error prompt.
- The emulated PC stops while ProDOS reads or writes, as it does for `A:`.
- This GW-BASIC does not take a directory in a file name on any drive (it
  counts the backslash as a letter of the name, on a PC as well):
  `OPEN "C:DATA.TXT"` works, `OPEN "C:\SUB\DATA.TXT"` is "Bad file name".
  `CD` to the directory in DOS first.
