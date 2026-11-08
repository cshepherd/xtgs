; jmp.asm - compare-and-branch: 5 instructions an iteration, one
; conditional jump taken every other time.
        org 0x100
        mov dx, OUTER
outer:  mov cx, 0
inner:  test cx, 1
        jz skip
        inc ax
skip:   dec cx
        jnz inner
        dec dx
        jnz outer
        hlt
