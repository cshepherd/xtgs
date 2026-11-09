; strings.asm - the BIOS video services and string instructions: set mode,
; position the cursor, write a string at a position (INT 10h/13h), read the
; cursor back, XLAT through a table, REPE CMPSB, INT 21h/40h to stdout,
; INT 10h/0E teletype; exits with code 7.
        org 100h
start:  mov ax, 0003h           ; mode 3: clear
        int 10h
        mov ah, 02h             ; cursor to row 10, column 20
        xor bh, bh
        mov dx, 0A14h
        int 10h
        mov ax, 1301h           ; write string, cursor follows it
        mov bx, 0007h
        mov cx, msg1_len
        mov dx, 0A14h
        push cs
        pop es
        mov bp, msg1
        int 10h
        mov ah, 03h             ; where is the cursor now?
        xor bh, bh
        int 10h
        push dx
        mov dx, txt1
        mov ah, 9
        int 21h
        pop dx
        push dx
        mov al, dh
        xor ah, ah
        call printdec
        mov dl, ','
        mov ah, 2
        int 21h
        pop dx
        mov al, dl
        xor ah, ah
        call printdec
        call newline
        mov si, text            ; uppercase through XLAT
        mov di, upper
        mov bx, uptab
        mov cx, text_len
        cld
.up:    lodsb
        xlat
        stosb
        loop .up
        mov ah, 40h             ; write(1, upper, len)
        mov bx, 1
        mov cx, text_len
        mov dx, upper
        int 21h
        call newline
        mov si, text            ; compare two strings
        mov di, text2
        mov cx, text_len
        repe cmpsb
        jne .diff
        mov dx, same
        jmp .say
.diff:  mov dx, differ
.say:   mov ah, 9
        int 21h
        mov si, tty             ; teletype through the BIOS
.tty:   lodsb
        test al, al
        jz .done
        mov ah, 0Eh
        mov bx, 0007h
        int 10h
        jmp .tty
.done:  mov ax, 4C07h
        int 21h

printdec:                       ; ax unsigned in decimal; preserves bx cx
        push bx
        push cx
        mov bx, 10
        xor cx, cx
.div:   xor dx, dx
        div bx
        push dx
        inc cx
        test ax, ax
        jnz .div
.out:   pop dx
        add dl, '0'
        mov ah, 2
        int 21h
        loop .out
        pop cx
        pop bx
        ret
newline:
        mov dl, 13
        mov ah, 2
        int 21h
        mov dl, 10
        mov ah, 2
        int 21h
        ret

msg1    db 'AT 10,20'
msg1_len equ $-msg1
txt1    db 'Cursor: $'
text    db 'Hello, World of xt/gs!'
text_len equ $-text
text2   db 'Hello, World of xt/gs?'
upper   times text_len db 0
same    db 'same', 13, 10, '$'
differ  db 'differ', 13, 10, '$'
tty     db 'Teletype OK', 13, 10, 0
uptab:
%assign i 0
%rep 256
  %if i >= 'a' && i <= 'z'
        db i - 32
  %else
        db i
  %endif
  %assign i i+1
%endrep
