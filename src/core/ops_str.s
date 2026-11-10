*----------------------------------------------------------
* ops_str.s - string instructions with REP/REPE/REPNE and
* DF. Source is (override or DS):SI, destination ES:DI.
*
* Without REP the common ones (MOVS, STOS, LODS) are inline:
* the host pointers by one add each (the base's bank word
* as it is unless the add carried, as in the EA tails) and
* DF looked at once. CMPS and SCAS go through the element
* routines at the end of the file, which are also what any
* awkward case falls back to: they work everything out for
* one element, wraps and all.
*
* With REP (str_rep) the pointers are worked out once for
* as many elements as fit before the nearest wrap (SI, DI
* or either host pointer reaching the end of its 64K), and
* that run is done by the 65816 itself: MOVS by MVN (MVP
* with DF set), STOS by storing one element and an MVN
* that overlaps it, SCASB and CMPSB by a loop over [ptr],y.
* Then the pointers again, until CX is 0. An element that
* lies across a wrap is one call of the element routine.
* What is left to rep_slow, an element routine per element:
* REP LODS, the word compares, and STOS, SCAS, CMPS with DF
* set.
*
* A REP string instruction retires through next_ct: it is
* one of the instructions that count the slot (cpu.s).
*----------------------------------------------------------

op_A4                      ; movsb
 mx %00
 lda vREP
 beq :one
 ldx #0
 jmp str_rep
:one
 bit vOVR
 bmi :sgen
 lda rSI
 clc
 adc bDS
 sta pSRC
 lda bDS+2
 sta pSRC+2
 bcc :s1
:sgen
 jsr str_src
:s1
 lda rDI
 clc
 adc bES
 sta pDST
 lda bES+2
 bcs :dgen
 sta pDST+2
 cmp #^H_TXT
 bne :d1
:dgen
 jsr str_dst
:d1
 sep #$20
 mx %10
 lda [pSRC]
 sta [pDST]
 rep #$20
 mx %00
 lda rFL
 and #F_DF
 bne :down
 inc rSI
 inc rDI
 jmp (NEXTVEC)
:down
 dec rSI
 dec rDI
 jmp (NEXTVEC)

op_A5                      ; movsw
 mx %00
 lda vREP
 beq :one
 ldx #2
 jmp str_rep
:one
 lda rSI                   ; a word at offset $FFFF: the element routine
 inc
 beq :slow
 lda rDI
 inc
 beq :slow
 bit vOVR
 bmi :sgen
 lda rSI
 clc
 adc bDS
 sta pSRC
 lda bDS+2
 sta pSRC+2
 bcc :s1
:sgen
 jsr str_src
:s1
 lda rDI
 clc
 adc bES
 sta pDST
 lda bES+2
 bcs :dgen
 sta pDST+2
 cmp #^H_TXT
 bne :d1
:dgen
 jsr str_dst
:d1
 lda [pSRC]
 sta [pDST]
 lda rFL
 and #F_DF
 bne :down
 inc rSI
 inc rSI
 inc rDI
 inc rDI
 jmp (NEXTVEC)
:down
 dec rSI
 dec rSI
 dec rDI
 dec rDI
 jmp (NEXTVEC)
:slow
 jsr movsw
 jmp (NEXTVEC)

op_A6                      ; cmpsb
 mx %00
 ldx #4
 bra str_one
op_A7                      ; cmpsw
 mx %00
 ldx #6
 bra str_one
op_AE                      ; scasb
 mx %00
 ldx #16
 bra str_one
op_AF                      ; scasw
 mx %00
 ldx #18
str_one                    ; X = the routine: once, or CX times
 mx %00
 lda vREP
 bne str_rep
 stx tmp7
 jsr str_call
 jmp (NEXTVEC)
str_rep
 mx %00
 stx tmp7
 lda rCX
 beq :none
 jmp (rep_tab,x)
:none
 jmp next_ct
rep_tab  da rep_movsb,rep_movsw,rep_cmpsb,rep_slow,rep_stosb,rep_stosw,rep_slow,rep_slow,rep_scasb,rep_slow

