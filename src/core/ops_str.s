*----------------------------------------------------------
* ops_str.s - string instructions with REP/REPE/REPNE and
* DF. Source is (override or DS):SI, destination ES:DI.
* str_run drives one routine from str_tab: once, or CX
* times, stopping early for CMPS/SCAS by ZF as the prefix
* says. (The MVN fast path for REP MOVS is M4 work.)
*----------------------------------------------------------

op_A4
 mx %00
 ldx #0
 bra str_run
op_A5
 mx %00
 ldx #2
 bra str_run
op_A6
 mx %00
 ldx #4
 bra str_run
op_A7
 mx %00
 ldx #6
 bra str_run
op_AA
 mx %00
 ldx #8
 bra str_run
op_AB
 mx %00
 ldx #10
 bra str_run
op_AC
 mx %00
 ldx #12
 bra str_run
op_AD
 mx %00
 ldx #14
 bra str_run
op_AE
 mx %00
 ldx #16
 bra str_run
op_AF
 mx %00
 ldx #18

str_run
 mx %00
 stx tmp7
 lda vREP
 bne :rep
 jsr str_call
 jmp (NEXTVEC)
:rep
 lda rCX
 bne :lj1
 jmp :done
:lj1
* --- MVN fast path: REP MOVSB/MOVSW forward, whole copy inside one source
* bank and one dest bank. MOVS sets no flags, so only SI/DI/CX change.
 lda tmp7
 beq :mvn_try              ; movsb
 cmp #2
 beq :mvn_try              ; movsw
 jmp :loop ; other string ops: generic
:mvn_try
 lda rFL
 and #F_DF
 beq :lj2
 jmp :loop ; backward: generic
:lj2
 lda rCX                   ; byte count = CX (movsb) or CX*2 (movsw)
 ldx tmp7
 beq :mvn_bytes
 asl
 bcc :lj3
 jmp :loop ; CX*2 > 64 KB
:lj3
:mvn_bytes
 sta vBOUNCE               ; the byte count (vBOUNCE is free during MOVS)
 bne :lj4
 jmp :loop
:lj4
 lda rSI                   ; SI + bytes must not wrap the 16-bit offset
 clc
 adc vBOUNCE
 bcc :lj5
 jmp :loop
:lj5
 lda rDI
 clc
 adc vBOUNCE
 bcc :lj6
 jmp :loop
:lj6
 jsr str_src               ; pSRC = (override|DS):SI
 jsr str_dst               ; pDST = ES:DI
 lda pSRC                  ; host offsets + bytes must stay inside the bank
 clc
 adc vBOUNCE
 bcs :loop
 lda pDST
 clc
 adc vBOUNCE
 bcs :loop
 sty rIP                   ; MVN clobbers Y, which holds the guest IP
 lda vBOUNCE               ; count-1, kept on the stack across the 8-bit patch
 dec
 pha
 sep #$20
 mx %10
 lda pDST+2
 sta :mvn+1                ; dst bank
 lda pSRC+2
 sta :mvn+2                ; src bank
 rep #$20
 mx %00
 pla                       ; count-1 back in a 16-bit accumulator
 phb
 ldx pSRC
 ldy pDST
:mvn
 dfb $54,$00,$00           ; MVN srcbank -> dstbank (banks patched above)
 plb
 lda rSI
 clc
 adc vBOUNCE
 sta rSI
 lda rDI
 clc
 adc vBOUNCE
 sta rDI
 stz rCX
 ldy rIP
 jmp (NEXTVEC)
:loop
 jsr str_call
 dec rCX
 beq :done
 ldx tmp7
 lda str_cond,x
 beq :loop
 lda vREP
 cmp #$F3
 beq :repe
 lda rFL                   ; REPNE: stop once equal
 and #F_ZF
 bne :done
 bra :loop
:repe
 lda rFL                   ; REPE: stop once not equal
 and #F_ZF
 beq :done
 bra :loop
:done
 jmp (NEXTVEC)
str_call
 mx %00
 ldx tmp7
 jmp (str_tab,x)
str_tab  da movsb,movsw,cmpsb,cmpsw,stosb,stosw,lodsb,lodsw,scasb,scasw
str_cond dw 0,0,1,1,0,0,0,0,1,1

*--- pointers and advances
str_src                    ; pSRC = (override|DS):SI
 mx %00
 ldx vSEGOVR
 bne :seg
 ldx #bDS
:seg
 lda rSI
 clc
 adc 0,x
 sta pSRC
 lda 2,x
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pSRC+2
 rts
