; tandya.asm - a Tandy 1000's mode 0Ah, 640x200 in four colours
; (src/svc/tandy.s, docs/tandy.md): mode 09h's 32K and its four line
; banks, a line eighty pairs of bytes and a pair eight pixels, the even
; byte the low bit of each pixel's colour and the odd byte the high bit.
; It runs on the PC that XTGS.CMD's VIDEO=TANDY makes. The cases: the
; mode and what the BIOS says of it (the page register, the BDA's
; copies of 3D8h and 3D9h); the 32K as memory; the pixel calls, both
; bytes of a pair; the pages; the mode set that keeps the screen; text
; again. The failed cases are named at the end.
;
; It ends on a picture the judge compares with the SHR pixels and the
; palette ("video": "tandyA"; tools/tandyshr.py): drawn, left for a
; frame, then written over in places, so that a line that is not drawn
; again shows. As it is, in pages 6 and 7 after the BIOS set the mode,
; two palette registers changed. With the command line "P": the mode is
; entered from text by the ports alone, the picture is in pages 2 and
; 3 with the whole palette turned round behind a mask of 0Eh (two
; colours of the four left), and at the end the CPU has pages 6 and 7
; again and fills them while 2 and 3 are shown. With "X" the first
; picture is left by the array's mode register alone, for the CGA's
; mode 6 on the same bytes ("video": "cga6"), and with "T" the 32K is
; filled with blank cells and left by 3D8h for text, which must then
; show them ("video": "text").
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
        cmp byte [80h], 0       ; "P": by the ports, on pages 2 and 3
        je .noarg
        mov al, [82h]
        and al, 0DFh
        mov [arg], al
        cmp al, 'P'
        jne .noarg
        mov byte [onp], 1
.noarg:
        mov ax, 000Ah
        int 10h
        mov ah, 0Fh
        int 10h
        cmp ax, 500Ah           ; 1: mode 0Ah, 80 columns
        CHK e
        mov ax, 40h
        mov es, ax
        cmp byte [es:49h], 0Ah  ; 2: in the BDA
        CHK e
        cmp word [es:4Ah], 80   ; 3
        CHK e
        cmp byte [es:8Ah], 0F6h ; 4: pages 6 and 7 for both
        CHK e
        cmp byte [es:65h], 3Bh  ; 5: what the BIOS wrote to 3D8h
        CHK e
        cmp byte [es:66h], 3Fh  ; 6: and to 3D9h
        CHK e
        mov ax, 0580h
        int 10h
        cmp bx, 0606h           ; 7
        CHK e

; ---- the 32K as memory ---------------------------------------------------
        mov ax, 0B800h
        mov es, ax
        xor di, di
        xor ax, ax
        mov cx, 4000h
        repe scasw              ; 8: the mode set cleared it
        CHK e
        mov word [es:0], 1234h
        mov word [es:4000h], 5678h
        cmp word [es:0], 1234h  ; 9: BC00 is not B800 again
        CHK e
        xor di, di
        mov ax, 5AA5h
        mov cx, 4000h
        rep stosw
        xor di, di
        mov cx, 4000h
        repe scasw              ; 10: REP STOSW over all of it
        CHK e
        call clear

; ---- INT 10h's pixels ----------------------------------------------------
        mov al, 1
        xor cx, cx
        xor dx, dx
        call setpix
        cmp word [es:0], 0080h  ; 11: the left pixel is bit 7, colour 1 the
        CHK e                   ; even byte's
        mov al, 2
        mov cx, 1
        xor dx, dx
        call setpix
        cmp word [es:0], 4080h  ; 12: colour 2 the odd byte's
        CHK e
        mov al, 3
        mov cx, 7
        xor dx, dx
        call setpix
        cmp word [es:0], 4181h  ; 13: colour 3 both
        CHK e
        mov al, 3
        mov cx, 639
        mov dx, 199
        call setpix
        cmp word [es:7F3Eh], 0101h      ; 14: the last one
        CHK e
        mov al, 2
        mov cx, 8
        mov dx, 1
        call setpix
        cmp word [es:2002h], 8000h      ; 15: line 1 is the second 8K
        CHK e
        mov al, 1
        mov cx, 17
        mov dx, 6
        call setpix
        cmp word [es:40A4h], 0040h      ; 16: line 6 the third's second row
        CHK e
        mov al, 83h
        mov cx, 17
        mov dx, 6
        call setpix
        cmp word [es:40A4h], 4000h      ; 17: bit 7: XOR
        CHK e
        mov cx, 17
        mov dx, 6
        call getpix
        cmp al, 2               ; 18: and read
        CHK e
        mov cx, 7
        xor dx, dx
        call getpix
        cmp al, 3               ; 19
        CHK e
        mov cx, 1
        xor dx, dx
        call getpix
        cmp al, 2               ; 20
        CHK e
        xor cx, cx
        xor dx, dx
        call getpix
        cmp al, 1               ; 21
        CHK e
        mov cx, 2
        xor dx, dx
        call getpix
        cmp al, 0               ; 22
        CHK e
        mov cx, 639
        mov dx, 199
        call getpix
        cmp al, 3               ; 23
        CHK e
        mov al, 1
        mov cx, 7
        xor dx, dx
        call setpix
        cmp word [es:0], 4081h  ; 24: a colour over another: both bytes
        CHK e
        mov al, 0
        xor cx, cx
        xor dx, dx
        call setpix
        cmp word [es:0], 4001h  ; 25
        CHK e
        mov al, 3
        mov cx, 640
        xor dx, dx
        call setpix
        cmp word [es:00A0h], 0  ; 26: off the screen: nothing
        CHK e
        mov al, 3
        xor cx, cx
        mov dx, 200
        call setpix
        cmp word [es:1F40h], 0  ; 27
        CHK e

