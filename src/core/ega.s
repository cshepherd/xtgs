*----------------------------------------------------------
* ega.s - the EGA's planes behind A000 (mode 0Dh, 320x200 in
* 16 colours; docs/ega.md).
*
* A byte of A000 is four bytes, one in each plane (H_EGA and
* H_EGA1-3, src/include/pc.s), and what a read returns or a
* write stores is the graphics controller's doing: latches,
* map mask, bit mask, set/reset, the write and read modes.
* So while mode 0Dh is on (ega_cur) the guest's own bank A
* is not memory to it:
*
* - an instruction with a ModR/M operand there is caught in
*   the effective-address tails (cpu.s: ea_hi, ef_vid), which
*   send the ModR/M byte to ega_trap. The opcode, found from
*   the ModR/M byte's length, says what the instruction does
*   with the operand (eg_class): a read is done at once into
*   vBOUNCE (ega_rd), pEA is pointed at vBOUNCE, and for a
*   write the instruction retires through ega_retire, which
*   puts what the handler left there through ega_wr. The
*   handlers know nothing of it.
* - the string instructions have their opcodes pointed at
*   eg_strop for as long as the mode lasts (ega_sync), which
*   looks where SI and DI are and goes on to the ordinary
*   handler unless one of them is in the planes. Then the
*   work is done an element at a time by eg_movsb ... through
*   ega_rd and ega_wr, or for the moves and fills a program
*   does a screen at a time, by MVN a plane at a time.
* - the ports 3C0h-3CFh are the registers (ega_out); the
*   core keeps what ega_rd and ega_wr need of them in its own
*   bank (eg_derive).
*
* The BIOS (src/svc/ega.s) sets the mode, draws from the
* planes to the SHR screen and has its own way to them; it
* raises EGA_SYNC when it has changed the mode or a register
* and the hypercall's return brings the core up to date.
*
* Not caught: a word at offset $FFFF of its segment, the
* stack, an instruction fetched from A000, and a REP string
* instruction that starts outside the planes and runs into
* them.
*----------------------------------------------------------
ega_cur    dw 0              ; nonzero: mode 0Dh, the planes are trapped
eg_y       dw 0              ; IP kept
eg_m       dw 0              ; the trap: ModR/M byte
eg_c       dw 0              ; the opcode's class (eg_class)
eg_k       dw 0              ; 1 read, 2 write, 3 both
eg_off     dw 0              ; the operand's offset in the planes
eg_w       dw 0
eg_w2      dw 0
eg_sx      dw 0              ; a string instruction's opcode * 2
eg_u       dw 0              ; and which of SI and DI it uses
eg_o       dw 0              ; a run: first offset, bytes
eg_n       dw 0
eg_lo      dw 0
eg_t2      dw 0
eg_es      dw 0              ; bytes an element
eg_p       dw 0              ; the plane, times 4
eg_bit     dw 0              ; and its bit in the map mask
eg_lat     ds 4              ; the latches
eg_pv      ds 4              ; a write: each plane's byte before the function
eg_v       dw 0              ; the data
eg_t       dw 0
* the registers as ega_rd and ega_wr want them (eg_derive); bytes, the
* high halves 0
eg_mm      dw 0              ; map mask: sequencer 2, bits 0-3
eg_bm      dw 0              ; bit mask: graphics controller 8
eg_wmode   dw 0              ; write mode: 5, bits 0-1
eg_rmode   dw 0              ; read mode 1: 5, bit 3
eg_rmap    dw 0              ; read map: 4, bits 0-1
eg_rot     dw 0              ; rotate count: 3, bits 0-2
eg_func    dw 0              ; function: 3, bits 3-4 (0 store, 1 AND, 2 OR, 3 XOR)
eg_sr      dw 0              ; set/reset: 0
eg_esr     dw 0              ; enable set/reset: 1
eg_cc      dw 0              ; colour compare: 2
eg_cdc     dw 0              ; colour don't care: 7
eg_plain   dw 0              ; nonzero: a write is the data in the enabled planes
eg_pl      adrl H_EGA,H_EGA1,H_EGA2,H_EGA3

