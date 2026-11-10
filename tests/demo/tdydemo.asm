; tdydemo.asm - TDYDEMO.COM: a Tandy 1000's 320x200 16-colour mode (09h)
; on XT/GS (docs/tandy.md; XTGS.CMD's line VIDEO=TANDY). A picture is
; drawn on pages 6 and 7, which the mode shows, and another on pages 4
; and 5 while the first is on the screen (the CPU's page, INT 10h
; AX=0581h); then the screen goes from one to the other (AX=0582h) and
; the palette round (AX=1002h) until a key. "TDYDEMO 8" is the same in
; the 160x200 mode (08h): a page a picture, 7 and then 5, and
; "TDYDEMO A" in the 640x200 mode of four colours (0Ah): the sixteen
; shades are the four colours and three mixtures between each two.
; tools/build_freedos.py assembles it onto the FreeDOS folder and floppy.
;       nasm -f bin -o TDYDEMO.COM tdydemo.asm
        cpu 8086
        org 100h

start:  mov ax, 0F000h          ; a 1000's BIOS: FFh at F000:FFFE, 21h at
        mov es, ax              ; F000:C000
        cmp byte [es:0FFFEh], 0FFh
        jne .no
        cmp byte [es:0C000h], 21h
        je .tandy
.no:    mov dx, notandy
        mov ah, 09h
        int 21h
        mov ax, 4C01h
        int 21h
.tandy: mov ax, 0009h
        cmp byte [80h], 0
        je .mode
        mov bl, [82h]
        and bl, 0DFh
        cmp bl, 'A'
        jne .not4
        inc ax                  ; mode 0Ah: mode 09h's lines, a cell two
        mov byte [four], 1      ; pairs of bytes
.not4:  cmp byte [82h], '8'
        jne .mode
        dec ax                  ; mode 08h: half the bytes a line, in two
        mov byte [lsh], 1       ; banks of 8K, a page each picture
        mov word [lmask], 1
        mov word [rowb], 80
        mov word [cellb], 2
        mov byte [shown], 7
        mov byte [hidden], 5
.mode:  int 10h
        mov ax, 0B800h
        mov es, ax
        cld
        mov word [shade], xors  ; pages 6 and 7: the screen's
        call draw
        mov ax, 0581h           ; pages 4 and 5 at B800, 6 and 7 still shown
        mov bl, [hidden]
        int 10h
        mov word [shade], rings
        call draw

.turn:  xor byte [shown], 2     ; the screen: 4, 6, 4...
        mov bh, [shown]
        mov ax, 0582h
        int 10h
        mov bp, 12              ; and twelve steps of the palette on each
.step:  mov al, [pal+1]         ; registers 1-15 one on; 0 stays black
        mov si, pal+2
        mov di, pal+1
        mov cx, 14
        push es
        push ds
        pop es
        rep movsb
        mov [pal+15], al
        mov dx, pal
        mov ax, 1002h
        int 10h
        pop es
        mov cx, 2               ; two ticks
.wait:  push cx
        mov ah, 0
        int 1Ah
        mov si, dx
.same:  mov ah, 1
        int 16h
        jnz .key
        mov ah, 0
        int 1Ah
        cmp dx, si
        je .same
        pop cx
        loop .wait
        dec bp
        jnz .step
        jmp .turn
.key:   mov ah, 0
        int 16h
        mov ax, 0003h
        int 10h
        mov ax, 4C00h
        int 21h

; draw - the 32K at B800: line BP is in the 8K bank BP & 3 at (BP >> 2) *
; 160, eight pixels (four bytes) at a time in the colour [shade] gives
; for column BX (0-39) and line BP. In mode 08h: bank BP & 1, at
; (BP >> 1) * 80, four pixels (two bytes) at a time.
draw:   xor bp, bp
.line:  mov ax, bp
        mov cl, [lsh]
        shr ax, cl
        mul word [rowb]
        mov di, ax
        mov ax, bp
        and ax, [lmask]
        mov cl, 13
        shl ax, cl
        add di, ax
        xor bx, bx
.cell:  call [shade]
        and al, 0Fh
        cmp byte [four], 0
        jne .c4
        mov ah, al
        mov cl, 4
        shl ah, cl
        or al, ah
        mov cx, [cellb]
        rep stosb
        jmp short .next
.c4:    push bx                 ; mode 0Ah: the shade's high two bits are
        mov bl, al              ; the colour, and its low two say how many
        and bx, 3               ; pixels in eight are the next colour
        mov dl, [dith+bx]
        test bp, 1
        jz .even
        rol dl, 1               ; (on an odd line, the ones beside them)
.even:  mov ah, 0               ; the colour in all eight: its high bit is
        test al, 8              ; the odd byte, its low bit the even one
        jz .h0
        dec ah
.h0:    test al, 4
        mov al, 0
        jz .l0
        dec al
.l0:    mov bl, al              ; one added where DL says: the low bit
        and bl, dl              ; turns, and the high bit where it carries
        xor al, dl
        xor ah, bl
        pop bx
        stosw
        stosw
.next:  inc bx
        cmp bx, 40
        jb .cell
        inc bp
        cmp bp, 200
        jb .line
        ret

xors:   mov ax, bp              ; (x XOR y) / 8: the squares in squares
        mov cl, 3
        shr ax, cl
        xor ax, bx
        ret

rings:  mov ax, bx              ; the squares of the distances from the
        sub ax, 20              ; middle, added: rings
        imul al
        mov si, ax
        mov ax, bp
        mov cl, 3
        shr ax, cl
        sub ax, 12
        imul al
        add ax, si
        shr ax, 1
        shr ax, 1
        ret

shade:  dw 0
shown:  db 6
hidden: db 4
lsh:    db 2
lmask:  dw 3
rowb:   dw 160
cellb:  dw 4
four:   db 0
dith:   db 00h, 88h, 0AAh, 0EEh
pal:    db 0, 1, 9, 3, 11, 2, 10, 14, 6, 12, 4, 5, 13, 7, 15, 8
        db 0                    ; the border
notandy: db 'This needs a Tandy 1000: VIDEO=TANDY in XTGS.CMD.', 13, 10, '$'
