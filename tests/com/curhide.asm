; curhide.asm - a program hides the cursor by putting it below the screen
; (INT 10h AH=02h, row 25), as Norton's SYSINFO does. The blinking cursor
; must then be nowhere: drawn at "row 25" it was past the SHR's pixels,
; in the first lines' control bytes (two scan lines in 320 mode) and the
; palettes. The judge wants the screen still text ("video": "text").
        cpu 8086
        org 100h
        mov dx, msg
        mov ah, 09h
        int 21h
        mov ah, 02h             ; the cursor to row 25, column 0
        xor bh, bh
        mov dx, 1900h
        int 10h
        mov cx, 24              ; a blink and more: on and off again
        call ticks
        mov ah, 02h             ; and to row 30, column 90
        xor bh, bh
        mov dx, 1E5Ah
        int 10h
        mov cx, 24
        call ticks
        mov ah, 02h             ; back where printing left it
        xor bh, bh
        mov dx, 0100h
        int 10h
        mov ax, 4C00h
        int 21h
ticks:  mov ax, 40h
        mov es, ax
.n:     mov ax, [es:6Ch]
.w:     cmp ax, [es:6Ch]
        je .w
        loop .n
        ret
msg:    db "the cursor goes below the screen", 13, 10, "$"
