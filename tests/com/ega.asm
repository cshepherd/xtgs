; ega.asm - the EGA's mode 0Dh, 320x200 in 16 colours (src/core/ega.s,
; src/svc/ega.s, docs/ega.md). A byte of A000 is four bytes, one a plane,
; and what a write stores or a read returns is the graphics controller's
; doing. The cases: the mode and what the BIOS says of the card; write
; mode 0 (map mask, set/reset, bit mask, the functions, the rotate), the
; latches through XCHG and OR, write modes 2 and 1, read mode 1; words
; and the addressing forms (ModR/M, the accumulator's own, XLAT); the
; string instructions alone, under REP, backwards, each way between
; memory and the planes; and INT 10h (pixels, characters and the font
; they come from, the teletype, the scroll, the palette, the pages).
; The failed cases are named at the end.
;
; It ends on a picture the judge compares with the SHR pixels and the
; palette ("video": "ega"; tools/egashr.py): on page 0, or on page 1
; with another palette when the command line is "P".
        org 100h

%macro CHK 1                    ; the case passes under this condition
        pushf
        inc word [ncase]
        popf
        j%+1 %%ok
        call fail
%%ok:
%endmacro

%macro GC 2                     ; a graphics controller register <- a value
        mov dx, 3CEh
        mov ax, ((%2) << 8) | (%1)
        out dx, ax
%endmacro

%macro SEQ 2                    ; a sequencer register
        mov dx, 3C4h
        mov ax, ((%2) << 8) | (%1)
        out dx, ax
%endmacro

%macro PL 5                     ; the byte at an offset is this in planes 0-3
        mov di, %1
        call planes
        mov ax, [got]
        xor ax, (%2) | ((%3) << 8)
        mov bx, [got+2]
        xor bx, (%4) | ((%5) << 8)
        or ax, bx
        CHK z
%endmacro

%macro PLA 2                    ; ... the same in all four
        PL %1, %2, %2, %2, %2
%endmacro

start:  cld
        cmp byte [80h], 0       ; "P": end on page 1
        je .noarg
        mov al, [82h]
        and al, 0DFh
        cmp al, 'P'
        jne .noarg
        mov byte [onp], 1
.noarg:
        mov ah, 12h
        mov bl, 10h
        int 10h
        cmp bx, 0003h           ; 1: an EGA: colour, 256K
        CHK e
        mov ax, 000Dh
        int 10h
        mov ax, 0A000h
        mov es, ax
        mov ah, 0Fh
        int 10h
        cmp ax, 280Dh           ; 2: mode 0Dh, 40 columns
        CHK e
        cmp bh, 0               ; 3: page 0
        CHK e
        push es
        mov ax, 40h
        mov es, ax
        cmp word [es:4Ah], 40   ; 4: and in the BDA
        pop es
        CHK e
        push es
        mov ax, 40h
        mov es, ax
        cmp byte [es:49h], 0Dh  ; 5
        pop es
        CHK e
        PLA 0, 0                ; 6, 7: the mode set cleared the planes
        PLA 7999, 0

; ---- write mode 0 ------------------------------------------------------
        mov byte [es:0], 0FFh
        PLA 0, 0FFh             ; 8: the data in every plane
        SEQ 2, 05h
        mov byte [es:1], 0AAh
        SEQ 2, 0Fh
        PL 1, 0AAh, 0, 0AAh, 0  ; 9: the map mask
        GC 0, 06h
        GC 1, 0Fh
        mov byte [es:2], 0
        PL 2, 0, 0FFh, 0FFh, 0  ; 10: set/reset in every plane
        GC 0, 02h
        GC 1, 03h
        mov byte [es:3], 5Ah
        PL 3, 0, 0FFh, 5Ah, 5Ah ; 11: and in two of them
        GC 1, 0
        mov byte [es:4], 0F0h
        GC 8, 0Fh
        mov al, [es:4]          ; (the latches)
        mov byte [es:4], 0AAh
        GC 8, 0FFh
        PLA 4, 0FAh             ; 12: the bit mask
        mov byte [es:5], 0Fh
        GC 3, 10h
        mov al, [es:5]
        mov byte [es:5], 0A0h
        PLA 5, 0AFh             ; 13: OR
        GC 3, 08h
        mov al, [es:5]
        mov byte [es:5], 0F5h
        PLA 5, 0A5h             ; 14: AND
        GC 3, 18h
        mov al, [es:5]
        mov byte [es:5], 0FFh
        PLA 5, 5Ah              ; 15: XOR
        GC 3, 01h
        mov byte [es:6], 81h
        GC 3, 0
        PLA 6, 0C0h             ; 16: the rotate

        GC 0, 09h               ; the way a program sets pixels: XCHG
        GC 1, 0Fh
        GC 8, 18h
        mov al, 0A5h
        xchg [es:7], al
        cmp al, 0               ; 17: what was there
        CHK e
        GC 0, 06h
        GC 8, 81h
        or byte [es:7], 0       ; ... or OR
        GC 1, 0
        GC 8, 0FFh
        PL 7, 18h, 81h, 81h, 18h        ; 18

; ---- write modes 2 and 1, read mode 1 ----------------------------------
        GC 5, 2
        GC 8, 0F0h
        mov al, [es:8]
        mov byte [es:8], 0Bh
        GC 8, 0FFh
        GC 5, 0
        PL 8, 0F0h, 0F0h, 0, 0F0h       ; 19: the data is a colour
        GC 5, 1
        mov al, [es:8]
        mov [es:9], al
        SEQ 2, 03h
        mov [es:10], al
        SEQ 2, 0Fh
        GC 5, 0
        PL 9, 0F0h, 0F0h, 0, 0F0h       ; 20: the latches
        PL 10, 0F0h, 0F0h, 0, 0         ; 21: under the map mask
        GC 5, 08h
        GC 2, 0Bh
        mov al, [es:8]
        cmp al, 0F0h            ; 22: the pixels of colour 11
        CHK e
        GC 7, 07h
        GC 2, 03h
        mov al, [es:8]
        cmp al, 0F0h            ; 23: of colour 3 or 11
        CHK e
        GC 2, 0
        mov al, [es:8]
        cmp al, 0Fh             ; 24: of colour 0 or 8
        CHK e
        GC 7, 0
        mov al, [es:8]
        cmp al, 0FFh            ; 25: of any
        CHK e
        GC 7, 0Fh
        GC 5, 0

; ---- words and the addressing forms ------------------------------------
        mov word [es:12], 0A55Ah
        PLA 12, 5Ah             ; 26, 27
        PLA 13, 0A5h
        GC 4, 2
        mov ax, [es:12]
        cmp ax, 0A55Ah          ; 28
        CHK e
        GC 4, 0
        or word [es:12], 0101h
        PLA 12, 5Bh             ; 29
        inc byte [es:14]
        inc byte [es:14]
        not byte [es:14]
        PLA 14, 0FDh            ; 30
        test byte [es:14], 02h  ; 31: a read alone
        CHK z
        cmp byte [es:14], 0FDh  ; 32
        CHK e
        push word [es:12]
        pop word [es:16]
        PLA 16, 5Bh             ; 33, 34
        PLA 17, 0A5h
        mov bx, 18
        mov si, 2
        mov di, 20
        mov bp, 20
        mov byte [es:bx], 11h           ; 18
        mov byte [es:bx+si], 22h        ; 20
        mov byte [es:di+1], 33h         ; 21
        mov byte [es:bp+si], 44h        ; 22
        mov byte [es:bx+di+100h], 55h   ; 294
        push ds
        push es
        pop ds
        mov byte [bx+5], 66h            ; 23, by DS
        mov al, [23]                    ; the accumulator's own forms
        mov [24], al
        mov ax, [22]
        mov [25], ax
        mov al, 5
        xlatb                           ; 23 again
        pop ds
        cmp al, 66h             ; 35
        CHK e
        PLA 18, 11h             ; 36-43
        PLA 20, 22h
        PLA 21, 33h
        PLA 22, 44h
        PLA 294, 55h
        PLA 24, 66h
        PLA 25, 44h
        PLA 26, 66h

; ---- the string instructions -------------------------------------------
        mov di, 40
        mov al, 3Ch
        stosb
        cmp di, 41              ; 44
        CHK e
        PLA 40, 3Ch             ; 45
        mov di, 80
        mov cx, 40
        mov al, 0FFh
        rep stosb
        cmp di, 120             ; 46
        CHK e
        test cx, cx             ; 47
        CHK z
        PLA 80, 0FFh            ; 48-50
        PLA 119, 0FFh
        PLA 120, 0
        mov di, 160
        mov cx, 20
        mov ax, 0A5C3h
        rep stosw
        PLA 160, 0C3h           ; 51, 52
        PLA 199, 0A5h
        GC 0, 05h               ; a fill by set/reset
        GC 1, 0Fh
        mov di, 200
        mov cx, 40
        rep stosb
        GC 1, 0
        PL 200, 0FFh, 0, 0FFh, 0        ; 53, 54
        PL 239, 0FFh, 0, 0FFh, 0
        SEQ 2, 08h              ; and one plane's
        mov di, 240
        mov cx, 40
        mov al, 0FFh
        rep stosb
        SEQ 2, 0Fh
        PL 240, 0, 0, 0, 0FFh           ; 55, 56
        PL 279, 0, 0, 0, 0FFh
        mov si, pat             ; memory to the planes
        mov di, 280
        mov cx, 40
        rep movsb
        cmp si, pat+40          ; 57
        CHK e
        PLA 280, 01h            ; 58, 59
        PLA 319, 28h
        GC 5, 1                 ; the planes to the planes, by the latches
        push ds
        push es
        pop ds
        mov si, 200
        mov di, 320
        mov cx, 40
        rep movsb
        mov si, 240
        mov di, 360
        mov cx, 20
        rep movsw
        pop ds
        GC 5, 0
        PL 320, 0FFh, 0, 0FFh, 0        ; 60-63
        PL 359, 0FFh, 0, 0FFh, 0
        PL 360, 0, 0, 0, 0FFh
        PL 399, 0, 0, 0, 0FFh
        GC 4, 2                 ; the planes to memory: the plane read
        mov si, 200
        call toram
        cmp word [buf], 0FFFFh  ; 64, 65
        CHK e
        cmp byte [buf+39], 0FFh
        CHK e
        GC 4, 1
        mov si, 200
        call toram
        cmp word [buf], 0       ; 66, 67
        CHK e
        cmp byte [buf+39], 0
        CHK e
        GC 4, 0
        std                     ; backwards
        mov di, 439
        mov cx, 40
        mov al, 77h
        rep stosb
        cld
        cmp di, 399             ; 68
        CHK e
        PLA 400, 77h            ; 69-71
        PLA 439, 77h
        PL 399, 0, 0, 0, 0FFh
        push ds                 ; LODSB: plane 0, then plane 1
        push es
        pop ds
        mov si, 200
        lodsb
        mov bl, al
        push bx
        GC 4, 1
        pop bx
        lodsb
        mov bh, al
        pop ds
        cmp bx, 00FFh           ; 72
        CHK e
        GC 4, 0
        mov di, 200
        mov al, 0FFh
        mov cx, 40
        repe scasb
        CHK e                   ; 73: forty bytes of plane 0 the same
        cmp di, 240             ; 74
        CHK e
        mov di, 280
        mov si, pat
        mov cx, 40
        repe cmpsb
        CHK e                   ; 75: the pattern is there
        mov di, 280
        mov si, pat+1
        mov cx, 40
        repe cmpsb
        CHK ne                  ; 76: and not one byte on
        push ds                 ; write mode 0, the planes to the planes:
        push es                 ; the plane read goes to all four
        pop ds
        mov si, 200
        mov di, 440
        mov cx, 40
        rep movsb
        GC 4, 3                 ; one MOVSB, plane 3
        mov si, 240
        movsb
        pop ds
        PLA 440, 0FFh           ; 77-79
        PLA 479, 0FFh
        PLA 480, 0FFh

; ---- INT 10h -------------------------------------------------------------
        mov ax, 0C0Ch           ; a pixel
        mov bh, 0
        mov cx, 5
        mov dx, 100
        int 10h
        PL 4000, 0, 0, 04h, 04h         ; 80
        mov ah, 0Dh
        mov bh, 0
        mov cx, 5
        mov dx, 100
        int 10h
        cmp al, 0Ch             ; 81
        CHK e
        mov ax, 0C8Ah           ; XOR
        mov bh, 0
        mov cx, 5
        mov dx, 100
        int 10h
        mov ah, 0Dh
        mov bh, 0
        mov cx, 5
        mov dx, 100
        int 10h
        cmp al, 06h             ; 82
        CHK e

        mov dx, 1403h           ; two characters in colour 14
        call setcur
        mov ax, 0941h
        mov bx, 000Eh
        mov cx, 2
        int 10h
        mov dx, 1404h
        call readch
        cmp al, 'A'             ; 83
        CHK e
        mov ax, 1130h           ; the font they came from
        mov bh, 3
        int 10h
        cmp cx, 8               ; 84
        CHK e
        push ds
        push es
        pop ds
        lea si, [bp+8*'A']
        push cs
        pop es
        mov di, buf
        mov cx, 4
        rep movsw
        pop ds
        mov ax, 0A000h
        mov es, ax
        GC 4, 1                 ; plane 1 is the glyph, plane 0 nothing
        mov si, buf
        mov di, 20*320+3
        mov cx, 8
        xor bx, bx
.gl:    lodsb
        or bh, al
        xor al, [es:di]
        or bl, al
        add di, 40
        loop .gl
        test bl, bl             ; 85
        CHK z
        test bh, bh             ; 86: (and the glyph is not blank)
        CHK nz
        GC 4, 0
        mov di, 20*320+3+80
        cmp byte [es:di], 0     ; 87
        CHK e

        mov dx, 1500h           ; the teletype
        call setcur
        mov al, 'E'
        call tty
        mov al, 'G'
        call tty
        mov al, 'A'
        call tty
        call getcur
        cmp dx, 1503h           ; 88
        CHK e
        mov dx, 1501h
        call readch
        cmp al, 'G'             ; 89
        CHK e

        mov ax, 0601h           ; the screen up a row
        mov bh, 0
        xor cx, cx
        mov dx, 1827h
        int 10h
        mov dx, 1303h
        call readch
        cmp al, 'A'             ; 90
        CHK e
        PL 0, 0FFh, 0, 0FFh, 0  ; 91: what was line 8
        PLA 24*320, 0           ; 92: the last row is clear
        mov ax, 0600h           ; a window filled with colour 4
        mov bh, 04h
        mov cx, 1600h
        mov dx, 1727h
        int 10h
        PL 22*320, 0, 0, 0FFh, 0        ; 93-95
        PL 24*320-1, 0, 0, 0FFh, 0
        PLA 22*320-1, 0
        mov ax, 0701h           ; and three rows of it down one
        mov bh, 0
        mov cx, 1500h
        mov dx, 1727h
        int 10h
        PLA 22*320, 0           ; 96, 97
        PL 23*320, 0, 0, 0FFh, 0

        mov ax, 1000h           ; the palette: by the BIOS
        mov bx, 1401h
        int 10h
        mov dx, 3DAh            ; and by the ports
        in al, dx
        mov dx, 3C0h
        mov al, 02h
        out dx, al
        mov al, 15h
        out dx, al
        mov al, 20h
        out dx, al

        mov ax, 0501h           ; page 1
        int 10h
        mov ah, 0Fh
        int 10h
        cmp bh, 1               ; 98
        CHK e
        mov ax, 0C0Fh           ; a pixel there
        mov bh, 1
        xor cx, cx
        xor dx, dx
        int 10h
        PLA 2000h, 80h          ; 99
        mov ax, 0C0Ah           ; and one on page 0
        mov bh, 0
        mov cx, 319
        mov dx, 199
        int 10h
        PL 7999, 0, 01h, 0, 01h ; 100
        mov ah, 0Dh
        mov bh, 1
        xor cx, cx
        xor dx, dx
        int 10h
        cmp al, 0Fh             ; 101
        CHK e
        mov ah, 02h             ; each page has its cursor, and BH names
        mov bh, 0               ; the page a character goes to
        mov dx, 0A07h
        int 10h
        mov ah, 02h
        mov bh, 1
        mov dx, 0505h
        int 10h
        mov ax, 095Ah           ; a Z on page 0, which is not shown
        mov bx, 000Fh
        mov cx, 1
        int 10h
        mov ah, 08h
        mov bh, 0
        int 10h
        cmp al, 'Z'             ; 102
        CHK e
        mov ah, 08h
        mov bh, 1
        int 10h
        cmp al, 'Z'             ; 103: and not on page 1
        CHK ne
        mov ax, 0E51h           ; the teletype: the page shown
        mov bx, 000Bh
        int 10h
        mov ah, 03h
        mov bh, 1
        int 10h
        cmp dx, 0506h           ; 104
        CHK e
        mov ah, 03h
        mov bh, 0
        int 10h
        cmp dx, 0A07h           ; 105
        CHK e
        push es
        mov ax, 40h
        mov es, ax
        cmp word [es:52h], 0506h        ; 106: the BDA's second cursor
        pop es
        CHK e
        mov dx, 0505h
        mov ah, 02h
        mov bh, 1
        int 10h
        mov ah, 08h
        mov bh, 1
        int 10h
        cmp al, 'Q'             ; 107
        CHK e
        xor bp, bp
        cmp byte [onp], 0
        je .pg0
        mov bp, 2000h           ; "P": the picture goes on page 1
        mov ax, 1002h           ; the bright colours first
        push es
        push cs
        pop es
        mov dx, pal
        int 10h
        pop es
        mov ah, 0Bh             ; and a blue background
        mov bx, 0001h
        int 10h
        jmp .pic
.pg0:   mov ax, 0500h
        int 10h

; ---- the picture: sixteen bands by set/reset, lines 32-95 --------------
.pic:   GC 1, 0Fh
        xor bx, bx
        lea di, [bp+32*40]
.band:  mov dx, 3CEh
        mov al, 0
        mov ah, bl
        out dx, ax
        mov cx, 80
        rep stosw
        inc bx
        cmp bx, 16
        jb .band
        GC 1, 0
; stripes four pixels wide by write mode 2 and the bit mask, lines 104-151
        GC 5, 2
        lea di, [bp+104*40]
        xor bx, bx
.str:   mov dx, 3CEh
        mov ax, 0F008h
        out dx, ax
        mov al, bl
        xchg [es:di], al
        mov dx, 3CEh
        mov ax, 0F08h
        out dx, ax
        mov al, bl
        not al
        xchg [es:di], al
        inc di
        inc bx
        cmp bx, 48*40
        jb .str
        GC 8, 0FFh
        GC 5, 0
; and a line of pixels by the BIOS, line 100
        xor cx, cx
.dots:  mov ah, 0Ch
        mov al, cl
        and al, 0Fh
        mov bh, [onp]
        mov dx, 100
        int 10h
        add cx, 3
        cmp cx, 320
        jb .dots

        mov dx, 1800h
        mov ah, 02h
        mov bh, [onp]
        int 10h
        mov ax, [ncase]         ; "ega: N cases, N bad[: n n n]"
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

planes: push ax                 ; got = the byte at ES:DI in planes 0-3, by
        push dx                 ; the read map a byte at a time; leaves
        push si                 ; plane 0 to be read and that byte latched
        xor si, si
.p:     mov dx, 3CEh
        mov al, 4
        out dx, al
        inc dx
        mov ax, si
        out dx, al
        mov al, [es:di]
        mov [got+si], al
        inc si
        cmp si, 4
        jb .p
        mov dx, 3CFh
        mov al, 0
        out dx, al
        mov al, [es:di]
        pop si
        pop dx
        pop ax
        ret

toram:  push ds                 ; buf = the 40 bytes at A000:SI as read
        push es
        push es
        pop ds
        push cs
        pop es
        mov di, buf
        mov cx, 40
        rep movsb
        pop es
        pop ds
        ret

setcur: mov ah, 02h             ; DH, DL = row, column
        mov bh, 0
        int 10h
        ret

getcur: mov ah, 03h             ; DX = row, column
        mov bh, 0
        int 10h
        ret

readch: call setcur             ; AL = the character at DH, DL
        mov ah, 08h
        mov bh, 0
        int 10h
        ret

tty:    mov ah, 0Eh             ; AL, in colour 10
        mov bx, 000Ah
        int 10h
        ret

onp:    db 0
ncase:  dw 0
nbad:   dw 0
badlist: times 12 dw 0
got:    dd 0
pat:
%assign i 1
%rep 41
        db i
%assign i i+1
%endrep
pal:    db 0, 11h, 12h, 13h, 14h, 15h, 16h, 17h
        db 1, 2, 3, 4, 5, 6, 7, 10h, 0
buf:    times 40 db 0
msg:    db 'ega: '
msg_n:  db '000 cases, '
msg_b:  db '000 bad', '$'
num:    db ' 000', '$'
