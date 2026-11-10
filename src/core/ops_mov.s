*----------------------------------------------------------
* ops_mov.s - data movement: MOV, XCHG, LEA, LDS/LES, XLAT,
* CBW/CWD, LAHF/SAHF, PUSH/POP sreg, PUSHF/POPF, POP r/m.
*----------------------------------------------------------

* (MOV r/m,reg and reg,r/m, 88-8B, are generated: gen/alu.s)
op_8C                      ; mov r/m16, sreg (reg bit 2 ignored, as the 8086)
 mx %00
 jsr modrm_w
 lda vMODRM
 and #$0018
 lsr
 lsr
 tax
 lda rES,x
 sta [pEA]
 jmp (NEXTVEC)
op_8E                      ; mov sreg, r/m16
 mx %00
 jsr modrm_w
 lda [pEA]
 sta tmp0
 lda vMODRM
 and #$0018
 lsr
 lsr
 tax
 lda tmp0
 sta rES,x
 jsr set_seg_x
 jmp (NEXTVEC)
op_8D                      ; lea r16, m
 mx %00
 jsr modrm_w
 lda vEA
 ldx vREGOFF
 sta 0,x
 jmp (NEXTVEC)
op_8F                      ; pop r/m16
 mx %00
 jsr modrm_w
 jsr pop16
 sta [pEA]
 jmp (NEXTVEC)

op_A0                      ; mov AL, [moffs16]
 mx %00
 jsr emb_06                ; [disp16], DS or the override
 sep #$20
 mx %10
 lda [pEA]
 sta rAX
 rep #$20
 mx %00
 jmp (NEXTVEC)
op_A1                      ; mov AX, [moffs16]
 mx %00
 jsr emw_06                ; [disp16], DS or the override
 lda [pEA]
 sta rAX
 jmp (NEXTVEC)
op_A2                      ; mov [moffs16], AL
 mx %00
 jsr emb_06                ; [disp16], DS or the override
 sep #$20
 mx %10
 lda rAX
 sta [pEA]
 rep #$20
 mx %00
 jmp (NEXTVEC)
op_A3                      ; mov [moffs16], AX
 mx %00
 jsr emw_06                ; [disp16], DS or the override
 lda rAX
 sta [pEA]
 jmp (NEXTVEC)

op_86                      ; xchg r/m8, r8
 mx %00
 jsr modrm_b
 sep #$20
 mx %10
 ldx vREGOFF
 lda 0,x
 pha
 lda [pEA]
 sta 0,x
 pla
 sta [pEA]
 rep #$20
 mx %00
 jmp (NEXTVEC)
op_87                      ; xchg r/m16, r16
 mx %00
 jsr modrm_w
 ldx vREGOFF
 lda 0,x
 pha
 lda [pEA]
 sta 0,x
 pla
 sta [pEA]
 jmp (NEXTVEC)
op_90                      ; nop (xchg ax, ax)
 mx %00
 jmp (NEXTVEC)

op_98                      ; cbw
 mx %00
 lda rAX
 and #$00FF
 eor #$80
 sec
 sbc #$80
 sta rAX
 jmp (NEXTVEC)
op_99                      ; cwd
 mx %00
 lda rAX
 bmi :neg
 stz rDX
 jmp (NEXTVEC)
:neg
 lda #$FFFF
 sta rDX
 jmp (NEXTVEC)

op_9E                      ; sahf: SF ZF AF PF CF from AH
 mx %00
 lda vLP
 and #LP_OF
 sta tmp4
 lda rAX+1
 and #$00FF
 jsr flags_low
 jmp (NEXTVEC)
op_9F                      ; lahf
 mx %00
 jsr flags_get
 sep #$20
 mx %10
 sta rAX+1
 rep #$20
 mx %00
 jmp (NEXTVEC)

op_D7                      ; xlat: AL = [DS:BX+AL]
 mx %00
 lda rAX
 and #$00FF
 clc
 adc rBX
 sta vEA
 jsr ea_ds_b
 sep #$20
 mx %10
 lda [pEA]
 sta rAX
 rep #$20
 mx %00
 jmp (NEXTVEC)

op_C4                      ; les r16, m32
 mx %00
 jsr modrm_w
 sty rIP
 lda [pEA]
 ldx vREGOFF
 sta 0,x
 lda vMODRM
 and #$00C0
 cmp #$00C0
 beq :reg
 jsr ea_plus2
 lda [pEA]
 bra :seg
:reg                       ; register form (undefined): the next register
 ldy #2
 lda [pEA],y
:seg
 sta rES
 jsr set_es
 ldy rIP
 jmp (NEXTVEC)
op_C5                      ; lds r16, m32
 mx %00
 jsr modrm_w
 sty rIP
 lda [pEA]
 ldx vREGOFF
 sta 0,x
 lda vMODRM
 and #$00C0
 cmp #$00C0
 beq :reg
 jsr ea_plus2
 lda [pEA]
 bra :seg
:reg                       ; register form (undefined): the next register
 ldy #2
 lda [pEA],y
:seg
 sta rDS
 jsr set_ds
 ldy rIP
 jmp (NEXTVEC)
op_C6                      ; mov r/m8, imm8
 mx %00
 jsr modrm_b
 lda [bCS],y
 iny
 sep #$20
 mx %10
 sta [pEA]
 rep #$20
 mx %00
 jmp (NEXTVEC)
op_C7                      ; mov r/m16, imm16
 mx %00
 jsr modrm_w
 lda [bCS],y
 iny
 iny
 sta [pEA]
 jmp (NEXTVEC)

*--- segment register pushes and pops (0F is POP CS on an 8086)
op_06
 mx %00
 lda rES
 jsr push16
 jmp (NEXTVEC)
op_07
 mx %00
 jsr pop16
 sta rES
 jsr set_es
 jmp (NEXTVEC)
op_0E
 mx %00
 lda rCS
 jsr push16
 jmp (NEXTVEC)
op_0F
 mx %00
 jsr pop16
 sta rCS
 jsr set_cs
 jmp (NEXTVEC)
op_16
 mx %00
 lda rSS
 jsr push16
 jmp (NEXTVEC)
op_17
 mx %00
 jsr pop16
 sta rSS
 jsr set_ss
 jmp (NEXTVEC)
op_1E
 mx %00
 lda rDS
 jsr push16
 jmp (NEXTVEC)
op_1F
 mx %00
 jsr pop16
 sta rDS
 jsr set_ds
 jmp (NEXTVEC)
op_9C                      ; pushf
 mx %00
 jsr flags_get
 jsr push16
 jmp (NEXTVEC)
op_9D                      ; popf
 mx %00
 jsr pop16
 jsr flags_set
 jmp irq_soon

*--- test
* (TEST r/m,reg, 84/85, is generated: gen/alu.s)
op_A8                      ; test AL, imm8
 mx %00
 lda [bCS],y
 iny
 sep #$20
 mx %10
 sta tmp0
 lda rAX
 and tmp0
 jmp flg_log8
op_A9                      ; test AX, imm16
 mx %00
 lda [bCS],y
 iny
 iny
 sta tmp0
 lda rAX
 and tmp0
 jmp flg_log16
