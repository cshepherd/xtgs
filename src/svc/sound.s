*----------------------------------------------------------
* sound.s - the Ensoniq DOC (ES5503) as the PC's 8253 timer
* outputs: channel 2 gated by port 61h is the speaker, and
* channel 0 is IRQ0 (docs/sound.md).
*
* Three oscillators are enabled, so the DOC visits each at
* 7,159,090 / 8 / 5 = 178,977 Hz. All three free-run the same
* 256-byte square wave at DOC RAM $0000 (128 x $FF, 128 x $01:
* a $00 would halt an oscillator):
*   0, 1  the speaker, DOC channels 1 and 0 (both sides of a
*         stereo card), started together
*   2     the timer: volume 0, interrupt enabled. It wraps,
*         and interrupts, at the rate channel 0 is programmed
*         for (18.2 Hz for a count of 65536). It is the highest
*         oscillator enabled, so MAME's extra gain on that one
*         is not heard.
*
* A 256-byte table at resolution r plays SR * FC / 2^(17+r),
* and the PIT's clock is 7,159,090 / 6, so for a count n
*   FC = 2^(17+r) * 20 / (3 * n)
* which is $06AAAAAB / n at r = 7; r drops by one for each
* halving that brings FC under 16 bits (pit_fc).
*
* The timer's interrupt comes through the firmware's sound
* vector ($E1:002C) to snd_irq, which acknowledges it and
* counts it in vTICK in the guest direct page; the core's slot
* turns each into INT 08h (Mode B) and vbl_work into a BDA
* tick (Mode A). A PIC holds one pending IRQ0; vTICK holds up
* to TICK_MAX, because a BIOS service here can take several
* tick periods of host time that are none of the guest's (and
* drops back to one when channel 0 is reprogrammed: ticks owed
* at the old rate are not owed at the new one).
*
* The firmware services an interrupt taken with S outside
* page 1 on page 1 at the same low byte, so page 1 is saved at
* open and put back at close. The GLU's control and address
* registers are shared with the interrupt: every foreground
* routine touches them with interrupts off.
*
* Every routine states its M/X: called in the wrong width, an
* immediate's extra $00 executes as BRK (which is what kept
* the first attempt at this silent).
*----------------------------------------------------------
R_FCL      = $00
R_FCH      = $20
R_VOL      = $40
R_PTR      = $80
R_CTL      = $A0
R_SIZ      = $C0
R_OSCINT   = $E0
R_OSCENA   = $E1
SPK_VOL    = $70             ; each speaker oscillator's volume
TMR_MINDIV = 2048            ; channel 0 no faster than 583 Hz (GW-BASIC asks for 400)
SPK_MINDIV = 64              ; under this (over 18.6 kHz) the speaker is silent
TICK_MAX   = 16              ; IRQ0s held while the guest cannot take them
FC_K_LO    = $AAAB           ; 2^24 * 20 / 3
FC_K_HI    = $06AA

snd_on     dw 0              ; the DOC is ours (vector hooked, timer running)
snd_ctlr   dw 0              ; GLU control: DOC registers, no auto-increment, volume
snd_oldvec ds 4              ; the firmware's sound-interrupt vector
snd_oldp   dw 0              ; P at open (its I bit is put back at close)
snd_dv     dw 0              ; pit_fc: the count
snd_q      ds 4              ; pit_fc: dividend, then quotient
snd_fc     dw 0              ; pit_fc: the frequency register...
snd_res    dw 0              ; ...and the resolution it is for
snd_t      dw 0
pit_acc    dw 3,3            ; access mode, channel 0 and 2: 1 LSB, 2 MSB, 3 both
pit_ff     dw 0,0            ; both: the next byte is the high one
pit_cnt    dw 0,0            ; the count (0 = 65536)
spk_fc     dw 0              ; channel 2 as an FC (0: nothing to play)
spk_res    dw 0
spk_run    dw 0              ; the speaker oscillators are running
tmr_run    dw 0              ; the timer oscillator is running
snd_pg1    ds 256            ; bank $00 page 1 while interrupts are live

*----------------------------------------------------------
* doc_w - DOC register X = A. 8-bit A, 16-bit X, DBR = SVC,
* interrupts off.
*----------------------------------------------------------
doc_w
 mx %10
 pha
:b1
 lda >GLU_CTL
 bmi :b1
 lda snd_ctlr
 sta >GLU_CTL
 txa
 sta >GLU_ADRL
 lda #0
 sta >GLU_ADRH
