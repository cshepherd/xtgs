*----------------------------------------------------------
* emit.s - a scanned loop into code: em_region. Each
* instruction is one or more templates of gen/jtab.s
* stamped into the cache (stamp), the places for its
* operands filled from sl_val by the template's own list.
*
* The code's conventions: the guest's registers in the
* direct page, 16-bit index registers, X, Y and A free. The
* accumulator is 16 bits wide at the piece's top, at every
* place a jump comes to and at every way out; t_w is what
* it is at the place being stamped, and stamp changes it
* (SEP, REP) when a template is for the other width.
*
* A piece in the cache: its record (the epoch it last
* compared its bytes in, its entry, the guest bytes it was
* made from; em_ver), its stub with the entries for links
* before it and inside it (em_stub), the code.
*----------------------------------------------------------
SL_R       = 1               ; the slots (tools/gen_jit.py, SLOTS)
SL_M       = 2
SL_I8      = 3
SL_I16     = 4
SL_D16     = 5
SL_S0      = 6
SL_S2      = 7
SL_IPC     = 8
SL_IPN     = 9
SL_CB      = 10
SL_T16     = 11
SL_SR      = 12
SL_CB2     = 13
SL_EAR     = 14

sl_val     ds 32             ; a word for each slot
t_w        dw 0              ; the accumulator's width in the code so far: 0 sixteen bits, 1 eight
em_i       dw 0              ; the instruction, twice
em_entry   dw 0              ; the piece's stub
em_desc    dw 0              ; its record
em_nr      dw 0              ; runs of bytes in it
em_wr      dw 0              ; em_eat: 3 for a write
em_nost    dw 0              ; em_eo: the offset is the instruction's own 16 bits, and no code is wanted for it
em_op      dw 0
em_mod     dw 0
em_l       dw 0
em_set     dw 0              ; the set's place in ts_tab
em_fl      dw 0              ; its flags
em_mem     dw 0
em_t       dw 0
em_t2      dw 0
em_sk      dw 0              ; a jump's template: where its last byte is
fx_n       dw 0              ; jumps ahead: where the address goes, and which instruction's it is
fx_at      ds MAXI*2
fx_ix      ds MAXI*2
st_p       dw 0
st_len     dw 0
st_nf      dw 0
st_dst     dw 0
st_f       dw 0
st_at      dw 0
st_s       dw 0
st_v       dw 0
r8off      dfb 0,2,4,6,1,3,5,7   ; AL CL DL BL AH CH DH BH in the direct page

em_b                       ; a byte (A) into the cache (the bank being filled: jit.s, ce_b)
 mx %00
 ldx c_ptr
 jsr ce_b
 inx
 stx c_ptr
 rts
em_w                       ; a word
 mx %00
 ldx c_ptr
 jsr ce_w
 inx
 inx
 stx c_ptr
 rts

em_w16                     ; the accumulator 16 bits wide from here
 mx %00
 lda t_w
 beq :is
 stz t_w
 lda #$20C2                ; rep #$20
 jmp em_w
:is
 rts
em_w8
 mx %00
 lda t_w
 bne :is
 inc t_w
 lda #$20E2                ; sep #$20
 jmp em_w
:is
 rts

* stamp - template A into the cache, its fixups applied
stamp
 mx %00
 dec
 asl
 tax
 lda tp_tab,x
 sta st_p
 tax
 lda >JIT_BASE+2,x
 and #$00FF
 beq :w16
 jsr em_w8
 bra :wok
:w16
 jsr em_w16
:wok
 ldx st_p
 lda >JIT_BASE,x
 and #$00FF
 sta st_len
 lda >JIT_BASE+1,x
 and #$00FF
 sta st_nf
 lda c_ptr
 sta st_dst
 lda st_len
 beq :copied
 lda st_p
 clc
 adc #3
 tax
 ldy c_ptr
 lda c_bk
 bne :second
 lda st_len
 dec
 mvn JIT_BASE,JIT_RT
 bra :moved
