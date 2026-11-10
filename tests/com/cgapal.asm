; cgapal.asm - the colours of the CGA's graphics modes (docs/cga.md), and
; on a Tandy 1000 (XTGS.CMD's VIDEO=TANDY; docs/tandy.md) the video
; array's mask and palette registers behind them. What a pixel is shown
; in cannot be read back by a program, so the cases here are the BIOS's
; copies of the two registers (40:65, 40:66) and the judge does the rest:
; it works the colours out from the registers and compares the SHR's
; palette with them ("video": "cga4"/"cga6"; tools/cgashr.py colours),
; and the manifest's "cga_colours" says what they should come to. Every
; run draws its picture first and lets it be shown, and ends on a write
; that changes colours only: nothing in B800 is touched after it.
;
; The command line is the mode:
;   4  mode 4. INT 10h 0Bh: the background and the bright bit (BL's bit
;      4), then palette 0: blue, bright green, red, yellow (1 10 12 14).
;      A Tandy: register 1 by INT 10h AX=1000h, three by the ports, and
;      last a mask of 0Dh, which folds 10 onto 8 and 14 onto 12.
;   5  mode 5, the colour burst off: cyan, red, white. 3D9h by the port,
;      then 3D8h's bit 2 off and on again with the mode kept. A Tandy:
;      a mask of 7 and four registers.
;   6  mode 6: the colour of the pixels that are set, by INT 10h 0Bh and
;      by the port. A Tandy: register 0, the ground, as well.
;   T  (a Tandy) the 160x100 mode, 80-column text two scan lines a row:
;      its sixteen colours through the array. Nothing is printed: the
;      exit code says whether a case failed.
;   9  (a Tandy) mode 09h: INT 10h 0Bh writes palette register 0.
        cpu 8086
        org 100h

%macro CHK 1                    ; the case passes under this condition
        pushf
        inc word [ncase]
        popf
        j%+1 %%ok
        call fail
%%ok:
%endmacro

%macro ARRAY 2                  ; a register of the video array <- a value
        mov dx, 3DAh
        mov al, %1
        out dx, al
        mov dx, 3DEh
        mov al, %2
        out dx, al
%endmacro

start:  cld
        mov bl, '4'
        cmp byte [80h], 0
        je .noarg
        mov bl, [82h]
.noarg: and bl, 0DFh            ; (a digit loses bit 5 too: '5' is 15h)
        mov ax, 0F000h          ; a 1000's BIOS: FFh at F000:FFFE, 21h at
        mov es, ax              ; F000:C000
        cmp byte [es:0FFFEh], 0FFh
        jne .pc
        cmp byte [es:0C000h], 21h
        jne .pc
        mov byte [tandy], 1
.pc:    mov ax, 40h
        mov es, ax
        cmp byte [es:65h], 29h  ; 1: text: what the BIOS wrote to 3D8h
        CHK e
        cmp byte [es:66h], 30h  ; 2: and to 3D9h
        CHK e
        cmp bl, '5' & 0DFh
        jne .n5
        jmp mode5
.n5:    cmp bl, '6' & 0DFh
        jne .n6
        jmp mode6
.n6:    cmp bl, 'T'
        jne .nt
        jmp t160
.nt:    cmp bl, '9' & 0DFh
        jne mode4
        jmp mode9

; ---- mode 4 --------------------------------------------------------------
mode4:  mov ax, 0004h
        int 10h
        cmp byte [es:65h], 2Ah  ; 3: 320 across, the burst on
        CHK e
        cmp byte [es:66h], 30h  ; 4: black, palette 1, bright
        CHK e
        mov bx, pat4
        call picture
        call ticks
        mov ah, 0Bh             ; the background blue, the three bright still
        mov bx, 0011h
        int 10h
        cmp byte [es:66h], 31h  ; 5
        CHK e
        mov ah, 0Bh             ; palette 0: green, red, brown (yellow, bright)
        mov bx, 0100h
        int 10h
        cmp byte [es:66h], 11h  ; 6
        CHK e
        mov ah, 0Bh             ; a background without bit 4: not bright
        mov bx, 0001h
        int 10h
        cmp byte [es:66h], 01h  ; 7
        CHK e
        mov ah, 0Bh             ; and palette 1 comes back with BH=1 alone
        mov bx, 0101h
        int 10h
        cmp byte [es:66h], 21h  ; 8
        CHK e
        call ticks
        mov ah, 0Bh
        mov bx, 0100h
        int 10h
        mov ah, 0Bh             ; as the judge finds it: 1, 10, 12, 14
        mov bx, 0011h
        int 10h
        cmp byte [es:66h], 11h  ; 9
        CHK e
        cmp byte [es:65h], 2Ah  ; 10: 3D8h's copy as it was
        CHK e
        cmp byte [tandy], 0
        jne .t
        jmp report
.t:     mov ax, 1000h           ; register 1 <- 5: blue is shown as magenta
        mov bx, 0501h
        int 10h
        ARRAY 1Ah, 09h          ; bright green as bright blue
        ARRAY 1Ch, 02h          ; bright red as green
        ARRAY 1Eh, 07h          ; yellow as white
        call ticks
        ARRAY 01h, 0Dh          ; the mask: 10 is register 8, 14 register 12
        jmp report

; ---- mode 5 --------------------------------------------------------------
mode5:  mov ax, 0005h
        int 10h
        cmp byte [es:65h], 2Eh  ; 3: 320 across, the burst off
        CHK e
        cmp byte [es:66h], 30h  ; 4
        CHK e
        mov ah, 0Fh
        int 10h
        cmp ax, 2805h           ; 5
        CHK e
        mov bx, pat4
        call picture
        call ticks              ; bright cyan, red and white on black
        mov dx, 3D9h
        mov al, 06h             ; a brown ground, the three not bright, and
        out dx, al              ; palette 0, which mode 5 does not look at
        call ticks
        mov dx, 3D8h
        mov al, 2Ah             ; the burst on with the mode kept: mode 4's
        out dx, al              ; green, red and brown
        call ticks
        mov dx, 3D8h
        mov al, 2Eh             ; and off again: 6, 3, 4, 7
        out dx, al
        cmp byte [es:66h], 30h  ; 6: the BIOS was told none of it
        CHK e
        cmp byte [tandy], 0
        jne .t
        jmp report
.t:     call ticks
        ARRAY 01h, 07h          ; a mask that changes none of the four
        ARRAY 13h, 0Dh          ; cyan as bright magenta
        ARRAY 14h, 0Ah          ; red as bright green
        ARRAY 16h, 00h          ; the brown ground black
        call ticks
        ARRAY 17h, 01h          ; and white as blue
        jmp report

; ---- mode 6 --------------------------------------------------------------
mode6:  mov ax, 0006h
        int 10h
        cmp byte [es:65h], 1Eh  ; 3: 640 across
        CHK e
        cmp byte [es:66h], 3Fh  ; 4: the pixels white
        CHK e
        mov bx, pat6
        call picture
        call ticks
        mov ah, 0Bh             ; yellow
        mov bx, 000Eh
        int 10h
        cmp byte [es:66h], 2Eh  ; 5
        CHK e
        call ticks
        mov dx, 3D9h            ; bright green, by the port
        mov al, 0Ah
        out dx, al
        cmp byte [es:66h], 2Eh  ; 6
        CHK e
        cmp byte [tandy], 0
        jne .t
        jmp report
.t:     call ticks
        ARRAY 10h, 01h          ; the ground blue
        call ticks
        ARRAY 1Ah, 0Bh          ; and bright green shown as bright cyan
        jmp report

; ---- the 160x100 mode on a Tandy -----------------------------------------
t160:   mov dx, 3D8h
        mov al, 1               ; 80 columns, video off
        out dx, al
        mov dx, 3D4h
        mov ax, 7F04h           ; vertical total
        out dx, ax
        mov ax, 6406h           ; vertical displayed = 100
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
.col:   mov al, 0DEh            ; the right half the low nibble's colour
        stosb
        mov al, bl
        add al, cl              ; the attribute: row + column
        stosb
        inc cx
        cmp cx, 80
        jb .col
        inc bx
        cmp bx, 100
        jb .row
        call ticks
        ARRAY 14h, 0Eh          ; red as yellow
        ARRAY 1Fh, 00h          ; white as black
        ARRAY 01h, 07h          ; and eight colours, not sixteen
        call ticks
        ARRAY 12h, 0Ch          ; green as bright red
        mov ax, 4C00h           ; (not a word: the BIOS would write it in
        cmp word [nbad], 0      ; the cells, and the judge reads them all)
        je .exit
        inc ax
.exit:  int 21h

; ---- mode 09h on a Tandy -------------------------------------------------
mode9:  mov ax, 0009h
        int 10h
        mov ax, 0B800h
        mov es, ax
        xor di, di
        xor bx, bx
.fill:  mov al, bl              ; sixteen bars across in each line bank
        mov cl, 4
        shl al, cl
        or al, bl
        mov cx, 10
        rep stosb
        inc bx
        and bx, 0Fh
        cmp di, 8000h - 10      ; (the last eight bytes are no line's)
        jbe .fill
        call ticks
        mov ah, 0Bh             ; the background: register 0 <- 3, and the
        mov bx, 0013h           ; colour-select register's copy all the same
        int 10h
        mov ax, 40h
        mov es, ax
        cmp byte [es:66h], 33h  ; 3
        CHK e
        mov ah, 0Bh             ; BH=1 is the CGA's palette bit and no
        mov bx, 0100h           ; register of the array
        int 10h
        cmp byte [es:66h], 13h  ; 4
        CHK e

report: mov ax, [ncase]         ; "cgapal: N cases, N bad[: n n n]"
        mov di, msg_n
        call dec3
        mov ax, [nbad]
        mov di, msg_b
        call dec3
        mov dx, msg
        mov ah, 9
        int 21h
        mov cx, [nbad]
        cmp cx, 12
        jbe .few
        mov cx, 12
.few:   jcxz .done
        mov si, badlist
.bl:    lodsw
        mov di, num+1
        call dec3
        mov dx, num
        mov ah, 9
        int 21h
        loop .bl
.done:  mov ax, 4C00h
        cmp word [nbad], 0
        je .exit
        inc ax
.exit:  int 21h

; ---- helpers -------------------------------------------------------------
fail:   push ax
        push bx
        mov bx, [nbad]
        inc word [nbad]
        cmp bx, 12
        jae .full
        shl bx, 1
        mov ax, [ncase]
        mov [badlist+bx], ax
.full:  pop bx
        pop ax
        ret

dec3:   mov bx, 100             ; AX (under 1000) as three digits at DI
        xor dx, dx
        div bx
        add al, '0'
        mov [di], al
        mov ax, dx
        mov bl, 10
        div bl
        add ax, '00'
        mov [di+1], ax
        ret

ticks:  call tick               ; long enough for the screen to be drawn
        call tick
tick:   mov ah, 0               ; until the BIOS tick count moves
        int 1Ah
        mov si, dx
.l:     mov ah, 0
        int 1Ah
        cmp dx, si
        je .l
        ret

; picture - both fields of B800: four bars of twenty bytes across, each
; band of 25 lines a bar on from the one above. BX: the four bytes of
; the bars (every pixel value in modes 4 and 5). ES is 40h again after.
picture:
        mov ax, 0B800h
        mov es, ax
        xor bp, bp              ; y
.line:  mov ax, bp
        shr ax, 1
        mov dx, 80
        mul dx
        mov di, ax
        test bp, 1
        jz .even
        add di, 2000h
.even:  mov ax, bp
        mov dl, 25
        div dl                  ; al = the band
        mov dl, al
        mov dh, 4
.bar:   mov si, dx
        and si, 3
        mov al, [bx+si]
        mov cx, 20
        rep stosb
        inc dl
        dec dh
        jnz .bar
        inc bp
        cmp bp, 200
        jb .line
        mov ax, 40h
        mov es, ax
        ret

tandy:  db 0
ncase:  dw 0
nbad:   dw 0
badlist: times 12 dw 0
pat4:   db 00h, 55h, 0AAh, 0FFh
pat6:   db 00h, 0FFh, 0AAh, 0F0h
msg:    db 'cgapal: '
msg_n:  db '000 cases, '
msg_b:  db '000 bad', '$'
num:    db ' 000$'
