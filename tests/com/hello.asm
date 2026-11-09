; hello.asm - the smallest convincing demonstration: a $-string and exit.
        org 100h
        mov dx, msg
        mov ah, 9
        int 21h
        mov ax, 4C00h
        int 21h
msg     db 'Hello from XT/GS!', 13, 10, '$'
