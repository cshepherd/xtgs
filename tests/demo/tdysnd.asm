; tdysnd.asm - TDYSND.COM: a Tandy 1000's three voices and its noise on
; XT/GS (docs/tandy.md, docs/sound.md; XTGS.CMD's line VIDEO=TANDY).
; "Frere Jacques" as the round it is: the three tone generators of the
; chip at port C0h come in two bars apart (the third an octave up) and
; each sings it twice, every note struck and let fall by the attenuation
; register, with the noise generator ticking the beat. The BIOS's count
; at 0040:006C keeps the time, an eighth every three ticks; a key stops it.
; tools/build_freedos.py assembles it onto the FreeDOS folder and floppy.
;       nasm -f bin -o TDYSND.COM tdysnd.asm
        cpu 8086
        org 100h
STEP    equ 3                   ; ticks an eighth
LEN     equ 64                  ; the tune's eighths (a power of two)
TOTAL   equ 32+LEN+LEN          ; the last voice comes in at 32
H       equ 80h                 ; the note before, held

start:  cld
        mov ax, 0F000h          ; a 1000's BIOS: FFh at F000:FFFE, 21h at
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
.tandy: mov dx, title
        mov ah, 09h
        int 21h
        mov ax, 40h
        mov es, ax
        xor bp, bp              ; the eighth
.step:  xor bx, bx              ; the voice
.note:  mov ax, bp
        mov cl, [enter+bx]
        xor ch, ch
        sub ax, cx
        jb .mute                ; not in yet
        cmp ax, LEN+LEN
        jae .mute               ; twice through
        and ax, LEN-1
        mov si, ax
        mov al, [tune+si]
        test al, al
        js .next
        cbw
        mov si, ax
        shl si, 1
        mov dx, [per+si]
        mov cl, [up+bx]
        shr dx, cl
        mov ah, bl              ; 1 vv 0 dddd: the period's low four bits
        mov cl, 5
        shl ah, cl
        mov al, dl
        and al, 0Fh
        or al, ah
        or al, 80h
        out 0C0h, al
        mov ax, dx              ; 0 0 dddddd: its high six
        mov cl, 4
        shr ax, cl
        out 0C0h, al
        mov byte [age+bx], 0
        jmp short .next
.mute:  mov byte [age+bx], H
.next:  inc bx
        cmp bx, 3
        jb .note
        xor di, di              ; the tick of this eighth
.tick:  xor bx, bx
.env:   mov al, [age+bx]        ; 1 vv 1 aaaa: 2 dB more each tick, five times
        test al, al
        js .off
        inc byte [age+bx]
        cmp al, 5
        jbe .fall
        mov al, 5
.fall:  add al, [soft+bx]
        jmp short .att
.off:   mov al, 0Fh
.att:   mov ah, bl
        mov cl, 5
        shl ah, cl
        or al, ah
        or al, 90h
        out 0C0h, al
        inc bx
        cmp bx, 3
        jb .env
        mov al, 0FFh            ; the noise: a tick long on each quarter
        test di, di
        jnz .quiet
        test bp, 1
        jnz .quiet
        mov al, 0E4h            ; white, 6991 shifts a second
        out 0C0h, al
        mov al, 0F7h
.quiet: out 0C0h, al
        mov dx, [es:6Ch]
.wait:  mov ah, 1
        int 16h
        jnz .key
        cmp dx, [es:6Ch]
        je .wait
        inc di
        cmp di, STEP
        jb .tick
        inc bp
        cmp bp, TOTAL
        jb .step
        jmp short .end
.key:   xor ah, ah
        int 16h
.end:   mov al, 9Fh             ; all four silent
.hush:  out 0C0h, al
        add al, 20h
        jc .out
        jmp .hush
.out:   mov ax, 4C00h
        int 21h

enter:  db 0, 16, 32            ; the eighth each voice comes in at
up:     db 0, 0, 1              ; octaves up
soft:   db 2, 2, 4              ; attenuation at the note's start
age:    db H, H, H              ; ticks since it
; periods, 3,579,545 / 32f: G3 C4 D4 E4 F4 G4 A4
per:    dw 571, 428, 381, 339, 320, 285, 254
tune:   db 1,H,2,H,3,H,1,H,  1,H,2,H,3,H,1,H
        db 3,H,4,H,5,H,H,H,  3,H,4,H,5,H,H,H
        db 5,6,5,4,3,H,1,H,  5,6,5,4,3,H,1,H
        db 1,H,0,H,1,H,H,H,  1,H,0,H,1,H,H,H
title:  db "Frere Jacques for three voices and the noise; a key stops it.", 13, 10, "$"
notandy: db "This needs a Tandy 1000: VIDEO=TANDY in XTGS.CMD.", 13, 10, "$"
