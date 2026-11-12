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
vbl_count  dw 0              ; frames seen (svc_vbl and vbl_check)
key_pending dw 0             ; scan code owed after an extended key's 0
kb_held    dw 0              ; Mode B: scancode of the key that is down (0 = none)
kb_heldt   dw 0              ; vbl_count when its make code was queued
kb_akdt    dw 0              ; vbl_count when any-key-down was last looked at
kb_mods    dw 0              ; Mode B: the Shift and Control bits last sent
KB_MINHOLD = 3               ; frames a key stays down at least

* svc_vbl - from the core's slot on a VBL edge (Y saved by the core)
svc_vbl
 mx %00
 phb
 phk
 plb
 jsr mode_poll             ; a CGA mode-control or 6845 write is pending?
 jsr kb_poll
 jsr ms_poll               ; the mouse (mouse.s)
 jsr rd_poll               ; the shared drive: DOS is up?
 jsr vbl_work
 plb
 rtl

* vbl_work - once a frame: blink, the Mode A ticks, screen flush.
* The tick is the DOC timer oscillator's interrupt (sound.s),
* which counts in vTICK. In Mode B the core's slot turns each
* into INT 08h and the guest's handler counts it; in Mode A
* nothing is delivered to the guest, so they are counted here.
vbl_work
 mx %00
 inc vbl_count
 inc blink
 lda vPCMODE
 cmp #2
 beq :noinc
:tick
 lda vTICK
 beq :noinc
 dec vTICK                 ; (one instruction: the interrupt cannot split it)
 jsr clk_tick
 bra :tick
:noinc
 lda vbl_count
 and #CLK_EVERY
 bne :nosync
 lda vPCMODE               ; (a PC there is: the probe and the vectors have none)
 beq :nosync
 jsr clk_sync              ; ticks lost? (clock.s)
:nosync
 jmp flush

* vbl_check - while a service waits: on a VBL edge do the frame's work
vbl_check
 mx %00
 lda >VBLBAR
 and #$0080
 cmp vVBL
 beq :same
 sta vVBL
 tax                       ; (STA sets no flags) the frame's work is done on
 beq :same                 ; one edge only: entering the blank
 jmp vbl_work
:same
 rts

* kb_poll - a key from the IIGS keyboard into the BDA buffer.
*
* In Mode B the key also goes to the scancode ring as a key that
* stays down (docs/keyboard.md): kb_scpush queues its make code and
* notes it in kb_held, and the break code follows only when the
* IIGS says no key is down any more (bit 7 of $C010, looked at
* once a frame and not before KB_MINHOLD frames). The auto-repeat's
* strobes are the typematic make codes. Reading $C010 also clears
* the strobe, so a key that arrives between the $C000 read and
* that one is lost: a few cycles a frame.
kb_poll
 mx %00
 lda vPCMODE
 cmp #2
 bne :key
 jsr kb_modpoll
:key
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
 pha                       ; the key word (scan<<8 | ascii)
 jsr kb_push               ; -> BDA ring buffer (INT 16h path, unchanged)
 pla
 jmp kb_scpush             ; -> port-0x60 scancode ring (IRQ1/INT 09h path)
:none
 rep #$20
 mx %00
 lda kb_held               ; a key is down for the guest: still down here?
 beq :out
 lda vbl_count
 cmp kb_akdt
 beq :out                  ; looked this frame
 sta kb_akdt
 sec
 sbc kb_heldt
 cmp #KB_MINHOLD
 bcc :out
 sep #$20
 mx %10
 lda >KBDSTRB              ; bit 7: any key down
 rep #$20
 mx %00
 bmi :out                  ; (REP leaves N alone)
 lda kb_held
 ora #$0080
 jsr sc_enq                ; released: the break code
 stz kb_held
:out
 rts

