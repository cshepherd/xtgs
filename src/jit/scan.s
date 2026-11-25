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
sc_bc      dw 0              ; the carry from its IPs into that bank (0 or 1)

* What the code a piece goes on to does with the flags (sc_ways, sc_look): for a jump or a call out of
* the piece, and for where a piece goes on at an address that is not its next instruction, the flags that
* are read from there on before they are written. sc_live takes that in place of "all of them", and an
* instruction whose flags nobody reads stores none. What was looked at is the piece's as much as its own
* code is: the stretches (la_s, la_e) are runs of its record (em_ver), their sixteens and pages are
* marked, and a store into one kills the piece. smc0 asks of a piece where its bytes are by bounds, and
* bounds that take in what lies between a piece and a far place it looked at would make all of that the
* piece's (pages of data and code, pieces killed for nothing: it was tried). So a stretch must fit one of
* three: the piece's own bounds when it is within SC_NEAR bytes of its code, or one of two more (bx_lo,
* bx_hi; e_xlo and e_ylo) that hold what lies within 64 bytes; a look whose stretch fits none has learned
* nothing.
LA_N       = 10              ; instructions a look may take
LA_R       = 8               ; stretches kept for a piece
i_la       ds MAXI*2         ; an instruction's: the flags read where its jump or its call goes,
i_lf       ds MAXI*2         ; and where it goes on, when that is not the next of these
la_s       ds LA_R*2         ; a stretch looked at: its first IP,
la_e       ds LA_R*2         ; and the IP after its last
la_n       dw 0              ; how many, twice
la_n0      dw 0
la_ip      dw 0
la_st      dw 0              ; where the stretch in hand begins
la_live    dw 0              ; the flags found read
la_pend    dw 0              ; the flags not written yet
la_left    dw 0
la_x       dw 0
la_t       dw 0
la_t2      dw 0
la_lo      dw 0              ; the stretch in hand in the piece's bank: its first byte, the byte after its last
la_hi      dw 0
bx_lo      ds 6              ; the three bounds: the piece's own code's (as sc_scan left them, and wider by what
bx_hi      ds 6              ; is near), and two for what is far (0: nothing in it)
bs_lo      ds 6              ; (as they were when a look began)
bs_hi      ds 6
sc_lo0     dw 0              ; the piece's own code's, as sc_scan left them
sc_hi0     dw 0

* sc_dec - the instruction at IP Y, by the tables: sc_op its opcode,
* sc_seg the base a prefix names, sc_k and sc_p its kind and parameter
* (a group's by the ModR/M byte's middle), sc_l what follows the
* opcode, sc_s and sc_u the flags it sets and reads, sc_mod, sc_x
* (X_MEM), sc_y the IP after it, sc_tg where a near jump or call goes.
sc_dec
 mx %00
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
 beq :rel16
 rts
:rel16
 dey                       ; a near jump or call: the 16 bits before the next instruction
 dey
 lda [bCS],y
 clc
 adc sc_y
 sta sc_tg
 rts
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
 rts

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
 jsr sc_dec
 lda sc_k
 cmp #K_GEN
 beq :gen
 cmp #K_LEA
 beq :gen
 cmp #K_IND
 beq :gen
 jmp :store
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
 sta sc_bc
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
 pha                       ; (the stub less one, and in bit 0 which bank of code: jit.s, c_get)
 and #$0001
 sta c_rb
 pla
 and #$FFFE
 clc
 adc #ST_IP+1
 tax
 jsr c_get
 sta sc_hw
 tya
 cmp sc_hw
 bne :no
 txa
 clc
 adc #ST_CS-ST_IP
 tax
 jsr c_get
 cmp rCS
 bne :no
 sec
 rts
:no
 clc
 rts
sc_hw      dw 0

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

* sc_ways - before sc_live: for every way out of the piece that goes
* to a known address, the flags read there (i_la, i_lf; all of them
* where nothing is known), and the stretches of code that says so.
sc_ways
 mx %00
 stz la_n
 lda sc_lo
 sta sc_lo0
 sta bx_lo
 lda sc_hi
 sta sc_hi0
 sta bx_hi
 stz bx_lo+2
 stz bx_hi+2
 stz bx_lo+4
 stz bx_hi+4
 ldx #0
