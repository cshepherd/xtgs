; xmstest.asm - XMSTEST.COM: the XMS driver (docs/xms.md), by its calls.
; Prints "XMS PASS free=NNNN" (KB), "XMS FAIL nn" (the step that failed)
; or "no XMS driver". tools/xms_test.py runs it (make test-xms).
        cpu 8086
        org 0x100

%macro  step 0                          ; one more step done
        inc byte [stepno]
%endmacro
%macro  xms 1
        mov ah, %1
        call far [entry]
%endmacro

start:  mov ax, 0x4300
        int 0x2f
        cmp al, 0x80
        je .have
        mov dx, msg_none
        jmp say
.have:  mov ax, 0x4310
        int 0x2f
        mov [entry], bx
        mov [entry+2], es
        push cs
        pop es

        step                            ; 1: the version is 2.00, no HMA
        xms 0x00
        cmp ax, 0x0200
        jne fail_j
        or dx, dx
        jne fail_j

        step                            ; 2: something is free
        xms 0x08
        or ax, ax
        je fail_j
        mov [free0], dx

        step                            ; 3: two blocks
        mov dx, 64
        xms 0x09
        cmp ax, 1
        jne fail_j
        mov [h1], dx
        mov dx, 100
        xms 0x09
        cmp ax, 1
        jne fail_j
        mov [h2], dx

        step                            ; 4: what is free went down by 164
        xms 0x08
        mov ax, [free0]
        sub ax, dx
        cmp ax, 164
        jne fail_j

        step                            ; 5: 4096 bytes out to the second block at three
        mov word [off], 0               ;    places and back, each time compared
        call round
        jne fail_j
        mov word [off], 61440
        call round
        jne fail_j
        mov word [off], 61440
        mov word [off+2], 0
        jmp skip1
fail_j: jmp fail
skip1:   mov word [off], 0x8000          ; 98304: the block's last 4096
        mov word [off+2], 1
        call round
        jne fail_j
        mov word [off+2], 0

        step                            ; 6: block to block, 32768 bytes from 69632, then
        mov word [mv_len], 0x8000       ;    the piece of that the last round wrote, read back
        mov ax, [h2]
        mov [mv_sh], ax
        mov word [mv_so], 0x1000
        mov word [mv_so+2], 1
        mov ax, [h1]
        mov [mv_dh], ax
        mov word [mv_do], 1024
        mov word [mv_do+2], 0
        call move
        cmp ax, 1
        jne fail_j
        mov word [mv_len], 4096
        mov ax, [h1]
        mov [mv_sh], ax
        mov word [mv_so], 29696         ; 1024 + (98304 - 69632)
        mov word [mv_so+2], 0
        mov word [mv_dh], 0
        mov word [mv_do], buf2
        mov [mv_do+2], cs
        call move
        cmp ax, 1
        jne fail_j
        call compare
        jne fail_j

        step                            ; 7: a move past the block's end is refused (A6h)
        mov word [mv_len], 4096
        mov word [mv_sh], 0
        mov word [mv_so], buf1
        mov [mv_so+2], cs
        mov ax, [h1]
        mov [mv_dh], ax
        mov word [mv_do], 61442         ; 64 KB - 4094
        mov word [mv_do+2], 0
        call move
        or ax, ax
        jne fail_j
        cmp bl, 0xa6
        jne fail_j

        step                            ; 8: and an odd length (A7h), and a handle that is none (A3h)
        mov word [mv_len], 3
        mov word [mv_do], 0
        call move
        or ax, ax
        jne fail_k
        cmp bl, 0xa7
        jne fail_k
        mov word [mv_len], 2
        mov word [mv_sh], 0x7777
        call move
        or ax, ax
        jne fail_k
        cmp bl, 0xa3
        jne fail_k

        step                            ; 9: the block's size, and a larger one
        mov dx, [h2]
        xms 0x0e
        cmp ax, 1
        jne fail_k
        cmp dx, 100
        jne fail_k
        mov dx, [h2]
        mov bx, 120
        xms 0x0f
        cmp ax, 1
        jne fail_k
        mov dx, [h2]
        xms 0x0e
        cmp dx, 120
        jne fail_k
        mov word [off], 0xd000          ; its new end holds bytes too
        mov word [off+2], 1
        call round
        jne fail_k
        jmp on1