* ega_trap - the operand at pEA is in the planes. A = the ModR/M byte,
* or $100 for an instruction with none whose opcode is the byte before
* IP (XLAT); the displacement has been fetched and nothing after it.
* Keeps Y; the fast set's callers keep X themselves.
ega_trap
 mx %00
 sta eg_m
 sty eg_y
 cmp #$0100
 bcs :y1
 and #$00C7
 cmp #$0006                ; [disp16]
 beq :d2
 cmp #$0080                ; mod 2
 bcs :d2
 cmp #$0040                ; mod 1
 bcs :d1
 bra :d0
:d2
 dey
:d1
 dey
:d0
 dey
:y1
 dey
 lda [bCS],y               ; the opcode
 ldy eg_y
 and #$00FF
 tax
 lda eg_class,x
 and #$00FF
 sta eg_c
 and #$0007
 bne :some
 rts                       ; nothing done with the operand (LEA, ESC)
:some
 cmp #4
 bcc :have
 beq :g80
 cmp #5
 beq :gF6
 lda eg_m                  ; FE, FF: INC and DEC write
 and #$0030
 beq :rw
 bra :r
:g80
 lda eg_m                  ; 80-83: all but CMP write
 and #$0038
 cmp #$0038
 beq :r
 bra :rw
:gF6
 lda eg_m                  ; F6, F7: NOT and NEG write
 and #$0030
 cmp #$0010
 beq :rw
:r
 lda #1
 bra :have
:rw
 lda #3
:have
 sta eg_k
 lda pEA
 sta eg_off
 lda eg_k
 lsr
 bcc :noread
 ldx eg_off
 jsr ega_rd
 sep #$20
 mx %10
 sta vBOUNCE
 rep #$20
 mx %00
 lda eg_c
 and #$0080
 beq :noread
 ldx eg_off
 inx
 jsr ega_rd
 sep #$20
 mx %10
 sta vBOUNCE+1
 rep #$20
 mx %00
:noread
 lda eg_k
 and #$0002
 beq :nowr
 lda vNEXT
 sta vNEXT2
 lda #ega_retire
 sta vNEXT
:nowr
 lda #GUEST_DP+vBOUNCE
 sta pEA
 stz pEA+2
 ldy eg_y
 rts

* ega_retire - the instruction wrote its operand to vBOUNCE: through
* the graphics controller to the planes with it, and retire.
ega_retire
 mx %00
 lda vNEXT2
 sta vNEXT
 ldx eg_off
 lda vBOUNCE
 jsr ega_wr
 lda eg_c
 and #$0080
 beq :done
 ldx eg_off
 inx
 lda vBOUNCE+1
 jsr ega_wr
:done
 jmp (NEXTVEC)

