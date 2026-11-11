; comtest.asm - COMTEST.COM: COM1 on XT/GS (docs/serial.md), with the line
; looped back on itself (MAME's -modem loopback, or a plug that joins the
; modem port's TxD to its RxD): everything sent must come back. By the
; BIOS (INT 14h), by the 8250's registers polled, a burst that is read
; only after it has all been sent (the receive ring), and by the port's
; interrupt. -DPORT=2 is COM2 (2F8h, IRQ3). A line
; for each case, "ok" or the bytes that were wrong and FAIL. tools/com_test.py judges them.
;       nasm -f bin -o COMTEST.COM comtest.asm
        cpu 8086
        org 100h
%ifndef PORT
%define PORT 1
%endif
%if PORT == 1
BASE    equ 3F8h                ; COM1: IRQ4
%define BASESTR "3F8h"
IRQV    equ 0Ch
IRQM    equ 10h
%else
BASE    equ 2F8h                ; COM2: IRQ3
%define BASESTR "2F8h"
IRQV    equ 0Bh
IRQM    equ 08h
%endif

start:  cld
        mov dx, t_port
        call name
        mov dx, t_bda           ; the BDA lists the port: which is DX for INT 14h
        call name
        xor ax, ax
        mov es, ax
        test byte [es:411h], 0Eh
        jz .f1
        xor bx, bx
.b0:    cmp word [es:400h+bx], BASE
        je .b9
        inc bx
        inc bx
        cmp bx, 8
        jb .b0
        jmp short .f1
.b9:    shr bx, 1
        mov [bport], bx
        call ok
        jmp short .bios
.f1:    call fail

.bios:  mov dx, t_bios          ; INT 14h: set 9600 8N1, send, receive
        call name
        mov ax, 00E3h
        mov dx, [bport]
        int 14h
        mov ax, 0155h
        mov dx, [bport]
        int 14h
        test ah, 80h
        jnz .f2
        mov ah, 02h
        mov dx, [bport]
        int 14h
        test ah, 80h
        jnz .f2
        cmp al, 55h
        jne .f2
        mov ah, 02h             ; nothing more: it times out
        mov dx, [bport]
        int 14h
        test ah, 80h
        jz .f2
        mov ah, 03h
        mov dx, [bport]
        int 14h
        test ah, 20h            ; the transmitter is empty
        jz .f2
        call ok
        jmp short .regs
.f2:    push ax
        mov al, ah
        call hex
        pop ax
        call hex
        call fail

.regs:  mov dx, t_regs          ; the registers read back
        call name
        mov dx, BASE+7
        mov al, 5Ah
        out dx, al
        in al, dx
        cmp al, 5Ah
        jne .f3
        mov dx, BASE+3
        mov al, 83h             ; DLAB
        out dx, al
        mov dx, BASE
        mov al, 0Ch             ; 9600
        out dx, al
        inc dx
        xor al, al
        out dx, al
        dec dx
        in al, dx
        cmp al, 0Ch
        jne .f3
        mov dx, BASE+3
        mov al, 03h
        out dx, al
        in al, dx
        cmp al, 03h
        jne .f3
        mov dx, BASE+1
        xor al, al
        out dx, al
        inc dx
        in al, dx               ; nothing asked for: no interrupt
        cmp al, 01h
        jne .f3
        call ok
        jmp short .poll
.f3:    call hex
        call fail

.poll:  mov dx, t_poll          ; 32 bytes there and back, one at a time
        call name
        mov bl, 20h
.p1:    mov al, bl
        call send
        call recv
        jc .f4
        cmp al, bl
        jne .f4
        inc bl
        cmp bl, 40h
        jb .p1
        call ok
        jmp short .burst
.f4:    pushf
        call hex
        mov al, bl
        call hex
        popf
        jnc .f4b
        mov dl, 'T'
        mov ah, 02h
        int 21h
.f4b:   call fail

.burst: mov dx, t_burst         ; 200 sent before any is read: the ring keeps them
        call name
        xor bl, bl
.b1:    mov al, bl
        call send
        inc bl
        cmp bl, 200
        jb .b1
        mov cx, 6               ; a third of a second for the last to arrive
        call ticks
        xor bl, bl
.b2:    mov dx, BASE+5
        in al, dx
        test al, 01h
        jz .b3
        mov dx, BASE
        in al, dx
        cmp al, bl
        jne .f5
        inc bl
        jmp .b2
.b3:    cmp bl, 200
        jne .f5
        mov dx, BASE+5
        in al, dx
        test al, 02h            ; and no overrun
        jnz .f5
        call ok
        jmp short .irq
.f5:    call hex
        mov al, bl
        call hex
        call fail

.irq:   mov dx, t_irq           ; received data by the port's interrupt
        call name
        mov ax, 3500h+IRQV
        int 21h
        mov [old], bx
        mov [old+2], es
        mov dx, isr
        mov ax, 2500h+IRQV
        int 21h
        in al, 21h
        mov [mask], al
        and al, ~IRQM
        out 21h, al
        mov word [got], 0
        mov word [thre], 0
        mov dx, BASE+4
        mov al, 0Bh             ; DTR, RTS, OUT2
        out dx, al
        mov dx, BASE+1
        mov al, 01h
        out dx, al
        mov bl, 80h
.i1:    mov al, bl
        call send
        inc bl
        cmp bl, 0C0h
        jb .i1
        mov cx, 36              ; two seconds at most
.i2:    cmp word [got], 64
        jae .i3
        push cx
        mov cx, 1
        call ticks
        pop cx
        loop .i2
.i3:    cmp word [got], 64
        jne .f6
        mov si, buf
        mov bl, 80h
.i4:    lodsb
        cmp al, bl
        jne .f6
        inc bl
        cmp bl, 0C0h
        jb .i4
        call ok
        jmp short .thre
.f6:    mov al, [got]
        call hex
        call fail

.thre:  mov dx, t_thre          ; the transmitter-empty interrupt, on being enabled
        call name
        mov dx, BASE+1
        mov al, 02h
        out dx, al
        mov cx, 2
        call ticks
        cmp word [thre], 1
        jne .f7
        mov al, 41h             ; and after a byte goes
        call send
        mov cx, 2
        call ticks
        cmp word [thre], 2
        jne .f7
        call recv               ; (the byte comes back: nothing asked for it)
        call ok
        jmp short .done
.f7:    mov al, [thre]
        call hex
        call fail

.done:  mov dx, BASE+1          ; everything as it was
        xor al, al
        out dx, al
        mov dx, BASE+4
        mov al, 03h
        out dx, al
        mov al, [mask]
        out 21h, al
        push ds
        lds dx, [old]
        mov ax, 2500h+IRQV
        int 21h
        pop ds
        mov dx, t_msr           ; the modem's lines, for the record
        call name
        mov dx, BASE+6
        in al, dx
        call hex
        mov dx, crlf
        mov ah, 09h
        int 21h
        mov ax, 4C00h
        int 21h

; the port's interrupt
isr:    push ax
        push dx
        push bx
        push ds
        push cs
        pop ds
.more:  mov dx, BASE+2
        in al, dx
        cmp al, 04h
        je .rx
        cmp al, 02h
        jne .out
        inc word [thre]
        jmp .more
.rx:    mov dx, BASE
        in al, dx
        mov bx, [got]
        cmp bx, 64
        jae .more
        mov [buf+bx], al
        inc word [got]
        jmp .more
.out:   mov al, 20h
        out 20h, al
        pop ds
        pop bx
        pop dx
        pop ax
        iret

; AL to the line, when the holding register is empty
send:   push ax
        mov dx, BASE+5
.w:     in al, dx
        test al, 20h
        jz .w
        pop ax
        mov dx, BASE
        out dx, al
        ret

; AL from the line, C set if none came in a second
recv:   push cx
        push es
        mov ax, 40h
        mov es, ax
        mov cx, [es:6Ch]
        add cx, 19
.w:     mov dx, BASE+5
        in al, dx
        test al, 01h
        jnz .got
        cmp cx, [es:6Ch]
        jne .w
        pop es
        pop cx
        stc
        ret
.got:   mov dx, BASE
        in al, dx
        pop es
        pop cx
        clc
        ret

; wait CX ticks
ticks:  push es
        push ax
        mov ax, 40h
        mov es, ax
.n:     mov ax, [es:6Ch]
.w:     cmp ax, [es:6Ch]
        je .w
        loop .n
        pop ax
        pop es
        ret

name:   mov ah, 09h
        int 21h
        ret
ok:     mov dx, s_ok
        jmp name
fail:   mov dx, s_fail
        jmp name
hex:    push ax
        mov cl, 4
        shr al, cl
        call .d
        pop ax
        and al, 0Fh
.d:     add al, '0'
        cmp al, '9'
        jbe .p
        add al, 7
.p:     mov dl, al
        mov ah, 02h
        int 21h
        ret

old:    dw 0, 0
mask:   db 0
got:    dw 0
thre:   dw 0
bport:  dw 0
t_port: db "COM", "0"+PORT, " at ", BASESTR, 13, 10, "$"
t_bda:  db "bda: $"
t_bios: db "bios: $"
t_regs: db "registers: $"
t_poll: db "polled: $"
t_burst: db "burst: $"
t_irq:  db "irq: $"
t_thre: db "thre: $"
t_msr:  db "modem status: $"
s_ok:   db "ok", 13, 10, "$"
s_fail: db " FAIL", 13, 10, "$"
crlf:   db 13, 10, "$"
buf:    times 64 db 0
