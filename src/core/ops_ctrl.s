*----------------------------------------------------------
* ops_ctrl.s - control transfer: Jcc tails, LOOP, JCXZ,
* JMP, CALL, RET, INT, IRET, HLT, and the FE/FF groups.
* A transfer that is taken counts the slot as it retires
* (next_ct in cpu.s, or its three lines inline).
*----------------------------------------------------------

* The Jcc tails live in gen/alu.s among the Jcc handlers;
* these trampolines put them within a short branch of here.
jcc_t
 mx %00
 jmp jcc_taken
jcc_n
 mx %00
 iny
 jmp (NEXTVEC)

op_E3                      ; jcxz
 mx %00
 lda rCX
 beq jcc_t
 bra jcc_n
op_E2                      ; loop
 mx %00
 dec rCX
 bne jcc_t
 bra jcc_n
op_E1                      ; loope / loopz
 mx %00
 dec rCX
 beq jcc_n
 lda vLP
 and #LP_ZF
 bne jcc_t
 bra jcc_n
op_E0                      ; loopne / loopnz
 mx %00
 dec rCX
 beq jcc_n
 lda vLP
 and #LP_ZF
 beq jcc_t
 bra jcc_n
op_EB                      ; jmp rel8
 mx %00
 bra jcc_t
op_E9                      ; jmp rel16
 mx %00
 lda [bCS],y
 iny
 iny
 sta tmp0
 tya
 clc
 adc tmp0
 tay
 dec vSLOT
 beq :due
 jmp (NEXTVEC)
:due
 jmp next_due
op_E8                      ; call rel16
 mx %00
 lda [bCS],y
 iny
 iny
 sta tmp0
 tya
 clc
 adc tmp0
 sta tmp1
 tya
 jsr push16
 ldy tmp1
 dec vSLOT
 beq :due
 jmp (NEXTVEC)
:due
 jmp next_due
op_EA                      ; jmp far ptr16:16
 mx %00
 lda [bCS],y
 iny
 iny
 sta tmp0
 lda [bCS],y
 sta rCS
 jsr set_cs
 ldy tmp0
 jmp next_ct
op_9A                      ; call far ptr16:16
 mx %00
 lda [bCS],y
 iny
 iny
 sta tmp0
 lda [bCS],y
 iny
 iny
 sta tmp1
 lda rCS
 jsr push16
 tya
 jsr push16
 lda tmp1
 sta rCS
 jsr set_cs
 ldy tmp0
 jmp next_ct
op_C3                      ; ret
 mx %00
 jsr pop16
 tay
 dec vSLOT
 beq :due
 jmp (NEXTVEC)
:due
 jmp next_due
op_C2                      ; ret imm16
 mx %00
 lda [bCS],y
 iny
 iny
 sta tmp0
 jsr pop16
 tay
 lda rSP
 clc
 adc tmp0
 sta rSP
 jmp next_ct
op_CB                      ; retf
 mx %00
 jsr pop16
 sta tmp1
 jsr pop16
 sta rCS
 jsr set_cs
 ldy tmp1
 jmp next_ct
op_CA                      ; retf imm16
 mx %00
 lda [bCS],y
 iny
 iny
 sta tmp0
 jsr pop16
 sta tmp1
 jsr pop16
 sta rCS
 jsr set_cs
 lda rSP
 clc
 adc tmp0
 sta rSP
 ldy tmp1
 jmp next_ct
op_CF                      ; iret
 mx %00
 jsr pop16
 sta tmp1
 jsr pop16
 sta rCS
 jsr set_cs
 jsr pop16
 jsr flags_set
 ldy tmp1
 jmp irq_soon              ; (an interrupt owed is taken now)
op_CD                      ; int imm8
 mx %00
 lda [bCS],y
 iny
 sty rIP
 and #$00FF
 jsr do_int
 jmp next_ct
op_CC                      ; int 3
 mx %00
 sty rIP
 lda #3
 jsr do_int
 jmp next_ct
op_CE                      ; into
 mx %00
 lda vLP
 and #LP_OF
 beq :no
 sty rIP
 lda #4
 jsr do_int
 jmp next_ct
:no
 jmp (NEXTVEC)