op_AA                      ; stosb
 mx %00
 lda vREP
 beq :one
 ldx #8
 jmp str_rep
:one
 lda rDI
 clc
 adc bES
 sta pDST
 lda bES+2
 bcs :dgen
 sta pDST+2
 cmp #^H_TXT
 bne :d1
:dgen
 jsr str_dst
:d1
 sep #$20
 mx %10
 lda rAX
 sta [pDST]
 rep #$20
 mx %00
 lda rFL
 and #F_DF
 bne :down
 inc rDI
 jmp (NEXTVEC)
:down
 dec rDI
 jmp (NEXTVEC)

op_AB                      ; stosw
 mx %00
 lda vREP
 beq :one
 ldx #10
 jmp str_rep
:one
 lda rDI
 inc
 beq :slow
 lda rDI
 clc
 adc bES
 sta pDST
 lda bES+2
 bcs :dgen
 sta pDST+2
 cmp #^H_TXT
 bne :d1
:dgen
 jsr str_dst
:d1
 lda rAX
 sta [pDST]
 lda rFL
 and #F_DF
 bne :down
 inc rDI
 inc rDI
 jmp (NEXTVEC)
:down
 dec rDI
 dec rDI
 jmp (NEXTVEC)
:slow
 jsr stosw
 jmp (NEXTVEC)

op_AC                      ; lodsb
 mx %00
 lda vREP
 beq :one
 ldx #12
 jmp str_rep
:one
 bit vOVR
 bmi :sgen
 lda rSI
 clc
 adc bDS
 sta pSRC
 lda bDS+2
 sta pSRC+2
 bcc :s1
:sgen
 jsr str_src
:s1
 sep #$20
 mx %10
 lda [pSRC]
 sta rAX
 rep #$20
 mx %00
 lda rFL
 and #F_DF
 bne :down
 inc rSI
 jmp (NEXTVEC)
:down
 dec rSI
 jmp (NEXTVEC)

op_AD                      ; lodsw
 mx %00
 lda vREP
 beq :one
 ldx #14
 jmp str_rep
:one
 lda rSI
 inc
 beq :slow
 bit vOVR
 bmi :sgen
 lda rSI
 clc
 adc bDS
 sta pSRC
 lda bDS+2
 sta pSRC+2
 bcc :s1
:sgen
 jsr str_src
:s1
 lda [pSRC]
 sta rAX
 lda rFL
 and #F_DF
 bne :down
 inc rSI
 inc rSI
 jmp (NEXTVEC)
:down
 dec rSI
 dec rSI
 jmp (NEXTVEC)
:slow
 jsr lodsw
 jmp (NEXTVEC)

*--- REP, an element routine per element
rep_slow
 mx %00
 jsr str_call
 dec rCX
 beq :done
 ldx tmp7
 lda str_cond,x
 beq rep_slow
 lda vREP
 cmp #$F3
 beq :repe
 lda vLP                   ; REPNE: stop once equal
 and #LP_ZF
 beq rep_slow
:done
 jmp next_ct
:repe
 lda vLP                   ; REPE: stop once not equal
 and #LP_ZF
 bne rep_slow
 jmp next_ct
str_call
 mx %00
 ldx tmp7
 jmp (str_tab,x)
str_tab  da movsb,movsw,cmpsb,cmpsw,stosb,stosw,lodsb,lodsw,scasb,scasw
str_cond dw 0,0,1,1,0,0,0,0,1,1

*--- REP MOVSB
rep_movsb
 mx %00
 lda rFL
 and #F_DF
 beq :fwd
 jmp mvb_bwd
:fwd
 jsr str_ptrs
 lda rCX                   ; the whole of it before any wrap?
 dec
 sta tmp2                  ; bytes - 1
 clc
 adc rSI
 bcs :lim
 lda tmp2
 adc rDI
 bcs :lim
 lda tmp2
 adc pSRC
 bcs :lim
 lda tmp2
 adc pDST
 bcs :lim
 lda rCX
 sta vCOUNT
 jsr mv_fwd
 jmp next_ct
