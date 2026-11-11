*----------------------------------------------------------
* joystick.s - the Apple joystick as the PC's (docs/joystick.md).
*
* A PC's game port is one byte at 201h. A write of anything
* starts four one-shots whose bits (0-3: stick A's X and Y,
* stick B's) stay 1 for a time that grows with the stick's
* resistance; bits 4-7 are the four buttons, 0 while pressed.
* A program writes, then counts its own loop until the bit
* falls. Here:
*
*   a write   reads the IIGS's paddles 0 and 1 (joy_sample)
*             and gives each axis a number of READS for which
*             its bit stays 1.
*   a read    bit 0 and 1 while those reads last, bits 2 and
*             3 always 1 (there is no second stick), bits 4
*             and 5 the IIGS's buttons 0 and 1 ($C061/$C062,
*             which are also the Open-Apple and Option keys).
*
* How many reads: on a PC it is a time, T = 24 us + 3.6 us for
* each of the paddle's 0-255 (a 85K stick; a PC's are 100K and
* trimmed), and the program's count is T over the time of one
* turn of its loop. The time this machine takes says nothing
* of that, so the loop is measured in the PC's terms instead:
* an 8088 is bound by its fetches, 4 cycles a byte, so a loop
* of L bytes turns in about 4L + 10 cycles of 0.2095 us, and
*
*     reads = (paddle + 7) * 60 / (14 L + 35)
*
* joy_loop finds L at the first read after a write: the first
* short backward jump (LOOP, Jcc, JMP) after the IN that goes
* back to the IN or to within 16 bytes before it. With none
* found L is 5 (IN, TEST, LOOPNZ). So a program with its own
* thresholds for a 4.77 MHz PC gets the counts it expects (a
* 19-byte loop reads 27 at the centre, 1 to 52 end to end; the
* 5-byte one 77), whatever this machine's speed.
*   INT 15h AH=84h  DX=0 the buttons in AL, DX=1 the paddles
*             as they read (0-255) in AX and BX.
*
* With no stick the paddles never time out and read 255. A
* PC is given a joystick from the first sample in which either
* axis is under JOY_OPEN (JOY_HAVE; a stick at rest is near
* 128); until then the port reads FFh as a PC without the
* adapter does, the BIOS answers zeros, and a write looks at
* the paddles only once in sixteen (a look that times out
* takes 3 ms).
*
* The Tandy's joystick port is the same port; so is a PCjr's.
*----------------------------------------------------------
JOY_OPEN   = 250             ; a paddle at or over this is one that is not there
JOY_L0     = 5               ; a read loop's bytes when none is found
JOY_SCAN   = 48              ; bytes after the IN looked at for the loop's jump

joy_cx     dw 0              ; reads of 201h for which bit 0 is still 1
joy_cy     dw 0              ; and bit 1
joy_skip   dw 0              ; writes since the paddles were looked at, with no stick
joy_t      dw 0
joy_new    dw 0              ; a write since the last read: look at the loop
joy_l      dw JOY_L0         ; the read loop's bytes, as last found
joy_div    dw 14*JOY_L0+35   ; 14 L + 35