:second
 lda st_len
 dec
 mvn JIT_BASE,JIT_RT2
:moved
 phk                       ; (the move left the cache's bank the data bank)
 plb
 sty c_ptr
:copied
 lda st_p
 clc
 adc #3
 adc st_len
 sta st_f
:fx
 lda st_nf
 bne :one
 rts
:one
 ldx st_f
 lda >JIT_BASE,x
 and #$00FF
 clc
 adc st_dst
 sta st_at
 lda >JIT_BASE+1,x
 and #$00FF
 sta st_s
 asl
 tax
 lda sl_val,x
 sta st_v
 ldx st_s
 lda sl_size,x
 and #$00FF
 cmp #2
 beq :two
 ldx st_at
 lda st_v
 jsr ce_b
 bra :nx
:two
 ldx st_at
 lda st_v
 jsr ce_w
:nx
 inc st_f
 inc st_f
 dec st_nf
 bra :fx

* em_region - the piece the i_ tables hold. C set: its stub is at
* em_entry. C clear: the cache has no room for it.
em_region
 mx %00
 stz t_w
 stz fx_n
 jsr em_ver
 jsr em_stub
 stz em_i
:ins
 ldx em_i
 cpx sc_n
 bcs :fix
 lda c_ptr
 cmp #CACHE_END-$0200
 bcc :room
 clc
 rts
:room
 lda i_x,x
 and #X_LABEL
 beq :nl
 jsr em_w16
 ldx em_i
:nl
 lda c_ptr
 sta i_na,x
 lda i_ip,x
 sta sl_val+SL_IPC+SL_IPC
 lda i_nx,x
 sta sl_val+SL_IPN+SL_IPN
 lda i_op,x
 and #$00FF
 sta em_op
 lda i_op+1,x
 and #$00FF
 sta em_mod
 lda i_k,x
 and #$00FF
 asl
 tax
 jsr (em_kind,x)
 ldx em_i                  ; where it goes on is not the next one here (the last, or one before
 lda i_k,x                 ; an IP that has a piece already): on at that IP, wherever its code is
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
 jsr em_out
:next
 inc em_i
 inc em_i
 bra :ins
:fix                       ; the jumps ahead get their addresses
 ldy #0
:f
 cpy fx_n
 bcs :done
 ldx fx_ix,y
 lda i_na,x
 ldx fx_at,y
 jsr ce_w
 iny
 iny
 bra :f
:done
 sec
 rts
em_kind da em_exit,em_step,em_gen,em_jcc,em_jmp,em_jmp,em_loop,em_jcxz,em_str,em_exit,em_exit,em_one,em_lea
 da em_call,em_ret,em_gen

* em_out - on at IP A, wherever its code is: the dispatcher's work the
* first time, a jump from then on (a link; back from here, the guard
* counts it)
em_out
 mx %00
 sta sl_val+SL_T16+SL_T16
 ldx em_i
 cmp i_ip,x
 beq :back
 bcc :back
 lda #TP_LINKF
 jmp stamp
:back
 lda #TP_LINKB
 jmp stamp
em_exit                    ; the interpreter's instruction: its parameter is how the core goes on
 mx %00
 ldx em_i
 lda i_k+1,x
 and #$00FF
 bne :n
 lda #TP_X0
 jmp stamp
:n
 clc
 adc #TP_X5-5
 jmp stamp
em_step                    ; the interpreter's, this one instruction, and back here (jitc.s)
 mx %00
 jsr em_w16
 lda c_ptr                 ; where the piece goes on: after the template
 clc
 adc #TP_STEP_LEN
 sta sl_val+SL_T16+SL_T16
 lda #TP_STEP
 jmp stamp
em_call                    ; CALL: the return address pushed, then on at the target
 mx %00
 lda #TP_CALL
 jsr stamp
 ldx em_i
 lda i_tg,x
 jmp em_out
em_ret                     ; RET, RET n, RETF: the parameter's template
 mx %00
 ldx em_op
 lda oi_l,x
 and #$00FF
 sta em_l
 stz em_fl
 jsr em_imm
 ldx em_i
 lda i_k+1,x
 and #$00FF
 asl
 tax
 lda one_tab,x
 jmp stamp

* em_ver - the piece's record: the epoch it last compared its bytes in
* (none yet), its entry, the guest code's bank, and each run of
* instructions that lie one after the other: where it is in the bank,
* how many words, the words (h_verify).
em_ver
 mx %00
 lda c_ptr
 sta em_desc
 lda #$FFFF
 jsr em_w
 lda e_n
 asl
 jsr em_w
 lda sc_cb
 jsr em_w
 lda #0
 jsr em_w                  ; (the runs: counted below)
 stz em_nr
 ldx #0
:run
 cpx sc_n
 bcs :runs
 lda i_ip,x
 sta em_t                  ; the run's first byte
:ext
 lda i_nx,x
 sta em_t2                 ; and the byte after its last, so far
 inx
 inx
 cpx sc_n
 bcs :cmp
 cmp i_ip,x
 beq :ext
:cmp
 phx
 jsr em_same
 plx
 bra :run
:runs
 ldx #0                    ; and the stretches its ways out were looked ahead at (scan.s: sc_look)
:la
 cpx la_n
 bcs :lad
 lda la_s,x
 sta em_t
 lda la_e,x
 sta em_t2
 phx
 jsr em_same
 plx
 inx
 inx
 bra :la
:lad
 lda em_desc
 clc
 adc #6
 tax
 lda em_nr
 jmp ce_w

* em_stub - the piece's entries. For a link back: the guard, and on
* into the one for a link ahead. For the dispatcher, Y the IP: is this
* the piece for that IP (two share a word of the map) and this CS? For
* a link ahead, and all of them: has it compared its bytes in this
* epoch?
em_stub
 mx %00
 lda c_ptr                 ; (the stub, seven bytes on, less one is to be even: the map's word for it has
 lsr                       ; the bank of code in bit 0)
 bcc :even
 lda #$00EA
 jsr em_b
:even
 lda #$C8C6                ; dec jG
 jsr em_w
 lda #$0FD0                ; bne (the link ahead's)
 jsr em_w
 lda #$004C                ; jmp h_gx
 jsr em_b
 lda #h_gx
 jsr em_w
 lda c_ptr
 sta em_entry
 lda #$00C0                ; cpy #ip
 jsr em_b
 lda rIP
 jsr em_w
 lda #$17D0                ; bne miss
 jsr em_w
 lda #$12A5                ; lda rCS
 jsr em_w
 lda #$00C9                ; cmp #cs
 jsr em_b
 lda rCS
 jsr em_w
 lda #$10D0                ; bne miss
 jsr em_w
 lda #$CAA5                ; lda jEP           (a link ahead comes in here)
 jsr em_w
 lda #$00CF                ; cmp >its epoch
 jsr em_b
 lda em_desc
 jsr em_w
 lda c_bk
 beq :first
 lda #^JIT_RT2
 bra :bank
:first
 lda #^jt_cache
:bank
 jsr em_b
 lda #$0BF0                ; beq body
 jsr em_w
 lda #$00A2                ; ldx #its record
 jsr em_b
 lda em_desc
 jsr em_w
 lda #$0020                ; jsr h_verify
 jsr em_b
 lda #h_verify
 jsr em_w
 lda #$0380                ; bra body
 jsr em_w
 lda #$004C                ; miss: jmp h_miss
 jsr em_b
 lda #h_miss
 jmp em_w
 err rCS-$12               ; (the bytes above)
 err jEP-$CA
 err jG-$C8

* em_same - the run of guest bytes from em_t up to em_t2 into the
* record: as words, the last word over the one before when the count is
* odd, a lone byte with the byte after it
em_same
 mx %00
 lda em_t2
 sec
 sbc em_t
 lsr
 sta em_t3                 ; whole words
 php
 beq :none
 lda em_t
 ldx em_t3
 jsr :put
:none
 plp
 bcc :out                  ; (even)
 lda em_t3
 beq :lone
 lda em_t2                 ; the word that ends with the last byte
 dec
 dec
 ldx #1
 bra :put
:lone
 lda em_t
 ldx #1
:put                       ; X words from IP A
 stx em_t4
 pha
 clc
 adc bCS
 pha
 jsr em_w
 lda em_t4
 jsr em_w
 lda em_t4                 ; (and its sixteens are code's: cl_map)
 asl
 clc
 adc 1,s
 tax
 pla
 jsr cl_mark
 ply
:w
 lda [bCS],y
 phy
 jsr em_w
 ply
 iny
 iny
 dec em_t4
 bne :w
 inc em_nr
:out
 rts
em_t3      dw 0
em_t4      dw 0

* em_reg - A = a register's number: its place in the direct page, by
* the set's width
em_reg
 mx %00
 and #$0007
 tax
 lda em_fl
 and #TS_W8
 bne :b
 txa
 asl
 rts
:b
 lda r8off,x
 and #$00FF
 rts

* em_gen - an instruction with a template set: its operands into the
* slots, the memory operand's pointer first when it has one, then the
* template for its form, with the flags when they are read later
em_gen
 mx %00
 ldx em_i
 lda i_k+1,x
 and #$00FF
 asl
 sta em_t
 asl
 asl
 clc
 adc em_t
 sta em_set
 tax
 lda ts_tab,x
 and #$00FF
 sta em_fl
 ldx em_op
 lda oi_l,x
 and #$00FF
 sta em_l
 ldx em_i
 lda i_x,x
 and #X_MEM
 sta em_mem
 lda em_l
 and #L_MODRM
 beq :noreg
 lda em_mod
 lsr
 lsr
 lsr
 jsr em_reg
 sta sl_val+SL_R+SL_R
 lda em_mod
 jsr em_reg
 sta sl_val+SL_M+SL_M
 bra :ops
:noreg
 stz sl_val+SL_R+SL_R      ; (AL or AX, for the forms with an address or no ModR/M byte)
 stz sl_val+SL_M+SL_M
 lda em_l
 and #L_REGOP
 beq :ops
 lda em_op
 jsr em_reg
 sta sl_val+SL_M+SL_M
:ops
 jsr em_imm
 lda em_mem
 beq :reg
 lda em_fl                 ; an operand that is only read: fetched, and then the register form's
 and #TS_MEMW+TS_FAR       ; template with the fetched value for its r/m
 bne :ptr
 ldx em_set
 lda ts_tab+2,x
 beq :ptr
 jsr em_fetch
 lda #jT
 sta sl_val+SL_M+SL_M
 stz em_mem
 bra :reg
:ptr
 jsr em_ea
 lda em_fl                 ; CF for an ADC and its like, from the lazy flags
 and #TS_CIN+TS_CINV
 beq :tmpl
 cmp #TS_CIN
 beq :cin
:cinv
 lda #TP_CINV
 jsr stamp
 bra :tmpl
:cin
 lda #TP_CIN
 jsr stamp
 bra :tmpl
:reg
 lda em_fl
 and #TS_CIN+TS_CINV
 beq :tmpl
 ldx em_i
 lda i_x,x
 and #X_FUSED
 bne :fused
 lda em_fl
 and #TS_CIN
 bne :cin
 bra :cinv
:fused                     ; the carry is the instruction before's: the right way up?
 jsr sc_pclass
 cmp #1
 beq :psub
 lda em_fl                 ; (that one left CF)
 and #TS_CINV
 beq :tmpl
 bra :flip
:psub                      ; (that one left CF inverted)
 lda em_fl
 and #TS_CIN
 beq :tmpl
:flip
 lda #TP_CFLIP
 jsr stamp
:tmpl
 stz em_ss
 lda em_fl
 and #TS_SREG
 beq :nosr
 lda em_mod                ; the segment register the byte's middle names
 and #$0018
 lsr
 lsr
 sta em_t
 cmp #4                    ; (SS: the stack's remembered range is asked about again after it, sp_sync)
 bne :nss
 inc em_ss
:nss
 clc
 adc #rES
 sta sl_val+SL_SR+SL_SR
 lda em_t
 asl
 clc
 adc #bES
 sta sl_val+SL_S0+SL_S0
 inc
 inc
 sta sl_val+SL_S2+SL_S2
:nosr
 ldx em_set
 lda em_mem
 beq :rr
 inx
 inx
 inx
 inx
:rr
 ldy em_i
 lda i_x,y
 and #X_NEED
 beq :plain
 inx
 inx
:plain
 lda ts_tab+2,x
 jsr stamp
 lda em_ss
 beq :done
 lda #TP_SPSYNC
 jsr stamp
:done
 rts
em_ss      dw 0

* em_imm - the instruction's immediate into the slots (I8 and I16; an
* 8-bit one sign-extended for the 16 when the opcode says)
em_imm
 mx %00
 ldx em_i
 ldy i_nx,x
 lda em_l
 and #L_F6
 beq :plain
 lda em_mod
 and #$0030
 bne :none
 lda em_fl
 and #TS_W8
 bne :i8
 bra :i16
:plain
 lda em_l
 and #L_I16
 bne :i16
 lda em_l
 and #L_I8
 beq :none
:i8
 dey
 lda [bCS],y
 and #$00FF
 sta sl_val+SL_I8+SL_I8
 sta sl_val+SL_I16+SL_I16
 lda em_l
 and #L_SX
 beq :none
 lda sl_val+SL_I16+SL_I16
 cmp #$0080
 bcc :none
 ora #$FF00
 sta sl_val+SL_I16+SL_I16
:none
 rts
:i16
 dey
 dey
 lda [bCS],y
 sta sl_val+SL_I16+SL_I16
 sta sl_val+SL_I8+SL_I8
 rts

* em_eo - the offset of the instruction's memory operand, in A when
* the code runs; em_t = the segment base it is from by default
em_eo
 mx %00
 ldx em_i
 lda i_x+1,x               ; a prefix: the opcode is a byte on
 and #$00FF
 beq :np
 lda #1
:np
 clc
 adc i_ip,x
 inc                       ; past the opcode
 tay
 lda em_l
 and #L_MOFFS
 bne :d16
 iny                       ; and the ModR/M byte
 lda em_mod
 and #$00C7
 cmp #$0006
 beq :d16
 lda em_mod
 and #$0007
 tax
 lda ea_seg,x
 and #$00FF
 sta em_t
 lda em_mod
 and #$00C0
 beq :tp
 cmp #$0040
 beq :d8
 lda [bCS],y
 bra :disp
:d8
 lda [bCS],y
 and #$00FF
 cmp #$0080
 bcc :disp
 ora #$FF00
:disp
 sta sl_val+SL_D16+SL_D16
 txa
 clc
 adc #8
 tax
:tp
 txa
 asl
 tax
 lda eo_tab,x
 jmp stamp
:d16
 lda [bCS],y
 sta sl_val+SL_D16+SL_D16
 lda #bDS
 sta em_t
 lda em_nost
 bne :nost
 lda eo_tab+12
 jmp stamp
:nost
 rts

* em_seg - the slots for the segment: the prefix's, or A
em_seg
 mx %00
 sta em_t
 ldx em_i
 lda i_x+1,x
 and #$00FF
 bne :have
 lda em_t
:have
 sta sl_val+SL_S0+SL_S0
 inc
 inc
 sta sl_val+SL_S2+SL_S2
 rts

* em_fetch - the instruction's memory operand, which it only reads,
* into jT (gen_jit.py, fetch): the offset, the segment's base as the
* pointer when it is low enough, the pointer routine when it is not
em_fetch
 mx %00
 stz em_nost
 lda em_l
 and #L_MOFFS
 bne :own
 lda em_mod
 and #$00C7
 cmp #$0006
 bne :gen
:own
 inc em_nost
:gen
 jsr em_eo
 stz em_wr                 ; the routine for the segment and the size
 ldx em_i
 lda i_x+1,x
 and #$00FF
 bne :seg
 lda em_t
:seg
 pha
 jsr em_eai
 sta sl_val+SL_EAR+SL_EAR
 pla
 sta sl_val+SL_S0+SL_S0
 inc
 inc
 sta sl_val+SL_S2+SL_S2
 lda em_fl
 and #TS_W8
 bne :byte
 lda em_nost
 beq :w
 lda sl_val+SL_D16+SL_D16
 cmp #$FFFF
 bne :wd
 lda eo_tab+12             ; (a word at FFFFh: the offset in A after all, for the template that looks)
 jsr stamp
:w
 stz em_nost
 lda #TP_FETCH_W
 jmp stamp
:wd
 stz em_nost
 lda #TP_FETCH_WD
 jmp stamp
:byte
 lda em_nost
 stz em_nost
 beq :b
 lda #TP_FETCH_BD
 jmp stamp
:b
 lda #TP_FETCH_B
 jmp stamp

* em_ea - the pointer to the instruction's memory operand (pEA): Y
* the IP for whoever has to give up, the offset, and the run-time
* bank's routine for the segment and what is done there (gen/jrt.s)
em_ea
 mx %00
 jsr em_eo
 lda #TP_EA_Y
 jsr stamp
 stz em_wr
 lda em_fl
 and #TS_MEMW
 beq :rd
 lda #3
 sta em_wr
:rd
 ldx em_i                  ; the segment: the prefix's, or the form's own
 lda i_x+1,x
 and #$00FF
 bne em_eat
 lda em_t
* em_eat - JSR to the pointer routine: A = the segment base's place in
* the direct page, em_wr 0 a read or 3 a write, em_fl the size
em_eat
 mx %00
 jsr em_eai
 pha
 lda #$0020
 jsr em_b
 pla
 jmp em_w
* em_eai - A = that routine's address
em_eai
 mx %00
 sec
 sbc #bES                  ; 0, 4, 8, 12
 lsr
 sta em_t
 asl
 clc
 adc em_t                  ; * 6
 clc
 adc em_wr
 sta em_t
 lda em_fl
 and #TS_FAR
 beq :nf
 inc em_t
 inc em_t
 bra :go
:nf
 lda em_fl
 and #TS_WORDMEM
 beq :go
 inc em_t
:go
 lda em_t
 asl
 tax
 lda ea_rt,x
 rts

* em_lea - LEA: the offset, into the register
em_lea
 mx %00
 ldx em_i
 lda i_k+1,x
 and #$00FF
 asl
 sta em_t
 asl
 asl
 clc
 adc em_t
 sta em_set
 tax
 lda ts_tab,x
 and #$00FF
 sta em_fl
 lda #L_MODRM
 sta em_l
 lda em_mod
 lsr
 lsr
 lsr
 jsr em_reg
 sta sl_val+SL_R+SL_R
 jsr em_eo
 ldx em_set
 lda ts_tab+6,x
 jmp stamp

* em_one - an instruction that is one template (the parameter; 0: NOP)
em_one
 mx %00
 lda em_op
 and #$0007
 asl
 sta sl_val+SL_M+SL_M
 ldx em_i
 lda i_k+1,x
 and #$00FF
 asl
 tax
 lda one_tab,x
 bne :t
 rts
:t
 jmp stamp

* em_str - MOVS, STOS, LODS alone (the parameter: 0 MOVSB, 1 MOVSW,
* 2 STOSB, 3 STOSW, 4 LODSB, 5 LODSW)
em_str
 mx %00
 ldx em_i
 lda i_k+1,x
 and #$00FF
 sta em_set                ; (which)
 lsr
 lda #0
 bcc :b
 lda #TS_WORDMEM
:b
 sta em_fl
 lda em_set
 cmp #2
 bcc :src
 cmp #4
 bcc :dst
:src                       ; the source: (the prefix's segment or DS):SI
 lda eo_tab+8
 jsr stamp
 lda #TP_EA_Y
 jsr stamp
 stz em_wr
 ldx em_i
 lda i_x+1,x
 and #$00FF
 bne :sseg
 lda #bDS
:sseg
 jsr em_eat
 lda em_set
 and #$0001
 sta em_t
 lda em_set
 cmp #4
 bcs :lods
 lda #TP_MOVS_LD_B
 clc
 adc em_t
 jsr stamp
 bra :dst
:lods
 lda #TP_LODS_B
 clc
 adc em_t
 jsr stamp
 bra :adv
:dst                       ; the destination: ES:DI
 lda eo_tab+10
 jsr stamp
 lda #TP_EA_Y
 jsr stamp
 lda #3
 sta em_wr
 lda #bES
 jsr em_eat
 lda em_set
 and #$0001
 sta em_t
 lda em_set
 cmp #2
 bcs :stos
 lda #TP_MOVS_ST_B
 clc
 adc em_t
 jsr stamp
 bra :adv
:stos
 lda #TP_STOS_B
 clc
 adc em_t
 jsr stamp
:adv                       ; SI and DI on
 lda em_set
 and #$0001
 sta em_t
 lda em_set
 cmp #2
 bcc :si
 cmp #4
 bcc :di
:si
 lda #TP_ADV_SI1
 clc
 adc em_t
 jsr stamp
 lda em_set
 cmp #4
 bcs :done
:di
 lda #TP_ADV_DI1
 clc
 adc em_t
 jsr stamp
:done
 rts

* em_jcc, em_loop, em_jcxz - a jump that may not be taken: the
* template that goes round the code for "taken", then that code, then
* the template's last byte, which is how far round
em_loop
 mx %00
 lda #TP_LOOP
 bra em_cond
em_jcxz
 mx %00
 lda #TP_JCXZ
 bra em_cond
em_jcc
 mx %00
 ldx em_i
 lda i_x,x
 and #X_FUSED
 beq :lazy
 jsr sc_fclass
 cmp #JF_NEVER
 bne :nn
 rts
:nn
 cmp #JF_ALWAYS
 bne em_cond
 jmp em_jmp
:lazy
 lda i_k+1,x
 and #$00FF
 asl
 tax
 lda jg_tab,x
em_cond
 mx %00
 jsr stamp
 lda c_ptr
 dec
 sta em_sk
 jsr em_jmp
 lda c_ptr
 sec
 sbc em_sk
 dec
 ldx em_sk
 jsr ce_b
 rts

* em_jmp - to the instruction's target: one of the loop's own (back:
* the guard counts it; ahead: the address comes later), or a way out
em_jmp
 mx %00
 jsr em_w16
 ldx em_i
 lda i_x,x
 and #X_INT
 bne :int
 lda i_tg,x
 jmp em_out
:int
 lda i_tg,x
 cmp em_i
 beq :back
 bcs :ahead
:back
 tax
 lda i_ip,x
 sta sl_val+SL_T16+SL_T16
 lda #TP_GUARD
 jsr stamp
 ldx em_i
 lda i_tg,x
 tax
 lda i_na,x
 sta sl_val+SL_T16+SL_T16
 lda #TP_JMP
 jmp stamp
:ahead
 ldy fx_n
 sta fx_ix,y
 lda c_ptr
 inc
 sta fx_at,y
 iny
 iny
 sty fx_n
 lda #TP_JMP
 jmp stamp
