; tandy.asm - a Tandy 1000's video (src/svc/tandy.s, docs/tandy.md):
; the page register (3DFh), the video array (3DAh, 3DEh) and mode 09h,
; 320x200 in 16 colours, four bits a pixel in the 32K at B800. It runs
; on the PC that XTGS.CMD's VIDEO=TANDY makes. The cases: the BIOS's two
; identifying bytes; the mode and what the BIOS says of it; the 32K as
; memory (no wrap at 16K, the string instructions over all of it); the
; pixel calls; the eight pages through the port and through INT 10h 05h
; (each keeps its bytes while another is the CPU's, an odd one is at
; B800 alone, an even one brings the next at BC00); the mode set that
; keeps the screen; text again. The failed cases are named at the end.
;
; It ends on a picture the judge compares with the SHR pixels and the
; palette ("video": "tandy9"; tools/tandyshr.py): drawn, left for a
; frame, then written over in places, so that a line that is not drawn
; again shows. As it is, in pages 6 and 7 after the BIOS set the mode,
; two palette registers changed. With the command line "P": the mode is
; entered from text by the ports alone, the picture is in pages 2 and
; 3 with the whole palette turned round behind a mask of 7, and at the
; end the CPU has pages 6 and 7 again and fills them while 2 and 3 are
; shown.
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
        cmp al, 'P'
        jne .noarg
        mov byte [onp], 1
.noarg:
        mov ax, 0F000h
        mov es, ax
        cmp byte [es:0FFFEh], 0FFh      ; 1: the model byte
        CHK e
        cmp byte [es:0C000h], 21h       ; 2: and a 1000's own
        CHK e
        mov ax, 40h
        mov es, ax
        cmp byte [es:8Ah], 3Fh  ; 3: text: page 7 for the CPU and the screen
        CHK e
        mov ax, 0580h
        int 10h
        cmp bx, 0707h           ; 4: and the BIOS says so
        CHK e

        mov ax, 0009h
        int 10h
        mov ah, 0Fh
        int 10h
        cmp ax, 2809h           ; 5: mode 09h, 40 columns
        CHK e
        mov ax, 40h
        mov es, ax
        cmp byte [es:49h], 9    ; 6: in the BDA
        CHK e
        cmp word [es:4Ah], 40   ; 7
        CHK e
        cmp byte [es:8Ah], 0F6h ; 8: pages 6 and 7 for both
        CHK e
        mov ax, 0580h
        int 10h
        cmp bx, 0606h           ; 9
        CHK e

; ---- the 32K as memory ---------------------------------------------------
        mov ax, 0B800h
        mov es, ax
        xor di, di
        xor ax, ax
        mov cx, 4000h
        repe scasw              ; 10: the mode set cleared it
        CHK e
        mov word [es:0], 1234h
        mov word [es:4000h], 5678h
        cmp word [es:0], 1234h  ; 11: BC00 is not B800 again
        CHK e
        mov word [es:7FFEh], 9ABCh
        mov word [es:3FFEh], 0DEF0h
        cmp word [es:7FFEh], 9ABCh      ; 12
        CHK e
        xor di, di
        mov ax, 5AA5h
        mov cx, 4000h
        rep stosw
        xor di, di
        mov cx, 4000h
        repe scasw              ; 13: REP STOSW over all of it
        CHK e
        mov si, pat
        mov di, 7EA0h           ; line 199: bank 3, row 49
        mov cx, 160
        rep movsb
        mov si, pat
        mov di, 7EA0h
        mov cx, 160
        repe cmpsb              ; 14: REP MOVSB to a line
        CHK e
        cmp word [es:7F40h], 5AA5h      ; 15: and no further
        CHK e
        call clear

