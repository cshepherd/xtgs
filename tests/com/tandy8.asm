; tandy8.asm - a Tandy 1000's mode 08h, 160x200 in 16 colours
; (src/svc/tandy.s, docs/tandy.md): one page of 16K, laid out as the
; CGA's graphics are (80 bytes a line, the even lines in the first 8K
; and the odd ones in the second), a byte two pixels of four bits. It
; runs on the PC that XTGS.CMD's VIDEO=TANDY makes. The cases: the mode
; and what the BIOS says of it (20 columns, page 7 for the CPU and the
; screen); the 16K as memory; the pixel calls; a page that is the
; CPU's and not the screen's; the mode set that keeps the screen; the
; mode after mode 09h and after text. The failed cases are named at the
; end.
;
; It ends on a picture the judge compares with the SHR pixels and the
; palette ("video": "tandy8"; tools/tandyshr.py): drawn, left for a
; frame, then written over in places, so that a line that is not drawn
; again shows. As it is, on page 7 after the BIOS set the mode, two
; palette registers changed and the pixels of a slanting line set by
; INT 10h. With the command line "P": the mode is entered from text by
; the ports alone, with pages 6 and 7 the CPU's and 7 the screen's, so
; the picture is written at BC00; the palette is turned round behind a
; mask of 7; the CPU has pages 2 and 3 for a while and fills them while
; 7, in neither half of the window, is shown, and 7 comes back to be
; written over; and at the end page 6, at B800 and not shown, is filled.
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

%macro PAGEREG 1                ; the page register <- a value
        mov dx, 3DFh
        mov al, %1
        out dx, al
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
        cmp byte [80h], 0       ; "P": by the ports, the screen's page at BC00
        je .noarg
        mov al, [82h]
        and al, 0DFh
        cmp al, 'P'
        jne .noarg
        mov byte [onp], 1
.noarg:
        mov ax, 0008h
        int 10h
        mov ah, 0Fh
        int 10h
        cmp ax, 1408h           ; 1: mode 08h, 20 columns
        CHK e
        mov ax, 40h
        mov es, ax
        cmp byte [es:49h], 8    ; 2: in the BDA
        CHK e
        cmp word [es:4Ah], 20   ; 3
        CHK e
        cmp byte [es:8Ah], 3Fh  ; 4: page 7 for the CPU and the screen
        CHK e
        mov ax, 0580h
        int 10h
        cmp bx, 0707h           ; 5
        CHK e

; ---- the 16K as memory ---------------------------------------------------
        mov ax, 0B800h
        mov es, ax
        mov word [es:0], 0FFFFh ; (the mode set again: it clears)
        mov word [es:3FFEh], 0FFFFh
        mov ax, 0008h
        int 10h
        xor di, di
        xor ax, ax
        mov cx, 2000h
        repe scasw              ; 6
        CHK e
        xor di, di
        mov ax, 5AA5h
        mov cx, 2000h
        rep stosw
        xor di, di
        mov cx, 2000h
        repe scasw              ; 7: REP STOSW over all of it
        CHK e
        mov si, pat
        mov di, 3EF0h           ; line 199: the second 8K's row 99
        mov cx, 80
        rep movsb
        mov si, pat
        mov di, 3EF0h
        mov cx, 80
        repe cmpsb              ; 8: REP MOVSB to a line
        CHK e
        cmp word [es:3F40h], 5AA5h      ; 9: and no further
        CHK e
        call clear

; ---- INT 10h's pixels ----------------------------------------------------
        mov al, 0Bh
        xor cx, cx
        xor dx, dx
        call setpix
        cmp byte [es:0], 0B0h   ; 10: the left pixel is the high four bits
        CHK e
        mov al, 0Ch
        mov cx, 1
        xor dx, dx
        call setpix
        cmp byte [es:0], 0BCh   ; 11
        CHK e
        mov al, 7
        mov cx, 159
        mov dx, 199
        call setpix
        cmp byte [es:3F3Fh], 07h        ; 12: the last one
        CHK e
        mov al, 9
        mov cx, 2
        mov dx, 1
        call setpix
        cmp byte [es:2001h], 90h        ; 13: line 1 is the second 8K
        CHK e
        mov al, 0Eh
        mov cx, 10
        mov dx, 6
        call setpix
        cmp byte [es:00F5h], 0E0h       ; 14: line 6 the first's fourth row
        CHK e
        mov al, 8Fh
        mov cx, 10
        mov dx, 6
        call setpix
        cmp byte [es:00F5h], 10h        ; 15: bit 7: XOR
        CHK e
        mov cx, 10
        mov dx, 6
        call getpix
        cmp al, 1               ; 16: and read
        CHK e
        mov cx, 1
        xor dx, dx
        call getpix
        cmp al, 0Ch             ; 17
        CHK e
        mov cx, 159
        mov dx, 199
        call getpix
        cmp al, 7               ; 18
        CHK e
        mov al, 5
        mov cx, 160
        xor dx, dx
        call setpix
        cmp byte [es:0050h], 0  ; 19: off the screen: nothing
        CHK e
        mov al, 5
        xor cx, cx
        mov dx, 200
        call setpix
        cmp byte [es:1F40h], 0  ; 20
        CHK e
        mov cx, 160
        xor dx, dx
        call getpix
        cmp al, 0               ; 21
        CHK e

