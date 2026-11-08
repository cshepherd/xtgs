; str.asm - REP MOVSW of 16 KB, OUTER times (the generic per-element path
; until the MVN fast path exists). Counted as one "instruction" per word.
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