; ---- INT 10h's pixels ----------------------------------------------------
        mov al, 0Bh
        xor cx, cx
        xor dx, dx
        call setpix
        cmp byte [es:0], 0B0h   ; 16: the left pixel is the high four bits
        CHK e
        mov al, 0Ch
        mov cx, 1
        xor dx, dx
        call setpix
        cmp byte [es:0], 0BCh   ; 17
        CHK e
        mov al, 7
        mov cx, 319
        mov dx, 199
        call setpix
        cmp byte [es:7F3Fh], 07h        ; 18: the last one
        CHK e
        mov al, 9
        mov cx, 2
        mov dx, 1
        call setpix
        cmp byte [es:2001h], 90h        ; 19: line 1 is the second 8K
        CHK e
        mov al, 0Eh
        mov cx, 10
        mov dx, 6
        call setpix
        cmp byte [es:40A5h], 0E0h       ; 20: line 6 the third's second row
        CHK e
        mov al, 8Fh
        mov cx, 10
        mov dx, 6
        call setpix
        cmp byte [es:40A5h], 10h        ; 21: bit 7: XOR
        CHK e
        mov cx, 10
        mov dx, 6
        call getpix
        cmp al, 1               ; 22: and read
        CHK e
        mov cx, 1
        xor dx, dx
        call getpix
        cmp al, 0Ch             ; 23
        CHK e
        mov cx, 319
        mov dx, 199
        call getpix
        cmp al, 7               ; 24
        CHK e
        mov al, 5
        mov cx, 320
        xor dx, dx
        call setpix
        cmp byte [es:00A0h], 0  ; 25: off the screen: nothing
        CHK e
        mov al, 5
        xor cx, cx
        mov dx, 200
        call setpix
        cmp byte [es:1F40h], 0  ; 26
        CHK e

; ---- the pages -----------------------------------------------------------
        call clear
        mov word [es:0], 6606h          ; pages 6 and 7
        mov word [es:4000h], 7707h
        PAGEREG 0D6h                    ; the CPU has 2 and 3, the screen 6 and 7
        push es
        mov ax, 40h
        mov es, ax
        cmp byte [es:8Ah], 0D6h ; 27: the BIOS's copy
        pop es
        CHK e
        mov ax, 0580h
        int 10h
        cmp bx, 0602h           ; 28
        CHK e
        mov word [es:0], 2202h
        mov word [es:4000h], 3303h
        PAGEREG 0DEh                    ; an odd page: 3 is at B800
        cmp word [es:0], 3303h  ; 29
        CHK e
        mov word [es:2], 3313h
        PAGEREG 0F6h
        cmp word [es:0], 6606h  ; 30: 6 and 7 as they were left
        CHK e
        cmp word [es:4000h], 7707h      ; 31
        CHK e
        mov ax, 0581h           ; the CPU's page, by the BIOS
        mov bl, 2
        int 10h
        cmp word [es:0], 2202h  ; 32
        CHK e
        cmp word [es:4000h], 3303h      ; 33
        CHK e
        cmp word [es:4002h], 3313h      ; 34: what was written at B800 with 3 there
        CHK e
        mov ax, 0580h
        int 10h
        cmp bx, 0602h           ; 35
        CHK e
        mov ax, 0582h           ; the screen's
        mov bh, 4
        int 10h
        mov ax, 0580h
        int 10h
        cmp bx, 0402h           ; 36
        CHK e
        mov ax, 0583h           ; both
        mov bx, 0105h
        int 10h
        mov ax, 0580h
        int 10h
        cmp bx, 0105h           ; 37
        CHK e
        push es
        mov ax, 40h
        mov es, ax
        cmp byte [es:8Ah], 0E9h ; 38: (the two high bits are kept)
        pop es
        CHK e
        xor bx, bx              ; every page its own number, each at B800
.wr:    mov ax, 0581h
        int 10h
        mov al, bl
        or al, 0A0h
        mov [es:100h], al
        not al
        mov [es:3FFFh], al
        inc bx
        cmp bl, 8
        jb .wr
        mov bl, 7               ; 39-46: read back from 7 to 0, an even one
