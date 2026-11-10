*----------------------------------------------------------
* flags.s - guest FLAGS, kept lazily.
*
* An arithmetic instruction does not build the 8086's FLAGS.
* It leaves what they can be worked out from:
*
*   vLP    low byte: the 65816's P after the operation, read
*          as LP_SF ($80, N) LP_OF ($40, V) LP_ZF ($02, Z)
*          LP_CF ($01: the 8086's carry, so a subtraction
*          inverts C before it stores). LP_AFD ($08) says AF
*          is LP_AF ($10) and not the operands'; the core
*          runs with D and X clear, so a P pushed as it is
*          says "from the operands". Bits $20, $04 and the
*          high byte are whatever they were: mask them.
*   vLRES  low byte: the result's, for PF (the parity table)
*   vFS, vFD  source and destination before the operation:
*          AF is bit 4 of vFS ^ vFD ^ vLRES
*
* rFL holds TF, IF and DF only (bits 8-10); its other bits
* are not read. flags_get assembles the word the guest sees
* (PUSHF, an interrupt, LAHF, the harness), flags_set takes
* one apart (POPF, IRET).
*
* The generated ALU handlers (gen/alu.s) have their tails
* inline. The ones here are for the hand-written handlers:
* tail-called with the result in A (M=1 for byte, M=0 for
* word) and the 65816's N V Z C still those of the
* operation; flg_sub8/16 expect vFS and vFD set by the
* handler. The _r forms return instead of retiring, with
* 16-bit A, and take the operands as tmp0 (source) and tmp1
* (destination): the string compares and the divide traps.
*
* The decimal adjusts work on an 8086 FLAGS byte: flg_sync
* puts one in rFL (and OF in vOF, $0080 or 0) before them
* and flg_commit takes it back and retires.
*----------------------------------------------------------

flags_get                  ; A = FLAGS as the guest sees them (X, tmp4 used)
 mx %00
 lda vLRES
 and #$00FF
 tax
 lda parity,x
 and #F_PF
 sta tmp4
 lda vLP
 bit #LP_AFD
 bne :direct
 lda vFS
 eor vFD
 eor vLRES
 and #F_AF
 tsb tmp4
 lda vLP
:direct
 and #$00FF
 asl
 tax
 lda rFL
 and #F_TF+F_IF+F_DF
 ora lp2f,x                ; SF ZF CF OF, AF when LP_AFD, the fixed bits
 ora tmp4
 rts

flags_set                  ; A = FLAGS to load (X, tmp4 used)
 mx %00
 sta rFL
 and #F_OF
 xba
 asl
 asl
 asl                       ; LP_OF
 sta tmp4
 lda rFL
 and #$00FF
flags_low                  ; A = FLAGS' low byte, tmp4 = LP_OF or 0
 mx %00
 tax
 and #F_PF
 eor #F_PF
 sta vLRES                 ; $00 has even parity, $04 odd
 lda f2lp,x
 and #$00FF
 ora tmp4
 sta vLP
 rts

flg_sync                   ; the lazy flags into rFL's low byte and vOF
 mx %00
 jsr flags_get
 sta rFL
 and #F_OF
 beq :clr
 lda #$0080
:clr
 sta vOF
 rts

flg_commit                 ; rFL's low byte and vOF back, and retire
 mx %00
 lda vOF
 and #$0080
 asl
 asl
 asl
 asl
 sta tmp4
 lda rFL
 and #$07D7
 ora tmp4
 jsr flags_set
 jmp (NEXTVEC)

*--- sub / sbb / cmp / neg (CF = NOT C)
flg_sub16
 mx %00
 sta vLRES
 php
 php
 pla
 eor #LP_CF
 sta vLP
 jmp (NEXTVEC)
flg_sub16_r
 mx %00
 sta vLRES
 php
 php
 lda tmp0
 sta vFS
 lda tmp1
 sta vFD
 pla
 eor #LP_CF
 sta vLP
 rts

flg_sub8
 mx %10
 sta vLRES
 php
 pla
 eor #LP_CF
 sta vLP
 rep #$20
 mx %00
 jmp (NEXTVEC)
flg_sub8_r
 mx %10
 sta vLRES
 php
 lda tmp0
 sta vFS
 lda tmp1
 sta vFD
 pla
 eor #LP_CF
 sta vLP
 rep #$20
 mx %00
 rts

*--- and / or / xor / test (CF = OF = 0, AF cleared)
flg_log16
 mx %00
 sta vLRES
 beq :z
 bmi :n
 lda #LP_AFD
 sta vLP
 jmp (NEXTVEC)
:n
 lda #LP_AFD+LP_SF
 sta vLP
 jmp (NEXTVEC)
:z
 lda #LP_AFD+LP_ZF
 sta vLP
 jmp (NEXTVEC)

flg_log8
 mx %10
 sta vLRES
 beq :z
 bmi :n
 lda #LP_AFD
 bra :s
:n
 lda #LP_AFD+LP_SF
 bra :s
:z
 lda #LP_AFD+LP_ZF
:s
 sta vLP
 rep #$20
 mx %00
 jmp (NEXTVEC)

*--- inc / dec, done as an add or subtract of 1 (so V is OF)
* with vFD the value before: CF kept, AF from the operands
* (a source of 1 has no bit 4: vFS = 0 serves).
flg_incdec16
 mx %00
 sta vLRES
 stz vFS
 php
 php
 pla
 eor vLP
 and #$00FE
 eor vLP
 sta vLP
 jmp (NEXTVEC)
flg_incdec8
 mx %10
 sta vLRES
 stz vFS
 php
 pla
 eor vLP
 and #$FE
 eor vLP
 sta vLP
 rep #$20
 mx %00
 jmp (NEXTVEC)

*--- multiply: A = the high half; CF = OF = (A != 0)
flg_mul
 mx %00
 bne :set
 lda vLP
 and #$FFFF-LP_CF-LP_OF
 sta vLP
 jmp (NEXTVEC)
:set
 lda vLP
 ora #LP_CF+LP_OF
 sta vLP
 jmp (NEXTVEC)

*--- shifts: result in tmp1, CF in vCF (0/1), OF in vOF
* ($80/0); SF ZF PF from the result, AF cleared.
flg_shift16
 mx %00
 jsr flg_cfof
 ora #LP_AFD
 sta tmp2
 lda tmp1
 sta vLRES
 beq :z
 bpl :s
 lda #LP_SF
 tsb tmp2
 bra :s
:z
 lda #LP_ZF
 tsb tmp2
:s
 lda tmp2
 sta vLP
 jmp (NEXTVEC)

flg_shift8
 mx %10
 rep #$20
 mx %00
 jsr flg_cfof
 ora #LP_AFD
 sta tmp2
 lda tmp1
 and #$00FF
 sta vLRES
 beq :z
 bit #$0080
 beq :s
 lda #LP_SF
 tsb tmp2
 bra :s
:z
 lda #LP_ZF
 tsb tmp2
:s
 lda tmp2
 sta vLP
 jmp (NEXTVEC)

*--- rotates: only CF (vCF) and OF (vOF) change
flg_rot
 mx %00
 jsr flg_cfof
 sta tmp2
 lda vLP
 and #$FFFF-LP_CF-LP_OF
 ora tmp2
 sta vLP
 jmp (NEXTVEC)

flg_cfof                   ; A = LP_CF and LP_OF from vCF and vOF
 mx %00
 lda vOF
 and #$0080
 lsr
 sta tmp2
 lda vCF
 and #$0001
 ora tmp2
 rts