; ---- the pages -----------------------------------------------------------
        call clear
        mov word [es:0], 7707h          ; page 7
        mov ax, 0581h                   ; the CPU has 5, the screen 7
        mov bl, 5
        int 10h
        mov ax, 0580h
        int 10h
        cmp bx, 0705h           ; 22
        CHK e
        push es
        mov ax, 40h
        mov es, ax
        cmp byte [es:8Ah], 2Fh  ; 23: the BIOS's copy
        pop es
        CHK e
        cmp word [es:0], 7707h  ; 24: B800 is another page
        CHK ne
        mov word [es:0], 5505h
        mov al, 0Ah                     ; a pixel goes to the CPU's page
        mov cx, 3
        xor dx, dx
        call setpix
        cmp word [es:0], 5A05h  ; 25: (and nowhere else in the word)
        CHK e
        mov ax, 0581h
        mov bl, 7
        int 10h
        cmp word [es:0], 7707h  ; 26: 7 as it was left
        CHK e
        cmp byte [es:1], 77h    ; 27
        CHK e
        mov ax, 0583h           ; 4 for both: an even page, 5 behind it
        mov bx, 0404h
        int 10h
        cmp word [es:4000h], 5A05h      ; 28: with its pixel
        CHK e
        cmp word [es:0], 7707h          ; 29: and B800 is not 7
        CHK ne
        mov ax, 0583h
        mov bx, 0707h
        int 10h

; ---- the mode set again --------------------------------------------------
        mov word [es:0], 0C33Ch
        mov word [es:3F3Eh], 0A55Ah
        mov ax, 0088h           ; bit 7: the screen is kept
        int 10h
        cmp word [es:0], 0C33Ch ; 30
        CHK e
        cmp word [es:3F3Eh], 0A55Ah     ; 31
        CHK e
        mov ax, 0009h           ; mode 09h, and 08h after it
        int 10h
        mov word [es:0], 9999h
        mov word [es:4000h], 9999h
        mov ax, 0008h
        int 10h
        mov ah, 0Fh
        int 10h
        cmp ax, 1408h           ; 32
        CHK e
        push es
        mov ax, 40h
        mov es, ax
        cmp byte [es:8Ah], 3Fh  ; 33: page 7 again
        pop es
        CHK e
        cmp word [es:0], 0      ; 34: cleared
        CHK e
        mov ax, 0003h
        int 10h
        mov ah, 0Fh
        int 10h
        cmp ax, 5003h           ; 35: text
        CHK e
        cmp word [es:0], 0720h  ; 36: and B800 is the text
        CHK e

; ---- the picture ---------------------------------------------------------
        cmp byte [onp], 0
        jne .ports
        mov ax, 0008h
        int 10h
        ARRAY 11h, 0Ch          ; palette register 1, by the port
        mov ax, 1000h           ; and 2, by the BIOS
        mov bx, 0E02h
        int 10h
        jmp .draw
.ports: PAGEREG 37h             ; pages 6 and 7 the CPU's, 7 the screen's,
        ARRAY 01h, 0Fh          ; the mask, the border, 16 colours,
        ARRAY 02h, 00h
        ARRAY 03h, 14h
        mov dx, 3D8h            ; and graphics, 160 across, enabled
        mov al, 2Ah
        out dx, al
        mov word [base], 4000h  ; (page 7 is at BC00)
        mov ax, 1002h           ; all sixteen registers and the border
        push es
        push ds
        pop es
        mov dx, pal
        int 10h
        pop es
        ARRAY 01h, 07h          ; the mask: eight colours
.draw:  call picture
        call tick               ; the frame draws it
        call tick
        cmp byte [onp], 0
        je .over
        PAGEREG 17h             ; 7 shown still, 2 and 3 the CPU's:
        xor di, di
        mov ax, 0FFFFh
        mov cx, 4000h
        rep stosw               ; which must not show
        call tick
        call tick
        PAGEREG 37h             ; and 7 is at BC00 again, as it was
        call tick               ; (drawn whole: what follows is not)
        call tick

.over:  mov bp, 20              ; a slanting line through every screen line
        xor dx, dx