*--- joy_sample: the two paddles -> JOY_X, JOY_Y (0-255), and JOY_HAVE once
* one is there. The timing loop is John Brooks's GetJoyXY (by way of
* ../ddiigs): both paddles in one pass, a count every 11 cycles on
* average, at 1 MHz (the speed register's bit 7 shifted out and back),
* interrupts off for its three milliseconds at most. The direct page is
* the I/O page while it runs.
joy_sample
 mx %00
 php
 sep #$34                  ; SEI, 8-bit A and X
 mx %11
 phd
 pea $C000
 pld
 bit $70                   ; start the paddles' timers
 lsr $36                   ; 1 MHz
 ldx #1
 xba
 xba
:d0
 lda $64                   ; paddle 0, and paddle 1
 and $65
 bpl :tosolo
 inx
 lda $64
 and $65
 bpl :tosolo
 inx
 lda $64
 and $65
 bpl :tosolo
 inx
 bne :d0
 lda $64                   ; 255: which of them are still high?
 and $65
 bmi :same
 dex
:same
 dex
 txy
 bra :exit
:solox
 bit $64
 bmi :soloxok
 dey
 bra :exit
:soloxok
 inx
 bne :solox
:soloy
 bit $65
 bmi :soloyok
 dex
 bra :exit
:tosolo
 txy
 bit $64
 bmi :soloxok
 bit $65
 bpl :same
:soloyok
 iny
 bne :soloy
 dey
:exit
 rol $36                   ; the speed as it was
 pld
 plp                       ; (X and Y: their high bytes are 0)
 mx %00
 txa
 sta >JOY_X
 tya
 sta >JOY_Y
 lda >JOY_READS
 inc
 sta >JOY_READS
 lda >JOY_X
 cmp #JOY_OPEN
 bcc :have
 lda >JOY_Y
 cmp #JOY_OPEN
 bcs :out
:have
 lda #1
 sta >JOY_HAVE
:out
 rts

*--- joy_trig: a write to 201h.
joy_trig
 mx %00
 lda >JOY_HAVE
 bne :go
 lda joy_skip              ; no stick yet: one look in sixteen
 inc
 and #$000F
 sta joy_skip
 cmp #1
 bne :out
:go
 jsr joy_sample
 lda >JOY_HAVE
 beq :out
 lda >JOY_X
 jsr joy_cnt
 sta joy_cx
 lda >JOY_Y
 jsr joy_cnt
 sta joy_cy
 lda #1
 sta joy_new
:out
 rts
joy_cnt                    ; A = a paddle's 0-255 -> the reads its bit lasts
 mx %00
 clc
 adc #7
 asl
 asl
 sta joy_t                 ; (p + 7) * 4
 asl
 asl
 asl
 asl                       ; * 64
 sec
 sbc joy_t                 ; * 60
 ldx #0                    ; / joy_div (under 1000; the quotient under 256)
:sub
 cmp joy_div
 bcc :done
 sbc joy_div
 inx
 bra :sub
:done
 txa
 bne :ok
 inc
:ok
 rts

*--- joy_loop: Y = the guest's IP after the IN that read the port. Finds the
* loop the IN is in and, when its length is not the one the counts were
* made for, makes them again. Keeps Y.
joy_loop
 mx %00
 phy
 ldx #0                    ; bytes past the IN
:scan
 lda [bCS],y               ; an opcode and what follows it
 bpl :next                 ; a jump back has a negative displacement
 sta joy_t
 and #$00FF
 cmp #$00EB                ; JMP short
 beq :cand
 and #$00FC
 cmp #$00E0                ; LOOPNZ, LOOPZ, LOOP, JCXZ
 beq :cand
 and #$00F0
 cmp #$0070                ; Jcc
 bne :next
:cand
 lda joy_t                 ; how far back from the jump's end: 256 - displacement
 xba
 and #$00FF
 eor #$00FF
 inc
 sta joy_t
 txa                       ; it must reach the IN (X + 2 bytes back at least)
 clc
 adc #2
 cmp joy_t
 beq :in
 bcs :next
:in
 clc
 adc #16                   ; and not go more than 16 bytes before it
 cmp joy_t
 bcc :next
 lda joy_t
 bra :found
:next
 iny
 inx
 cpx #JOY_SCAN
 bcc :scan
 lda #JOY_L0
:found
 ply
 cmp joy_l
 beq :same
 sta joy_l
 asl                       ; 14 L + 35
 sta joy_t
 asl
 asl
 asl
 sec
 sbc joy_t
 clc
 adc #35
 sta joy_div
 lda >JOY_X
 jsr joy_cnt
 sta joy_cx
 lda >JOY_Y
 jsr joy_cnt
 sta joy_cy
:same
 rts

*--- joy_read: a read of 201h -> A. Y = the guest's IP after the IN.
joy_read
 mx %00
 lda >JOY_HAVE
 bne :have
 lda #$00FF
 rts
:have
 lda joy_new
 beq :old
 stz joy_new
 jsr joy_loop
:old
 jsr joy_btn               ; F0 with a 0 for each button down
 ora #$000C
 ldx joy_cx
 beq :x0
 dex
 stx joy_cx
 ora #$0001
:x0
 ldx joy_cy
 beq :y0
 dex
 stx joy_cy
 ora #$0002
:y0
 rts

*--- joy_btn: A = F0h, bit 4 clear while button 0 is down and bit 5 while
* button 1 is; F0h with no stick.
joy_btn
 mx %00
 lda >JOY_HAVE
 beq :none
 lda >BUTN0                ; BUTN0 and, in the high byte, BUTN1: bit 7 = down
 tax
 lda #$00F0
 cpx #$8000
 bcc :n1
 and #$00DF
:n1
 pha
 txa
 and #$0080
 beq :n0
 pla
 and #$00EF
 rts
:n0
 pla
 rts
:none
 lda #$00F0
 rts
