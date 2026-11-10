; egademo.asm - EGADEMO.COM: the EGA's 320x200 16-colour mode (0Dh) on XT/GS.
; Sixteen bars filled through set/reset, a lattice drawn a pixel at a time
; in write mode 2, the BIOS's text, and the palette going round until a key.
; tools/build_freedos.py assembles it onto the FreeDOS folder and floppy.
;       nasm -f bin -o EGADEMO.COM egademo.asm
        org 100h

%macro GC 2                     ; graphics controller register %1 = %2
        mov dx, 3CEh
        mov ax, (%2 << 8) | %1
        out dx, ax
%endmacro

start:  mov ax, 000Dh
        int 10h
        mov ah, 0Fh
        int 10h
        cmp al, 0Dh
        je .ega
        mov dx, noega
        mov ah, 09h
        int 21h
        mov ax, 4C01h
        int 21h
.ega:   mov ax, 0A000h
        mov es, ax
        cld

; the bars: set/reset is the colour, on every plane, so the byte written
; does not matter and one REP STOSB is a line of a bar
        GC 1, 0Fh
        xor bl, bl              ; the colour
.bar:   mov dx, 3CEh
        mov al, 0
        mov ah, bl
        out dx, ax
        mov al, bl
        xor ah, ah
        shl ax, 1
        add ax, 24*40+4         ; line 24, two bytes a bar from byte 4
        mov di, ax
        mov dx, 72              ; lines
.line:  mov cx, 2
        rep stosb
        add di, 38
        dec dx
        jnz .line
        inc bl
        cmp bl, 16
        jb .bar
        GC 1, 0

; the lattice: write mode 2, the bit mask choosing the pixel; the read
; before the write loads the latches the mask keeps
        GC 5, 2
        xor si, si              ; x
.dot:   mov bx, si
        and bx, 63
        add bx, 112             ; y going down
        mov ax, si
        mov cl, 4
        shr ax, cl
        and al, 7
        or al, 8                ; the bright eight
        call plot
        mov bx, si
        and bx, 63
        neg bx
        add bx, 175             ; and coming up
        mov ax, si
        mov cl, 5
        shr ax, cl
        and al, 7
        inc al
        call plot
        inc si
        cmp si, 320
        jb .dot
        GC 8, 0FFh
        GC 5, 0

        mov dx, 0105h           ; row 1, column 5
        mov si, title
        mov bl, 15
        call say
        mov dx, 1707h
        mov si, press
        mov bl, 14
        call say

; the palette goes round, a step every other tick, until a key
.turn:  mov ah, 01h
        int 16h
        jnz .key
        xor ah, ah
        int 1Ah
        shr dx, 1
        cmp dx, [tick]
        je .turn
        mov [tick], dx
        inc byte [phase]
        mov bl, 1               ; registers 1-15
.reg:   mov al, bl
        add al, [phase]
        xor ah, ah
        mov cl, 15
        div cl                  ; AH = (register + phase) mod 15
        mov al, ah
        inc al                  ; colours 1-15
        cmp al, 8
        jb .lo
        add al, 8               ; 8-15 are 10h-17h on a 200-line monitor
.lo:    mov bh, al
        mov ax, 1000h
        int 10h
        inc bl
        cmp bl, 16
        jb .reg
        jmp .turn
.key:   xor ah, ah
        int 16h
        mov ax, 0003h
        int 10h
        mov ax, 4C00h
        int 21h

; plot - the pixel at x = SI, y = BX in colour AL (write mode 2)
plot:   push ax
        mov ax, 40
        mul bx
        mov di, si
        mov cl, 3
        shr di, cl
        add di, ax
        mov cx, si
        and cl, 7
        mov ah, 80h
        shr ah, cl
        mov al, 8
        mov dx, 3CEh
        out dx, ax
        pop ax
        mov ah, [es:di]
        mov [es:di], al
        ret

; say - the string at SI at row DH, column DL in colour BL
say:    mov ah, 02h
        mov bh, 0
        int 10h
.ch:    lodsb
        test al, al
        jz .done
        mov ah, 0Eh
        int 10h
        jmp .ch
.done:  ret

title:  db "XT/GS: EGA 320x200, 16 colours", 0
press:  db "the palette turns: press a key", 0
noega:  db "No EGA mode 0Dh here.", 13, 10, "$"
tick:   dw 0
phase:  db 0
