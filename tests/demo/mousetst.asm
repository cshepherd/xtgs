; mousetst.asm - MOUSETST.COM: the mouse as the driver's INT 33h gives it
; (docs/mouse.md). Not a test by itself: tools/build_freedos.py assembles it
; for the FreeDOS diskette and folder, and tools/mouse_test.py runs
; MOUSETST L and moves MAME's mouse.
;
;   MOUSETST      the text cursor shown; one line, rewritten at each change
;   MOUSETST L    a new line at each change
;
; A line: where function 03h says the mouse is and its buttons, then what
; the handler (function 0Ch, every event) was last called with: the events
; it has seen since the line before, how many calls, and its CX and DX.
; Any key ends it.
        cpu 8086
        org 100h
        mov al, [82h]
        and al, 0DFh
        cmp al, 'L'
        jne .nolog
        mov byte [logm], 1
.nolog: xor ax, ax
        int 33h
        cmp ax, 0FFFFh
        je .have
        mov dx, none
        mov ah, 9
        int 21h
        mov ax, 4C01h
        int 21h
.have:  mov [nbtn], bx
        mov ax, 0Ch
        mov cx, 1Fh
        mov dx, handler
        push cs
        pop es
        int 33h
        mov ax, 1
        int 33h
        mov word [lx], 0FFFFh
.loop:  mov ah, 1
        int 16h
        jz .look
        jmp .done
.look:  mov ax, 3
        int 33h
        cmp cx, [lx]
        jne .new
        cmp dx, [ly]
        jne .new
        cmp bx, [lb]
        je .loop
.new:   mov [lx], cx
        mov [ly], dx
        mov [lb], bx
        mov ax, 2                       ; (hidden while the line is written)
        int 33h
        mov si, t_x
        call puts
        mov ax, [lx]
        call putn
        mov si, t_y
        call puts
        mov ax, [ly]
        call putn
        mov si, t_b
        call puts
        mov ax, [lb]
        call putn
        mov si, t_ev
        call puts
        cli
        mov ax, [hev]
        mov word [hev], 0
        mov bx, [hn]
        mov cx, [hx]
        mov dx, [hy]
        sti
        push dx
        push cx
        push bx
        call putn
        mov si, t_n
        call puts
        pop ax
        call putn
        mov si, t_hx
        call puts
        pop ax
        call putn
        mov si, t_hy
        call puts
        pop ax
        call putn
        mov si, t_cr
        cmp byte [logm], 0
        je .cr
        mov si, t_nl
.cr:    call puts
        mov ax, 1
        int 33h
        jmp .loop
.done:  mov ah, 0
        int 16h
        xor ax, ax
        int 33h
        mov ax, 4C00h
        int 21h

handler:                                ; far, from the driver: AX the events
        or [cs:hev], ax
        inc word [cs:hn]
        mov [cs:hx], cx
        mov [cs:hy], dx
        retf

puts:   lodsb
        or al, al
        jz .r
        mov ah, 0Eh
        mov bx, 7
        int 10h
        jmp puts
.r:     ret

putn:   mov bx, 10                      ; AX in decimal
        xor cx, cx
.d:     xor dx, dx
        div bx
        push dx
        inc cx
        or ax, ax
        jnz .d
.p:     pop ax
        add al, '0'
        mov ah, 0Eh
        mov bx, 7
        int 10h
        loop .p
        ret

logm    db 0
nbtn    dw 0
lx      dw 0
ly      dw 0
lb      dw 0
hev     dw 0
hn      dw 0
hx      dw 0
hy      dw 0
none    db 'No mouse driver (INT 33h).', 13, 10, '$'
t_x     db 'mouse x=', 0
t_y     db ' y=', 0
t_b     db ' b=', 0
t_ev    db ' handler ev=', 0
t_n     db ' n=', 0
t_hx    db ' x=', 0
t_hy    db ' y=', 0
t_cr    db '    ', 13, 0
t_nl    db 13, 10, 0
