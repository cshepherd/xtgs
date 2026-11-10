*----------------------------------------------------------
* ops_ctrl.s - control transfer: Jcc tails, LOOP, JCXZ,
* JMP, CALL, RET, INT, IRET, HLT, and the FE/FF groups.
*----------------------------------------------------------

* The Jcc tails live in gen/alu.s among the Jcc handlers;
* these trampolines put them within a short branch of here.
jcc_t
 mx %00
 jmp jcc_taken
jcc_n
 mx %00
 jmp jcc_not

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
 lda rFL
 and #F_ZF
 bne jcc_t
 bra jcc_n
op_E0                      ; loopne / loopnz
 mx %00
 dec rCX
 beq jcc_n
 lda rFL
 and #F_ZF
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
 jmp (NEXTVEC)
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
 jmp (NEXTVEC)
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
 jmp (NEXTVEC)
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
 jmp (NEXTVEC)
op_C3                      ; ret
 mx %00
 jsr pop16
 tay
 jmp (NEXTVEC)
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
 jmp (NEXTVEC)
op_CB                      ; retf
 mx %00
 jsr pop16
 sta tmp1
 jsr pop16
 sta rCS
 jsr set_cs
 ldy tmp1
 jmp (NEXTVEC)
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
 jmp (NEXTVEC)
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
 jmp (NEXTVEC)
op_CC                      ; int 3
 mx %00
 sty rIP
 lda #3
 jsr do_int
 jmp (NEXTVEC)
op_CE                      ; into
 mx %00
 lda vOF
 beq :no
 sty rIP
 lda #4
 jsr do_int
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
 jmp (NEXTVEC)
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
 sta tmp1
 inc
 sta [pEA]
 jmp flg_inc16
gFF_1                      ; dec r/m16
 mx %00
 lda [pEA]
 sta tmp1
 dec
 sta [pEA]
 jmp flg_dec16
gFF_2                      ; call r/m16
 mx %00
 lda [pEA]
 sta tmp0
 tya
 jsr push16
 ldy tmp0
 jmp (NEXTVEC)
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
 jmp (NEXTVEC)
gFF_4                      ; jmp r/m16
 mx %00
 lda [pEA]
 tay
 jmp (NEXTVEC)
gFF_5                      ; jmp far m16:16
 mx %00
 lda [pEA]
 sta tmp0
 jsr ea_plus2
 lda [pEA]
 sta rCS
 jsr set_cs
 ldy tmp0
 jmp (NEXTVEC)
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
 ldy rIP
 jmp (NEXTVEC)
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
 sta tmp1
 inc
 sta [pEA]
 jmp flg_inc8
gFE_1                      ; dec r/m8
 mx %00
 sep #$20
 mx %10
 lda [pEA]
 sta tmp1
 dec
 sta [pEA]
 jmp flg_dec8