:b2
 lda >GLU_CTL
 bmi :b2
 pla
 sta >GLU_DATA
 rts

*----------------------------------------------------------
* doc_drain - read the interrupt register until nothing is
* pending (bit 7 set). The GLU returns a read on the access
* after it, so the address is moved off $E0 first: the second
* read must not acknowledge another oscillator. 8-bit A, any
* DBR (the interrupt calls it), interrupts off. Gives up after
* 64 rounds rather than hang on a register that never clears.
*----------------------------------------------------------
doc_drain
 mx %10
 ldx #64
:again
 lda >GLU_CTL
 bmi :again
 lda >snd_ctlr
 sta >GLU_CTL
 lda #R_OSCINT
 sta >GLU_ADRL
 lda #0
 sta >GLU_ADRH
 lda >GLU_DATA             ; starts the read
 lda #0
 sta >GLU_ADRL
:busy
 lda >GLU_CTL
 bmi :busy
 lda >GLU_DATA             ; the $E0 value
 bmi :done
 dex
 bne :again
:done
 rts

*----------------------------------------------------------
* doc_haltall - halt all 32 oscillators. 8-bit A, 16-bit X.
*----------------------------------------------------------
doc_haltall
 mx %10
 ldx #R_CTL
:h
 lda #$01
 jsr doc_w
 inx
 cpx #R_CTL+32
 bcc :h
 rts

*----------------------------------------------------------
* svc_sndopen - take the DOC: silence it, load the square
* wave, set up the three oscillators, hook the interrupt and
* start the timer at channel 0's power-on rate. Returns with
* interrupts enabled. Y is the core's.
*----------------------------------------------------------
svc_sndopen
 mx %00
 phb
 phk
 plb
 phy
 lda snd_on
 beq :go
 jmp :out
:go
 sep #$20
 mx %10
 php
 pla
 sta snd_oldp
 rep #$20
 mx %00
 sei
 ldx #$FE                  ; page 1 as the loader left it
:pg
 lda >$000100,x
 sta snd_pg1,x
 dex
 dex
 bpl :pg
 lda #3
 sta pit_acc
 sta pit_acc+2
 stz pit_ff
 stz pit_ff+2
 stz pit_cnt
 stz pit_cnt+2
 stz spk_fc
 stz spk_run
 stz tmr_run
 stz vTICK
 lda #0
 sta >SPK_PORT
 sta >DOC_IRQS
 sta >DOC_DROPS
 sep #$20
 mx %10
 lda >MVOLSHAD             ; the Control Panel's volume
 and #$0F
 bne :vol
 lda #6                    ; unset: a moderate level
:vol
 sta snd_ctlr
 jsr doc_haltall
 ldx #R_VOL
:zv
 lda #0
 jsr doc_w
 inx
 cpx #R_VOL+32
 bcc :zv
 jsr doc_drain
:b1
 lda >GLU_CTL              ; the square wave to DOC RAM $0000
 bmi :b1
 lda snd_ctlr
 ora #$60                  ; RAM, auto-increment
 sta >GLU_CTL
 lda #0
 sta >GLU_ADRL
 sta >GLU_ADRH
 ldx #0
:wt
 lda >GLU_CTL
 bmi :wt
 lda #$FF
 cpx #128
 bcc :hi
 lda #$01
:hi
 sta >GLU_DATA
 inx
 cpx #256
 bcc :wt
 ldx #R_OSCENA             ; three oscillators: (3 - 1) * 2
 lda #4
 jsr doc_w
 ldx #R_PTR                ; all three: the table at page 0, 256 bytes
:cfg
 lda #0
 jsr doc_w
 inx
 cpx #R_PTR+3
 bcc :cfg
 ldx #R_SIZ
:siz
 lda #7
 jsr doc_w
 inx
 cpx #R_SIZ+3
 bcc :siz
 ldx #R_VOL
 lda #SPK_VOL
 jsr doc_w
 ldx #R_VOL+1
 lda #SPK_VOL
 jsr doc_w
 rep #$20
 mx %00
 lda >DOCVEC               ; hook the interrupt: JML snd_irq
 sta snd_oldvec
 lda >DOCVEC+2
 sta snd_oldvec+2
 lda #$005C
 sta >DOCVEC
 lda #snd_irq
 sta >DOCVEC+1
 sep #$20
 mx %10
 lda #^snd_irq
 sta >DOCVEC+3
 rep #$20
 mx %00
 lda #1
 sta snd_on
 jsr tmr_apply             ; a count of 0: 18.2 Hz
 jsr clk_init              ; the guest starts now: the time of day again (clock.s)
 mx %00
 cli
