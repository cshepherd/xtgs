; tandyf.asm - a Tandy 1000's pages changed over the way a program does
; that shows one pair and draws in the other (src/svc/tandy.s,
; tdy_setpage; docs/tandy.md): the register written 0C2h, 0D0h, 0C2h...
; forty times, something drawn in the hidden pair before each. XT/GS
; keeps a page's home and takes there only the 256s that were written,
; and brings a page by comparing, so this is the test of that: a word
; across two 256s, across two line banks and across the two halves of
; the window; a run of the string instructions over several 256s; the
; BIOS's pixel; the same thing drawn in both pairs (their 256s are
; alike again) and different things; a frame between some changes and
; none between others. After every change the pair that came back must
; hold what it was left with (four words, and now and then the sum of
; all 32K). Before the forty: an odd page alone at B800, written and
; found again as the second of its pair, and a pair that is both shown
; and drawn in.
;
; It ends on a picture ("video": "tandy9"; tools/tandyshr.py), pages 0
; and 1 shown while the CPU has 2 and 3: the last forty frames drew only
; what changed, so a 256 the screen missed shows.
        cpu 8086
        org 100h

%macro CHK 1                    ; the case passes under this condition
        pushf
        inc word [ncase]
        popf
        j%+1 %%ok
        call fail
%%ok:
%endmacro

%macro PAGEREG 1                ; the page register <- a value
        mov dx, 3DFh
        mov al, %1
        out dx, al
%endmacro

start:  cld
        mov ax, 0009h
        int 10h
        mov ax, 0B800h
        mov es, ax
        PAGEREG 0C2h            ; the CPU has 0 and 1, the screen 2 and 3
        call ground
        PAGEREG 0D0h            ; the CPU has 2 and 3, the screen 0 and 1
        call ground             ; (the same in both)
        call tick

; ---- an odd page alone ---------------------------------------------------
        PAGEREG 0C2h
        mov word [es:41FEh], 1234h      ; in page 1, as the second of its pair
        PAGEREG 0CAh            ; page 1 at B800, nothing at BC00
        cmp word [es:01FEh], 1234h      ; 1
        CHK e
        mov word [es:0200h], 0AA55h
        mov word [es:00FFh], 0BEEFh     ; (a word across two 256s)
        PAGEREG 0C2h            ; and the second of its pair again
        cmp word [es:4200h], 0AA55h     ; 2
        CHK e
        cmp word [es:40FFh], 0BEEFh     ; 3
        CHK e
        cmp word [es:41FEh], 1234h      ; 4
        CHK e

; ---- a pair shown and drawn in --------------------------------------------
        PAGEREG 0D2h            ; 2 and 3 for both
        mov word [es:0520h], 9999h
        call tick
        mov word [es:4520h], 0AAAAh
        mov word [es:25FFh], 0BBBBh
        call tick
        PAGEREG 0D0h            ; and hidden again: the screen has 0 and 1
        cmp word [es:25FFh], 0BBBBh     ; 5
        CHK e

; ---- forty changes ---------------------------------------------------------
        mov byte [cur], 0D0h
        mov word [gen], 0
.turn:  inc word [gen]
        mov ax, [gen]
        mov bx, ax              ; a block where the turn says, six words of it
        mov cl, 8
        shl bx, cl
        add bx, ax
        add bx, ax
        add bx, ax
        and bx, 7FF0h           ; (turn * 259, a multiple of 16)
        mov cx, 6
        mov di, bx
.blk:   stosw
        loop .blk
        mov ax, [gen]           ; a run of 300 words that is the same for two
        shr ax, 1               ; turns running: the two pairs are alike there
        mov bx, ax              ; again after the second
        mov cl, 9
        shl ax, cl
        and ax, 3FFFh
        add ax, 1F00h
        mov di, ax
        mov ax, bx
        mov ah, al
        mov cx, 300
        rep stosw
        test word [gen], 3      ; the BIOS's pixel, one turn in four
        jnz .nopix
        mov ax, [gen]
        mov cx, ax
        shl cx, 1
        shl cx, 1
        mov dx, ax
        mov ah, 0Ch
        and al, 0Fh
        or al, 1
        mov bh, 0
        int 10h
