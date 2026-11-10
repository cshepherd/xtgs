; t160.asm - the 160x100 16-colour mode (docs/cga.md): 80-column text with
; the 6845's maximum scan line at 1, set the way programs set it, through
; the ports. The judge compares the SHR pixels with all 16,000 bytes of
; B800 ("video": "t160"). The second half changes cells after the screen
; has been drawn once: only their pages are looked at again.
        org 100h

        mov dx, 3D8h
        mov al, 1               ; 80 columns, video off
        out dx, al
        mov dx, 3D4h
        mov al, 4               ; vertical total, a byte at a time
        out dx, al
        inc dx
        mov al, 7Fh
        out dx, al
        dec dx
        mov ax, 6406h           ; vertical displayed = 100: register and value in a word
        out dx, ax
        mov ax, 7007h           ; vertical sync position
        out dx, ax
        mov ax, 0109h           ; maximum scan line = 1: two scan lines a row
        out dx, ax
        mov dx, 3D8h
        mov al, 9               ; 80 columns, video on, blink off
        out dx, al

        mov ax, 0B800h
        mov es, ax
        xor di, di
        xor bx, bx              ; row
.row:   xor cx, cx              ; column
.col:   mov ax, cx
        mov dl, 10
        div dl                  ; al = column / 10
        add al, bl
        and ax, 7
        mov si, chars
        add si, ax
        mov al, [si]            ; the character: by row and ten columns
        stosb
        mov al, bl
        add al, bl
        add al, bl
        add al, cl              ; the attribute: row * 3 + column
        stosb
        inc cx
        cmp cx, 80
        jb .col
        inc bx
        cmp bx, 100
        jb .row

        call tick               ; let the screen be drawn
        call tick
        call tick

        mov byte [es:1], 0E1h   ; one attribute byte
        mov word [es:254], 4EDDh        ; the last cell of a 256-byte page
        mov word [es:256], 0A5DEh       ; and the first of the next
        mov word [es:15998], 0C3DDh     ; the last cell of the screen
        mov di, 50 * 160        ; a row with one instruction
        mov ax, 2FDEh
        mov cx, 80
        rep stosw
        mov ax, 4C00h
        int 21h

tick:   mov ah, 0               ; until the BIOS tick count moves
        int 1Ah
        mov si, dx
.l:     mov ah, 0
        int 1Ah
        cmp dx, si
        je .l
        ret

chars:  db 0DDh, 0DEh, 0DBh, 0B0h, 0B1h, 0B2h, 20h, 'A'