* eg_mark - the byte at X of the planes was written (ega_wr's end): its
* flag, when it is on the screen, and its 256's in VID_DIRTY.
eg_mark
 mx %10
 rep #$20
 mx %00
 txa
 sec
 sbc >EGA_START
 cmp #EGA_LEN
 bcs :out
 tax
 lda >EGA_DIRTY,x
 ora #$0001
 sta >EGA_DIRTY,x
 txa
 xba
 and #$00FF
 tax
 lda >VID_DIRTY,x
 ora #$0001
 sta >VID_DIRTY,x
:out
 rts

* eg_markrng - the same for the eg_n bytes (not 0) from offset eg_o.
* Y is lost.
eg_markrng
 mx %00
 lda eg_o
 sec
 sbc >EGA_START
 cmp #EGA_LEN
 bcc :in
 eor #$FFFF                ; it starts off the screen: the bytes before
 inc                       ; the screen's first
 cmp eg_n
 bcs :out
 sta eg_t2
 lda eg_n
 sec
 sbc eg_t2
 sta eg_n
 lda #0
:in
 sta eg_lo
 lda #EGA_LEN
 sec
 sbc eg_lo
 cmp eg_n
 bcs :k
 sta eg_n
:k
 ldx eg_lo
 sep #$20
 mx %10
 lda #1
 sta >EGA_DIRTY,x
 rep #$20
 mx %00
 lda eg_n
 dec
 beq :pages
 lda eg_lo
 clc
 adc #<EGA_DIRTY
 tax
 tay
 iny
 lda eg_n
 dec
 dec
 phb
 mvn EGA_DIRTY,EGA_DIRTY
 plb
:pages
 lda eg_lo
 clc
 adc eg_n
 dec
 xba
 and #$00FF
 sta eg_t2                 ; the last 256
 lda eg_lo
 xba
 and #$00FF
 tax
 sep #$20
 mx %10
 lda #1
:pg
 sta >VID_DIRTY,x
 inx
 cpx eg_t2
 bcc :pg
 beq :pg
 rep #$20
 mx %00
:out
 rts

* eg_derive - the registers (bank RES, as the ports or the BIOS wrote
* them) into the core's own. Keeps X and Y.
eg_derive
 mx %00
 sep #$20
 mx %10
 lda >EGA_SEQ+2
 and #$0F
 sta eg_mm
 lda >EGA_GC+8
 sta eg_bm
 lda >EGA_GC+5
 and #$03
 sta eg_wmode
 lda >EGA_GC+5
 and #$08
 sta eg_rmode
 lda >EGA_GC+4
 and #$03
 sta eg_rmap
 lda >EGA_GC+3
 and #$07
 sta eg_rot
 lda >EGA_GC+3
 lsr
 lsr
 lsr
 and #$03
 sta eg_func
 lda >EGA_GC
 and #$0F
 sta eg_sr
 lda >EGA_GC+1
 and #$0F
 sta eg_esr
 lda >EGA_GC+2
 and #$0F
 sta eg_cc
 lda >EGA_GC+7
 and #$0F
 sta eg_cdc
 stz eg_plain
 lda eg_wmode              ; write mode 0,
 ora eg_rot                ; no rotate, function or set/reset,
 ora eg_func
 ora eg_esr
 bne :np
 lda eg_bm                 ; every bit
 cmp #$FF
 bne :np
 inc eg_plain
:np
 rep #$20
 mx %00
 rts

* ega_sync - after a hypercall that raised EGA_SYNC: the registers
* again, and when the mode came or went, the string instructions'
* opcodes to eg_strop or back to their own.
ega_sync
 mx %00
 lda #0
 sta >EGA_SYNC
 jsr eg_derive
 lda >EGA_ON
 cmp ega_cur
 beq :out
 sta ega_cur
 cmp #0
 beq :off
 ldx #22
:on
 lda eg_orig,x
 beq :n1
 lda #eg_strop
 sta optab+$148,x
:n1
 dex
 dex
 bpl :on
 rts
:off
 ldx #22
:o2
 lda eg_orig,x
 beq :n2
 sta optab+$148,x
:n2
 dex
 dex
 bpl :o2
:out
 rts
* A4-AF: the ordinary handlers (A8 and A9 are TEST), what each uses (1
* SI, 2 DI), its place in str_tab, and how it is done under REP
eg_orig    da op_A4,op_A5,op_A6,op_A7,0,0,op_AA,op_AB,op_AC,op_AD,op_AE,op_AF
eg_uses    dw 3,3,3,3,0,0,2,2,1,1,2,2
eg_idx     dw 0,2,4,6,0,0,8,10,12,14,16,18
eg_stab    da eg_movsb,eg_movsw,eg_cmpsb,eg_cmpsw,eg_stosb,eg_stosw,eg_lodsb,eg_lodsw,eg_scasb,eg_scasw
eg_fast    da eg_fmovs,eg_fmovs,eg_rep,eg_rep,eg_fstos,eg_fstos,eg_rep,eg_rep,eg_rep,eg_rep

* ega_out - a write to 3C0h-3CFh: A = the port, tmp0 = the value.
* Keeps Y.
ega_out
 mx %00
 cmp #$03CE
 beq :gci
 cmp #$03CF
 beq :gcd
 cmp #$03C4
 beq :seqi
 cmp #$03C5
 beq :seqd
 cmp #$03C0
 beq :ac
 rts
:gci
 lda tmp0
 and #$000F
 sta >EGA_GCI
 rts
:gcd
 lda >EGA_GCI
 tax
 sep #$20
 mx %10
 lda tmp0
 sta >EGA_GC,x
 rep #$20
 mx %00
 jmp eg_derive
:seqi
 lda tmp0
 and #$0007
 sta >EGA_SEQI
 rts
:seqd
 lda >EGA_SEQI
 tax
 sep #$20
 mx %10
 lda tmp0
 sta >EGA_SEQ,x
 rep #$20
 mx %00
 jmp eg_derive
:ac                        ; the attribute controller: index and data in turn
 lda >EGA_ACFF             ; (a read of 3DAh makes the index next)
 bne :acd
 lda tmp0
 and #$003F
 sta >EGA_ACI
 lda #1
 sta >EGA_ACFF
 rts
:acd
 lda #0
 sta >EGA_ACFF
 lda >EGA_ACI
 and #$001F
 tax
 sep #$20
 mx %10
 lda tmp0
 sta >EGA_AC,x
 rep #$20
 mx %00
 lda #1
 sta >EGA_PALD             ; the flush sets the SHR palette
 rts

*--- the string instructions in mode 0Dh
* eg_strop - A4-A7 and AA-AF while ega_cur: X = the opcode * 2.
eg_strop
 mx %00
 stx eg_sx
 lda eg_uses-$148,x
 sta eg_u
 lsr
 bcc :dst
 jsr str_src               ; (A = the pointer's bank word)
 cmp #^H_EGA
 beq :ega
:dst
 lda eg_u
 and #$0002
 beq :norm
 jsr str_dst0
 cmp #^H_EGA
 beq :ega
:norm
 ldx eg_sx
 jmp (eg_orig-$148,x)
:ega
 ldx eg_sx
 lda eg_idx-$148,x
 sta tmp7
 lda vREP
 bne :rep
 jsr eg_call
 jmp (NEXTVEC)
:rep
 lda rCX
 bne :some
 jmp next_ct
:some
 ldx tmp7
 jmp (eg_fast,x)

* eg_rep - REP, an element at a time (rep_slow's loop)
eg_rep
 mx %00
 jsr eg_call
 dec rCX
 beq :done
 ldx tmp7
 lda str_cond,x
 beq eg_rep
 lda vREP
 cmp #$F3
 beq :repe
 lda vLP                   ; REPNE: stop once equal
 and #LP_ZF
 beq eg_rep
:done
 jmp next_ct
:repe
 lda vLP                   ; REPE: stop once not equal
 and #LP_ZF
 bne eg_rep
 jmp next_ct
eg_call
 mx %00
 ldx tmp7
 jmp (eg_stab,x)

* A byte at (override|DS):SI or ES:DI, read or written wherever it is.
* A word is its low byte and then its high one, each on its own, as
* the 8088 does it.
eg_srcb                    ; A = the byte at SI
 mx %00
 jsr str_src
 cmp #^H_EGA
 bne :ram
 ldx pSRC
 jmp ega_rd
:ram
 lda [pSRC]
 and #$00FF
 rts
eg_srcw                    ; A = the word at SI
 mx %00
 jsr eg_srcb
 sta eg_w
 inc rSI
 jsr eg_srcb
 dec rSI
 xba
 ora eg_w
 rts
eg_dstb                    ; A = the byte at DI
 mx %00
 jsr str_dst0
 cmp #^H_EGA
 bne :ram
 ldx pDST
 jmp ega_rd
:ram
 lda [pDST]
 and #$00FF
 rts
eg_dstw                    ; A = the word at DI
 mx %00
 jsr eg_dstb
 sta eg_w
 inc rDI
 jsr eg_dstb
 dec rDI
 xba
 ora eg_w
 rts
eg_putb                    ; the byte A -> DI
 mx %00
 pha
 jsr str_dst               ; (the text buffer's page marked)
 lda pDST+2
 cmp #^H_EGA
 bne :ram
 ldx pDST
 pla
 jmp ega_wr
:ram
 pla
 sep #$20
 mx %10
 sta [pDST]
 rep #$20
 mx %00
 rts
eg_putw                    ; the word A -> DI
 mx %00
 sta eg_w2
 jsr eg_putb
 inc rDI
 lda eg_w2
 xba
 jsr eg_putb
 dec rDI
 rts

eg_movsb
 mx %00
 jsr eg_srcb
 jsr eg_putb
 jsr adv_si1
 jmp adv_di1
eg_movsw
 mx %00
 jsr eg_srcw
 jsr eg_putw
 jsr adv_si2
 jmp adv_di2
eg_cmpsb                   ; [SI] - [DI]
 mx %00
 jsr eg_srcb
 sta tmp1
 jsr eg_dstb
 sta tmp0
 sep #$20
 mx %10
 lda tmp1
 sec
 sbc tmp0
 jsr flg_sub8_r
 mx %00
 jsr adv_si1
 jmp adv_di1
eg_cmpsw
 mx %00
 jsr eg_srcw
 sta tmp1
 jsr eg_dstw
 sta tmp0
 lda tmp1
 sec
 sbc tmp0
 jsr flg_sub16_r
 jsr adv_si2
 jmp adv_di2
eg_stosb
 mx %00
 lda rAX
 jsr eg_putb
 jmp adv_di1
eg_stosw
 mx %00
 lda rAX
 jsr eg_putw
 jmp adv_di2
eg_lodsb
 mx %00
 jsr eg_srcb
 sep #$20
 mx %10
 sta rAX
 rep #$20
 mx %00
 jmp adv_si1
eg_lodsw
 mx %00
 jsr eg_srcw
 sta rAX
 jmp adv_si2
eg_scasb                   ; AL - [DI]
 mx %00
 jsr eg_dstb
 sta tmp0
 sep #$20
 mx %10
 lda rAX
 sta tmp1
 sec
 sbc tmp0
 jsr flg_sub8_r
 mx %00
 jmp adv_di1
eg_scasw
 mx %00
 jsr eg_dstw
 sta tmp0
 lda rAX
 sta tmp1
 sec
 sbc tmp0
 jsr flg_sub16_r
 jmp adv_di2

*--- REP STOS and REP MOVS a plane at a time. What a program does to
* the whole screen or a wide piece of it is one of four things, and
* each is a block move in every plane it touches:
*   a fill with the data itself (eg_plain): REP STOSB, STOSW
*   memory to the planes, likewise: REP MOVSB, MOVSW
*   the planes to memory in read mode 0: REP MOVSB, MOVSW
*   planes to planes through the latches (write mode 1): REP MOVSB
* with DF clear and no end of SI, DI or a 64K in the way. Anything
* else is eg_rep's.
eg_fstos
 mx %00
 lda eg_plain
 bne :try
:slow
 jmp eg_rep
:try
 lda rFL
 and #F_DF
 bne :slow
 jsr eg_bytes              ; eg_n = the bytes, eg_es an element's
 bcs :slow
 jsr str_dst0
 cmp #^H_EGA
 bne :slow
 lda eg_n
 dec
 clc
 adc rDI
 bcs :slow
 lda eg_n
 dec
 clc
 adc pDST
 bcs :slow
 sty eg_y
 stz eg_p
 lda #1
 sta eg_bit
:plane
 lda eg_bit
 and eg_mm
 beq :next
 ldx eg_p
 lda eg_pl+2,x
 sta pDST+2
 xba
 ora pDST+2
 sta mvn_bk
 lda eg_es
 dec
 beq :b
 lda rAX
 sta [pDST]
 bra :run
:b
 sep #$20
 mx %10
 lda rAX
 sta [pDST]
 rep #$20
 mx %00
:run
 lda eg_n                  ; the first element along the rest
 sec
 sbc eg_es
 beq :next
 dec
 pha
 ldx pDST
 txa
 clc
 adc eg_es
 tay
 pla
 jsr mvn_go
:next
 lda eg_p
 clc
 adc #4
 sta eg_p
 asl eg_bit
 lda eg_bit
 cmp #$0010
 bcc :plane
 lda pDST
 sta eg_o
 jsr eg_done               ; DI, CX, the marks
 jmp next_ct

* eg_bytes - eg_es = the element's bytes (tmp7: an odd pair is words),
* eg_n = CX of them; C set when that is more than a 64K
eg_bytes
 mx %00
 lda tmp7
 and #$0002
 bne :w
 lda #1
 sta eg_es
 lda rCX
 sta eg_n
 clc
 rts
:w
 lda #2
 sta eg_es
 lda rCX
 asl
 sta eg_n
 rts
* eg_done - a run of eg_n bytes to the planes at eg_o is over: DI
* and CX, the marks, and IP back in Y
eg_done
 mx %00
 lda rDI
 clc
 adc eg_n
 sta rDI
 stz rCX
 jsr eg_markrng
 ldy eg_y
 rts

eg_fmovs
 mx %00
 lda rFL
 and #F_DF
 bne :slow
 jsr eg_bytes
 bcs :slow
 jsr str_ptrs
 lda eg_n                  ; nothing wraps?
 dec
 sta eg_t2
 clc
 adc rSI
 bcs :slow
 lda eg_t2
 clc
 adc rDI
 bcs :slow
 lda eg_t2
 clc
 adc pSRC
 bcs :slow
 lda eg_t2
 clc
 adc pDST
 bcs :slow
 lda pDST+2
 cmp #^H_EGA
 beq :topl
 jmp :toram
:topl
 lda pSRC+2
 cmp #^H_EGA
 beq :latch
 lda eg_plain              ; memory to the planes
 bne :in
:slow
 jmp eg_rep
:latch                     ; planes to planes: write mode 1, by bytes
 lda eg_es
 dec
 bne :slow
 lda eg_wmode
 cmp #1
 bne :slow
:in
 sty eg_y
 lda pSRC+2
 sta eg_w                  ; the source's bank, when it is memory
 lda pSRC
 clc
 adc eg_t2
 sta eg_w2                 ; the last byte read
 stz eg_p
 lda #1
 sta eg_bit
:plane
 lda eg_bit
 and eg_mm
 beq :next
 ldx eg_p
 lda eg_pl+2,x
 sta pDST+2
 lda eg_w
 cmp #^H_EGA
 bne :src
 lda pDST+2                ; the same plane
:src
 xba
 ora pDST+2
 sta mvn_bk
 ldx pSRC
 ldy pDST
 lda eg_t2
 jsr mvn_go
:next
 lda eg_p
 clc
 adc #4
 sta eg_p
 asl eg_bit
 lda eg_bit
 cmp #$0010
 bcc :plane
 lda eg_w
 cmp #^H_EGA
 bne :nolat
 ldx eg_w2                 ; the latches: the last byte's
 jsr ega_rd
:nolat
 lda rSI
 clc
 adc eg_n
 sta rSI
 lda pDST
 sta eg_o
 jsr eg_done
 jmp next_ct
:toram                     ; the planes to memory: the plane the read map names
 lda pSRC+2
 cmp #^H_EGA
 bne :slow2
 lda eg_rmode
 bne :slow2
 lda pDST+2
 cmp #^H_TXT               ; (the text buffer has its marks to keep)
 beq :slow2
 sty eg_y
 lda eg_rmap
 asl
 asl
 tax
 lda eg_pl+2,x
 xba
 ora pDST+2
 sta mvn_bk
 lda pSRC
 clc
 adc eg_t2
 pha
 ldx pSRC
 ldy pDST
 lda eg_t2
 jsr mvn_go
 plx
 jsr ega_rd                ; the latches: the last byte's
 lda rSI
 clc
 adc eg_n
 sta rSI
 lda rDI
 clc
 adc eg_n
 sta rDI
 stz rCX
 ldy eg_y
 jmp next_ct
:slow2
 jmp eg_rep
