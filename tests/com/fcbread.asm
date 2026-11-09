; fcbread.asm - mimic EDLIN's load: FCB open, SET_DMA, record size 1,
; FCB random block read with a big count, then report AL, CX and the buffer.
        org 100h
        mov dx, fcb
        mov ah, 0Fh             ; FCB open
        int 21h
        cmp al, 0
        jne .err
        mov word [fcb+14], 1    ; record size = 1
        xor ax, ax
        mov word [fcb+33], ax   ; random record lo
        mov word [fcb+35], ax   ; random record hi
        mov dx, buf
        mov ah, 1Ah             ; SET_DMA
        int 21h
        mov cx, 200             ; request many records
        mov dx, fcb
        mov ah, 27h             ; FCB random block read
        int 21h
        mov [rc], al
        mov [cnt], cx
        ; print "AL=<hex> CX=<dec>\r\n"
        mov dx, almsg
        mov ah, 9
        int 21h
        mov al, [rc]
        call hexbyte
        mov dx, cxmsg
        mov ah, 9
        int 21h
        mov ax, [cnt]
        call decword
        mov dl, 13
        mov ah, 2
        int 21h
        mov dl, 10
        mov ah, 2
        int 21h
        ; dump the buffer (cnt bytes) to stdout
        mov cx, [cnt]
        mov bx, 1
        mov dx, buf
        mov ah, 40h
        int 21h
        mov ax, 4C00h
        int 21h
.err:   mov dx, emsg
        mov ah, 9
        int 21h
        mov ax, 4C01h
        int 21h
hexbyte:                        ; AL in hex
        push ax
        mov cl, 4
        shr al, cl
        call hexnib
        pop ax
        and al, 0Fh
hexnib: add al, '0'
        cmp al, '9'
        jbe .p
        add al, 7
.p:     mov dl, al
        mov ah, 2
        int 21h
        ret
decword:                        ; AX unsigned decimal
        push bx
        push cx
        mov bx, 10
        xor cx, cx
.d:     xor dx, dx
        div bx
        push dx
        inc cx
        test ax, ax
        jnz .d
.o:     pop dx
        add dl, '0'
        mov ah, 2
        int 21h
        loop .o
        pop cx
        pop bx
        ret
fcb:    db 0                     ; drive = default
        db 'HELLO   TXT'
        times 25 db 0
almsg   db 'AL=$'
cxmsg   db ' CX=$'
emsg    db 'FCB open failed', 13, 10, '$'
rc      db 0
cnt     dw 0
buf     times 256 db 0
