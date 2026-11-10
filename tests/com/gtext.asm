; gtext.asm - the BIOS's text in the CGA graphics modes (src/svc/gtext.s,
; docs/cga.md). In modes 4 and 6 INT 10h's character services must draw
; into the pixels at B800 and never store text cells there: clear and
; scroll a window (06h/07h, BH the filling byte), write a character
; (09h/0Ah: colour, XOR, the count), read it back (08h), the teletype
; (0Eh: CR, LF, BS, BEL, the wrap, the scroll), the pixel calls (0Ch/0Dh)
; and the columns (0Fh and the BDA: 40 in modes 4 and 5). Every check is
; a case; the failed ones are named at the end.
;
; It ends on a picture in mode 4, or in mode 6 when the command line is
; "6", which the judge compares with the SHR pixels ("video": "cga4",
; "cga6"; tools/cgashr.py): what the services wrote must also be marked
; for the screen.
        org 100h

%macro CHK 1                    ; the case passes under this condition
        pushf
        inc word [ncase]
        popf
        j%+1 %%ok
        call fail
%%ok:
%endmacro

%macro READ 2                   ; AL = the character at row, column
        mov dx, (%1 << 8) | %2
        call readch
%endmacro

%macro WRITE 5                  ; row, column, character, colour, count
        mov dx, (%1 << 8) | %2
        mov al, %3
        mov bl, %4
        mov cx, %5
        call wrch
%endmacro

start:  mov ax, 0B800h
        mov es, ax
        cld

