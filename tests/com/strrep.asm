; strrep.asm - the string instructions, alone and under REP, against the
; same work done a byte at a time by ordinary instructions. Every case of
; the table is run twice from the same memory (a window of WIN bytes round
; SI and one round DI): once as the instruction itself, once by run_ref,
; which uses no string instruction; the registers, the flags and both
; windows must agree. The cases put SI and DI at the end of a 64K block of
; the PC's memory (segments 2FF0h and 3FF0h: offset 0100h is the first byte
; of the next block), at the segment's wrap, on odd addresses so that a
; word lies across either, on overlapping moves, and in the text buffer.
; Then eight long runs (bigs) and, last, rows of the text screen written by
; string instructions, which the judge compares with the pixels.
; Prints "strrep: N cases, B bad" and a line "BAD n x" for each difference
; (x: S I, D I, C X, A X, F lags, m source window, M destination window,
; B a long run).
        cpu 8086
        org 100h

WIN     equ 96                  ; bytes in a window
CTR     equ 40                  ; where SI or DI is in it

C_OP    equ 0                   ; the opcode, A4h..AFh
C_REP   equ 1                   ; 0, F3h or F2h
C_FL    equ 2
C_M     equ 3                   ; destination window = table xor M ...
C_K     equ 4                   ; ... and xor X at CTR+K and CTR+K+1
C_X     equ 5
C_SSEG  equ 6
C_DSEG  equ 8
C_SI    equ 10
C_DI    equ 12
C_CX    equ 14
C_AX    equ 16
C_LEN   equ 18

DF      equ 1                   ; direction flag set
OV      equ 2                   ; ES: before REP (DS is then a decoy)
RUN     equ 4                   ; the table of runs of eight equal bytes
OV2     equ 8                   ; ES: after REP

N       equ 3000h               ; a block's first segment
E       equ 4000h
NX      equ 2FF0h               ; the block ends at offset 0100h
EX      equ 3FF0h
DCY     equ 3100h               ; the decoy
TXT     equ 0B800h

%macro tc 12                    ; op rep fl sseg dseg si di cx ax m k x
        db %1, %2, %3, %10, %11, %12
        dw %4, %5, %6, %7, %8, %9
%endmacro

start:  mov ax, 0003h
        int 10h
        mov word [casep], cases
.next:  mov bx, [casep]
        cmp byte [bx+C_OP], 0
        je .done
        inc word [ncase]
        mov byte [cbad], 0
        call prep
        call fill
        call run_str
        call snap
        call fill
        call run_ref
        call check
        add word [casep], C_LEN
        jmp .next
.done:  call bigs
        mov dx, t_name
        mov ah, 9
        int 21h
        mov ax, [ncase]
        call printdec
        mov dx, t_cases
        mov ah, 9
        int 21h
        mov ax, [nbad]
        call printdec
        mov dx, t_bad
        mov ah, 9
        int 21h
        call paint
        mov ax, 4C00h
        int 21h

;--- what the case needs: segments, table, flags word, the instruction
prep:   mov bx, [casep]
        mov ax, [bx+C_SSEG]
        test byte [bx+C_FL], OV|OV2
        jz .p1
        mov ax, [bx+C_DSEG]
.p1:    mov [eseg], ax
        mov ax, [bx+C_DSEG]
        mov [dsegv], ax
        mov al, [bx+C_K]
        cbw
        add ax, CTR
        mov [kidx], ax
        mov word [tabp], tab_d
        test byte [bx+C_FL], RUN
        jz .p2
        mov word [tabp], tab_r
.p2:    pushf
        pop ax
        and ax, 0F22Ah          ; keep IF; OF DF TF SF ZF AF PF CF clear
        or ax, 0045h            ; ZF PF CF set
        test byte [bx+C_FL], DF
        jz .p3
        or ax, 0400h
.p3:    mov [iflags], ax
        mov di, stub
        mov al, [bx+C_FL]
        test al, OV
        jz .p4
        mov byte [di], 26h
        inc di
.p4:    mov ah, [bx+C_REP]
        or ah, ah
        jz .p5
        mov [di], ah
        inc di
.p5:    test al, OV2
        jz .p6
        mov byte [di], 26h
        inc di
.p6:    mov al, [bx+C_OP]
        mov [di], al
        mov byte [di+1], 0C3h   ; ret
        ret

;--- both windows from the table
fill:   mov bx, [casep]
        mov es, [eseg]
        mov di, [bx+C_SI]
        sub di, CTR
        mov bx, [tabp]
        xor si, si
.f1:    mov al, [bx+si]
        mov [es:di], al
        inc di
        inc si
        cmp si, WIN
        jb .f1
        mov bx, [casep]
        mov es, [dsegv]
        mov di, [bx+C_DI]
        sub di, CTR
        mov dh, [bx+C_M]
        mov dl, [bx+C_X]
        mov bx, [tabp]
        xor si, si
.f2:    mov al, [bx+si]
        xor al, dh
        mov cx, si
        sub cx, [kidx]
        cmp cx, 1
        ja .f3
        xor al, dl
.f3:    mov [es:di], al
        inc di
        inc si
        cmp si, WIN
        jb .f2
        ret

;--- the instruction itself
run_str:
        mov bx, [casep]
        mov es, [bx+C_DSEG]
        mov si, [bx+C_SI]
        mov di, [bx+C_DI]
        mov cx, [bx+C_CX]
        mov ax, [bx+C_AX]
        push word [iflags]
        mov ds, [bx+C_SSEG]
        popf
        call stub
        pushf
        push cs
        pop ds
        pop word [s_fl]
        cld
        mov [s_si], si
        mov [s_di], di
        mov [s_cx], cx
        mov [s_ax], ax
        ret