:lim                       ; no: as far as the nearest wrap, then again
 lda rCX
 sta vCOUNT
 ldx #rSI
 jsr lim_fb
 ldx #rDI
 jsr lim_fb
 ldx #pSRC
 jsr lim_fb
 ldx #pDST
 jsr lim_fb
 lda vCOUNT
 dec
 sta tmp2
 jsr mv_fwd
 bne :fwd
 jmp next_ct
mvb_bwd                    ; DF set: the bytes at SI, SI-1, ...
 mx %00
 jsr str_ptrs
 lda rCX
 sta vCOUNT
 ldx #rSI
 jsr lim_bb
 ldx #rDI
 jsr lim_bb
 ldx #pSRC
 jsr lim_bb
 ldx #pDST
 jsr lim_bb
 lda vCOUNT
 dec
 sta tmp2
 lda pSRC
 sta tmp4
 lda pDST
 sta tmp5
 jsr mv_bwd
 bne mvb_bwd
 jmp next_ct

*--- REP MOVSW. A move by bytes in the direction of DF is the move by
* words, but for a destination one byte beyond the source in that
* direction (each word then reads a byte the word before it wrote, and
* a byte move would read it a byte early): that one is left to rep_slow.
rep_movsw
 mx %00
 lda rFL
 and #F_DF
 beq :fwd
 jmp mvw_bwd
:fwd
 jsr str_ptrs
 lda pSRC
 inc
 cmp pDST
 beq :slow
 lda rCX
 asl
 bcs :lim                  ; 64K and more: in parts
 dec
 sta tmp2                  ; bytes - 1
 adc rSI                   ; (carry is clear)
 bcs :lim
 lda tmp2
 adc rDI
 bcs :lim
 lda tmp2
 adc pSRC
 bcs :lim
 lda tmp2
 adc pDST
 bcs :lim
 lda rCX
 sta vCOUNT
 jsr mv_fwd
 jmp next_ct
:lim
 lda rCX
 sta vCOUNT
 ldx #rSI
 jsr lim_fw
 ldx #rDI
 jsr lim_fw
 ldx #pSRC
 jsr lim_fw
 ldx #pDST
 jsr lim_fw
 lda vCOUNT
 beq :elem
 asl
 dec
 sta tmp2
 jsr mv_fwd
 bne :fwd
 jmp next_ct
:elem                      ; a word across a wrap
 jsr movsw
 dec rCX
 bne :fwd
 jmp next_ct
:slow
 jmp rep_slow
mvw_bwd                    ; DF set: the words at SI, SI-2, ...
 mx %00
 jsr str_ptrs
 lda pDST
 inc
 cmp pSRC
 beq :slow
 lda #$FFFF                ; a word across a wrap
 cmp rSI
 beq :elem
 cmp rDI
 beq :elem
 cmp pSRC
 beq :elem
 cmp pDST
 beq :elem
 lda rCX
 sta vCOUNT
 ldx #rSI
 jsr lim_bw
 ldx #rDI
 jsr lim_bw
 ldx #pSRC
 jsr lim_bw
 ldx #pDST
 jsr lim_bw
 lda vCOUNT
 asl
 dec
 sta tmp2
 lda pSRC                  ; from the first word's high byte down
 inc
 sta tmp4
 lda pDST
 inc
 sta tmp5
 jsr mv_bwd
 bne mvw_bwd
 jmp next_ct
:elem
 jsr movsw
 dec rCX
 bne mvw_bwd
 jmp next_ct
:slow
 jmp rep_slow

*--- REP STOSB / STOSW (DF clear)
rep_stosb
 mx %00
 lda rFL
 and #F_DF
 beq :fwd
 jmp rep_slow
:fwd
 jsr str_dst0
 lda rCX
 sta vCOUNT
 ldx #rDI
 jsr lim_fb
 ldx #pDST
 jsr lim_fb
 sep #$20
 mx %10
 lda rAX
 sta [pDST]
 rep #$20
 mx %00
 lda vCOUNT
 dec
 sta tmp2
 lda #1
 jsr fill_go
 bne :fwd
 jmp next_ct
