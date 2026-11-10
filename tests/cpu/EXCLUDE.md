# CPU test exclusions

Vectors from SingleStepTests/8088 v2 that `tools/vectors.py` drops, and why.

| Opcode | Why |
| --- | --- |
| `FE /7` | XT/GS reserves `FE 38 lo hi` as its hypercall (BOOTSTRAP.md 5.6). The 8086's own behaviour for `FE /2`-`/7` is undefined and these forms live in the suite's `v2_undefined` set anyway. |

| any | Instruction bytes that cross the 1 MiB wrap (`CS*16 + IP + length > 100000h`). Instruction fetch goes through the CS base pointer plus a 16-bit IP and does not wrap at the top of guest memory; real code never executes there, and a per-fetch wrap check would tax the hottest path. About 1.5% of a file's vectors. |
| any | A data word that straddles the 1 MiB wrap (RAM at both `FFFFFh` and `00000h`, e.g. a stack word with SS:SP at `FFFFFh`). The host pointer is computed once per word; the second byte is read linearly from the next host bank. Segment-offset wraps (`xxxx:FFFF`) are handled. |
| 0F, 9B, F4 | No vector files exist in the suite (POP CS, WAIT, HLT). |

Instruction fetch also does not wrap at the *segment* boundary (a byte of an
instruction at `xxxx:FFFF` followed by `xxxx:0000`); the suite does not
exercise that and real code does not do it.

## Known deviations

- `IN` from a port the core serves itself reads the PC's device in every
  mode, where the suite's machine had nothing there and read `FFh`: the
  keyboard's 60h and 64h, the 8253's 40h and 42h, port B at 61h and the
  CGA's status at 3DAh (`port_in8`, `src/core/ops_misc.s`). In a 300-vector
  sample of `E4` that is 2 failures (`E4 60`, `E4 61`). Every other port
  reads `FFh` under the vectors.
