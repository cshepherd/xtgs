; egaw.asm - mode 0Dh as a window on a wider buffer (docs/ega.md): the
; 6845's offset register makes a line of the planes 48 bytes, its start
; address puts the screen in the middle of them and the attribute
; controller pans it by pixels, which is how a game scrolls. The judge
; ("video": "ega") compares the SHR with the planes through those three.
;   no argument   48 bytes a line, from 3604h, panned 3 pixels
;   W             48 bytes a line, from FE00h: the screen goes round the
;                 planes' end
;   P             40 bytes a line, from 0100h, panned 5
;   E             48 bytes a line, from 0200h, panned 4: an even number, which
;                 XT/GS draws as whole bytes of the SHR and no shift
; After the picture has been drawn once, bytes are written where the
; lines of 40 bytes never were (past the 8000th), singly and by REP STOSB,
; and before it: stale pixels there are what the judge finds.
        cpu 8086
        org 100h

        mov dx, msg
        mov ah, 09h
        int 21h
        mov al, [82h]
        and al, 0DFh
        cmp al, 'W'
        jne .nw
        mov word [start], 0FE00h
        mov byte [pan], 0
.nw:    cmp al, 'P'
        jne .np
        mov word [start], 0100h
        mov byte [pan], 5
        mov byte [offs], 20
.np:    cmp al, 'E'
        jne .ne
        mov word [start], 0200h
        mov byte [pan], 4
.ne:    mov ax, 000Dh
        int 10h
        mov ax, 0A000h
        mov es, ax

        mov bl, 1               ; each plane its own bytes, from a buffer
        mov bh, 0
.plane: mov dx, 3C4h
        mov al, 2
        mov ah, bl
        out dx, ax
        mov di, buf
        mov cx, 9700
        xor si, si
.fill:  mov ax, si              ; a byte from its place and its plane
        mov dl, ah
        add al, dl
        add al, dl
        mov dh, bh
        xor al, dh
        ror al, 1
        add al, bh
        mov [di], al
        inc di
        inc si
        loop .fill
        mov si, buf
        mov di, [start]
        mov cx, 9700
        cld
        rep movsb
        inc bh
        shl bl, 1
        cmp bl, 10h
        jne .plane
        mov dx, 3C4h
        mov ax, 0F02h
        out dx, ax

        mov dx, 3D4h            ; the offset register, the start address
        mov al, 13h
        mov ah, [offs]
        out dx, ax
        mov al, 0Ch
        mov ah, [start+1]
        out dx, ax
        mov al, 0Dh
        mov ah, [start]
        out dx, ax
        mov dx, 3DAh            ; and the panning
        in al, dx
        mov dx, 3C0h
        mov al, 33h
        out dx, al
        mov al, [pan]
        out dx, al

        mov cx, 4               ; drawn
        call ticks
        mov di, [start]         ; then written: a byte near the top,
        add di, 100
        mov byte [es:di], 5Ah
        mov di, [start]         ; one past the 8000th
        add di, 9000
        mov byte [es:di], 0A5h
        mov di, [start]         ; and a run there
        add di, 8500
        mov al, 3Ch
        mov cx, 100
        rep stosb
        mov cx, 4
        call ticks
        mov ax, 4C00h
        int 21h

ticks:  push es
        mov ax, 40h
        mov es, ax
.n:     mov ax, [es:6Ch]
.w:     cmp ax, [es:6Ch]
        je .w
        loop .n
        pop es
        ret

msg:    db "egaw", 13, 10, "$"
start:  dw 3604h
pan:    db 3
offs:   db 24
buf:
