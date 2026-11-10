*----------------------------------------------------------
* ops_grp.s - group 3 (TEST NOT NEG MUL IMUL DIV IDIV),
* group 2 (ROL ROR RCL RCR SHL SHR SETMO SAR) and the
* decimal adjusts (DAA DAS AAA AAS AAM AAD).
*----------------------------------------------------------

*=== group 3 ===============================================
op_F6
 mx %00
 jsr modrm_b
 lda vMODRM
 and #$0038
 lsr
 lsr
 tax
 jmp (gF6_tab,x)
gF6_tab da gF6_0,gF6_0,gF6_2,gF6_3,gF6_4,gF6_5,gF6_6,gF6_7
op_F7
 mx %00
 jsr modrm_w
 lda vMODRM
 and #$0038
 lsr
 lsr
 tax
 jmp (gF7_tab,x)
gF7_tab da gF7_0,gF7_0,gF7_2,gF7_3,gF7_4,gF7_5,gF7_6,gF7_7

gF6_0                      ; test r/m8, imm8
 mx %00
 lda [bCS],y
 iny
 sep #$20
 mx %10
 sta tmp0
 lda [pEA]
 and tmp0
 jmp flg_log8
gF7_0                      ; test r/m16, imm16
 mx %00
 lda [bCS],y
 iny
 iny
 sta tmp0
 lda [pEA]
 and tmp0
 jmp flg_log16
gF6_2                      ; not r/m8
 mx %00
 sep #$20
 mx %10
 lda [pEA]
 eor #$FF
 sta [pEA]
 rep #$20
 mx %00
 jmp (NEXTVEC)
gF7_2                      ; not r/m16
 mx %00
 lda [pEA]
 eor #$FFFF
 sta [pEA]
 jmp (NEXTVEC)
gF6_3                      ; neg r/m8 = 0 - r/m8
 mx %00
 sep #$20
 mx %10
 lda [pEA]
 sta vFS
 lda #0
 sta vFD
 sec
 sbc vFS
 sta [pEA]
 jmp flg_sub8
gF7_3                      ; neg r/m16
 mx %00
 lda [pEA]
 sta vFS
 lda #0
 sta vFD
 sec
 sbc vFS
 sta [pEA]
 jmp flg_sub16

* mul16 - tmp0 * tmp1 (unsigned) -> A = high word, tmp1 = low word.
mul16
 mx %00
 lda #0
 ldx #16
 lsr tmp1
:loop
 bcc :noadd
 clc
 adc tmp0
:noadd
 ror
 ror tmp1
 dex
 bne :loop
 rts

gF6_4                      ; mul r/m8: AX = AL * r/m8
 mx %00
 lda [pEA]
 and #$00FF
 sta tmp0
 lda rAX
 and #$00FF
 sta tmp1
 jsr mul16
 lda tmp1
 sta rAX
 and #$FF00
 jmp flg_mul
gF7_4                      ; mul r/m16: DX:AX = AX * r/m16
 mx %00
 lda [pEA]
 sta tmp0
 lda rAX
 sta tmp1
 jsr mul16
 sta rDX
 lda tmp1
 sta rAX
 lda rDX
 jmp flg_mul

* imul32 - tmp0 * tmp1 (signed 16-bit) -> tmp3:tmp1 (signed 32-bit).
imul32
 mx %00
 stz tmp2                  ; sign of the product
 lda tmp0
 bpl :p0
 eor #$FFFF
 inc
 sta tmp0
 inc tmp2
:p0
 lda tmp1
 bpl :p1
 eor #$FFFF
 inc
 sta tmp1
 inc tmp2
:p1
 jsr mul16
 sta tmp3
 lda tmp2
 and #1
 beq :done
 lda #0                    ; negate tmp3:tmp1
 sec
 sbc tmp1
 sta tmp1
 lda #0
 sbc tmp3
 sta tmp3
:done
 rts

gF6_5                      ; imul r/m8: AX = AL * r/m8 (signed)
 mx %00
 lda [pEA]
 and #$00FF
 eor #$80
 sec
 sbc #$80
 sta tmp0
 lda rAX
 and #$00FF
 eor #$80
 sec
 sbc #$80
 sta tmp1
 jsr imul32
 lda tmp1
 sta rAX
 and #$00FF                ; CF = OF = (AH != sign extension of AL)
 eor #$80
 sec
 sbc #$80
 eor tmp1
 jmp flg_mul
