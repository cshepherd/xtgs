# Keyboard

The IIGS keyboard (`$C000`/`$C010`, modifiers at `$C025`) becomes a PC
keyboard in `src/svc/keyboard.s`. Keys are polled once a frame (and while a
service waits for input) and pushed into the BIOS data area's ring buffer
at `0040:001E` as scan-code/ASCII words, so `INT 16h`, `INT 21h` input and
programs that read the BDA directly all see the same thing.

| IIGS key | byte | PC key | AH:AL |
| --- | --- | --- | --- |
| Left arrow | `$08` | Left | `4B:00` |
| Right arrow | `$15` | Right | `4D:00` |
| Up arrow | `$0B` | Up | `48:00` |
| Down arrow | `$0A` | Down | `50:00` |
| Delete | `$7F` | Backspace | `0E:08` |
| Option + ←/→/↑/↓ | arrows | Home/End/PgUp/PgDn | `47/4F/49/51:00` |
| Option + Delete | `$7F` | Del (forward) | `53:00` |
| Ctrl + Delete | `$7F` | Insert | `52:00` |
| Return | `$0D` | Enter | `1C:0D` |
| Esc | `$1B` | Esc | `01:1B` |
| Tab | `$09` | Tab | `0F:09` |
| Option + 1..9, 0 | digits | F1..F9, F10 | `3B..44:00` |
| Ctrl + letter | `$01`-`$1A` | Ctrl + letter | letter's scan code, control byte |
| everything else | ASCII | its US-layout key | `scan_tab` (gen/tables.s), the ASCII |

Consequences: Backspace is the IIGS Delete key, since `$08` is taken by the
left arrow; Ctrl-H therefore also reads as Left. Shift, Ctrl, Caps Lock and
Option set the BDA shift flags (left shift, ctrl, caps, alt).

Home/End/PgUp/PgDn/Del/Insert have no spare IIGS key, so they are Option
(and Control) chords with the arrow and Delete keys, as above — enough to drive
a spreadsheet like Lotus 1-2-3. Not yet: Alt+key codes beyond the function
keys, Shift/Ctrl/Alt + function-key chords (WordPerfect's command set), and the
keypad as a keypad.

## The hardware keyboard: port 60h, held keys

Besides this INT 16h / BDA-buffer path, in Mode B `kb_poll` also feeds a
**hardware keyboard**: scancodes go into a ring the core serves at port 0x60
and delivers as IRQ1/INT 09h, for programs that read the 8042 directly
instead of calling INT 16h (see `docs/mode-b.md`). The INT 16h ring is still
filled unchanged, so INT 16h programs are unaffected.

A key is down for the guest for as long as it is down on the IIGS, so a game
that keeps its own table of pressed keys (Tunneler does, from its INT 09h
handler) sees a key held:

- A key's **make** code is queued when its strobe arrives (`kb_scpush`), and
  the key is remembered in `kb_held`.
- Its **break** code is queued when the IIGS reports that no key is down:
  bit 7 of `$C010`, looked at once a frame while a key is held, and not
  before the key has been down for `KB_MINHOLD` (3) frames, so a tap is long
  enough to be seen.
- The IIGS auto-repeat's strobes are sent as make codes again, which is what
  a PC keyboard's typematic repeat does.
- **Shift and Control are keys of their own** (`kb_modpoll`): `$C025` shows
  them live, with or without another key, and a change queues the make or
  break code of left Shift (`2Ah`) or Ctrl (`1Dh`). Tunneler's fire button is
  Ctrl.

Limits, all from what `$C000`/`$C010` can say:

- **One ordinary key at a time.** The IIGS reports the latest key only, so a
  second key releases the first for the guest; Shift and Control are
  independent of it and of each other. Two direction keys for a diagonal, or
  two players on the letter keys and the arrows at once, do not work. Doing
  better means reading key-up and key-down events from the ADB
  microcontroller, which is not done.
- When two keys are down and one is released, MAME's any-key-down bit goes
  off, and the guest sees the held key released. What real hardware does
  there has not been checked.
- Reading `$C010` also clears the strobe, so a key that arrives in the few
  cycles between the `$C000` read and that one is lost.
- Option and Command are not sent as Alt make/break codes (Option is the
  function-key layer), and Caps Lock sends none. Extended keys are sent
  without the `E0h` prefix.
- The break of a key released while a BIOS service is waiting for input in a
  hypercall is queued then, but delivered only when the guest runs again.

Verified in MAME with Tunneler (`D`, `X`, the right arrow and Control held
through the harness's `press` input: the tanks move and fire) and with typing
at the FreeDOS prompt. Not yet tried on a real IIGS.
