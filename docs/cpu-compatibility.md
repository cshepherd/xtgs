# CPU compatibility notes

What the SingleStepTests/8088 vectors taught the core, beyond the
documented 8086 instruction set. Each item was measured against the
suite (10,000 hardware-generated vectors an opcode) and is implemented in
`src/core/`. `tests/cpu/EXCLUDE.md` lists what the packer drops instead.

## FLAGS

- Bits 1 and 12-15 read as 1, bits 3 and 5 as 0, whatever was loaded
  (`POPF`, `IRET`, `SAHF`). `flags_get` assembles the value the guest sees;
  `rFL` stores the loaded word and `vOF` the overflow flag.

## Decimal adjust (`DAA`, `DAS`)

The textbook rule ("high adjust when old AL > 99h or CF") is wrong for one
input class. The hardware does:

- low adjust (±6, AF set) when the low nibble > 9 or AF was set;
- high adjust (±60h, CF set) when CF was set, or the high nibble > 9, or the
  high nibble is 9 **and** the low nibble > 9 **and AF was clear**.

With AF set and AL in 9Ah-9Fh the 8088 does *not* adjust the high nibble.
CF is set only by the high adjust; AF only by the low one; SF ZF PF from
the result.

## Division

- `DIV` traps when the dividend's high half is not below the divisor (the
  divisor 0 case included). The FLAGS word pushed by the trap is that of the
  compare *high half - divisor*: SF ZF AF PF CF OF all follow the 8086 SUB
  rules on those operands.
- `IDIV` works on magnitudes. It traps before dividing when
  |high half| ≥ |divisor| (flags of that compare), and after dividing when the
  quotient magnitude is ≥ 80h / 8000h: **a quotient of -128 or -32768 is a
  divide error on the 8088**. The pushed flags for that late trap are those
  of the division's final restoring-step compare with CF cleared: with the
  quotient's bit 0 set, (r + d) - d; clear, r - d (r = remainder magnitude,
  d = divisor magnitude, both masked to the operand width).
- `AAM imm`: AH = AL / imm, AL = AL mod imm; imm = 0 is a divide error whose
  pushed flags are those of comparing a zero high half with the zero
  divisor (ZF and PF set, the rest clear).
- **A `REP`/`REPNE` prefix on `IDIV` flips the quotient's sign** (the
  prefix's internal flag is shared with the sign logic); the remainder keeps
  the dividend's sign. Measured on every non-trapping prefixed vector.
  `DIV`, `MUL` and `IMUL` are unaffected.

## Shifts and rotates

- `D2`/`D3` take the full CL as the count (no masking to 5 bits).
- `RCL`/`RCR` rotate through the *incoming* CF; the count loop carries CF
  step to step. OF after a multi-step shift is whatever the last step gives,
  which is what the hardware does too.
- `/6` (undocumented SETMO): result all ones, flags as a logic op.

## Stack and far pointers

- `PUSH SP` (54h and FF /6 on SP) pushes the decremented SP.
- A word at offset FFFFh of a segment wraps to offset 0 of the same segment
  (operands and the stack: `SP = FFFFh`). Far pointers read their segment
  word at offset+2 wrapped the same way (`LDS`, `LES`, `CALL far m`,
  `JMP far m`).
- `POP CS` (0Fh) exists and loads CS. (The suite has no vectors for it.)

## Not modelled

- Instruction fetch across the 1 MiB boundary, and a data word straddling
  physical FFFFFh (see `tests/cpu/EXCLUDE.md`).
- The REP + segment-override interrupt-restart quirk; interrupts are not
  delivered during string instructions yet.
- Undefined forms the suite keeps in `v2_undefined` (`FE /2`-`/7`,
  `FF /2`-`/7` register forms, `8F` with reg != 0).
