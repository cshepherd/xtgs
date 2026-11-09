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

Besides this INT 16h / BDA-buffer path, `kb_poll` also feeds a **hardware
keyboard**: it enqueues each key's make and break scancodes into a ring the
core serves at port 0x60 and delivers as IRQ1/INT 09h, for programs that read
the 8042 directly instead of calling INT 16h (see `docs/mode-b.md`). The INT
16h ring is still filled unchanged, so INT 16h programs are unaffected.
