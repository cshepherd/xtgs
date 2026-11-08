*----------------------------------------------------------
* cpu.s - the interpreter loop and its helpers.
*
* Conventions (BOOTSTRAP.md section 5): native mode, M=0
* X=0 at fetch and at retire, D = GUEST_DP, DBR = K = $03,
* Y = IP. A handler ends with JMP (NEXTVEC): normally
* `next`, which clears the prefixes, counts the slot and
* falls into `fetch`; the harness points it at step_done.
* Prefix handlers JMP fetch directly so a prefixed
* instruction retires as one.
*----------------------------------------------------------
 err NEXTVEC-GUEST_DP-vNEXT
 err HALTVEC-GUEST_DP-vHALTVEC

*--- retire, then fetch and dispatch the next instruction
next
 mx %00
 stz vSEGOVR
 stz vREP
 dec vSLOT
 bne fetch
 jmp slot
fetch
 mx %00
 lda [bCS],y
 iny
 and #$00FF
 asl
 tax
 jmp (optab,x)

*--- every SLOT_N instructions: the counters; later the VBL
* tick, the keyboard and interrupt delivery.
slot
 mx %00
 lda #SLOT_N
 sta vSLOT
 lda vICOUNT
 clc
 adc #SLOT_N
 sta vICOUNT
 bcc :nc
 inc vICOUNT+2
:nc
 jmp fetch

*--- prefixes: note it and fetch the next byte
op_26
 mx %00
 lda #bES
 sta vSEGOVR
 jmp fetch
op_2E
 mx %00
 lda #bCS
 sta vSEGOVR
 jmp fetch
op_36
 mx %00
 lda #bSS
 sta vSEGOVR
 jmp fetch
op_3E
 mx %00
 lda #bDS
 sta vSEGOVR
 jmp fetch
op_F0                      ; LOCK
 mx %00
 jmp fetch
op_F2                      ; REPNE
 mx %00
 lda #$F2
 sta vREP
 jmp fetch
op_F3                      ; REP / REPE
 mx %00
 lda #$F3
 sta vREP
 jmp fetch

*--- ModR/M: fetch the byte and dispatch to its routine
* (gen/eatab.s), which sets vREGOFF and pEA (vEA too for a
* memory operand) and returns to our caller.
modrm_b
 mx %00
 lda [bCS],y
 iny
 and #$00FF
 sta vMODRM
 asl
 tax
 jmp (eatab_b,x)
modrm_w
 mx %00
 lda [bCS],y
 iny
 and #$00FF
 sta vMODRM
 asl
 tax
 jmp (eatab_w,x)

*--- effective-address tails. On entry vEA is the offset;
* X becomes the DP offset of the segment base after the
* override; pEA = base + vEA, wrapped to the guest's 1 MiB
* (the 1 MiB-aligned GUEST_BASE makes that an AND/ORA).
ea_ds_b
 mx %00
 ldx vSEGOVR
 bne ea_seg_b
 ldx #bDS
 bra ea_seg_b
ea_ss_b
 mx %00
 ldx vSEGOVR
 bne ea_seg_b
 ldx #bSS
ea_seg_b
 mx %00
 stx vEASEG
 lda vEA
 clc
 adc 0,x
 sta pEA
 lda 2,x
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pEA+2
 rts

* Word operands: an offset of $FFFF wraps within the
* segment (second byte at offset 0), so that case goes
* through a bounce word in the direct page.
ea_ds_w
 mx %00
 ldx vSEGOVR
 bne ea_seg_w
 ldx #bDS
 bra ea_seg_w
ea_ss_w
 mx %00
 ldx vSEGOVR
 bne ea_seg_w
 ldx #bSS
ea_seg_w
 mx %00
 stx vEASEG
 lda vEA
 cmp #$FFFF
 beq ea_split
 clc
 adc 0,x
 sta pEA
 lda 2,x
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pEA+2
 rts
ea_split
 mx %00
 lda 0,x                   ; seg:FFFF
 clc
 adc #$FFFF
 sta pSPLIT
 lda 2,x
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pSPLIT+2
 lda 0,x                   ; seg:0000
 sta pTMP
 lda 2,x
 sta pTMP+2
 sep #$20
 mx %10
 lda [pSPLIT]
 sta vBOUNCE
 lda [pTMP]
 sta vBOUNCE+1
 rep #$20
 mx %00
 lda #GUEST_DP+vBOUNCE
 sta pEA
 stz pEA+2
 lda vNEXT
 sta vNEXT2
 lda #split_retire
 sta vNEXT
 rts