rep_stosw
 mx %00
 lda rFL
 and #F_DF
 beq :fwd
 jmp rep_slow
:fwd
 jsr str_dst0
 lda rCX
 sta vCOUNT
 ldx #rDI
 jsr lim_fw
 ldx #pDST
 jsr lim_fw
 lda vCOUNT
 beq :elem
 asl
 dec
 sta tmp2
 lda rAX
 sta [pDST]
 lda #2
 jsr fill_go
 bne :fwd
 jmp next_ct
:elem                      ; a word across a wrap
 jsr stosw
 dec rCX
 bne :fwd
 jmp next_ct

*--- REPE / REPNE SCASB (DF clear)
rep_scasb
 mx %00
 lda rFL
 and #F_DF
 beq :fwd
 jmp rep_slow
:fwd
 jsr str_dst0
 lda rCX
 sta vCOUNT
 ldx #rDI
 jsr lim_fb
 ldx #pDST
 jsr lim_fb
 sty rIP
 ldy #0
 lda vREP
 cmp #$F3
 sep #$20                  ; (Z is the compare's still)
 mx %10
 beq :repe
 lda rAX
:ne                        ; REPNE: on while they differ
 cmp [pDST],y
 beq :hit
 iny
 cpy vCOUNT
 bne :ne
 bra :ran
:repe
 lda rAX
:eq                        ; REPE: on while they are equal
 cmp [pDST],y
 bne :hit
 iny
 cpy vCOUNT
 bne :eq
:ran                       ; the run is done: the last element's flags
 dey
 ldx #0
 bra :flags
:hit                       ; the condition ended it at element Y
 ldx #1
:flags
 stx tmp3
 lda [pDST],y
 sta tmp0
 iny                       ; Y = elements done
 lda rAX
 sta tmp1
 sec
 sbc tmp0
 jsr flg_sub8_r
 mx %00
 tya
 clc
 adc rDI
 sta rDI
 sty tmp2
 ldy rIP
 lda rCX
 sec
 sbc tmp2
 sta rCX
 beq :done
 lda tmp3
 bne :done
 jmp :fwd
:done
 jmp next_ct

*--- REPE / REPNE CMPSB (DF clear)
rep_cmpsb
 mx %00
 lda rFL
 and #F_DF
 beq :fwd
 jmp rep_slow
:fwd
 jsr str_ptrs
 lda rCX
 sta vCOUNT
 ldx #rSI
 jsr lim_fb
 ldx #rDI
 jsr lim_fb
 ldx #pSRC
 jsr lim_fb
 ldx #pDST
 jsr lim_fb
 sty rIP
 ldy #0
 lda vREP
 cmp #$F3
 sep #$20
 mx %10
 beq :eq
:ne
 lda [pSRC],y
 cmp [pDST],y
 beq :hit
 iny
 cpy vCOUNT
 bne :ne
 bra :ran
:eq
 lda [pSRC],y
 cmp [pDST],y
 bne :hit
 iny
 cpy vCOUNT
 bne :eq
:ran
 dey
 ldx #0
 bra :flags
:hit
 ldx #1