fail_k: jmp fail
on1:
        step                            ; 10: locked, it is not freed (ABh); unlocked, it is
        mov dx, [h1]
        xms 0x0c
        cmp ax, 1
        jne fail_k
        cmp dx, 0x11
        jb fail_k
        mov dx, [h1]
        xms 0x0a
        or ax, ax
        jne fail_k
        cmp bl, 0xab
        jne fail_k
        mov dx, [h1]
        xms 0x0d
        cmp ax, 1
        jne fail_k
        mov dx, [h1]
        xms 0x0a
        cmp ax, 1
        jne fail_k
        mov dx, [h1]                    ; and not twice (A2h)
        xms 0x0a
        or ax, ax
        jne fail_k
        cmp bl, 0xa2
        jne fail_k
        mov dx, [h2]
        xms 0x0a
        cmp ax, 1
        jne fail_k

        step                            ; 11: all of it is free again; more than there is, is not had
        xms 0x08
        cmp dx, [free0]
        jne fail_k
        mov dx, 60000
        xms 0x09
        or ax, ax
        jne fail_k
        cmp bl, 0xa0
        jne fail_k

        step                            ; 12: no high memory area, no A20 line, no upper memory
        mov dx, 0xffff
        xms 0x01
        or ax, ax
        jne fail
        cmp bl, 0x90
        jne fail
        xms 0x07
        or ax, ax
        jne fail
        mov dx, 16
        xms 0x10
        or ax, ax
        jne fail

        mov dx, msg_pass
        mov ah, 9
        int 0x21
        mov ax, [free0]
        call decimal
        mov dx, msg_nl
say:    mov ah, 9
        int 0x21
        mov ax, 0x4c00
        int 0x21

fail:   mov dx, msg_fail
        mov ah, 9
        int 0x21
        mov al, [stepno]
        xor ah, ah
        call decimal
        mov dx, msg_nl
        mov ah, 9
        int 0x21
        mov ax, 0x4c01
        int 0x21

; round - buf1 filled anew, moved to the second block at [off], moved back
; to buf2, compared. ZF set when the same.
round:  inc byte [seed]
        mov al, [seed]
        mov di, buf1
        mov cx, 4096
.f:     stosb
        add al, 7
        loop .f
        mov word [mv_len], 4096
        mov word [mv_len+2], 0
        mov word [mv_sh], 0
        mov word [mv_so], buf1
        mov [mv_so+2], cs
        mov ax, [h2]
        mov [mv_dh], ax
        mov ax, [off]
        mov [mv_do], ax
        mov ax, [off+2]
        mov [mv_do+2], ax
        call move
        cmp ax, 1
        jne rout
        mov di, buf2
        mov cx, 2048
        xor ax, ax
        rep stosw
        mov ax, [h2]
        mov [mv_sh], ax
        mov ax, [off]
        mov [mv_so], ax
        mov ax, [off+2]
        mov [mv_so+2], ax
        mov word [mv_dh], 0
        mov word [mv_do], buf2
        mov [mv_do+2], cs
        call move
        cmp ax, 1
        jne rout
compare:
        mov si, buf1
        mov di, buf2
        mov cx, 4096
        repe cmpsb
rout:   ret

move:   mov si, mv_len
        xms 0x0b
        ret

decimal:                                ; AX in decimal
        mov bx, 10
        xor cx, cx
.d:     xor dx, dx
        div bx
        push dx
        inc cx
        or ax, ax
        jnz .d
.p:     pop dx
        add dl, '0'
        mov ah, 2
        int 0x21
        loop .p
        ret

msg_none db 'no XMS driver', 13, 10, '$'
msg_pass db 'XMS PASS free=$'
msg_fail db 'XMS FAIL $'
msg_nl  db 13, 10, '$'
stepno  db 0
seed    db 0
entry   dw 0, 0
free0   dw 0
h1      dw 0
h2      dw 0
off     dw 0, 0
mv_len  dw 0, 0
mv_sh   dw 0
mv_so   dw 0, 0
mv_dh   dw 0
mv_do   dw 0, 0
buf1    equ $
buf2    equ $ + 4096
