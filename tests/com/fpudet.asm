; fpudet.asm - is there an 8087, as a program finds out (docs/8087.md, M9.2):
; the BIOS's equipment word, FNINIT and the status and control words stored;
; then the control instructions (FLDCW, FENI, FDISI, FNCLEX), the control
; word stored through every kind of operand (a base and an index, a
; displacement, BP's stack segment, a segment override, a word that lies
; across the segment's end), and a run of other 8087 instructions in every
; form of operand, which must each be as long as it is: the count after
; them says the processor kept in step. fpudet runs it with FPU=8087 and
; fpunone without the line: a PC with no coprocessor, where every one of
; them does nothing and the words stay as they were.
        cpu 8086
        org 100h
start:  int 11h
        mov [eq], ax
        mov word [sw], 5A5Ah
        mov word [cw], 5A5Ah
        fninit
        fnstsw [sw]
        fnstcw [cw]
        mov dx, m_eq
        call puts
        mov al, [eq]
        shr al, 1
        and al, 1
        add al, '0'
        call putc
        mov dx, m_sw
        call puts
        mov ax, [sw]
        call hex4
        mov dx, m_cw
        call puts
        mov ax, [cw]
        call hex4
        call nl
; the control word loaded and stored
        mov word [t], 0AAAAh
        fldcw [val]
        fnstcw [t]
        mov dx, m_t1
        call puts
        mov ax, [t]
        call hex4
        call nl
; the interrupt-enable mask, and the reset again
        mov word [t], 0AAAAh
        mov word [t+2], 0AAAAh
        mov word [t+4], 0AAAAh
        fninit
        db 0DBh, 0E0h           ; FENI
        fnstcw [t]
        db 0DBh, 0E1h           ; FDISI
        fnstcw [t+2]
        db 0DBh, 0E2h           ; FNCLEX
        fnstsw [t+4]
        mov dx, m_t2
        call puts
        mov ax, [t]
        call hex4
        call spc
        mov ax, [t+2]
        call hex4
        call spc
        mov ax, [t+4]
        call hex4
        call nl
; the control word through each kind of operand
        mov di, buf
        mov cx, 8
        mov ax, 0AAAAh
        rep stosw
        mov bx, buf
        mov si, 2
        fnstcw [bx+si]          ; buf+2
        mov bp, buf
        fnstcw [bp+4]           ; buf+4, by SS
        fnstcw [buf+6]          ; a displacement alone
        mov di, 8
        fnstcw [bx+di+0]        ; buf+8
        mov ax, cs
        add ax, 1000h
        mov es, ax
        mov word [es:0FFFEh], 0AAAAh
        mov word [es:0], 0AAAAh
        mov word [es:20h], 0AAAAh
        mov di, 20h
        fnstcw [es:di]          ; another segment
        fnstcw [es:0FFFFh]      ; and across its end: FFFF and 0000
        mov dx, m_t3
        call puts
        mov si, buf+2
        mov cx, 4
.w:     lodsw
        call hex4
        call spc
        loop .w
        mov ax, [es:20h]
        call hex4
        call spc
        mov al, [es:0FFFFh]
        call hex2
        mov al, [es:0]
        call hex2
        call spc
        mov al, [es:0FFFEh]
        call hex2
        mov al, [es:1]
        call hex2
        call nl
; other instructions, in every form: each as long as it is
        xor cx, cx
        mov bx, buf
        xor si, si
        xor di, di
        mov bp, buf
        db 0D8h, 0C1h                   ; fadd st, st(1)
        inc cx
        db 0D9h, 06h
        dw buf                          ; fld dword [buf]
        inc cx
        db 0DDh, 40h, 04h               ; fld qword [bx+si+4]
        inc cx
        db 0DBh, 0A8h
        dw 2                            ; fld tword [bx+si+2]
        inc cx
        db 26h, 0DEh, 09h               ; es: fimul word [bx+di]
        inc cx
        db 0D9h, 0FAh                   ; fsqrt
        inc cx
        db 9Bh, 0DCh, 0C9h              ; fwait, fmul st(1), st
        inc cx
        db 0DFh, 7Eh, 00h               ; fistp qword [bp+0]
        inc cx
        db 0DAh, 22h                    ; fisub dword [bp+si]
        inc cx
        db 0DEh, 0D9h                   ; fcompp
        inc cx
        db 36h, 0D8h, 1Fh               ; ss: fcomp dword [bx]
        inc cx
        db 0DDh, 0D8h                   ; fstp st(0)
        inc cx
        mov dx, m_t4
        call puts
        mov ax, cx
        call hex4
        call nl
        mov dx, m_done
        call puts
        mov ax, 4C00h
        int 21h

puts:   mov ah, 9
        int 21h
        ret
putc:   mov dl, al
        mov ah, 2
        int 21h
        ret
spc:    mov al, ' '
        jmp putc
nl:     mov al, 13
        call putc
        mov al, 10
        jmp putc
hex4:   push ax
        mov al, ah
        call hex2
        pop ax
hex2:   push ax
        push cx
        mov cl, 4
        shr al, cl
        pop cx
        call .n
        pop ax
        and al, 0Fh
.n:     add al, '0'
        cmp al, '9'
        jbe .p
        add al, 7
.p:     jmp putc

m_eq:   db 'EQUIPMENT 8087=$'
m_sw:   db ' STATUS=$'
m_cw:   db ' CONTROL=$'
m_t1:   db 'FLDCW 0F7F: $'
m_t2:   db 'FENI FDISI FNCLEX: $'
m_t3:   db 'OPERANDS: $'
m_t4:   db 'IN STEP: $'
m_done: db 'DONE', 13, 10, '$'
val:    dw 0F7Fh
eq:     dw 0
sw:     dw 0
cw:     dw 0
t:      dw 0, 0, 0
buf:    times 16 dw 0