.rd:    mov ax, 0581h           ; with the next behind it
        int 10h
        mov al, bl
        or al, 0A0h
        mov ah, al
        not ah
        cmp [es:100h], al
        jne .rdbad
        cmp [es:3FFFh], ah
        jne .rdbad
        test bl, 1
        jnz .rdodd
        inc al
        dec ah
        cmp [es:4100h], al
        jne .rdbad
        cmp [es:7FFFh], ah
        jmp .rdbad
.rdodd: cmp al, al
.rdbad: CHK e
        dec bl
        jns .rd

; ---- the mode set again --------------------------------------------------
        mov ax, 0583h
        mov bx, 0606h
        int 10h
        mov word [es:0], 0C33Ch
        mov word [es:7F3Eh], 0A55Ah
        mov ax, 0089h           ; bit 7: the screen is kept
        int 10h
        cmp word [es:0], 0C33Ch ; 47
        CHK e
        cmp word [es:7F3Eh], 0A55Ah     ; 48
        CHK e
        mov ax, 0003h
        int 10h
        mov ah, 0Fh
        int 10h
        cmp ax, 5003h           ; 49: text
        CHK e
        push es
        mov ax, 40h
        mov es, ax
        cmp byte [es:8Ah], 3Fh  ; 50: on page 7
        pop es
        CHK e
        mov ax, 0E54h           ; (the teletype, in text)
        mov bx, 0007h
        int 10h
        cmp word [es:0], 0754h  ; 51: and B800 is the text
        CHK e

; ---- the picture ---------------------------------------------------------
        cmp byte [onp], 0
        jne .ports
        mov ax, 0009h
        int 10h
        ARRAY 11h, 0Ch          ; palette register 1, by the port
        mov ax, 1000h           ; and 2, by the BIOS
        mov bx, 0E02h
        int 10h
        jmp .draw
.ports: PAGEREG 0F6h            ; as the BIOS does it: the pages,
        ARRAY 01h, 0Fh          ; the mask, the border, 16 colours,
        ARRAY 02h, 00h
        ARRAY 03h, 14h
        mov dx, 3D8h            ; and 320 graphics, enabled
        mov al, 2Bh
        out dx, al
        PAGEREG 0D2h            ; pages 2 and 3 for the CPU and the screen
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

        mov bx, 60              ; a line of pixels through every screen line
        xor dx, dx
.diag:  mov cx, bx
        mov al, 0Fh
        call setpix
        inc bx
        inc dx
        cmp dx, 200
        jb .diag
        mov byte [es:0], 0F1h           ; the first byte, and the last of
        mov byte [es:1F3Fh], 0F2h       ; each 8K's fifty rows
        mov byte [es:3F3Fh], 0F3h
        mov byte [es:5F3Fh], 0F4h
        mov byte [es:7F3Fh], 0F5h
        mov word [es:20FFh], 0E1E2h     ; a word across two 256s
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

        cmp byte [onp], 0
        je .report
        PAGEREG 0F2h            ; 2 and 3 shown, 6 and 7 the CPU's
        xor di, di
        mov ax, 0FFFFh
        mov cx, 4000h
        rep stosw               ; which must not show
        call tick
        call tick

.report:
        mov ax, [ncase]         ; "tandy: N cases, N bad[: n n n]"
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

; the picture: sixteen bars of twenty pixels, each band of eight lines a
; colour on from the one above; line y is at (y & 3) * 8K + (y >> 2) * 160
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
        mov dx, 16
.bar:   mov al, bl
        and al, 0Fh
        mov ah, al
        mov cl, 4
        shl ah, cl
        or al, ah
        mov cx, 10
        rep stosb
        inc bx
        dec dx
        jnz .bar
        inc bp
        cmp bp, 200
        jb .line
        ret

onp:    db 0
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
msg:    db 'tandy: '
msg_n:  db '000 cases, '
msg_b:  db '000 bad', '$'
num:    db ' 000', '$'