; ---- mode 4: 320x200, 40 columns, two bytes a cell -------------------
        mov ax, 0004h
        int 10h
        mov word [cw], 2
        mov ah, 0Fh
        int 10h
        cmp ax, 2804h           ; 1: 40 columns, mode 4
        CHK e
        push es
        mov ax, 40h
        mov es, ax
        cmp word [es:4Ah], 40   ; 2: and in the BDA
        pop es
        CHK e
        call getcur
        test dx, dx             ; 3: the cursor is home
        CHK e
        call bufsum
        test ax, ax             ; 4: the mode set cleared the screen
        CHK e

        mov ax, 0FFFFh          ; clear the screen as GW-BASIC does
        mov [es:0], ax
        mov [es:0F00h], ax
        mov [es:1F3Eh], ax
        mov [es:2000h], ax
        mov [es:3F3Eh], ax
        call clear
        call bufsum
        test ax, ax             ; 5: no pixel left, and no text cell
        CHK e

        mov ax, 0600h           ; a window filled with BH
        mov bh, 55h
        mov cx, 0101h
        mov dx, 0202h
        int 10h
        cmp word [es:320+2], 5555h      ; 6
        CHK e
        cmp word [es:320+4], 5555h      ; 7
        CHK e
        cmp byte [es:320+1], 0          ; 8
        CHK e
        cmp byte [es:320+6], 0          ; 9
        CHK e
        cmp word [es:2000h+320+2], 5555h        ; 10: the odd field
        CHK e
        cmp word [es:2000h+880+4], 5555h        ; 11: the last line of row 2
        CHK e
        cmp byte [es:960+2], 0          ; 12: row 3
        CHK e
        cmp byte [es:240+2], 0          ; 13: row 0
        CHK e
        call bufsum
        cmp ax, (2*8*2*5555h) & 0FFFFh  ; 14: and nothing else
        CHK e
        call clear

        WRITE 5, 3, 'A', 3, 1   ; write character
        mov dx, 0503h
        call cellsum
        test ax, ax             ; 15: something was drawn
        CHK ne
        push ax
        call bufsum
        pop bx
        cmp ax, bx              ; 16: in that cell alone
        CHK e
        cmp word [es:5*160+3*2], 0      ; 17: (where the text cell would be)
        CHK e
        call getcur
        cmp dx, 0503h           ; 18: the cursor stays
        CHK e
        READ 5, 3
        cmp al, 'A'             ; 19: read character
        CHK e
        WRITE 5, 4, 'A', 1, 1
        mov dx, 0504h
        call cellsum
        test cl, 0AAh           ; 20: colour 1 sets the low bit of a pixel
        CHK z
        test cl, 55h            ; 21
        CHK nz
        READ 5, 4
        cmp al, 'A'             ; 22: a pixel of any colour is a set bit
        CHK e
        WRITE 5, 5, 'A', 2, 1
        mov dx, 0505h
        call cellsum
        test cl, 55h            ; 23: colour 2 the high bit
        CHK z
        test cl, 0AAh           ; 24
        CHK nz
        WRITE 5, 3, 'A', 83h, 1 ; XOR: 3 over 3 is nothing
        mov dx, 0503h
        call cellsum
        test ax, ax             ; 25
        CHK e
        READ 5, 3
        test al, al             ; 26: and no character
        CHK e
        WRITE 5, 4, 'A', 82h, 1 ; 2 over 1 is 3
        mov dx, 0504h
        call cellsum
        mov al, cl
        shr al, 1
        xor al, cl
        test al, 55h            ; 27: both bits of every pixel alike
        CHK z
        test cl, cl             ; 28
        CHK nz

        WRITE 7, 38, 'B', 2, 5  ; the count: the run ends with its row
        READ 7, 38
        cmp al, 'B'             ; 29
        CHK e
        READ 7, 39
        cmp al, 'B'             ; 30
        CHK e
        READ 8, 0
        test al, al             ; 31
        CHK e
        mov dx, 0700h
        call rowsum
        push ax
        mov dx, 0726h
        call cellsum
        pop bx
        shl ax, 1
        cmp ax, bx              ; 32: two cells in row 7
        CHK e

        mov dx, 0900h           ; 0Ah draws as 09h does
        call setcur
        mov ax, 0A43h
        mov bx, 0001h
        mov cx, 2
        int 10h
        READ 9, 0
        cmp al, 'C'             ; 33
        CHK e
        READ 9, 1
        cmp al, 'C'             ; 34
        CHK e
        READ 9, 2
        test al, al             ; 35
        CHK e

        mov dx, 0A00h           ; the teletype
        call setcur
        mov ax, 0E48h
        mov bx, 0002h
        int 10h
        mov ax, 0E69h
        mov bx, 0002h
        int 10h
        call getcur
        cmp dx, 0A02h           ; 36: the cursor moved on
        CHK e
        READ 10, 0
        cmp al, 'H'             ; 37
        CHK e
        READ 10, 1
        cmp al, 'i'             ; 38
        CHK e
        mov dx, 0A00h
        call cellsum
        test cl, 55h            ; 39: in BL's colour
        CHK z
        test cl, 0AAh           ; 40
        CHK nz
        mov dx, 0A05h
        call setcur
        mov al, 0Dh
        call tty
        call getcur
        cmp dx, 0A00h           ; 41: CR
        CHK e
        mov al, 08h
        call tty
        call getcur
        cmp dx, 0A00h           ; 42: BS at the left edge
        CHK e
        mov al, 0Ah
        call tty
        call getcur
        cmp dx, 0B00h           ; 43: LF
        CHK e
        mov dx, 0C27h
        call setcur
        mov al, 'X'
        call tty
        call getcur
        cmp dx, 0D00h           ; 44: the wrap after column 39
        CHK e
        READ 12, 39
        cmp al, 'X'             ; 45
        CHK e
        mov dx, 0D03h
        call setcur
        mov al, 07h
        call tty
        call getcur
        cmp dx, 0D03h           ; 46: BEL
        CHK e
        mov al, 08h
        call tty
        call getcur
        cmp dx, 0D02h           ; 47: BS
        CHK e

        mov dx, 1800h           ; LF on the last row: the screen moves up
        call setcur
        mov al, 'Z'
        call tty
        mov al, 0Ah
        call tty
        call getcur
        cmp dx, 1801h           ; 48
        CHK e
        READ 23, 0
        cmp al, 'Z'             ; 49
        CHK e
        READ 4, 4
        cmp al, 'A'             ; 50: all of it
        CHK e
        READ 5, 4
        test al, al             ; 51
        CHK e
        mov dx, 1800h
        call rowsum
        test ax, ax             ; 52: the new row is empty
        CHK e
        mov dx, 1827h           ; and the wrap at the last cell
        call setcur
        mov al, 'W'
        call tty
        call getcur
        cmp dx, 1800h           ; 53
        CHK e
        READ 23, 39
        cmp al, 'W'             ; 54
        CHK e
        READ 22, 0
        cmp al, 'Z'             ; 55
        CHK e

        mov ax, 0601h           ; scroll up, the whole screen
        mov bh, 0
        xor cx, cx
        mov dx, 184Fh
        int 10h
        READ 21, 0
        cmp al, 'Z'             ; 56
        CHK e
        READ 22, 39
        cmp al, 'W'             ; 57
        CHK e
        mov ax, 0702h           ; scroll down two rows in rows 20-24
        mov bh, 0AAh
        mov cx, 1400h
        mov dx, 1827h
        int 10h
        READ 23, 0
        cmp al, 'Z'             ; 58
        CHK e
        READ 24, 39
        cmp al, 'W'             ; 59
        CHK e
        cmp word [es:20*320], 0AAAAh            ; 60: the freed rows are BH
        CHK e
        cmp word [es:2000h+21*320+318], 0AAAAh  ; 61
        CHK e
        cmp word [es:22*320], 0                 ; 62: (old row 20)
        CHK e
        cmp word [es:2000h+19*320+318], 0       ; 63: above the window
        CHK e

        call clear              ; a window narrower than the screen
        WRITE 2, 1, 'Q', 3, 1
        WRITE 2, 0, 'R', 3, 1
        WRITE 2, 3, 'S', 3, 1
        mov ax, 0601h
        mov bh, 0
        mov cx, 0101h
        mov dx, 0202h
        int 10h
        READ 1, 1
        cmp al, 'Q'             ; 64
        CHK e
        READ 2, 1
        test al, al             ; 65
        CHK e
        READ 2, 0
        cmp al, 'R'             ; 66: left of it
        CHK e
        READ 2, 3
        cmp al, 'S'             ; 67: right of it
        CHK e
        mov ax, 0701h
        mov bh, 0
        mov cx, 0101h
        mov dx, 0202h
        int 10h
        READ 2, 1
        cmp al, 'Q'             ; 68
        CHK e
        READ 1, 1
        test al, al             ; 69
        CHK e

        call clear              ; the pixel calls
        mov ax, 0C02h
        mov cx, 319
        mov dx, 199
        call pixel
        cmp byte [es:2000h+99*80+79], 02h       ; 70
        CHK e
        mov ah, 0Dh
        mov cx, 319
        mov dx, 199
        call pixel
        cmp al, 2               ; 71
        CHK e
        mov ax, 0C01h
        xor cx, cx
        xor dx, dx
        call pixel
        cmp byte [es:0], 40h    ; 72
        CHK e
        mov ax, 0C83h           ; XOR
        xor cx, cx
        xor dx, dx
        call pixel
        cmp byte [es:0], 80h    ; 73
        CHK e
        mov ah, 0Dh
        xor cx, cx
        xor dx, dx
        call pixel
        cmp al, 2               ; 74
        CHK e
        mov ax, 0C03h
        mov cx, 5
        mov dx, 1
        call pixel
        cmp byte [es:2000h+1], 30h      ; 75
        CHK e
        mov ax, 0C03h           ; off the screen
        mov cx, 320
        xor dx, dx
        call pixel
        mov ax, 0C03h
        xor cx, cx
        mov dx, 200
        call pixel
        call bufsum
        cmp ax, 0200h+0080h+3000h       ; 76
        CHK e
        mov ah, 0Dh
        mov cx, 6
        mov dx, 1
        call pixel
        test al, al             ; 77
        CHK e

        mov ax, 0005h           ; mode 5 is mode 4 without the colour burst
        int 10h
        mov ah, 0Fh
        int 10h
        cmp ax, 2805h           ; 78
        CHK e

