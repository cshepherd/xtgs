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
* A Tandy 1000 (TDY_ON) has its sound chip as well, the
* SN76496 at ports C0h-C7h (psg_write, below; docs/tandy.md),
* and there eleven oscillators are enabled, each visited at
* 7,159,090 / 8 / 13 = 68,837 Hz:
*   0, 1   the speaker, as above
*   2-7    the chip's three tones, a pair each
*   8, 9   its noise
*   10     the timer (the highest, as above)
* so the constant of the PIT's division is 13/5 of the other
* there (snd_k), and the timer's oscillator is not always 2
* (snd_to, tmr_r*).
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
FC_KT_LO   = $5555           ; 2^24 * 52 / 3: the same with eleven oscillators
FC_KT_HI   = $1155
N_OSC      = 3               ; oscillators enabled on a PC
N_OSCT     = 11              ; and on a Tandy
PSG_O      = 2               ; the chip's first oscillator
PSG_VOL    = $88             ; each of a voice's oscillators with no attenuation
PSG_MINDIV = 6               ; a tone's period under this (over 18.6 kHz) is silent
PSG_KT_LO  = $0000           ; 2^21 * 13: a tone of period n is FC = this / n at
PSG_KT_HI  = $01A0           ; r = 7 (3,579,545 / 32n Hz; eleven oscillators)
PSG_KP_LO  = $BBBC           ; 2^21 * 13 / 15: the periodic noise, a fifteenth of
PSG_KP_HI  = $001B           ; the shift rate
PSG_KN_LO  = $A000           ; 2^13 * 13: the white noise's shift rate as an FC,
PSG_KN_HI  = $0001           ; r = 7 and a 256-byte table

snd_on     dw 0              ; the DOC is ours (vector hooked, timer running)
snd_ctlr   dw 0              ; GLU control: DOC registers, no auto-increment, volume
snd_oldvec ds 4              ; the firmware's sound-interrupt vector
snd_oldp   dw 0              ; P at open (its I bit is put back at close)
snd_dv     dw 0              ; pit_fc: the count
snd_q      ds 4              ; pit_fc: dividend, then quotient
snd_fc     dw 0              ; pit_fc: the frequency register...
snd_res    dw 0              ; ...and the resolution it is for
snd_t      dw 0
snd_ptr    dw 0              ; pv_setfreq: the wave table's page
doc_lr     dw 0              ; doc_w: the log's entry
snd_k      ds 4              ; pit_fc's constant: FC_K, or FC_KT on a Tandy
snd_n      dw 0              ; oscillators enabled
snd_to     dw 0              ; the timer's oscillator (the last of them)
tmr_rs     dw 0              ; its registers: R_SIZ + snd_to,
tmr_rl     dw 0              ; R_FCL,
tmr_rh     dw 0              ; R_FCH
tmr_rc     dw 0              ; and R_CTL
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
* interrupts off. Keeps A, X and Y.
*----------------------------------------------------------
doc_w
 mx %10
 sta >DOC_REG,x            ; for the judge: the registers as written, and
 pha                       ; the write in its place among the others
 phx
 stx doc_lr
 sta doc_lr+1
 rep #$20
 mx %00
 lda doc_lr
 jsr doc_logw
 sep #$20
 mx %10
 plx
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
* doc_logw - A (a register, and a value in the high byte)
* to the ring DOC_LOG. Interrupts off.
*----------------------------------------------------------
doc_logw
 mx %00
 pha
 lda >DOC_LOGN
 inc
 sta >DOC_LOGN
 dec
 and #DOC_LOGM
 asl
 tax
 pla
 sta >DOC_LOG,x
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
* wave (and on a Tandy the noise), set up the oscillators,
* hook the interrupt and start the timer at channel 0's
* power-on rate. Returns with interrupts enabled. Y is the
* core's.
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
 sta >DOC_SUM
 sta >DOC_LOGN
 ldx #$FE                  ; nothing written yet
:shd
 sta >DOC_REG,x
 dex
 dex
 bpl :shd
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
 cpx #256
 bcc :hi
 lda #$FF                  ; page 1: a pulse, 17 of 256 high, and the rest as
 cpx #256+17               ; far under the middle as leaves no DC: the chip's
 bcc :hi                   ; periodic noise, one in fifteen
 lda #$77
