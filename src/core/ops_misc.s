*----------------------------------------------------------
* ops_misc.s - flag instructions, IN/OUT, WAIT, SALC, ESC.
*----------------------------------------------------------

op_F5                      ; cmc
 mx %00
 lda rFL
 eor #F_CF
 sta rFL
 jmp (NEXTVEC)
op_F8                      ; clc
 mx %00
 lda rFL
 and #$FFFF-F_CF
 sta rFL
 jmp (NEXTVEC)
op_F9                      ; stc
 mx %00
 lda rFL
 ora #F_CF
 sta rFL
 jmp (NEXTVEC)
op_FA                      ; cli
 mx %00
 lda rFL
 and #$FFFF-F_IF
 sta rFL
 jmp (NEXTVEC)
op_FB                      ; sti
 mx %00
 lda rFL
 ora #F_IF
 sta rFL
 jmp (NEXTVEC)
op_FC                      ; cld
 mx %00
 lda rFL
 and #$FFFF-F_DF
 sta rFL
 jmp (NEXTVEC)
op_FD                      ; std
 mx %00
 lda rFL
 ora #F_DF
 sta rFL
 jmp (NEXTVEC)
op_9B                      ; wait
 mx %00
 jmp (NEXTVEC)
op_D6                      ; salc (undocumented): AL = CF ? $FF : 0
 mx %00
 sep #$20
 mx %10
 lda rFL
 and #F_CF
 beq :z
 lda #$FF
:z
 sta rAX
 rep #$20
 mx %00
 jmp (NEXTVEC)

*--- ports: mostly open bus. The CGA status register 3DAh is
* special: GW-BASIC (and other CGA code) polls its display-enable
* (bit 0) and vertical-retrace (bit 3) bits and waits on the edges
* before touching video memory. Return a value that toggles both
* each read so those wait loops always terminate promptly.
cga_stat   dw 0
port_in8                   ; A = port -> A = value (8-bit in the low byte)
 mx %00
 cmp #$0060
 beq :kbdata
 cmp #$0064
 beq :kbstat
 cmp #$0040
 beq :pit
 cmp #$0042
 beq :pit
 cmp #$0061
 beq :ppib
 cmp #$03DA
 beq :cgastat
 lda #$00FF
 rts
:ppib                      ; 8255 port B: what was written (the speaker bits a
 lda cga_stat              ; program ORs into), with bits 4 and 5 moving as an
 clc                       ; AT's refresh and timer-2 output do, so a loop that
 adc #$0010                ; waits on either ends
 sta cga_stat
 and #$0030
 sta tmp6
 lda >SPK_PORT
 and #$00CF
 ora tmp6
 rts
:pit                       ; 8253 PIT counter: we don't model the real 1.19 MHz
 lda vICOUNT               ; timer, but a free-running pseudo-random value keeps a
 clc                       ; guest that seeds or samples the PIT (for an RNG or a
 adc >PIT_CTR              ; busy-wait) from stalling. Mix the retired-instruction
 clc                       ; count with an accumulating odd step so reads differ.
 adc #$9E37
 sta >PIT_CTR
 and #$00FF
 rts
:kbdata                    ; 8042 data: pop the next scancode (make/break)
 lda >KBD_QHEAD
 and #KBD_QMASK
 cmp >KBD_QTAIL
 beq :kbempty
 tax
 sep #$20
 mx %10
 lda >KBD_QBUF,x           ; the scancode byte (long,x)
 rep #$20
 mx %00
 and #$00FF
 pha
 txa
 inc
 and #KBD_QMASK
 sta >KBD_QHEAD            ; advance the read index
 pla
 rts
:kbempty
 lda #$0000
 rts
:kbstat                    ; 8042 status: bit0 (OBF) = a scancode is waiting
 lda >KBD_QHEAD
 and #KBD_QMASK
 cmp >KBD_QTAIL
 beq :kbstat0
 lda #$0001
 rts
:kbstat0
 lda #$0000
 rts
:cgastat
 lda cga_stat              ; free-running: all (bit0,bit3) states appear
 inc
 sta cga_stat
 and #$00FF
 rts
port_in16
 mx %00
 cmp #$03DA
 beq :cgastat
 lda #$FFFF
 rts
:cgastat
 lda cga_stat
 inc
 sta cga_stat
 and #$00FF
 ora #$FF00
 rts
port_out                   ; A = port, tmp0 = value
 mx %00
 cmp #$0040                ; 40h-61h: the 8253 (channel 0 the IRQ0 rate, channel 2
 bcc :other                ; the speaker's pitch) and the 8255's port B (speaker
 cmp #$0062                ; gate and data): sound.s plays them on the DOC
 bcs :other
 jsl SVC_BASE+33           ; svc_sndport (keeps Y)
 rts
:other
 cmp #$03D8                ; CGA mode-control register (Lotus sets the mode here)
 beq :mctl
 cmp #$03D9                ; CGA colour-select register
 beq :csel
 rts
:mctl
 lda tmp0
 sta >CGA_MODEREQ
 lda #1
 sta >CGA_MODECHG          ; svc_vbl applies it (switch gfx_mode, keep B800)
 rts
:csel
 lda tmp0                  ; bits 0-3 background/border
 and #$000F
 sta cga_bg
 lda tmp0                  ; bit 4 intensity
 and #$0010
 beq :i0
 lda #1
 sta cga_int
 bra :pal
:i0
 stz cga_int
:pal
 lda tmp0                  ; bit 5 palette select
 and #$0020
 beq :p0
 lda #1
 sta cga_pal
 bra :pd
:p0
 stz cga_pal
:pd
 lda #1
 sta cga_pd
 rts
op_E4                      ; in AL, imm8
 mx %00
 lda [bCS],y
 iny
 and #$00FF
 jsr port_in8
 sep #$20
 mx %10
 sta rAX
 rep #$20
 mx %00
 jmp (NEXTVEC)
op_E5                      ; in AX, imm8
 mx %00
 lda [bCS],y
 iny
 and #$00FF
 jsr port_in16
 sta rAX
 jmp (NEXTVEC)
op_EC                      ; in AL, DX
 mx %00
 lda rDX
 jsr port_in8
 sep #$20
 mx %10
 sta rAX
 rep #$20
 mx %00
 jmp (NEXTVEC)
op_ED                      ; in AX, DX
 mx %00
 lda rDX
 jsr port_in16
 sta rAX
 jmp (NEXTVEC)
op_E6                      ; out imm8, AL
 mx %00
 lda rAX
 and #$00FF
 sta tmp0
 lda [bCS],y
 iny
 and #$00FF
 jsr port_out
 jmp (NEXTVEC)
op_E7                      ; out imm8, AX
 mx %00
 lda rAX
 sta tmp0
 lda [bCS],y
 iny
 and #$00FF
 jsr port_out
 jmp (NEXTVEC)
op_EE                      ; out DX, AL
 mx %00
 lda rAX
 and #$00FF
 sta tmp0
 lda rDX
 jsr port_out
 jmp (NEXTVEC)
op_EF                      ; out DX, AX
 mx %00
 lda rAX
 sta tmp0
 lda rDX
 jsr port_out
 jmp (NEXTVEC)

*--- ESC (8087): decode the operand, do nothing
op_D8
 mx %00
op_D9
op_DA
op_DB
op_DC
op_DD
op_DE
op_DF
 jsr modrm_w
 jmp (NEXTVEC)
