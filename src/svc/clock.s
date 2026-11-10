*----------------------------------------------------------
* clock.s - the IIGS clock as the PC's (docs/clock.md).
*
* The date and time are the IIGS's own, read with the Misc
* Tools' ReadTimeHex (both front ends leave the Tool Locator
* and the Misc Tools started while the core runs). The guest
* reads them and cannot set them:
*
*   INT 1Ah AH=02/04   the real-time clock, BCD
*   INT 21h AH=2Ah/2Ch (Mode A) the same, binary
*   0040:006C          the BIOS tick count, set at PC init to
*                      the time of day (clk_init), counted by
*                      IRQ0 (clk_tick: INT 08h in Mode B, the
*                      frame's work in Mode A), wrapped at
*                      midnight with the flag at 0040:0070
*
* A DOS keeps its time from the tick count, and ticks are lost
* here: the DOC timer's interrupts are counted to TICK_MAX and
* no further while a service call runs long (a file read, a
* screen blit). So every CLK_EVERY frames clk_sync compares the
* ticks the clock says went by with the ticks counted, and once
* the count is CLK_STEP ticks short adds what is owed.
*
* The clock reads in whole seconds, so what is owed is known to a
* second (18.2 ticks) and no better: CLK_STEP is just over that, and
* a count that has been moved runs up to a second from where an
* unbroken one would be, in step with the clock's seconds.
*
* The comparison is of amounts gone by, never of the tick count
* with the time of day: a guest that sets its own time (INT 1Ah
* AH=01, or a write to 0040:006C) keeps it, running at the
* clock's rate. A count that runs ahead (a guest that makes
* IRQ0 faster and passes every one on) is left alone.
*----------------------------------------------------------
DAY_LO     = $00B0           ; ticks in a day: $1800B0
DAY_HI     = $0018
CLK_EVERY  = $007F           ; frames between looks at the clock, less one (a mask)
CLK_STEP   = 20              ; ticks owed before the count is moved
CLK_DEBT   = $FFC0           ; the least clk_owed is let fall to (-64)

clk_sec    dw 0              ; ReadTimeHex: minute<<8 | second
clk_hour   dw 0              ; (year - 1900)<<8 | hour
clk_date   dw 0              ; month<<8 | day, both from 0
clk_wday   dw 0              ; weekday<<8 (1 = Sunday)
clk_now    ds 4              ; the clock's time of day in ticks (clk_ticks)
clk_last   ds 4              ; the one before
clk_d      ds 4
clk_owed   ds 4              ; ticks the count is short of the clock (signed)
clk_seen   dw 0              ; ticks counted since the last look
clk_held   dw 0              ; IRQ0s held for the guest (vTICK) at the last look
clk_m      dw 0
clk_n      dw 0

* clk_read - the IIGS's date and time into clk_sec..clk_wday
clk_read
 mx %00
 phd
 phb
 pha                       ; room for the four words
 pha
 pha
 pha
 ldx #$0D03                ; ReadTimeHex
 jsl TOOLS
 rep #$30
 mx %00
 phk
 plb
 pla
 sta clk_sec
 pla
 sta clk_hour
 pla
 sta clk_date
 pla
 sta clk_wday
 plb
 pld
 rts

* clk_mul - A (under 256) times clk_m -> A (16 bits). Uses clk_m, clk_n.
clk_mul
 mx %00
 sta clk_n
 lda #0
:l
 lsr clk_n
 bcc :s
 clc
 adc clk_m
:s
 asl clk_m
 ldx clk_n
 bne :l
 rts

* clk_term - add A (under 256) times X to clk_now
clk_term
 mx %00
 stx clk_m
 jsr clk_mul
 clc
 adc clk_now
 sta clk_now
 bcc :nc
 inc clk_now+2
:nc
 rts

* clk_ticks - read the clock; clk_now = its time of day in BIOS
* ticks, 1193180/65536 a second: 65543 1/3 an hour, 1092.39 a
* minute, 18.21 a second (within a tick and a bit all day).
clk_ticks
 mx %00
 jsr clk_read
 lda #85                   ; the fractions, in 256ths
 sta clk_m
 lda clk_hour
 and #$00FF
 sta clk_now+2             ; (65536 an hour)
 jsr clk_mul
 sta clk_now
 lda clk_sec
 xba
 and #$00FF
 ldx #100
 jsr clk_term
 lda clk_sec
 and #$00FF
 ldx #53
 jsr clk_term
 lda clk_now
 xba
 and #$00FF
 sta clk_now
 lda clk_hour
 and #$00FF
 ldx #7
 jsr clk_term
 lda clk_sec
 xba
 and #$00FF
 ldx #1092
 jsr clk_term
 lda clk_sec
 and #$00FF
 ldx #18
 jmp clk_term

* clk_init - the tick count is the time of day. Twice: after build_bda,
* and from svc_sndopen as the timer starts (what was loaded in between
* took time the count would otherwise begin behind by).
clk_init
 mx %00
 lda #0
 sta >CLK_PAID
 sta >CLK_MADE
 jsr clk_mark
 lda clk_now
 sta >H_BDA+BDA_TICKS
 lda clk_now+2
 sta >H_BDA+BDA_TICKS+2
 rts

* clk_mark - the tick count is right as it stands (it was just set):
* nothing owed, and the amounts gone by are measured from now.
clk_mark
 mx %00
 jsr clk_ticks
 stz clk_owed
 stz clk_owed+2
 stz clk_seen
 lda vTICK
 sta clk_held
 rts

* clk_tick - one IRQ0: the BIOS's count, back to 0 at a day's ticks
clk_tick
 mx %00
 inc clk_seen
 lda >H_BDA+BDA_TICKS
 inc
 sta >H_BDA+BDA_TICKS
 bne :lo
 lda >H_BDA+BDA_TICKS+2
 inc
 sta >H_BDA+BDA_TICKS+2
 rts
