; arith.asm - integer work: primes by trial division (MUL, DIV, CMP,
; conditional jumps), factorials, a string filled and reversed with STOSB
; and XCHG, a weighted checksum; decimal output through INT 21h/02.
        org 100h
start:  mov dx, hdr
        mov ah, 9
        int 21h
        mov cx, 2
.next:  mov ax, cx
        call isprime
        jnc .notp
        mov ax, cx
        call printdec
        mov dl, ' '
        mov ah, 2
        int 21h
.notp:  inc cx
        cmp cx, 100
        jb .next
        call newline
        mov dx, hdr2
        mov ah, 9
        int 21h
        mov cx, 1
        mov ax, 1
.fact:  mul cx                  ; ax = cx!  (fits 16 bits through 8!)
        push ax
        mov ax, cx
        call printdec
        mov dl, '!'
        mov ah, 2
        int 21h
        mov dl, '='
        mov ah, 2
        int 21h
        pop ax
        push ax
        call printdec
        mov dl, ' '
        mov ah, 2
        int 21h
        pop ax
        inc cx
        cmp cx, 9
        jb .fact
        call newline
        mov di, buf             ; fill A..Z
        mov cx, 26
        mov al, 'A'
        cld
.fill:  stosb
        inc al
        loop .fill
        mov si, buf             ; reverse in place
        mov di, buf+25
        mov cx, 13
.rev:   mov al, [si]
        xchg al, [di]
        mov [si], al
        inc si
        dec di
        loop .rev
        mov dx, hdr3
        mov ah, 9
        int 21h
        mov dx, buf
        mov ah, 9
        int 21h
        call newline
        xor ax, ax              ; checksum: sum of byte * position
        xor bx, bx
        mov si, buf
        mov cx, 26
.sum:   mov dl, [si]
        xor dh, dh
        inc bx
        push ax
        mov ax, dx
        mul bx
        pop dx
        add ax, dx
        inc si
        loop .sum
        push ax
        mov dx, hdr4
        mov ah, 9
        int 21h
        pop ax
        call printdec
        call newline
        mov ax, 4C00h
        int 21h

isprime:                        ; ax = n -> CF set if prime; clobbers bx dx si
        mov si, ax
        cmp si, 2
        jb .no
        je .yes
        test si, 1
        jz .no
        mov bx, 3
.loop:  mov ax, bx
        mul bx
        cmp ax, si
        ja .yes
        mov ax, si
        xor dx, dx
        div bx
        test dx, dx
        jz .no
        add bx, 2
        jmp .loop
.yes:   stc
        ret
.no:    clc
        ret

printdec:                       ; ax unsigned in decimal; preserves bx cx
        push bx
        push cx
        mov bx, 10
        xor cx, cx
.div:   xor dx, dx
        div bx
        push dx
        inc cx
        test ax, ax
        jnz .div
.out:   pop dx
        add dl, '0'
        mov ah, 2
        int 21h
        loop .out
        pop cx
        pop bx
        ret

newline:
        mov dl, 13
        mov ah, 2
        int 21h
        mov dl, 10
        mov ah, 2
        int 21h
        ret

hdr     db 'Primes below 100: $'
hdr2    db 'Factorials: $'
hdr3    db 'Reversed: $'
hdr4    db 'Checksum: $'
buf     times 26 db 0
        db '$'