gF7_5                      ; imul r/m16: DX:AX = AX * r/m16 (signed)
 mx %00
 lda [pEA]
 sta tmp0
 lda rAX
 sta tmp1
 jsr imul32
 lda tmp1
 sta rAX
 lda tmp3
 sta rDX
 lda rAX                   ; CF = OF = (DX != sign extension of AX)
 bpl :pos
 lda #$FFFF
 bra :cmp
:pos
 lda #0
:cmp
 eor rDX
 jmp flg_mul

* div32 - tmp2:tmp1 / tmp0 (unsigned) -> tmp1 quotient, tmp2
* remainder. Requires tmp0 != 0 and tmp2 < tmp0.
div32
 mx %00
 ldx #16
:loop
 asl tmp1
 rol tmp2
 bcs :sub
 lda tmp2
 cmp tmp0
 bcc :next
:sub
 lda tmp2
 sec
 sbc tmp0
 sta tmp2
 inc tmp1
:next
 dex
 bne :loop
 rts

div_err                    ; divide error: INT 0 with IP past the instruction
 mx %00
 sty rIP
 lda #0
 jsr do_int
 jmp (NEXTVEC)
* The 8088 traps with the flags of its first step, a compare of the
* dividend's high half against the divisor (measured: every DIV
* vector). tmp0 = divisor.
div_err8
 mx %00
 sep #$20
 mx %10
 lda rAX+1
 sta tmp1
 sec
 sbc tmp0
 jsr flg_sub8_r
 bra div_err
div_err16
 mx %00
 lda rDX
 sta tmp1
 sec
 sbc tmp0
 jsr flg_sub16_r
 bra div_err

* IDIV traps (measured against every trap vector in the suite):
*  - before dividing, when |hi| >= |d| or d = 0: the flags of CMP |hi|, |d|
*    (idiv_err8/16: A = |hi|, tmp0 = |d|);
*  - after dividing, when the quotient magnitude is >= $80 / $8000: the
*    flags of the last restoring step's compare, CF cleared: with the
*    quotient's bit 0 set, (r + d) - d; clear, r - d (idiv_late8/16:
*    tmp0 = |d|, tmp1 = q, tmp2 = r).
idiv_late8
 mx %00
 lda tmp1
 and #1
 sta tmp6                  ; the last quotient bit
 beq :nosub
 lda tmp2
 clc
 adc tmp0
 bra :op
:nosub
 lda tmp2
:op
 sta tmp1
 sep #$20
 mx %10
 lda tmp1
 sec
 sbc tmp0
 jsr flg_sub8_r
 mx %00                    ; flg_sub8_r returns with 16-bit A
 lda tmp6
 bne :keep                 ; subtract path: CF is the compare's own borrow
 lda vLP
 and #$FFFF-LP_CF          ; no-subtract path: the certain borrow reads as 0
 sta vLP
:keep
 rts
idiv_late16
 mx %00
 lda tmp1
 and #1
 sta tmp6
 beq :nosub
 lda tmp2
 clc
 adc tmp0
 bra :op
:nosub
 lda tmp2
:op
 sta tmp1
 sec
 sbc tmp0
 jsr flg_sub16_r
 lda tmp6
 bne :keep
 lda vLP
 and #$FFFF-LP_CF
 sta vLP
:keep
 rts
idiv_err8
 mx %00
 sta tmp1
 sep #$20
 mx %10
 lda tmp1
 sec
 sbc tmp0
 jsr flg_sub8_r
 jmp div_err
idiv_err16
 mx %00
 sta tmp1
 sec
 sbc tmp0
 jsr flg_sub16_r
 jmp div_err

gF6_6                      ; div r/m8: AL = AX / r/m8, AH = remainder
 mx %00
 lda [pEA]
 and #$00FF
 sta tmp0
 beq :err
 lda rAX
 xba
 and #$00FF
 cmp tmp0
 bcs :err                  ; quotient would not fit
 stz tmp2
 lda rAX
 sta tmp1
 jsr div32
 lda tmp2
 xba
 ora tmp1
 sta rAX
 jmp (NEXTVEC)
:err
 jmp div_err8