str_dst                    ; pDST = ES:DI
 mx %00
 lda rDI
 clc
 adc bES
 sta pDST
 lda bES+2
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pDST+2
 cmp #^H_TXT
 bne :ok
 jmp vid_mark_dst
:ok
 rts
adv_si1
 mx %00
 lda rFL
 and #F_DF
 bne :d
 inc rSI
 rts
:d
 dec rSI
 rts
adv_si2
 mx %00
 lda rFL
 and #F_DF
 bne :d
 inc rSI
 inc rSI
 rts
:d
 dec rSI
 dec rSI
 rts
adv_di1
 mx %00
 lda rFL
 and #F_DF
 bne :d
 inc rDI
 rts
:d
 dec rDI
 rts
adv_di2
 mx %00
 lda rFL
 and #F_DF
 bne :d
 inc rDI
 inc rDI
 rts
:d
 dec rDI
 dec rDI
 rts

*--- word access with the segment wrap: an offset of $FFFF puts the
* high byte at offset 0 of the same segment. Entry: the pointer is set.
rd16_src                   ; A = word at (override|DS):SI
 mx %00
 lda rSI
 cmp #$FFFF
 beq :split
 lda [pSRC]
 rts
:split
 ldx vSEGOVR
 bne :seg
 ldx #bDS
:seg
 lda 0,x
 sta pTMP
 lda 2,x
 sta pTMP+2
 sep #$20
 mx %10
 lda [pSRC]
 sta tmp4
 lda [pTMP]
 sta tmp4+1
 rep #$20
 mx %00
 lda tmp4
 rts
rd16_dst                   ; A = word at ES:DI
 mx %00
 lda rDI
 cmp #$FFFF
 beq :split
 lda [pDST]
 rts
:split
 lda bES
 sta pTMP
 lda bES+2
 sta pTMP+2
 sep #$20
 mx %10
 lda [pDST]
 sta tmp4
 lda [pTMP]
 sta tmp4+1
 rep #$20
 mx %00
 lda tmp4
 rts
wr16_dst                   ; word A -> ES:DI
 mx %00
 sta tmp4
 lda rDI
 cmp #$FFFF
 beq :split
 lda tmp4
 sta [pDST]
 rts
:split
 lda bES
 sta pTMP
 lda bES+2
 sta pTMP+2
 sep #$20
 mx %10
 lda tmp4
 sta [pDST]
 lda tmp4+1
 sta [pTMP]
 rep #$20
 mx %00
 rts

*--- one iteration each
movsb
 mx %00
 jsr str_src
 jsr str_dst
 sep #$20
 mx %10
 lda [pSRC]
 sta [pDST]
 rep #$20
 mx %00
 jsr adv_si1
 jmp adv_di1
movsw
 mx %00
 jsr str_src
 jsr str_dst
 jsr rd16_src
 jsr wr16_dst
 jsr adv_si2
 jmp adv_di2
cmpsb                      ; [SI] - [DI]
 mx %00
 jsr str_src
 jsr str_dst
 sep #$20
 mx %10
 lda [pDST]
 sta tmp0
 lda [pSRC]
 sta tmp1
 sec
 sbc tmp0
 jsr flg_sub8_r
 jsr adv_si1
 jmp adv_di1
cmpsw
 mx %00
 jsr str_src
 jsr str_dst
 jsr rd16_dst
 sta tmp0
 jsr rd16_src
 sta tmp1
 sec
 sbc tmp0
 jsr flg_sub16_r
 jsr adv_si2
 jmp adv_di2
stosb
 mx %00
 jsr str_dst
 sep #$20
 mx %10
 lda rAX
 sta [pDST]
 rep #$20
 mx %00
 jmp adv_di1
stosw
 mx %00
 jsr str_dst
 lda rAX
 jsr wr16_dst
 jmp adv_di2
lodsb
 mx %00
 jsr str_src
 sep #$20
 mx %10
 lda [pSRC]
 sta rAX
 rep #$20
 mx %00
 jmp adv_si1
lodsw
 mx %00
 jsr str_src
 jsr rd16_src
 sta rAX
 jmp adv_si2
scasb                      ; AL - [DI]
 mx %00
 jsr str_dst
 sep #$20
 mx %10
 lda [pDST]
 sta tmp0
 lda rAX
 sta tmp1
 sec
 sbc tmp0
 jsr flg_sub8_r
 jmp adv_di1
scasw
 mx %00
 jsr str_dst
 jsr rd16_dst
 sta tmp0
 lda rAX
 sta tmp1
 sec
 sbc tmp0
 jsr flg_sub16_r
 jmp adv_di2