.nopix: mov ax, [gen]
        mov [es:0100h], ax      ; this turn's number, where the next look is
        mov [es:41FFh], ax      ; (last, over whatever the turn drew there):
        mov [es:1FFFh], ax      ; across two 256s of the second half, across
        mov [es:3FFFh], ax      ; two 256s and two line banks, across the halves
        mov bl, [cur]           ; which pair is this: 0 when the CPU has 0 and 1
        and bx, 10h
        shr bx, 1
        shr bx, 1
        shr bx, 1               ; 0 or 2
        mov word [sums+bx], 0FFFFh
        mov ax, [gen]
        and ax, 7
        cmp ax, 6
        jb .nosum
        call sum                ; turns 6, 7, 14, 15...: what it is left with
        mov [sums+bx], ax
.nosum: xor byte [cur], 12h     ; 0D0h <-> 0C2h: the pairs change places
        PAGEREG [cur]
        cmp word [gen], 2
        jb .next
        mov ax, [gen]           ; the pair that came back was drawn last turn
        dec ax
        cmp [es:0100h], ax
        CHK e
        cmp [es:41FFh], ax
        CHK e
        cmp [es:1FFFh], ax
        CHK e
        cmp [es:3FFFh], ax
        CHK e
        mov bl, [cur]
        and bx, 10h
        shr bx, 1
        shr bx, 1
        shr bx, 1
        cmp word [sums+bx], 0FFFFh
        je .next
        call sum
        cmp ax, [sums+bx]
        CHK e
.next:  mov ax, [gen]           ; a frame between two changes in three
        mov bl, 3
        div bl
        or ah, ah
        jz .noframe
        call tick
.noframe:
        cmp word [gen], 40
        jae .over
        jmp .turn
.over:  call tick               ; the CPU has 2 and 3, the screen 0 and 1
        mov word [es:0A00h], 0F0F0h     ; which must not show
        call tick
        call tick

        mov ax, [ncase]         ; "tandyf: N cases, N bad[: n n n]"
        mov di, msg_n
        call dec3
        mov ax, [nbad]
        mov di, msg_b
        call dec3
        mov dx, msg
        mov ah, 9
        int 21h
        mov cx, [nbad]
        cmp cx, 12
        jbe .few
        mov cx, 12
.few:   jcxz .done
        mov si, badlist
.bl:    lodsw
        mov di, num+1
        call dec3
        mov dx, num
        mov ah, 9
        int 21h
        loop .bl
.done:  mov ax, 4C00h
        cmp word [nbad], 0
        je .exit
        inc ax
.exit:  int 21h

; ---- helpers -------------------------------------------------------------
fail:   push ax
        push bx
        mov bx, [nbad]
        inc word [nbad]
        cmp bx, 12
        jae .full
        shl bx, 1
        mov ax, [ncase]
        mov [badlist+bx], ax
.full:  pop bx
        pop ax
        ret

dec3:   mov bx, 100             ; AX (under 1000) as three digits at DI
        xor dx, dx
        div bx
        add al, '0'
        mov [di], al
        mov ax, dx
        mov bl, 10
        div bl
        add ax, '00'
        mov [di+1], ax
        ret

ground: xor di, di              ; the 32K at ES: bands of colour, a word the
        mov cx, 4000h           ; high byte of its own place twice
.g:     mov ax, di
        mov al, ah
        and ax, 7777h
        stosw
        loop .g
        ret

sum:    push bx                 ; AX = the sum of the 32K at ES, word by word
        push cx                 ; (never 0FFFFh: that is "none kept")
        push si
        push ds
        push es
        pop ds
        xor si, si
        xor bx, bx
        mov cx, 4000h
.s:     lodsw
        add bx, ax
        rol bx, 1
        loop .s
        pop ds
        mov ax, bx
        cmp ax, 0FFFFh
        jne .ok
        dec ax
.ok:    pop si
        pop cx
        pop bx
        ret

tick:   mov ah, 0               ; until the BIOS tick count moves
        int 1Ah
        mov si, dx
.l:     mov ah, 0
        int 1Ah
        cmp dx, si
        je .l
        ret

cur:    db 0
gen:    dw 0
sums:   dw 0, 0
ncase:  dw 0
nbad:   dw 0
badlist: times 12 dw 0
msg:    db 'tandyf: '
msg_n:  db '000 cases, '
msg_b:  db '000 bad$'
num:    db ' 000$'