; ---- the pages -----------------------------------------------------------
        call clear
        mov word [es:0], 6606h          ; pages 6 and 7
        mov word [es:4000h], 7707h
        PAGEREG 0D6h                    ; the CPU has 2 and 3, the screen 6 and 7
        mov ax, 0580h
        int 10h
        cmp bx, 0602h           ; 28
        CHK e
        mov word [es:0], 2202h
        mov word [es:4000h], 3303h
        mov ax, 0583h                   ; both, by the BIOS
        mov bx, 0606h
        int 10h
        cmp word [es:0], 6606h  ; 29: 6 and 7 as they were left
        CHK e
        cmp word [es:4000h], 7707h      ; 30
        CHK e
        mov ax, 0581h           ; the CPU's page
        mov bl, 2
        int 10h
        cmp word [es:0], 2202h  ; 31
        CHK e
        cmp word [es:4000h], 3303h      ; 32
        CHK e
        mov cx, 9               ; a pixel is written in the CPU's pages
        mov dx, 2
        mov al, 3
        call setpix
        cmp word [es:4002h], 4040h      ; 33
        CHK e
        mov ax, 0583h
        mov bx, 0606h
        int 10h
        cmp word [es:4002h], 0  ; 34: and not in the screen's
        CHK e

; ---- the mode set again --------------------------------------------------
        mov word [es:0], 0C33Ch
        mov word [es:7F3Eh], 0A55Ah
        mov ax, 008Ah           ; bit 7: the screen is kept
        int 10h
        cmp word [es:0], 0C33Ch ; 35
        CHK e
        cmp word [es:7F3Eh], 0A55Ah     ; 36
        CHK e
        mov ah, 0Bh             ; the colour-select register, by the BIOS:
        mov bx, 0005h           ; its copy follows
        int 10h
        push es
        mov ax, 40h
        mov es, ax
        cmp byte [es:66h], 25h  ; 37
        pop es
        CHK e
        mov ax, 0003h
        int 10h
        mov ah, 0Fh
        int 10h
        cmp ax, 5003h           ; 38: text
        CHK e
        push es
        mov ax, 40h
        mov es, ax
        cmp byte [es:8Ah], 3Fh  ; 39: on page 7
        CHK e
        cmp byte [es:65h], 29h  ; 40
        CHK e
        cmp byte [es:66h], 30h  ; 41
        pop es
        CHK e
        mov ax, 0E54h           ; (the teletype, in text)
        mov bx, 0007h
        int 10h
        cmp word [es:0], 0754h  ; 42: and B800 is the text
        CHK e

; ---- the picture ---------------------------------------------------------
        cmp byte [onp], 0
        jne .ports
        mov ax, 000Ah
        int 10h
        ARRAY 11h, 0Ch          ; palette register 1, by the port
        mov ax, 1000h           ; and 2, by the BIOS
        mov bx, 0E02h
        int 10h
        jmp .draw
.ports: PAGEREG 0F6h            ; as the BIOS does it: the pages,
        ARRAY 01h, 0Fh          ; the mask, the border, four colours at
        ARRAY 02h, 00h          ; 640,
        ARRAY 03h, 0Ch
        mov dx, 3D8h            ; and 640 graphics, enabled
        mov al, 3Bh
        out dx, al
        inc dx
        mov al, 3Fh
        out dx, al
        PAGEREG 0D2h            ; pages 2 and 3 for the CPU and the screen
        mov ax, 1002h           ; all sixteen registers and the border
        push es
        push ds
        pop es
        mov dx, pal
        int 10h
        pop es
        ARRAY 01h, 0Eh          ; the mask: colours 0 and 2
