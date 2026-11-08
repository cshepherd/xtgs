*----------------------------------------------------------
* flags.s - guest FLAGS from 65816 results.
*
* rFL holds FLAGS except that OF lives in vOF ($0080 set, 0
* clear) and bit 11 of rFL is ignored; flags_get assembles
* the value the guest sees (fixed bits 1 and 12-15 set),
* flags_set distributes one.
*
* The flg_* routines are tail-called with the result in A
* (M=1 for byte, M=0 for word), the 65816's N V Z C still
* those of the operation, tmp0 = source operand, tmp1 =
* destination before. They rewrite rFL's low byte (SF ZF AF
* PF CF, bit 1 set), set vOF, keep TF IF DF, and retire. The
* _r forms return instead (string compares).
*----------------------------------------------------------

flags_get                  ; A = FLAGS as the guest sees them
 mx %00
 lda vOF
 asl
 asl
 asl
 asl
 sta tmp4
 lda rFL
 and #$07D7                ; keep SF ZF AF PF CF, bit 1, TF IF DF; OF comes from vOF
 ora tmp4
 ora #F_FIXED
 rts

flags_set                  ; A = FLAGS to load
 mx %00
 sta rFL
 and #F_OF
 beq :clr
 lda #$0080
 sta vOF
 rts
:clr
 stz vOF
 rts

*--- add / adc (CF = C)
flg_add16
 mx %00
 php
 sta tmp2
 eor tmp0
 eor tmp1
 and #$0010                ; AF, and B = 0
 sta tmp3
 sep #$20
 mx %10
 lda tmp2
 tax
 lda parity,x
 ora tmp3
 sta tmp3
 pla
 tax
 lda p2f_add,x
 ora tmp3
 sta rFL
 lda p2f_of,x
 sta vOF
 rep #$20
 mx %00
 jmp (NEXTVEC)

flg_add8
 mx %10
 php
 sta tmp2
 eor tmp0
 eor tmp1
 and #$10
 sta tmp3
 xba
 lda #0
 xba                       ; B = 0
 lda tmp2
 tax
 lda parity,x
 ora tmp3
 sta tmp3
 pla
 tax
 lda p2f_add,x
 ora tmp3
 sta rFL
 lda p2f_of,x
 sta vOF
 rep #$20
 mx %00
 jmp (NEXTVEC)

*--- sub / sbb / cmp / neg (CF = NOT C)
flg_sub16
 mx %00
 jsr flg_sub16_r
 jmp (NEXTVEC)
flg_sub16_r
 mx %00
 php
 sta tmp2
 eor tmp0
 eor tmp1
 and #$0010
 sta tmp3
 sep #$20
 mx %10
 lda tmp2
 tax
 lda parity,x
 ora tmp3
 sta tmp3
 pla
 tax
 lda p2f_sub,x
 ora tmp3
 sta rFL
 lda p2f_of,x
 sta vOF
 rep #$20
 mx %00
 rts

flg_sub8
 mx %10
 jsr flg_sub8_r
 jmp (NEXTVEC)
flg_sub8_r
 mx %10
 php
 sta tmp2
 eor tmp0
 eor tmp1
 and #$10
 sta tmp3
 xba
 lda #0
 xba
 lda tmp2
 tax
 lda parity,x
 ora tmp3
 sta tmp3
 pla
 tax
 lda p2f_sub,x
 ora tmp3
 sta rFL
 lda p2f_of,x
 sta vOF
 rep #$20
 mx %00
 rts

*--- and / or / xor / test (CF = OF = 0, AF cleared)
flg_log16
 mx %00
 php
 sta tmp2
 sep #$20
 mx %10
 xba
 lda #0
 xba
 lda tmp2
 tax
 lda parity,x
 sta tmp3
 pla
 tax
 lda p2f_log,x
 ora tmp3
 sta rFL
 stz vOF
 rep #$20
 mx %00
 jmp (NEXTVEC)

flg_log8
 mx %10
 php
 sta tmp2
 xba
 lda #0
 xba
 lda tmp2
 tax
 lda parity,x
 sta tmp3
 pla
 tax
 lda p2f_log,x
 ora tmp3
 sta rFL
 stz vOF
 rep #$20
 mx %00
 jmp (NEXTVEC)

