; mem.asm - memory operands: 5 instructions an iteration, three of them
; with ModR/M memory operands (one read-modify-write).
        org 0x100
        mov dx, OUTER
        mov bx, 0x1000
        mov si, 0x1000
outer:  mov cx, 0
inner:  add [bx], ax
        mov ax, [si+2]
        mov [bx+4], ax
        dec cx
        jnz inner
        dec dx
        jnz outer
        hlt