.draw:  call picture
        call tick               ; the frame draws it
        call tick

        mov bx, 20              ; a line of pixels through every screen line
        xor dx, dx
.diag:  mov cx, bx
        mov al, dl
        and al, 3
        jnz .dc
        mov al, 3
.dc:    call setpix
        add bx, 3
        inc dx
        cmp dx, 200
        jb .diag
        mov byte [es:0], 0F1h           ; the first byte, and the last of
        mov byte [es:1F3Fh], 0F2h       ; each 8K's fifty rows
        mov byte [es:3F3Fh], 0F3h
        mov byte [es:5F3Fh], 0F4h
        mov byte [es:7F3Fh], 0F5h
        mov word [es:20FFh], 0E1E2h     ; a word across two 256s (and two pairs)
        mov di, 0FA0h                   ; line 100, with one instruction
        mov al, 0EEh
        mov cx, 160
        rep stosb
        mov di, 3FF0h                   ; from the first 16K into the second
        mov ax, 0D00Dh                  ; (line 8's first bytes)
        mov cx, 16
        rep stosw
        mov si, pat                     ; a row moved in
        mov di, 6000h + 30 * 160
        mov cx, 80
        rep movsw
        call tick
        call tick

        cmp byte [arg], 'X'
        jne .notx
        ARRAY 03h, 00h          ; no longer four colours at 640: mode 6
        call tick
        call tick
.notx:  cmp byte [arg], 'T'
        jne .nott
        xor di, di              ; blank cells, drawn as stripes
        mov ax, 0720h
        mov cx, 4000h
        rep stosw
        call tick
        call tick
        mov dx, 3D8h            ; 80-column text, enabled
        mov al, 29h
        out dx, al
        call tick
        call tick
.nott:  cmp byte [onp], 0
        je .report
        PAGEREG 0F2h            ; 2 and 3 shown, 6 and 7 the CPU's
        xor di, di
        mov ax, 0FFFFh
        mov cx, 4000h
        rep stosw               ; which must not show
        call tick
        call tick

.report:
        mov ax, [ncase]         ; "tandya: N cases, N bad[: n n n]"
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

clear:  xor di, di              ; the 32K at ES <- 0
        xor ax, ax
        mov cx, 4000h
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

tick:   mov ah, 0               ; until the BIOS tick count moves
        int 1Ah
        mov si, dx
.l:     mov ah, 0
        int 1Ah
        cmp dx, si
        je .l
        ret

; the picture: sixteen bars of forty pixels, each band of eight lines a
; colour on from the one above; the bars of the second quarter and the
; fourth have every other pixel one colour on, those of the right half
; two pixels in four two colours on. Line y is at (y & 3) * 8K +
; (y >> 2) * 160, a pair the low bits of its eight pixels and then the
; high bits.
picture:
        xor bp, bp              ; y
.line:  mov ax, bp
        shr ax, 1
        shr ax, 1
        mov bx, 160
        mul bx
        mov di, ax
        mov ax, bp
        and ax, 3
        mov cl, 13
        shl ax, cl
        add di, ax
        mov bx, bp
        mov cl, 3
        shr bx, cl              ; the band
        xor dx, dx              ; the bar
.bar:   mov al, bl
        add al, dl
        mov ah, 0
        test al, 2
        jz .h0
        mov ah, 0FFh
.h0:    test al, 1
        mov al, 0
        jz .l0
        mov al, 0FFh
.l0:    test dl, 4
        jz .n4
        xor al, 55h
.n4:    test dl, 8
        jz .n8
        xor ah, 33h
.n8:    mov cx, 5
        rep stosw
        inc dx
        cmp dx, 16
        jb .bar
        inc bp
        cmp bp, 200
        jb .line
        ret

onp:    db 0
arg:    db 0
ncase:  dw 0
nbad:   dw 0
badlist: times 12 dw 0
pat:
%assign i 1
%rep 160
        db (i * 7) & 0FFh
%assign i i+1
%endrep
pal:    db 0Fh, 0Eh, 0Dh, 0Ch, 0Bh, 0Ah, 9, 8
        db 7, 6, 5, 4, 3, 2, 1, 0, 0
msg:    db 'tandya: '
msg_n:  db '000 cases, '
msg_b:  db '000 bad', '$'
num:    db ' 000', '$'