;--- keep both windows
snap:   mov bx, [casep]
        mov es, [eseg]
        mov si, [bx+C_SI]
        sub si, CTR
        mov di, snapbuf
        mov cx, WIN
.s1:    mov al, [es:si]
        mov [di], al
        inc si
        inc di
        loop .s1
        mov es, [dsegv]
        mov si, [bx+C_DI]
        sub si, CTR
        mov cx, WIN
.s2:    mov al, [es:si]
        mov [di], al
        inc si
        inc di
        loop .s2
        ret

;--- the same by ordinary instructions: SI DI CX as the guest's, DX its AX,
; BP the step
run_ref:
        mov bx, [casep]
        mov ax, [iflags]
        mov [r_fl], ax
        mov al, [bx+C_OP]
        mov ah, al
        and ah, 1
        mov [wid], ah
        sub al, 0A4h
        shr al, 1
        mov [cls], al           ; 0 MOVS 1 CMPS 3 STOS 4 LODS 5 SCAS
        mov bp, 1
        or ah, ah
        jz .w
        inc bp
.w:     test byte [bx+C_FL], DF
        jz .d
        neg bp
.d:     mov si, [bx+C_SI]
        mov di, [bx+C_DI]
        mov cx, [bx+C_CX]
        mov dx, [bx+C_AX]
        mov al, [bx+C_REP]
        mov [repv], al
        or al, al
        jz .one
        jcxz .end
.loop:  call elem
        dec cx
        jz .end
        mov al, [cls]
        cmp al, 1
        je .cond
        cmp al, 5
        jne .loop
.cond:  mov ax, [r_fl]
        and ax, 0040h
        cmp byte [repv], 0F3h
        jne .ne
        or ax, ax               ; REPE goes on while ZF is set
        jz .end
        jmp .loop
.ne:    or ax, ax
        jnz .end
        jmp .loop
.one:   call elem
.end:   mov [r_si], si
        mov [r_di], di
        mov [r_cx], cx
        mov [r_ax], dx
        ret

elem:   mov al, [cls]
        cmp al, 0
        je .movs
        cmp al, 1
        je .cmps
        cmp al, 3
        je .stos
        cmp al, 4
        je .lods
        call get_dst            ; SCAS: AX - destination
        mov bx, ax
        mov ax, dx
        call cmp_ab
        add di, bp
        ret
.movs:  call get_src
        call put_dst
        add si, bp
        add di, bp
        ret
.cmps:  call get_dst            ; source - destination
        mov bx, ax
        call get_src
        call cmp_ab
        add si, bp
        add di, bp
        ret
.stos:  mov ax, dx
        call put_dst
        add di, bp
        ret
.lods:  call get_src
        cmp byte [wid], 0
        jne .lw
        mov dl, al
        jmp .l2
.lw:    mov dx, ax
.l2:    add si, bp
        ret

get_src:
        mov es, [eseg]
        mov al, [es:si]
        cmp byte [wid], 0
        je .r
        push si
        inc si                  ; (FFFFh goes round to 0)
        mov ah, [es:si]
        pop si
.r:     ret
get_dst:
        mov es, [dsegv]
        mov al, [es:di]
        cmp byte [wid], 0
        je .r
        push di
        inc di
        mov ah, [es:di]
        pop di
.r:     ret
put_dst:
        mov es, [dsegv]
        mov [es:di], al
        cmp byte [wid], 0
        je .r
        push di
        inc di
        mov [es:di], ah
        pop di
.r:     ret
cmp_ab: cmp byte [wid], 0       ; the flags of AX - BX (AL - BL)
        jne .w
        cmp al, bl
        jmp .f
.w:     cmp ax, bx
.f:     pushf
        pop ax
        and ax, 08D5h
        and word [r_fl], 0F72Ah
        or [r_fl], ax
        ret

;--- compare
check:  mov ax, [s_si]
        cmp ax, [r_si]
        je .1
        mov al, 'S'
        call bad
.1:     mov ax, [s_di]
        cmp ax, [r_di]
        je .2
        mov al, 'D'
        call bad
.2:     mov ax, [s_cx]
        cmp ax, [r_cx]
        je .3
        mov al, 'C'
        call bad
.3:     mov ax, [s_ax]
        cmp ax, [r_ax]
        je .4
        mov al, 'A'
        call bad
.4:     mov ax, [s_fl]
        xor ax, [r_fl]
        and ax, 0CD5h
        jz .5
        mov al, 'F'
        call bad
.5:     mov bx, [casep]
        mov es, [eseg]
        mov si, [bx+C_SI]
        sub si, CTR
        mov di, snapbuf
        mov cx, WIN
.m1:    mov al, [es:si]
        cmp al, [di]
        jne .b1
        inc si
        inc di
        loop .m1
        jmp .6
.b1:    mov al, 'm'
        call bad
.6:     mov bx, [casep]
        mov es, [dsegv]
        mov si, [bx+C_DI]
        sub si, CTR
        mov di, snapbuf+WIN
        mov cx, WIN
.m2:    mov al, [es:si]
        cmp al, [di]
        jne .b2
        inc si
        inc di
        loop .m2
        ret
.b2:    mov al, 'M'
        ; (falls into bad)

; "BAD n x": AL = x; the case counts as bad once
bad:    push ax
        cmp byte [cbad], 0
        jne .b
        inc byte [cbad]
        inc word [nbad]
.b:     mov dx, t_badl
        mov ah, 9
        int 21h
        mov ax, [ncase]
        call printdec
        mov dl, ' '
        mov ah, 2
        int 21h
        pop dx
        mov ah, 2
        int 21h
        mov dx, t_nl
        mov ah, 9
        int 21h
        ret

