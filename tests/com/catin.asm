; catin.asm - copy stdin (handle 0) to stdout (handle 1); tests "< FILE".
        org 100h
.loop:  mov ah, 3Fh
        xor bx, bx
        mov cx, 128
        mov dx, buf
        int 21h
        jc .done
        test ax, ax
        jz .done
        mov cx, ax
        mov bx, 1
        mov dx, buf
        mov ah, 40h
        int 21h
        jmp .loop
.done:  mov ax, 4C00h
        int 21h
buf     times 128 db 0