; ---- mode 6: 640x200, 80 columns, a byte a cell -----------------------
        mov ax, 0006h
        int 10h
        mov word [cw], 1
        mov ah, 0Fh
        int 10h
        cmp ax, 5006h           ; 79
        CHK e
        push es
        mov ax, 40h
        mov es, ax
        cmp word [es:4Ah], 80   ; 80
        pop es
        CHK e
        call bufsum
        test ax, ax             ; 81
        CHK e
        WRITE 5, 3, 'A', 1, 1
        mov dx, 0503h
        call cellsum
        test ax, ax             ; 82
        CHK ne
        push ax
        call bufsum
        pop bx
        cmp ax, bx              ; 83: eight bytes at row*320 + column
        CHK e
        READ 5, 3
        cmp al, 'A'             ; 84
        CHK e
        WRITE 5, 3, 'A', 81h, 1
        call bufsum
        test ax, ax             ; 85: XOR
        CHK e
        WRITE 3, 78, 'M', 1, 9
        READ 3, 79
        cmp al, 'M'             ; 86: column 79
        CHK e
        READ 4, 0
        test al, al             ; 87
        CHK e
        mov dx, 184Fh           ; the teletype at the last cell
        call setcur
        mov al, 'k'
        call tty
        call getcur
        cmp dx, 1800h           ; 88
        CHK e
        READ 23, 79
        cmp al, 'k'             ; 89
        CHK e
        READ 2, 78
        cmp al, 'M'             ; 90
        CHK e
        mov dx, 1800h
        call rowsum
        test ax, ax             ; 91
        CHK e
        mov ax, 0601h           ; scroll up, the new row all BH
        mov bh, 0FFh
        xor cx, cx
        mov dx, 184Fh
        int 10h
        cmp word [es:24*320], 0FFFFh            ; 92
        CHK e
        cmp word [es:2000h+24*320+318], 0FFFFh  ; 93
        CHK e
        READ 22, 79
        cmp al, 'k'             ; 94
        CHK e
        call clear
        call bufsum
        test ax, ax             ; 95
        CHK e
        mov ax, 0C01h
        mov cx, 639
        mov dx, 199
        call pixel
        cmp byte [es:2000h+99*80+79], 01h       ; 96
        CHK e
        mov ah, 0Dh
        mov cx, 639
        mov dx, 199
        call pixel
        cmp al, 1               ; 97
        CHK e
        mov ax, 0C01h
        mov cx, 8
        mov dx, 2
        call pixel
        cmp byte [es:80+1], 80h ; 98
        CHK e
        mov ax, 0C81h           ; XOR
        mov cx, 639
        mov dx, 199
        call pixel
        mov ah, 0Dh
        mov cx, 639
        mov dx, 199
        call pixel
        test al, al             ; 99
        CHK e

