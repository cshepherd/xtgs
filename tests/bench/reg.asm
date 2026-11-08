; reg.asm - register-only loop: 4 instructions an iteration.
; OUTER x 65536 iterations, then HLT.
        org 0x100
        mov dx, OUTER
outer:  mov cx, 0
inner:  add ax, bx
        sub bx, 1
        dec cx
        jnz inner
        dec dx
        jnz outer
        hlt