:hi
 sta >GLU_DATA
 inx
 cpx #512
 bcc :wt
 rep #$20
 mx %00
 lda #N_OSC                ; a PC: three oscillators
 sta snd_n
 lda #FC_K_LO
 sta snd_k
 lda #FC_K_HI
 sta snd_k+2
 lda >TDY_ON
 beq :pc
 jsr psg_ntab              ; a Tandy: the chip's noise, and eleven
 lda #N_OSCT
 sta snd_n
 lda #FC_KT_LO
 sta snd_k
 lda #FC_KT_HI
 sta snd_k+2
:pc
 lda snd_n
 sta >DOC_NOSC
 dec
 sta snd_to                ; the timer is the last of them
 clc
 adc #R_SIZ
 sta tmr_rs
 lda snd_to
 clc
 adc #R_FCL
 sta tmr_rl
 lda snd_to
 clc
 adc #R_FCH
 sta tmr_rh
 lda snd_to
 clc
 adc #R_CTL
 sta tmr_rc
 jsr psg_reset
 sep #$20
 mx %10
 lda snd_to                ; the oscillators enabled: (n - 1) * 2
 asl
 ldx #R_OSCENA
 jsr doc_w
 ldx #R_PTR                ; all of them: the table at page 0, 256 bytes
:cfg
 lda #0
 jsr doc_w
 inx
 cpx #R_PTR+N_OSCT
 bcc :cfg
 ldx #R_SIZ
:siz
 lda #7
 jsr doc_w
 inx
 cpx #R_SIZ+N_OSCT
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
 jsr com_close             ; COM1's interrupt goes first (serial.s)
 jsr ms_close              ; and the mouse's goes back on, if it was (mouse.s)
 lda #0
 sta >CTL_LIVE             ; no PC for the desk accessory to restart (control.s)
 jsr st_drop               ; nor a saved state of it
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
 lda snd_k
 sta snd_q
 lda snd_k+2
 sta snd_q+2
 jmp fc_div
:mute
 stz snd_fc
 sec
 rts
:max
 lda snd_k                 ; the constant / 65536, rounded
 asl
 lda snd_k+2
 adc #0
 sta snd_fc
 lda #7
 sta snd_res
 clc
 rts

*----------------------------------------------------------
* div32 - snd_q (32 bits) / snd_dv (16 bits, not 0) -> snd_q.
* Keeps Y.
*----------------------------------------------------------
div32
 mx %00
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
 rts

*----------------------------------------------------------
* fc_div - snd_q / snd_dv as a DOC frequency: snd_fc, and
* snd_res the resolution it is for, 7 less one for each
* halving that brought it under 16 bits. C set (and snd_fc
* 0) when no resolution does. Keeps Y.
*----------------------------------------------------------
fc_div
 mx %00
 jsr div32
 lda #7
 sta snd_res
:norm
 lda snd_q+2
 beq :ok
 lsr snd_q+2
 ror snd_q
 dec snd_res
 bpl :norm
 stz snd_fc
 sec
 rts
:ok
 lda snd_q
 sta snd_fc
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
 ldx tmr_rs
 lda snd_res
 jsr doc_w
 ldx tmr_rl
 lda snd_fc
 jsr doc_w
 ldx tmr_rh
 lda snd_fc+1
 jsr doc_w
 lda tmr_run
 bne :running
 inc tmr_run
 ldx tmr_rc                ; free-run, interrupt enabled, channel 2
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