:l
 cpx sc_n
 bcc :go
 lda bx_lo                 ; (the piece's bounds with what was looked at near it)
 sta sc_lo
 lda bx_hi
 sta sc_hi
 rts
:go
 stx la_x
 lda #ALLF
 sta i_la,x
 sta i_lf,x
 lda i_k,x
 and #$00FF
 cmp #K_STEP+1
 bcc :next                 ; (the interpreter's: it stores what it sets)
 cmp #K_CALL
 beq :tg
 cmp #K_JCC
 bcc :fall
 cmp #K_JCXZ+1
 bcs :fall
 lda i_x,x                 ; a jump: out of the piece?
 and #X_INT
 bne :fall
:tg
 lda i_tg,x
 jsr sc_look
 ldx la_x
 sta i_la,x
:fall                      ; does it go on, and not at the next of these?
 lda i_k,x
 and #$00FF
 tay
 lda kt_tab,y
 and #$00FF
 bne :next
 txa
 inc
 inc
 cmp sc_n
 bcs :off
 lda i_nx,x
 cmp i_ip+2,x
 beq :next
:off
 lda i_nx,x
 jsr sc_look
 ldx la_x
 sta i_lf,x
:next
 ldx la_x
 inx
 inx
 jmp :l

* sc_look - A = an IP under this CS: the flags that are read from
* there on before they are written (A; ALLF: not known), by the first
* LA_N instructions at most, through a jump or into a call, as far as
* a conditional jump, a return, or an instruction of the interpreter's.
* The bytes that were looked at are kept in la_s and la_e when that is
* less than all the flags, and only bytes of the piece's own bank on
* pages that may be code.
sc_look
 mx %00
 sta la_ip
 sta la_st
 lda la_n
 sta la_n0
 ldx #4
:sv
 lda bx_lo,x
 sta bs_lo,x
 lda bx_hi,x
 sta bs_hi,x
 dex
 dex
 bpl :sv
 stz la_live
 lda #ALLF
 sta la_pend
 lda #LA_N
 sta la_left
 bra :ins
:allj
 jmp :all
:ins
 lda la_ip                 ; (sixteen bytes clear of the segment's end and of the bank's: an instruction
 cmp #$FFF0                ; is all in one place)
 bcs :allj
 clc
 adc bCS
 tax
 lda #0
 rol
 cmp sc_bc
 bne :allj                  ; (another bank than the piece's)
 cpx #$FFF0
 bcs :allj
 txa
 xba
 and #$00FF
 sta la_t
 lda sc_cb
 and #$000F
 xba
 ora la_t
 tax
 lda pg_map,x
 and #$00FF
 cmp #4
 beq :allj                  ; (a page that is never code: stores there are not looked at)
 ldy la_ip
 jsr sc_dec
 lda sc_k
 cmp #K_STEP+1
 bcc :allj                  ; the interpreter's: it reads what it likes
 cmp #K_RET
 bcs :allj                  ; a return, a jump through a register: who knows where
 cmp #K_JCC
 beq :allj                  ; a conditional jump: two ways on
 cmp #K_LOOP
 beq :allj
 cmp #K_JCXZ
 beq :allj
 lda sc_u
 and la_pend
 tsb la_live
 lda sc_s
 eor #$FFFF
 and la_pend
 sta la_pend
 beq :close                ; every flag written: what follows is nothing to this
 lda sc_k
 cmp #K_JMP8
 beq :on
 cmp #K_JMP16
 beq :on
 cmp #K_CALL
 beq :on
 lda sc_y
 sta la_ip
 bra :cnt
:on                        ; on where it goes: this stretch ends, another begins
 lda sc_y
 jsr :keep
 bcs :fail
 lda sc_tg
 sta la_ip
 sta la_st
:cnt
 dec la_left
 beq :all
 jmp :ins
:all                       ; what is not written yet counts as read; the bytes so far are what said so
 lda la_pend
 tsb la_live
 lda la_ip
 bra :end
:close
 lda sc_y
:end
 jsr :keep
 bcs :fail
 lda la_live
 cmp #ALLF
 beq :fail                 ; (nothing learned: nothing kept)
 rts
:fail
 lda la_n0
 sta la_n
 ldx #4
:rs
 lda bs_lo,x
 sta bx_lo,x
 lda bs_hi,x
 sta bx_hi,x
 dex
 dex
 bpl :rs
 lda #ALLF
 rts
:keep                      ; the stretch from la_st up to A. C set: no room for it
 cmp la_st
 bne :some
:kept0                     ; (nothing in it, or it is kept already)
 clc
 rts
:some
 sta la_t
 ldx #0
:dup
 cpx la_n
 bcs :new
 lda la_s,x
 cmp la_st
 bne :dn
 lda la_e,x
 cmp la_t
 beq :kept0
:dn
 inx
 inx
 bra :dup
:new
 cpx #LA_R*2
 bcs :full
 lda la_st                 ; where it is in the bank
 clc
 adc bCS
 sta la_lo
 lda la_t
 clc
 adc bCS
 sta la_hi
 lda la_lo                 ; within SC_NEAR bytes of the piece's own code: inside its bounds
 clc
 adc #SC_NEAR
 bcs :b0lo
 cmp sc_lo0
 bcc :far
:b0lo
 lda sc_hi0
 clc
 adc #SC_NEAR
 bcs :b0
 cmp la_hi
 bcc :far
:b0
 ldy #0
 bra :join
:far
 ldy #2
:box
 lda bx_hi,y
 beq :take                 ; (nothing in this one yet)
 lda la_lo                 ; with what is in it: no more than 64 bytes from end to end?
 cmp bx_lo,y
 bcc :l1
 lda bx_lo,y
:l1
 sta la_t2
 lda la_hi
 cmp bx_hi,y
 bcs :h1
 lda bx_hi,y
:h1
 sec
 sbc la_t2
 cmp #65
 bcc :join
 iny
 iny
 cpy #6
 bcc :box
:full
 sec
 rts
:take
 lda la_lo
 sta bx_lo,y
 lda la_hi
 sta bx_hi,y
 bra :add
:join
 lda la_lo
 cmp bx_lo,y
 bcs :j1
 sta bx_lo,y
:j1
 lda la_hi
 cmp bx_hi,y
 bcc :add
 sta bx_hi,y
:add
 ldx la_n
 lda la_st
 sta la_s,x
 lda la_t
 sta la_e,x
 inx
 inx
 stx la_n
:kept
 clc
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
 lda #ALLF                 ; what is read after it
 sta sc_t
 ldy sc_k
 lda kt_tab,y
 and #$00FF
 beq :thru
 lda sc_k                  ; (nothing falls through it; a call: what the routine reads)
 cmp #K_CALL
 bne :fell
 lda i_la,x
 sta sc_t
 bra :fell
:thru
 lda i_lf,x                ; when it goes on outside the piece: what was seen there
 sta sc_t
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
 lda i_la,x                ; a jump: what its target reads
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