:lo
 cmp #DAY_LO
 bne :out
 lda >H_BDA+BDA_TICKS+2
 cmp #DAY_HI
 bne :out
 lda #0
 sta >H_BDA+BDA_TICKS
 sta >H_BDA+BDA_TICKS+2
 bra clk_midnt
:out
 rts

* clk_midnt - one more midnight in the flag INT 1Ah AH=00 hands over
clk_midnt
 mx %00
 sep #$20
 mx %10
 lda >H_BDA+BDA_MIDNT
 inc
 sta >H_BDA+BDA_MIDNT
 rep #$20
 mx %00
 rts

* clk_sync - from vbl_work every CLK_EVERY frames: what the clock
* says went by since the last look, less what was counted, is owed.
clk_sync
 mx %00
 lda clk_now
 sta clk_last
 lda clk_now+2
 sta clk_last+2
 jsr clk_ticks
 sec
 lda clk_now
 sbc clk_last
 sta clk_d
 lda clk_now+2
 sbc clk_last+2
 sta clk_d+2
 bpl :fwd
 clc                       ; midnight went by
 lda clk_d
 adc #DAY_LO
 sta clk_d
 lda clk_d+2
 adc #DAY_HI
 sta clk_d+2
:fwd
 cmp #$000C                ; half a day and more: the IIGS's clock was set
 bcc :sane                 ; back (or far ahead). Leave the guest's time be.
 stz clk_seen
 lda vTICK
 sta clk_held
 rts
:sane
 lda vTICK                 ; an IRQ0 held for the guest is not a lost one:
 tax                       ; counted when it is held, not when it is taken
 sec
 sbc clk_held
 stx clk_held
 clc
 adc clk_seen
 stz clk_seen
 sta clk_n                 ; (signed: fewer may be held now than then)
 ldx #0
 cmp #$8000
 bcc :pos
 dex
:pos
 stx clk_m
 sec
 lda clk_d
 sbc clk_n
 sta clk_d
 lda clk_d+2
 sbc clk_m
 sta clk_d+2
 clc
 lda clk_owed
 adc clk_d
 sta clk_owed
 lda clk_owed+2
 adc clk_d+2
 sta clk_owed+2
 bmi :neg
 bne :add
 lda clk_owed
 cmp #CLK_STEP
 bcc :out
:add
 lda >CLK_PAID
 inc
 sta >CLK_PAID
 lda >CLK_MADE
 clc
 adc clk_owed
 sta >CLK_MADE
 lda >H_BDA+BDA_TICKS+2    ; a count already past a day's ticks is the
 cmp #DAY_HI               ; guest's own business: no midnight for it
 bcc :below
 bne :above
 lda >H_BDA+BDA_TICKS
 cmp #DAY_LO
 bcc :below
:above
 jsr :sum
 bra :paid
:below
 jsr :sum
 lda >H_BDA+BDA_TICKS+2
 cmp #DAY_HI
 bcc :paid
 bne :wrap
 lda >H_BDA+BDA_TICKS
 cmp #DAY_LO
 bcc :paid
:wrap
 sec
 lda >H_BDA+BDA_TICKS
 sbc #DAY_LO
 sta >H_BDA+BDA_TICKS
 lda >H_BDA+BDA_TICKS+2
 sbc #DAY_HI
 sta >H_BDA+BDA_TICKS+2
 jsr clk_midnt
:paid
 stz clk_owed
 stz clk_owed+2
:out
 rts
:neg
 cmp #$FFFF
 bne :clamp
 lda clk_owed
 cmp #CLK_DEBT
 bcs :out
:clamp
 lda #CLK_DEBT
 sta clk_owed
 lda #$FFFF
 sta clk_owed+2
 rts
:sum
 clc
 lda >H_BDA+BDA_TICKS
 adc clk_owed
 sta >H_BDA+BDA_TICKS
 lda >H_BDA+BDA_TICKS+2
 adc clk_owed+2
 sta >H_BDA+BDA_TICKS+2
 rts

* clk_bcd - A (0-99) -> A in BCD. Uses X, clk_n.
clk_bcd
 mx %00
 ldx #0
:l
 cmp #10
 bcc :d
 sbc #10
 inx
 bra :l
:d
 sta clk_n
 txa
 asl
 asl
 asl
 asl
 ora clk_n
 rts

* clk_rtctime - INT 1Ah AH=02: CH hours, CL minutes, DH seconds, BCD
clk_rtctime
 mx %00
 jsr clk_read
 lda clk_hour
 and #$00FF
 jsr clk_bcd
 xba
 sta rCX
 lda clk_sec
 xba
 and #$00FF
 jsr clk_bcd
 ora rCX
 sta rCX
 lda clk_sec
 and #$00FF
 jsr clk_bcd
 xba
 sta rDX                   ; (DL = 0: no daylight saving)
 rts

* clk_rtcdate - INT 1Ah AH=04: CH century, CL year, DH month, DL day, BCD
clk_rtcdate
 mx %00
 jsr clk_read
 lda clk_hour
 xba
 and #$00FF                ; years since 1900
 ldy #19
:c
 cmp #100
 bcc :y
 sbc #100
 iny
 bra :c
:y
 jsr clk_bcd
 sta rCX
 tya
 jsr clk_bcd
 xba
 ora rCX
 sta rCX
 lda clk_date
 and #$00FF
 inc
 jsr clk_bcd
 sta rDX
 lda clk_date
 xba
 and #$00FF
 inc
 jsr clk_bcd
 xba
 ora rDX
 sta rDX
 rts