:out
 ply
 plb
 rtl

*----------------------------------------------------------
* svc_sndclose - halt every oscillator, give the interrupt
* and page 1 back, and the I bit as it was at open.
*----------------------------------------------------------
svc_sndclose
 mx %00
 phb
 phk
 plb
 lda snd_on
 beq :out
 sei
 stz snd_on
 sep #$20
 mx %10
 jsr doc_haltall
 jsr doc_drain
 rep #$20
 mx %00
 lda snd_oldvec
 sta >DOCVEC
 lda snd_oldvec+2
 sta >DOCVEC+2
 ldx #$FE
:pg
 lda snd_pg1,x
 sta >$000100,x
 dex
 dex
 bpl :pg
 stz vTICK
 lda snd_oldp
 and #$0004
 bne :out                  ; interrupts were off at open: leave them off
 cli
:out
 plb
 rtl

*----------------------------------------------------------
* snd_irq - the firmware's sound-interrupt dispatch JMLs
* here (emulation mode if the interrupt came during a ROM or
* ProDOS call: the mode is kept in the carry from XCE and
* given back). Acknowledge the timer oscillator and flag the
* tick. Nothing here depends on DBR or D. Carry clear on the
* way out: the interrupt was ours.
*----------------------------------------------------------
snd_irq
 mx %00
 php
 clc
 xce                       ; native; C = the mode we came in
 php
 rep #$30
 mx %00
 pha
 phx
 sep #$20
 mx %10
 jsr doc_drain
 rep #$20
 mx %00
 lda >GUEST_DP+vTICK       ; one more IRQ0 owed, up to TICK_MAX
 cmp #TICK_MAX
 bcs :full
 inc
 sta >GUEST_DP+vTICK
 bra :count
:full
 lda >DOC_DROPS
 inc
 sta >DOC_DROPS
:count
 lda >DOC_IRQS
 inc
 sta >DOC_IRQS
 plx
 pla
 plp                       ; C = the mode we came in
 xce
 plp
 clc
 rtl

*----------------------------------------------------------
* pit_fc - A = an 8253 count (0 = 65536) -> snd_fc/snd_res,
* the DOC frequency and resolution that play it. C set (and
* snd_fc 0) when the count is under SPK_MINDIV.
*----------------------------------------------------------
pit_fc
 mx %00
 sta snd_dv
 cmp #0
 beq :max
 cmp #SPK_MINDIV
 bcc :mute
 lda #FC_K_LO
 sta snd_q
 lda #FC_K_HI
 sta snd_q+2
 lda #0                    ; the remainder (17 bits with the carry)
 ldx #32
:div
 asl snd_q
 rol snd_q+2
 rol
 bcs :sub
 cmp snd_dv
 bcc :no
:sub
 sbc snd_dv
 inc snd_q
:no
 dex
 bne :div
 lda #7
 sta snd_res
:norm
 lda snd_q+2
 beq :ok
 lsr snd_q+2
 ror snd_q
 dec snd_res
 bpl :norm
:mute
 stz snd_fc
 sec
 rts
:ok
 lda snd_q
 sta snd_fc
 clc
 rts
:max
 lda #FC_K_HI+1            ; $06AAAAAB / 65536, rounded
 sta snd_fc
 lda #7
 sta snd_res
 clc
 rts

*----------------------------------------------------------
* tmr_apply - channel 0's count to the timer oscillator,
* started if it is not running.
*----------------------------------------------------------
tmr_apply
 mx %00
 lda snd_on
 beq :out
 lda pit_cnt
 beq :go                   ; 0 is 65536
 cmp #TMR_MINDIV
 bcs :go
 lda #TMR_MINDIV
:go
 jsr pit_fc
 php
 sei
 sep #$20
 mx %10
 ldx #R_SIZ+2
 lda snd_res
 jsr doc_w
 ldx #R_FCL+2
 lda snd_fc
 jsr doc_w
 ldx #R_FCH+2
 lda snd_fc+1
 jsr doc_w
 lda tmr_run
 bne :running
 inc tmr_run
 ldx #R_CTL+2              ; free-run, interrupt enabled, channel 2
 lda #$28
 jsr doc_w
:running
 rep #$20
 mx %00
 lda vTICK                 ; a new rate: of the ticks owed at the old
 cmp #2                    ; one, keep the one a PIC would hold
 bcc :few
 lda #1
 sta vTICK
:few
 plp
 mx %00
:out
 rts

