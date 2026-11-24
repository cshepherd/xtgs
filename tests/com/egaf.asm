; egaf.asm - mode 0Dh shown from one part of the planes while another is
; drawn in, and the two changed over by the 6845's start address, thirty
; times: what a game does that draws each frame off the screen
; (docs/ega.md; src/svc/ega.s, eg_wide and eg_lcmp). XT/GS then draws
; only the lines that are not the same in the two parts, and the lines
; written in the part that was shown since it was last drawn. Each turn
; draws a block where the turn says, a thing that is the same for two
; turns running (so the two parts are alike there again), and one turn
; in three a byte in the part that is on the screen just before it
; leaves it. Some changes have a frame between them and some have not.
; The judge ("video": "ega") compares the SHR with the planes at the
; end: a line that was wrongly left alone shows.
;   no argument   48 bytes a line, the parts at 0604h and 3604h
;   N             40 bytes a line, the parts at 0000h and 2000h
        cpu 8086
        org 100h

        mov dx, msg
        mov ah, 09h
        int 21h
        mov al, [82h]
        and al, 0DFh
        cmp al, 'N'
        jne .wide
        mov word [bufa], 0000h
        mov word [bufb], 2000h
        mov byte [offs], 20
.wide:  mov ax, 000Dh
        int 10h
        mov ax, 0A000h
        mov es, ax
        cld
        mov dx, 3D4h            ; the offset register
        mov al, 13h
        mov ah, [offs]
        out dx, ax
        mov di, [bufa]
        call ground
        mov di, [bufb]
        call ground
        mov bx, [bufa]
        call show
        mov cx, 3
        call ticks

.turn:  inc word [gen]
        mov si, [bufb]          ; the part that is not shown: B on odd turns
        mov bp, [bufa]
        test word [gen], 1
        jnz .h
        xchg si, bp
.h:     mov ax, [gen]           ; this turn's planes
        and al, 7
        inc al
        mov ah, al
        mov al, 2
        mov dx, 3C4h
        out dx, ax
        mov ax, [gen]           ; a block of 12 bytes where the turn says
        mov cx, 397
        mul cx
        mov cx, 9000
        div cx
        mov di, si
        add di, dx
        mov al, [gen]
        or al, 81h
        mov cx, 12
        rep stosb
        mov ax, [gen]           ; 20 bytes that two turns running draw alike
        shr ax, 1
        mov bx, ax
        mov cx, 613
        mul cx
        mov cx, 9000
        div cx
        mov di, si
        add di, dx
        mov al, bl
        or al, 18h
        mov cx, 20
.same:  mov [es:di], al
        inc di
        loop .same
        mov ax, [gen]           ; one turn in three: a byte in the part shown
        mov bl, 3
        div bl
        or ah, ah
        jnz .nosh
        mov ax, [gen]
        mov cx, 211
        mul cx
        mov cx, 9000
        div cx
        mov di, bp
        add di, dx
        mov byte [es:di], 0E7h
.nosh:  mov bx, si              ; and the two change over
        call show
        mov ax, [gen]           ; a frame after two changes in five
        mov bl, 5
        div bl
        cmp ah, 2
        jae .nofr
        mov cx, 1
        call ticks
.nofr:  cmp word [gen], 30
        jb .turn
        mov cx, 3
        call ticks
        mov ax, 4C00h
        int 21h

show:   mov dx, 3D4h            ; the screen from BX
        mov al, 0Ch
        mov ah, bh
        out dx, ax
        mov al, 0Dh
        mov ah, bl
        out dx, ax
        ret

ground: mov bl, 1               ; 9700 bytes from DI: stripes, a plane's own byte
        mov si, stripe          ; (by REP STOSB: a byte at a time through the
.plane: mov dx, 3C4h            ; planes' trap would be most of the test's time)
        mov al, 2
        mov ah, bl
        out dx, ax
        push di
        lodsb
        mov cx, 9700
        rep stosb
        pop di
        shl bl, 1
        cmp bl, 10h
        jne .plane
        ret

ticks:  push es
        mov ax, 40h
        mov es, ax
.n:     mov ax, [es:6Ch]
.w:     cmp ax, [es:6Ch]
        je .w
        loop .n
        pop es
        ret

msg:    db "egaf", 13, 10, "$"
bufa:   dw 0604h
bufb:   dw 3604h
offs:   db 24
gen:    dw 0
stripe: db 55h, 33h, 0Fh, 00h