gF7_6                      ; div r/m16: AX = DX:AX / r/m16, DX = remainder
 mx %00
 lda [pEA]
 sta tmp0
 beq :err
 lda rDX
 cmp tmp0
 bcs :err
 sta tmp2
 lda rAX
 sta tmp1
 jsr div32
 lda tmp1
 sta rAX
 lda tmp2
 sta rDX
 jmp (NEXTVEC)
:err
 jmp div_err16

* Signed division: magnitudes through div32, then the signs:
* quotient negative when the signs differ, remainder with the
* dividend's sign. The quotient must fit (positive <= $7F /
* $7FFF, negative magnitude <= $80 / $8000) or INT 0.
gF6_7                      ; idiv r/m8
 mx %00
 lda [pEA]
 and #$00FF
 eor #$80
 sec
 sbc #$80
 sta tmp0
 stz tmp4                  ; bit 0: quotient negative; bit 1: remainder negative
 bpl :d0
 eor #$FFFF
 inc
 sta tmp0
 inc tmp4
:d0
 lda rAX
 sta tmp1
 bpl :d1
 eor #$FFFF
 inc
 sta tmp1
 lda tmp4
 eor #3
 sta tmp4
:d1
 lda vREP                  ; a REP/REPNE prefix flips the quotient's sign
 beq :norep                ; (the 8086's F1 flag, shared with the string loop)
 lda tmp4
 eor #1
 sta tmp4
:norep
 stz tmp2
 lda tmp1
 xba
 and #$00FF
 sta tmp5                  ; |dividend| high byte, for the error flags
 lda tmp0
 beq :err                  ; divisor 0: trap with CMP |hi|, 0
 lda tmp5
 cmp tmp0
 bcs :err
 jsr div32
 lda tmp1                  ; the 8088 rejects a quotient magnitude of $80
 cmp #$80                  ; (-128 traps too, measured)
 bcs :late
 lda tmp4
 and #1
 beq :rem
 lda #0
 sec
 sbc tmp1
 sta tmp1
:rem
 lda tmp4
 and #2
 beq :store
 lda #0
 sec
 sbc tmp2
 sta tmp2
:store
 lda tmp2
 xba
 and #$FF00
 sta tmp2
 lda tmp1
 and #$00FF
 ora tmp2
 sta rAX
 jmp (NEXTVEC)
:err
 lda tmp5
 jmp idiv_err8
:late
 jsr idiv_late8
 jmp div_err
gF7_7                      ; idiv r/m16
 mx %00
 lda [pEA]
 sta tmp0
 stz tmp4
 bpl :d0
 eor #$FFFF
 inc
 sta tmp0
 inc tmp4
:d0
 lda rAX
 sta tmp1
 lda rDX
 sta tmp2
 bpl :d1
 lda #0                    ; negate tmp2:tmp1
 sec
 sbc tmp1
 sta tmp1
 lda #0
 sbc tmp2
 sta tmp2
 lda tmp4
 eor #3
 sta tmp4
:d1
 lda vREP                  ; REP/REPNE flips the quotient's sign
 beq :norep
 lda tmp4
 eor #1
 sta tmp4
:norep
 lda tmp2
 sta tmp5                  ; |dividend| high word, for the error flags
 lda tmp0
 beq :err                  ; divisor 0: trap with CMP |hi|, 0
 lda tmp5
 cmp tmp0
 bcs :err
 jsr div32
 lda tmp1                  ; a quotient magnitude of $8000 traps either way
 cmp #$8000
 bcs :late
 lda tmp4
 and #1
 beq :rem
 lda #0
 sec
 sbc tmp1
 sta tmp1
:rem
 lda tmp4
 and #2
 beq :store
 lda #0
 sec
 sbc tmp2
 sta tmp2
:store
 lda tmp1
 sta rAX
 lda tmp2
 sta rDX
 jmp (NEXTVEC)
:err
 lda tmp5
 jmp idiv_err16
:late
 jsr idiv_late16
 jmp div_err

*=== group 2: shifts and rotates =============================
* D0/D1: count 1. D2/D3: count CL (the 8086 does not mask
* it). The count loop runs the step as the hardware does,
* tracking CF in vCF; OF is computed from the final state as
* the hardware's last step would. Rotates leave SF ZF AF PF.
op_D0
 mx %00
 jsr modrm_b
 lda #1
 sta vCOUNT
 bra shift8
op_D2
 mx %00
 jsr modrm_b
 lda rCX
 and #$00FF
 sta vCOUNT
 bne shift8
 jmp (NEXTVEC)
shift8
 mx %00
 lda vLP
 and #LP_CF
 sta vCF
 lda vMODRM
 and #$0038
 lsr
 lsr
 tax
 sep #$20
 mx %10
 lda [pEA]
 sta tmp1
 jmp (sh8_tab,x)
sh8_tab da sh8_rol,sh8_ror,sh8_rcl,sh8_rcr,sh8_shl,sh8_shr,sh8_setmo,sh8_sar

op_D1
 mx %00
 jsr modrm_w
 lda #1
 sta vCOUNT
 bra shift16
op_D3
 mx %00
 jsr modrm_w
 lda rCX
 and #$00FF
 sta vCOUNT
 bne shift16
 jmp (NEXTVEC)
shift16
 mx %00
 lda vLP
 and #LP_CF
 sta vCF
 lda vMODRM
 and #$0038
 lsr
 lsr
 tax
 lda [pEA]
 sta tmp1
 jmp (sh16_tab,x)
sh16_tab da sh16_rol,sh16_ror,sh16_rcl,sh16_rcr,sh16_shl,sh16_shr,sh16_setmo,sh16_sar

* --- 8-bit steps (M=1). Each: tmp1 -> tmp1, vCF; then OF.
sh8_rol
 mx %10
:l
 lda tmp1
 asl
 bcc :n
 ora #1
:n
 sta tmp1
 lda #0
 rol
 sta vCF
 dec vCOUNT
 bne :l
 lda tmp1                  ; OF = MSB ^ CF (= bit 0)
 and #$81
 beq :z
 cmp #$81
 beq :z
 lda #$80
 bra :s
:z
 lda #0
:s
 sta vOF
 bra sh8_rot_done
sh8_ror
 mx %10
:l
 lda tmp1
 lsr
 bcc :n
 ora #$80
:n
 sta tmp1
 lda #0
 rol
 sta vCF
 dec vCOUNT
 bne :l
sh8_of_top2                ; OF = MSB ^ bit 6 of the result
 mx %10
 lda tmp1
 asl
 bcc :n
 eor #$80
:n
 and #$80
 sta vOF
 bra sh8_rot_done
sh8_rcl
 mx %10
:l
 lda tmp1
 sta tmp0
 lda vCF
 lsr
 lda tmp0
 rol
 sta tmp1
 lda #0
 rol
 sta vCF
 dec vCOUNT
 bne :l
 lda tmp1                  ; OF = MSB ^ CF
 and #$80
 beq :z
 lda vCF
 eor #1
 bra :s
:z
 lda vCF
:s
 beq :c
 lda #$80
:c
 sta vOF
 bra sh8_rot_done
sh8_rcr
 mx %10
:l
 lda tmp1
 sta tmp0
 lda vCF
 lsr
 lda tmp0
 ror
 sta tmp1
 lda #0
 rol
 sta vCF
 dec vCOUNT
 bne :l
 bra sh8_of_top2
sh8_rot_done
 mx %10
 lda tmp1
 sta [pEA]
 rep #$20
 mx %00
 jmp flg_rot
sh8_shl
 mx %10
:l
 lda tmp1
 asl
 sta tmp1
 lda #0
 rol
 sta vCF
 dec vCOUNT
 bne :l
 lda tmp1                  ; OF = MSB ^ CF
 and #$80
 beq :z
 lda vCF
 eor #1
 bra :s
:z
 lda vCF
:s
 beq :c
 lda #$80
:c
 sta vOF
 bra sh8_shift_done
sh8_shr
 mx %10
:l
 lda tmp1
 sta tmp0
 lsr
 sta tmp1
 lda #0
 rol
 sta vCF
 dec vCOUNT
 bne :l
 lda tmp0                  ; OF = MSB before the last step
 and #$80
 sta vOF
 bra sh8_shift_done
sh8_sar
 mx %10
:l
 lda tmp1
 cmp #$80
 ror
 sta tmp1
 lda #0
 rol
 sta vCF
 dec vCOUNT
 bne :l
 stz vOF
 bra sh8_shift_done
sh8_setmo                  ; undocumented /6: result $FF, flags as a logic op
 mx %10
 lda #$FF
 sta tmp1
 stz vCF
 stz vOF
sh8_shift_done
 mx %10
 lda tmp1
 sta [pEA]
 jmp flg_shift8

* --- 16-bit steps (M=0)
sh16_rol
 mx %00
:l
 lda tmp1
 asl
 bcc :n
 ora #1
:n
 sta tmp1
 lda #0
 rol
 sta vCF
 dec vCOUNT
 bne :l
 lda tmp1
 and #$8001
 beq :z
 cmp #$8001
 beq :z
 lda #$0080
 bra :s
:z
 lda #0
:s
 sta vOF
 bra sh16_rot_done
sh16_ror
 mx %00
:l
 lda tmp1
 lsr
 bcc :n
 ora #$8000
:n
 sta tmp1
 lda #0
 rol
 sta vCF
 dec vCOUNT
 bne :l
sh16_of_top2
 mx %00
 lda tmp1
 asl
 bcc :n
 eor #$8000
:n
 and #$8000
 beq :z
 lda #$0080
:z
 sta vOF
 bra sh16_rot_done
sh16_rcl
 mx %00
:l
 lda tmp1
 sta tmp0
 lda vCF
 lsr
 lda tmp0
 rol
 sta tmp1
 lda #0
 rol
 sta vCF
 dec vCOUNT
 bne :l
 lda tmp1
 and #$8000
 beq :z
 lda vCF
 eor #1
 bra :s
:z
 lda vCF
:s
 beq :c
 lda #$0080
:c
 sta vOF
 bra sh16_rot_done
sh16_rcr
 mx %00
:l
 lda tmp1
 sta tmp0
 lda vCF
 lsr
 lda tmp0
 ror
 sta tmp1
 lda #0
 rol
 sta vCF
 dec vCOUNT
 bne :l
 bra sh16_of_top2
sh16_rot_done
 mx %00
 lda tmp1
 sta [pEA]
 jmp flg_rot
sh16_shl
 mx %00
:l
 lda tmp1
 asl
 sta tmp1
 lda #0
 rol
 sta vCF
 dec vCOUNT
 bne :l
 lda tmp1
 and #$8000
 beq :z
 lda vCF
 eor #1
 bra :s
:z
 lda vCF
:s
 beq :c
 lda #$0080
:c
 sta vOF
 bra sh16_shift_done
sh16_shr
 mx %00
:l
 lda tmp1
 sta tmp0
 lsr
 sta tmp1
 lda #0
 rol
 sta vCF
 dec vCOUNT
 bne :l
 lda tmp0
 and #$8000
 beq :z
 lda #$0080
:z
 sta vOF
 bra sh16_shift_done
sh16_sar
 mx %00
:l
 lda tmp1
 cmp #$8000
 ror
 sta tmp1
 lda #0
 rol
 sta vCF
 dec vCOUNT
 bne :l
 stz vOF
 bra sh16_shift_done
sh16_setmo
 mx %00
 lda #$FFFF
 sta tmp1
 stz vCF
 stz vOF
sh16_shift_done
 mx %00
 lda tmp1
 sta [pEA]
 jmp flg_shift16

*=== decimal adjusts =========================================
* Written from the 8086 algorithms; SF ZF PF from AL, the
* undefined flags as they fall out. They work on a FLAGS
* byte in rFL and OF in vOF: flg_sync before, flg_commit
* after (flags.s).
op_27                      ; daa
 mx %00
 jsr flg_sync
 sep #$20
 mx %10
 clc
 bra bcd_adjust
op_2F                      ; das
 mx %00
 jsr flg_sync
 sep #$20
 mx %10
 sec
* bcd_adjust - DAA (C clear) / DAS (C set), as the 8088 does it
* (measured against the hardware vectors): the low adjust when
* the low nibble > 9 or AF; the high adjust when CF, or the high
* nibble > 9, or the high nibble is 9 with the low nibble > 9
* and AF clear. CF = high adjust, AF = low adjust, SZP from AL.
bcd_adjust
 mx %10
 php
 lda rAX
 sta tmp0                  ; old AL
 lda rFL
 sta tmp2                  ; old flags
 stz tmp3                  ; new CF/AF bits
 lda tmp0
 and #$0F
 cmp #$0A
 bcs :low
 lda tmp2
 and #F_AF
 beq :nolow
:low
 lda #F_AF
 sta tmp3
 plp
 php
 bcs :low_das
 lda rAX
 clc
 adc #6
 bra :low_store
:low_das
 lda rAX
 sec
 sbc #6
:low_store
 sta rAX
:nolow
 lda tmp2
 and #F_CF
 bne :high
 lda tmp0
 and #$F0
 cmp #$A0
 bcs :high
 cmp #$90
 bne :nohigh
 lda tmp0
 and #$0F
 cmp #$0A
 bcc :nohigh
 lda tmp2
 and #F_AF
 bne :nohigh
:high
 lda tmp3
 ora #F_CF
 sta tmp3
 plp
 php
 bcs :high_das
 lda rAX
 clc
 adc #$60
 bra :high_store
:high_das
 lda rAX
 sec
 sbc #$60
:high_store
 sta rAX
:nohigh
 plp
 lda tmp2
 and #$FF-F_CF-F_AF
 ora tmp3
 sta rFL
 lda rAX
 jmp bcd_flags8
op_37                      ; aaa
 mx %00
 jsr flg_sync
 sep #$20
 mx %10
 lda rAX
 and #$0F
 cmp #$0A
 bcs :adj
 lda rFL
 and #F_AF
 bne :adj
 lda rFL
 and #$FF-F_CF-F_AF
 sta rFL
 bra :mask
:adj
 lda rAX
 clc
 adc #6
 sta rAX
 inc rAX+1
 lda rFL
 ora #F_AF+F_CF
 sta rFL
:mask
 lda rAX
 and #$0F
 sta rAX
 jmp bcd_flags8
op_3F                      ; aas
 mx %00
 jsr flg_sync
 sep #$20
 mx %10
 lda rAX
 and #$0F
 cmp #$0A
 bcs :adj
 lda rFL
 and #F_AF
 bne :adj
 lda rFL
 and #$FF-F_CF-F_AF
 sta rFL
 bra :mask
:adj
 lda rAX
 sec
 sbc #6
 sta rAX
 dec rAX+1
 lda rFL
 ora #F_AF+F_CF
 sta rFL
:mask
 lda rAX
 and #$0F
 sta rAX
 jmp bcd_flags8

* bcd_flags8 - M=1, A = AL: SF ZF PF from it, CF AF kept.
bcd_flags8
 mx %10
 sta tmp2
 xba
 lda #0
 xba
 lda tmp2
 tax
 lda parity,x
 sta tmp3
 lda rFL
 and #F_CF+F_AF
 ora tmp3
 ora #$02
 sta tmp3
 lda tmp2
 bne :nz
 lda #F_ZF
 bra :s
:nz
 and #$80
:s
 ora tmp3
 sta rFL
 rep #$20
 mx %00
 jmp flg_commit

op_D4                      ; aam imm8: AH = AL / imm, AL = AL mod imm
 mx %00
 jsr flg_sync
 lda [bCS],y
 iny
 and #$00FF
 beq :err
 sta tmp0
 stz tmp2
 lda rAX
 and #$00FF
 sta tmp1
 jsr div32
 lda tmp1
 xba
 ora tmp2
 sta rAX
 sep #$20
 mx %10
 lda rFL
 and #$FF-F_CF-F_AF
 sta rFL
 stz vOF
 lda rAX
 jmp bcd_flags8
:err
 stz tmp0                  ; the 8088 compares a zero high half with the
 stz tmp1                  ; zero divisor first: ZF PF set, the rest clear
 sep #$20
 mx %10
 lda #0
 sec
 sbc tmp0
 jsr flg_sub8_r
 jmp div_err
op_D5                      ; aad imm8: AL = AH * imm + AL, AH = 0
 mx %00
 jsr flg_sync
 lda [bCS],y
 iny
 and #$00FF
 sta tmp0
 lda rAX
 xba
 and #$00FF
 sta tmp1
 jsr mul16
 lda tmp1
 sep #$20
 mx %10
 clc
 adc rAX
 sta rAX
 stz rAX+1
 lda rFL
 and #$FF-F_CF-F_AF
 sta rFL
 stz vOF
 lda rAX
 jmp bcd_flags8
