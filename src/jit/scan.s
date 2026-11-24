*----------------------------------------------------------
* scan.s - what a loop is made of: the instructions from
* rIP in the order they lie (sc_scan), which of their jumps
* stay among them (sc_resolve), and the flags that are read
* after each (sc_live).
*
* An instruction is a line in the i_ tables (its number
* twice is the index). Its kind says what emit.s makes of
* it (gen/jtab.s, K_): K_EXIT is the interpreter's (its
* parameter says how the core goes on after it), K_STEP is
* one instruction of the interpreter's and back into the
* piece.
*----------------------------------------------------------
X_LABEL    = $01             ; i_x: a jump here comes to it
X_NEED     = $02             ; its flags are read later: the lazy ones are stored
X_FUSED    = $04             ; a Jcc on the native flags the instruction before left
X_INT      = $08             ; a jump to one of these instructions (i_tg is which, twice)
X_MEM      = $10             ; the operand is in memory
ALLF       = $003F

i_ip       ds MAXI*2+2       ; its IP (a prefix's, when it has one)
i_nx       ds MAXI*2+2       ; the next instruction's
i_k        ds MAXI*2         ; kind, parameter
i_fl       ds MAXI*2         ; the flags it sets, the flags it reads
i_x        ds MAXI*2         ; X_ bits, the segment base a prefix names (its direct-page offset; 0 none)
i_op       ds MAXI*2         ; opcode, ModR/M byte
i_tg       ds MAXI*2         ; a jump's target
i_na       ds MAXI*2         ; where its code is
i_li       ds MAXI*2         ; the flags read from it on, before they are set again

sc_n       dw 0              ; instructions, twice
sc_found   dw 0
sc_y       dw 0
sc_max     dw 0              ; the byte after the last of them all
sc_op      dw 0
sc_k       dw 0
sc_p       dw 0
sc_l       dw 0
sc_s       dw 0
sc_u       dw 0
sc_seg     dw 0
sc_mod     dw 0
sc_x       dw 0
sc_tg      dw 0
sc_t       dw 0
sc_t2      dw 0
sc_cb      dw 0              ; the code's host bank
sc_lo      dw 0              ; and its first byte and the one after its last, there
sc_hi      dw 0

* sc_scan - C set: the i_ tables hold a loop worth translating
sc_scan
 mx %00
 stz sc_n
 stz sc_max
 ldy rIP
:ins
 ldx sc_n
 cpx #MAXI*2
 bcc :room
 jmp :end
:room
 cpx #0
 beq :own
 tya                       ; an IP that has a piece already (for this CS): this one does not go
 clc                       ; into it, it goes on to it
 adc rCS
 asl
 jsr sc_head
 bcs :head
 tya
 clc
 adc rCS
 asl
 eor #$8000                ; (the address's second word of the map)
 jsr sc_head
 bcc :nohead
:head
 tya
 inc
 jsr sc_ahead              ; (and on at a place past it that a jump here goes to)
 bcc :toend
 jmp :ins
:toend
 jmp :end
:nohead
 ldx sc_n
:own
 tya
 sta i_ip,x
 stz sc_seg
:pfx
 lda [bCS],y
 iny
 and #$00FF
 sta sc_op
 tax
 lda oi_k,x
 and #$00FF
 sta sc_k
 lda oi_p,x
 and #$00FF
 sta sc_p
 lda oi_l,x
 and #$00FF
 sta sc_l
 lda oi_s,x
 and #$00FF
 sta sc_s
 lda oi_u,x
 and #$00FF
 sta sc_u
 lda sc_k
 cmp #K_SEG
 bne :nopfx
 lda sc_seg                ; (a second prefix: the interpreter's)
 beq :first
 stz sc_k                  ; (K_EXIT, plain)
 stz sc_p
 stz sc_l
 bra :nopfx
:first
 lda sc_p
 sta sc_seg
 bra :pfx
:nopfx
 stz sc_mod
 stz sc_x
 stz sc_tg
 lda sc_l
 and #L_MODRM
 bne :modrm
 jmp :nomod
:modrm
 lda [bCS],y
 iny
 and #$00FF
 sta sc_mod
 lda sc_k
 cmp #K_GRP
 bne :nogrp
 lda sc_mod                ; a group: the four by the byte's middle
 and #$0038
 lsr
 sta sc_t
 lda sc_p
 asl
 asl
 asl
 asl
 asl
 clc
 adc sc_t
 tax
 lda gr_tab,x
 and #$00FF
 sta sc_k
 lda gr_tab+1,x
 and #$00FF
 sta sc_p
 lda gr_tab+2,x
 and #$00FF
 sta sc_s
 lda gr_tab+3,x
 and #$00FF
 sta sc_u
:nogrp
 lda sc_mod
 and #$00C0
 cmp #$00C0
 beq :nomod                ; a register
 lda #X_MEM
 sta sc_x
 lda sc_mod
 and #$00C7
 cmp #$0006                ; mod 0, r/m 6: an address
 beq :d16
 and #$00C0
 beq :nomod
 cmp #$0040
 bne :d16
 iny
 bra :nomod
:d16
 iny
 iny
:nomod
 lda sc_l
 and #L_MOFFS
 beq :nomoffs
 iny
 iny
 lda #X_MEM
 sta sc_x
:nomoffs
 lda sc_l                  ; the immediate
 and #L_F6
 beq :imm
 lda sc_mod                ; (F6 and F7: only TEST has one, of the operand's size)
 and #$0030
 bne :immdone
 iny
 lda sc_op
 lsr
 bcc :immdone
 iny
 bra :immdone
:imm
 lda sc_l
 and #L_I8
 beq :ni8
 iny
:ni8
 lda sc_l
 and #L_I16
 beq :immdone
 iny
 iny
:immdone
 sty sc_y
 lda sc_k
 cmp #K_GEN
 beq :gen
 cmp #K_LEA
 beq :gen
 cmp #K_IND
 beq :gen
 cmp #K_JCC
 beq :rel8
 cmp #K_LOOP
 beq :rel8
 cmp #K_JCXZ
 beq :rel8
 cmp #K_JMP8
 beq :rel8
 cmp #K_CALL
 beq :rel16
 cmp #K_JMP16
 bne :store
:rel16
 dey                       ; a near jump or call: the 16 bits before the next instruction
 dey
 lda [bCS],y
 clc
 adc sc_y
 sta sc_tg
 bra :store
:rel8
 dey
 lda [bCS],y
 and #$00FF
 cmp #$0080
 bcc :pos
 ora #$FF00
:pos
 clc
 adc sc_y
 sta sc_tg
 bra :store
:gen                       ; is there a template for this form? (if not: the interpreter's, and back)
 lda sc_p
 asl
 sta sc_t
 asl
 asl
 clc
 adc sc_t                  ; * 10
 tax
 lda sc_x
 and #X_MEM
 beq :rr
 inx
 inx
 inx
 inx
:rr
 lda ts_tab+2,x
 beq :any                  ; (no template for this form)
 lda sc_x                  ; (back to the set's first line)
 and #X_MEM
 beq :rr2
 dex
 dex
 dex
 dex
:rr2
 lda ts_tab,x
 and #TS_SREG
 beq :store
 lda sc_mod                ; a segment register by the byte's middle: ES, SS and DS are
 and #$0038                ; loaded here, CS is not; and there are four
 cmp #$0020
 bcs :any
 cmp #$0008
 bne :store
 lda sc_p
 cmp #SET_MOV_SR
 bne :store
:any
 stz sc_k                  ; K_EXIT: the interpreter's instruction, and nothing trusted after it
 lda #5
 sta sc_p
 bra :st2
:store
 lda sc_k                  ; an instruction the interpreter does inside a piece must not
 cmp #K_STEP               ; be one that could write into the piece's own code
 bne :st2
 lda sc_p
 beq :st2
 lda sc_x
 and #X_MEM
 bne :any
:st2
 lda sc_op                 ; REP: by what it repeats. A MOVS or a STOS writes where DI says,
 cmp #$00F2                ; which the core looks at afterwards (8); the others write nothing (7)
 beq :rep
 cmp #$00F3
 bne :norep
:rep
 ldy sc_y
 lda [bCS],y
 and #$00E7                ; (a segment prefix between: 26 2E 36 3E)
 cmp #$0026
 bne :rop
 iny
:rop
 lda [bCS],y
 and #$00FF
 cmp #$00A4
 bcc :norep
 cmp #$00B0
 bcs :norep
 tax
 lda #7
 cpx #$00A6                ; A4 A5: MOVS
 bcc :wr
 cpx #$00AA                ; A6 A7: CMPS; A8 A9 are TEST's
 bcc :rd
 cpx #$00AC                ; AA AB: STOS
 bcs :rd
:wr
 lda #8
:rd
 cpx #$00A8
 beq :norep
 cpx #$00A9
 beq :norep
 sta sc_p
:norep
 ldx sc_n
 lda sc_k                  ; (what the interpreter takes from there on has no length
 cmp #K_EXIT               ; that matters here: its first byte is all that is looked at)
 bne :len
 lda i_ip,x
 inc
 sta sc_y
:len
 lda sc_y
 sta i_nx,x
 cmp sc_max
 bcc :nomax
 sta sc_max
:nomax
 lda sc_p
 xba
 ora sc_k
 sta i_k,x
 lda sc_u
 xba
 ora sc_s
 sta i_fl,x
 lda sc_seg
 xba
 ora sc_x
 sta i_x,x
 lda sc_mod
 xba
 ora sc_op
 sta i_op,x
 lda sc_tg
 sta i_tg,x
 lda #ALLF
 sta i_li,x
 inx
 inx
 stx sc_n
 ldx sc_k
 lda kt_tab,x
 and #$00FF
 bne :term
 ldy sc_y
 jmp :ins
:term                      ; nothing falls through: on at the nearest place ahead that a
 ldx sc_n                  ; jump here goes to, if there is one
 dex
 dex
 lda i_nx,x                ; (a target inside the last one is nobody's)
 jsr sc_ahead
 bcc :end
 jmp :ins
:end
 lda i_k                   ; the first one the interpreter's: nothing to translate, and
 and #$00FF                ; the map says how the core goes on from there
 bne :mine
 lda i_k+1                 ; (0: the interpreter's from there; 5 to 8: the instruction, then the
 and #$00FF                ; dispatcher again)
 clc
 rts
:mine
 lda bCS                   ; all of it in one host bank
 clc
 adc i_ip
 sta sc_lo
 lda #0
 rol
 sta sc_t
 lda sc_max
 beq :rej
 dec
 clc
 adc bCS
 inc
 beq :rej
 sta sc_hi
 lda sc_hi
 cmp sc_lo
 bcc :rej                  ; (the last byte is in the next bank)
 beq :rej
 lda bCS+2
 clc
 adc sc_t
 and #$000F
 ora #GUEST_BANK
 sta sc_cb
 sec
 rts
:rej
 lda #0
 clc
 rts

* sc_head - C set: the map's word at A is the stub of the piece for IP
* Y under this CS. Keeps Y.
sc_head
 mx %00
 tax
 lda >JIT_MAP,x
 cmp #$0100
 bcc :no
 tax
 tya
 cmp >JIT_RT+ST_IP+1,x
 bne :no
 lda rCS
 cmp >JIT_RT+ST_CS+1,x
 bne :no
 sec
 rts
:no
 clc
 rts

* sc_ahead - C set and Y = the lowest target of a jump among the
* instructions that is at A or past it, and no more than SC_NEAR bytes
* past it: a piece is code that lies together (what is between its
* parts is somebody else's, perhaps data)
SC_NEAR    = 48
sc_ahead
 mx %00
 stz sc_found
 sta sc_t
 clc
 adc #SC_NEAR
 bcc :lim
 lda #$FFFF
:lim
 sta sc_t2
 ldx #0
:l
 cpx sc_n
 bcs :done
 lda i_k,x
 and #$00FF
 cmp #K_JCC
 bcc :next
 cmp #K_JCXZ+1
 bcs :next
 lda i_tg,x
 cmp sc_t
 bcc :next
 cmp sc_t2
 beq :take
 bcs :next
:take
 sta sc_t2
 inc sc_found
:next
 inx
 inx
 bra :l
:done
 lda sc_t2
 ldx sc_found
 beq :none
 tay
 sec
 rts
:none
 clc
 rts

* sc_resolve - the jumps that go to one of the instructions (X_INT,
* and that one gets X_LABEL), and the Jccs that can branch on the
* native flags of the instruction before (X_FUSED)
sc_resolve
 mx %00
 ldx #0
:l
 cpx sc_n
 bcc :go
 jmp :fuse
:go
 lda i_k,x
 and #$00FF
 cmp #K_JCC
 bcc :next
 cmp #K_JCXZ+1
 bcs :next
 lda i_tg,x
 ldy #0
:find
 cpy sc_n
 bcs :next
 cmp i_ip,y
 beq :found
 iny
 iny
 bra :find
:found
 tya
 sta i_tg,x
 lda i_x,x
 ora #X_INT
 sta i_x,x
 lda i_x,y
 ora #X_LABEL
 sta i_x,y
:next
 inx
 inx
 bra :l
:fuse
 ldx #2
:f
 cpx sc_n
 bcc :f1
 rts
:f1
 lda i_x,x
 and #X_LABEL
 bne :fn
 lda i_k-2,x
 and #$00FF
 cmp #K_GEN
 bne :fn
 lda i_nx-2,x
 cmp i_ip,x
 bne :fn
 lda i_k,x
 and #$00FF
 cmp #K_JCC
 beq :fj
 cmp #K_GEN                ; an ADC, an SBB, an RCL or an RCR on a register takes CF
 bne :fn                   ; from the carry the instruction before left
 lda i_x,x
 and #X_MEM
 bne :fn
 jsr sc_setx
 lda ts_tab,y
 and #TS_CIN+TS_CINV
 beq :fn
 jsr sc_pclass
 cmp #1                    ; sub
 beq :fc
 cmp #2                    ; add
 beq :fc
 cmp #5                    ; a shift
 beq :fc
 cmp #6                    ; a rotate
 bne :fn
:fc
 lda i_x,x
 ora #X_FUSED
 sta i_x,x
 lda i_fl,x                ; (it reads CF from no lazy flag)
 and #$FEFF
 sta i_fl,x
 bra :fn
:fj
 jsr sc_fclass             ; A = the entry of jf_tab for this Jcc after that instruction
 beq :fn
 lda i_x,x
 ora #X_FUSED
 sta i_x,x
 lda i_fl,x                ; (it reads no lazy flag)
 and #$00FF
 sta i_fl,x
:fn
 inx
 inx
 jmp :f

* sc_setx - Y = the place in ts_tab of instruction X's set. Keeps X.
sc_setx
 mx %00
 lda i_k+1,x
 and #$00FF
 asl
 sta sc_t
 asl
 asl
 clc
 adc sc_t
 tay
 rts
* sc_pclass - A = the class of the native flags the instruction before
* X leaves (a K_GEN). Keeps X.
sc_pclass
 mx %00
 lda i_k-1,x
 and #$00FF
 asl
 sta sc_t
 asl
 asl
 clc
 adc sc_t
 tay
 lda ts_tab+1,y
 and #$00FF
 rts

* sc_fclass - instruction X is a Jcc and X-2 a K_GEN: A = jf_tab's
* entry for the two (0: none). Keeps X.
sc_fclass
 mx %00
 phx
 lda i_k-1,x               ; the set
 and #$00FF
 asl
 sta sc_t
 asl
 asl
 clc
 adc sc_t
 tay
 lda ts_tab+1,y
 and #$00FF
 beq :out
 dec
 asl
 asl
 asl
 asl
 sta sc_t
 lda i_k+1,x               ; the condition
 and #$00FF
 clc
 adc sc_t
 asl
 tay
 lda jf_tab,y
:out
 plx
 cmp #0
 rts

* sc_live - one pass from the last instruction to the first: the flags
* read from each on (i_li), and X_NEED where one that it sets is among
* those read after it. Outside the piece everything is read. Twice, so
* that a jump back finds what its target read the first time.
sc_live
 mx %00
 ldx sc_n
:l
 cpx #0
 bne :go
 rts
:go
 dex
 dex
 lda i_k,x
 and #$00FF
 sta sc_k
 cmp #K_STEP+1             ; (K_EXIT and K_STEP: the interpreter reads what it likes)
 bcs :ours
 lda #ALLF
 sta i_li,x
 bra :l
:ours
 lda #ALLF                 ; what is read after it when it falls through
 sta sc_t
 ldy sc_k
 lda kt_tab,y
 and #$00FF
 bne :fell                 ; (nothing falls through it: a call, a return)
 txa
 inc
 inc
 cmp sc_n
 bcs :fell
 lda i_nx,x
 cmp i_ip+2,x
 bne :fell
 lda i_li+2,x
 sta sc_t
:fell
 lda sc_k
 cmp #K_JCC
 bcc :set
 cmp #K_JCXZ+1
 bcs :set
 lda #ALLF                 ; a jump: what its target reads
 sta sc_t2
 lda i_x,x
 and #X_INT
 beq :ext
 ldy i_tg,x
 lda i_li,y
 sta sc_t2
:ext
 lda sc_k
 cmp #K_JMP8
 beq :only
 cmp #K_JMP16
 beq :only
 lda sc_t2
 tsb sc_t
 bra :set
:only
 lda sc_t2
 sta sc_t
:set
 lda i_x,x
 and #$FFFF-X_NEED
 sta i_x,x
 lda i_fl,x
 and #$00FF
 and sc_t
 beq :noneed
 lda i_x,x
 ora #X_NEED
 sta i_x,x
:noneed
 lda i_fl,x
 and #$00FF
 eor #$FFFF
 and sc_t
 sta sc_t
 lda i_fl,x
 xba
 and #$00FF
 ora sc_t
 sta i_li,x
 jmp :l
