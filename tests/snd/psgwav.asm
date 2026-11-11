; psgwav.asm - the Tandy 1000's sound chip and the speaker for the ear
; of tools/psg_test.py (make test-psg), which records what MAME plays
; and measures it: fourteen sounds, each ON ticks of the BIOS's count
; long with OFF ticks of silence after it, so that the recording's bursts
; are the table below in order and their spacing is the timer's rate
; with the chip's oscillators enabled. The table is repeated in
; tools/psg_test.py (SOUNDS): keep the two together.
        cpu 8086
        org 100h
ON      equ 9
OFF     equ 4

start:  cld
        mov ax, 40h
        mov es, ax
        mov al, 0B6h            ; the speaker's pitch: channel 2 at 1193
        out 43h, al
        mov al, 0A9h
        out 42h, al
        mov al, 04h
        out 42h, al
        mov cx, 1               ; from a tick's edge
        call ticks
        mov si, sounds
.next:  lodsb                   ; 0: the chip alone, 1: the speaker too, FFh: the end
        cmp al, 0FFh
        je .done
        mov bl, al
        lodsb
        mov cl, al
        xor ch, ch
        jcxz .nochip
.byte:  lodsb
        out 0C0h, al
        loop .byte
.nochip:
        test bl, bl
        jz .hold
        in al, 61h
        or al, 3
        out 61h, al
.hold:  mov cx, ON
        call ticks
        mov al, 9Fh             ; silence
        out 0C0h, al
        mov al, 0BFh
        out 0C0h, al
        mov al, 0DFh
        out 0C0h, al
        mov al, 0FFh
        out 0C0h, al
        in al, 61h
        and al, 0FCh
        out 61h, al
        mov cx, OFF
        call ticks
        jmp .next
.done:  mov dx, m_done
        mov ah, 9
        int 21h
        mov ax, 4C00h
        int 21h

ticks:  mov ax, [es:6Ch]        ; CX changes of the tick count
.wait:  cmp ax, [es:6Ch]
        je .wait
        loop ticks
        ret

sounds: db 0, 3, 8Eh, 0Fh, 90h                  ;  1 tone 0, period 254: 440.4 Hz
        db 0, 3, 0AAh, 0Ah, 0B0h                ;  2 tone 1, period 170: 658.0 Hz
        db 0, 3, 0CFh, 3Fh, 0D0h                ;  3 tone 2, period 1023: 109.3 Hz
        db 0, 9, 8Eh, 0Fh, 90h, 0AAh, 0Ch, 0B0h, 0CAh, 0Ah, 0D0h  ;  4 a chord: 254, 202, 170
        db 0, 3, 8Eh, 0Fh, 95h                  ;  5 tone 0, 10 dB down
        db 0, 3, 8Eh, 0Fh, 9Ah                  ;  6 tone 0, 20 dB down
        db 0, 2, 0E4h, 0F0h                     ;  7 white noise, 6991 shifts a second
        db 0, 2, 0E6h, 0F0h                     ;  8 white noise, 1748
        db 0, 2, 0E0h, 0F0h                     ;  9 periodic noise: 466.1 Hz
        db 0, 4, 0C4h, 01h, 0E7h, 0F0h          ; 10 white noise at tone 2's rate (period 20): 5593
        db 0, 2, 0E3h, 0F0h                     ; 11 periodic at tone 2's rate: 372.9 Hz
        db 1, 0                                 ; 12 the speaker: 1000.2 Hz
        db 1, 3, 8Eh, 0Fh, 90h                  ; 13 the speaker and tone 0
        db 0, 3, 80h, 02h, 90h                  ; 14 tone 0, period 32: 3495.6 Hz
        db 0FFh
m_done: db 'done', 13, 10, '$'
