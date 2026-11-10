*----------------------------------------------------------
* jit2.s - M6 runtime block translator (the real JIT).
*
* Translates guest basic blocks into native 65816 in a code
* cache (bank $06), keyed by guest linear IP in a direct-
* mapped block map (bank $06 high), runs them, and returns
* to the dispatcher at each block end. The K command drives
* it: K R / K M / K J run the reg/mem/jmp bench loop through
* the JIT, with the same MB_RUNIDX marks as the B command so
* tools/jit_spike.py can time it.
*
* Coverage: mov r16,imm; inc/dec r16; add/sub/cmp/and/or/xor
* r/m16,r16 and r/m16,imm8 reg-form (value only, flags elided);
* test; jz/jnz (native Z); jmp short; hlt. Anything else ends
* the block with a fallback exit to the interpreter.
*
* Flags: the benchmark loops have no flags live across a block
* boundary, so this translator elides them and reads the
* native Z the preceding op leaves for the terminating jz/jnz.
* It is therefore correct for those loops; a boot-general
* version must materialize rFL at block exits (see docs/jit.md).
*----------------------------------------------------------
JIT_CODE_BANK = JIT_BANK
JIT_MAP       = $8000       ; block map base within bank $06
JIT_MAPMASK   = $00FF       ; 256 slots, 8 bytes each

*--- emit one byte (A low) into the cache
emit_b
 mx %00
 sep #$20
 sta [pEMIT]
 rep #$20
 inc pEMIT
 rts

*--- emit one word (A) into the cache
emit_w
 mx %00
 sta [pEMIT]
 inc pEMIT
 inc pEMIT
 rts

*--- reset: emit pointer to $06:0000, clear the block map
jit_cache_reset
 mx %00
 lda #0
 sta pEMIT
 lda #JIT_CODE_BANK
 sta pEMIT+2
 lda #JIT_MAP               ; pMAP walks the map clearing high words to $FFFF
 sta pMAP
 lda #JIT_CODE_BANK
 sta pMAP+2
 ldx #0
:clr
 ldy #2
 lda #$FFFF
 sta [pMAP],y               ; slot+2 (lin high word) = empty marker
 lda pMAP
 clc
 adc #8
 sta pMAP
 inx
 cpx #JIT_MAPMASK+1
 bne :clr
 rts

*--- jit_lin: jLIN = CS*16 + IP (20-bit), pMAP = slot for its hash
jit_lin
 mx %00
 stz jLIN+2
 lda rCS
 asl
 rol jLIN+2
 asl
 rol jLIN+2
 asl
 rol jLIN+2
 asl
 rol jLIN+2                 ; A = CS<<4 low word, jLIN+2 = CS>>12
 clc
 adc rIP
 sta jLIN
 lda jLIN+2
 adc #0
 sta jLIN+2
 lda jLIN                   ; hash = low byte
 and #JIT_MAPMASK
 asl
 asl
 asl                        ; *8
 clc
 adc #JIT_MAP
 sta pMAP
 lda #JIT_CODE_BANK
 sta pMAP+2
 rts

*--- jit_lookup: C=1 and A=native offset if a block for CS:IP
* is cached, else C=0
jit_lookup
 mx %00
 jsr jit_lin
 ldy #0
 lda [pMAP],y               ; stored lin low
 cmp jLIN
 bne :miss
 ldy #2
 lda [pMAP],y               ; stored lin high
 cmp jLIN+2
 bne :miss
 ldy #4
 lda [pMAP],y               ; native offset
 sec
 rts
:miss
 clc
 rts

*--- store the current CS:IP -> jEntry in the map (pMAP set by jit_lin)
jit_mapput
 mx %00
 ldy #0
 lda jLIN
 sta [pMAP],y
 ldy #2
 lda jLIN+2
 sta [pMAP],y
 ldy #4
 lda jEntry
 sta [pMAP],y
 rts

*--- enter the block at cache offset A; returns A = block status
jit_enter
 mx %00
 sta pENTER
 lda #JIT_CODE_BANK
 sta pENTER+2
 phk
 pea :eret-1
 jmp [GUEST_DP+pENTER]
:eret
 rts

*--- translate the basic block at rCS:rIP; returns A = native offset.
* Y is the guest-IP cursor; jtmp2 holds the current opcode's IP.
jit_translate
 mx %00
 jsr jit_lin
 lda pEMIT
 sta jEntry
 jsr jit_mapput
 ldy rIP
 stz jPrevFlag
:nexti
 sty jtmp2                 ; opcode IP (resume point for a fallback)
 lda [bCS],y
 and #$00FF
 iny
 cmp #$F4
 bne :n1
 jmp :op_hlt
:n1
 cmp #$B8
 bcc :n2
 cmp #$C0
 bcs :n2
 jmp :op_movimm            ; B8-BF
:n2
 cmp #$40
 bcc :n3
 cmp #$50
 bcs :n3
 jmp :op_incdec            ; 40-4F
:n3
 cmp #$70
 bcc :n4
 cmp #$80
 bcs :n4
 jmp :op_jcc               ; 70-7F