*--- inc / dec: CF kept; OF when the result is $80(00) /
* $7F(FF); AF from the low nibble carry (source 1).
flg_inc16
 mx %00
 sta tmp2
 cmp #$8000
 bra flg_incdec16
flg_dec16
 mx %00
 sta tmp2
 cmp #$7FFF
flg_incdec16               ; Z = OF
 mx %00
 beq :of
 stz vOF
 bra :af
:of
 lda #$0080
 sta vOF
:af
 lda tmp2
 eor tmp1
 eor #1
 and #$0010
 sta tmp3
 lda rFL
 and #$0001
 ora tmp3
 sta tmp3                  ; AF | old CF
 sep #$20
 mx %10
 lda tmp2
 tax                       ; B = 0 (A was AF|CF)
 lda parity,x
 ora tmp3
 sta tmp3
 lda tmp2+1                ; SF, ZF from the result
 tax
 lda tmp2
 beq :z16
 lda #0                    ; nonzero: ZF clear, SF from the high byte
 bra :sf16
:z16
 txa
 beq :zero16
 lda #0
 bra :sf16
:zero16
 lda #F_ZF
:sf16
 sta tmp2
 txa
 and #$80
 ora tmp2
 ora tmp3
 ora #$02
 sta rFL
 rep #$20
 mx %00
 jmp (NEXTVEC)

flg_inc8
 mx %10
 sta tmp2
 cmp #$80
 bra flg_incdec8
flg_dec8
 mx %10
 sta tmp2
 cmp #$7F
flg_incdec8                ; Z = OF
 mx %10
 beq :of
 stz vOF
 bra :af
:of
 lda #$80
 sta vOF
:af
 lda tmp2
 eor tmp1
 eor #1
 and #$10
 sta tmp3
 lda rFL
 and #$01
 ora tmp3
 sta tmp3                  ; AF | old CF
 xba
 lda #0
 xba                       ; B = 0
 lda tmp2
 tax
 lda parity,x
 ora tmp3
 ora #$02
 sta tmp3
 lda tmp2
 bne :nz
 lda #F_ZF
 bra :sf
:nz
 and #$80
:sf
 ora tmp3
 sta rFL
 rep #$20
 mx %00
 jmp (NEXTVEC)

*--- multiply: A = the high half; CF = OF = (A != 0)
flg_mul
 mx %00
 bne :set
 lda rFL
 and #$FFFE
 sta rFL
 stz vOF
 jmp (NEXTVEC)
:set
 lda rFL
 ora #F_CF
 sta rFL
 lda #$0080
 sta vOF
 jmp (NEXTVEC)

*--- shifts: result in tmp1, CF in vCF, OF already in vOF;
* SF ZF PF from the result, AF cleared.
flg_shift16
 mx %00
 lda tmp1
 sta tmp2
 sep #$20
 mx %10
 xba
 lda #0
 xba
 lda tmp2
 tax
 lda parity,x
 ora vCF
 ora #$02
 sta tmp3
 lda tmp2+1
 tax
 lda tmp2
 beq :z16
 lda #0
 bra :sf16
:z16
 txa
 beq :zero16
 lda #0
 bra :sf16
:zero16
 lda #F_ZF
:sf16
 sta tmp2
 txa
 and #$80
 ora tmp2
 ora tmp3
 sta rFL
 rep #$20
 mx %00
 jmp (NEXTVEC)

flg_shift8
 mx %00
 sep #$20
 mx %10
 xba
 lda #0
 xba
 lda tmp1
 tax
 lda parity,x
 ora vCF
 ora #$02
 sta tmp3
 lda tmp1
 bne :nz
 lda #F_ZF
 bra :sf
:nz
 and #$80
:sf
 ora tmp3
 sta rFL
 rep #$20
 mx %00
 jmp (NEXTVEC)

*--- rotates: only CF (vCF) and OF (vOF) change
flg_rot
 mx %00
 lda rFL
 and #$FFFE
 ora vCF
 sta rFL
 jmp (NEXTVEC)
