; typefile.asm - isolate handle-based file I/O (3Dh/3Fh/40h/3Eh) from FCBs:
; open HELLO.TXT, copy it to stdout in 64-byte reads, close, exit.
        org 100h
        mov dx, name
        mov ax, 3D00h
        int 21h
        jc .err
        mov [h], ax
.loop:  mov bx, [h]
        mov cx, 64
        mov dx, buf
        mov ah, 3Fh
        int 21h
        jc .err
        test ax, ax
        jz .done
        mov cx, ax
        mov bx, 1
        mov dx, buf
        mov ah, 40h
        int 21h
        jmp .loop
.done:  mov bx, [h]
        mov ah, 3Eh
        int 21h
        mov ax, 4C00h
        int 21h
.err:   mov dx, emsg
        mov ah, 9
        int 21h
        mov ax, 4C01h
        int 21h
name    db 'HELLO.TXT', 0
emsg    db 'open/read error', 13, 10, '$'
h       dw 0
buf     times 64 db 0
