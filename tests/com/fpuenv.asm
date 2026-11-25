; fpuenv.asm - the 8087's environment and exceptions (docs/8087.md, M9.5), each line
; worked out by hand from Intel's manual (figures S-18 and S-19, the tag word, the
; masked and unmasked responses):
; E1  FSTENV: control, status and tag words; the instruction's address less where
;     it is (0000 0000), its opcode (DD 06: 0506), the operand's address less where
;     it is (0000 0000); and the control word after it, every exception masked
; E2  the same with a segment prefix: the address is the prefix's
; E3  FSAVE: the control and status words after it (FNINIT's), the image's status
;     and tag words, its three registers' exponents and pi's top word; FRSTOR: the
;     status word, and the three registers popped
; E4  FLDENV: the status and control words loaded, the tag word stored again
; E5  unmasked exceptions with the interrupt disabled: the instruction undone, IR
;     set (a: an empty register; b: x/0; c: FIST too large, the store not made, and
;     FISTP not popped; d: overflow; e: precision, which is not undone)
; E6  with the interrupt enabled, INT 2 (a PC/XT's NMI): taken once (a), not with
;     FDISI (b), and taken when FLDCW unmasks an exception already flagged (c); the
;     handler's status word, and the status word after its FNCLEX
        cpu 8086
        org 100h
start:
; --- E1
        mov dx, m1
        call puts
        fninit
        fldcw [cw0F40]
        fld1
l1:     fld qword [x1]
        fnstenv [env]
        fnstcw [t1]
        call envline
        mov bx, l1
        mov ax, x1
        call ptrs
        mov ax, [t1]
        call pw
        call nl
; --- E2
        mov dx, m2
        call puts
        fninit
        push ds
        pop es
l2:     fld qword [es:x1]
        fnstenv [env]
        mov bx, l2
        mov ax, x1
        call ptrs
        call nl
; --- E3
        mov dx, m3
        call puts
        fninit
        fld1
        fldpi
        fldz
        fsave [sv]
        fnstcw [t1]
        fnstsw [t2]
        mov ax, [t1]
        call pw
        mov ax, [t2]
        call pw
        mov ax, [sv+2]
        call pw
        mov ax, [sv+4]
        call pw
        mov ax, [sv+14+8]
        call pw
        mov ax, [sv+24+8]
        call pw
        mov ax, [sv+34+8]
        call pw
        mov ax, [sv+24+6]
        call pw
        frstor [sv]
        fnstsw [t2]
        mov ax, [t2]
        call pw
        mov cx, 3
.p:     fstp tword [r]
        mov ax, [r+8]
        call pw
        loop .p
        call nl
; --- E4
        mov dx, m4
        call puts
        fninit
        fldenv [envin]
        fnstsw [t2]
        fnstcw [t1]
        fnstenv [env]
        mov ax, [t2]
        call pw
        mov ax, [t1]
        call pw
        mov ax, [env+4]
        call pw
        call nl
; --- E5
        mov dx, m5
        call puts
        fninit                  ; a: an empty register, I unmasked
        fldcw [cw03FE]
        fld1
        fld st5
        call sw
        fnclex
        call sw
        fninit                  ; b: x/0, Z unmasked
        fldcw [cw03FB]
        fldz
        fld1
        fdiv st0, st1
        call sw
        fstp tword [r]
        mov ax, [r+8]
        call pw
        fninit                  ; c: FIST too large: no store, and FISTP not popped
        fldcw [cw03FE]
        fld qword [big]
        mov word [o], 0AAAAh
        fist word [o]
        call sw
        mov ax, [o]
        call pw
        fistp word [o]
        call sw
        fninit                  ; d: overflow
        fldcw [cw03F7]
        fld tword [huge]
        fmul st0, st0
        call sw
        fstp tword [r]
        mov ax, [r+8]
        call pw
        fninit                  ; e: precision: the result stays
        fldcw [cw03DF]
        fld1
        fdiv dword [three]
        call sw
        fstp tword [r]
        mov ax, [r+8]
        call pw
        call nl
; --- E6
        mov dx, m6
        call puts
        xor ax, ax
        mov es, ax
        mov ax, [es:8]
        mov [old2], ax
        mov ax, [es:10]
        mov [old2+2], ax
        cli
        mov word [es:8], nmi
        mov [es:10], cs
        sti
        fninit                  ; a
        fldcw [cw037E]
        fld1
        fld st5
        nop
        mov ax, [hits]
        call pw
        mov ax, [hsw]
        call pw
        call sw
        fninit                  ; b
        fldcw [cw037E]
        fdisi
        fld1
        fld st5
        nop
        mov ax, [hits]
        call pw
        call sw
        fninit                  ; c
        fld1
        fdiv dword [zero]
        fldcw [cw037B]
        nop
        mov ax, [hits]
        call pw
        mov ax, [hsw]
        call pw
        xor ax, ax
        mov es, ax
        cli
        mov ax, [old2]
        mov [es:8], ax
        mov ax, [old2+2]
        mov [es:10], ax
        sti
        call nl
        mov dx, done
        call puts
        mov ax, 4C00h
        int 21h

nmi:    push ax
        fnstsw [cs:hsw]
        fnclex
        inc word [cs:hits]
        pop ax
        iret

; envline: the control, status and tag words of env
envline:
        mov ax, [env]
        call pw
        mov ax, [env+2]
        call pw
        mov ax, [env+4]
        jmp pw
; ptrs: BX the instruction's offset in CS, AX the operand's in DS: env's pointers less them
ptrs:   push ax
        mov ax, cs
        call lin
        mov cx, [env+6]
        sub cx, ax
        xchg ax, cx
        call pw
        mov ax, [env+8]
        push cx
        mov cl, 12
        shr ax, cl
        pop cx
        sub ax, dx
        call pw
        mov ax, [env+8]
        and ax, 07FFh
        call pw
        pop bx
        mov ax, ds
        call lin
        mov cx, [env+10]
        sub cx, ax
        xchg ax, cx
        call pw
        mov ax, [env+12]
        mov cl, 12
        shr ax, cl
        sub ax, dx
        jmp pw
; lin: AX a segment, BX an offset: AX the address's low word, DX its top four bits
lin:    mov dx, ax
        mov cl, 4
        shl ax, cl
        mov cl, 12
        shr dx, cl
        add ax, bx
        adc dx, 0
        ret
sw:     fnstsw [t2]
        mov ax, [t2]
pw:     push ax
        mov al, ah
        call hex2
        pop ax
        call hex2
        mov al, ' '
        jmp putc
hex2:   push ax
        push cx
        mov cl, 4
        shr al, cl
        call .n
        pop cx
        pop ax
        and al, 0Fh
.n:     add al, '0'
        cmp al, '9'
        jbe putc
        add al, 7
putc:   push ax
        push dx
        mov dl, al
        mov ah, 2
        int 21h
        pop dx
        pop ax
        ret
puts:   mov ah, 9
        int 21h
        ret
nl:     mov al, 13
        call putc
        mov al, 10
        jmp putc

m1:     db 'E1 $'
m2:     db 'E2 $'
m3:     db 'E3 $'
m4:     db 'E4 $'
m5:     db 'E5 $'
m6:     db 'E6 $'
done:   db 'DONE', 13, 10, '$'
cw0F40: dw 0F40h
cw03FE: dw 03FEh
cw03FB: dw 03FBh
cw03F7: dw 03F7h
cw03DF: dw 03DFh
cw037E: dw 037Eh
cw037B: dw 037Bh
x1:     dq 2.5
big:    dq 1.0e10
three:  dd 3.0
zero:   dd 0.0
huge:   dw 0, 0, 0, 8000h, 7E7Fh            ; 2^16000
envin:  dw 037Fh, 5020h, 0FFFFh, 0, 0, 0, 0 ; C3, the top 2, P; every register empty
hits:   dw 0
hsw:    dw 0
old2:   dw 0, 0
t1:     dw 0
t2:     dw 0
o:      dw 0
r:      times 10 db 0
env:    times 14 db 0
sv:     times 94 db 0