:flags
 stx tmp3
 lda [pDST],y
 sta tmp0
 lda [pSRC],y
 sta tmp1
 iny                       ; Y = elements done (A and carry are not INY's)
 sec
 sbc tmp0
 jsr flg_sub8_r
 mx %00
 tya
 clc
 adc rSI
 sta rSI
 tya
 clc
 adc rDI
 sta rDI
 sty tmp2
 ldy rIP
 lda rCX
 sec
 sbc tmp2
 sta rCX
 beq :done
 lda tmp3
 bne :done
 jmp :fwd
:done
 jmp next_ct

*--- how many elements before a wrap: vCOUNT = min(vCOUNT, the
* number the 16-bit value at 0,x allows), going up (lim_f*) or
* down (lim_b*), bytes or words. A word count of 0 is a word
* that lies across the wrap.
lim_fb
 mx %00
 lda #0
 sec
 sbc 0,x
 beq :no                   ; from 0: all 64K
 cmp vCOUNT
 bcs :no
 sta vCOUNT
:no
 rts
lim_fw
 mx %00
 lda #0
 sec
 sbc 0,x
 ror                       ; (carry only from 0: $8000 words)
 cmp vCOUNT
 bcs :no
 sta vCOUNT
:no
 rts
lim_bb
 mx %00
 lda 0,x
 inc
 beq :no
 cmp vCOUNT
 bcs :no
 sta vCOUNT
:no
 rts
lim_bw                     ; (the caller has seen that it is not $FFFF)
 mx %00
 lda 0,x
 clc
 adc #2
 ror
 cmp vCOUNT
 bcs :no
 sta vCOUNT
:no
 rts

*--- the moves. tmp2 = bytes - 1, vCOUNT = elements; SI, DI and CX
* are brought up to date, Z set when CX is 0. Text-buffer pages are
* marked for the whole run.
mv_fwd                     ; pSRC -> pDST, upwards
 mx %00
 lda pDST+2
 cmp #^H_TXT
 bne :nv
 lda pDST
 sta tmp0
 clc
 adc tmp2
 sta tmp1
 jsr vid_mark_rng
:nv
 lda pSRC+1                ; the MVN's operand: destination bank, source bank
 and #$FF00
 ora pDST+2
 sta mvn_bk
 sty rIP
 ldx pSRC
 ldy pDST
 lda tmp2
 jsr mvn_go
 ldy rIP
 lda tmp2
 sec
 adc rSI
 sta rSI
 lda tmp2
 sec
 adc rDI
 sta rDI
 lda rCX
 sec
 sbc vCOUNT
 sta rCX
 rts
mv_bwd                     ; downwards from host offsets tmp4 (source) and tmp5
 mx %00
 lda pDST+2
 cmp #^H_TXT
 bne :nv
 lda tmp5
 sta tmp1
 sec
 sbc tmp2
 sta tmp0
 jsr vid_mark_rng
:nv
 lda pSRC+1
 and #$FF00
 ora pDST+2
 sta mvp_bk
 sty rIP
 ldx tmp4
 ldy tmp5
 lda tmp2
 jsr mvp_go
 ldy rIP
 lda rSI
 clc
 sbc tmp2
 sta rSI
 lda rDI
 clc
 sbc tmp2
 sta rDI
 lda rCX
 sec
 sbc vCOUNT
 sta rCX
 rts
* fill_go - the first element (A bytes) is at pDST: the rest of the
* tmp2+1 bytes by an MVN from it to just beyond it.
fill_go
 mx %00
 sta tmp3
 lda pDST+2
 cmp #^H_TXT
 bne :nv
 lda pDST
 sta tmp0
 clc
 adc tmp2
 sta tmp1
 jsr vid_mark_rng
:nv
 lda tmp2
 sec
 sbc tmp3                  ; the bytes still to fill, less one
 bcc :one
 pha
 lda pDST+1
 and #$FF00
 ora pDST+2
 sta mvn_bk
 sty rIP
 lda pDST
 tax
 clc
 adc tmp3
 tay
 pla
 jsr mvn_go
 ldy rIP
:one
 lda tmp2
 sec
 adc rDI
 sta rDI
 lda rCX
 sec
 sbc vCOUNT
 sta rCX
 rts
* mvn_go, mvp_go - A+1 bytes from X to Y in the banks written at
* mvn_bk / mvp_bk (the block moves leave DBR at the destination's).
mvn_go
 mx %00
 phb
 dfb $54
mvn_bk dfb 0,0
 plb
 rts
mvp_go
 mx %00
 phb
 dfb $44
mvp_bk dfb 0,0
 plb
 rts

*--- pointers and advances
str_ptrs                   ; pSRC and pDST
 mx %00
 jsr str_src
 bra str_dst0
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
str_dst                    ; pDST = ES:DI, its text page marked
 mx %00
 jsr str_dst0
 cmp #^H_TXT
 bne :ok
 jmp vid_mark_dst
:ok
 rts
str_dst0                   ; pDST = ES:DI; A = its bank word
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

*--- the element routines: one element, everything worked out
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