* kb_modpoll - Mode B: Shift and Control are keys of their own on a
* PC, with make and break codes ($2A, $1D) that a program reading
* port 0x60 follows. $C025 shows them live, with or without another
* key. Option is not sent as Alt: it is the function-key layer.
kb_modpoll
 mx %00
 sep #$20
 mx %10
 lda >KEYMOD
 rep #$20
 mx %00
 and #$0003
 cmp kb_mods
 beq :out
 sta sv2                   ; now
 eor kb_mods
 sta sv0                   ; the bits that changed
 lda sv2
 sta kb_mods
 lda sv0
 and #$0001
 beq :ctl
 lda sv2
 and #$0001
 eor #$0001                ; up -> the break bit
 xba
 lsr
 ora #$002A                ; left Shift
 jsr sc_enq
:ctl
 lda sv0
 and #$0002
 beq :out
 lda sv2
 and #$0002
 eor #$0002
 xba
 lsr
 lsr
 ora #$001D                ; Control
 jsr sc_enq
:out
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
 cmp #$08                  ; Left  / Option+Left  = Home
 bne :n1
 lda sv1
 and #$0040
 bne :hm
 lda #$4B00                ; Left
 rts
:hm
 lda #$4700                ; Home
 rts
:n1
 cmp #$15                  ; Right / Option+Right = End
 bne :n2
 lda sv1
 and #$0040
 bne :en
 lda #$4D00                ; Right
 rts
:en
 lda #$4F00                ; End
 rts
:n2
 cmp #$0B                  ; Up    / Option+Up    = PgUp
 bne :n3
 lda sv1
 and #$0040
 bne :pu
 lda #$4800                ; Up
 rts
:pu
 lda #$4900                ; PgUp
 rts
:n3
 cmp #$0A                  ; Down  / Option+Down  = PgDn
 bne :n4
 lda sv1
 and #$0040
 bne :pd
 lda #$5000                ; Down
 rts
:pd
 lda #$5100                ; PgDn
 rts
:n4
 cmp #$7F                  ; Delete: Backspace, Option=Del, Ctrl=Insert
 bne :n5
 lda sv1
 and #$0040
 bne :dl
 lda sv1
 and #$0002
 bne :in
 lda #$0E08                ; Backspace
 rts
:dl
 lda #$5300                ; Del (forward delete)
 rts
:in
 lda #$5200                ; Insert
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

* kb_scpush - A = key word (scancode in the high byte). Queue the make
* code into the hardware-keyboard scancode ring that the core serves at
* port 0x60 and delivers as IRQ1/INT 09h, and note the key as down
* (kb_held); kb_poll queues the break code when it is released. The
* IIGS reports one key, the latest, so a second key releases the first.
* Mode B only (nothing reads port 0x60 in the other modes). Programs
* with their own INT 09h handler (Lotus 1-2-3's KB.DRV, many games)
* read keys this way.
kb_scpush
 mx %00
 pha                       ; save the key word
 lda vPCMODE
 cmp #2
 bne :drop
 pla
 xba
 and #$00FF                ; A = scancode (0 = none)
 beq :done
 sta sv2
 lda kb_held
 beq :make
 cmp sv2
 beq :make                 ; the auto-repeat: the make code again
 ora #$0080                ; another key: the held one's break code
 jsr sc_enq                ; (break = make | $80)
:make
 lda sv2
 jsr sc_enq                ; make code
 lda sv2
 sta kb_held
 lda vbl_count
 sta kb_heldt
:done
 rts
:drop
 pla
 rts

* sc_enq - A low byte = scancode -> the scancode ring (dropped when full)
sc_enq
 mx %00
 and #$00FF
 sta sv3
 lda >KBD_QTAIL
 and #KBD_QMASK
 tax
 lda sv3
 sep #$20
 mx %10
 sta >KBD_QBUF,x           ; store the scancode byte (long,x)
 rep #$20
 mx %00
 txa
 inc
 and #KBD_QMASK
 cmp >KBD_QHEAD            ; next tail == head -> ring full, drop
 beq :full
 sta >KBD_QTAIL
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

* kb_reset - Mode B start: no key is down, no modifier was sent
kb_reset
 mx %00
 stz kb_held
 stz kb_mods
 rts

* kb_flush - empty the buffer
kb_flush
 mx %00
 lda >H_BDA+BDA_KBTAIL
 sta >H_BDA+BDA_KBHEAD
 stz key_pending
 rts