printdec:                       ; AX in decimal
        mov bx, 10
        xor cx, cx
.d1:    xor dx, dx
        div bx
        push dx
        inc cx
        or ax, ax
        jnz .d1
.d2:    pop dx
        add dl, '0'
        mov ah, 2
        int 21h
        loop .d2
        ret

;--- long runs: BIGN words between 2F80:0000 (its block ends at 0800h) and
; 3F00:0FFF (a word lies across its block's end), with a guard byte either
; side of the destination
SRCB      equ 2F80h
DSTB      equ 3F00h
DOFF    equ 0FFFh
BIGN    equ 1000h

bigs:   mov dx, 3               ; 1: REP MOVSW upwards
        call bstart
        xor si, si
        mov di, DOFF
        mov cx, BIGN
        call bsegs
        rep movsw
        call bback
        mov ax, 2*BIGN
        mov bx, DOFF+2*BIGN
        call bregs
        mov ax, 1
        call bverify

        mov dx, 5               ; 2: REP MOVSW downwards
        call bstart
        mov si, 2*BIGN-2
        mov di, DOFF+2*BIGN-2
        mov cx, BIGN
        call bsegs
        std
        rep movsw
        call bback
        mov ax, -2
        mov bx, DOFF-2
        call bregs
        mov ax, 1
        call bverify

        mov dx, 0               ; 3: REP STOSW
        call bstart
        mov di, DOFF
        mov cx, BIGN
        call bsegs
        mov ax, 0A55Ah
        xor si, si
        rep stosw
        call bback
        xor ax, ax
        mov bx, DOFF+2*BIGN
        call bregs
        mov ax, 0A55Ah
        call bverify

        mov dx, 7               ; 4: REP MOVSB upwards
        call bstart
        xor si, si
        mov di, DOFF
        mov cx, 2*BIGN
        call bsegs
        rep movsb
        call bback
        mov ax, 2*BIGN
        mov bx, DOFF+2*BIGN
        call bregs
        mov ax, 1
        call bverify

        mov dx, 0               ; 5: REP STOSB
        call bstart
        mov di, DOFF
        mov cx, 2*BIGN
        call bsegs
        mov al, 3Ch
        xor si, si
        rep stosb
        call bback
        xor ax, ax
        mov bx, DOFF+2*BIGN
        call bregs
        mov ax, 3C3Ch
        call bverify

        mov dx, 11              ; 6: REP MOVSB downwards
        call bstart
        mov si, 2*BIGN-1
        mov di, DOFF+2*BIGN-1
        mov cx, 2*BIGN
        call bsegs
        std
        rep movsb
        call bback
        mov ax, -1
        mov bx, DOFF-1
        call bregs
        mov ax, 1
        call bverify

        mov dx, 13              ; 7: a block moved down 16 bytes over itself
        call bstart
        mov ax, SRCB
        mov es, ax
        mov si, 16
        xor di, di
        mov cx, BIGN-8
        mov ds, ax
        rep movsw
        call bback
        mov ax, 2*BIGN
        mov bx, 2*BIGN-16
        call bregs
        mov ax, SRCB
        mov es, ax
        xor bx, bx
        mov ax, 8*13+1
        mov cx, BIGN-8
.v7:    cmp [es:bx], ax
        jne .b7
        add ax, 13
        add bx, 2
        loop .v7
        jmp .8
.b7:    mov al, 'B'
        call bad

.8:     mov dx, 17              ; 8: the first word spread over the block
        call bstart
        mov ax, SRCB
        mov es, ax
        xor si, si
        mov di, 2
        mov cx, BIGN-1
        mov ds, ax
        rep movsw
        call bback
        mov ax, 2*BIGN-2
        mov bx, 2*BIGN
        call bregs
        mov ax, SRCB
        mov es, ax
        xor bx, bx
        mov cx, BIGN
.v8:    cmp word [es:bx], 1
        jne .b8
        add bx, 2
        loop .v8
        ret
.b8:    mov al, 'B'
        jmp bad

bstart: inc word [ncase]        ; source words 1, 1+DX, 1+2*DX...; the guards
        mov byte [cbad], 0
        mov [bstep], dx
        mov ax, SRCB
        mov es, ax
        xor bx, bx
        mov ax, 1
        mov cx, BIGN
.f:     mov [es:bx], ax
        add ax, dx
        add bx, 2
        loop .f
        mov ax, DSTB
        mov es, ax
        mov byte [es:DOFF-1], 0EEh
        mov byte [es:DOFF+2*BIGN], 0EEh
        ret
bsegs:  mov ax, DSTB              ; ES the destination, DS the source, DF clear
        mov es, ax
        mov ax, SRCB
        mov ds, ax
        cld
        ret
bback:  push cs
        pop ds
        cld
        mov [s_si], si
        mov [s_di], di
        mov [s_cx], cx
        ret
bregs:  cmp ax, [s_si]          ; SI = AX, DI = BX, CX = 0
        jne .b
        cmp bx, [s_di]
        jne .b
        cmp word [s_cx], 0
        je .r
.b:     mov al, 'C'
        call bad
.r:     ret
bverify:                        ; the destination: AX, AX+step...; the guards
        mov dx, [bstep]
        mov bx, DSTB
        mov es, bx
        mov bx, DOFF
        mov cx, BIGN
.v:     cmp [es:bx], ax
        jne .b
        add ax, dx
        add bx, 2
        loop .v
        cmp byte [es:DOFF-1], 0EEh
        jne .b
        cmp byte [es:DOFF+2*BIGN], 0EEh
        jne .b
        ret
.b:     mov al, 'B'
        jmp bad

;--- rows of the text screen by string instructions (the judge compares the
; text buffer with the pixels): each run covers more than one 256-byte page
paint:  mov bx, pbuf
        xor cx, cx
.p:     mov al, cl
        and al, 3Fh
        add al, 21h
        mov [bx], al
        mov byte [bx+1], 1Eh
        add bx, 2
        inc cx
        cmp cx, 400
        jb .p
        mov ax, TXT
        mov es, ax
        cld
        mov si, pbuf            ; rows 8-12: REP MOVSW
        mov di, 8*160
        mov cx, 400
        rep movsw
        std                     ; rows 14-15: REP MOVSB downwards
        mov si, pbuf+319
        mov di, 15*160+159
        mov cx, 320
        rep movsb
        cld
        mov di, 17*160          ; rows 17-19: REP STOSW
        mov ax, 2F2Ah
        mov cx, 240
        rep stosw
        mov di, 21*160          ; row 21: REP STOSB
        mov al, 41h
        mov cx, 160
        rep stosb
        mov di, 23*160          ; row 23: STOSW, one at a time
        mov ax, 4E2Bh
        mov cx, 80
.s:     stosw
        loop .s
        ret

t_name: db 'strrep: $'
t_cases: db ' cases, $'
t_bad:  db ' bad', 13, 10, '$'
t_badl: db 'BAD $'
t_nl:   db 13, 10, '$'

casep:  dw 0
ncase:  dw 0
nbad:   dw 0
cbad:   db 0
wid:    db 0
cls:    db 0
repv:   db 0
eseg:   dw 0
dsegv:  dw 0
kidx:   dw 0
tabp:   dw 0
iflags: dw 0
bstep:  dw 0
s_si:   dw 0
s_di:   dw 0
s_cx:   dw 0
s_ax:   dw 0
s_fl:   dw 0
r_si:   dw 0
r_di:   dw 0
r_cx:   dw 0
r_ax:   dw 0
r_fl:   dw 0
stub:   times 6 db 0

tab_d:                          ; every byte different; CTR is 41h
%assign i 0
%rep WIN
        db ((i+64-CTR)*5+1) & 255
%assign i i+1
%endrep
tab_r:                          ; runs of eight: 29h from CTR, 2Eh from CTR+8,
%assign i 0                     ; 24h below CTR
%rep WIN
        db (((i+64-CTR)>>3)*5+1) & 255
%assign i i+1
%endrep

cases:
; MOVSB, MOVSW alone
        tc 0A4h, 0, 0,   N,   E,   0100h, 0200h, 1, 1234h, 80h, 0, 0
        tc 0A4h, 0, DF,  N,   E,   0100h, 0200h, 1, 1234h, 80h, 0, 0
        tc 0A4h, 0, 0,   NX,  EX,  00FFh, 0100h, 1, 1234h, 80h, 0, 0
        tc 0A4h, 0, 0,   N,   E,   0FFFFh, 0FFFFh, 1, 1234h, 80h, 0, 0
        tc 0A4h, 0, DF,  N,   E,   0000h, 0000h, 1, 1234h, 80h, 0, 0
        tc 0A4h, 0, OV,  DCY, E,   0100h, 0200h, 1, 1234h, 80h, 0, 0
        tc 0A4h, 0, 0,   NX,  TXT, 00FFh, 0200h, 1, 1234h, 80h, 0, 0
        tc 0A5h, 0, 0,   N,   E,   0100h, 0200h, 1, 1234h, 80h, 0, 0
        tc 0A5h, 0, DF,  N,   E,   0100h, 0200h, 1, 1234h, 80h, 0, 0
        tc 0A5h, 0, 0,   NX,  EX,  00FFh, 00FFh, 1, 1234h, 80h, 0, 0
        tc 0A5h, 0, 0,   N,   E,   0FFFFh, 0200h, 1, 1234h, 80h, 0, 0
        tc 0A5h, 0, 0,   N,   E,   0100h, 0FFFFh, 1, 1234h, 80h, 0, 0
        tc 0A5h, 0, 0,   N,   E,   0FFFEh, 0FFFEh, 1, 1234h, 80h, 0, 0
        tc 0A5h, 0, DF,  N,   E,   0001h, 0000h, 1, 1234h, 80h, 0, 0
        tc 0A5h, 0, DF,  N,   E,   0FFFFh, 0FFFFh, 1, 1234h, 80h, 0, 0
        tc 0A5h, 0, OV,  DCY, E,   0100h, 0200h, 1, 1234h, 80h, 0, 0
        tc 0A5h, 0, 0,   NX,  TXT, 00FFh, 0201h, 1, 1234h, 80h, 0, 0
; STOSB, STOSW alone
        tc 0AAh, 0, 0,   N,   E,   0100h, 0200h, 1, 12ABh, 80h, 0, 0
        tc 0AAh, 0, DF,  N,   E,   0100h, 0200h, 1, 12ABh, 80h, 0, 0
        tc 0AAh, 0, 0,   N,   EX,  0100h, 00FFh, 1, 12ABh, 80h, 0, 0
        tc 0AAh, 0, 0,   N,   E,   0100h, 0FFFFh, 1, 12ABh, 80h, 0, 0
        tc 0AAh, 0, 0,   N,   TXT, 0100h, 0200h, 1, 12ABh, 80h, 0, 0
        tc 0ABh, 0, 0,   N,   E,   0100h, 0200h, 1, 12ABh, 80h, 0, 0
        tc 0ABh, 0, DF,  N,   E,   0100h, 0200h, 1, 12ABh, 80h, 0, 0
        tc 0ABh, 0, 0,   N,   EX,  0100h, 00FFh, 1, 12ABh, 80h, 0, 0
        tc 0ABh, 0, 0,   N,   E,   0100h, 0FFFFh, 1, 12ABh, 80h, 0, 0
        tc 0ABh, 0, DF,  N,   E,   0100h, 0000h, 1, 12ABh, 80h, 0, 0
        tc 0ABh, 0, 0,   N,   TXT, 0100h, 0200h, 1, 12ABh, 80h, 0, 0
; LODSB, LODSW alone
        tc 0ACh, 0, 0,   N,   E,   0100h, 0200h, 1, 12ABh, 80h, 0, 0
        tc 0ACh, 0, DF,  N,   E,   0100h, 0200h, 1, 12ABh, 80h, 0, 0
        tc 0ACh, 0, OV,  DCY, E,   0100h, 0200h, 1, 12ABh, 80h, 0, 0
        tc 0ACh, 0, 0,   N,   E,   0FFFFh, 0200h, 1, 12ABh, 80h, 0, 0
        tc 0ADh, 0, 0,   N,   E,   0100h, 0200h, 1, 12ABh, 80h, 0, 0
        tc 0ADh, 0, DF,  N,   E,   0100h, 0200h, 1, 12ABh, 80h, 0, 0
        tc 0ADh, 0, 0,   NX,  E,   00FFh, 0200h, 1, 12ABh, 80h, 0, 0
        tc 0ADh, 0, 0,   N,   E,   0FFFFh, 0200h, 1, 12ABh, 80h, 0, 0
        tc 0ADh, 0, OV,  DCY, EX,  00FFh, 0200h, 1, 12ABh, 80h, 0, 0
; SCAS, CMPS alone
        tc 0AEh, 0, 0,   N,   E,   0100h, 0200h, 1, 00C1h, 80h, 0, 0
        tc 0AEh, 0, DF,  N,   E,   0100h, 0200h, 1, 0010h, 80h, 0, 0
        tc 0AEh, 0, 0,   N,   EX,  0100h, 00FFh, 1, 0FF00h, 80h, 0, 0
        tc 0AFh, 0, 0,   N,   E,   0100h, 0200h, 1, 1234h, 80h, 0, 0
        tc 0AFh, 0, 0,   N,   EX,  0100h, 00FFh, 1, 0C6C1h, 80h, 0, 0
        tc 0AFh, 0, DF,  N,   E,   0100h, 0FFFFh, 1, 8000h, 80h, 0, 0
        tc 0A6h, 0, 0,   N,   E,   0100h, 0200h, 1, 1234h, 00h, 0, 0
        tc 0A6h, 0, 0,   N,   E,   0100h, 0200h, 1, 1234h, 80h, 0, 0
        tc 0A6h, 0, DF,  NX,  EX,  00FFh, 0100h, 1, 1234h, 01h, 0, 0
        tc 0A7h, 0, 0,   N,   E,   0100h, 0200h, 1, 1234h, 00h, 0, 0
        tc 0A7h, 0, DF,  N,   E,   0100h, 0200h, 1, 1234h, 7Fh, 0, 0
        tc 0A7h, 0, 0,   NX,  EX,  00FFh, 00FFh, 1, 1234h, 01h, 0, 0
        tc 0A7h, 0, 0,   N,   E,   0FFFFh, 0FFFFh, 1, 1234h, 00h, 0, 0FFh
        tc 0A7h, 0, OV,  DCY, E,   0100h, 0200h, 1, 1234h, 00h, 0, 0
; REP MOVSB
        tc 0A4h, 0F3h, 0,   N,   E,   0100h, 0200h, 20, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, 0,   N,   E,   0100h, 0200h, 0, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, 0,   N,   E,   0100h, 0200h, 1, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, DF,  N,   E,   0100h, 0200h, 20, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, DF,  N,   E,   0100h, 0200h, 0, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, 0,   NX,  EX,  00F8h, 0100h, 20, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, 0,   NX,  EX,  0100h, 00F5h, 20, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, 0,   NX,  EX,  00F8h, 00F3h, 24, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, 0,   NX,  EX,  00ECh, 00ECh, 20, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, DF,  NX,  EX,  0105h, 0109h, 20, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, DF,  NX,  EX,  0100h, 00FFh, 20, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, 0,   N,   E,   0FFF8h, 0200h, 20, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, 0,   N,   E,   0100h, 0FFF0h, 24, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, 0,   NX,  EX,  0FFF0h, 0FFFFh, 24, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, DF,  N,   E,   0005h, 000Ah, 20, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, DF,  NX,  EX,  0000h, 0FFFFh, 20, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, 0,   N,   N,   0100h, 0101h, 20, 1234h, 00h, 0, 0
        tc 0A4h, 0F3h, 0,   N,   N,   0100h, 0102h, 20, 1234h, 00h, 0, 0
        tc 0A4h, 0F3h, 0,   N,   N,   0101h, 0100h, 20, 1234h, 00h, 0, 0
        tc 0A4h, 0F3h, DF,  N,   N,   0100h, 00FFh, 20, 1234h, 00h, 0, 0
        tc 0A4h, 0F3h, DF,  N,   N,   0100h, 0101h, 20, 1234h, 00h, 0, 0
        tc 0A4h, 0F3h, 0,   N,   N+1, 0110h, 0101h, 20, 1234h, 00h, 0, 0
        tc 0A4h, 0F3h, 0,   NX,  NX,  00F0h, 00F1h, 24, 1234h, 00h, 0, 0
        tc 0A4h, 0F2h, 0,   N,   E,   0100h, 0200h, 10, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, OV,  DCY, E,   0100h, 0200h, 20, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, OV2, DCY, EX,  00F8h, 0200h, 20, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, 0,   NX,  TXT, 00F0h, 01F0h, 40, 1234h, 80h, 0, 0
        tc 0A4h, 0F3h, DF,  NX,  TXT, 0110h, 0210h, 30, 1234h, 80h, 0, 0
; REP MOVSW
        tc 0A5h, 0F3h, 0,   N,   E,   0100h, 0200h, 20, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, 0,   N,   E,   0100h, 0200h, 0, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, 0,   N,   E,   0100h, 0200h, 1, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, DF,  N,   E,   0100h, 0200h, 20, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, DF,  N,   E,   0100h, 0200h, 1, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, 0,   NX,  EX,  00F8h, 0100h, 20, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, 0,   NX,  EX,  00F7h, 0200h, 20, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, 0,   NX,  EX,  0100h, 00F5h, 20, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, 0,   NX,  EX,  00F7h, 00F1h, 24, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, 0,   NX,  EX,  00FFh, 00FFh, 12, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, DF,  NX,  EX,  0108h, 010Eh, 20, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, DF,  NX,  EX,  0107h, 0109h, 20, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, DF,  NX,  EX,  00FFh, 00FFh, 12, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, 0,   N,   E,   0FFF8h, 0200h, 20, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, 0,   N,   E,   0FFF7h, 0200h, 20, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, 0,   N,   E,   0100h, 0FFF1h, 24, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, 0,   NX,  EX,  0FFFFh, 0FFFDh, 12, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, DF,  N,   E,   0006h, 000Ah, 20, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, DF,  N,   E,   0005h, 0200h, 20, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, DF,  NX,  EX,  0200h, 0003h, 20, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, DF,  N,   E,   0FFFFh, 0FFFFh, 8, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, 0,   N,   N,   0100h, 0101h, 20, 1234h, 00h, 0, 0
        tc 0A5h, 0F3h, 0,   N,   N,   0100h, 0102h, 20, 1234h, 00h, 0, 0
        tc 0A5h, 0F3h, 0,   N,   N,   0100h, 0103h, 20, 1234h, 00h, 0, 0
        tc 0A5h, 0F3h, 0,   N,   N,   0101h, 0100h, 20, 1234h, 00h, 0, 0
        tc 0A5h, 0F3h, 0,   N,   N,   0102h, 0100h, 20, 1234h, 00h, 0, 0
        tc 0A5h, 0F3h, DF,  N,   N,   0100h, 00FFh, 20, 1234h, 00h, 0, 0
        tc 0A5h, 0F3h, DF,  N,   N,   0100h, 00FEh, 20, 1234h, 00h, 0, 0
        tc 0A5h, 0F3h, DF,  N,   N,   0100h, 0101h, 20, 1234h, 00h, 0, 0
        tc 0A5h, 0F3h, 0,   N,   N+1, 0110h, 0101h, 20, 1234h, 00h, 0, 0
        tc 0A5h, 0F3h, 0,   NX,  NX,  00F1h, 00F2h, 20, 1234h, 00h, 0, 0
        tc 0A5h, 0F3h, DF,  NX,  NX,  0109h, 0108h, 20, 1234h, 00h, 0, 0
        tc 0A5h, 0F2h, 0,   N,   E,   0100h, 0200h, 10, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, OV,  DCY, E,   0100h, 0200h, 20, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, OV2, DCY, EX,  00F7h, 0200h, 20, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, 0,   NX,  TXT, 00F1h, 01F0h, 24, 1234h, 80h, 0, 0
        tc 0A5h, 0F3h, DF,  NX,  TXT, 0110h, 0211h, 20, 1234h, 80h, 0, 0
; REP STOSB, REP STOSW
        tc 0AAh, 0F3h, 0,   N,   E,   0100h, 0200h, 20, 12ABh, 80h, 0, 0
        tc 0AAh, 0F3h, 0,   N,   E,   0100h, 0200h, 0, 12ABh, 80h, 0, 0
        tc 0AAh, 0F3h, 0,   N,   E,   0100h, 0200h, 1, 12ABh, 80h, 0, 0
        tc 0AAh, 0F3h, 0,   N,   E,   0100h, 0200h, 2, 12ABh, 80h, 0, 0
        tc 0AAh, 0F3h, DF,  N,   E,   0100h, 0200h, 20, 12ABh, 80h, 0, 0
        tc 0AAh, 0F3h, 0,   N,   EX,  0100h, 00F8h, 20, 12ABh, 80h, 0, 0
        tc 0AAh, 0F3h, 0,   N,   EX,  0100h, 00FFh, 20, 12ABh, 80h, 0, 0
        tc 0AAh, 0F3h, 0,   N,   EX,  0100h, 00FEh, 2, 12ABh, 80h, 0, 0
        tc 0AAh, 0F3h, 0,   N,   E,   0100h, 0FFF8h, 20, 12ABh, 80h, 0, 0
        tc 0AAh, 0F3h, 0,   N,   E,   0100h, 0FFFFh, 20, 12ABh, 80h, 0, 0
        tc 0AAh, 0F3h, DF,  N,   EX,  0100h, 0105h, 20, 12ABh, 80h, 0, 0
        tc 0AAh, 0F3h, DF,  N,   E,   0100h, 0005h, 20, 12ABh, 80h, 0, 0
        tc 0AAh, 0F2h, 0,   N,   E,   0100h, 0200h, 10, 12ABh, 80h, 0, 0
        tc 0AAh, 0F3h, 0,   N,   TXT, 0100h, 01F8h, 40, 12ABh, 80h, 0, 0
        tc 0ABh, 0F3h, 0,   N,   E,   0100h, 0200h, 20, 12ABh, 80h, 0, 0
        tc 0ABh, 0F3h, 0,   N,   E,   0100h, 0200h, 0, 12ABh, 80h, 0, 0
        tc 0ABh, 0F3h, 0,   N,   E,   0100h, 0200h, 1, 12ABh, 80h, 0, 0
        tc 0ABh, 0F3h, 0,   N,   E,   0100h, 0200h, 2, 12ABh, 80h, 0, 0
        tc 0ABh, 0F3h, DF,  N,   E,   0100h, 0200h, 20, 12ABh, 80h, 0, 0
        tc 0ABh, 0F3h, 0,   N,   EX,  0100h, 00F8h, 20, 12ABh, 80h, 0, 0
        tc 0ABh, 0F3h, 0,   N,   EX,  0100h, 00F7h, 20, 12ABh, 80h, 0, 0
        tc 0ABh, 0F3h, 0,   N,   EX,  0100h, 00FFh, 1, 12ABh, 80h, 0, 0
        tc 0ABh, 0F3h, 0,   N,   EX,  0100h, 00FDh, 2, 12ABh, 80h, 0, 0
        tc 0ABh, 0F3h, 0,   N,   E,   0100h, 0FFF8h, 20, 12ABh, 80h, 0, 0
        tc 0ABh, 0F3h, 0,   N,   E,   0100h, 0FFF7h, 20, 12ABh, 80h, 0, 0
        tc 0ABh, 0F3h, DF,  N,   EX,  0100h, 0107h, 20, 12ABh, 80h, 0, 0
        tc 0ABh, 0F3h, DF,  N,   E,   0100h, 0005h, 20, 12ABh, 80h, 0, 0
        tc 0ABh, 0F2h, 0,   N,   E,   0100h, 0200h, 10, 12ABh, 80h, 0, 0
        tc 0ABh, 0F3h, 0,   N,   TXT, 0100h, 01F1h, 24, 12ABh, 80h, 0, 0
; REP LODSB, REP LODSW
        tc 0ACh, 0F3h, 0,   N,   E,   0100h, 0200h, 5, 12ABh, 80h, 0, 0
        tc 0ACh, 0F3h, DF,  NX,  E,   0102h, 0200h, 5, 12ABh, 80h, 0, 0
        tc 0ACh, 0F3h, 0,   N,   E,   0100h, 0200h, 0, 12ABh, 80h, 0, 0
        tc 0ADh, 0F3h, 0,   NX,  E,   00FBh, 0200h, 5, 12ABh, 80h, 0, 0
        tc 0ADh, 0F3h, DF,  N,   E,   0003h, 0200h, 5, 12ABh, 80h, 0, 0
; REP SCASB (the table of runs: 29h from DI, 2Eh from DI+8, 24h below DI)
        tc 0AEh, 0F3h, RUN, N,   E,   0100h, 0200h, 20, 0029h, 0, 0, 0
        tc 0AEh, 0F3h, RUN, N,   E,   0100h, 0200h, 8, 0029h, 0, 0, 0
        tc 0AEh, 0F3h, RUN, N,   E,   0100h, 0200h, 9, 0029h, 0, 0, 0
        tc 0AEh, 0F3h, RUN, N,   E,   0100h, 0200h, 5, 0029h, 0, 0, 0
        tc 0AEh, 0F3h, RUN, N,   E,   0100h, 0200h, 0, 0029h, 0, 0, 0
        tc 0AEh, 0F3h, RUN, N,   E,   0100h, 0200h, 20, 0077h, 0, 0, 0
        tc 0AEh, 0F2h, RUN, N,   E,   0100h, 0200h, 20, 772Eh, 0, 0, 0
        tc 0AEh, 0F2h, RUN, N,   E,   0100h, 0200h, 9, 002Eh, 0, 0, 0
        tc 0AEh, 0F2h, RUN, N,   E,   0100h, 0200h, 8, 002Eh, 0, 0, 0
        tc 0AEh, 0F2h, RUN, N,   E,   0100h, 0200h, 20, 0077h, 0, 0, 0
        tc 0AEh, 0F2h, RUN, N,   E,   0100h, 0200h, 20, 0029h, 0, 0, 0
        tc 0AEh, 0F2h, RUN, N,   E,   0100h, 0200h, 0, 002Eh, 0, 0, 0
        tc 0AEh, 0F3h, RUN|DF, N, E,  0100h, 0200h, 20, 0029h, 0, 0, 0
        tc 0AEh, 0F2h, RUN|DF, N, E,  0100h, 0200h, 20, 001Fh, 0, 0, 0
        tc 0AEh, 0F3h, RUN, N,   EX,  0100h, 00FCh, 20, 0029h, 0, 0, 0
        tc 0AEh, 0F2h, RUN, N,   EX,  0100h, 00FCh, 20, 0033h, 0, 0, 0
        tc 0AEh, 0F3h, RUN, N,   EX,  0100h, 00F8h, 8, 0029h, 0, 0, 0
        tc 0AEh, 0F3h, RUN, N,   E,   0100h, 0FFFCh, 20, 0029h, 0, 0, 0
        tc 0AEh, 0F2h, RUN, N,   E,   0100h, 0FFFCh, 20, 0033h, 0, 0, 0
        tc 0AEh, 0F2h, RUN|DF, N, EX, 0100h, 0103h, 20, 001Fh, 0, 0, 0
        tc 0AEh, 0F2h, RUN|DF, N, E,  0100h, 0003h, 20, 001Fh, 0, 0, 0
; REP SCASW
        tc 0AFh, 0F3h, RUN, N,   E,   0100h, 0200h, 10, 2929h, 0, 0, 0
        tc 0AFh, 0F3h, RUN, N,   E,   0100h, 0200h, 4, 2929h, 0, 0, 0
        tc 0AFh, 0F2h, RUN, N,   E,   0100h, 0200h, 10, 2E2Eh, 0, 0, 0
        tc 0AFh, 0F2h, RUN, N,   E,   0100h, 0201h, 10, 2E29h, 0, 0, 0
        tc 0AFh, 0F2h, RUN, N,   E,   0100h, 0200h, 10, 7777h, 0, 0, 0
        tc 0AFh, 0F3h, RUN, N,   E,   0100h, 0200h, 0, 2929h, 0, 0, 0
        tc 0AFh, 0F3h, RUN, N,   EX,  0100h, 00FBh, 10, 2929h, 0, 0, 0
        tc 0AFh, 0F2h, RUN, N,   EX,  0100h, 00F9h, 10, 2E2Eh, 0, 0, 0
        tc 0AFh, 0F2h, RUN, N,   E,   0100h, 0FFF9h, 10, 2E2Eh, 0, 0, 0
        tc 0AFh, 0F3h, RUN|DF, N, E,  0100h, 0206h, 10, 2929h, 0, 0, 0
; REP CMPSB (the windows differ by M, and by X as well at K and K+1)
        tc 0A6h, 0F3h, 0,   N,   E,   0100h, 0200h, 20, 1234h, 0, 10, 0FFh
        tc 0A6h, 0F3h, 0,   N,   E,   0100h, 0200h, 20, 1234h, 0, 0, 0
        tc 0A6h, 0F3h, 0,   N,   E,   0100h, 0200h, 20, 1234h, 0, 0, 1
        tc 0A6h, 0F3h, 0,   N,   E,   0100h, 0200h, 20, 1234h, 0, 19, 80h
        tc 0A6h, 0F3h, 0,   N,   E,   0100h, 0200h, 20, 1234h, 0, 20, 80h
        tc 0A6h, 0F3h, 0,   N,   E,   0100h, 0200h, 0, 1234h, 0, 0, 0FFh
        tc 0A6h, 0F2h, 0,   N,   E,   0100h, 0200h, 20, 1234h, 80h, 10, 80h
        tc 0A6h, 0F2h, 0,   N,   E,   0100h, 0200h, 20, 1234h, 80h, 0, 0
        tc 0A6h, 0F2h, 0,   N,   E,   0100h, 0200h, 20, 1234h, 80h, 0, 80h
        tc 0A6h, 0F2h, 0,   N,   E,   0100h, 0200h, 20, 1234h, 80h, 19, 80h
        tc 0A6h, 0F2h, 0,   N,   E,   0100h, 0200h, 0, 1234h, 80h, 0, 80h
        tc 0A6h, 0F3h, DF,  N,   E,   0100h, 0200h, 20, 1234h, 0, -5, 0FFh
        tc 0A6h, 0F2h, DF,  N,   E,   0100h, 0200h, 20, 1234h, 80h, -9, 80h
        tc 0A6h, 0F3h, 0,   NX,  EX,  00F8h, 00F3h, 24, 1234h, 0, 15, 0FFh
        tc 0A6h, 0F3h, 0,   NX,  EX,  00F8h, 00F3h, 24, 1234h, 0, 0, 0
        tc 0A6h, 0F3h, 0,   NX,  EX,  00F8h, 00F3h, 24, 1234h, 0, 8, 40h
        tc 0A6h, 0F2h, 0,   NX,  EX,  00FEh, 0100h, 20, 1234h, 80h, 3, 80h
        tc 0A6h, 0F3h, 0,   N,   E,   0FFF8h, 0FFF0h, 24, 1234h, 0, 18, 0FFh
        tc 0A6h, 0F3h, DF,  NX,  EX,  0103h, 0006h, 20, 1234h, 0, -12, 0FFh
        tc 0A6h, 0F3h, OV,  DCY, E,   0100h, 0200h, 20, 1234h, 0, 10, 0FFh
        tc 0A6h, 0F3h, OV2, DCY, E,   0100h, 0200h, 20, 1234h, 0, 10, 0FFh
; REP CMPSW
        tc 0A7h, 0F3h, 0,   N,   E,   0100h, 0200h, 20, 1234h, 0, 10, 0FFh
        tc 0A7h, 0F3h, 0,   N,   E,   0100h, 0200h, 20, 1234h, 0, 11, 0FFh
        tc 0A7h, 0F3h, 0,   N,   E,   0100h, 0200h, 20, 1234h, 0, 0, 0
        tc 0A7h, 0F2h, 0,   N,   E,   0100h, 0200h, 20, 1234h, 80h, 10, 80h
        tc 0A7h, 0F2h, 0,   N,   E,   0100h, 0200h, 20, 1234h, 80h, 0, 0
        tc 0A7h, 0F3h, 0,   NX,  EX,  00F7h, 00F3h, 20, 1234h, 0, 22, 0FFh
        tc 0A7h, 0F3h, 0,   N,   E,   0FFF7h, 0200h, 20, 1234h, 0, 30, 0FFh
        tc 0A7h, 0F3h, DF,  N,   E,   0100h, 0200h, 20, 1234h, 0, -7, 0FFh
        tc 0A7h, 0F3h, 0,   N,   E,   0100h, 0200h, 0, 1234h, 0, 0, 0FFh
        db 0

snapbuf equ $
pbuf    equ snapbuf+2*WIN
