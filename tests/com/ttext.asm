; ttext.asm - the BIOS's text in a Tandy 1000's graphics modes
; (src/svc/tandy.s and gtext.s, docs/tandy.md). In modes 08h, 09h and
; 0Ah INT 10h's character services draw the 8x8 font into the pixels of
; the pages the CPU has at B800: twenty columns in mode 08h and forty
; in 09h, a cell four bytes wide (a pixel four bits, the left one the
; high four), and eighty in mode 0Ah, a cell a pair of bytes (the even
; one the low bit of eight pixels' colours, the odd one the high bit).
; Line y is in the 8K bank y & 3 at (y >> 2) * 160, or in mode 08h in
; y & 1 at (y >> 1) * 80. The cases: the columns; clear and scroll a
; window (06h/07h, BH the colour of the freed lines); write a character
; (09h/0Ah: every bit of the colour, XOR, the count) and read it back
; (08h); the teletype (0Eh: CR, LF, BS, BEL, the wrap, the scroll); the
; string (13h); DOS's console. A cell is compared with the font's glyph
; (third_party/font8x8, eleven of them copied below) drawn here by
; ordinary instructions. The failed cases are named at the end.
;
; The mode is 09h, or 08h with the command line "8" and 0Ah with "A".
; It ends on a picture the judge compares with the SHR pixels
; ("video": "tandy9", "tandy8", "tandyA"; tools/tandyshr.py): drawn,
; left for a frame, then written over in places and moved up by the
; teletype, and at the very end three characters more. With "P" (mode 09h) the CPU is given pages 4 and 5 after
; that frame while the screen keeps 6 and 7: what is written then must
; not show.
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

%macro CELL 4                   ; is the cell at row, column that glyph in
        mov dx, (%1 << 8) | %2  ; that colour, on colour 0?
        mov si, %3
        mov bl, %4
        call cellchk
%endmacro

%macro WORDAT 3                 ; AX = the word at line %3 of the cell at
        mov dx, (%1 << 8) | %2  ; row, column
        mov cx, %3
        call cellline
        mov ax, [es:di]
%endmacro

%macro WINDOW 5                 ; INT 10h AX with BH over rows and columns
        mov ax, %1              ; CX to DX
        mov bh, %2
        mov cx, %3
        mov dx, %4
        add dl, %5              ; (a column counted from the right end)
        int 10h
%endmacro

start:  cld
        mov ax, 0B800h
        mov es, ax
        cmp byte [80h], 0
        je .m9
        mov al, [82h]
        cmp al, '8'
        je .m8
        and al, 0DFh
        cmp al, 'A'
        je .mA
        cmp al, 'P'
        jne .m9
        mov byte [onp], 1
        jmp .m9
.m8:    mov byte [mode], 8
        mov word [cols], 20
        mov word [nbank], 2
        mov word [lbytes], 80
        mov byte [shiftb], 1
        mov byte [qrow], 1      ; (the last line of text is two rows of 20)
        jmp .m9
.mA:    mov byte [mode], 0Ah
        mov word [cols], 80
        mov byte [bpc], 2
        mov byte [cmask], 3
        mov word [fw6], 0FF00h
        mov word [fw5], 00FFh
.m9:    mov ax, [cols]
        dec ax
        mov [lastc], al

; ---- the mode ----------------------------------------------------------
        mov ah, 0
        mov al, [mode]
        int 10h
        mov ah, 0Fh
        int 10h
        cmp al, [mode]          ; 1: the mode
        CHK e
        cmp ah, [cols]          ; 2: its columns
        CHK e
        push es
        mov ax, 40h
        mov es, ax
        mov ax, [es:4Ah]
        pop es
        cmp ax, [cols]          ; 3: and in the BDA
        CHK e
        call getcur
        test dx, dx             ; 4: the cursor is home
        CHK e
        call bufsum
        test ax, ax             ; 5: the mode set cleared the screen
        CHK e

; ---- clear and fill ------------------------------------------------------
        mov ax, 0FFFFh
        mov [es:0], ax
        mov [es:1F3Eh], ax
        mov [es:2000h], ax
        mov [es:3F3Eh], ax
        mov word [es:4000h], 0A5A5h
        mov word [es:7F3Eh], 5A5Ah
        call clear
        call bufsum
        test ax, ax             ; 6: no pixel left
        CHK e
        mov ax, [es:4000h]      ; 7: mode 08h is the first 16K and no more;
        mov bx, [es:7F3Eh]      ; the others are all 32K
        cmp byte [mode], 8
        jne .c7
        sub ax, 0A5A5h
        sub bx, 5A5Ah
.c7:    or ax, bx
        CHK z
        xor ax, ax
        mov [es:4000h], ax
        mov [es:7F3Eh], ax

        WINDOW 0600h, 06h, 0101h, 0202h, 0      ; a window filled with BH
        WORDAT 1, 1, 0
        cmp ax, [fw6]           ; 8: its first bytes
        CHK e
        cmp word [es:di-2], 0   ; 9: and the ones before them
        CHK e
        WORDAT 2, 3, 7
        mov bx, [es:di-2]
        cmp bx, [fw6]           ; 10: its last bytes
        CHK e
        test ax, ax             ; 11: and the ones after them
        CHK e
        WORDAT 3, 1, 0
        test ax, ax             ; 12: row 3
        CHK e
        WORDAT 0, 1, 7
        test ax, ax             ; 13: row 0
        CHK e
        call bufsum
        push ax
        mov al, [bpc]           ; two rows of eight lines, two cells of bpc
        mov ah, 0               ; bytes: 16 * bpc words
        mov cl, 4
        shl ax, cl
        mul word [fw6]
        pop bx
        cmp ax, bx              ; 14: and nothing else
        CHK e
        WINDOW 0600h, 0F5h, 0101h, 0202h, 0     ; the colour is BH's low bits
        WORDAT 1, 1, 0
        cmp ax, [fw5]           ; 15
        CHK e
        WORDAT 2, 2, 7
        cmp ax, [fw5]           ; 16
        CHK e
        call clear

; ---- write and read a character ------------------------------------------
        WRITE 5, 3, 'A', 0Fh, 1
        CELL 5, 3, g_A, 0Fh     ; 17: the glyph, every pixel of it
        CHK e
        mov dx, 0503h
        call cellsum
        push ax
        call bufsum
        pop bx
        cmp ax, bx              ; 18: in that cell alone
        CHK e
        call getcur
        cmp dx, 0503h           ; 19: the cursor stays
        CHK e
        READ 5, 3
        cmp al, 'A'             ; 20: read character
        CHK e
        WRITE 5, 4, 'A', 1, 1
        CELL 5, 4, g_A, 1       ; 21: colour 1
        CHK e
        READ 5, 4
        cmp al, 'A'             ; 22: a pixel of any colour is a set bit
        CHK e
        WRITE 5, 5, 'A', 2, 1
        CELL 5, 5, g_A, 2       ; 23: colour 2
        CHK e
        WRITE 5, 6, 'A', 0Eh, 1
        CELL 5, 6, g_A, 0Eh     ; 24: colour 14 (of four colours: 2)
        CHK e
        READ 5, 6
        cmp al, 'A'             ; 25
        CHK e
        WRITE 5, 3, 'A', 8Fh, 1 ; XOR: a colour over itself is nothing
        mov dx, 0503h
        call cellsum
        test ax, ax             ; 26
        CHK e
        READ 5, 3
        test al, al             ; 27: and no character
        CHK e
        WRITE 5, 4, 'A', 86h, 1 ; 6 over 1 is 7
        CELL 5, 4, g_A, 7       ; 28
        CHK e
        WRITE 5, 5, 0DBh, 81h, 1        ; 1 over the 2 of the A, and 1 beside it;
        WRITE 5, 5, 'A', 82h, 1 ; 2 over the A's 3: the whole cell is 1
        CELL 5, 5, g_DB, 1      ; 29
        CHK e
        mov dx, 0607h           ; 0Ah draws as 09h does
        call setcur
        mov ax, 0A00h + 'Q'
        mov bx, 0005h
        mov cx, 1
        int 10h
        CELL 6, 7, g_Q, 5       ; 30
        CHK e
        mov dh, 7               ; a run of a hundred ends with its row
        mov dl, [lastc]
        sub dl, 2
        mov al, 0DBh
        mov bl, 0Fh
        mov cx, 100
        call wrch
        mov dh, 7
        mov dl, [lastc]
        mov si, g_DB
        mov bl, 0Fh
        call cellchk            ; 31: the last column
        CHK e
        mov dh, 7
        mov dl, [lastc]
        sub dl, 2
        mov si, g_DB
        mov bl, 0Fh
        call cellchk            ; 32: the first of the three
        CHK e
        mov dh, 7
        mov dl, [lastc]
        sub dl, 3
        call cellsum
        test ax, ax             ; 33: and not the one before
        CHK e
        mov dh, 8
        call rowsum
        test ax, ax             ; 34: nor the next row
        CHK e
        WRITE 9, 0, 'A', 0Fh, 0 ; a count of none
        mov dx, 0900h
        call cellsum
        test ax, ax             ; 35
        CHK e
        call bufsum
        push ax
        WRITE 25, 0, 'A', 0Fh, 1        ; a row off the screen
        call bufsum
        pop bx
        cmp ax, bx              ; 36: draws nothing
        CHK e

; ---- the teletype ----------------------------------------------------------
        xor dx, dx
        call setcur
        mov al, 'H'
        call tty
        mov al, 'i'
        call tty
        CELL 0, 0, g_H, 0Bh     ; 37
        CHK e
        CELL 0, 1, g_i, 0Bh     ; 38
        CHK e
        call getcur
        cmp dx, 0002h           ; 39: the cursor moved on
        CHK e
        mov al, 0Dh
        call tty
        call getcur
        cmp dx, 0000h           ; 40: CR
        CHK e
        mov al, 0Ah
        call tty
        call getcur
        cmp dx, 0100h           ; 41: LF
        CHK e
        mov al, 08h
        call tty
        call getcur
        cmp dx, 0100h           ; 42: BS at the left edge
        CHK e
        mov al, 'x'
        call tty
        mov al, 07h
        call tty
        call getcur
        cmp dx, 0101h           ; 43: BEL
        CHK e
        mov al, 08h
        call tty
        call getcur
        cmp dx, 0100h           ; 44: BS
        CHK e
        mov dh, 2               ; the last column: the cursor wraps
        mov dl, [lastc]
        call setcur
        mov al, 'W'
        call tty
        call getcur
        cmp dx, 0300h           ; 45
        CHK e
        mov dh, 2
        mov dl, [lastc]
        mov si, g_W
        mov bl, 0Bh
        call cellchk            ; 46
        CHK e
        mov dx, 1800h           ; LF on the last row: the screen moves up
        call setcur
        mov al, 'k'
        call tty
        mov al, 0Ah
        call tty
        call getcur
        cmp dx, 1801h           ; 47
        CHK e
        CELL 23, 0, g_k, 0Bh    ; 48: the k a row up
        CHK e
        mov dh, 24
        call rowsum
        test ax, ax             ; 49: the new row empty
        CHK e
        CELL 0, 0, g_x, 0Bh     ; 50: row 1 is row 0
        CHK e
        mov dh, 1
        mov dl, [lastc]
        mov si, g_W
        mov bl, 0Bh
        call cellchk            ; 51: to its last column
        CHK e
        CELL 4, 6, g_A, 0Eh     ; 52: and row 5 is row 4
        CHK e
        mov dh, 5
        call rowsum
        push ax
        mov dh, 6
        call rowsum
        pop bx
        test bx, bx             ; 53: row 6 (the Q's) is row 5
        CHK ne
        test ax, ax             ; 54: and row 7 (the run) is row 6
        CHK ne
        call clear

; ---- scroll a window -------------------------------------------------------
        WRITE 11, 2, 'Q', 9, 1
        WRITE 11, 6, 'R', 0Ah, 1
        WRITE 10, 3, 'Z', 0Ch, 1
        WRITE 9, 2, 'D', 0Dh, 1
        WRITE 12, 2, 'k', 1, 1
        WINDOW 0601h, 06h, 0A02h, 0C05h, 0      ; rows 10-12, columns 2-5, up
        CELL 10, 2, g_Q, 9      ; 55
        CHK e
        mov dx, 0A03h
        call cellsum
        test ax, ax             ; 56: the Z went off the top
        CHK e
        CELL 11, 2, g_k, 1      ; 57
        CHK e
        WORDAT 12, 2, 0
        cmp ax, [fw6]           ; 58: the freed row is BH
        CHK e
        WORDAT 12, 6, 7
        cmp word [es:di-2], 0   ; 59: to its last byte
        CHK ne
        test ax, ax             ; 60: and not beyond
        CHK e
        WORDAT 12, 2, 0
        cmp word [es:di-2], 0   ; 61: nor before
        CHK e
        CELL 11, 6, g_R, 0Ah    ; 62: outside the window nothing moved
        CHK e
        CELL 9, 2, g_D, 0Dh     ; 63
        CHK e
        WINDOW 0701h, 00h, 0A02h, 0C05h, 0      ; and down
        CELL 11, 2, g_Q, 9      ; 64
        CHK e
        CELL 12, 2, g_k, 1      ; 65
        CHK e
        mov dx, 0A02h
        call cellsum
        mov bx, ax
        mov dx, 0A05h
        call cellsum
        or ax, bx               ; 66: the freed row is colour 0
        CHK z
        CELL 11, 6, g_R, 0Ah    ; 67
        CHK e
        WINDOW 0603h, 0F5h, 0A02h, 0C05h, 0     ; every row of it: cleared
        WORDAT 10, 2, 0
        cmp ax, [fw5]           ; 68
        CHK e
        WORDAT 12, 5, 7
        cmp ax, [fw5]           ; 69
        CHK e
        CELL 11, 6, g_R, 0Ah    ; 70
        CHK e
        mov dl, [lastc]         ; a window past the screen's edges is cut
        dec dl                  ; to them
        mov dh, 20
        mov cx, dx
        WINDOW 0600h, 06h, cx, 1EC8h, 0
        mov dh, 24
        mov dl, [lastc]
        mov cx, 7
        call cellline
        mov bl, [bpc]
        mov bh, 0
        mov ax, [es:di+bx-2]
        cmp ax, [fw6]           ; 71: the screen's last bytes
        CHK e
        mov dh, 20
        mov dl, [lastc]
        dec dl
        mov cx, 0
        call cellline
        mov ax, [es:di]
        cmp ax, [fw6]           ; 72: the window's first
        CHK e
        cmp word [es:di-2], 0   ; 73
        CHK e
        mov dh, 19
        call rowsum
        test ax, ax             ; 74: and the row above it untouched
        CHK e

; ---- the string, and DOS -----------------------------------------------------
        mov ax, 1301h           ; "Hi" at row 14, column 4, the cursor after it
        mov bx, 000Ah
        mov cx, 2
        mov dx, 0E04h
        mov bp, hi
        push es
        push ds
        pop es
        int 10h
        pop es
        CELL 14, 4, g_H, 0Ah    ; 75
        CHK e
        CELL 14, 5, g_i, 0Ah    ; 76
        CHK e
        call getcur
        cmp dx, 0E06h           ; 77
        CHK e
        mov dx, 1000h
        call setcur
        mov dl, 'D'             ; DOS's console draws in colour 7
        mov ah, 2
        int 21h
        CELL 16, 0, g_D, 7      ; 78
        CHK e
        mov dl, 9               ; and a tab is spaces to the stop
        mov ah, 2
        int 21h
        call getcur
        cmp dx, 1008h           ; 79
        CHK e
        READ 16, 0
        cmp al, 'D'             ; 80
        CHK e
        mov ah, 0Dh             ; a pixel of the D
        mov bh, 0
        xor cx, cx
        mov dx, 16*8
        int 10h
        mov ah, 7
        and ah, [cmask]
        cmp al, ah              ; 81
        CHK e
        mov ax, 0C01h           ; and one more in its cell: no character
        mov bh, 0
        mov cx, 3
        mov dx, 16*8+7
        int 10h
        READ 16, 0
        test al, al             ; 82
        CHK e

; ---- the picture ---------------------------------------------------------------
        call clear
        xor di, di              ; a row of every sort of character in
.set:   mov dx, di              ; every colour
        mov dh, 2
        mov ax, di
        add al, 0B0h
        mov bx, di
        inc bl
        mov cx, 1
        call wrch
        inc di
        cmp di, [cols]
        jb .set
        mov dx, 0400h
        call setcur
        mov bl, 0Eh
        call say
        mov bl, 0Dh
        call say
        WRITE 9, 2, 0DBh, 0Ah, 100      ; a run to the end of its row
        WRITE 9, 4, 'x', 8Fh, 3 ; and XOR over it
        xor di, di              ; a diagonal, pixel by pixel
.diag:  mov ax, di
        mov cl, 3
        shr ax, cl
        and al, 0Fh
        or al, 1
        mov ah, 0Ch
        mov bh, 0
        mov cx, di
        add cx, 30
        mov dx, di
        int 10h
        inc di
        cmp di, 120
        jb .diag
        WINDOW 0600h, 06h, 0B05h, 0D0Ch, 0      ; a window of colour 6
        WINDOW 0701h, 03h, 0400h, 0A08h, 0      ; part of the picture moved down
        call tick               ; the frame draws it
        call tick

        cmp byte [onp], 0       ; "P": the CPU has pages 4 and 5 from here,
        je .over                ; the screen 6 and 7
        mov dx, 3DFh
        mov al, 0E6h
        out dx, al
.over:  WRITE 3, 1, 'Q', 0Dh, 3 ; written over in places
        WRITE 9, 6, 'R', 89h, 2
        WINDOW 0601h, 05h, 0C00h, 0E06h, 0
        mov dx, 1800h           ; the last row, and two rows up
        call setcur
        mov bl, 0Bh
        call say
        mov dh, [qrow]          ; (the Q's went up with the rest)
        mov dl, 1
        call readch
        cmp al, 'Q'             ; 83
        CHK e
        mov dx, 1800h           ; and the result moves it all up once more
        call setcur

        mov ax, [ncase]         ; "ttext: N cases, N bad[: n n n]"
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
        call tick               ; (a frame draws what was moved)
        call tick
        WRITE 13, 9, 'Z', 0Eh, 2        ; and characters that nothing moves
        WRITE 20, 15, 'k', 89h, 1       ; afterwards: each must be marked for
        mov dx, 1205h                   ; the screen by itself
        call setcur
        mov al, 'W'
        mov ah, 0Eh
        mov bx, 000Dh
        int 10h
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

tty:    mov ah, 0Eh             ; AL, in colour 11
        mov bx, 000Bh
        int 10h
        ret

say:    mov si, text            ; the line of text by the teletype, in BL
.ch:    lodsb
        test al, al
        jz .end
        mov ah, 0Eh
        mov bh, 0
        int 10h
        jmp .ch
.end:   ret

tick:   mov ah, 0               ; until the BIOS tick count moves
        int 1Ah
        mov si, dx
.l:     mov ah, 0
        int 1Ah
        cmp dx, si
        je .l
        ret

clear:  mov ax, 0600h           ; the whole screen <- colour 0
        mov bh, 0
        xor cx, cx
        mov dx, 184Fh
        int 10h
        ret

lineoff:                        ; AX = a line of the screen -> DI = where
        push ax                 ; it starts at B800
        push bx
        push cx
        push dx
        mov bx, ax
        mov cl, [shiftb]
        shr ax, cl
        mul word [lbytes]
        mov di, ax
        mov ax, [nbank]
        dec ax
        and bx, ax
        mov cl, 13
        shl bx, cl
        add di, bx
        pop dx
        pop cx
        pop bx
        pop ax
        ret

cellline:                       ; DI = where line CX of the cell at DH, DL
        push ax                 ; starts
        mov al, dh
        mov ah, 0
        shl ax, 1
        shl ax, 1
        shl ax, 1
        add ax, cx
        call lineoff
        mov al, dl
        mul byte [bpc]
        add di, ax
        pop ax
        ret

cellchk:                        ; Z when the cell at DH, DL is the glyph at
        push ax                 ; SI in the colour BL on colour 0
        push bx
        push cx
        push si
        push di
        push bp
        and bl, [cmask]
        xor cx, cx
.line:  call cellline
        lodsb
        cmp byte [bpc], 2
        je .pair
        mov ah, al              ; two bits of the glyph a byte
        mov bp, 4
.byte:  xor al, al
        shl ah, 1
        jnc .n1
        mov al, bl
        shl al, 1
        shl al, 1
        shl al, 1
        shl al, 1
.n1:    shl ah, 1
        jnc .n2
        or al, bl
.n2:    cmp [es:di], al
        jne .out
        inc di
        dec bp
        jnz .byte
        jmp .next
.pair:  mov ah, al              ; the glyph's line for each bit of the colour
        test bl, 1
        jnz .p1
        xor al, al
.p1:    test bl, 2
        jnz .p2
        xor ah, ah
.p2:    cmp [es:di], ax
        jne .out
.next:  inc cx
        cmp cx, 8
        jb .line
        xor ax, ax
.out:   pop bp
        pop di
        pop si
        pop cx
        pop bx
        pop ax
        ret

cellsum:                        ; AX = the sum of the words of the cell at
        push bx                 ; DH, DL
        push cx
        push di
        xor bx, bx
        xor cx, cx
.line:  call cellline
        add bx, [es:di]
        cmp byte [bpc], 2
        je .n
        add bx, [es:di+2]
.n:     inc cx
        cmp cx, 8
        jb .line
        mov ax, bx
        pop di
        pop cx
        pop bx
        ret

rowsum: push bx                 ; AX = the sum of row DH's cells
        push dx
        xor bx, bx
        mov dl, 0
.c:     call cellsum
        add bx, ax
        inc dl
        cmp dl, [cols]
        jb .c
        mov ax, bx
        pop dx
        pop bx
        ret

bufsum: push si                 ; AX = the sum of the words of the mode's
        push cx                 ; 8K banks, 8000 bytes of each
        push bx
        push dx
        xor bx, bx
        xor si, si
        mov dx, [nbank]
.bank:  push si
        mov cx, 4000
.b:     es lodsw
        add bx, ax
        loop .b
        pop si
        add si, 2000h
        dec dx
        jnz .bank
        mov ax, bx
        pop dx
        pop bx
        pop cx
        pop si
        ret

mode:   db 9
onp:    db 0
cols:   dw 40
lastc:  db 39
qrow:   db 2
bpc:    db 4                    ; bytes a cell in a line
cmask:  db 0Fh                  ; the bits of a colour that count
nbank:  dw 4                    ; the 8K banks the lines are dealt among,
shiftb: db 2                    ; and the bytes of a line
lbytes: dw 160
fw6:    dw 6666h                ; colours 6 and 5 as a word of pixels
fw5:    dw 5555h
ncase:  dw 0
nbad:   dw 0
badlist: times 12 dw 0
g_A:    db 030h, 078h, 0CCh, 0CCh, 0FCh, 0CCh, 0CCh, 000h
g_H:    db 0CCh, 0CCh, 0CCh, 0FCh, 0CCh, 0CCh, 0CCh, 000h
g_i:    db 030h, 000h, 070h, 030h, 030h, 030h, 078h, 000h
g_W:    db 0C6h, 0C6h, 0C6h, 0D6h, 0FEh, 0EEh, 0C6h, 000h
g_k:    db 0E0h, 060h, 066h, 06Ch, 078h, 06Ch, 0E6h, 000h
g_Q:    db 078h, 0CCh, 0CCh, 0CCh, 0DCh, 078h, 01Ch, 000h
g_R:    db 0FCh, 066h, 066h, 07Ch, 06Ch, 066h, 0E6h, 000h
g_Z:    db 0FEh, 0C6h, 08Ch, 018h, 032h, 066h, 0FEh, 000h
g_D:    db 0F8h, 06Ch, 066h, 066h, 066h, 06Ch, 0F8h, 000h
g_x:    db 000h, 000h, 0C6h, 06Ch, 038h, 06Ch, 0C6h, 000h
g_DB:   db 0FFh, 0FFh, 0FFh, 0FFh, 0FFh, 0FFh, 0FFh, 0FFh
hi:     db 'Hi'
text:   db 'XT/GS draws text on a Tandy.', 13, 10, 0
msg:    db 'ttext: '
msg_n:  db '000 cases, '
msg_b:  db '000 bad', '$'
num:    db ' 000', '$'
crlf:   db 13, 10, '$'
