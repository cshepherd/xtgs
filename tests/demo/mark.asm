; mark.asm - MARK.COM, for tools/control_test.py (make test-control): says
; what the word at F800:0000 is (memory here, where a PC has its ROM: nothing
; uses it) and then makes it BEEFh, or one more if it was not 0. A PC restarted with
; its memory kept (the desk accessory's soft reboot) finds BEEF there, one
; restarted with its memory cleared (the hard reboot) 0000.
        cpu 8086
        org 100h
        mov ax, 0F800h
        mov es, ax
        mov bx, [es:0]
        mov ax, bx              ; 0000 becomes BEEF, anything else one more
        inc ax
        or bx, bx
        jnz .w
        mov ax, 0BEEFh
.w:     mov [es:0], ax
        mov di, hex
        mov cx, 4
.d:     rol bx, 1
        rol bx, 1
        rol bx, 1
        rol bx, 1
        mov al, bl
        and al, 0Fh
        add al, '0'
        cmp al, '9'
        jbe .s
        add al, 7
.s:     mov [di], al            ; (ES is not ours here)
        inc di
        loop .d
        mov dx, msg
        mov ah, 9
        int 21h
        mov ax, 4C00h
        int 21h
msg:    db 'MARK='
hex:    db '0000', 13, 10, '$'
