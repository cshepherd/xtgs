; strs.asm - the string instructions as a DOS kernel uses them (the counts
; of a FreeDOS boot, docs/benchmarks.md): short REP MOVSB and REP MOVSW
; runs, LODSB and STOSB one at a time, a REPNE SCASB, a REP STOSW. 20
; instructions an iteration, 9 of them string instructions on 115 bytes.
        org 0x100
        mov dx, OUTER
        cld
outer:  mov bp, 8192
inner:  mov si, 0x1000
        mov di, 0x2000
        mov cx, 7
        rep movsb
        lodsb
        stosb
        lodsb
        stosb
        mov cx, 16
        rep movsw
        mov di, 0x2000
        mov al, 0xFF
        mov cx, 8
        repne scasb
        mov di, 0x3000
        mov cx, 32
        xor ax, ax
        rep stosw
        dec bp
        jnz inner
        dec dx
        jnz outer
        hlt
