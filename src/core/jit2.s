*----------------------------------------------------------
* jit2.s - M6 runtime block translator (the real JIT).
*
* Translates guest basic blocks into native 65816 in a code
* cache (the JIT's bank), keyed by guest linear IP in a
* direct-mapped block map (the bank's upper half), and runs
* them. The K command drives it on BENCH at 0000:0100, with
* the same MB_RUNIDX marks as the B command, so
* tools/jit_bench.py can time it against the interpreter.
* Its letter is the mode (jit_mode):
*
*   K U   0  unlinked: every block returns to the dispatcher
*   K S   1  a block's branch to its own entry stays native
*            (the first M6's link)
*   K L   2  every direct edge linked (M6.1, docs/jit.md)
*   K G   3  the same with the guard: X counts the backward
*            edges down and the block returns at 0 (K alone)
*   K C   4  U translating again at every dispatch, which
*            is how a translation's cost is measured
*
* Coverage: mov r16,imm16; inc/dec r16; add r/m16,r16 and
* add/sub/cmp r/m16,imm8 in their register forms (value only,
* flags elided); test r16,imm16; jz/jnz (native Z); hlt.
* Anything else ends the block with a fallback exit, and the
* dispatcher has the interpreter run that one instruction.
*
* A linked block (modes 2 and 3). A conditional jump whose
* target has a native entry branches to it, by a short branch
* when it reaches and by an inverted branch over a JMP when
* not. One whose target has none goes through a site, a JMP
* to its own exit stub, and the stub returns the address of
* the JMP's operand: the dispatcher translates the target,
* stores its entry there (jit_exec) and that edge is native
* from then on. After a conditional jump the translation goes
* on at the fall-through, which gets its own map entry, so the
* jump not taken costs a branch and nothing more. Every entry
* has one contract: the guest's registers in the direct page,
* nothing in A, Y or the native flags, X the guard's count.
* So any edge may go to any entry.
*
* The guard. Linked blocks never come back by themselves, and
* the interpreter's slot (interrupts, the frame's work) has to
* be met. A loop has a backward edge, so in mode 3 each of
* those counts X down and returns to the dispatcher at 0,
* status 3, with rIP the target. JIT_GUARD_N of them go by
* between two returns. K has no slot to run; the cost of the
* count is what it shows.
*
* Benchmark-only, still: flags. The loops have no flags live
* across a block boundary, so the translator elides them and
* reads the native Z the preceding op leaves for the jz/jnz.
* Nothing is given to the interpreter's lazy flags at an exit.
* It is correct for these loops and for no other code; M6.4
* of XTGS-M6-JIT-Revisited.md is what general code needs.
*----------------------------------------------------------
JIT_CODE_BANK = JIT_BANK
J2_MAP       = $8000       ; block map base within the bank
J2_MAPMASK   = $00FF       ; 256 slots, 8 bytes each
JIT_START     = $0010       ; the cache's first byte: a site's address is never a status
JIT_FULL      = $7800       ; a translation that begins beyond this resets the cache
JIT_RGMAX     = $0400       ; and one this long is cut, with a site for the rest
JIT_GUARD_N   = 64          ; mode 3: backward edges between two returns

jit_mode   dw 0             ; the K command's letter as a number
jit_guard  dw JIT_GUARD_N   ; X at every entry
jit_gen    dw 0             ; counts the cache's resets: a site from before one is gone
jit_gen0   dw 0
jit_site   dw 0             ; the site an exit named
jit_xs     dw 0             ; emit_xlink's own
jit_nt     dw 0             ; a jump target's native entry
jit_stats                   ; u32 each, for tools/jit_bench.py
jit_ndisp  adrl 0           ; entries to the dispatcher
jit_nxlat  adrl 0           ; translations
jit_nlink  adrl 0           ; sites patched
jit_nbyte  adrl 0           ; bytes emitted
jit_nrst   adrl 0           ; cache resets

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

*--- reset: the emit pointer to the cache's start, the block map empty
jit_cache_reset
 mx %00
 inc jit_gen
 inc jit_nrst
 bne :n
 inc jit_nrst+2
:n
 lda #JIT_START
 sta pEMIT
 lda #JIT_CODE_BANK
 sta pEMIT+2
 lda #J2_MAP               ; pMAP walks the map clearing high words to $FFFF
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
 cpx #J2_MAPMASK+1
 bne :clr
 rts

*--- jit_lin: jLIN = CS*16 + IP (20-bit), pMAP = slot for its hash.
* jit_lin_a: the same for the IP in A. (X and Y kept.)
jit_lin
 mx %00
 lda rIP
jit_lin_a
 mx %00
 sta jtmp
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
 adc jtmp
 sta jLIN
 lda jLIN+2
 adc #0
 sta jLIN+2
 lda jLIN                   ; hash = low byte
 and #J2_MAPMASK
 asl
 asl
 asl                        ; *8
 clc
 adc #J2_MAP
 sta pMAP
 lda #JIT_CODE_BANK
 sta pMAP+2
 rts

*--- jit_lookup: C=1 and A=native offset if a block for CS:IP
* is cached, else C=0. jit_find: the same for the IP in A, Y kept.
jit_find
 mx %00
 phy
 jsr jit_lin_a
 jsr jit_look2
 ply
 rts
jit_lookup
 mx %00
 jsr jit_lin
jit_look2
 mx %00
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

*--- store jLIN -> the emit pointer in the map (pMAP set by jit_lin). Y kept.
jit_mapput
 mx %00
 phy
 ldy #0
 lda jLIN
 sta [pMAP],y
 ldy #2
 lda jLIN+2
 sta [pMAP],y
 ldy #4
 lda pEMIT
 sta [pMAP],y
 ply
 rts

*--- enter the block at cache offset A; returns A = block status:
* 0 go on at rIP, 1 the interpreter's instruction at rIP, 2 halt,
* 3 the guard ran out (go on at rIP), JIT_START and up the site to link
jit_enter
 mx %00
 sta pENTER
 lda #JIT_CODE_BANK
 sta pENTER+2
 ldx jit_guard
 phk
 pea :eret-1
 jmp [GUEST_DP+pENTER]
:eret
 rts

*--- translate the basic block at rCS:rIP; returns A = native offset.
* Y is the guest-IP cursor; jtmp2 holds the current opcode's IP.
jit_translate
 mx %00
 lda pEMIT
 cmp #JIT_FULL
 bcc :room
 jsr jit_cache_reset
:room
 inc jit_nxlat
 bne :nx
 inc jit_nxlat+2
:nx
 jsr jit_lin
 lda pEMIT
 sta jEntry
 jsr jit_mapput
 ldy rIP
 stz jPrevFlag
:nexti
 sty jtmp2                 ; opcode IP (resume point for a fallback)
 lda pEMIT                 ; long enough: the rest is another translation's
 sec
 sbc jEntry
 cmp #JIT_RGMAX
 bcc :fits
 tya
 jsr emit_xlink
 jmp :xdone
:fits
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
:xdone                     ; the translation ends: A = its entry
 lda pEMIT
 sec
 sbc jEntry
 clc
 adc jit_nbyte
 sta jit_nbyte
 bcc :xd
 inc jit_nbyte+2
:xd
 lda jEntry
 rts

:op_hlt
 lda #$A9
 jsr emit_b                ; lda #$0002 (status = halt)
 lda #$0002
 jsr emit_w
 lda #$6B
 jsr emit_b
 jmp :xdone

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
 lda jit_mode
 cmp #2
 bcc :jcc_old
 cmp #4
 bcs :jcc_old
 jmp :jcc_link
:jcc_old
 lda jit_mode              ; mode 0 and 4: no link at all
 cmp #1
 bne :jcc_unlinked
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
 jmp :xdone
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
 jmp :xdone

*  The linked forms (modes 2 and 3). tmp0 the opcode, tmp2 the taken
*  IP, tmp3 the fall-through's (= Y), jtmp2 the opcode's own.
*  tmp1 becomes the inverted branch, tmp4 1 when the guard counts
*  this edge (mode 3 and the target not ahead).
:jcc_link
 lda #$D0                  ; jz: not taken is bne
 sta tmp1
 lda tmp0
 lsr
 bcc :jl_inv
 lda #$F0                  ; jnz: not taken is beq
 sta tmp1
:jl_inv
 stz tmp4
 lda jit_mode
 cmp #3
 bne :jl_g
 lda jtmp2
 cmp tmp2
 bcc :jl_g                 ; the target is ahead of the jump
 inc tmp4
:jl_g
 lda tmp2
 jsr jit_find
 bcs :jl_hit
 jmp :jl_miss
:jl_hit
 sta jit_nt
 lda tmp4
 bne :jl_hitg
*  target translated, no guard:  Bcc nt  |  Bcc' +3 / jmp nt
 lda pEMIT
 jsr jit_near
 bcs :jl_far
 pha
 lda tmp1
 eor #$20                  ; the branch itself (BNE $D0 <-> BEQ $F0)
 jsr emit_b
 pla
 jsr emit_b
 jmp :jl_fall
:jl_far
 lda tmp1
 jsr emit_b
 lda #3
 jsr emit_b
 lda #$4C
 jsr emit_b
 lda jit_nt
 jsr emit_w
 jmp :jl_fall
*  target translated, guard:  Bcc' cont / dex / bne nt / stub3
*                         |  Bcc' cont / dex / beq +3 / jmp nt / stub3
:jl_hitg
 lda pEMIT
 clc
 adc #3                    ; where the BNE would be
 jsr jit_near
 bcs :jl_gfar
 pha
 lda tmp1
 jsr emit_b
 lda #12                   ; dex 1, bne 2, stub 9
 jsr emit_b
 lda #$CA
 jsr emit_b                ; dex
 lda #$D0
 jsr emit_b                ; bne nt
 pla
 jsr emit_b
 bra :jl_stub3
:jl_gfar
 lda tmp1
 jsr emit_b
 lda #15                   ; dex 1, beq 2, jmp 3, stub 9
 jsr emit_b
 lda #$CA
 jsr emit_b                ; dex
 lda #$F0
 jsr emit_b                ; beq the stub
 lda #3
 jsr emit_b
 lda #$4C
 jsr emit_b
 lda jit_nt
 jsr emit_w
:jl_stub3
 lda tmp2
 jsr emit_setip            ; the guard ran out: rIP the target, status 3
 lda #$A9
 jsr emit_b
 lda #$0003
 jsr emit_w
 lda #$6B
 jsr emit_b
 bra :jl_fall
*  target not translated:  Bcc' cont / [dex / beq +3] / site
:jl_miss
 lda tmp1
 jsr emit_b
 lda tmp4
 bne :jl_mg
 lda #12                   ; the site and its stub
 jsr emit_b
 bra :jl_site
:jl_mg
 lda #15
 jsr emit_b
 lda #$CA
 jsr emit_b                ; dex
 lda #$F0
 jsr emit_b                ; beq the site's stub
 lda #3
 jsr emit_b
:jl_site
 lda tmp2
 jsr emit_xlink
*  the fall-through: here, unless it has an entry already
:jl_fall
 lda tmp3
 jsr jit_find
 bcc :jl_new
 sta jit_nt
 lda #$4C
 jsr emit_b                ; jmp its entry
 lda jit_nt
 jsr emit_w
 jmp :xdone
:jl_new
 jsr jit_mapput            ; (jit_find left jLIN and pMAP the fall-through's)
 stz jPrevFlag             ; an entry: nothing in the native flags
 jmp :nexti

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

*--- emit a site for the guest IP in A: "jmp stub / stub: lda #ip /
* sta rIP / lda #site / rtl" (12 bytes), the site the address of the
* JMP's operand, which jit_exec makes the target's entry
emit_xlink
 mx %00
 pha
 lda #$4C
 jsr emit_b
 lda pEMIT
 sta jit_xs
 clc
 adc #2
 jsr emit_w                ; the stub is the next thing
 pla
 jsr emit_setip
 lda #$A9
 jsr emit_b
 lda jit_xs
 jsr emit_w
 lda #$6B
 jsr emit_b
 rts

*--- can a branch at cache offset A reach jit_nt? C clear and A the
* displacement byte, or C set
jit_near
 mx %00
 clc
 adc #2
 eor #$FFFF
 sec
 adc jit_nt                ; jit_nt - (A + 2)
 pha
 clc
 adc #$0080
 cmp #$0100
 pla
 and #$00FF
 rts

*--- run guest until a block returns halt
jit_exec
 mx %00
:loop
 inc jit_ndisp
 bne :d1
 inc jit_ndisp+2
:d1
 lda jit_mode
 cmp #4
 beq :always
 jsr jit_lookup
 bcs :run
:always
 jsr jit_translate
:run
 jsr jit_enter
 cmp #JIT_START
 bcs :link
 cmp #$0002
 beq :done
 cmp #$0001
 bne :loop
 jsr jit_step_one
 bra :loop
:done
 rts
:link                      ; an exit through a site: A = the address to patch
 sta jit_site
 lda jit_mode
 cmp #2
 bcc :loop                 ; (a cut block in the unlinked modes)
 cmp #4
 bcs :loop
 inc jit_ndisp
 bne :d2
 inc jit_ndisp+2
:d2
 lda jit_gen
 sta jit_gen0
 jsr jit_lookup
 bcs :have
 jsr jit_translate
:have
 pha
 lda jit_gen               ; the cache was reset meanwhile: the site is gone
 cmp jit_gen0
 bne :gone
 lda jit_site
 sta pENTER
 lda #JIT_CODE_BANK
 sta pENTER+2
 lda 1,s
 sta [pENTER]
 inc jit_nlink
 bne :gone
 inc jit_nlink+2
:gone
 pla
 bra :run

*--- run one interpreter instruction at rIP, return (for fallback)
jit_step_one
 mx %00
 lda vNEXT
 pha
 lda vnext0
 pha
 lda #:ret
 sta vNEXT
 sta vnext0
 ldy rIP
 jmp fetch
:ret
 sty rIP
 stz vSEGOVR
 stz vOVR
 stz vREP
 pla
 sta vnext0
 pla
 sta vNEXT
 rts

*--- K command: run the bench at 0000:0100 through the JIT
jitk_run
 mx %00
 ldx #18
:z
 stz jit_stats,x
 dex
 dex
 bpl :z
 stz jit_gen
 lda >MB_CMD+3             ; the K command's letter
 and #$00FF
 ldx #0
 cmp #'U'
 beq :m
 inx
 cmp #'S'
 beq :m
 inx
 cmp #'L'
 beq :m
 ldx #4
 cmp #'C'
 beq :m
 ldx #3                    ; G, or none
:m
 stx jit_mode
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
