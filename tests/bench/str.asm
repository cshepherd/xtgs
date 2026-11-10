; str.asm - REP MOVSW of 16 KB, OUTER times: one MVN (src/core/ops_str.s).
; Counted as one "instruction" per word. strs.asm is the short runs.
        org 0x100
        mov dx, OUTER
        cld
outer:  mov si, 0x1000
        mov di, 0x6000
        mov cx, 0x2000
        rep movsw
        dec dx
        jnz outer
        hlt
