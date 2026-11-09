*----------------------------------------------------------
* keyboard.s - the IIGS keyboard as a PC keyboard: keys go
* into the BIOS data area's ring buffer as scan/ASCII words
* (so programs reading the BDA work too). Also the timer
* tick and the once-a-frame work (svc_vbl).
*
* Mapping (docs/keyboard.md): the IIGS's $08/$15/$0B/$0A
* arrows are PC Left/Right/Up/Down, Delete ($7F) is
* Backspace, Option+digit is F1-F10; everything else by
* scan_tab (gen/tables.s). Control characters keep their
* letter's scan code.
*----------------------------------------------------------
tick_acc   dw 0              ; 18.2 Hz from 60 Hz: += 19886 a frame
vbl_count  dw 0
key_pending dw 0             ; scan code owed after an extended key's 0

* svc_vbl - from the core's slot on a VBL edge (Y saved by the core)
svc_vbl
 mx %00
 phb
 phk
 plb
 jsr kb_poll
 jsr vbl_work
 plb
 rtl

vbl_work                   ; tick, blink, screen flush
 mx %00
 inc vbl_count
 inc blink
 lda tick_acc
 clc
 adc #19886
 sta tick_acc
 bcc :noinc
 lda >H_BDA+BDA_TICKS
 inc
 sta >H_BDA+BDA_TICKS
 bne :noinc
 lda >H_BDA+BDA_TICKS+2
 inc
 sta >H_BDA+BDA_TICKS+2
:noinc
 jmp flush

* vbl_check - while a service waits: on a VBL edge do the frame's work
vbl_check
 mx %00
 lda >VBLBAR
 and #$0080
 cmp vVBL
 beq :same
 sta vVBL
 beq :same                 ; the falling edge
 jmp vbl_work
:same
 rts

* kb_poll - a key from the IIGS keyboard into the BDA buffer
kb_poll
 mx %00
 sep #$20
 mx %10
 lda >KBD
 bpl :none
 and #$7F
 sta sv0
 lda >KBDSTRB              ; clear the strobe
 lda >KEYMOD
 sta sv1
 rep #$20
 mx %00
 jsr kb_flags
 jsr kb_translate
 jmp kb_push
:none
 rep #$20
 mx %00
 rts

* kb_flags - $C025 modifiers -> BDA shift flags
kb_flags
 mx %00
 stz sv2
 lda sv1
 and #$0001                ; shift -> left shift
 beq :c
 lda #$02
 sta sv2
:c
 lda sv1
 and #$0002                ; control
 beq :o
 lda sv2
 ora #$04
 sta sv2
:o
 lda sv1
 and #$0040                ; option -> alt
 beq :k
 lda sv2
 ora #$08
 sta sv2
:k
 lda sv1
 and #$0004                ; caps lock
 beq :w
 lda sv2
 ora #$40
 sta sv2
:w
 sep #$20
 mx %10
 lda sv2
 sta >H_BDA+BDA_KBFLAG
 rep #$20
 mx %00
 rts

* kb_translate - sv0 = ASCII, sv1 = modifiers -> A = scan<<8 | ASCII
kb_translate
 mx %00
 lda sv0
 and #$00FF
 sta sv0
 cmp #$08
 bne :n1
 lda #$4B00                ; Left
 rts
:n1
 cmp #$15
 bne :n2
 lda #$4D00                ; Right
 rts
:n2
 cmp #$0B
 bne :n3
 lda #$4800                ; Up
 rts
:n3
 cmp #$0A
 bne :n4
 lda #$5000                ; Down
 rts
:n4
 cmp #$7F
 bne :n5
 lda #$0E08                ; Backspace
 rts
:n5
 lda sv1
 and #$0040                ; Option + digit = function key
 beq :table
 lda sv0
 cmp #'0'
 bcc :table
 cmp #'9'+1
 bcs :table
 cmp #'0'
 bne :fn
 lda #$4400                ; F10
 rts
:fn
 sec
 sbc #'1'
 clc
 adc #$3B
 xba                       ; scan in the high byte, ASCII 0
 and #$FF00
 rts
:table
 ldx sv0
 lda scan_tab,x
 and #$00FF
 xba
 ora sv0
 rts

* kb_push - A = key word into the BDA ring; dropped when full
kb_push
 mx %00
 sta sv2
 lda >H_BDA+BDA_KBTAIL
 tax
 inx
 inx
 cpx #BDA_KBEND
 bcc :nw
 ldx #BDA_KBBUF
:nw
 txa
 cmp >H_BDA+BDA_KBHEAD
 beq :full
 sta sv3                   ; next tail
 lda >H_BDA+BDA_KBTAIL
 tax
 lda sv2
 sta >H_BDA,x
 lda sv3
 sta >H_BDA+BDA_KBTAIL
:full
 rts

* kb_pop - C=1, A = key word, or C=0 when empty
kb_pop
 mx %00
 lda >H_BDA+BDA_KBHEAD
 cmp >H_BDA+BDA_KBTAIL
 beq :none
 tax
 lda >H_BDA,x
 sta sv2
 inx
 inx
 cpx #BDA_KBEND
 bcc :nw
 ldx #BDA_KBBUF
:nw
 txa
 sta >H_BDA+BDA_KBHEAD
 lda sv2
 sec
 rts
:none
 clc
 rts

* kb_peek - C=1, A = next key word (left in the buffer), or C=0
kb_peek
 mx %00
 lda >H_BDA+BDA_KBHEAD
 cmp >H_BDA+BDA_KBTAIL
 beq :none
 tax
 lda >H_BDA,x
 sec
 rts
:none
 clc
 rts

* kb_wait - A = the next key word, polling until there is one
* (the screen keeps flushing meanwhile)
kb_wait
 mx %00
:loop
 jsr kb_pop
 bcs :got
 jsr kb_poll
 jsr vbl_check
 bra :loop
:got
 rts

* kb_flush - empty the buffer
kb_flush
 mx %00
 lda >H_BDA+BDA_KBTAIL
 sta >H_BDA+BDA_KBHEAD
 stz key_pending
 rts