; ---- mode 3: the same calls still store cells -------------------------
        mov ax, 0003h
        int 10h
        mov ah, 0Fh
        int 10h
        cmp ax, 5003h           ; 100
        CHK e
        WRITE 0, 0, 'A', 1Eh, 2
        cmp word [es:0], 1E41h  ; 101
        CHK e
        cmp word [es:2], 1E41h  ; 102
        CHK e
        mov dx, 0001h
        call setcur
        mov ah, 08h
        mov bh, 0
        int 10h
        cmp ax, 1E41h           ; 103
        CHK e

; ---- the picture the judge looks at ------------------------------------
        mov ax, 0004h
        mov word [cw], 2
        mov word [cols], 40
        cmp byte [80h], 2
        jb .mode
        cmp byte [82h], '6'
        jne .mode
        mov ax, 0006h
        mov word [cw], 1
        mov word [cols], 80
.mode:  int 10h
        mov dx, 0200h
        call setcur
        mov bl, 1               ; three lines by the teletype, a colour each
.line:  mov si, text
.ch:    lodsb
        test al, al
        jz .eol
        mov ah, 0Eh
        int 10h
        jmp .ch
.eol:   inc bl
        cmp bl, 4
        jb .line
        xor di, di              ; a row of every sort of character, by 09h
.set:   mov dx, di
        mov dh, 5
        mov ax, di
        add al, 0B0h
        mov bx, di
        and bl, 3
        mov cx, 1
        call wrch
        inc di
        cmp di, [cols]
        jb .set
        WRITE 7, 2, 0DBh, 2, 100        ; a run to the end of its row
        WRITE 7, 4, 'x', 83h, 3 ; and XOR over it
        xor di, di              ; a diagonal, pixel by pixel
