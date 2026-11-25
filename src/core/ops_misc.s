*----------------------------------------------------------
* ops_misc.s - flag instructions, IN/OUT, WAIT, SALC, ESC.
*----------------------------------------------------------

op_F5                      ; cmc
 mx %00
 lda vLP
 eor #LP_CF
 sta vLP
 jmp (NEXTVEC)
op_F8                      ; clc
 mx %00
 lda vLP
 and #$FFFF-LP_CF
 sta vLP
 jmp (NEXTVEC)
op_F9                      ; stc
 mx %00
 lda vLP
 ora #LP_CF
 sta vLP
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
 jmp irq_sti               ; (an interrupt owed: after the next instruction)
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
 lda vLP
 and #LP_CF
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
 bne :n60
 jmp kb_data
:n60
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
 cmp #$03D5
 bne :n3d5
 jmp crtc_data
:n3d5
 ldx vPCMODE               ; Mode B: the 8259, the 8237 and the diskette
 cpx #2                    ; controller (ports.s); a port nobody is at reads FF
 bne :nobody
 jsl SVC_BASE+39           ; svc_portin (keeps Y)
 rts
:nobody
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
 lda #0                    ; (a read makes 3C0h's next write the index: the EGA)
 sta >EGA_ACFF
 lda cga_stat              ; free-running: all (bit0,bit3) states appear
 inc
 sta cga_stat
 and #$00FF
 rts
crtc_data                  ; the 6845's selected register: R12-R17 read back what
 mx %00                    ; was written (a program finds the adapter by writing
 lda >CRTC_IDX             ; the cursor's address and reading it), the others 0
 cmp #12
 bcc :none
 cmp #18
 bcs :none
 tax
 lda >CRTC_REG,x
 and #$00FF
 rts
:none
 lda #0
 rts
kb_data                    ; 8042 data: pop the next scancode (make/break)
 mx %00
 lda #0                    ; (and IRQ1 is no longer in service: the slot may
 sta >PIC_KBIS             ; bring the next one)
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
 bne :ncsel
 jmp :csel
:ncsel
 cmp #$03D4                ; the 6845's register select
 beq :cidx
 cmp #$03D5                ; and the selected register
 beq :creg
 cmp #$03C0                ; 3C0h-3CFh: the EGA's registers (ega.s)
 bcc :notega
 cmp #$03D0
 bcs :notega
 jmp ega_out
:notega
 ldx vPCMODE               ; Mode B: the 8259, the 8237 and the diskette
 beq :nobody               ; controller (ports.s); there and under the .COM
 cpx #2                    ; runner 3DAh-3DFh, the Tandy's video (tandy.s),
 beq :svc                  ; and C0h-C7h, its sound chip (sound.s)
 cmp #$00C8
 bcs :tvid
 cmp #$00C0
 bcs :svc
 rts
:tvid
 cmp #$03DA
 bcc :nobody
 cmp #$03E0
 bcs :nobody
:svc
 jsl SVC_BASE+36           ; svc_portout (keeps Y)
:nobody
 rts
:cidx
 lda tmp0
 and #$001F
 sta >CRTC_IDX
 rts
:creg
 lda >CRTC_IDX
 tax
 sep #$20
 mx %10
 lda tmp0
 sta >CRTC_REG,x
 rep #$20
 mx %00
 cpx #9                    ; the maximum scan line: with 1, text is the 160x100
 bne :curs                 ; mode (svc_vbl looks, as for a 0x3D8 write)
 lda #1
 sta >CGA_MODECHG
 rts
:curs
 cpx #14                   ; the cursor address: the guest moves the cursor
 bcc :cdone                ; itself (the BIOS's own moves take it back)
 cpx #16
 bcs :cdone
 lda #1
 sta >CRTC_CUR
:cdone
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
 lda rDX
 cmp #$03D4
 beq :pair
 cmp #$03CE                ; the EGA's graphics controller
 beq :pair
 cmp #$03C4                ; and its sequencer
 beq :pair
 lda rAX
 sta tmp0
 lda rDX
 jsr port_out
 jmp (NEXTVEC)
:pair                      ; an index and its register in one word: AL selects,
 lda rAX                   ; AH is the value
 and #$00FF
 sta tmp0
 lda rDX
 jsr port_out
 lda rAX
 xba
 and #$00FF
 sta tmp0
 lda rDX
 inc
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

*--- ESC when the PC has an 8087 (docs/8087.md): fpu_start points the
* eight opcodes here. The operand as before, and the instruction is the
* 8087's own image's (src/fpu), which is told which of the eight it is.
fpx_0
 mx %00
 lda #0
 bra fpx
fpx_1
 mx %00
 lda #1
 bra fpx
fpx_2
 mx %00
 lda #2
 bra fpx
fpx_3
 mx %00
 lda #3
 bra fpx
fpx_4
 mx %00
 lda #4
 bra fpx
fpx_5
 mx %00
 lda #5
 bra fpx
fpx_6
 mx %00
 lda #6
 bra fpx
fpx_7
 mx %00
 lda #7
fpx
 mx %00
 pha
 phy                       ; (the IP after the opcode: the 8087 keeps the instruction's address)
 jsr modrm_b               ; (the operand is the 8087's to fetch, whatever its length: no word's bounce)
 plx
 pla
 jsl FPU_BASE+3
 bcs :nmi
 jmp (NEXTVEC)
:nmi                       ; an unmasked exception with the 8087's interrupt enabled: a PC/XT's NMI
 inc jEP                   ; (the frame goes on the stack: the translator told, whatever the page)
 sty rIP
 lda #2
 jsr do_int
 jmp next_ct

* fpu_start - a PC starts (not from a saved state: CORE's bank is in one,
* this table with it, and the 8087's words are in the results bank): its
* 8087, when XTGS.CMD says FPU=8087 and the front end found the image.
* fpu_sync - a PC started from a boot state: the 8087's image, when this PC
* has one, forgets what it knew of SANE (its fp_sync)
fpu_sync
 mx %00
 lda >FPU_ON
 beq :out
 lda >MB_LAYOUT+RG_DATA+RG_DATA
 beq :out
 jsl FPU_BASE+6
:out
 rts

fpu_start
 mx %00
 lda #0
 sta >FPU_ON
 lda >FPU_CFG
 cmp #1
 bne :no
 lda >MB_LAYOUT+RG_DATA+RG_DATA
 beq :no
 jsl FPU_BASE
 ldx #14
:t
 lda :ops,x
 sta optab+$1B0,x          ; (the eight from D8)
 dex
 dex
 bpl :t
:no
 rts
:ops       da fpx_0,fpx_1,fpx_2,fpx_3,fpx_4,fpx_5,fpx_6,fpx_7