* ea_plus2 - pEA for the word at vEA+2 in the same segment (the
* segment half of a far pointer), wrapping within the segment.
ea_plus2
 mx %00
 lda vEA
 inc
 inc
 sta vEA
 ldx vEASEG
 jmp ea_seg_w

split_retire               ; write the bounce word back, then retire
 mx %00
 sep #$20
 mx %10
 lda vBOUNCE
 sta [pSPLIT]
 lda vBOUNCE+1
 sta [pTMP]
 rep #$20
 mx %00
 lda vNEXT2
 sta vNEXT
 jmp (NEXTVEC)

*--- segment bases: bXX = GUEST_BASE + (seg << 4), as lo16
* and a bank word, wrapped to 20 bits.
set_es
 mx %00
 lda rES
 asl
 asl
 asl
 asl
 sta bES
 lda rES
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 ora #GUEST_BANK
 sta bES+2
 rts
set_cs
 mx %00
 lda rCS
 asl
 asl
 asl
 asl
 sta bCS
 lda rCS
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 ora #GUEST_BANK
 sta bCS+2
 rts
set_ss
 mx %00
 lda rSS
 asl
 asl
 asl
 asl
 sta bSS
 lda rSS
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 ora #GUEST_BANK
 sta bSS+2
 rts
set_ds
 mx %00
 lda rDS
 asl
 asl
 asl
 asl
 sta bDS
 lda rDS
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 ora #GUEST_BANK
 sta bDS+2
 rts
set_seg_x                  ; X = sreg number * 2 (ES CS SS DS)
 mx %00
 jmp (setseg_tab,x)
setseg_tab da set_es,set_cs,set_ss,set_ds
set_all_bases
 mx %00
 jsr set_es
 jsr set_cs
 jsr set_ss
 jmp set_ds

*--- stack: push16 pushes A at SS:SP-2; pop16 returns the
* word at SS:SP and adds 2. Both preserve X and Y. SP = $FFFF
* splits the word across SS:FFFF and SS:0000.
push16
 mx %00
 sta tmp4
 lda rSP
 dec
 dec
 sta rSP
 cmp #$FFFF
 beq :split
 clc
 adc bSS
 sta pSTK
 lda bSS+2
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pSTK+2
 lda tmp4
 sta [pSTK]
 rts
:split
 jsr stk_split
 sep #$20
 mx %10
 lda tmp4
 sta [pSTK]
 lda tmp4+1
 sta [pSTK2]
 rep #$20
 mx %00
 rts
pop16
 mx %00
 lda rSP
 cmp #$FFFF
 beq :split
 clc
 adc bSS
 sta pSTK
 lda bSS+2
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pSTK+2
 lda rSP
 inc
 inc
 sta rSP
 lda [pSTK]
 rts
:split
 jsr stk_split
 lda rSP
 inc
 inc
 sta rSP
 sep #$20
 mx %10
 lda [pSTK]
 sta tmp4
 lda [pSTK2]
 sta tmp4+1
 rep #$20
 mx %00
 lda tmp4
 rts
stk_split                  ; pSTK = SS:FFFF, pSTK2 = SS:0000
 mx %00
 lda bSS
 clc
 adc #$FFFF
 sta pSTK
 lda bSS+2
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pSTK+2
 lda bSS
 sta pSTK2
 lda bSS+2
 sta pSTK2+2
 rts

*--- do_int: A = vector. rIP holds the return IP (the caller
* stored Y there). Pushes FLAGS, CS, IP; clears IF and TF;
* loads CS:IP from the IVT. Y = the new IP on return.
do_int
 mx %00
 sta tmp6
 jsr flags_get
 jsr push16
 lda rFL
 and #$FCFF
 sta rFL
 lda rCS
 jsr push16
 lda rIP
 jsr push16
 lda tmp6
 asl
 asl
 sta pSTK
 lda #GUEST_BANK
 sta pSTK+2
 ldy #2
 lda [pSTK],y
 sta rCS
 jsr set_cs
 lda [pSTK]
 tay
 rts

*--- unimplemented or undefined: count it and move on
op_bad
 mx %00
 inc vBAD
 jmp (NEXTVEC)
