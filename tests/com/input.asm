; input.asm - buffered keyboard input (INT 21h/0Ah) echoed back uppercased.
        org 100h
start:  mov dx, prompt
        mov ah, 9
        int 21h
        mov dx, buf
        mov ah, 0Ah
        int 21h
        call newline
        mov dx, hello
        mov ah, 9
        int 21h
        mov cl, [buf+1]
        xor ch, ch
        jcxz .skip
        mov si, buf+2
.u:     lodsb
        cmp al, 'a'
        jb .o
        cmp al, 'z'
        ja .o
        sub al, 32
.o:     mov dl, al
        mov ah, 2
        int 21h
        loop .u
.skip:  mov dx, bang
        mov ah, 9
        int 21h
        mov ax, 4C00h
        int 21h
newline:
        mov dl, 13
        mov ah, 2
        int 21h
        mov dl, 10
        mov ah, 2
        int 21h
        ret
buf     db 20, 0
        times 21 db 0
prompt  db 'Name? $'
hello   db 'Hello, $'
bang    db '!', 13, 10, '$'
