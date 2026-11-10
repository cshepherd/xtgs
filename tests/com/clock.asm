; clock.asm - what the PC says the date and time are, every way a program
; can ask: DOS (INT 21h AH=2Ah/2Ch), the real-time clock (INT 1Ah AH=04/02)
; and the BIOS tick count (INT 1Ah AH=00), asked one after the other and
; printed afterwards. Then a wait for the tick count to move on by 20,
; polling it in a loop of eight instructions (which no IRQ0 once got into:
; see irq_chk in src/core/cpu.s), and how many times it was seen to change;
; then the date and time again after ten seconds with interrupts off, in
; which no IRQ0 is taken and most are lost, and four more for the count to
; be put right. tools/clock_test.py holds the lines against the host's
; clock.
;
;   D yyyy mm dd w      DOS date, hex words/bytes; w = weekday, 0 Sunday
;   T hh mm ss cc       DOS time, hex bytes
;   R ccyy mmdd hhmm ss RTC date and time, BCD
;   K hhhhllll f        ticks since midnight, the midnight flag
;   W hhhhllll nn       the ticks after 20 more went by, and the changes seen
;   X                   the ten seconds are over; D, T, R and K follow again
        org 100h
        call report
        mov ah, 0               ; 20 ticks more (a second and a tenth)
        int 1Ah
        mov bx, dx
        mov di, dx
        xor si, si
wloop:  mov ah, 0
        int 1Ah
        cmp dx, di
        je .same
        inc si
        mov di, dx
.same:  mov ax, dx
        sub ax, bx
        cmp ax, 20
        jb wloop
        mov al, 'W'
        call tag
        mov ax, cx
        call hex4
        mov ax, dx
        call hex4
        call space
        mov ax, si
        call hex2
        call crlf

        cli
        mov cx, 10
        call waitsec
        sti
        mov cx, 4
        call waitsec
        mov al, 'X'
        call tag
        call crlf
        call report
        mov ax, 4C00h
        int 21h

waitsec:                        ; until the RTC's seconds have changed CX times
        push cx
        mov ah, 02h
        int 1Ah
        pop cx
        mov bl, dh
.l:     push cx
        mov ah, 02h
        int 1Ah
        pop cx
        cmp dh, bl
        je .l
        mov bl, dh
        loop .l
        ret

report: mov ah, 2Ah
        int 21h
        mov [ddate], cx
        mov [ddate+2], dx
        mov [ddate+4], al
        mov ah, 2Ch
        int 21h
        mov [dtime], cx
        mov [dtime+2], dx
        mov ah, 04h
        int 1Ah
        sbb al, al
        mov [nortc], al
        mov [rdate], cx
        mov [rdate+2], dx
        mov ah, 02h
        int 1Ah
        sbb al, al
        or [nortc], al
        mov [rtime], cx
        mov [rtime+2], dx
        mov ah, 0
        int 1Ah
        mov [tick], dx
        mov [tick+2], cx
        mov [tick+4], al

        mov al, 'D'
        call tag
        mov ax, [ddate]
        call hex4
        call space
        mov al, [ddate+3]
        call hex2
        call space
        mov al, [ddate+2]
        call hex2
        call space
        mov al, [ddate+4]
        call hex2
        call crlf
        mov al, 'T'
        call tag
        mov al, [dtime+1]
        call hex2
        call space
        mov al, [dtime]
        call hex2
        call space
        mov al, [dtime+3]
        call hex2
        call space
        mov al, [dtime+2]
        call hex2
        call crlf
        cmp byte [nortc], 0
        je .rtc
        mov dx, norte
        mov ah, 9
        int 21h
        jmp .tick
.rtc:   mov al, 'R'
        call tag
        mov ax, [rdate]
        call hex4
        call space
        mov ax, [rdate+2]
        call hex4
        call space
        mov ax, [rtime]
        call hex4
        call space
        mov al, [rtime+3]
        call hex2
        call crlf
.tick:  mov al, 'K'
        call tag
        mov ax, [tick+2]
        call hex4
        mov ax, [tick]
        call hex4
        call space
        mov al, [tick+4]
        call hex2
        jmp crlf

tag:    call putc
space:  mov al, ' '
putc:   push ax
        push dx
        mov dl, al
        mov ah, 2
        int 21h
        pop dx
        pop ax
        ret
crlf:   mov al, 13
        call putc
        mov al, 10
        jmp putc
hex4:   push ax
        mov al, ah
        call hex2
        pop ax
hex2:   push ax
        shr al, 1
        shr al, 1
        shr al, 1
        shr al, 1
        call hex1
        pop ax
hex1:   push ax
        and al, 0Fh
        add al, '0'
        cmp al, '9'
        jbe .d
        add al, 7
.d:     call putc
        pop ax
        ret
norte:  db 'R none', 13, 10, '$'
nortc:  db 0
ddate:  times 5 db 0
dtime:  times 4 db 0
rdate:  times 4 db 0
rtime:  times 4 db 0
tick:   times 5 db 0