*----------------------------------------------------------
* The Tandy 1000's sound chip, the SN76496 (docs/tandy.md):
* three square waves and a noise, each with an attenuation,
* written a byte at a time at ports C0h-C7h. A byte with bit
* 7 set names a register in bits 6-4 and gives its low four
* bits; one without gives the high six of the tone period
* last named (or, for the other registers, the four again).
*   0, 2, 4  a tone's period n, ten bits: 3,579,545 / 32n Hz
*            (0 is 1024)
*   1, 3, 5  its attenuation, 2 dB a step, 15 off
*   6        the noise: bits 0-1 the shift rate (a tone's of
*            period 16, 32 or 64, or with 3 tone 2's own),
*            bit 2 white (a 15-bit shift register's output)
*            or periodic (one bit in fifteen)
*   7        the noise's attenuation
* The registers are PSG_REG in the results bank. A voice is
* a pair of DOC oscillators, PSG_O + 2v and the next, one on
* each DOC channel, halted while there is nothing to hear
* and keyed on back to back, which is what keeps the two in
* phase: so a new period halts them, writes it and starts
* them again, and only an attenuation is written as they
* run. pv_* is what the DOC has, by voice * 2.
*
* The noise is DOC RAM $8000-$FFFF: the shift register's
* 32,767 bits and one more, so the whole table (r = 7) is
* the chip's own sequence to within that bit. With tone 2
* as its clock the rate may be anything, and a slow one is
* a shorter table from the same place (the frequency's
* precision is the table's length: psg_noise). A write to
* register 6 starts the chip's register again, and here the
* table. The periodic noise is the pulse at page 1 played
* as a tone of fifteen times the period.
*----------------------------------------------------------
psg_l      dw 0              ; the register last named, * 2
psg_b      dw 0              ; psg_write: the byte
pv_force   dw 0              ; pv_setfreq: start again though nothing changed
pv_fc      ds 8              ; the frequency (0: nothing that can be played)
pv_siz     ds 8              ; R_SIZ's value: the resolution, the table's size
pv_ptr     ds 8              ; the table's page
pv_vol     ds 8              ; the volume the attenuation makes
pv_run     ds 8              ; the pair is running
psg_vtab   dfb PSG_VOL,108,86,68,54,43,34,27,22,17,14,11,9,7,5,0,0   ; PSG_VOL, 2 dB a step
psg_ptab   dfb 254,202,160,127,101,80,64,51,40,32,25,20,16,13,10,0,0 ; the pulse: 254/136 of it

*----------------------------------------------------------
* psg_reset - from svc_sndopen: the chip silent, nothing
* named, no voice running.
*----------------------------------------------------------
psg_reset
 mx %00
 ldx #14
:r
 lda #0
 sta >PSG_REG,x
 dex
 dex
 bpl :r
 lda #$000F
 sta >PSG_REG+2
 sta >PSG_REG+6
 sta >PSG_REG+10
 sta >PSG_REG+14
 lda #0
 sta >PSG_LATCH
 sta >PSG_WRITES
 stz psg_l
 stz pv_force
 ldx #6
:v
 stz pv_fc,x
 stz pv_siz,x
 stz pv_ptr,x
 stz pv_vol,x
 stz pv_run,x
 dex
 dex
 bpl :v
 rts

*----------------------------------------------------------
* psg_ntab - the white noise to DOC RAM $8000-$FFFF: 32,768
* steps of the chip's shift register, fifteen bits with the
* exclusive-or of the lowest two coming in at the top
* (x^15 + x + 1: 32,767 states), a bit a byte, $FF or $01.
* The register is bits 15-1 of snd_q and its output bit 0.
* DOC_SUM is the table's checksum for the judge. Interrupts
* off.
*----------------------------------------------------------
psg_ntab
 mx %00
 sep #$20
 mx %10
:b
 lda >GLU_CTL
 bmi :b
 lda snd_ctlr
 ora #$60                  ; RAM, auto-increment
 sta >GLU_CTL
 lda #0
 sta >GLU_ADRL
 lda #$80
 sta >GLU_ADRH
 rep #$20
 mx %00
 lda #$8000
 sta snd_q
 stz snd_q+2               ; the checksum
 ldx #$8000
:gen
 lda snd_q
 lsr
 eor snd_q
 lsr
 lsr                       ; C = bit 1 xor bit 2
 lda snd_q
 ror
 sta snd_q
 lsr                       ; C = the bit that came out
 lda #$0001
 bcc :lo
 lda #$00FF
:lo
 sta snd_t
 lda snd_q+2               ; rotated left, and the byte added
 asl
 adc snd_t
 sta snd_q+2
 sep #$20
 mx %10
:bz
 lda >GLU_CTL
 bmi :bz
 lda snd_t
 sta >GLU_DATA
 rep #$20
 mx %00
 dex
 bne :gen
 lda snd_q+2
 sta >DOC_SUM
 rts

*----------------------------------------------------------
* psg_write - a byte (tmp0) to the chip, from svc_portout.
* On a PC that is not a Tandy nobody is at the port.
*----------------------------------------------------------
psg_write
 mx %00
 lda >TDY_ON
 beq :no
 lda snd_on
 bne :go
:no
 rts
:go
 lda >PSG_WRITES
 inc
 sta >PSG_WRITES
 stz pv_force
 lda tmp0
 and #$00FF
 sta psg_b
 xba
 ora #DOC_MARK
 php
 sei
 jsr doc_logw
 plp
 lda psg_b
 bit #$0080
 beq :data
 lsr
 lsr
 lsr
 and #$000E                ; the register, as a word's index
 sta psg_l
 tax
 lsr
 sta >PSG_LATCH
 bra :low
:data
 ldx psg_l
 cpx #12
 bcs :low                  ; the noise and its attenuation,
 txa
 and #$0002
 bne :low                  ; a tone's attenuation: the low four bits again
 lda psg_b
 and #$003F
 asl
 asl
 asl
 asl
 sta snd_t
 lda >PSG_REG,x
 and #$000F
 ora snd_t
 sta >PSG_REG,x
 bra :act
:low
 lda >PSG_REG,x
 and #$03F0
 sta snd_t
 lda psg_b
 and #$000F
 ora snd_t
 sta >PSG_REG,x
:act
 cpx #12
 beq :noise
 txa
 and #$0002
 bne :vol
 txa                       ; a tone's period
 lsr
 tay
 jsr psg_tone
 cpy #4
 bne :out
 lda >PSG_REG+12           ; tone 2's, which may be the noise's clock
 and #$0003
 cmp #$0003
 bne :out
 jsr psg_noise
 bra :out
:vol
 txa
 lsr
 and #$0006
 tay
 jsr psg_vcalc
 jsr pv_gate
 bra :out
:noise
 ldy #6                    ; the level first (the pulse has its own), then
 jsr psg_vcalc             ; the table from its start
 inc pv_force
 jsr psg_noise
 stz pv_force
:out
 rts

*----------------------------------------------------------
* psg_tone - tone Y/2's period to its oscillators. Keeps Y.
*----------------------------------------------------------
psg_tone
 mx %00
 tya
 asl
 tax
 lda >PSG_REG,x
 and #$03FF
 bne :n
 lda #$0400                ; 0 is 1024
:n
 cmp #PSG_MINDIV
 bcc :mute
 sta snd_dv
 lda #PSG_KT_LO
 sta snd_q
 lda #PSG_KT_HI
 sta snd_q+2
 jsr fc_div
 bcc :set
:mute
 stz snd_fc
 lda #7
 sta snd_res
:set
 stz snd_ptr               ; the square wave
 jmp pv_setfreq

*----------------------------------------------------------
* psg_noise - register 6 (and tone 2's period, when that is
* the clock) to the noise's oscillators. Y = 6 on the way
* out.
*
* White: the table is 256 << s bytes and r = 7, so a bit
* lasts 2^(16-s) / FC visits and FC = (2^13 * 13 / n) >> s
* for a clock of period n. s is the most that leaves FC
* whole or over 127: the fixed rates play the whole table
* (FC 52, 26 and 13), and a slow clock a shorter one, never
* under two seconds of it.
*----------------------------------------------------------
psg_noise
 mx %00
 lda >PSG_REG+12
 and #$0003
 cmp #$0003
 bne :fixed
 lda >PSG_REG+8            ; tone 2's period
 and #$03FF
 bne :have
 lda #$0400
 bra :have
:fixed
 tax
 lda #16
:sh
 cpx #0
 beq :have
 asl
 dex
 bra :sh
:have
 sta snd_dv
 lda >PSG_REG+12
 and #$0004
 beq :periodic
 lda #PSG_KN_LO
 sta snd_q
 lda #PSG_KN_HI
 sta snd_q+2
 jsr div32
 ldx #0                    ; s
:s
 cpx #7
 bcs :sized
 lda snd_q+2
 bne :half
 lda snd_q
 cmp #128
 bcs :half
 and #$0001
 bne :sized
:half
 lsr snd_q+2
 ror snd_q
 inx
 bra :s
:sized
 lda snd_q
 sta snd_fc
 txa
 asl
 asl
 asl
 ora #$0007
 sta snd_res
 lda #$0080
 sta snd_ptr
 bra :set
:periodic
 lda #PSG_KP_LO
 sta snd_q
 lda #PSG_KP_HI
 sta snd_q+2
 jsr fc_div
 bcc :pok
 stz snd_fc
 lda #7
 sta snd_res
:pok
 lda #$0001
 sta snd_ptr
:set
 ldy #6
 jmp pv_setfreq

*----------------------------------------------------------
* psg_vcalc - voice Y/2's attenuation as its oscillators'
* volume, pv_vol. Keeps Y.
*----------------------------------------------------------
psg_vcalc
 mx %00
 tya
 asl
 tax
 lda >PSG_REG+2,x
 and #$000F
 tax
 cpy #6
 bne :tone
 lda >PSG_REG+12
 and #$0004
 bne :tone                 ; white noise: a tone's levels
 lda psg_ptab,x
 bra :have
:tone
 lda psg_vtab,x
:have
 and #$00FF
 sta pv_vol,y
 rts

*----------------------------------------------------------
* pv_setfreq - voice Y/2 to snd_fc, snd_res (R_SIZ's value)
* and snd_ptr: nothing when that is what it has (unless
* pv_force), or else halted, written and, when there is
* something to hear, started. Keeps Y.
*----------------------------------------------------------
pv_setfreq
 mx %00
 lda pv_force
 bne :do
 lda snd_fc
 cmp pv_fc,y
 bne :do
 lda snd_res
 cmp pv_siz,y
 bne :do
 lda snd_ptr
 cmp pv_ptr,y
 bne :do
 rts
:do
 lda snd_fc
 sta pv_fc,y
 lda snd_res
 sta pv_siz,y
 lda snd_ptr
 sta pv_ptr,y
 php
 sei
 jsr pv_halt
 lda pv_fc,y
 bne :wr
 jmp :gate
:wr
 tya
 clc
 adc #R_SIZ+PSG_O
 tax
 sep #$20
 mx %10
 lda pv_siz,y
 jsr doc_w2
 rep #$20
 mx %00
 tya
 clc
 adc #R_PTR+PSG_O
 tax
 sep #$20
 mx %10
 lda pv_ptr,y
 jsr doc_w2
 rep #$20
 mx %00
 tya
 clc
 adc #R_FCL+PSG_O
 tax
 sep #$20
 mx %10
 lda pv_fc,y
 jsr doc_w2
 rep #$20
 mx %00
 tya
 clc
 adc #R_FCH+PSG_O
 tax
 sep #$20
 mx %10
 lda pv_fc+1,y
 jsr doc_w2
 rep #$20
 mx %00
:gate
 jsr pv_gate
 plp
 mx %00
 rts

*----------------------------------------------------------
* pv_gate - voice Y/2 running, at pv_vol, when it has a
* frequency and a volume, and halted when not. Keeps Y.
*----------------------------------------------------------
pv_gate
 mx %00
 php
 sei
 lda pv_fc,y
 beq :off
 lda pv_vol,y
 beq :off
 tya
 clc
 adc #R_VOL+PSG_O
 tax
 sep #$20
 mx %10
 lda pv_vol,y
 jsr doc_w2
 rep #$20
 mx %00
 lda pv_run,y
 bne :out
 lda #1
 sta pv_run,y
 tya
 clc
 adc #R_CTL+PSG_O
 tax
 sep #$20
 mx %10
 lda #$10                  ; back to back, as the speaker's: the accumulators
 jsr doc_w                 ; start again, so the two are in phase
 inx
 lda #$00
 jsr doc_w
 rep #$20
 mx %00
 bra :out
:off
 jsr pv_halt
:out
 plp
 mx %00
 rts

*----------------------------------------------------------
* pv_halt - voice Y/2's pair halted, if it runs. Interrupts
* off. Keeps Y.
*----------------------------------------------------------
pv_halt
 mx %00
 lda pv_run,y
 beq :out
 lda #0
 sta pv_run,y
 tya
 clc
 adc #R_CTL+PSG_O
 tax
 sep #$20
 mx %10
 lda #$11
 jsr doc_w
 inx
 lda #$01
 jsr doc_w
 rep #$20
 mx %00
:out
 rts

*----------------------------------------------------------
* doc_w2 - DOC registers X and X+1 = A: an oscillator's and
* its partner's. As doc_w; X is one more on the way out.
*----------------------------------------------------------
doc_w2
 mx %10
 jsr doc_w
 inx
 jmp doc_w
