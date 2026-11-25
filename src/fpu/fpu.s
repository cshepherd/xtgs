*----------------------------------------------------------
* FPU - the 8087 (docs/8087.md; the plan is
* XTGS-M9-8087-SANE.md). An image of its own, in the data
* region's bank (FPU_BASE: a PC has no other use for that
* region), which both front ends load when the file FPU is
* beside CORE and which the core uses when XTGS.CMD says
* FPU=8087 (fpu_start, src/core/ops_misc.s: the eight ESC
* opcodes are then its handlers, and without it they are
* what they were).
*
* Its arithmetic is SANE's, the tool set the front end has
* started for it: add, subtract, multiply, divide, compare,
* square root, scale, round to an integer, the conversions out
* of extended, and (Elems816) the logarithms, the exponential,
* the tangent and the arctangent. What only moves a number or
* changes its sign is done here, and so are the conversions
* into extended, which are exact, the partial remainder, the
* extraction of exponent and significand, and packed decimal.
*
* Entries (JSL; native, 16-bit; D the guest's direct page):
*   +0  fp_init   a PC starts: the 8087 as FNINIT leaves it
*   +3  fp_esc    an ESC instruction. A = the opcode's low
*                 three bits (D8 is 0), and the core's
*                 modrm_b has been through the ModR/M byte:
*                 vMODRM, and for a memory operand vEA,
*                 vEASEG and pEA. X = the IP after the
*                 opcode. Y, the guest's IP, is kept. Carry set
*                 on the way out: the 8087 asks for its interrupt
*                 (the core takes INT 2, a PC/XT's NMI).
*
* The state is in the results bank (FPU_*, src/include/pc.s),
* where a saved state has it: the control word, the status
* word less the stack's top (FPU_TOP) and less what SANE has
* flagged since it was last asked, and the eight registers,
* twelve bytes each: ten as the 8087 has them and the tag.
* What is in this bank is lost at every start: it holds
* nothing but what an instruction needs while it is done,
* and what SANE's environment was last set to (fp_env).
*
* SANE and the 8087 (docs/8087.md has the table):
* - SANE's environment is the PC's while it runs. It is set
*   from the control word when an operation needs another
*   (fp_need): rounding and precision for arithmetic, the
*   rounding alone for a conversion or a rounding to an
*   integer, which the 8087's precision control has no say
*   in and SANE's has.
* - SANE's exception flags stay in SANE until the status
*   word is wanted (fp_sw, fp_fold: a call each time).
* - A NaN, an infinity, an empty register and a denormal
*   never reach SANE as they are: the 8087's rules for them
*   are here (fp_arith, fp_cmp), and a denormal is written
*   SANE's way first (fp_dni; fp_dno back).
* - Unnormals are not kept: SANE takes one for its value.
* - An exception that is masked is answered as the 8087 does.
*   One that is not (M9.5) undoes the instruction: the
*   registers and the stack's top it changed are put back
*   from a log (fp_log), a store is not made; then IR is set,
*   and with the interrupt enabled (IEM clear) the carry asks
*   the core for the interrupt. Which exceptions an instruction
*   raised is fp_new: what this image saw in the operands and
*   the results, and SANE's flags read (fp_fold) only when the
*   precision exception is unmasked, where nothing else tells.
* - The instruction's address, its opcode and its operand's
*   address are kept for FSTENV (fp_begin), but for the
*   control instructions, which keep the last.
*
* An instruction that is not done yet does nothing but be
* counted (FPU_BAD, and FPU_LAST is the opcode's three bits
* and its ModR/M byte), so that a test can say none was met.
* A store into the guest's memory goes through fp_put: the
* translator's epoch, the segment's end, the text buffer's
* flags.
*----------------------------------------------------------
 typ $06
 dsk fpu
 put ../include/layout.s
 org FPU_BASE
 mx %00
 put ../include/hw.s
 put ../include/mailbox.s
 put ../include/guest.s
 put ../include/pc.s

 jmp fp_init               ; +0
 jmp fp_esc                ; +3
 jmp fp_sync               ; +6  a PC's state put back (a boot state, the desk accessory's restore)

CW_RESET   = $03FF           ; FNINIT: every exception masked, interrupts off, 64 bits, to nearest, projective
CW_IEM     = $0080           ; the interrupt-enable mask (FENI clears it, FDISI sets it)
CW_RC      = $0C00           ; rounding: 0000 nearest, 0400 down, 0800 up, 0C00 chop
CW_IC      = $1000           ; infinity: affine when set
FE_I       = $0001           ; the status word's exception flags
FE_D       = $0002
FE_Z       = $0004
FE_O       = $0008
FE_U       = $0010
FE_P       = $0020
SANE_FP    = $090A           ; FP816 (X at the dispatcher)

*--- what an instruction needs while it is done
fp_ix      dw 0              ; opcode * 8 + reg field
fp_r       dw 0              ; the reg field
fp_f       dw 0              ; a memory operand's format: 0 single, 1 double, 2 16-bit, 3 32-bit, 4 64-bit integer, 5 extended
fp_len     dw 0
fp_tx      dw 0              ; which operand a conversion makes: 0 fp_a, 12 fp_b
fp_s       dw 0              ; a sign, $8000 or 0
fp_e       dw 0              ; an exponent
fp_den     dw 0              ; the second operand came from a denormal in memory
fp_k       dw 0              ; arithmetic, as SANE's opword: 0 add, 2 subtract, 4 multiply, 6 divide
fp_x0      dw 0              ; the offsets in FPU_REG of ST(0) and of ST(i)
fp_xi      dw 0
fp_ca      dw 0              ; the operands' classes (fp_cl)
fp_cb      dw 0
fp_rc      dw 0
fp_env     dw $FFFF          ; SANE's Environment word as this image last set it ($FFFF: not known)
fp_dirty   dw 0              ; SANE has done something that may have raised a flag since the flags were read
fp_a       ds 10             ; the first operand, and the result
fp_ta      dw 0              ; its tag
fp_b       ds 10             ; the second operand (fp_a + 12: X or Y chooses between them)
fp_tb      dw 0
fp_m       ds 96             ; a memory operand as the guest has it, or is to have it (FSAVE's 94 the most)
fp_ipx     dw 0              ; the IP after the opcode
fp_ctl     dw 0              ; this is a control instruction (no pointers, no undo)
fp_new     dw 0              ; the exceptions this instruction raised
fp_undo    dw 0              ; an exception is unmasked: log what is changed
fp_utop    dw 0              ; the stack's top before the instruction
fp_un      dw 0              ; entries in the log, 14 bytes each: the register's offset, its twelve bytes
fp_ulog    ds 14*6
fp_bz      dw 0              ; arithmetic: the divisor is zero
fp_nz      dw 0              ; arithmetic: a product or quotient of two numbers that are not zero
fp_q       ds 8              ; FPREM, FBLD, FBSTP: a 64-bit integer, a quotient
fp_rm      ds 10             ; FPREM: the partial remainder (and a word of carry)
fp_ea      dw 0
fp_eb      dw 0
fp_cnt     dw 0
fp_t       dw 0

fp_init
 mx %00
 phb
 phk
 plb
 phy
 jsr fp_reset
 lda #0
 sta >FPU_BAD
 sta >FPU_LAST
 phd                       ; SANE's version: the tool set answers from here
 pha
 ldx #$040A                ; SANEVersion
 jsl TOOLS
 rep #$30
 mx %00
 pla
 pld
 sta >FPU_SANE
 lda #1
 sta >FPU_ON
 ply
 plb
 rtl

* fp_reset - FNINIT: the control word, no exception, every register empty
fp_reset
 mx %00
 lda #CW_RESET
 sta >FPU_CW
 lda #0
 sta >FPU_SW
 sta >FPU_TOP
 sta >FPU_IP
 sta >FPU_IP+2
 sta >FPU_OPC
 sta >FPU_DP
 sta >FPU_DP+2
 ldx #84
:tag
 lda #3
 sta >FPU_REG+10,x
 txa
 sec
 sbc #12
 tax
 bpl :tag
 lda #$FFFF                ; and SANE's flags are no longer ours
 sta fp_env
 stz fp_dirty
 rts

*----------------------------------------------------------
* fp_esc - one instruction
*----------------------------------------------------------
fp_esc
 mx %00
 phb
 phk
 plb
 phy
 stx fp_ipx
 asl
 asl
 asl
 sta fp_ix
 lda vMODRM
 and #$0038                ; the reg field: with the opcode, which instruction (or which group)
 lsr
 lsr
 lsr
 sta fp_r
 ora fp_ix
 sta fp_ix
 stz fp_new
 stz fp_undo
 lda vMODRM
 cmp #$00C0
 bcs :reg
 ldx fp_ix
 lda fp_mfl,x
 and #$00FF
 cmp #$00FF
 beq :none
 pha
 and #$0007
 sta fp_f
 lda 1,s
 and #$0040                ; a control instruction?
 sta fp_ctl
 bne :c1
 jsr fp_begin
:c1
 pla
 and #$0080                ; read before the instruction is done?
 beq :go
 ldx fp_f
 lda fp_flen,x
 and #$00FF
 jsr fp_get
:go
 lda fp_ix
 asl
 tax
 jsr (fp_mem,x)
 bra :end
:none
 jsr fp_none
 bra :out
:reg
 stz fp_ctl
 lda fp_ix
 cmp #$1C                  ; DB E0-E7: FENI, FDISI, FNCLEX, FNINIT
 bne :r1
 sta fp_ctl
 bra :r2
:r1
 jsr fp_begin
:r2
 lda fp_ix
 asl
 tax
 jsr (fp_reg,x)
:end
 lda fp_ctl
 bne :irq
 jsr fp_end
:irq
 jsr fp_irq
 ply
 plb
 rtl
:out
 clc
 ply
 plb
 rtl

*----------------------------------------------------------
* fp_begin - an instruction that is not a control one: its
* address (with a segment prefix's), opcode and operand's
* address kept; and when an exception is unmasked, the log
* begun and SANE's flags made this instruction's alone.
*----------------------------------------------------------
fp_begin
 mx %00
 lda fp_ipx
 dec
 ldx vSEGOVR
 beq :np
 dec
:np
 sta fp_t
 lda rCS                   ; the segment's top four bits
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 sta fp_cnt
 lda rCS
 asl
 asl
 asl
 asl
 clc
 adc fp_t
 sta >FPU_IP
 lda fp_cnt
 adc #0
 and #$000F
 sta >FPU_IP+2
 lda fp_ix
 and #$0038
 xba
 lsr
 lsr
 lsr
 ora vMODRM
 sta >FPU_OPC
 lda vMODRM
 cmp #$00C0
 bcs :nod
 lda pEA
 sta >FPU_DP
 lda pEA+2
 and #$000F
 sta >FPU_DP+2
:nod
 lda >FPU_CW
 and #$003F
 cmp #$003F
 beq :out
 lda #1
 sta fp_undo
 stz fp_un
 lda >FPU_TOP
 sta fp_utop
 lda fp_dirty
 beq :out
 jsr fp_fold
 stz fp_new
:out
 rts

* fp_end - an exception the control word does not mask: the
* instruction is undone
fp_end
 mx %00
 lda fp_undo
 beq :out
 lda >FPU_CW
 and #FE_P
 bne :pm
 lda fp_dirty
 beq :pm
 jsr fp_fold
:pm
 jsr fp_unm
 and #$001F
 beq :done
 lda fp_un                 ; the log, last first
:back
 beq :top
 dec
 sta fp_un
 asl
 tax
 lda fp_x14,x
 tay
 ldx fp_ulog,y
 lda fp_ulog+2,y
 sta >FPU_REG,x
 lda fp_ulog+4,y
 sta >FPU_REG+2,x
 lda fp_ulog+6,y
 sta >FPU_REG+4,x
 lda fp_ulog+8,y
 sta >FPU_REG+6,x
 lda fp_ulog+10,y
 sta >FPU_REG+8,x
 lda fp_ulog+12,y
 sta >FPU_REG+10,x
 lda fp_un
 bra :back
:top
 lda fp_utop
 sta >FPU_TOP
:done
 stz fp_undo
:out
 rts
fp_x14     dw 0,14,28,42,56,70

* fp_unm - A = the exceptions this instruction raised that are not masked
fp_unm
 mx %00
 lda >FPU_CW
 eor #$FFFF
 and fp_new
 and #$003F
 rts

* fp_log - the register at X is to be changed: its twelve bytes
* go to the log first, while an exception is unmasked (X kept)
fp_log
 mx %00
 lda fp_undo
 beq :out
 lda fp_un
 cmp #6
 bcs :out
 asl
 tay
 lda fp_x14,y
 tay
 txa
 sta fp_ulog,y
 lda >FPU_REG,x
 sta fp_ulog+2,y
 lda >FPU_REG+2,x
 sta fp_ulog+4,y
 lda >FPU_REG+4,x
 sta fp_ulog+6,y
 lda >FPU_REG+6,x
 sta fp_ulog+8,y
 lda >FPU_REG+8,x
 sta fp_ulog+10,y
 lda >FPU_REG+10,x
 sta fp_ulog+12,y
 inc fp_un
:out
 rts

* fp_irq - after every instruction: an exception flag that the
* control word does not mask sets IR, once, and with the
* interrupt enabled asks for it (carry set)
fp_irq
 mx %00
 lda >FPU_CW
 eor #$FFFF
 and >FPU_SW
 and #$003F
 beq :no
 lda >FPU_SW
 bit #$0080
 bne :no
 ora #$0080
 sta >FPU_SW
 lda >FPU_CW
 and #CW_IEM
 bne :no
 sec
 rts
:no
 clc
 rts

* An instruction that is not done: counted.
fp_none
 mx %00
 lda >FPU_BAD
 inc
 sta >FPU_BAD
 lda fp_ix
 and #$0038
 xba                       ; opcode * 8 in the high byte: the three bits from bit 11
 ora vMODRM
 sta >FPU_LAST
 rts

*----------------------------------------------------------
* The guest's memory. fp_get: A bytes (even) of the operand at
* vEA to fp_m; fp_put: A bytes of fp_m to it. The operand may
* go round its segment's end, and then (or over a bank's end,
* the megabyte's among them) it is moved a byte at a time.
*----------------------------------------------------------
fp_get
 mx %00
 sta fp_len
 dec
 clc
 adc vEA
 bcs :slow
 lda fp_len
 dec
 clc
 adc pEA
 bcs :slow
 ldy #0
:w
 lda [pEA],y
 sta fp_m,y
 iny
 iny
 cpy fp_len
 bcc :w
 rts
:slow
 ldy #0
:b
 jsr fp_ptr
 sep #$20
 mx %10
 lda [pTMP]
 sta fp_m,y
 rep #$20
 mx %00
 iny
 cpy fp_len
 bcc :b
 rts

fp_put
 mx %00
 sta fp_len
 dec
 clc
 adc vEA
 bcs :slow
 lda fp_len
 dec
 clc
 adc pEA
 bcs :slow
 jsr fp_jep
 ldy #0
:w
 lda fp_m,y
 sta [pEA],y
 iny
 iny
 cpy fp_len
 bcc :w
 lda vPCMODE               ; the text buffer's bank: the 256s written are marked
 beq :out
 lda pEA+2
 cmp #^H_TXT
 bne :out
 lda pEA
 jsr fp_vm
 lda fp_len
 dec
 clc
 adc pEA
 jmp fp_vm
:out
 rts
:slow
 inc jEP                   ; (round a segment's or a bank's end: the translator told, whatever the page)
 ldy #0
:b
 jsr fp_ptr
 sep #$20
 mx %10
 lda fp_m,y
 sta [pTMP]
 rep #$20
 mx %00
 lda vPCMODE
 beq :nx
 lda pTMP+2
 cmp #^H_TXT
 bne :nx
 lda pTMP
 jsr fp_vm
:nx
 iny
 cpy fp_len
 bcc :b
 rts

* fp_jep - the translator, when it runs, told of a store onto a
* page that translated code was made from (its pg_map, whose
* address it gives at JIT_BASE+3; bit 0 a page of code): its
* epoch goes on, every piece compares its bytes before it runs
* again, and the core goes back to the dispatcher (jit_hook).
* A store elsewhere tells it nothing. (The operand is within a
* bank here: its first and last bytes' pages are the two.)
fp_jep
 mx %00
 lda >MB_LAYOUT+RG_JIT+RG_JIT
 beq :out
 lda >JIT_CFG
 beq :out
 lda pEA+2                 ; the first byte's page: the address's bits 19-8
 and #$000F
 xba
 sta fp_t
 lda pEA
 xba
 and #$00FF
 ora fp_t
 jsr :pg
 lda fp_len                ; and the last's
 dec
 clc
 adc pEA
 xba
 and #$00FF
 ora fp_t
:pg
 clc
 adc >JIT_BASE+3
 tax
 lda >JIT_BASE,x
 lsr
 bcc :out
 inc jEP
 inc fp_nep
:out
 rts
fp_nep     dw 0              ; (times a store of the 8087's put the translator's epoch on)

* fp_sync - a PC's state put back without fp_init: what this
* image knows of SANE's environment and flags begins again (the
* next operation sets the environment, which clears the flags)
fp_sync
 mx %00
 phb
 phk
 plb
 lda #$FFFF
 sta fp_env
 stz fp_dirty
 plb
 rtl

* fp_ptr - pTMP = where byte Y of the operand is: the offset goes
* round in its segment, the address in the megabyte (Y kept)
fp_ptr
 mx %00
 tya
 clc
 adc vEA
 ldx vEASEG
 clc
 adc 0,x
 sta pTMP
 lda 2,x
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pTMP+2
 rts

* fp_vm - A = the low word of an address written in the text
* buffer's bank: its 256 is marked (Y kept)
fp_vm
 mx %00
 and #$7F00
 xba
 tax
 sep #$20
 mx %10
 lda #1
 sta >VID_DIRTY,x
 rep #$20
 mx %00
 rts

*----------------------------------------------------------
* The registers
*----------------------------------------------------------
* fp_st - X = the offset in FPU_REG of ST(A)
fp_st
 mx %00
 clc
 adc >FPU_TOP
 and #$0007
 asl
 tax
 lda fp_x12,x
 tax
 rts
fp_x12     dw 0,12,24,36,48,60,72,84

* fp_ldr - the register at X, its tag with it, to the operand Y
* (0 fp_a, 12 fp_b)
fp_ldr
 mx %00
 lda >FPU_REG,x
 sta fp_a,y
 lda >FPU_REG+2,x
 sta fp_a+2,y
 lda >FPU_REG+4,x
 sta fp_a+4,y
 lda >FPU_REG+6,x
 sta fp_a+6,y
 lda >FPU_REG+8,x
 sta fp_a+8,y
 lda >FPU_REG+10,x
 sta fp_a+10,y
 rts

* fp_str - the operand Y and its tag to the register at X
fp_str
 mx %00
 lda fp_undo
 beq :go
 phy
 jsr fp_log
 ply
:go
 lda fp_a,y
 sta >FPU_REG,x
 lda fp_a+2,y
 sta >FPU_REG+2,x
 lda fp_a+4,y
 sta >FPU_REG+4,x
 lda fp_a+6,y
 sta >FPU_REG+6,x
 lda fp_a+8,y
 sta >FPU_REG+8,x
 lda fp_a+10,y
 sta >FPU_REG+10,x
 rts

* fp_push - fp_a becomes ST(0). A register in the way is the
* stack's overflow: invalid, and the indefinite is what is pushed.
fp_push
 mx %00
 lda >FPU_TOP
 dec
 and #$0007
 sta >FPU_TOP
 asl
 tax
 lda fp_x12,x
 tax
 lda >FPU_REG+10,x
 cmp #3
 beq :ok
 phx
 lda #FE_I
 jsr fp_exc
 jsr fp_indef
 plx
:ok
 ldy #0
 jmp fp_str

* fp_pop - ST(0) is empty and the stack's top moves on
fp_pop
 mx %00
 lda #0
 jsr fp_st
 jsr fp_log
 lda #3
 sta >FPU_REG+10,x
 lda >FPU_TOP
 inc
 and #$0007
 sta >FPU_TOP
 rts

* fp_exc - the exception flags in A are raised (X and Y kept)
fp_exc
 mx %00
 pha
 ora fp_new
 sta fp_new
 pla
 ora >FPU_SW
 sta >FPU_SW
 rts

* fp_indef - fp_a is the indefinite; fp_ind, the operand X
fp_indef
 mx %00
 ldx #0
fp_ind
 mx %00
 stz fp_a,x
 stz fp_a+2,x
 stz fp_a+4,x
 lda #$C000
 sta fp_a+6,x
 lda #$FFFF
 sta fp_a+8,x
 lda #2
 sta fp_a+10,x
 rts

* fp_b2a - fp_b's ten bytes to fp_a
fp_b2a
 mx %00
 lda fp_b
 sta fp_a
 lda fp_b+2
 sta fp_a+2
 lda fp_b+4
 sta fp_a+4
 lda fp_b+6
 sta fp_a+6
 lda fp_b+8
 sta fp_a+8
 rts

* fp_cl - the class of the operand X (0 fp_a, 12 fp_b), by its tag
* and then its bytes: 0 a number, 1 zero, 2 denormal, 3 infinity,
* 4 NaN, 5 nothing (an empty register). X kept; Z set for a number.
fp_cl
 mx %00
 lda fp_a+10,x
 cmp #2
 bcc :out
 beq :sp
 lda #5
 rts
:out
 ora #0                    ; (the flags A's, not the compare's)
 rts
:sp
 lda fp_a+8,x
 and #$7FFF
 bne :top
 lda #2
 rts
:top
 lda fp_a,x
 ora fp_a+2,x
 ora fp_a+4,x
 bne :nan
 lda fp_a+6,x
 cmp #$8000
 bne :nan
 lda #3
 rts
:nan
 lda #4
 rts

* fp_tagx - the tag of the ten bytes of the operand X, into its
* tag (and A): valid, zero or special
fp_tagx
 mx %00
 lda fp_a+8,x
 and #$7FFF
 beq :low
 cmp #$7FFF
 beq :sp
 lda #0
 bra :set
:low
 lda fp_a,x
 ora fp_a+2,x
 ora fp_a+4,x
 ora fp_a+6,x
 bne :sp
 lda #1
 bra :set
:sp
 lda #2
:set
 sta fp_a+10,x
 rts

*----------------------------------------------------------
* SANE's environment and its flags
*----------------------------------------------------------
* fp_need - SANE's Environment word as the control word has it,
* for arithmetic (A = 0: rounding and precision) or for a
* conversion (A = 1: rounding alone). Set only when it is not
* that already; SANE's flags are read first when they may hold
* something, for setting the word clears them.
fp_need
 mx %00
 tay
 lda >FPU_CW
 and #$0F00
 xba
 asl
 tax
 lda fp_etab,x
 cpy #0
 beq :have
 and #$C000
:have
 cmp fp_env
 beq :out
 pha
 lda fp_dirty
 beq :set
 jsr fp_fold
:set
 pla
 sta fp_env
 pha                       ; the word, by value
 pea $0001                 ; FSETENV
 ldx #SANE_FP
 jsl TOOLS
:out
 rts
* by the control word's rounding (nearest, down, up, chop) and precision (24 bits, -, 53, 64)
fp_etab    dw $0080,$0000,$0040,$0000
           dw $8080,$8000,$8040,$8000
           dw $4080,$4000,$4040,$4000
           dw $C080,$C000,$C040,$C000

* fp_fold - SANE's exception flags into the status word, and
* cleared in SANE, so that what it holds is always new
fp_fold
 mx %00
 pea $0003                 ; FGETENV: the word in X
 ldx #SANE_FP
 jsl TOOLS
 stz fp_dirty
 txa
 and #$1F00
 beq :out
 txa
 and #$E0FF
 pha                       ; the word without them, by value
 txa
 xba
 and #$001F
 tax
 lda fp_ftab,x
 and #$00FF
 jsr fp_exc
 pea $0001                 ; FSETENV
 ldx #SANE_FP
 jsl TOOLS
:out
 rts
* SANE's invalid 01, underflow 02, overflow 04, divide by zero 08, inexact 10: the 8087's I, U, O, Z, P
fp_ftab    dfb $00,$01,$10,$11,$08,$09,$18,$19,$04,$05,$14,$15,$0C,$0D,$1C,$1D
           dfb $20,$21,$30,$31,$28,$29,$38,$39,$24,$25,$34,$35,$2C,$2D,$3C,$3D

* fp_sw - A = the status word, whole
fp_sw
 mx %00
 lda fp_dirty
 beq :n
 jsr fp_fold
:n
 lda >FPU_TOP
 xba
 asl
 asl
 asl
 ora >FPU_SW
 rts

*----------------------------------------------------------
* Denormals. An exponent field of 0 is 2^-16382 times the
* significand on an 8087 and 2^-16383 times it in SANE.
*----------------------------------------------------------
* fp_dni - the operand X, a denormal, written SANE's way
fp_dni
 mx %00
 lda fp_a+6,x
 bmi :one                  ; (with its integer bit: SANE's exponent 1 is the same number)
 asl fp_a,x
 rol fp_a+2,x
 rol fp_a+4,x
 rol fp_a+6,x
 rts
:one
 lda fp_a+8,x
 ora #$0001
 sta fp_a+8,x
 rts

* fp_dno - fp_a, a number of SANE's below 2^-16382, written the
* 8087's way: halved, and when a bit is lost by that rounded as
* the control word says. The 8087 calls it an underflow, exact
* or not. (SANE has rounded already at its own last place: the
* two roundings are not always the one the 8087 does.)
fp_dno
 mx %00
 lsr fp_a+6
 ror fp_a+4
 ror fp_a+2
 ror fp_a
 bcc :exact
 lda #FE_P
 jsr fp_exc
 lda >FPU_CW
 and #CW_RC
 beq :near
 cmp #CW_RC
 beq :exact                ; chop
 cmp #$0400
 beq :down
 lda fp_a+8                ; up: a positive number
 bmi :exact
 bra :inc
:down
 lda fp_a+8
 bpl :exact
 bra :inc
:near
 lda fp_a                  ; a half: to the even
 lsr
 bcc :exact
:inc
 inc fp_a
 bne :exact
 inc fp_a+2
 bne :exact
 inc fp_a+4
 bne :exact
 inc fp_a+6
:exact
 lda #FE_U
 jsr fp_exc
 lda fp_a+6
 bpl :den
 lda fp_a+8                ; rounded up to the least normal number
 ora #$0001
 sta fp_a+8
 stz fp_ta
 rts
:den
 ora fp_a+4
 ora fp_a+2
 ora fp_a
 bne :sp
 lda #1
 sta fp_ta
 rts
:sp
 lda #2
 sta fp_ta
 rts

* fp_post - what SANE's arithmetic left in fp_a, as the 8087
* writes it, and its tag
fp_post
 mx %00
 lda fp_a+8
 and #$7FFF
 bne *+5
 jmp :low
 cmp #$7FFE
 bcs :high
:norm
 stz fp_ta
 rts
:high
 beq :max
 lda fp_a                  ; an infinity (SANE's has no integer bit)?
 ora fp_a+2
 ora fp_a+4
 bne :nan
 lda fp_a+6
 and #$7FFF
 bne :nan
 lda #$8000
 sta fp_a+6
 lda #FE_O+FE_P            ; from numbers: an overflow, or a division by zero
 ldx fp_bz
 beq :ovf
 lda #FE_Z
:ovf
 jsr fp_exc
:sp
 lda #2
 sta fp_ta
 rts
:nan                       ; SANE's NaN for an invalid operation: the 8087's is the indefinite
 lda #FE_I
 jsr fp_exc
 jmp fp_indef
:max                       ; the largest number: when rounding chops, an overflow is infinity on an 8087
 lda >FPU_CW
 and #CW_RC
 cmp #CW_RC
 bne :norm
 lda fp_a
 and fp_a+2
 and fp_a+4
 and fp_a+6
 cmp #$FFFF
 bne :norm
 jsr fp_fold               ; (was there an overflow? This one's or an earlier one's)
 lda >FPU_SW
 and #FE_O
 beq :norm
 stz fp_a
 stz fp_a+2
 stz fp_a+4
 lda #$8000
 sta fp_a+6
 lda fp_a+8
 ora #$7FFF
 sta fp_a+8
 bra :sp
:low
 lda fp_a
 ora fp_a+2
 ora fp_a+4
 ora fp_a+6
 bne :den
 lda fp_nz                 ; a product or quotient of numbers that is 0: an underflow
 beq :z
 lda #FE_U+FE_P
 jsr fp_exc
:z
 lda #1
 sta fp_ta
 rts
:den
 jmp fp_dno

*----------------------------------------------------------
* fp_arith - fp_a = fp_a (fp_k) fp_b, the tags with them; the
* result's tag in fp_ta. fp_den: fp_b was a denormal in memory.
*----------------------------------------------------------
fp_arith
 mx %00
 lda fp_ta
 ora fp_tb
 cmp #2
 bcs :special
 lda fp_den
 bne :special
:sane
 lda fp_k                  ; a multiply or a divide of two numbers: here (fp_md), unless out of range
 cmp #4
 bcc :sn0
 lda fp_ta
 ora fp_tb
 bne :sn0
 jsr fp_md
 bcs :sn0
 rts
:sn0
 stz fp_bz
 stz fp_nz
 lda fp_k
 cmp #4
 bcc :sn
 lda fp_tb
 cmp #1
 bne :sb
 sta fp_bz
:sb
 ora fp_ta
 bne :sn
 inc fp_nz                 ; (both tags 0: two numbers)
:sn
 lda #0
 jsr fp_need
 pea ^fp_b
 pea fp_b
 pea ^fp_a
 pea fp_a
 lda fp_k
 pha
 ldx #SANE_FP
 jsl TOOLS
 lda #1
 sta fp_dirty
 jmp fp_post
:special
 ldx #0
 jsr fp_cl
 sta fp_ca
 ldx #12
 jsr fp_cl
 sta fp_cb
 cmp #5
 bne :s1
 jmp :inval
:s1
 lda fp_ca
 cmp #5
 bne :s2
 jmp :inval
:s2
 cmp #4
 bne :s3
 jmp :anan
:s3
 lda fp_cb
 cmp #4
 bne :s4
 jmp :bnan
:s4
 lda fp_den                ; a denormal: its own exception, and no divisor
 bne :dend
 lda fp_cb
 cmp #2
 beq :dend
 lda fp_ca
 cmp #2
 bne :noden
 lda #FE_D
 jsr fp_exc
 bra :noden
:dend
 lda #FE_D
 jsr fp_exc
 lda fp_k
 cmp #6
 beq :inval
:noden
 lda fp_ca
 cmp #3
 beq :inf
 lda fp_cb
 cmp #3
 beq :inf
 lda fp_ca                 ; SANE's way of writing a denormal
 cmp #2
 bne :aok
 ldx #0
 jsr fp_dni
:aok
 lda fp_cb
 cmp #2
 bne :gos
 ldx #12
 jsr fp_dni
:gos
 jmp :sane
:inval
 lda #FE_I
 jsr fp_exc
 jmp fp_indef
:anan                      ; a NaN is the result; of two, the one with the larger significand
 lda #FE_I
 jsr fp_exc
 lda fp_cb
 cmp #4
 bne :keep
 lda fp_b+6
 cmp fp_a+6
 bne :which
 lda fp_b+4
 cmp fp_a+4
 bne :which
 lda fp_b+2
 cmp fp_a+2
 bne :which
 lda fp_b
 cmp fp_a
:which
 bcc :keep
 beq :keep
 bra :takeb
:bnan
 lda #FE_I
 jsr fp_exc
:takeb
 jsr fp_b2a
:keep
 lda #2
 sta fp_ta
 rts
*--- an infinity among them
:inf
 lda fp_a+8
 eor fp_b+8
 and #$8000
 sta fp_s
 lda fp_k
 cmp #4
 beq :imul
 cmp #6
 beq :idiv
 cmp #2
 bne :iadd
 lda fp_b+8                ; a - b is a + (-b)
 eor #$8000
 sta fp_b+8
:iadd
 lda fp_ca
 cmp #3
 bne :takeb                ; b alone
 lda fp_cb
 cmp #3
 bne :keep                 ; a alone
 lda >FPU_CW               ; both: projective, never; affine, of one sign
 and #CW_IC
 beq :inval2
 lda fp_a+8
 eor fp_b+8
 bmi :inval2
 bra :keep
:imul
 lda fp_ca
 cmp #1
 beq :inval2
 lda fp_cb
 cmp #1
 beq :inval2
:mkinf
 stz fp_a
 stz fp_a+2
 stz fp_a+4
 lda #$8000
 sta fp_a+6
 lda fp_s
 ora #$7FFF
 sta fp_a+8
 bra :keep
:idiv
 lda fp_cb
 cmp #3
 bne :mkinf                ; infinity / a number
 lda fp_ca
 cmp #3
 beq :inval2
 stz fp_a                  ; a number / infinity
 stz fp_a+2
 stz fp_a+4
 stz fp_a+6
 lda fp_s
 sta fp_a+8
 lda #1
 sta fp_ta
 rts
:inval2
 jmp :inval

*----------------------------------------------------------
* Multiply and divide of two normal numbers, here: SANE's are
* 16,000 cycles each (docs/8087.md). fp_md: fp_a = fp_a * fp_b
* or fp_a / fp_b (fp_k 4 or 6), both tagged valid; carry set,
* nothing changed, when either is not normal (an unnormal) or
* the result is out of the normal range: then SANE does it, as
* before. Rounded to the control word's precision and direction
* from a guard bit and a sticky; P raised here when inexact.
*----------------------------------------------------------
fp_x       ds 8              ; the multiplicand / the divisor
fp_y       ds 8              ; the multiplier
fp_p       ds 16             ; the product; the dividend's remainder (+8: a word above it)
fp_qd      ds 8              ; the quotient
fp_rsig    ds 8              ; the result's significand, before rounding
fp_g       dw 0              ; the bit below it
fp_sk      dw 0              ; anything below that (sticky)
fp_re      dw 0              ; its biased exponent
fp_rs      dw 0              ; its sign
fp_mw      dw 0
fp_bw      dw 0              ; the divisor's first word that is not 0, by offset
fp_qm      dw 0              ; the quotient's bit being found, and its word
fp_qx      dw 0
fp_ri      dw 0              ; rounding: the increment, its word, the round bit, its lsb
fp_rk      dw 0
fp_rb      dw 0
fp_lsb     dw 0

fp_md
 mx %00
 lda fp_a+6
 bmi *+5
 jmp :no
 lda fp_b+6
 bmi *+5
 jmp :no
 lda fp_a+8
 eor fp_b+8
 and #$8000
 sta fp_rs
 lda fp_k
 cmp #6
 bne *+5
 jmp :div
*--- multiply: the operand with more zero words is the multiplier
 jsr :zw
 bcs :swap
 ldx #6
:c1
 lda fp_a,x
 sta fp_x,x
 lda fp_b,x
 sta fp_y,x
 dex
 dex
 bpl :c1
 bra :mul
:swap
 ldx #6
:c2
 lda fp_b,x
 sta fp_x,x
 lda fp_a,x
 sta fp_y,x
 dex
 dex
 bpl :c2
:mul
 jsr fp_mulsig
 lda fp_a+8                ; the exponent: ea + eb - 16383, one more when the product's top bit is set
 and #$7FFF
 sta fp_re
 lda fp_b+8
 and #$7FFF
 clc
 adc fp_re
 sec
 sbc #16382
 bcc :no                   ; (far below the range)
 sta fp_re
 lda fp_p+14
 bmi :top
 dec fp_re
 asl fp_p
 rol fp_p+2
 rol fp_p+4
 rol fp_p+6
 rol fp_p+8
 rol fp_p+10
 rol fp_p+12
 rol fp_p+14
:top
 lda fp_p+8
 sta fp_rsig
 lda fp_p+10
 sta fp_rsig+2
 lda fp_p+12
 sta fp_rsig+4
 lda fp_p+14
 sta fp_rsig+6
 lda fp_p+6
 asl
 lda #0
 rol
 sta fp_g
 lda fp_p+6
 and #$7FFF
 ora fp_p+4
 ora fp_p+2
 ora fp_p
 sta fp_sk
 bra fp_mdr
:no
 sec
 rts
*--- divide
:div
 jsr fp_divsig
 bcs :no
 bra fp_mdr
* :zw - carry set when fp_a has more zero words than fp_b
:zw
 ldx #6
 ldy #0
:z1
 lda fp_a,x
 bne :z2
 iny
:z2
 lda fp_b,x
 bne :z3
 dey
:z3
 dex
 dex
 bpl :z1
 tya
 dec
 bmi :zc
 sec
 rts
:zc
 clc
 rts

* fp_mdr - round, check the range, and the result to fp_a
fp_mdr
 mx %00
 jsr fp_rnd
 lda fp_re
 beq :no
 cmp #$7FFF
 bcs :no
 lda fp_rb                 ; inexact: P
 ora fp_sk
 beq :ex
 lda #FE_P
 jsr fp_exc
:ex
 lda fp_rsig
 sta fp_a
 lda fp_rsig+2
 sta fp_a+2
 lda fp_rsig+4
 sta fp_a+4
 lda fp_rsig+6
 sta fp_a+6
 lda fp_re
 ora fp_rs
 sta fp_a+8
 stz fp_ta
 clc
 rts
:no
 sec
 rts

* fp_mulsig - fp_p = fp_x * fp_y: the multiplier's bits from the
* least, a zero word of it a shift of sixteen
fp_mulsig
 mx %00
 ldx #14
:z
 stz fp_p,x
 dex
 dex
 bpl :z
 ldx #0
:wl
 lda fp_y,x
 bne :bits
 lda fp_p+2
 sta fp_p
 lda fp_p+4
 sta fp_p+2
 lda fp_p+6
 sta fp_p+4
 lda fp_p+8
 sta fp_p+6
 lda fp_p+10
 sta fp_p+8
 lda fp_p+12
 sta fp_p+10
 lda fp_p+14
 sta fp_p+12
 stz fp_p+14
 bra :next
:bits
 sta fp_mw
 ldy #16
:bl
 lsr fp_mw
 bcc :sh
 clc
 lda fp_p+8
 adc fp_x
 sta fp_p+8
 lda fp_p+10
 adc fp_x+2
 sta fp_p+10
 lda fp_p+12
 adc fp_x+4
 sta fp_p+12
 lda fp_p+14
 adc fp_x+6
 sta fp_p+14
:sh
 ror fp_p+14
 ror fp_p+12
 ror fp_p+10
 ror fp_p+8
 ror fp_p+6
 ror fp_p+4
 ror fp_p+2
 ror fp_p
 dey
 bne :bl
:next
 inx
 inx
 cpx #8
 bcs *+5
 jmp :wl
 rts

* fp_divsig - fp_rsig = fp_a / fp_b's significands, 64 bits and
* a guard bit and the sticky, fp_re the exponent; carry set when
* it is below the range
fp_divsig
 mx %00
 lda fp_a+8
 and #$7FFF
 clc
 adc #16383
 sta fp_re
 lda fp_b+8
 and #$7FFF
 sta fp_mw
 lda fp_re
 sec
 sbc fp_mw
 bcs *+5
 jmp :low
 sta fp_re
 ldx #6
:c
 lda fp_a,x
 sta fp_p,x
 lda fp_b,x
 sta fp_x,x
 stz fp_qd,x
 dex
 dex
 bpl :c
 stz fp_p+8
 ldx #0                    ; the divisor's first word that is not 0
:fw
 lda fp_x,x
 bne :fwd
 inx
 inx
 bra :fw
:fwd
 stx fp_bw                 ; (its offset is the index into :sub's entries)
 jsr :ge                   ; the dividend the smaller: shifted, the exponent one less
 bcs :go
 dec fp_re
 asl fp_p
 rol fp_p+2
 rol fp_p+4
 rol fp_p+6
 rol fp_p+8
:go
 lda #$8000
 sta fp_qm
 lda #6
 sta fp_qx
:lp
 jsr :ge
 bcc :zero
 jsr :sub
 ldx fp_qx
 lda fp_qd,x
 ora fp_qm
 sta fp_qd,x
:zero
 asl fp_p
 rol fp_p+2
 rol fp_p+4
 rol fp_p+6
 rol fp_p+8
 lsr fp_qm
 bne :lp
 lda #$8000
 sta fp_qm
 dec fp_qx
 dec fp_qx
 bpl :lp
 stz fp_g                  ; the guard bit, and what is left
 jsr :ge
 bcc :gz
 jsr :sub
 inc fp_g
:gz
 lda fp_p
 ora fp_p+2
 ora fp_p+4
 ora fp_p+6
 ora fp_p+8
 sta fp_sk
 ldx #6
:cq
 lda fp_qd,x
 sta fp_rsig,x
 dex
 dex
 bpl :cq
 lda fp_re
 beq :low
 clc
 rts
:low
 sec
 rts
* :ge - carry set when the remainder (65 bits) is the divisor or more
:ge
 lda fp_p+8
 bne :yes
 lda fp_p+6
 cmp fp_x+6
 bne :d
 lda fp_p+4
 cmp fp_x+4
 bne :d
 lda fp_p+2
 cmp fp_x+2
 bne :d
 lda fp_p
 cmp fp_x
:d
 rts
:yes
 sec
 rts
* :sub - the remainder less the divisor, from its first word that is not 0
:sub
 ldx fp_bw
 sec
 jmp (:ent,x)
:ent       da :s0,:s1,:s2,:s3
:s0
 lda fp_p
 sbc fp_x
 sta fp_p
:s1
 lda fp_p+2
 sbc fp_x+2
 sta fp_p+2
:s2
 lda fp_p+4
 sbc fp_x+4
 sta fp_p+4
:s3
 lda fp_p+6
 sbc fp_x+6
 sta fp_p+6
 lda fp_p+8
 sbc #0
 sta fp_p+8
 rts

* fp_rnd - fp_rsig, fp_g, fp_sk rounded to the control word's
* precision and in its direction (sign fp_rs); fp_rb and fp_sk
* say afterwards whether it was inexact
fp_rnd
 mx %00
 lda >FPU_CW
 and #$0300
 beq :p24
 cmp #$0200
 beq :p53
 lda fp_g                  ; 64 bits (and the reserved 01)
 sta fp_rb
 lda fp_rsig
 and #$0001
 sta fp_lsb
 stz fp_rk
 lda #1
 sta fp_ri
 bra :dir
:p53
 lda fp_rsig
 and #$0400
 sta fp_rb
 lda fp_rsig
 and #$03FF
 ora fp_g
 ora fp_sk
 sta fp_sk
 lda fp_rsig
 and #$0800
 sta fp_lsb
 lda fp_rsig
 and #$F800
 sta fp_rsig
 stz fp_rk
 lda #$0800
 sta fp_ri
 bra :dir
:p24
 lda fp_rsig+4
 and #$0080
 sta fp_rb
 lda fp_rsig+4
 and #$007F
 ora fp_rsig+2
 ora fp_rsig
 ora fp_g
 ora fp_sk
 sta fp_sk
 lda fp_rsig+4
 and #$0100
 sta fp_lsb
 lda fp_rsig+4
 and #$FF00
 sta fp_rsig+4
 stz fp_rsig+2
 stz fp_rsig
 lda #4
 sta fp_rk
 lda #$0100
 sta fp_ri
:dir
 lda fp_rb
 ora fp_sk
 beq :out                  ; exact
 lda >FPU_CW
 and #CW_RC
 beq :near
 cmp #CW_RC
 beq :out                  ; chop
 cmp #$0400
 beq :down
 lda fp_rs                 ; up: the positive go up
 bmi :out
 bra :inc
:down
 lda fp_rs
 bpl :out
 bra :inc
:near
 lda fp_rb
 beq :out
 lda fp_sk
 ora fp_lsb
 beq :out                  ; a half, to the even
:inc
 ldx fp_rk
 lda fp_rsig,x
 clc
 adc fp_ri
 sta fp_rsig,x
 bcc :out
:prop
 inx
 inx
 cpx #8
 beq :over
 lda fp_rsig,x
 inc
 sta fp_rsig,x
 beq :prop
 bra :out
:over
 lda #$8000
 sta fp_rsig+6
 inc fp_re
:out
 rts

*----------------------------------------------------------
* fp_cmp - fp_a, which is ST(0), against fp_b: the condition
* code. C0 when ST is the less, C3 when they are equal, C3, C2
* and C0 when they have no order.
*----------------------------------------------------------
fp_cmp
 mx %00
 lda fp_ta
 ora fp_tb
 cmp #2
 bcs :special
:sane
 pea ^fp_b
 pea fp_b
 pea ^fp_a
 pea fp_a
 pea $0008                 ; FCMPX: X = $40 the source (fp_b) is the greater, $80 the less, $02 equal
 ldx #SANE_FP
 jsl TOOLS
 txa
 and #$00FF
 cmp #$0040
 beq :lt
 cmp #$0080
 beq :gt
 cmp #$0002
 beq :eq
:un
 lda #$4500
 bra :cc
:lt
 lda #$0100
 bra :cc
:gt
 lda #0
 bra :cc
:eq
 lda #$4000
:cc
 sta fp_rc
 lda >FPU_SW
 and #$BAFF
 ora fp_rc
 sta >FPU_SW
 rts
:special
 ldx #0
 jsr fp_cl
 sta fp_ca
 ldx #12
 jsr fp_cl
 sta fp_cb
 cmp #4
 bcs :inval                ; a NaN or nothing
 lda fp_ca
 cmp #4
 bcs :inval
 cmp #2
 beq :dn
 lda fp_cb
 cmp #2
 bne :nodn
:dn
 lda #FE_D
 jsr fp_exc
:nodn
 lda >FPU_CW               ; projective: an infinity equals an infinity and has no order with a number
 and #CW_IC
 bne :affine
 lda fp_ca
 cmp #3
 bne :pb
 lda fp_cb
 cmp #3
 beq :eq
 bra :inval
:pb
 lda fp_cb
 cmp #3
 beq :inval
:affine
 lda fp_ca
 cmp #2
 bne :aok
 ldx #0
 jsr fp_dni
:aok
 lda fp_cb
 cmp #2
 beq *+5
 jmp :sane
 ldx #12
 jsr fp_dni
 jmp :sane
:inval
 lda #FE_I
 jsr fp_exc
 jmp :un

*----------------------------------------------------------
* Into extended: fp_m, in the format fp_f, to the operand fp_tx
* with its tag. All exact, none SANE's. A denormal becomes the
* unnormal of the same value, as on an 8087 (and its exception
* is raised, fp_den set).
*----------------------------------------------------------
fp_cvin
 mx %00
 lda fp_f
 asl
 tax
 jmp (:t,x)
:t         da fp_ld4,fp_ld8,fp_li2,fp_li4,fp_li8,fp_ld10

fp_ld4
 mx %00
 ldx fp_tx
 stz fp_a,x
 stz fp_a+2,x
 lda fp_m
 and #$00FF
 xba
 sta fp_a+4,x
 lda fp_m+2
 and #$8000
 sta fp_s
 lda fp_m+2
 asl
 xba
 and #$00FF
 beq :e0
 cmp #$00FF
 beq :top
 clc
 adc #$3F80
 ora fp_s
 sta fp_a+8,x
 lda fp_m+1
 ora #$8000
 sta fp_a+6,x
 lda #0
:tag
 sta fp_a+10,x
 rts
:e0
 lda fp_m+1
 and #$7FFF
 sta fp_a+6,x
 ora fp_a+4,x
 beq :zero
 lda #$3F81
 ora fp_s
 sta fp_a+8,x
 jsr fp_isden
 lda #0
 bra :tag
:zero
 lda fp_s
 sta fp_a+8,x
 lda #1
 bra :tag
:top
 lda fp_m+1
 ora #$8000
 sta fp_a+6,x
 lda fp_s
 ora #$7FFF
 sta fp_a+8,x
 lda #2
 bra :tag

fp_isden
 mx %00
 lda #1
 sta fp_den
 lda #FE_D
 jmp fp_exc

fp_ld8
 mx %00
 ldx fp_tx
 lda fp_m+6
 and #$8000
 sta fp_s
 lda fp_m+6
 lsr
 lsr
 lsr
 lsr
 and #$07FF
 sta fp_e
 lda fp_m+6
 and #$000F
 sta fp_m+6
 asl fp_m                  ; the fraction eleven places up: three, and a byte
 rol fp_m+2
 rol fp_m+4
 rol fp_m+6
 asl fp_m
 rol fp_m+2
 rol fp_m+4
 rol fp_m+6
 asl fp_m
 rol fp_m+2
 rol fp_m+4
 rol fp_m+6
 stz fp_a,x
 lda fp_m
 sta fp_a+1,x
 lda fp_m+2
 sta fp_a+3,x
 lda fp_m+4
 sta fp_a+5,x
 lda fp_m+6                ; (seven bits, and a 0 where the exponent comes)
 sta fp_a+7,x
 lda fp_e
 beq :e0
 cmp #$07FF
 beq :top
 clc
 adc #$3C00
 ora fp_s
 sta fp_a+8,x
 lda fp_a+6,x
 ora #$8000
 sta fp_a+6,x
 lda #0
:tag
 sta fp_a+10,x
 rts
:e0
 lda fp_a,x
 ora fp_a+2,x
 ora fp_a+4,x
 ora fp_a+6,x
 beq :zero
 lda #$3C01
 ora fp_s
 sta fp_a+8,x
 jsr fp_isden
 lda #0
 bra :tag
:zero
 lda fp_s
 sta fp_a+8,x
 lda #1
 bra :tag
:top
 lda fp_a+6,x
 ora #$8000
 sta fp_a+6,x
 lda fp_s
 ora #$7FFF
 sta fp_a+8,x
 lda #2
 bra :tag

fp_ld10
 mx %00
 ldx fp_tx
 lda fp_m
 sta fp_a,x
 lda fp_m+2
 sta fp_a+2,x
 lda fp_m+4
 sta fp_a+4,x
 lda fp_m+6
 sta fp_a+6,x
 lda fp_m+8
 sta fp_a+8,x
 jmp fp_tagx

fp_li2
 mx %00
 ldx fp_tx
 stz fp_a,x
 stz fp_a+2,x
 stz fp_a+4,x
 stz fp_s
 lda fp_m
 beq fp_lizero
 bpl :pos
 eor #$FFFF
 inc
 ldy #$8000
 sty fp_s
:pos
 sta fp_a+6,x
 lda #$400E
 jmp fp_nrm
fp_lizero                  ; +0
 mx %00
 stz fp_a,x
 stz fp_a+2,x
 stz fp_a+4,x
 stz fp_a+6,x
 stz fp_a+8,x
 lda #1
 sta fp_a+10,x
 rts

fp_li4
 mx %00
 ldx fp_tx
 stz fp_a,x
 stz fp_a+2,x
 stz fp_s
 lda fp_m
 ora fp_m+2
 beq fp_lizero
 lda fp_m+2
 bpl :pos
 lda #$8000
 sta fp_s
 lda #0
 sec
 sbc fp_m
 sta fp_m
 lda #0
 sbc fp_m+2
 sta fp_m+2
:pos
 lda fp_m
 sta fp_a+4,x
 lda fp_m+2
 sta fp_a+6,x
 lda #$401E
 jmp fp_nrm

fp_li8
 mx %00
 ldx fp_tx
 stz fp_s
 lda fp_m
 ora fp_m+2
 ora fp_m+4
 ora fp_m+6
 beq fp_lizero
 lda fp_m+6
 bpl :pos
 lda #$8000
 sta fp_s
 lda #0
 sec
 sbc fp_m
 sta fp_m
 lda #0
 sbc fp_m+2
 sta fp_m+2
 lda #0
 sbc fp_m+4
 sta fp_m+4
 lda #0
 sbc fp_m+6
 sta fp_m+6
:pos
 lda fp_m
 sta fp_a,x
 lda fp_m+2
 sta fp_a+2,x
 lda fp_m+4
 sta fp_a+4,x
 lda fp_m+6
 sta fp_a+6,x
 lda #$403E
* fp_nrm - the operand X's significand, not 0 and with A the
* exponent it has as it stands, made normal; the sign is fp_s
fp_nrm
 mx %00
 sta fp_e
:w
 lda fp_a+6,x
 bne :b
 lda fp_a+4,x              ; a word at a time
 sta fp_a+6,x
 lda fp_a+2,x
 sta fp_a+4,x
 lda fp_a,x
 sta fp_a+2,x
 stz fp_a,x
 lda fp_e
 sec
 sbc #16
 sta fp_e
 bra :w
:b
 bmi :done
 lda fp_a,x
 ora fp_a+2,x
 ora fp_a+4,x
 bne :s
 ldy fp_e                  ; nothing below the top word: in A
 lda fp_a+6,x
:q
 dey
 asl
 bpl :q
 sta fp_a+6,x
 sty fp_e
 bra :done
:s
 dec fp_e
 asl fp_a,x
 rol fp_a+2,x
 rol fp_a+4,x
 rol fp_a+6,x
 bpl :s
:done
 lda fp_e
 ora fp_s
 sta fp_a+8,x
 lda #0
 sta fp_a+10,x
 rts

*----------------------------------------------------------
* Out of extended: fp_a, with its tag, to fp_m in the format
* fp_f. A number goes by SANE, with the control word's rounding;
* the rest is the 8087's own.
*----------------------------------------------------------
fp_cvout
 mx %00
 lda fp_f
 asl
 tax
 jmp (:t,x)
:t         da fp_st4,fp_st8,fp_si2,fp_si4,fp_si8,fp_st10

* fp_x2z - SANE's conversion A (FX2S, FX2D...) of fp_a to fp_m
fp_x2z
 mx %00
 pha
 lda #1
 jsr fp_need
 pla
 pea ^fp_a
 pea fp_a
 pea ^fp_m
 pea fp_m
 pha
 ldx #SANE_FP
 jsl TOOLS
 lda #1
 sta fp_dirty
 rts

fp_st4
 mx %00
 ldx #0
 jsr fp_cl
 asl
 tax
 jmp (:t,x)
:t         da :norm,:zero,:den,:inf,:nan,:empty
:empty
 lda #FE_I
 jsr fp_exc
 stz fp_m
 lda #$FFC0
 sta fp_m+2
 rts
:zero
 stz fp_m
 lda fp_a+8
 and #$8000
 sta fp_m+2
 rts
:inf
 stz fp_m
 lda fp_a+8
 and #$8000
 ora #$7F80
 sta fp_m+2
 rts
:nan                       ; its significand's top
 lda fp_a+5
 sta fp_m
 lda fp_a+7
 and #$007F
 sta fp_m+2
 ora fp_m
 bne :nz
 inc fp_m                  ; (a NaN it stays)
:nz
 lda fp_a+8
 and #$8000
 ora #$7F80
 ora fp_m+2
 sta fp_m+2
 rts
:den
 ldx #0
 jsr fp_dni
:norm
 lda >FPU_CW               ; when rounding chops, a number too large is infinity on an 8087
 and #CW_RC
 cmp #CW_RC
 bne :go
 lda fp_a+8
 and #$7FFF
 cmp #$407F
 bcc :go
 lda #FE_O+FE_P
 jsr fp_exc
 bra :inf
:go
 lda #$0210                ; FX2S
 jsr fp_x2z
 lda fp_m+2                ; a denormal stored is an underflow on an 8087, exact or not
 and #$7F80
 beq :lo
 cmp #$7F80
 bne :done
 lda #FE_O+FE_P            ; a number become infinity
 jmp fp_exc
:lo
 lda fp_m+2
 and #$007F
 ora fp_m
 bne :u
 lda #FE_U+FE_P            ; a number become 0
 jmp fp_exc
:u
 lda #FE_U
 jsr fp_exc
:done
 rts

fp_st8
 mx %00
 ldx #0
 jsr fp_cl
 asl
 tax
 jmp (:t,x)
:t         da :norm,:zero,:den,:inf,:nan,:empty
:empty
 lda #FE_I
 jsr fp_exc
 stz fp_m
 stz fp_m+2
 stz fp_m+4
 lda #$FFF8
 sta fp_m+6
 rts
:zero
 stz fp_m
 stz fp_m+2
 stz fp_m+4
 lda fp_a+8
 and #$8000
 sta fp_m+6
 rts
:inf
 stz fp_m
 stz fp_m+2
 stz fp_m+4
 lda fp_a+8
 and #$8000
 ora #$7FF0
 sta fp_m+6
 rts
:nan                       ; its significand eleven places down: three, and a byte
 lsr fp_a+6
 ror fp_a+4
 ror fp_a+2
 ror fp_a
 lsr fp_a+6
 ror fp_a+4
 ror fp_a+2
 ror fp_a
 lsr fp_a+6
 ror fp_a+4
 ror fp_a+2
 ror fp_a
 lda fp_a+1
 sta fp_m
 lda fp_a+3
 sta fp_m+2
 lda fp_a+5
 sta fp_m+4
 lda fp_a+7
 and #$000F
 sta fp_m+6
 ora fp_m+4
 ora fp_m+2
 ora fp_m
 bne :nz
 inc fp_m
:nz
 lda fp_a+8
 and #$8000
 ora #$7FF0
 ora fp_m+6
 sta fp_m+6
 rts
:den
 ldx #0
 jsr fp_dni
:norm
 lda >FPU_CW
 and #CW_RC
 cmp #CW_RC
 bne :go
 lda fp_a+8
 and #$7FFF
 cmp #$43FF
 bcc :go
 lda #FE_O+FE_P
 jsr fp_exc
 jmp :inf
:go
 lda #$0110                ; FX2D
 jsr fp_x2z
 lda fp_m+6
 and #$7FF0
 beq :lo
 cmp #$7FF0
 bne :done
 lda #FE_O+FE_P
 jmp fp_exc
:lo
 lda fp_m+6
 and #$000F
 ora fp_m+4
 ora fp_m+2
 ora fp_m
 bne :u
 lda #FE_U+FE_P
 jmp fp_exc
:u
 lda #FE_U
 jsr fp_exc
:done
 rts

fp_st10
 mx %00
 lda fp_ta
 cmp #3
 bne :have
 lda #FE_I
 jsr fp_exc
 jsr fp_indef
:have
 lda fp_a
 sta fp_m
 lda fp_a+2
 sta fp_m+2
 lda fp_a+4
 sta fp_m+4
 lda fp_a+6
 sta fp_m+6
 lda fp_a+8
 sta fp_m+8
 rts

* To an integer: a number by SANE, as a 64-bit integer (FX2C,
* by the control word's rounding), and its range judged here:
* an infinity, a NaN, a denormal or nothing is invalid, and so is
* a number too large for the format (I alone, as the 8087 has
* it: SANE would flag precision too). The format's most negative
* is the answer.
fp_si2
 mx %00
 jsr fp_si
 bcs :inv                  ; (-2^63 too: too large for 16 bits)
 lda fp_m                  ; does it fit 16 bits? (the words above are the low word's sign)
 and #$8000
 beq :p
 lda #$FFFF
:p
 cmp fp_m+2
 bne :inv
 cmp fp_m+4
 bne :inv
 cmp fp_m+6
 bne :inv
 rts
:inv
 lda #FE_I
 jsr fp_exc
:least
 lda #$8000
 sta fp_m
 rts

fp_si4
 mx %00
 jsr fp_si
 bcs :inv
 lda fp_m+2
 and #$8000
 beq :p
 lda #$FFFF
:p
 cmp fp_m+4
 bne :inv
 cmp fp_m+6
 bne :inv
 rts
:inv
 lda #FE_I
 jsr fp_exc
:least
 stz fp_m
 lda #$8000
 sta fp_m+2
 rts

fp_si8
 mx %00
 jsr fp_si
 bcc :out
 stz fp_m
 stz fp_m+2
 stz fp_m+4
 lda #$8000
 sta fp_m+6
:out
 rts

* fp_si - fp_a to a 64-bit integer in fp_m; carry set when it is
* none (invalid raised) or -2^63, which SANE's comp cannot hold
fp_si
 mx %00
 ldx #0
 jsr fp_cl
 beq :num
 cmp #1
 beq :zero
 cmp #2
 bne :inv
 ldx #0                    ; a denormal: rounds to 0 or +-1
 jsr fp_dni
 bra :go
:zero
 stz fp_m
 stz fp_m+2
 stz fp_m+4
 stz fp_m+6
 clc
 rts
:num
 lda fp_a+8
 and #$7FFF
 cmp #$403E                ; 2^63 and more
 bcc :go
 lda fp_a+8                ; -2^63 itself
 cmp #$C03E
 bne :inv
 lda fp_a+6
 cmp #$8000
 bne :inv
 lda fp_a
 ora fp_a+2
 ora fp_a+4
 bne :inv
 sec
 rts
:inv
 lda #FE_I
 jsr fp_exc
 sec
 rts
:go
 lda #$0510                ; FX2C
 jsr fp_x2z
 clc
 rts

*----------------------------------------------------------
* The instructions with a memory operand
*----------------------------------------------------------
* FLD m32/m64/m80, FILD m16/m32/m64
fm_load
 mx %00
 stz fp_tx
 jsr fp_cvin
 jmp fp_push

* FST, FSTP, FIST, FISTP: every format
fm_storep
 mx %00
 jsr fm_store
 jmp fp_pop
fm_store
 mx %00
 lda #0
 jsr fp_st
 ldy #0
 jsr fp_ldr
 jsr fp_cvout
fm_put                     ; fp_m to the operand, unless an unmasked exception stops it
 mx %00
 lda fp_undo
 beq :put
 jsr fp_unm
 and #$001F
 beq :put
 rts
:put
 ldx fp_f
 lda fp_flen,x
 and #$00FF
 jmp fp_put

* The arithmetic and the compares of D8, DA, DC and DE: ST and
* the operand, made extended first. reg 5 and 7 are the operand
* less ST and the operand over ST.
fm_arith
 mx %00
 stz fp_den
 lda fp_r
 cmp #5
 beq :rev
 cmp #7
 beq :rev
 lda #12
 sta fp_tx
 jsr fp_cvin
 lda #0
 jsr fp_st
 stx fp_x0
 ldy #0
 jsr fp_ldr
 bra :do
:rev
 stz fp_tx
 jsr fp_cvin
 stz fp_den                ; (a denormal that is not the divisor)
 lda #0
 jsr fp_st
 stx fp_x0
 ldy #12
 jsr fp_ldr
:do
 lda fp_r
 cmp #2
 beq :cmp
 cmp #3
 beq :cmpp
 asl
 tax
 lda fp_kt,x
 sta fp_k
 jsr fp_arith
 ldx fp_x0
 ldy #0
 jmp fp_str
:cmpp
 jsr fp_cmp
 jmp fp_pop
:cmp
 jmp fp_cmp
* SANE's operation by the reg field: add, multiply, (compare,) (compare,) subtract, subtract, divide, divide
fp_kt      dw 0,4,0,0,2,2,6,6

fm_fldcw                   ; D9 /5
 mx %00
 lda fp_dirty              ; (SANE's flags first: an exception this unmasks is the 8087's to see)
 beq :go
 jsr fp_fold
:go
 lda fp_m
 sta >FPU_CW
 rts
fm_fnstcw                  ; D9 /7
 mx %00
 lda >FPU_CW
 sta fp_m
 lda #2
 jmp fp_put
fm_fnstsw                  ; DD /7
 mx %00
 jsr fp_sw
 sta fp_m
 lda #2
 jmp fp_put

*----------------------------------------------------------
* The instructions on the registers
*----------------------------------------------------------
* D8, DC, DE: ST(0) and ST(i). The result is ST - ST(i),
* ST(i) - ST (5), ST / ST(i), ST(i) / ST (7) for all three;
* it goes to ST(0) for D8 and to ST(i) for the others, and DE
* pops. reg 2 and 3 compare ST(0) with ST(i).
fr_arith
 mx %00
 stz fp_den
 lda #0
 jsr fp_st
 stx fp_x0
 lda vMODRM
 and #$0007
 jsr fp_st
 stx fp_xi
 lda fp_r
 cmp #2
 beq :cmp
 cmp #3
 beq :cmp
 cmp #5
 beq :rev
 cmp #7
 beq :rev
 ldx fp_x0
 ldy #0
 jsr fp_ldr
 ldx fp_xi
 ldy #12
 jsr fp_ldr
 bra :do
:rev
 ldx fp_xi
 ldy #0
 jsr fp_ldr
 ldx fp_x0
 ldy #12
 jsr fp_ldr
:do
 lda fp_r
 asl
 tax
 lda fp_kt,x
 sta fp_k
 jsr fp_arith
 ldx fp_x0
 lda fp_ix
 cmp #8
 bcc :st
 ldx fp_xi
:st
 ldy #0
 jsr fp_str
 lda fp_ix
 cmp #48
 bcc :out
 jmp fp_pop
:out
 rts
:cmp
 ldx fp_x0
 ldy #0
 jsr fp_ldr
 ldx fp_xi
 ldy #12
 jsr fp_ldr
 jsr fp_cmp
 lda fp_r                  ; FCOMP pops, DE pops, FCOMPP (DE D9) is both
 cmp #3
 bne :c1
 jsr fp_pop
:c1
 lda fp_ix
 cmp #48
 bcc :out
 jmp fp_pop

fr_fld                     ; D9 C0+i
 mx %00
 lda vMODRM
 and #$0007
 jsr fp_st
 ldy #0
 jsr fp_ldr
 lda fp_ta
 cmp #3
 bne :ok
 lda #FE_I
 jsr fp_exc
 jsr fp_indef
:ok
 jmp fp_push

fr_fxch                    ; D9 C8+i (and DD C8+i): an empty one is the indefinite first
 mx %00
 lda #0
 jsr fp_st
 stx fp_x0
 ldy #0
 jsr fp_ldr
 lda vMODRM
 and #$0007
 jsr fp_st
 stx fp_xi
 ldy #12
 jsr fp_ldr
 lda fp_ta
 cmp #3
 bne :aok
 lda #FE_I
 jsr fp_exc
 jsr fp_indef
:aok
 lda fp_tb
 cmp #3
 bne :bok
 lda #FE_I
 jsr fp_exc
 ldx #12
 jsr fp_ind
:bok
 ldx fp_xi
 ldy #0
 jsr fp_str
 ldx fp_x0
 ldy #12
 jmp fp_str

fr_fstp                    ; DD D8+i (and D9 D8+i)
 mx %00
 jsr fr_fst
 jmp fp_pop
fr_fst                     ; DD D0+i
 mx %00
 lda #0
 jsr fp_st
 ldy #0
 jsr fp_ldr
 lda fp_ta
 cmp #3
 bne :ok
 lda #FE_I
 jsr fp_exc
 jsr fp_indef
:ok
 lda vMODRM
 and #$0007
 jsr fp_st
 ldy #0
 jmp fp_str

fr_ffree                   ; DD C0+i
 mx %00
 lda vMODRM
 and #$0007
 jsr fp_st
 lda #3
 sta >FPU_REG+10,x
 rts

fr_nop                     ; D9 D0
 mx %00
 lda vMODRM
 cmp #$00D0
 beq :ok
 jmp fp_none
:ok
 rts

fr_d9e                     ; D9 E0-E7: FCHS, FABS, -, -, FTST, FXAM
 mx %00
 lda vMODRM
 and #$0007
 asl
 tax
 jmp (:t,x)
:t         da :chs,:abs,fp_none,fp_none,:tst,fr_fxam,fp_none,fp_none
:chs
 jsr :top
 bcs :out
 lda >FPU_REG+8,x
 eor #$8000
 sta >FPU_REG+8,x
:out
 rts
:abs
 jsr :top
 bcs :out
 lda >FPU_REG+8,x
 and #$7FFF
 sta >FPU_REG+8,x
 rts
:top                       ; X = ST(0); with nothing in it, invalid and the indefinite, C set
 lda #0
 jsr fp_st
 lda >FPU_REG+10,x
 cmp #3
 beq :none
 clc
 rts
:none
 phx
 lda #FE_I
 jsr fp_exc
 jsr fp_indef
 plx
 ldy #0
 jsr fp_str
 sec
 rts
:tst                       ; ST(0) against +0
 lda #0
 jsr fp_st
 ldy #0
 jsr fp_ldr
 stz fp_b
 stz fp_b+2
 stz fp_b+4
 stz fp_b+6
 stz fp_b+8
 lda #1
 sta fp_tb
 jmp fp_cmp

* FXAM: C3 C2 C1 C0, C1 the sign. 0000 unnormal, 0001 NaN, 0100
* normal, 0101 infinity, 1000 zero, 1001 empty, 1100 denormal.
fr_fxam
 mx %00
 lda #0
 jsr fp_st
 ldy #0
 jsr fp_ldr
 stz fp_rc
 lda fp_a+8
 bpl :pos
 lda #$0200
 sta fp_rc
:pos
 lda fp_ta
 cmp #3
 bne :full
 stz fp_rc                 ; (empty: C1 is not the sign of what was there)
 lda #$4100
 bra :set
:full
 lda fp_a+8
 and #$7FFF
 beq :low
 cmp #$7FFF
 beq :high
 lda fp_a+6
 bpl :unn
 lda #$0400
 bra :set
:unn
 lda #0
 bra :set
:high
 lda fp_a
 ora fp_a+2
 ora fp_a+4
 bne :nan
 lda fp_a+6
 cmp #$8000
 bne :nan
 lda #$0500
 bra :set
:nan
 lda #$0100
 bra :set
:low
 lda fp_a
 ora fp_a+2
 ora fp_a+4
 ora fp_a+6
 bne :den
 lda #$4000
 bra :set
:den
 lda #$4400
:set
 ora fp_rc
 sta fp_rc
 lda >FPU_SW
 and #$B8FF
 ora fp_rc
 sta >FPU_SW
 rts

fr_const                   ; D9 E8-EE: FLD1, FLDL2T, FLDL2E, FLDPI, FLDLG2, FLDLN2, FLDZ
 mx %00
 lda vMODRM
 and #$0007
 cmp #7
 bne :have
 jmp fp_none
:have
 asl
 tax
 lda fp_x12,x
 tax
 lda fp_ctab,x
 sta fp_a
 lda fp_ctab+2,x
 sta fp_a+2
 lda fp_ctab+4,x
 sta fp_a+4
 lda fp_ctab+6,x
 sta fp_a+6
 lda fp_ctab+8,x
 sta fp_a+8
 lda fp_ctab+10,x
 sta fp_ta
 jmp fp_push
* (each to the nearest, whatever the control word: the 8087 does not round them)
fp_ctab    dw $0000,$0000,$0000,$8000,$3FFF,0      ; 1
           dw $8AFE,$CD1B,$784B,$D49A,$4000,0      ; log2 10
           dw $F0BC,$5C17,$3B29,$B8AA,$3FFF,0      ; log2 e
           dw $C235,$2168,$DAA2,$C90F,$4000,0      ; pi
           dw $F799,$FBCF,$9A84,$9A20,$3FFD,0      ; log10 2
           dw $79AC,$D1CF,$17F7,$B172,$3FFE,0      ; ln 2
           dw $0000,$0000,$0000,$0000,$0000,1      ; 0

fr_rndint
 mx %00
 lda #0
 jsr fp_st
 stx fp_x0
 ldy #0
 jsr fp_ldr
 ldx #0
 jsr fp_cl
 asl
 tax
 jmp (:t,x)
:t         da :norm,:out,:den,:out,:nan,:empty
:empty
 lda #FE_I
 jsr fp_exc
 jsr fp_indef
 bra :st
:nan
 lda #FE_I
 jmp fp_exc
:den
 lda #FE_D
 jsr fp_exc
 ldx #0
 jsr fp_dni
 bra :go
:norm
 lda fp_a+8                ; from 2^63 up it is an integer
 and #$7FFF
 cmp #$403E
 bcs :out
:go
 stz fp_k
 stz fp_bz
 stz fp_nz
 lda #1
 jsr fp_need
 pea ^fp_a
 pea fp_a
 pea $0014                 ; FRINTX
 ldx #SANE_FP
 jsl TOOLS
 lda #1
 sta fp_dirty
 jsr fp_post
:st
 ldx fp_x0
 ldy #0
 jmp fp_str
:out
 rts

fr_dbe                     ; DB E0-E7, by the r/m field: FENI, FDISI, FNCLEX, FNINIT
 mx %00
 lda vMODRM
 and #$0007
 cmp #4
 bcc :have
 jmp fp_none
:have
 asl
 tax
 jmp (:tab,x)
:tab       da :eni,:disi,:clex,fp_reset
:eni
 lda >FPU_CW
 and #$FFFF-CW_IEM
 sta >FPU_CW
 rts
:disi
 lda >FPU_CW
 ora #CW_IEM
 sta >FPU_CW
 rts
:clex                      ; the exception flags, the interrupt request and busy: SANE's flags with them
 lda >FPU_SW
 and #$7F00
 sta >FPU_SW
 lda #$FFFF
 sta fp_env
 stz fp_dirty
 rts

*----------------------------------------------------------
* The environment (figure S-19): control, status and tag
* words, the instruction's address (20 bits: the top four in
* the next word's top, the opcode's eleven bits below them),
* the operand's. FSAVE (figure S-18): the same and the eight
* registers, ST(0) first.
*----------------------------------------------------------
* fp_tw - A = the tag word (register 7's two bits the top)
fp_tw
 mx %00
 lda #0
 ldx #84
:t
 asl
 asl
 ora >FPU_REG+10,x
 pha
 txa
 sec
 sbc #12
 tax
 pla
 bcs :t
 rts

* fp_envo - the environment to fp_m
fp_envo
 mx %00
 lda >FPU_CW
 sta fp_m
 jsr fp_sw
 sta fp_m+2
 jsr fp_tw
 sta fp_m+4
 lda >FPU_IP
 sta fp_m+6
 lda >FPU_IP+2
 xba
 asl
 asl
 asl
 asl
 and #$F000
 ora >FPU_OPC
 sta fp_m+8
 lda >FPU_DP
 sta fp_m+10
 lda >FPU_DP+2
 xba
 asl
 asl
 asl
 asl
 and #$F000
 sta fp_m+12
 rts

* fp_envi - the environment from fp_m: the registers' tags
* from the tag word, but for one not empty its tag is what its
* contents are
fp_envi
 mx %00
 lda fp_dirty              ; SANE's flags are not this environment's
 beq :c
 jsr fp_fold
:c
 lda fp_m
 sta >FPU_CW
 lda fp_m+2
 and #$3800
 xba
 lsr
 lsr
 lsr
 sta >FPU_TOP
 lda fp_m+2
 and #$47FF                ; (not busy, not the top)
 sta >FPU_SW
 lda fp_m+6
 sta >FPU_IP
 lda fp_m+8
 and #$07FF
 sta >FPU_OPC
 lda fp_m+8
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 sta >FPU_IP+2
 lda fp_m+10
 sta >FPU_DP
 lda fp_m+12
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 sta >FPU_DP+2
 lda fp_m+4
 sta fp_t
 ldx #0
:g
 lda fp_t
 and #$0003
 cmp #3
 beq :e
 jsr fp_rtag
 bra :n
:e
 sta >FPU_REG+10,x
:n
 lsr fp_t
 lsr fp_t
 txa
 clc
 adc #12
 tax
 cpx #96
 bcc :g
 rts

* fp_rtag - the register at X tagged by what it holds (X kept)
fp_rtag
 mx %00
 phx
 ldy #0
 jsr fp_ldr
 ldx #0
 jsr fp_tagx
 plx
 sta >FPU_REG+10,x
 rts

fm_fstenv                  ; D9 /6: and then every exception masked
 mx %00
 jsr fp_envo
 lda #14
 jsr fp_put
 lda >FPU_CW
 ora #$003F
 sta >FPU_CW
 rts
fm_fldenv                  ; D9 /4
 mx %00
 jmp fp_envi
fm_fsave                   ; DD /6: and then FNINIT
 mx %00
 jsr fp_envo
 ldy #14
 stz fp_cnt
:r
 lda fp_cnt
 jsr fp_st
 lda >FPU_REG,x
 sta fp_m,y
 lda >FPU_REG+2,x
 sta fp_m+2,y
 lda >FPU_REG+4,x
 sta fp_m+4,y
 lda >FPU_REG+6,x
 sta fp_m+6,y
 lda >FPU_REG+8,x
 sta fp_m+8,y
 tya
 clc
 adc #10
 tay
 inc fp_cnt
 lda fp_cnt
 cmp #8
 bcc :r
 lda #94
 jsr fp_put
 jmp fp_reset
fm_frstor                  ; DD /4: the registers by the image's stack top, then the environment
 mx %00
 lda fp_m+2
 and #$3800
 xba
 lsr
 lsr
 lsr
 sta >FPU_TOP
 ldy #14
 stz fp_cnt
:r
 lda fp_cnt
 jsr fp_st
 lda fp_m,y
 sta >FPU_REG,x
 lda fp_m+2,y
 sta >FPU_REG+2,x
 lda fp_m+4,y
 sta >FPU_REG+4,x
 lda fp_m+6,y
 sta >FPU_REG+6,x
 lda fp_m+8,y
 sta >FPU_REG+8,x
 tya
 clc
 adc #10
 tay
 inc fp_cnt
 lda fp_cnt
 cmp #8
 bcc :r
 jmp fp_envi

*----------------------------------------------------------
* M9.4: the rest of the 8087's instructions
*----------------------------------------------------------
* fp_one - ST(0) to fp_a (fp_x0 its place), A = its class. Carry
* set when there is nothing to work on: empty (invalid, fp_a the
* indefinite) or a NaN (invalid, fp_a the NaN); the caller puts
* fp_a where the result goes. A denormal raises D (class 2).
fp_one
 mx %00
 lda #0
 jsr fp_st
 stx fp_x0
 ldy #0
 jsr fp_ldr
 ldx #0
 jsr fp_cl
 cmp #4
 bcc :num
 pha
 lda #FE_I
 jsr fp_exc
 pla
 cmp #5
 bne :nan
 jsr fp_indef
:nan
 sec
 rts
:num
 cmp #2
 bne :out
 pha
 lda #FE_D
 jsr fp_exc
 pla
:out
 clc
 rts

* fp_st0 - fp_a to ST(0) (fp_x0)
fp_st0
 mx %00
 ldx fp_x0
 ldy #0
 jmp fp_str

* fp_inv0 - invalid: the indefinite to ST(0)
fp_inv0
 mx %00
 lda #FE_I
 jsr fp_exc
 jsr fp_indef
 bra fp_st0

* fp_a2b - fp_a and its tag to fp_b
fp_a2b
 mx %00
 ldx #10
:c
 lda fp_a,x
 sta fp_b,x
 dex
 dex
 bpl :c
 rts

* fp_nx - the operand X, a number not 0: its significand made
* normal; A = its exponent (a denormal's is 1), below 1 when the
* shift takes it there
fp_nx
 mx %00
 lda fp_a+8,x
 and #$7FFF
 bne :e
 lda #1
:e
 sta fp_e
:l
 lda fp_a+6,x
 bmi :d
 asl fp_a,x
 rol fp_a+2,x
 rol fp_a+4,x
 rol fp_a+6,x
 dec fp_e
 bra :l
:d
 lda fp_e
 rts

* fp_elem - Elems816's operation A on fp_a. Its flags are not
* the 8087's: the 8087's transcendentals report only precision.
fp_elem
 mx %00
 pha
 lda #1
 jsr fp_need
 lda fp_dirty
 beq :c
 jsr fp_fold
:c
 pla
 pea ^fp_a
 pea fp_a
 pha
 ldx #$0B0A                ; Elems816
 jsl TOOLS
 lda fp_env                ; its flags cleared
 pha
 pea $0001                 ; FSETENV
 ldx #SANE_FP
 jsl TOOLS
 stz fp_dirty
 lda #FE_P
 jsr fp_exc
 stz fp_k
 stz fp_bz
 stz fp_nz
 jmp fp_post

* fp_sane1 - FP816's operation A on fp_a alone (FSQRTX), with the
* control word's rounding and precision
fp_sane1
 mx %00
 pha
 lda #0
 jsr fp_need
 pla
 pea ^fp_a
 pea fp_a
 pha
 ldx #SANE_FP
 jsl TOOLS
 lda #1
 sta fp_dirty
 stz fp_k
 stz fp_bz
 stz fp_nz
 jmp fp_post

fr_f2xm1                   ; D9 F0: 2^ST - 1 (the 8087's operand is 0 to 0.5)
 mx %00
 jsr fp_one
 bcs :st
 cmp #1
 beq :out                  ; +-0 stays
 cmp #3
 beq :out
 cmp #2
 bne :go
 ldx #0
 jsr fp_dni
:go
 lda #$000E                ; FEXP21X
 jsr fp_elem
:st
 jmp fp_st0
:out
 rts

fr_fsqrt                   ; D9 FA
 mx %00
 jsr fp_one
 bcs :st
 cmp #1
 beq :out                  ; +-0 stays
 cmp #2
 beq :inv                  ; a denormal
 cmp #3
 beq :inf
 lda fp_a+8                ; a negative number, or an unnormal
 bmi :inv
 lda fp_a+6
 bpl :inv
 lda #$0012                ; FSQRTX
 jsr fp_sane1
:st
 jmp fp_st0
:inf
 lda fp_a+8                ; +infinity is itself when affine
 bmi :inv
 lda >FPU_CW
 and #CW_IC
 bne :out
:inv
 jmp fp_inv0
:out
 rts

fr_fscale                  ; D9 FD: ST * 2^(ST(1), chopped to an integer)
 mx %00
 jsr fp_one
 bcc *+5
 jmp :st
 sta fp_ca
 lda #1
 jsr fp_st
 ldy #12
 jsr fp_ldr
 ldx #12
 jsr fp_cl
 cmp #3
 bcc *+5
 jmp :inv
 cmp #2
 bcc :n1
 lda #FE_D
 jsr fp_exc
 bra :out                  ; a denormal's integer part is 0
:n1
 cmp #1
 beq :out
 lda fp_ca
 cmp #1
 beq :out                  ; 0 and infinity stay
 cmp #3
 beq :out
 cmp #2
 bne :c
 ldx #0
 jsr fp_dni
:c
 lda fp_b+8                ; the scale: ST(1)'s integer part, to +-32767
 and #$7FFF
 sec
 sbc #16383
 bmi :out
 cmp #15
 bcc :sh
 lda #$7FFF
 bra :sg
:sh
 eor #$000F                ; 15 - e
 tax
 lda fp_b+6
:r
 dex
 bmi :sg
 lsr
 bra :r
:sg
 ldx fp_b+8
 bpl :pos
 eor #$FFFF
 inc
:pos
 cmp #0
 beq :out
 pha                       ; the scale, by value
 lda #0
 jsr fp_need
 pea ^fp_a
 pea fp_a
 pea $0018                 ; FSCALBX
 ldx #SANE_FP
 jsl TOOLS
 lda #1
 sta fp_dirty
 stz fp_k
 stz fp_bz
 stz fp_nz
 jsr fp_post
:st
 jmp fp_st0
:inv
 jmp fp_inv0
:out
 rts

fr_fxtract                 ; D9 F4: ST becomes its exponent, and its significand is pushed
 mx %00
 jsr fp_one
 bcs :st
 cmp #3
 beq :inv
 cmp #1
 beq :zero                 ; +-0: both +-0 (table S-26)
 ldx #0
 jsr fp_nx
 sec
 sbc #16383
 sta fp_m                  ; the exponent, a 16-bit integer
 lda fp_a+8
 and #$8000
 ora #$3FFF
 sta fp_a+8
 stz fp_ta
 lda #12
 sta fp_tx
 jsr fp_li2
 ldx fp_x0
 ldy #12
 jsr fp_str
 jmp fp_push
:zero
 jsr fp_st0
 jmp fp_push
:st
 jmp fp_st0
:inv
 jmp fp_inv0

*--- FPREM (D9 F8): ST's partial remainder by ST(1), the quotient
* chopped; exact, done here by long division. Up to 64 bits of
* quotient a time: more and C2 says the remainder is partial, to
* be asked again. Complete, C0 C3 C1 are the quotient's last
* three bits.
fr_fprem
 mx %00
 lda #0
 jsr fp_st
 stx fp_x0
 ldy #0
 jsr fp_ldr
 lda #1
 jsr fp_st
 ldy #12
 jsr fp_ldr
 ldx #0
 jsr fp_cl
 sta fp_ca
 ldx #12
 jsr fp_cl
 sta fp_cb
 cmp #5
 beq :inv
 lda fp_ca
 cmp #5
 beq :inv
 cmp #4
 beq :nana
 lda fp_cb
 cmp #4
 beq :nanb
 cmp #1
 beq :inv                  ; by 0
 cmp #2
 beq :invd                 ; by a denormal
 lda fp_ca
 cmp #3
 beq :inv                  ; infinity's
 lda fp_cb
 cmp #3
 beq :whole                ; by infinity: ST as it is
 lda fp_b+6
 bpl :inv                  ; by an unnormal
 lda fp_ca
 cmp #1
 beq :whole
 cmp #2
 bne :go
 lda #FE_D
 jsr fp_exc
 bra :go
:invd
 lda #FE_D
 jsr fp_exc
:inv
 jmp fp_inv0
:nanb
 jsr fp_b2a
:nana
 lda #FE_I
 jsr fp_exc
 jmp fp_st0
:whole
 stz fp_t
 lda #0
 jmp :cc
:go
 ldx #0
 jsr fp_nx
 sta fp_ea
 ldx #12
 jsr fp_nx
 sta fp_eb
 lda fp_ea
 sec
 sbc fp_eb
 bmi :whole                ; ST is the smaller
 cmp #66
 bcc :all
 lda #64                   ; a part: 64 bits of the quotient
 sta fp_cnt
 lda #$0400                ; (C2)
 sta fp_rc
 bra :div
:all
 inc
 sta fp_cnt
 stz fp_rc
:div
 lda fp_ea                 ; the remainder's exponent: ea - steps + 1
 sec
 sbc fp_cnt
 inc
 sta fp_eb
 lda fp_a
 sta fp_rm
 lda fp_a+2
 sta fp_rm+2
 lda fp_a+4
 sta fp_rm+4
 lda fp_a+6
 sta fp_rm+6
 stz fp_rm+8
 stz fp_t
:lp
 asl fp_t
 lda fp_rm+8
 bne :ge
 lda fp_rm+6
 cmp fp_b+6
 bne :cmp
 lda fp_rm+4
 cmp fp_b+4
 bne :cmp
 lda fp_rm+2
 cmp fp_b+2
 bne :cmp
 lda fp_rm
 cmp fp_b
:cmp
 bcc :lt
:ge
 sec
 lda fp_rm
 sbc fp_b
 sta fp_rm
 lda fp_rm+2
 sbc fp_b+2
 sta fp_rm+2
 lda fp_rm+4
 sbc fp_b+4
 sta fp_rm+4
 lda fp_rm+6
 sbc fp_b+6
 sta fp_rm+6
 lda fp_rm+8
 sbc #0
 sta fp_rm+8
 inc fp_t
:lt
 dec fp_cnt
 beq :fin
 asl fp_rm
 rol fp_rm+2
 rol fp_rm+4
 rol fp_rm+6
 rol fp_rm+8
 bra :lp
:fin
 lda fp_rm
 sta fp_a
 lda fp_rm+2
 sta fp_a+2
 lda fp_rm+4
 sta fp_a+4
 lda fp_rm+6
 sta fp_a+6
 ora fp_a+4
 ora fp_a+2
 ora fp_a
 bne :nz
 lda fp_a+8                ; 0, the dividend's sign
 and #$8000
 sta fp_a+8
 lda #1
 sta fp_ta
 bra :put
:nz
 lda fp_a+6
 bmi :norm
 lda fp_eb
 cmp #2
 bcc :den
 dec fp_eb
 asl fp_a
 rol fp_a+2
 rol fp_a+4
 rol fp_a+6
 bra :nz
:den
 stz fp_eb                 ; exponent field 0: the 8087's denormal
 lda #2
 bra :tg
:norm
 lda #0
:tg
 sta fp_ta
 lda fp_a+8
 and #$8000
 ora fp_eb
 sta fp_a+8
:put
 jsr fp_st0
 lda fp_rc
 bne :cc
 lda fp_t                  ; complete: C0 = Q2, C3 = Q1, C1 = Q0
 and #$0007
 asl
 tax
 lda fp_qcc,x
:cc
 sta fp_rc
 lda >FPU_SW
 and #$B8FF
 ora fp_rc
 sta >FPU_SW
 rts
fp_qcc     dw $0000,$0200,$4000,$4200,$0100,$0300,$4100,$4300

fr_fyl2x                   ; D9 F1: ST(1) * log2(ST), popped
 mx %00
 lda #$0002                ; FLOG2X
 bra fp_yl
fr_fyl2xp1                 ; D9 F9: ST(1) * log2(ST + 1), popped
 mx %00
 lda #$0006                ; FLOG21X
fp_yl
 mx %00
 sta fp_cnt
 lda #1
 jsr fp_st
 stx fp_xi
 lda >FPU_REG+10,x
 cmp #3
 beq :inv
 jsr fp_one
 bcs :put
 cmp #2
 bne :go
 ldx #0
 jsr fp_dni
:go
 lda fp_cnt
 jsr fp_elem
 ldx fp_xi
 ldy #12
 jsr fp_ldr
 lda #4
 sta fp_k
 stz fp_den
 jsr fp_arith
 bra :put
:inv
 lda #FE_I
 jsr fp_exc
 jsr fp_indef
:put
 ldx fp_xi
 ldy #0
 jsr fp_str
 jmp fp_pop

fr_fptan                   ; D9 F2: tan(ST) as Y and X: here Y the tangent and X (pushed) 1
 mx %00
 jsr fp_one
 bcs :two
 cmp #3
 beq :inv
 cmp #1
 beq :one                  ; tan(+-0) = +-0
 cmp #2
 bne :go
 ldx #0
 jsr fp_dni
:go
 lda #$001E                ; FTANX
 jsr fp_elem
:one
 jsr fp_st0
 ldx #0                    ; 1.0, from the constants
 ldy #0
:c
 lda fp_ctab,x
 sta fp_a,y
 inx
 inx
 iny
 iny
 cpy #12
 bcc :c
 jmp fp_push
:inv
 lda #FE_I
 jsr fp_exc
 jsr fp_indef
:two
 jsr fp_st0
 jsr fp_indef
 jmp fp_push

fr_fpatan                  ; D9 F3: arctan(ST(1) / ST) to ST(1), popped
 mx %00
 lda #1
 jsr fp_st
 stx fp_xi
 lda >FPU_REG+10,x
 cmp #3
 bne :y
 lda #FE_I
 jsr fp_exc
 jsr fp_indef
 bra :put
:y
 jsr fp_one                ; X
 bcs :put
 cmp #2
 bne :x
 ldx #0
 jsr fp_dni
:x
 lda fp_a+8
 sta fp_xs
 jsr fp_a2b                ; fp_b = X, fp_a = Y
 ldx fp_xi
 ldy #0
 jsr fp_ldr
 lda fp_a+8
 sta fp_ys
 lda fp_tb
 cmp #1
 bne :div
 lda fp_ta                 ; X = 0: +-pi/2, or Y when it is 0 too
 cmp #1
 beq :put
 jsr fp_pi
 lda fp_a+8
 and #$8000
 ora #$3FFF
 sta fp_a+8
 bra :put
:div
 lda #6
 sta fp_k
 stz fp_den
 jsr fp_arith
 lda #$0018                ; FATANX
 jsr fp_elem
 lda fp_xs                 ; X < 0: pi added, with Y's sign
 bpl :put
 jsr fp_a2b
 jsr fp_pi
 stz fp_k
 stz fp_den
 jsr fp_arith
:put
 ldx fp_xi
 ldy #0
 jsr fp_str
 jmp fp_pop
fp_xs      dw 0
fp_ys      dw 0

* fp_pi - fp_a = pi with Y's sign (fp_ys)
fp_pi
 mx %00
 ldx #36
 ldy #0
:c
 lda fp_ctab,x
 sta fp_a,y
 inx
 inx
 iny
 iny
 cpy #12
 bcc :c
 lda fp_ys
 and #$8000
 ora fp_a+8
 sta fp_a+8
 rts

*--- packed decimal: nine bytes of two digits, the least
* significant first, and a byte with the sign in its top bit
fm_fbld                    ; DF /4
 mx %00
 stz fp_q
 stz fp_q+2
 stz fp_q+4
 stz fp_q+6
 ldy #8
:by
 lda fp_m,y
 and #$00FF
 sta fp_t
 lsr
 lsr
 lsr
 lsr
 jsr fp_m10a
 lda fp_t
 and #$000F
 jsr fp_m10a
 dey
 bpl :by
 stz fp_s
 lda fp_m+8
 bpl :pos
 lda #$8000
 sta fp_s
:pos
 lda fp_q
 ora fp_q+2
 ora fp_q+4
 ora fp_q+6
 bne :num
 ldx #0
 jsr fp_lizero
 lda fp_s
 sta fp_a+8
 jmp fp_push
:num
 lda fp_q
 sta fp_a
 lda fp_q+2
 sta fp_a+2
 lda fp_q+4
 sta fp_a+4
 lda fp_q+6
 sta fp_a+6
 ldx #0
 lda #$403E
 jsr fp_nrm
 jmp fp_push

* fp_m10a - fp_q = fp_q * 10 + A (Y kept)
fp_m10a
 mx %00
 pha
 asl fp_q
 rol fp_q+2
 rol fp_q+4
 rol fp_q+6
 lda fp_q
 sta fp_rm
 lda fp_q+2
 sta fp_rm+2
 lda fp_q+4
 sta fp_rm+4
 lda fp_q+6
 sta fp_rm+6
 asl fp_q
 rol fp_q+2
 rol fp_q+4
 rol fp_q+6
 asl fp_q
 rol fp_q+2
 rol fp_q+4
 rol fp_q+6
 clc
 lda fp_q
 adc fp_rm
 sta fp_q
 lda fp_q+2
 adc fp_rm+2
 sta fp_q+2
 lda fp_q+4
 adc fp_rm+4
 sta fp_q+4
 lda fp_q+6
 adc fp_rm+6
 sta fp_q+6
 pla
 clc
 adc fp_q
 sta fp_q
 lda fp_q+2
 adc #0
 sta fp_q+2
 lda fp_q+4
 adc #0
 sta fp_q+4
 lda fp_q+6
 adc #0
 sta fp_q+6
 rts

* fp_d10 - fp_q = fp_q / 10, A = the remainder (Y kept)
fp_d10
 mx %00
 phy
 stz fp_ea
 ldy #64
:l
 asl fp_q
 rol fp_q+2
 rol fp_q+4
 rol fp_q+6
 rol fp_ea
 lda fp_ea
 cmp #10
 bcc :n
 sbc #10
 sta fp_ea
 inc fp_q
:n
 dey
 bne :l
 lda fp_ea
 ply
 rts

fm_fbstp                   ; DF /6: ST rounded to an integer, as 18 digits, and popped
 mx %00
 lda #0
 jsr fp_st
 ldy #0
 jsr fp_ldr
 ldx #0
 jsr fp_cl
 cmp #3
 bcc *+5
 jmp :inv
 cmp #1
 bne :nz
 stz fp_q
 stz fp_q+2
 stz fp_q+4
 stz fp_q+6
 bra :dig
:nz
 cmp #2
 bne :go
 ldx #0
 jsr fp_dni
:go
 lda #$0510                ; FX2C, by the control word's rounding
 jsr fp_x2z
 lda fp_m
 sta fp_q
 lda fp_m+2
 sta fp_q+2
 lda fp_m+4
 sta fp_q+4
 lda fp_m+6
 sta fp_q+6
 bpl :abs
 lda #0
 sec
 sbc fp_q
 sta fp_q
 lda #0
 sbc fp_q+2
 sta fp_q+2
 lda #0
 sbc fp_q+4
 sta fp_q+4
 lda #0
 sbc fp_q+6
 sta fp_q+6
 bmi :inv                  ; -2^63, or SANE's answer for one too large
:abs
 lda fp_q+6                ; 10^18 and more: invalid
 cmp #$0DE0
 bne :c
 lda fp_q+4
 cmp #$B6B3
 bne :c
 lda fp_q+2
 cmp #$A764
 bne :c
 lda fp_q
 cmp #$0000
:c
 bcs :inv
:dig
 ldy #0
:d
 jsr fp_d10
 sta fp_t
 jsr fp_d10
 asl
 asl
 asl
 asl
 ora fp_t
 sep #$20
 mx %10
 sta fp_m,y
 rep #$20
 mx %00
 iny
 cpy #9
 bcc :d
 sep #$20
 mx %10
 lda fp_a+9                ; the sign: ST's, so that -0 is -0
 and #$80
 sta fp_m+9
 rep #$20
 mx %00
 bra :put
:inv
 lda #FE_I
 jsr fp_exc
 stz fp_m                  ; packed decimal's indefinite
 stz fp_m+2
 stz fp_m+4
 lda #$C000
 sta fp_m+6
 lda #$FFFF
 sta fp_m+8
:put
 jsr fm_put
 jmp fp_pop

fr_d9f0                    ; D9 F0-F7
 mx %00
 lda vMODRM
 and #$0007
 asl
 tax
 jmp (:t,x)
:t         da fr_f2xm1,fr_fyl2x,fr_fptan,fr_fpatan,fr_fxtract,fp_none,:dec,:inc
:inc
 lda >FPU_TOP
 inc
 bra :set
:dec
 lda >FPU_TOP
 dec
:set
 and #$0007
 sta >FPU_TOP
 rts

fr_d9f8                    ; D9 F8-FF
 mx %00
 lda vMODRM
 and #$0007
 asl
 tax
 jmp (:t,x)
:t         da fr_fprem,fr_fyl2xp1,fr_fsqrt,fp_none,fr_rndint,fr_fscale,fp_none,fp_none

*--- a memory operand by opcode and reg field: its format (fp_f)
* in the low bits, $80 when the instruction reads it, $FF no
* such instruction of the 8087's (or none done yet)
* ($40: a control instruction, which keeps the pointers it finds and is not undone; the
* formats 6 and 7 are the environment's 14 bytes and FSAVE's 94; FBLD and FBSTP are 10)
fp_mfl     dfb $80,$80,$80,$80,$80,$80,$80,$80      ; D8: a single
           dfb $80,$FF,$00,$00,$C6,$C2,$46,$42      ; D9: FLD, -, FST, FSTP, FLDENV, FLDCW, FSTENV, FSTCW
           dfb $83,$83,$83,$83,$83,$83,$83,$83      ; DA: a 32-bit integer
           dfb $83,$FF,$03,$03,$FF,$85,$FF,$05      ; DB: FILD, -, FIST, FISTP, -, FLD m80, -, FSTP m80
           dfb $81,$81,$81,$81,$81,$81,$81,$81      ; DC: a double
           dfb $81,$FF,$01,$01,$C7,$FF,$47,$42      ; DD: FLD, -, FST, FSTP, FRSTOR, -, FSAVE, FSTSW
           dfb $82,$82,$82,$82,$82,$82,$82,$82      ; DE: a 16-bit integer
           dfb $82,$FF,$02,$02,$85,$84,$05,$04      ; DF: FILD, -, FIST, FISTP, FBLD, FILD m64, FBSTP, FISTP m64
fp_flen    dfb 4,8,2,4,8,10,14,94
fp_mem
 da fm_arith,fm_arith,fm_arith,fm_arith,fm_arith,fm_arith,fm_arith,fm_arith      ; D8
 da fm_load,fp_none,fm_store,fm_storep,fm_fldenv,fm_fldcw,fm_fstenv,fm_fnstcw     ; D9
 da fm_arith,fm_arith,fm_arith,fm_arith,fm_arith,fm_arith,fm_arith,fm_arith      ; DA
 da fm_load,fp_none,fm_store,fm_storep,fp_none,fm_load,fp_none,fm_storep         ; DB
 da fm_arith,fm_arith,fm_arith,fm_arith,fm_arith,fm_arith,fm_arith,fm_arith      ; DC
 da fm_load,fp_none,fm_store,fm_storep,fm_frstor,fp_none,fm_fsave,fm_fnstsw      ; DD
 da fm_arith,fm_arith,fm_arith,fm_arith,fm_arith,fm_arith,fm_arith,fm_arith      ; DE
 da fm_load,fp_none,fm_store,fm_storep,fm_fbld,fm_load,fm_fbstp,fm_storep        ; DF
*--- and a register (mod 11): the r/m field is the register, or the instruction of a group
fp_reg
 da fr_arith,fr_arith,fr_arith,fr_arith,fr_arith,fr_arith,fr_arith,fr_arith      ; D8
 da fr_fld,fr_fxch,fr_nop,fr_fstp,fr_d9e,fr_const,fr_d9f0,fr_d9f8                ; D9
 da fp_none,fp_none,fp_none,fp_none,fp_none,fp_none,fp_none,fp_none              ; DA
 da fp_none,fp_none,fp_none,fp_none,fr_dbe,fp_none,fp_none,fp_none               ; DB
 da fr_arith,fr_arith,fr_arith,fr_arith,fr_arith,fr_arith,fr_arith,fr_arith      ; DC
 da fr_ffree,fr_fxch,fr_fst,fr_fstp,fp_none,fp_none,fp_none,fp_none              ; DD
 da fr_arith,fr_arith,fr_arith,fr_arith,fr_arith,fr_arith,fr_arith,fr_arith      ; DE
 da fp_none,fp_none,fp_none,fp_none,fp_none,fp_none,fp_none,fp_none              ; DF
 err *-1-FPU_BASE/$10000     ; one bank