*----------------------------------------------------------
* spk_update - the speaker oscillators to what channel 2 and
* port 61h ask for: playing when the gate and the speaker
* enable are both set and the count is playable.
*----------------------------------------------------------
spk_update
 mx %00
 lda snd_on
 beq :out
 lda spk_fc
 beq :off
 lda >SPK_PORT
 and #$0003
 cmp #$0003
 bne :off
 php
 sei
 sep #$20
 mx %10
 ldx #R_SIZ
 lda spk_res
 jsr doc_w
 ldx #R_SIZ+1
 lda spk_res
 jsr doc_w
 ldx #R_FCL
 lda spk_fc
 jsr doc_w
 ldx #R_FCH
 lda spk_fc+1
 jsr doc_w
 ldx #R_FCL+1
 lda spk_fc
 jsr doc_w
 ldx #R_FCH+1
 lda spk_fc+1
 jsr doc_w
 lda spk_run
 bne :on
 inc spk_run
 ldx #R_CTL                ; key both on, back to back: the accumulators
 lda #$10                  ; restart, so the two stay in phase
 jsr doc_w
 ldx #R_CTL+1
 lda #$00
 jsr doc_w
:on
 plp
 mx %00
:out
 rts
:off
 lda spk_run
 beq :out
 stz spk_run
 php
 sei
 sep #$20
 mx %10
 ldx #R_CTL
 lda #$11
 jsr doc_w
 ldx #R_CTL+1
 lda #$01
 jsr doc_w
 plp
 mx %00
 rts

*----------------------------------------------------------
* pit_data - a byte (tmp0) written to channel X/2's counter
* (X = 0 or 2). C set when that completes a count.
*----------------------------------------------------------
pit_data
 mx %00
 lda tmp0
 and #$00FF
 sta snd_t
 lda pit_acc,x
 cmp #1
 beq :lsb
 cmp #2
 beq :msb
 lda pit_ff,x
 bne :high
 lda pit_cnt,x
 and #$FF00
 ora snd_t
 sta pit_cnt,x
 inc pit_ff,x
 clc
 rts
:high
 stz pit_ff,x
 lda snd_t
 xba
 sta snd_t
 lda pit_cnt,x
 and #$00FF
 ora snd_t
 sta pit_cnt,x
 sec
 rts
:lsb
 lda snd_t
 sta pit_cnt,x
 sec
 rts
:msb
 lda snd_t
 xba
 sta pit_cnt,x
 sec
 rts

*----------------------------------------------------------
* svc_sndport - a guest write to port A (40h-61h), value in
* tmp0: the 8253's channels 0 and 2 and its control word, and
* the 8255's port B (bit 0 timer-2 gate, bit 1 speaker data).
* Y is the core's.
*----------------------------------------------------------
svc_sndport
 mx %00
 phb
 phk
 plb
 phy
 cmp #$0061
 beq :p61
 cmp #$0043
 beq :p43
 cmp #$0042
 beq :p42
 cmp #$0040
 beq :p40
:out
 ply
 plb
 rtl
:p42
 ldx #2
 jsr pit_data
 bcc :out
 lda pit_cnt+2
 jsr pit_fc
 lda snd_fc
 sta spk_fc
 lda snd_res
 sta spk_res
 jsr spk_update
 bra :out
:p40
 ldx #0
 jsr pit_data
 bcc :out
 jsr tmr_apply
 bra :out
:p43
 lda tmp0
 and #$0030                ; 0: a counter-latch command (reads are synthetic)
 beq :out
 lsr
 lsr
 lsr
 lsr
 sta snd_t
 lda tmp0
 and #$00C0
 beq :c0
 cmp #$0080
 bne :out                  ; channel 1 (DRAM refresh): not ours
 lda snd_t
 sta pit_acc+2
 stz pit_ff+2
 bra :out
:c0
 lda snd_t
 sta pit_acc
 stz pit_ff
 bra :out
:p61
 lda tmp0
 and #$00FF
 tax
 eor >SPK_PORT             ; the bits that changed
 sta snd_t
 txa
 sta >SPK_PORT
 lda snd_t
 and #$0003
 beq :out2                 ; (a keyboard acknowledge: bit 7 only)
 and #$0002
 beq :upd
 txa                       ; the speaker bit moved with the gate low:
 and #$0001                ; the cone is driven directly, so click
 bne :upd
 sep #$20
 mx %10
 lda >SPKR
 rep #$20
 mx %00
:upd
 jsr spk_update
:out2
 ply
 plb
 rtl