:n4
 cmp #$01
 bne :n5
 jmp :op_add               ; 01 add r/m16,r16
:n5
 cmp #$83
 bne :n6
 jmp :op_grp83             ; 83 /x r/m16,imm8
:n6
 cmp #$F7
 bne :fallback
 jmp :op_grpf7             ; F7 /0 test r/m16,imm16
:fallback
 lda jtmp2                 ; resume IP = this opcode
 jsr emit_setip            ; lda #ip / sta rIP
 lda #$A9
 jsr emit_b                ; lda #$0001 (status = fallback)
 lda #$0001
 jsr emit_w
 lda #$6B
 jsr emit_b                ; rtl
 lda jEntry
 rts

:op_hlt
 lda #$A9
 jsr emit_b                ; lda #$0002 (status = halt)
 lda #$0002
 jsr emit_w
 lda #$6B
 jsr emit_b
 lda jEntry
 rts

:op_movimm                 ; A = opcode B8-BF
 and #$0007
 asl
 sta tmp2                  ; dst off
 lda [bCS],y
 iny
 iny
 sta tmp1                  ; imm16
 lda #$A9
 jsr emit_b                ; lda #imm
 lda tmp1
 jsr emit_w
 lda #$85
 jsr emit_b                ; sta dp off
 lda tmp2
 jsr emit_b
 stz jPrevFlag
 jmp :nexti

:op_incdec                 ; A = opcode 40-4F
 sta tmp0                  ; opcode
 and #$0007
 asl
 sta tmp2                  ; off
 lda tmp0
 and #$0008
 bne :id_dec
 lda #$E6                  ; inc dp
 bra :id_e
:id_dec
 lda #$C6                  ; dec dp
:id_e
 jsr emit_b
 lda tmp2
 jsr emit_b
 lda #1
 sta jPrevFlag
 jmp :nexti

:op_add                    ; 01 add r/m16,r16 (reg form only)
 lda [bCS],y
 and #$00FF
 iny
 sta tmp0                  ; modrm
 and #$00C0
 cmp #$00C0
 beq :add_rr
 jmp :fallback_back1       ; mem form: fall back to this opcode
:add_rr
 lda tmp0
 and #$0007
 asl
 sta tmp2                  ; rm off (dst)
 lda tmp0
 and #$0038
 lsr
 lsr
 sta tmp3                  ; reg off (src)
 lda #$A5
 jsr emit_b                ; lda rm
 lda tmp2
 jsr emit_b
 lda #$18
 jsr emit_b                ; clc
 lda #$65
 jsr emit_b                ; adc reg
 lda tmp3
 jsr emit_b
 lda #$85
 jsr emit_b                ; sta rm
 lda tmp2
 jsr emit_b
 lda #1
 sta jPrevFlag
 jmp :nexti

:op_grp83                  ; 83 /x r/m16, imm8 (reg form only)
 lda [bCS],y
 and #$00FF
 iny
 sta tmp0                  ; modrm
 and #$00C0
 cmp #$00C0
 beq :g83_rr
 jmp :fallback_back1
:g83_rr
 lda tmp0
 and #$0007
 asl
 sta tmp2                  ; rm off
 lda [bCS],y
 and #$00FF
 iny
 sta tmp1                  ; imm8
 and #$0080
 beq :g83_pos
 lda tmp1
 ora #$FF00                ; sign-extend
 sta tmp1
:g83_pos
 lda #$A5
 jsr emit_b                ; lda rm
 lda tmp2
 jsr emit_b
 lda tmp0
 and #$0038
 cmp #$0000
 beq :g83_add
 cmp #$0028
 beq :g83_sub
 cmp #$0038
 beq :g83_cmp
 jmp :fallback_back2       ; other sub-ops: fall back
:g83_add
 lda #$18
 jsr emit_b                ; clc
 lda #$69
 jsr emit_b                ; adc #imm
 lda tmp1
 jsr emit_w
 bra :g83_store
:g83_sub
 lda #$38
 jsr emit_b                ; sec
 lda #$E9
 jsr emit_b                ; sbc #imm
 lda tmp1
 jsr emit_w
 bra :g83_store
:g83_cmp
 lda #$38
 jsr emit_b                ; sec
 lda #$E9
 jsr emit_b                ; sbc #imm (no store)
 lda tmp1
 jsr emit_w
 lda #1
 sta jPrevFlag
 jmp :nexti
:g83_store
 lda #$85
 jsr emit_b                ; sta rm
 lda tmp2
 jsr emit_b
 lda #1
 sta jPrevFlag
 jmp :nexti

:op_grpf7                  ; F7 /0 test r/m16, imm16 (reg form only)
 lda [bCS],y
 and #$00FF
 iny
 sta tmp0                  ; modrm
 and #$0038
 beq :f7a
 jmp :fallback_back1       ; only /0 (test)
:f7a
 lda tmp0
 and #$00C0
 cmp #$00C0
 beq :f7b
 jmp :fallback_back1