.diag:  mov ax, di
        shr ax, 1
        shr ax, 1
        shr ax, 1
        and al, 3
        or al, 1
        mov ah, 0Ch
        mov cx, di
        add cx, 100
        mov dx, di
        call pixel
        inc di
        cmp di, 200
        jb .diag
        mov ax, 0600h           ; a window filled with a pattern
        mov bh, 1Bh
        mov cx, 0A14h
        mov dx, 0C24h
        int 10h
        mov ax, 0701h           ; and part of the picture moved down
        mov bh, 0
        mov cx, 0500h
        mov dx, 0A0Fh
        int 10h
        mov dx, 1800h           ; the last row, and two rows up
        call setcur
        mov si, text
.ch2:   lodsb
        test al, al
        jz .eol2
        mov ah, 0Eh
        mov bl, 3
        int 10h
        jmp .ch2
.eol2:
        mov ax, [ncase]         ; "gtext: N cases, N bad[: n n n]"
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
.done:  mov dx, crlf
        mov ah, 9
        int 21h
        mov ax, 4C00h
        cmp word [nbad], 0
        je .exit
        inc ax
.exit:  int 21h

; ---- helpers -----------------------------------------------------------
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

wrch:   push ax                 ; AL, BL, CX at DH, DL
        push bx
        call setcur
        pop bx
        pop ax
        mov ah, 09h
        mov bh, 0
        int 10h
        ret

tty:    mov ah, 0Eh             ; AL, in colour 3
        mov bx, 0003h
        int 10h
        ret

pixel:  mov bh, 0               ; AH = 0Ch or 0Dh, the rest as set
        int 10h
        ret

clear:  mov ax, 0600h           ; the screen, as GW-BASIC clears it
        mov bh, 0
        xor cx, cx
        mov dx, 184Fh
        int 10h
        ret

bufsum: push si                 ; AX = the sum of both fields' 8000 words
        push cx
        push bx
        xor bx, bx
        xor si, si
        call .field
        mov si, 2000h
        call .field
        mov ax, bx
        pop bx
        pop cx
        pop si
        ret
.field: mov cx, 4000
.b:     es lodsw
        add bx, ax
        loop .b
        ret

rowsum: push si                 ; AX = the sum of row DH's 320 words
        push cx
        push bx
        mov al, dh
        mov ah, 0
        mov bx, 320
        push dx
        mul bx
        pop dx
        mov si, ax
        xor bx, bx
        push si
        call .half
        pop si
        add si, 2000h
        call .half
        mov ax, bx
        pop bx
        pop cx
        pop si
        ret
.half:  mov cx, 160
.b:     es lodsw
        add bx, ax
        loop .b
        ret

cellsum:                        ; AX = the sum of the cell at DH, DL, as
        push si                 ; the words bufsum adds; CL = its bytes ORed
        push bx
        push dx
        mov al, dh
        mov ah, 0
        mov bx, 320
        push dx
        mul bx
        pop dx
        mov si, ax
        mov al, dl
        mov ah, 0
        mul word [cw]
        add si, ax
        xor bx, bx
        xor cx, cx
        push si
        call .half
        pop si
        add si, 2000h
        call .half
        mov ax, bx
        pop dx
        pop bx
        pop si
        ret
.half:  mov ch, 4               ; four lines of a field
.line:  mov ax, [es:si]
        cmp word [cw], 2
        je .add
        mov ah, 0               ; one byte: where it is in its word
        test si, 1
        jz .add
        xchg al, ah
.add:   add bx, ax
        or cl, al
        or cl, ah
        add si, 80
        dec ch
        jnz .line
        ret

cw:     dw 2                    ; bytes a cell
cols:   dw 40
ncase:  dw 0
nbad:   dw 0
badlist: times 12 dw 0
text:   db 'XT/GS draws text in graphics.', 13, 10, 0
msg:    db 'gtext: '
msg_n:  db '000 cases, '
msg_b:  db '000 bad', '$'
num:    db ' 000', '$'
crlf:   db 13, 10, '$'
