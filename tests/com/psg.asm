; psg.asm - the Tandy 1000's sound chip, the SN76496 at ports C0h-C7h
; (XTGS.CMD's VIDEO=TANDY; docs/tandy.md), with the speaker and the
; timer going beside it. A program cannot read the chip, so nothing here
; is a case of its own: the bytes are written, and the judge follows
; them through a model of the chip and holds what the DOC was told to
; play against it after every one (the manifest's "psg"; tools/psgdoc.py).
; What is printed is where in the bytes the speaker and the timer change,
; which the manifest repeats, and that the BIOS's ticks still come.
;
; The bytes: three tones by the three forms of OUT and three of the
; ports; every attenuation; a period's high bits alone and low bits
; alone; period 0 (1024) and the periods too short to play; a data byte
; to an attenuation; the noise at its three rates and at tone 2's, tone 2
; moving under it, white and periodic, written again to start it again,
; every attenuation of both;
; and at the end a chord, the noise and the speaker all left sounding.
; On a PC that is not a Tandy (psgpc) nobody is at the ports.
        cpu 8086
        org 100h

%macro PSG 1-2 0C0h             ; a byte to the chip, by the port's number
        mov al, %1
        out %2, al
        inc word [nbytes]
%endmacro

%macro PSGD 1                   ; the same by DX
        mov al, %1
        out dx, al
        inc word [nbytes]
%endmacro

start:  cld
        ; three tones
        PSG 8Eh                 ; tone 0: the period's low four bits,
        PSG 0Fh                 ; and its high six: 0FEh, 440 Hz
        PSG 90h                 ; no attenuation
        PSG 0AAh, 0C1h          ; tone 1: 0AAh, 658 Hz
        PSG 0Ah, 0C1h
        PSG 0B4h, 0C1h          ; 8 dB down
        mov dx, 0C7h
        PSGD 0CFh               ; tone 2: 3FFh, 109 Hz
        PSGD 3Fh
        PSGD 0D8h               ; 16 dB down
        ; every attenuation of tone 0, silence and back
        mov bl, 90h
.att:   mov al, bl
        out 0C0h, al
        inc word [nbytes]
        inc bl
        cmp bl, 0A0h
        jb .att
        PSG 90h
        ; the high six bits alone, after the low four are named once
        PSG 80h
        mov bl, 01h
.hi:    mov al, bl
        out 0C2h, al
        inc word [nbytes]
        add bl, 7
        cmp bl, 40h
        jb .hi
        PSG 00h                 ; period 0: 1024
        ; the low four alone: 1 to 5 cannot be played, 6 and 7 can
        mov bl, 81h
.lo:    mov al, bl
        out 0C0h, al
        inc word [nbytes]
        inc bl
        cmp bl, 88h
        jb .lo
        PSG 8Eh
        PSG 0Fh                 ; 440 Hz again
        PSG 0Fh                 ; (and again: nothing to do)
        ; an attenuation named, then data bytes: its four bits again
        PSG 95h
        PSG 03h
        PSG 4Fh                 ; 15: silent
        PSG 02h
        ; the other voices: the same value, off, on; tone 2's period in parts
        PSG 0B4h
        PSG 0BFh
        PSG 0B0h
        PSG 0C5h                ; 3F5h
        PSG 20h                 ; 205h
        ; the noise: white at the three rates and at tone 2's
        PSG 0E4h
        PSG 0F0h
        PSG 0E5h
        PSG 0E6h
        PSG 0E7h                ; a shift a cycle of tone 2 (period 205h)
        PSG 0C1h                ; tone 2 moves under it: 201h,
        PSG 00h                 ; 1 (too short to play: the noise still goes),
        PSG 0C0h                ; 0 (1024),
        PSG 0CAh
        PSG 08h                 ; 8Ah
        PSG 0DFh                ; tone 2 silent: the noise keeps its clock
        PSG 0E4h                ; the register again, twice: from the start
        PSG 0E4h
        PSG 05h                 ; a data byte to it: 5
        PSG 0F2h
        PSG 07h                 ; and to its attenuation: 7
        ; periodic: one bit in fifteen
        PSG 0E0h
        PSG 0E1h
        PSG 0E2h
        PSG 0E3h                ; at tone 2's rate
        PSG 0C4h
        PSG 01h                 ; which moves: 14h
        PSG 0FAh
        PSG 0F0h
        PSG 0E7h                ; white again: the same attenuation, another level
        PSG 0E3h
        PSG 0FFh                ; off,
        PSG 0E0h                ; written while silent,
        PSG 0F4h                ; and on
        ; every attenuation of the pulse, and of the white noise
        mov bl, 0F0h
.patt:  mov al, bl
        out 0C0h, al
        inc word [nbytes]
        inc bl
        jnz .patt
        PSG 0E5h
        mov bl, 0F0h
.watt:  mov al, bl
        out 0C0h, al
        inc word [nbytes]
        inc bl
        jnz .watt
        PSG 0E0h
        PSG 0F4h
        ; the speaker beside it: channel 2 at 1193 (1000 Hz), gate and data
        mov al, 0B6h
        out 43h, al
        mov al, 0A9h
        out 42h, al
        mov al, 04h
        out 42h, al
        in al, 61h
        or al, 3
        out 61h, al
        mov si, m_spk
        call note
        PSG 0D6h                ; (tone 2 on: the judge looks at each byte)
        ; the timer: channel 0 at 2983 (400 Hz) for sixteen ticks, then 65536
        mov al, 36h
        out 43h, al
        mov al, 0A7h
        out 40h, al
        mov al, 0Bh
        out 40h, al
        mov si, m_t1
        call note
        PSG 0D5h
        mov cx, 16
        call ticks
        mov al, 36h
        out 43h, al
        xor al, al
        out 40h, al
        out 40h, al
        mov si, m_t0
        call note
        PSG 0D6h
        mov cx, 2               ; the ticks still come with every voice going
        call ticks
        mov dx, m_tick
        mov ah, 9
        int 21h
        ; nobody answers a read
        in al, 0C0h
        cmp al, 0FFh
        mov dx, m_rd
        je .rd
        mov dx, m_rdbad
.rd:    mov ah, 9
        int 21h
        ; left sounding: a chord, the noise at tone 2's rate, the speaker
        PSG 92h
        PSG 0A6h
        PSG 0Dh                 ; tone 1: 0D6h, 523 Hz
        PSG 0B4h
        PSG 0E7h
        PSG 0F6h
        mov ax, [nbytes]
        call decimal
        mov dx, m_end
        mov ah, 9
        int 21h
        mov ax, 4C00h
        int 21h

; ticks - wait for CX changes of the BIOS's tick count; "no ticks" and
; out when one does not come
ticks:  push es
        mov ax, 40h
        mov es, ax
.next:  mov ax, [es:6Ch]
        xor bx, bx
        mov di, 8
.wait:  cmp ax, [es:6Ch]
        jne .came
        dec bx
        jnz .wait
        dec di
        jnz .wait
        mov dx, m_none
        mov ah, 9
        int 21h
        mov ax, 4C01h
        int 21h
.came:  loop .next
        pop es
        ret

; note - the message at SI, the number of bytes written so far, a line end
note:   mov dx, si
        mov ah, 9
        int 21h
        mov ax, [nbytes]
        call decimal
        mov dx, m_nl
        mov ah, 9
        int 21h
        ret

; decimal - AX in decimal
decimal: xor cx, cx
        mov bx, 10
.d:     xor dx, dx
        div bx
        push dx
        inc cx
        test ax, ax
        jnz .d
.p:     pop dx
        add dl, '0'
        mov ah, 2
        int 21h
        loop .p
        ret

nbytes: dw 0
m_spk:  db 'speaker 1193 from byte $'
m_t1:   db 'timer 2983 from byte $'
m_t0:   db 'timer 0 from byte $'
m_tick: db 'ticks come', 13, 10, '$'
m_rd:   db 'C0h reads FF', 13, 10, '$'
m_rdbad: db 'C0h does not read FF', 13, 10, '$'
m_none: db 'no ticks', 13, 10, '$'
m_end:  db ' bytes', 13, 10, '$'
m_nl:   db 13, 10, '$'