op_F4                      ; hlt. In Mode B an idle STI;HLT waits for the next
 mx %00                    ; interrupt, not a program exit: resume and let the
 lda vPCMODE               ; slot check deliver IRQ0 and poll the keyboard. The
 cmp #2                    ; bench/.COM paths (HLT = exit) and a genuine CLI;HLT
 bne :term                 ; (nothing can wake it) still end the run.
 lda rFL
 and #F_IF
 beq :term
 lda #1                    ; (the slot looks at every HLT)
 sta vSLOT
 jmp next_ct
:term
 lda #1
 sta vHALT
 jmp (HALTVEC)

*--- group 5: inc/dec/call/callf/jmp/jmpf/push r/m16
op_FF
 mx %00
 jsr modrm_w
 lda vMODRM
 and #$0038
 lsr
 lsr
 tax
 jmp (gFF_tab,x)
gFF_tab da gFF_0,gFF_1,gFF_2,gFF_3,gFF_4,gFF_5,gFF_6,gFF_6
gFF_0                      ; inc r/m16
 mx %00
 lda [pEA]
 sta vFD
 clc
 adc #1
 sta [pEA]
 jmp flg_incdec16
gFF_1                      ; dec r/m16
 mx %00
 lda [pEA]
 sta vFD
 sec
 sbc #1
 sta [pEA]
 jmp flg_incdec16
gFF_2                      ; call r/m16
 mx %00
 lda [pEA]
 sta tmp0
 tya
 jsr push16
 ldy tmp0
 dec vSLOT
 beq :due
 jmp (NEXTVEC)
:due
 jmp next_due
gFF_3                      ; call far m16:16
 mx %00
 sty rIP
 lda [pEA]
 sta tmp0
 jsr ea_plus2
 lda [pEA]
 sta tmp1
 lda rCS
 jsr push16
 lda rIP
 jsr push16
 lda tmp1
 sta rCS
 jsr set_cs
 ldy tmp0
 jmp next_ct
gFF_4                      ; jmp r/m16
 mx %00
 lda [pEA]
 tay
 dec vSLOT
 beq :due
 jmp (NEXTVEC)
:due
 jmp next_due
gFF_5                      ; jmp far m16:16
 mx %00
 lda [pEA]
 sta tmp0
 jsr ea_plus2
 lda [pEA]
 sta rCS
 jsr set_cs
 ldy tmp0
 jmp next_ct
gFF_6                      ; push r/m16 (push sp pushes the new value)
 mx %00
 lda pEA+2
 bne :mem
 lda pEA
 cmp #GUEST_DP+rSP
 bne :mem
 lda rSP
 dec
 dec
 jsr push16
 jmp (NEXTVEC)
:mem
 lda [pEA]
 jsr push16
 jmp (NEXTVEC)

*--- group 4: inc/dec r/m8; FE /7 with mod=0 rm=0 (FE 38) is
* the XT/GS hypercall: the next word selects a service.
op_FE
 mx %00
 lda [bCS],y
 and #$00FF
 cmp #$38
 beq :hyper
 jsr modrm_b
 lda vMODRM
 and #$0038
 lsr
 lsr
 tax
 jmp (gFE_tab,x)
:hyper
 iny
 lda [bCS],y
 iny
 iny
 sty rIP
 jsl SVC_BASE+12
 bcs :stop
 lda >EGA_SYNC             ; the BIOS changed the EGA's mode or registers
 beq :nosync
 jsr ega_sync
:nosync
 ldy rIP
 jmp next_ct               ; (a service that waits asks for the slot: vSLOT = 1)
:stop                      ; the program terminated: A = exit code
 sta vEXIT
 ldy rIP
 jmp (HALTVEC)
gFE_tab da gFE_0,gFE_1,op_bad,op_bad,op_bad,op_bad,op_bad,op_bad
gFE_0                      ; inc r/m8
 mx %00
 sep #$20
 mx %10
 lda [pEA]
 sta vFD
 clc
 adc #1
 sta [pEA]
 jmp flg_incdec8
gFE_1                      ; dec r/m8
 mx %00
 sep #$20
 mx %10
 lda [pEA]
 sta vFD
 sec
 sbc #1
 sta [pEA]
 jmp flg_incdec8
