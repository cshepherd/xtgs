; joytest.asm - JOYTEST.COM: the joystick as a PC program sees it on XT/GS
; (docs/joystick.md): the game port at 201h read the way games do, a write
; and then a count of reads until each axis's bit falls, the buttons in
; bits 4 and 5; and the BIOS's INT 15h AH=84h beside it. One line, written
; over and over; a key ends it. JOYTEST L starts a new line whenever what
; it reads changes (tools/joy_test.py reads those). tools/build_freedos.py assembles it onto
; the FreeDOS folder and floppy.
;       nasm -f bin -o JOYTEST.COM joytest.asm
        cpu 8086
        org 100h
LIMIT   equ 2000                ; reads before an axis is given up

start:  mov dx, title
        mov ah, 09h
        int 21h
.again: mov bl, 1               ; X: bit 0
        call axis
        mov [px], ax
        mov bl, 2               ; Y: bit 1
        call axis
        mov [py], ax
        mov dx, 201h
        in al, dx
        mov [pb], al
        mov ah, 84h             ; the BIOS: positions
        mov dx, 1
        int 15h
        mov [bx_], ax
        mov [by_], bx
        mov ah, 84h             ; and buttons
        xor dx, dx
        int 15h
        mov [bb], al

        mov dx, s_port
        call puts
        mov ax, [px]
        call num
        mov dx, s_y
        call puts
        mov ax, [py]
        call num
        mov dx, s_btn
        call puts
        mov al, [pb]
        call btns
        mov dx, s_bios
        call puts
        mov ax, [bx_]
        call num
        mov dx, s_y
        call puts
        mov ax, [by_]
        call num
        mov dx, s_btn
        call puts
        mov al, [bb]
        call btns
        mov dl, 13
        mov ah, 02h
        int 21h
        mov al, [80h]           ; L on the command line: a line for each change
        test al, al
        jz .key
        mov al, [82h]
        and al, 0DFh
        cmp al, 'L'
        jne .key
        mov si, px
        mov di, was
        mov cx, 10
        push ds
        pop es
        cld
        repe cmpsb
        je .key
        mov si, px
        mov di, was
        mov cx, 10
        rep movsb
        mov dl, 10
        mov ah, 02h
        int 21h
.key:   mov ah, 1
        int 16h
        jz .again
        xor ah, ah
        int 16h
        mov dx, crlf
        call puts
        mov ax, 4C00h
        int 21h

; BL = the axis's bit -> AX = reads of 201h until it fell, FFFFh if it never did
axis:   mov dx, 201h
        out dx, al
        xor cx, cx
.l:     in al, dx
        test al, bl
        jz .done
        inc cx
        cmp cx, LIMIT
        jb .l
        mov cx, 0FFFFh
.done:  mov ax, cx
        ret

puts:   mov ah, 09h
        int 21h
        ret

; AX in decimal, four places; FFFFh as "none"
num:    cmp ax, 0FFFFh
        jne .n
        mov dx, s_none
        jmp puts
.n:     mov bx, 10
        mov di, buf+4
.d:     xor dx, dx
        div bx
        add dl, '0'
        dec di
        mov [di], dl
        test ax, ax
        jnz .d
.p:     cmp di, buf
        je .o
        dec di
        mov byte [di], ' '
        jmp .p
.o:     mov dx, buf
        jmp puts

; AL = the port's byte: 1 and 2 for the buttons that are down
btns:   mov ah, al
        mov dl, '-'
        test ah, 10h
        jnz .a
        mov dl, '1'
.a:     push ax
        mov ah, 02h
        int 21h
        pop ax
        mov dl, '-'
        test ah, 20h
        jnz .b
        mov dl, '2'
.b:     mov ah, 02h
        int 21h
        ret

px:     dw 0
py:     dw 0
pb:     db 0
bx_:    dw 0
by_:    dw 0
bb:     db 0
        db 0
was:    times 10 db 0FFh        ; what the line before showed (px..bb)
buf:    db "    $"
title:  db "The joystick, by port 201h and by the BIOS; a key ends it.", 13, 10, "$"
s_port: db "port X$"
s_y:    db " Y$"
s_btn:  db " buttons $"
s_bios: db "   BIOS X$"
s_none: db "none$"
crlf:   db 13, 10, "$"
