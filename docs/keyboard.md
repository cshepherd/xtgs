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
| Return | `$0D` | Enter | `1C:0D` |
| Esc | `$1B` | Esc | `01:1B` |
| Tab | `$09` | Tab | `0F:09` |
| Option + 1..9, 0 | digits | F1..F9, F10 | `3B..44:00` |
| Ctrl + letter | `$01`-`$1A` | Ctrl + letter | letter's scan code, control byte |
| everything else | ASCII | its US-layout key | `scan_tab` (gen/tables.s), the ASCII |

Consequences: Backspace is the IIGS Delete key, since `$08` is taken by the
left arrow; Ctrl-H therefore also reads as Left. Shift, Ctrl, Caps Lock and
Option set the BDA shift flags (left shift, ctrl, caps, alt).

Not yet: Home/End/PgUp/PgDn/Insert (no IIGS keys spare without a chord),
Alt+key codes beyond the function keys, the keypad as a keypad.
