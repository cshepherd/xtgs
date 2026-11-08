*----------------------------------------------------------
* probe.s - M0: is the guest's 1 MiB really there, and does
* the text screen render?
*
* Writes a byte at every 256th address of $20:0000-$2F:FFFF
* and at every bank's last byte, then reads them all back.
* The value depends on bank and page, so a missing bank or
* one aliasing another shows as mismatches. Then the
* services bank draws the test frame. Returns A = 0 when
* every byte read back; else 1. MB_PROBE_ERRS and
* MB_PROBE_FIRST carry the details.
*----------------------------------------------------------
probe_run
 mx %00
 lda #GUEST_BANK
 sta pEA+2
 stz pEA
 stz tmp2                  ; mismatches
 stz tmp3
 stz tmp4                  ; first mismatch: lo
 stz tmp5                  ; and bank
* Write pass.
:wbank
 stz pEA
:wpage
 jsr probe_value
 sep #$20
 mx %10
 sta [pEA]
 rep #$20
 mx %00
 lda pEA
 clc
 adc #$100
 sta pEA
 bne :wpage
 lda #$FFFF                ; the bank's last byte
 sta pEA
 jsr probe_value
 sep #$20
 mx %10
 sta [pEA]
 rep #$20
 mx %00
 inc pEA+2
 lda pEA+2
 cmp #GUEST_BANK+16
 bcc :wbank
* Read pass.
 lda #GUEST_BANK
 sta pEA+2
:rbank
 stz pEA
:rpage
 jsr probe_check
 lda pEA
 clc
 adc #$100
 sta pEA
 bne :rpage
 lda #$FFFF
 sta pEA
 jsr probe_check
 inc pEA+2
 lda pEA+2
 cmp #GUEST_BANK+16
 bcc :rbank
 lda tmp2
 sta >MB_PROBE_ERRS
 lda tmp4
 sta >MB_PROBE_FIRST
 lda tmp5
 sta >MB_PROBE_FIRST+2
* The screen.
 jsl SVC_BASE              ; init
 jsl SVC_BASE+6            ; test frame into the text buffer
 jsl SVC_BASE+3            ; render it
 lda tmp2
 beq :ok
 lda #1
 rts
:ok
 lda #0
 rts

* probe_value - A (16-bit; low byte meaningful) = the byte
* expected at [pEA]: bank + page, scrambled.
probe_value
 mx %00
 lda pEA+2
 asl
 asl
 asl
 clc
 adc pEA+1
 adc pEA
 eor #$5A
 and #$00FF
 rts

* probe_check - compare [pEA] with its value; count.
probe_check
 mx %00
 jsr probe_value
 sta tmp0
 lda [pEA]
 and #$00FF
 cmp tmp0
 beq :ok
 inc tmp2
 lda tmp3
 bne :ok                   ; first mismatch already noted
 inc tmp3
 lda pEA
 sta tmp4
 lda pEA+2
 sta tmp5
:ok
 rts
