# Opening a DOS program from the Finder

A file named `*.EXE`, `*.COM`, `*.BAT` or `*.BAS` is a document of the
GS/OS application `XTGS`. In the Finder it has the application's icon, and
opening it opens `XTGS`, which starts the PC as it always does and then
types, at the DOS prompt, the two commands that run the file:

```
C:\>CD \GAMES\KEEN1
C:\GAMES\KEEN1>KEEN1.EXE
```

A `.BAS` is run by GW-BASIC, which is left at its `Ok` when the program
ends:

```
C:\>CD \BASIC
C:\BASIC>\GWBASIC LANDER.BAS
```

The file has to be in the folder DOS has as its drive (docs/share.md: the
folder `SHARED` beside `XTGS`, or the one `XTGS.CMD` names). For any other
file `XTGS` says so and goes back to the Finder; no PC is started.

With `STATE=ON` and a boot state taken at the prompt (docs/state.md) the PC
is there in seconds and the keys follow at once. Without one it boots, and
the keys wait for the prompt.

This is the GS/OS application's only. `XTGS.SYSTEM`, the ProDOS 8 loader,
has no documents.

## The three parts

**The bundle** (`tools/gsos_rfork.py`, `--doc`). The application's
`rBundle` has, after the record for the application itself, one for each
of `*.EXE`, `*.COM`, `*.BAT` and `*.BAS`: a match on the filename alone (the
Finder's `*` is any run of characters; GS.ShrinkIt's `*.SIT` and `*.SHK`
are the same kind of record), the application's two icons, the bit that
says "open the application for it", and what kind of file it is ("MS-DOS
program", "MS-DOS batch file", "GW-BASIC program": the Finder's Kind). The layout was read
from the Desktop file of a System 6 volume, seventeen bundles of other
programs, and is written down in the tool. As with the icon, the Finder
knows a bundle once it is in the volume's `Icons/Desktop`: the volumes
built here have it (`gsos_rfork.py desktop`), and on any other disk the
application has to be opened once.

The match is by name on every volume, whatever the file's type: a file
called `LETTER.COM` anywhere gets the icon, and is refused when opened.

**The front end** (`src/gs/xtgs16.s`, `get_arg`). The Finder leaves the
file's pathname in the Message Center before it launches the application:
message 1, at `+6` a word that is 0 for "open", at `+8` the pathnames as
Pascal strings with a zero after the last. `XTGS` takes the first, with
`/` for `:`, into 256 bytes of its own, points `MB_ARG` at them, sets
`MB_ARGN` to 1 and deletes the message. If `XTGS.CMD`'s command is not `S`
or `D` there is no DOS to run anything, and it refuses the file itself.

**SVC** (`src/svc/ghost.s`). `gh_check`, from `svc_bootinit` once the
shared drive is set up, compares the pathname with the folder's
(`rd_root`), without regard to case, and turns what follows into DOS's
names: each folder and the file through `rd_unname`, which is how the
drive itself spells a ProDOS name for DOS (`MW.MAIN.EXE` is `MW_MAIN.EXE`,
`X..7UP` is `7UP`), each held to eight characters and three. The keys go
back into the front end's buffer, `MB_ARGN` becomes 2:

```
[E: Return]  CD \DIR\DIR Return  NAME.EXT Return
```

The drive's letter is typed only when DOS was not booted from the folder
(command `D` with a line `E=...`). Before the name of a `NAME.BAS` goes
the interpreter's (`gh_basic`): `\GWBASIC ` when there is a `GWBASIC.EXE`
in the drive's root, which is where the volumes built here have it and
where the folder just made the current one is not; `GWBASIC ` when there
is none, for DOS to find along its `PATH`, or to say it cannot. This happens before `bs_try` looks for
a boot state, and nothing of it is in the PC: the keys and how far they
have got (`MB_ARGI`) are in the front end's page, which no state holds.

`gh_poll`, called by `kb_poll` when the IIGS keyboard has no key of its
own, hands the keys over one at a time, and `kb_poll` treats each as it
treats a key that was pressed: into the BIOS's buffer, and its scancode
to port 60h with IRQ1.

## When the keys are typed

The first key waits for a prompt, which is taken to be this: the guest
has been asking for a key and finding none (`INT 16h`, `gh_ask` in
`bios.s`) for thirty frames in a row, the screen is in a text mode, and
the character before the cursor is `>`. FreeDOS polls the keyboard this
way at its prompt, and also while its kernel waits two seconds for F5 or
F8, while `PAUSE` waits, and while FreeCOM asks for the date when there is
no `AUTOEXEC.BAT`; none of those has a `>` before the cursor, and nothing
is typed into them. Each later key goes in when the guest is asking again,
the key before it has been taken from the buffer and its key is up.

So the keys wait as long as it takes: through a slow boot, through an
`AUTOEXEC.BAT` that asks something, through a program it starts. They are
typed at the first prompt after that. A prompt that does not end in `>`
(`PROMPT $P$_`) never gets them.

After a reboot from XTGS Control (docs/control.md) keys that were not yet
typed are typed from the first again; keys that were are not typed twice.

## What is refused

`MB_ARGN` is `$8000` plus the reason, the core returns without starting a
PC, and the front end shows the system's text alert (`TLTextMountVolume`),
"XT/GS will not run NAME", and quits when it is answered.

| | | |
| --- | --- | --- |
| 1 | It is outside the folder DOS uses. | the pathname does not begin with the shared folder's and a `/` |
| 2 | XTGS.CMD gives DOS no folder. | no shared folder (command `D` with no line for one, or the folder is not there), or a command that boots no DOS |
| 3 | DOS has no name for that file. | the name or one of its folders is not 8.3 as the drive spells it, or the path is longer than 63 |

## What can get in the way

- **Another program may take the file first.** Before the Finder opens an
  application for a file it asks its extensions, and a desk accessory that
  edits text can say yes to any file of type `TXT`. Hermes does: on a
  System with Hermes installed, opening a `.BAT` file of type `TXT` opens
  it in Hermes, and `XTGS` is never launched (seen in MAME; without Hermes
  on the same volume, `XTGS` gets it). A BASIC program saved as text
  (`SAVE "NAME",A`, and every `.BAS` of the volumes built here) is `TXT`
  as well. The shared drive makes the files
  DOS creates `TXT` (docs/share.md), programs among them, so the same
  goes for an `.EXE` that DOS itself wrote. The files of the release
  volume that are not text are `BIN`.
- **A boot state taken anywhere but at a prompt** starts a PC that is in
  the middle of something; the keys then wait for a prompt like any
  other, and are typed into whatever shows one.
- Only the first file of several opened together is run.

## Testing

`make test-open` (`tools/open_test.py`, work files in `build/open/`): the
application launched by `tests/gsos/start16.s`, which puts the pathname in
the volume's file `ARG` into the Message Center as the Finder does. Eight
steps, a boot or two each: a batch file in a folder with respelled names,
given in lower case; a `.COM` in the root after an `AUTOEXEC.BAT` that
waits for a key; files outside the folder; a folder DOS has no name for;
an `XTGS.CMD` that boots no DOS; a start from a boot state; DOS booted
from a diskette image with the folder as `E:`; and a BASIC program, with
GW-BASIC in the root and with GW-BASIC on the `PATH`. What was typed is
read from the BIOS teletype's capture, since a program may clear the
screen.

The Finder itself is not in that test. It was driven by hand in MAME on
the volume `make finder` builds (System 6.0.1): `COMMAND.COM` and
`XMSTEST.COM` in `SHARED` have the DOS icon; opening `XMSTEST.COM` launched
`XTGS`, which booted FreeDOS, typed nothing while FreeCOM asked for the
date and the time, and typed `CD \` and `XMSTEST.COM` at `C:\>`; a `.BAT`
in the volume's root, with Hermes taken off the volume, got the alert.
And with the volume `make games-test-image` builds (the games, `JIT=ON`,
`STATE=ON`) as a second disk beside a System 6 volume of another name:
`XMSTEST.COM` opened from the Finder booted, was typed and ran; a boot
state written then from XTGS Control was what the next opening started
from, the keys following within fifteen seconds of the double-click at 16
MHz; and `HELLO.BAS`, Hermes again off the boot volume, ran in GW-BASIC.
A state written after a boot from ProDOS 8 is not one the GS/OS
application starts from, nor the other way round (the layout is another:
docs/state.md); it boots then, and a state written from there replaces it.
Not run on a real IIGS.