.diag:  mov cx, bp
        mov al, 0Fh
        call plot
        mov ax, dx
        and ax, 1
        add bp, ax
        inc dx
        cmp dx, 200
        jb .diag
        mov bx, [base]
        mov byte [es:bx], 0F1h          ; the first byte, and the last of
        mov byte [es:bx+1F3Fh], 0F2h    ; each 8K's hundred rows
        mov byte [es:bx+3F3Fh], 0F3h
        mov word [es:bx+20FFh], 0E1E2h  ; a word across two 256s
        lea di, [bx+0FA0h]              ; line 100, with one instruction
        mov al, 0EEh
        mov cx, 80
        rep stosb
        lea di, [bx+1F30h]              ; the end of the first 8K's last row
        mov ax, 0D00Dh                  ; and on over what is no line
        mov cx, 24
        rep stosw
        lea di, [bx+1FF8h]              ; from the first 8K into the second
        mov ax, 0B00Bh                  ; (line 1's first bytes)
        mov cx, 12
        rep stosw
        mov si, pat                     ; a row moved in
        lea di, [bx+2000h+30*80]
        mov cx, 40
        rep movsw
        call tick
        call tick

        cmp byte [onp], 0
        je .report
        xor di, di              ; page 6, at B800, is not the screen's:
        mov ax, 0FFFFh
        mov cx, 2000h
        rep stosw               ; nor may this show
        call tick
        call tick

.report:
        mov ax, [ncase]         ; "tandy8: N cases, N bad[: n n n]"
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

clear:  xor di, di              ; the 16K at ES <- 0
        xor ax, ax
        mov cx, 2000h
        rep stosw
        ret

setpix: mov ah, 0Ch             ; the pixel CX, DX <- AL
        push bx
        mov bh, 0
        int 10h
        pop bx
        ret

getpix: mov ah, 0Dh             ; AL = the pixel CX, DX
        push bx
        mov bh, 0
        int 10h
        pop bx
        ret

; the pixel CX, DX <- AL on the page shown: by INT 10h when that is the
; CPU's page at B800, and into the byte when it is at BC00 ("P").
; Keeps DX and BP.
plot:   cmp word [base], 0
        je setpix
        push dx
        push ax
        mov ax, dx
        shr ax, 1
        mov bx, 80
        push dx
        mul bx
        pop dx
        mov di, ax              ; (y >> 1) * 80
        test dl, 1
        jz .even
        add di, 2000h
.even:  mov ax, cx
        shr ax, 1
        add di, ax
        add di, [base]
        pop ax
        mov ah, 0F0h            ; an odd x: the low four bits
        test cl, 1
        jnz .put
        mov ah, 0Fh
        shl al, 1
        shl al, 1
        shl al, 1
        shl al, 1
.put:   and [es:di], ah
        or [es:di], al
        pop dx
        ret

tick:   mov ah, 0               ; until the BIOS tick count moves
        int 1Ah
        mov si, dx
.l:     mov ah, 0
        int 1Ah
        cmp dx, si
        je .l
        ret

; the picture: sixteen bars of ten pixels, each band of eight lines a
; colour on from the one above, and the right pixel of every other
; byte a colour on again, so that a pixel shown once, or its neighbour
; twice, is seen; line y is at (y & 1) * 8K + (y >> 1) * 80
picture:
        xor bp, bp              ; y
.line:  mov ax, bp
        shr ax, 1
        mov bx, 80
        mul bx
        mov di, ax
        test bp, 1
        jz .ev
        add di, 2000h
.ev:    add di, [base]
        mov bx, bp
        mov cl, 3
        shr bx, cl              ; the band
        mov dx, 16
.bar:   mov al, bl
        and al, 0Fh
        mov ah, al
        mov cl, 4
        shl ah, cl
        or al, ah
        stosb
        stosb
        inc al                  ; (the right pixel: the next colour)
        and al, 0Fh
        or al, ah
        stosb
        mov al, ah
        mov cl, 4
        shr al, cl
        or al, ah
        stosb
        stosb
        inc bx
        dec dx
        jnz .bar
        inc bp
        cmp bp, 200
        jb .line
        ret

onp:    db 0
base:   dw 0
ncase:  dw 0
nbad:   dw 0
badlist: times 12 dw 0
pat:
%assign i 1
%rep 80
        db (i * 7) & 0FFh
%assign i i+1
%endrep
pal:    db 0Fh, 0Eh, 0Dh, 0Ch, 0Bh, 0Ah, 9, 8
        db 7, 6, 5, 4, 3, 2, 1, 0, 0
msg:    db 'tandy8: '
msg_n:  db '000 cases, '
msg_b:  db '000 bad', '$'
num:    db ' 000', '$'
