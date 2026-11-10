*----------------------------------------------------------
* harness.s - M1: run packed SingleStepTests vectors.
*
* The loader put tools/vectors.py's output at DATA_BASE.
* Each record (little-endian):
*   +0  u16 reclen (0 ends the list)
*   +2  u16 regs[14]   AX CX DX BX SP BP SI DI ES CS SS DS IP FLAGS
*   +30 u16 xregs[14]  expected
*   +58 u16 mask       FLAGS bits to compare
*   +60 u16 nram, +62 u16 nxram
*   +64 {u16 lo, u8 bank, u8 val} x nram, then x nxram
* For each: load the state, run one instruction, compare,
* set a bit in the pass bitmap. Results at RES_BASE:
*   +0 u16 run, +2 u16 passed, +4 u16 first failing index
*   ($FFFF none), +8 u16 regs[14] actual for it (FLAGS
*   assembled), +36 u16 lo/+38 u8 bank/+39 u8 expected/+40
*   u8 actual of its first RAM mismatch (+39 = +40 = 0 if
*   none), +64 u16 unimplemented opcodes retired;
*   +$100 the bitmap. Returns A = 0 when every vector passed.
*----------------------------------------------------------
RES_BITMAP = RES_BASE+$100

harness_run
 mx %00
 lda #0
 ldx #0
:clr
 sta >RES_BASE,x
 inx
 inx
 cpx #$1000
 bcc :clr
 lda #$FFFF
 sta >RES_BASE+4
 stz vIDX
 stz vNRUN
 stz vNPASS
 lda #DATA_BASE
 sta pVEC
 lda #^DATA_BASE
 sta pVEC+2
:next_vec
 lda [pVEC]
 bne :have
 jmp :done
:have
 sta vRECLEN
 lda vIDX
 sta >MB_RUNIDX
* Registers, then FLAGS (flags_set), then the bases.
 ldy #2
 ldx #0
:regs
 lda [pVEC],y
 sta 0,x
 iny
 iny
 inx
 inx
 cpx #$1C
 bcc :regs
 lda rFL
 jsr flags_set
 jsr set_all_bases
 stz vBAD
 stz vHALT
 stz vSEGOVR
 stz vOVR
 stz vREP
* Initial RAM.
 ldy #60
 lda [pVEC],y
 sta vCOUNT
 ldy #64
:ram
 lda vCOUNT
 beq :ram_done
 dec vCOUNT
 lda [pVEC],y
 sta pDST
 iny
 iny
 lda [pVEC],y
 pha
 and #$000F
 ora #GUEST_BANK
 sta pDST+2
 pla
 xba
 sep #$20
 mx %10
 sta [pDST]
 rep #$20
 mx %00
 iny
 iny
 bra :ram
:ram_done
 sty vXRAMOFF
* One instruction.
 jsr run_one
* Registers: 13 words exact.
 stz vFAIL
 ldy #30
 ldx #0
:cmp
 lda [pVEC],y
 cmp 0,x
 beq :same
 inc vFAIL
:same
 iny
 iny
 inx
 inx
 cpx #$1A
 bcc :cmp
* FLAGS under the mask.
 jsr flags_get
 sta tmp6
 ldy #58
 lda [pVEC],y
 sta tmp7
 ldy #56
 lda [pVEC],y
 eor tmp6
 and tmp7
 beq :flags_ok
 inc vFAIL
:flags_ok
* Expected RAM.
 ldy #62
 lda [pVEC],y
 sta vCOUNT
 ldy vXRAMOFF
:xram
 lda vCOUNT
 beq :xram_done
 dec vCOUNT
 lda [pVEC],y
 sta pDST
 iny
 iny
 lda [pVEC],y
 sta tmp6                  ; bank in the low byte, expected in the high
 and #$000F
 ora #GUEST_BANK
 sta pDST+2
 iny
 iny
 lda [pDST]
 and #$00FF
 sta tmp5                  ; actual
 lda tmp6
 xba
 and #$00FF
 cmp tmp5
 beq :xram
 inc vFAIL
 lda >RES_BASE+4           ; the first failure's first RAM mismatch
 cmp #$FFFF
 bne :xram
 lda >RES_BASE+39
 bne :xram
 lda pDST
 sta >RES_BASE+36
 sep #$20
 mx %10
 lda pDST+2
 sta >RES_BASE+38
 lda tmp6+1
 sta >RES_BASE+39
 lda tmp5
 sta >RES_BASE+40
 rep #$20
 mx %00
 bra :xram
:xram_done
 lda vBAD
 beq :nobad
 inc vFAIL
 lda >RES_BASE+64
 inc
 sta >RES_BASE+64
:nobad
 lda vFAIL
 bne :failed
 inc vNPASS
 lda vIDX                  ; bitmap bit
 lsr
 lsr
 lsr
 tax
 lda vIDX
 and #7
 tay
 sep #$20
 mx %10
 lda bit_tab,y
 ora >RES_BITMAP,x
 sta >RES_BITMAP,x
 rep #$20
 mx %00
 bra :advance
:failed
 lda >RES_BASE+4
 cmp #$FFFF
 bne :advance
 lda vIDX
 sta >RES_BASE+4
 ldx #0
:copy
 lda 0,x
 sta >RES_BASE+8,x
 inx
 inx
 cpx #$1A
 bcc :copy
 jsr flags_get
 sta >RES_BASE+8+26
:advance
 inc vNRUN
 inc vIDX
 lda pVEC
 clc
 adc vRECLEN
 sta pVEC
 bcc :nocarry
 inc pVEC+2
:nocarry
 jmp :next_vec
:done
 lda vNRUN
 sta >RES_BASE
 lda vNPASS
 sta >RES_BASE+2
 cmp vNRUN
 beq :allpass
 lda #1
 rts
:allpass
 lda #0
 rts

bit_tab hex 0102040810204080
vIDX       dw 0              ; vector index
vRECLEN    dw 0              ; record length
vBAD       dw 0              ; unimplemented opcodes retired (op_bad)

* run_one - execute one instruction from the guest state;
* returns when it retires (prefixes and REP included).
run_one
 mx %00
 lda #step_done
 sta vNEXT
 sta vnext0
 sta vHALTVEC
 ldy rIP
 jmp fetch
step_done
 mx %00
 sty rIP
 stz vSEGOVR
 stz vOVR
 stz vREP
 rts