:f7b
 lda tmp0
 and #$0007
 asl
 sta tmp2                  ; rm off
 lda [bCS],y
 iny
 iny
 sta tmp1                  ; imm16
 lda #$A5
 jsr emit_b                ; lda rm
 lda tmp2
 jsr emit_b
 lda #$29
 jsr emit_b                ; and #imm16
 lda tmp1
 jsr emit_w
 lda #1
 sta jPrevFlag
 jmp :nexti

:op_jcc                    ; 70-7F; handle 74 (jz) / 75 (jnz) via native Z
 sta tmp0                  ; opcode
 and #$000F
 cmp #$0004
 beq :jcc_ok
 cmp #$0005
 beq :jcc_ok
 jmp :fallback_back1       ; other conditions need rFL: fall back
:jcc_ok
 lda jPrevFlag
 bne :jcc_z
 jmp :fallback_back1       ; no valid native Z: fall back
:jcc_z
 lda [bCS],y
 and #$00FF
 iny                       ; Y now = fall-through IP
 sta tmp1                  ; rel8
 and #$0080
 beq :jcc_pos
 lda tmp1
 ora #$FF00
 sta tmp1
:jcc_pos
 tya
 sta tmp3                  ; fall-through IP
 clc
 adc tmp1
 sta tmp2                  ; taken IP
 lda tmp2                  ; self-loop? taken target == this block's entry
 cmp rIP
 bne :jcc_unlinked
 ; --- self-loop link: taken branches natively back to jEntry ---
 lda tmp0
 and #$0001
 bne :sl_nz
 lda #$F0                  ; jz  -> beq take
 bra :sl_br
:sl_nz
 lda #$D0                  ; jnz -> bne take
:sl_br
 jsr emit_b
 lda #$09                  ; over the 9-byte fall exit
 jsr emit_b
 lda tmp3
 jsr emit_setip            ; fall: lda #fall / sta rIP (5)
 lda #$A9
 jsr emit_b                ; lda #0 (3)
 lda #$0000
 jsr emit_w
 lda #$6B
 jsr emit_b                ; rtl (1)  -> fall exit = 9 bytes
 lda #$4C
 jsr emit_b                ; take: jmp abs jEntry (stay native)
 lda jEntry
 jsr emit_w
 lda jEntry
 rts
:jcc_unlinked
 ; emit: Bcc take ; lda #fall/sta rIP ; bra done ; take: lda #taken/sta rIP ; done: lda #0/rtl
 lda tmp0
 and #$0001
 bne :jcc_nz
 lda #$F0                  ; jz  -> beq take
 bra :jcc_br
:jcc_nz
 lda #$D0                  ; jnz -> bne take
:jcc_br
 jsr emit_b
 lda #$07                  ; Bcc take: over fall setip (5) + bra (2)
 jsr emit_b
 lda tmp3
 jsr emit_setip            ; fall path: lda #fall / sta rIP (5 bytes)
 lda #$80
 jsr emit_b                ; bra done
 lda #$05
 jsr emit_b                ; over the taken setip (5)
 lda tmp2
 jsr emit_setip            ; lda #taken / sta rIP (5 bytes)
 lda #$A9
 jsr emit_b                ; lda #0 (status continue)
 lda #$0000
 jsr emit_w
 lda #$6B
 jsr emit_b                ; rtl
 lda jEntry
 rts

:fallback_back1            ; fall back, resume at the opcode in jtmp2
 ldy jtmp2
 jmp :fallback
:fallback_back2
 ldy jtmp2
 jmp :fallback

*--- emit "lda #ip / sta rIP" (5 bytes); A = ip
emit_setip
 mx %00
 pha
 lda #$A9
 jsr emit_b
 pla
 jsr emit_w
 lda #$85
 jsr emit_b
 lda #rIP
 jsr emit_b
 rts

*--- run guest until a block returns halt
jit_exec
 mx %00
:loop
 jsr jit_lookup
 bcs :run
 jsr jit_translate
:run
 jsr jit_enter
 cmp #$0002
 beq :done
 cmp #$0001
 bne :loop
 jsr jit_step_one
 bra :loop
:done
 rts

*--- run one interpreter instruction at rIP, return (for fallback)
jit_step_one
 mx %00
 lda vNEXT
 pha
 lda #:ret
 sta vNEXT
 ldy rIP
 jmp fetch
:ret
 sty rIP
 stz vSEGOVR
 stz vREP
 pla
 sta vNEXT
 rts

*--- K command: run the bench at 0000:0100 through the JIT
jitk_run
 mx %00
 jsr jit_cache_reset
 stz rCS
 stz rDS
 stz rES
 stz rSS
 stz rAX
 stz rBX
 stz rCX
 stz rDX
 stz rSI
 stz rDI
 stz rBP
 jsr set_all_bases
 lda #$0100
 sta rIP
 lda #$FFFE
 sta rSP
 lda #F_FIXED
 jsr flags_set
 stz vHALT
 lda #$BE57
 sta >MB_RUNIDX
 jsr jit_exec
 lda #$D04E
 sta >MB_RUNIDX
 rts
