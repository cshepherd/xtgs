*----------------------------------------------------------
* JIT - the translator (docs/jit.md, "M6.3"). Three banks,
* the JIT region: this image (the translator proper and its
* tables), a bank of run-time routines and the code it
* makes (JIT_RT; jt_cache to that bank's end), and a bank
* with a word for a guest address (JIT_MAP: the word at
* (IP + CS) * 2, and when that one is another address's
* piece, the word 8000h from it). The image holds the run-time routines too,
* assembled for their bank: jt_init moves them there.
*
* What is translated is a piece of code from an IP that
* was come to often enough: the instructions from there in
* the order they lie, with the jumps among them (scan.s),
* each as the template of its form (emit.s, gen/jtab.s from
* tools/gen_jit.py). The guest's registers stay in the
* direct page, where the interpreter has them.
*
* A piece ends where its code goes somewhere else: a jump
* out, a call, a return, an IP that has a piece already.
* From there the dispatcher (h_disp, jt_look) looks the IP
* up in the map and goes to that piece's code when there
* is one, so a program's hot paths run from piece to piece
* without the interpreter; where the IP is in the code (a
* jump, a call, falling off the end) the place that asked
* is made a jump straight to the piece once the map has it
* (h_linkf, h_linkb). An instruction that has no template
* is done by the interpreter, one instruction, and the
* dispatcher is asked again (jitc.s). An IP with no code
* counts, is translated when it has been asked for sixteen
* times, and until then the interpreter goes on from it.
*
* Code that was written over. Every piece has the guest
* bytes it was made from and compares them (h_verify) on
* entry whenever the epoch (jEP) is not the one it last
* compared in; the epoch goes on each time something that
* is not translated code has run and may have written
* memory anywhere (the interpreter on its own, a hypercall,
* a REP MOVS; not an instruction that writes the stack at
* most, a far call or an INT, when the stack is not on a
* page of code). Translated code's own stores are looked at as
* they are made: one onto a page that translated code was
* made from (pg_map) is held against every piece (smc0),
* and the pieces it lands in are dead; into the running
* piece, the piece ends before the store. A store on a page
* of code but in no sixteen bytes that code was made from
* (cl_map) is let by. Sixteen bytes that hold code and take
* such stores again and again without one landing in the
* code make their page one of data and code together: its
* code is the interpreter's from then on, and stores to it
* are looked at no more. A
* dead piece's entries are made jumps to the dispatcher, so
* whatever was linked to it asks the map again.
*
* Entry from the core: JSL JIT_BASE (a PC starts) and JSL
* JIT_RT + 3*n, native mode, 16-bit M/X, D = GUEST_DP, DBR
* the core's. In translated code: the same, X and Y free,
* the accumulator's width what the emitter last set. What a
* run comes back with is in jitc.s (jit_ret).
*----------------------------------------------------------
 typ $06
 dsk jit
 put ../include/layout.s
 org JIT_BASE
 mx %00

 put ../include/hw.s
 put ../include/mailbox.s
 put ../include/guest.s
 put ../include/pc.s

 jmp jt_init               ; +0  a PC starts: the map and the cache empty (JSL)
 da pg_map                 ; +3  where pg_map is, for the 8087's stores (src/fpu: fp_put)

MAXI       = 48              ; instructions a piece may have
MAXE       = 500             ; pieces translated at a time
CACHE_END  = $FF00
ROOM       = $1000           ; a translation begins with this much of the cache left, or all is thrown away
BAILS      = 16              ; times a piece may meet memory it cannot write (the EGA's planes) before it is given up
M_STEP     = $00FB           ; the map, from here up: the instruction there is the interpreter's and then the
*                            ; dispatcher's again; $103 less the word is how (8, 7, 6, 5: jitc.s)
M_NEVER    = $00FF           ; nothing is to be translated there
*                            ; below those a count (the low five bits; bit 4: now) and the lives used above it;
*                            ; $0100 and over: the piece's stub, less one
ST_LB      = 7               ; a piece's stub: the entry for a link back is this far before it,
ST_LF      = 12              ; the entry for a link ahead this far in,
ST_IP      = 1               ; the IP it is for here,
ST_CS      = 8               ; and the CS

jt_stats                     ; (tools read these: u16 each)
jt_ntr     dw 0              ; pieces translated
jt_nrej    dw 0              ; refused
jt_nflush  dw 0              ; times everything was thrown away
jt_nstale  dw 0              ; pieces whose code had changed
jt_nbump   dw 0              ; stores onto a page of code that landed in none
jt_ngive   dw 0              ; pieces given up for the memory they wrote
jt_nmiss   dw 0              ; times both of the map's words were other addresses'
jt_nmix    dw 0              ; pages found to be data and code
jt_nep     dw 0              ; times the epoch went on: the interpreter came back at a jump back,
jt_nver    dw 0              ; times a piece compared its bytes
jt_nep2    dw 0              ; ... an instruction it did may have written anywhere,
jt_nep3    dw 0              ; ... one wrote the stack, on a page of code,
jt_nep4    dw 0              ; ... a REP MOVS or STOS wrote a page of code
jt_ndisp   dw 0              ; times the dispatcher was asked by the core

jt_dbgi    dw 0              ; (a look at the misses: the last 64, IP and CS)
jt_dbg     ds 256
jt_besi    dw 0              ; (and at the stores beside code: the last 48, where to, the bank, the piece's entry)
jt_bes     ds 288
jt_reji    dw 0              ; (and at what was refused: the last 64, IP, CS, why: 1 the scan, 2 a page of data
jt_rej     ds 384            ; and code, 3 no room, 4 the address used its lives, 5 its page became one of data and code)
c_ptr      dw 0              ; where the next byte of code goes
e_n        dw 0              ; entries in use
e_n2       dw 0              ; (twice: the tables' index past the last)
e_slot     ds MAXE*2         ; an entry: the piece's word of the map (its place there),
e_nat      ds MAXE*2         ; its stub less one (0: dead),
e_desc     ds MAXE*2         ; its record in the cache (the epoch it last compared in, its bytes),
e_end      ds MAXE*2         ; the byte after its code there,
e_lo       ds MAXE*2         ; its guest code in its host bank: first byte,
e_hi       ds MAXE*2         ; byte after the last,
e_xlo      ds MAXE*2         ; and the same of what its ways out were looked ahead at, far from its code: two
e_xhi      ds MAXE*2         ; places of 64 bytes at most (0 and 0: none; scan.s: bx_lo)
e_ylo      ds MAXE*2
e_yhi      ds MAXE*2
e_bank     ds MAXE*2         ; the bank,
e_cb       ds MAXE*2         ; which bank of code it is in (0: JIT_RT's, 1: JIT_RT2's),
e_life     ds MAXE*2         ; the lives its IP had used when it was made,
e_bail     ds MAXE*2         ; times it gave up at memory it cannot write
bk_code    ds 32             ; a word for each bank of the guest's: translated code was made from bytes there
c_bk       dw 0              ; the bank of code being filled: 0 JIT_RT's, 1 JIT_RT2's
c_lim      dw CACHE_END-ROOM ; where the first is full (a test sets it low: tools/jit_fuzz.py --small)
c_rb       dw 0              ; c_get's and c_set's bank
wh_b       dw 0              ; which's
tr_w       dw 0              ; jt_tr0: the map's word for the IP
tr_ret     dw 0
lk_ofs     dw 0              ; a link's: how far into the stub its way in is

* c_get, c_set, c_setb - the cache at X, in the bank c_rb names: A = the word there; the word A to there;
* A's low byte to there. ce_w, ce_b - the same two in the bank being filled (c_bk). Keep X and Y.
c_get
 mx %00
 lda c_rb
 bne :b
 lda >JIT_RT,x
 rts
:b
 lda >JIT_RT2,x
 rts
ce_w
 mx %00
 pha
 lda c_bk
 bra c_s1
c_set
 mx %00
 pha
 lda c_rb
c_s1
 mx %00
 bne :b
 pla
 sta >JIT_RT,x
 rts
:b
 pla
 sta >JIT_RT2,x
 rts
ce_b
 mx %00
 pha
 lda c_bk
 bra c_s2
c_setb
 mx %00
 pha
 lda c_rb
c_s2
 mx %00
 bne :b
 pla
 sep #$20
 mx %10
 sta >JIT_RT,x
 rep #$20
 mx %00
 rts
:b
 mx %00
 pla
 sep #$20
 mx %10
 sta >JIT_RT2,x
 rep #$20
 mx %00
 rts
tr_x       dw 0
tr_s       dw 0              ; and where that word is (the dispatcher says: the address's first word, or its second)

jt_init
 mx %00
 phb
 phk
 plb
 ldx #rt_image             ; the run-time routines to their bank, and to the second bank of code, where
 ldy #rt_start             ; the copy is told that it is the second (rt_flag) and which the other is
 lda #rt_end-rt_start-1
 mvn JIT_BASE,JIT_RT
 ldx #rt_image
 ldy #rt_start
 lda #rt_end-rt_start-1
 mvn JIT_BASE,JIT_RT2
 phk
 plb
 lda #1
 sta >rt_flag+$20000
 lda >rt_me+2
 sta >rt_ot+2+$20000
 lda >rt_ot+2
 sta >rt_me+2+$20000
 jsr jt_flush
 stz jt_ntr
 stz jt_nrej
 stz jt_nflush
 stz jt_nstale
 stz jt_nbump
 stz jt_ngive
 stz jt_nmiss
 stz jt_nmix
 stz jt_nep
 stz jt_nver
 stz jt_nep2
 stz jt_nep3
 stz jt_nep4
 stz jt_ndisp
 stz jEP
 lda #4
 sta jSTEP
 lda #$FFFF
 sta jSPO
 sta jSPO2
 lda #JIT_GUARD
 sta jG
 plb
 rtl

* jt_flush - every translation thrown away (DBR this bank)
jt_flush
 mx %00
 inc jt_nflush
 lda >H_BDA+BDA_TICKS      ; a program with more code than the cache holds: only what is asked for sixteen
 tax                       ; times, while the cache lasts less than half a minute (jt_age: Larry 2's lasts
 sec                       ; thirteen seconds). One that fills it as it loads and then runs in what it has
 sbc jt_t0                 ; is asked four times, as at the start.
 stx jt_t0
 cmp #JT_YOUNG
 lda #4
 bcs :slow
 lda jt_nflush             ; (jt_init's own emptying is the first)
 cmp #5
 lda #4
 bcc :slow
 lda #1
:slow
 sta jSTEP
 stz c_bk
 lda #jt_cache
 sta c_ptr
 stz e_n
 stz e_n2
 phy
 lda #0
 sta >JIT_MAP
 ldx #<JIT_MAP
 ldy #<JIT_MAP+2
 lda #$FFFD
 mvn JIT_MAP,JIT_MAP
 phk
 plb
 stz pg_map
 ldx #pg_map
 ldy #pg_map+2
 lda #$1000-3
 mvn JIT_BASE,JIT_BASE
 ldx #30
:bk
 stz bk_code,x
 dex
 dex
 bpl :bk
 stz cl_map
 ldx #cl_map
 ldy #cl_map+2
 lda #$2000-3
 mvn JIT_BASE,JIT_BASE
 lda #$0404                ; the interrupt vectors and the BIOS's data are never code: what the
 sta pg_map                ; frame's work and the BIOS write there needs no looking at
 sta pg_map+2
 sta pg_map+3
 ply
 rts

* ep_wrap0 - the epoch has been through all its values: no piece may
* take the new ones for the one it compared in (JSL)
ep_wrap0
 mx %00
 phb
 phk
 plb
 phy
 stz jEP
 ldy #0
:l
 cpy e_n2
 bcs :done
 lda e_nat,y
 beq :next
 lda e_cb,y
 sta c_rb
 ldx e_desc,y
 lda #$FFFF
 jsr c_set
:next
 iny
 iny
 bra :l
:done
 ply
 plb
 rtl

* jt_tr0 - translate the piece at CS:rIP (tr_w: its word of the map).
* C set: A = its stub less one. C clear: A = how the core goes on (0
* or 5), and the map says so from now on. (JSL)
jt_tr0
 mx %00
 phb
 phk
 plb
 lda e_n
 cmp #MAXE
 bcs :full
 lda c_ptr
 ldx c_bk
 bne :second
 cmp c_lim
 bcc :room
 inc c_bk                  ; the first bank of code is full: on in the second
 lda #jt_cache
 sta c_ptr
 bra :room
:second
 cmp #CACHE_END-ROOM
 bcc :room
:full
 jsr jt_flush
 lda #$0010                ; (the map is new: this IP has used no life)
 sta tr_w
:room
 jsr jt_age
 jsr sc_scan
 bcs :scanned
 jmp :no
:scanned
 jsr sc_resolve
 jsr sc_ways
 jsr sc_live
 jsr sc_live
 jsr pg_mark               ; (a page of data and code: the interpreter's)
 bcs :pgok
 lda #2
 jsr rej_note
 jmp :never
:pgok
 jsr em_region
 bcs :emok
 lda #3
 jsr rej_note
 jmp :never
:emok
 lda e_n
 asl
 tax
 lda tr_s
 sta e_slot,x
 lda em_entry
 dec
 sta e_nat,x
 lda em_desc
 sta e_desc,x
 lda c_ptr
 sta e_end,x
 lda sc_lo
 sta e_lo,x
 lda sc_hi
 sta e_hi,x
 lda bx_lo+2
 sta e_xlo,x
 lda bx_hi+2
 sta e_xhi,x
 lda bx_lo+4
 sta e_ylo,x
 lda bx_hi+4
 sta e_yhi,x
 lda sc_cb
 sta e_bank,x
 lda c_bk
 sta e_cb,x
 stz e_bail,x
 lda tr_w
 lsr
 lsr
 lsr
 lsr
 lsr
 sta e_life,x
 ldx tr_s
 lda em_entry              ; (the stub less one is even: em_stub. Bit 0 says which bank of code)
 dec
 ora c_bk
 sta >JIT_MAP,x
 sta tr_ret
 inc jt_ntr
 inc e_n
 inc e_n2
 inc e_n2
 lda tr_ret
 plb
 sec
 rtl
:no                        ; A = 0: never; 5 to 8: the interpreter's instruction, and how the core goes on
 pha
 lda #1
 jsr rej_note
 pla
 bra :no2
:never
 lda #0
:no2
 sta tr_x
 inc jt_nrej
 ldx tr_s
 lda #M_NEVER
 ldy tr_x
 beq :w
 lda #$0103
 sec
 sbc tr_x
:w
 sta >JIT_MAP,x
 lda tr_x
 plb
 clc
 rtl

* jt_age - the cache has lasted half a minute: what is in it is what
* the program runs, and a new address is translated at its fourth
* asking, not its sixteenth (each asking before that is the interpreter
* given the run, and every piece comparing its bytes afterwards)
JT_YOUNG   = 546             ; ticks of the BIOS's clock: thirty seconds
jt_t0      dw 0              ; the tick count's low word when the cache was last emptied
jt_age
 mx %00
 lda >H_BDA+BDA_TICKS
 sec
 sbc jt_t0
 cmp #JT_YOUNG
 bcc :young
 lda #4
 sta jSTEP
:young
 rts

* rej_note - why CS:rIP was refused (A), into the ring
rej_note
 mx %00
 ldx jt_reji
 sta jt_rej+4,x
 lda rIP
 sta jt_rej,x
 lda rCS
 sta jt_rej+2,x
 txa
 clc
 adc #6
 cmp #384
 bcc :k
 lda #0
:k
 sta jt_reji
 rts

* pg_mark - the pages the piece's guest code is on (sc_lo, sc_hi,
* sc_cb). pg_map: 0 no translated code is from this page; odd, some
* is (and stores that came beside it, twice, above bit 0); 2 it was
* found to be data as well, its pieces went and its stores are looked
* at no more, until code on it is wanted again: then it is a page of
* code once more (the stores may have been a program's being loaded
* past old code, and each address has only so many lives); 4 it is
* never code (the vectors, the BIOS's data). C set: marked. C clear:
* one of them is of the last kind, and nothing is marked.
pg_mark
 mx %00
 lda #$FFFF                ; (the stack's sixteens are looked at again: h_push)
 sta jSPO
 sta jSPO2
 lda sc_cb
 and #$000F
 asl
 tax
 lda #1
 sta bk_code,x             ; (and stores into this bank are, from now on: gen/jrt.s)
 lda sc_cb
 and #$000F
 xba
 sta tr_x
 lda sc_hi
 dec
 xba
 and #$00FF
 ora tr_x
 sta sc_t
 lda sc_lo
 xba
 and #$00FF
 ora tr_x
 sta sc_t2
 tax
 sep #$20
 mx %10
:c
 lda pg_map,x
 cmp #4
 beq :mixed
 cpx sc_t
 beq :mark
 inx
 bra :c
:mark
 ldx sc_t2
 jsr :pages
 rep #$20
 mx %00
 ldy #0                    ; and the pages of what its ways out were looked ahead at (sc_look left none
:st                        ; that is never code)
 cpy la_n
 bcs :done
 lda la_e,y
 dec
 clc
 adc bCS
 xba
 and #$00FF
 ora tr_x
 sta sc_t
 lda la_s,y
 clc
 adc bCS
 xba
 and #$00FF
 ora tr_x
 tax
 sep #$20
 mx %10
 jsr :pages
 rep #$20
 mx %00
 iny
 iny
 bra :st
:done
 sec
 rts
:pages                     ; from page X to page sc_t (8 bits wide)
 mx %10
:l
 lda pg_map,x
 lsr
 bcs :have
 lda #1
 sta pg_map,x
:have
 cpx sc_t
 beq :pd
 inx
 bra :l
:pd
 rts
 mx %00
:mixed
 rep #$20
 mx %00
 clc
 rts

* cl_mark - the sixteens of bytes that a run of a piece's code is in
* (cl_map: a bit each): from A up to X in the code's bank
cl_mark
 mx %00
 pha
 dex
 txa
 lsr
 lsr
 lsr
 lsr
 sta sc_t
 lda sc_cb
 and #$000F
 xba
 asl
 asl
 asl
 asl
 sta tr_x
 tsb sc_t
 pla
 lsr
 lsr
 lsr
 lsr
 ora tr_x
 sta sc_t2
:cl
 lda sc_t2
 and #$0007
 tax
 lda cl_bits,x
 and #$00FF
 sta tr_x
 lda sc_t2
 lsr
 lsr
 lsr
 tax
 lda cl_map,x
 ora tr_x
 sta cl_map,x
 lda sc_t2
 cmp sc_t
 beq :cdone
 inc sc_t2
 bra :cl
:cdone
 rts
cl_bits    dfb 1,2,4,8,16,32,64,128,0

kl_why     dw 0              ; why the next one dies: 1 a store into its bytes, 2 its page became one of data and
jt_kili    dw 0              ; code, 3 its bytes are not the ones it was made from, 4 it kept meeting the EGA's planes
jt_kil     ds 256
* kill - entry X (twice) is dead. A = what its word of the map
* becomes: 0 for "count again, a life less". Its entries in the cache
* become jumps to the dispatcher, for whatever was linked to it. Keeps
* Y. DBR this bank.
kill
 mx %00
 phy
 txy
 cmp #0
 bne :w
 lda e_life,y
 inc
 cmp #7
 bcc :l
 lda #M_NEVER
 bra :w
:l
 asl
 asl
 asl
 asl
 asl
:w
 pha
 lda e_nat,y
 bne :live
 pla                       ; (dead already: its word of the map may be another's by now)
 ply
 rts
:live
 lda e_cb,y
 sta c_rb
 lda e_nat,y               ; (a look at what dies: the last 32, the piece's IP and CS, why, the store's address)
 clc
 adc #ST_IP+1
 tax
 jsr c_get
 pha
 txa
 clc
 adc #ST_CS-ST_IP
 tax
 jsr c_get
 ldx jt_kili
 sta jt_kil+2,x
 pla
 sta jt_kil,x
 lda pEA+2
 xba
 ora kl_why
 sta jt_kil+4,x
 lda pEA
 sta jt_kil+6,x
 txa
 clc
 adc #8
 and #$00FF
 sta jt_kili
 ldx e_slot,y
 pla
 sta >JIT_MAP,x
 lda e_nat,y
 sec
 sbc #ST_LB-1              ; the entry for links back; the stub is ST_LB on, and the one for links ahead ST_LF more
 tax
 jsr :jmp                  ; the three ways in: each a JMP h_disp from now on
 txa
 clc
 adc #ST_LB
 tax
 jsr :jmp
 txa
 clc
 adc #ST_LF
 tax
 jsr :jmp
 lda #0
 sta e_nat,y
 ply
 rts
:jmp                       ; JMP h_disp at X of the bank c_rb names
 lda #$004C
 jsr c_setb
 inx
 lda #h_disp
 jsr c_set
 dex
 rts

* in_runs - C set: the store at pEA (to sh_last) touches a byte of entry Y's guest
* code (its record's runs: where, words). Keeps Y.
ir_n       dw 0
ir_lo      dw 0
in_runs
 mx %00
 lda e_cb,y
 sta c_rb
 lda e_desc,y
 clc
 adc #6
 tax
 jsr c_get
 sta ir_n
 beq :no
 inx
 inx
:r
 jsr c_get                 ; a run: where it begins,
 sta ir_lo
 inx
 inx
 jsr c_get                 ; and its words
 asl
 sta tr_x                  ; the run's bytes
 lda sh_last
 cmp ir_lo
 bcc :nr                   ; (the store ends before it)
 lda ir_lo
 clc
 adc tr_x
 sta ir_lo
 lda pEA
 cmp ir_lo
 bcc :yes
:nr
 txa
 clc
 adc #2
 adc tr_x
 tax
 dec ir_n
 bne :r
:no
 clc
 rts
:yes
 sec
 rts

* cl_clear - the two sixteens the word at pEA is in are no code's
cl_clear
 mx %00
 lda pEA+1
 and #$0FFF
 asl
 sta tr_x
 lda pEA
 and #$0080
 beq :lo
 inc tr_x
:lo
 lda pEA
 and #$0070
 lsr
 lsr
 lsr
 lsr
 tax
 lda cl_bits,x             ; this sixteen and the next (the next byte's bit 0 when this is the last)
 and #$00FF
 sta sh_p
 asl
 ora sh_p
 eor #$FFFF
 ldx tr_x
 and cl_map,x
 sta cl_map,x
 rts

* stale0 - a piece's bytes are not the ones it was made from: X = its
* entry (JSL)
stale0
 mx %00
 phb
 phk
 plb
 inc jt_nstale
 lda #3
 sta kl_why
 lda #0
 jsr kill
 plb
 rtl

* which - Y = the entry (twice) of the piece whose code the address A
* is in, e_n2 when it is nobody's. DBR this bank. wh_bank says which
* bank of code, from the data bank the caller came with (A = that, a
* word with the bank in its low byte): the routines run with their own.
wh_bank
 mx %00
 and #$00FF
 cmp #^JIT_RT2
 beq :second
 stz wh_b
 rts
:second
 lda #1
 sta wh_b
 rts
which
 mx %00
 sta tr_x
 ldy #0
:l
 cpy e_n2
 bcs :out
 lda e_nat,y
 beq :next
 lda e_cb,y                ; (wh_b: which bank of code the address is in)
 cmp wh_b
 bne :next
 lda tr_x
 cmp e_desc,y
 bcc :next
 cmp e_end,y
 bcc :out
:next
 iny
 iny
 bra :l
:out
 rts

* give0 - the piece running at A met memory that is the interpreter's
* (the EGA's planes): at the sixteenth time it is given up (JSL)
give0
 mx %00
 phb
 phk
 plb
 phy
 pha
 lda 5,s
 jsr wh_bank
 pla
 jsr which
 cpy e_n2
 bcs :out
 tyx
 inc e_bail,x
 lda e_bail,x
 cmp #BAILS
 bcc :out
 inc jt_ngive
 lda #4
 sta kl_why
 lda #M_NEVER
 jsr kill
:out
 ply
 plb
 rtl

* smc0 - the store at pEA (sm_len + 1 bytes of it) is on a page that pg_map says translated code
* was made from: every piece is asked. One whose guest bytes the word
* touches is dead. A = an address in the running piece's code: C set
* when it is one of them. Each page of the word's that no live piece
* has bytes on is no code page any more, and one that has them but took
* this store beside them counts: at the eighth it is a page of data and
* code, the pieces on it are dead and no more are made from it. Keeps
* Y. (JSL)
sh_n       dw 0              ; pieces the word landed in
sh_self    dw 0
sh_run     dw 0              ; the running piece's entry
sh_p       dw 0              ; the page looked at (pg_map's index), and whether a live piece has bytes on it
sh_live    dw 0
sh_lo      dw 0              ; the page's bytes in its bank
sh_hi      dw 0
sh_bank    dw 0
sh_cell    dw 0              ; live pieces with bytes in the word's sixteens
sh_clo     dw 0              ; those sixteens: from here,
sh_chi     dw 0              ; to before here
bc_lo      ds 256            ; the last stores beside code, 128 of them by the address's low seven bits and the
bc_bk      ds 256            ; seven above them (a routine's variables lie together, a dozen in the sixteens its
bc_tr      ds 256            ; code is in; two that share a place here take it from each other at every store,
                             ; and each time is a strike against the page: Arkanoid's did): where, the bank and
                             ; length, and jt_ntr then: the same store with no piece made since lands in none again
bc_x       dw 0
bc_same    dw 0
* e_touch - C set: entry Y has bytes, its own code's or the ones its ways out were looked ahead at, from
* sh_a up to before sh_b (0: to the bank's end) of its bank. Keeps X and Y.
sh_a       dw 0
sh_b       dw 0
e_touch
 mx %00
 lda e_hi,y
 cmp sh_a
 beq :look
 bcc :look
 lda sh_b
 beq :yes
 lda e_lo,y
 cmp sh_b
 bcc :yes
:look
 lda e_xhi,y
 cmp sh_a
 beq :look2
 bcc :look2
 lda sh_b
 beq :yes
 lda e_xlo,y
 cmp sh_b
 bcc :yes
:look2
 lda e_yhi,y
 cmp sh_a
 beq :no
 bcc :no
 lda sh_b
 beq :yes
 lda e_ylo,y
 cmp sh_b
 bcs :no
:yes
 sec
 rts
:no
 clc
 rts

sm_len     dw 0              ; the store smc0 is asked about: its bytes less one (h_smcb, h_smc, h_smcf, h_push)
sh_last    dw 0              ; its last byte (the bank's last, for one that goes past it)
sh_key     dw 0              ; its bank, and its length above it: what the stores beside code are remembered by
smc0
 mx %00
 phy
 phb
 phk
 plb
 pha
 stz bc_same
 lda pEA
 clc
 adc sm_len
 bcc :lb
 lda #$FFFF
:lb
 sta sh_last
 lda sm_len
 xba
 ora pEA+2
 sta sh_key
 lda sm_len                ; (a word and a byte at the one address are two stores: a routine that clears
 asl                       ; its word and then sets its bytes would have each take the other's place)
 asl
 asl
 eor pEA
 sta bc_x
 lda pEA
 xba
 asl
 eor bc_x
 and #$007F
 asl
 tax
 stx bc_x
 lda bc_lo,x
 cmp pEA
 bne :new
 lda bc_bk,x
 cmp sh_key
 bne :new
 inc bc_same               ; (the same store as before: no strike against its page whatever follows)
 lda bc_tr,x
 cmp jt_ntr
 bne :new
 pla
 plb
 ply
 clc
 rtl
:new
 lda 3,s                   ; (the data bank it was called with: the running piece's bank of code)
 jsr wh_bank
 pla
 jsr which
 sty sh_run
 stz sh_n
 stz sh_self
 stz sh_cell
 lda pEA
 and #$FFF0
 sta sh_clo
 clc
 adc #32
 bcc :cw
 lda #$FFFF
:cw
 sta sh_chi
 ldy #0
:e
 cpy e_n2
 bcs :pages
 lda e_nat,y
 beq :next
 lda e_bank,y
 cmp pEA+2
 bne :next
 lda sh_clo                ; (its bytes among the sixteens the store is in?)
 sta sh_a
 lda sh_chi
 sta sh_b
 jsr e_touch
 bcc :far
 inc sh_cell
:far
 lda pEA
 sta sh_a
 lda sh_last
 inc
 sta sh_b
 jsr e_touch
 bcc :next
 jsr in_runs               ; (between a first byte and a last of its: in one of its runs?)
 bcc :next
 inc sh_n
 cpy sh_run
 bne :kill
 inc sh_self
:kill
 tyx
 lda #1
 sta kl_why
 lda #0
 jsr kill
 inc jt_nstale
:next
 iny
 iny
 bra :e
:pages
 lda sh_cell               ; no live piece near: the bits were dead pieces', and the store is nothing
 bne :near
 jsr cl_clear
 plb
 ply
 clc
 rtl
:near
 lda sh_n
 bne :np
 lda bc_same
 beq :np
 ldx bc_x                  ; (known, and still beside: only the count of pieces was new)
 lda jt_ntr
 sta bc_tr,x
:np
 lda pEA+1                 ; the store's page, and the next one when it lies across two
 and #$0FFF
 jsr :page
 lda pEA
 and #$00FF
 clc
 adc sm_len
 cmp #$0100
 bcc :out
 lda pEA+1
 inc
 and #$0FFF
 jsr :page
:out
 lda sh_n
 bne :hit
 ldx bc_x                  ; beside code: remembered
 lda pEA
 sta bc_lo,x
 lda sh_key
 sta bc_bk,x
 lda jt_ntr
 sta bc_tr,x
 inc jt_nbump
 ldx jt_besi
 lda pEA
 sta jt_bes,x
 lda pEA+2
 sta jt_bes+2,x
 lda sh_run
 sta jt_bes+4,x
 txa
 clc
 adc #6
 cmp #288
 bcc :bk
 lda #0
:bk
 sta jt_besi
:hit
 plb
 ply
 lda >sh_self
 cmp #1
 rtl
:page                      ; A = pg_map's index
 sta sh_p
 tax
 lda pg_map,x
 lsr
 bcs :pcode
 rts
:pcode
 lda sh_p                  ; the page as a bank and its first and last byte + 1 there
 xba
 and #$000F
 ora #GUEST_BANK
 sta sh_bank
 lda sh_p
 xba
 and #$FF00
 sta sh_lo
 clc
 adc #$0100
 sta sh_hi                 ; (0 for the bank's last page: compared as 10000h below)
 stz sh_live
 ldy #0
:pe
 cpy e_n2
 bcs :pdone
 lda e_nat,y
 beq :pn
 lda e_bank,y
 cmp sh_bank
 bne :pn
 lda sh_lo                 ; its bytes are lo to hi-1: on the page when hi > the page's first
 sta sh_a                  ; and lo < the page's end
 lda sh_hi
 sta sh_b
 jsr e_touch
 bcc :pn
 inc sh_live
:pn
 iny
 iny
 bra :pe
:pdone
 ldx sh_p
 lda sh_live
 bne :some
 sep #$20                  ; none: the mark was a dead piece's
 mx %10
 lda #0
 sta pg_map,x
 rep #$20
 mx %00
 rts
:some
 lda sh_n                  ; the store landed in code: nothing to count
 beq :beside
 rts
:beside
 lda bc_same               ; (nor for a store that is made again and again: it is known)
 beq :strike
 rts
:strike
 sep #$20
 mx %10
 lda pg_map,x
 inc
 inc
 sta pg_map,x
 cmp #33
 rep #$20
 mx %00
 bcs :mixed
 rts
:mixed                     ; data and code: the pieces with bytes on it go, the page is marked for good
 sep #$20
 mx %10
 lda #2
 sta pg_map,x
 rep #$20
 mx %00
 inc jt_nmix
 ldy #0
:me
 cpy e_n2
 bcs :mdone
 lda e_nat,y
 beq :mn
 lda e_bank,y
 cmp sh_bank
 bne :mn
 lda sh_lo
 sta sh_a
 lda sh_hi
 sta sh_b
 jsr e_touch
 bcc :mn
 cpy sh_run
 bne :mk2
 inc sh_self               ; (the running piece's own page: it ends here too)
:mk2
 tyx
 lda #2
 sta kl_why
 lda #0                    ; (a life less: the page may be code alone the next time)
 jsr kill
:mn
 iny
 iny
 bra :me
:mdone
 rts

 put scan.s
 put emit.s
 put gen/jtab.s

pg_map     ds $1000          ; a byte for each 256 of the guest's megabyte: translated code was made from bytes there
cl_map     ds $2004          ; and a bit for each 16

*==========================================================
* The run-time routines: what the core enters and what
* translated code calls (JSR or JMP: they are in its bank).
* Assembled for JIT_RT, loaded here (rt_image) and moved by
* jt_init. DBR is their own bank in them (sp_sync, at every
* entry from the core, which takes its own back: jit_ret):
* a piece's record and stub are reached by their addresses
* in whichever bank of code is running, everything else
* outside the direct page long, and what is not done every
* time is the image's (JSL).
*==========================================================
rt_image
 org JIT_RT
rt_start
 jmp jt_enter              ; +0  Y = an IP the interpreter came to: its code, if there is any
 jmp jt_enter_s            ; +3  the same after an instruction that wrote the stack and nothing else
 jmp jt_enter_n            ; +6  the same after one that wrote nothing
 jmp jt_resume             ; +9  on after an instruction the interpreter did inside a piece (jtmp)
 jmp jt_enter_r            ; +12 the same after one that wrote ES:tmp4 to ES:tmp5
 jmp jt_enter_b            ; +15 the same after one that may have written anywhere

* Two banks of code, each with these routines at the same addresses (jt_init): a piece calls the ones in
* its own bank. What differs is here: which bank this copy is in, and where the other is.
rt_flag    dw 0              ; 0: this is JIT_RT's bank; 1: JIT_RT2's (bit 0 of a stub's word in the map)
rt_me      adrl rt_start     ; this bank (the byte at +2),
rt_ot      adrl rt_start+$20000  ; and the other

* x_go - come from the other bank's copy (st_far, by RTL) with A = where to go on here, less one
x_go
 mx %00
 phk
 plb
 pha
 rts
* st_far - on in the other bank of code at A + 1
st_far
 mx %00
 tax
 sep #$20
 mx %10
 lda rt_ot+2
 pha
 rep #$20
 mx %00
 pea x_go-1
 txa
 rtl
* st_same - A = a word of the map that is a stub's ($0100 and over: the stub less one, bit 0 its bank of
* code): is it the stub of IP Y under this CS? C set: it is. tmp4 = the word. Keeps Y.
st_same
 mx %00
 sta tmp4
 eor rt_flag
 lsr
 bcs :other
 asl
 tax
 tya
 cmp rt_start+ST_IP+1,x
 bne :no
 lda rCS
 cmp rt_start+ST_CS+1,x
 bne :no
 sec
 rts
:other                     ; in the other bank: by a pointer
 asl
 sta pSTK
 lda rt_ot+2
 sta pSTK+2
 phy
 ldy #ST_IP+1
 lda [pSTK],y
 cmp 1,s
 bne :no2
 ldy #ST_CS+1
 lda [pSTK],y
 cmp rCS
 bne :no2
 ply
 sec
 rts
:no2
 ply
:no
 clc
 rts
* st_go - on at the stub of the word in tmp4, A + 1 bytes in, whichever bank of code it is in
st_go
 mx %00
 sta jT
 lda tmp4
 eor rt_flag
 lsr
 bcs :other
 asl
 clc
 adc jT
 pha
 rts
:other
 asl
 clc
 adc jT
 jmp st_far

*--- the dispatcher. Y = the IP, A 16 bits wide.

* jt_enter - from the interpreter: whatever it did since translated
* code last ran may have written anywhere
jt_enter
 mx %00
 jsr sp_sync
 lda >jt_nep
 inc
 sta >jt_nep
je_on
 mx %00
 inc jEP
 bmi :wrap
 jmp jt_look
:wrap
 jsl ep_wrap0
 jmp jt_look
jt_enter_b
 mx %00
 jsr sp_sync
 lda >jt_nep2
 inc
 sta >jt_nep2
 bra je_on
* jt_enter_s - after an instruction that pushed, or an interrupt: were
* the six bytes at the stack's top on a page translated code is made
* from?
jt_enter_s
 mx %00
 jsr sp_sync
 lda rSP
 clc
 adc bSS
 sta pEA
 lda bSS+2
 bcc :nc
 adc #0
 and #$000F
 ora #GUEST_BANK
:nc
 sta pEA+2
 lda #1
 sta >sm_len
 jsr pg_chk
 bne :on
 lda pEA
 clc
 adc #4
 sta pEA
 bcc :n2
 lda pEA+2
 inc
 and #$000F
 ora #GUEST_BANK
 sta pEA+2
:n2
 jsr pg_chk
 bne :on
 jmp jt_look
:on
 lda >jt_nep3
 inc
 sta >jt_nep3
 jmp je_on
jt_enter_n
 mx %00
 jsr sp_sync
 lda >jt_ndisp
 inc
 sta >jt_ndisp
 jmp jt_look
* jt_enter_r - after a REP MOVS or STOS that wrote the bytes from offset
* tmp4 to offset tmp5 of ES: is a page among them one that translated
* code is made from? (A 256 of the segment is on two pages of memory.)
jt_enter_r
 mx %00
 jsr sp_sync
 lda tmp4
 and #$FF00
 sta tmp4
:pg
 lda tmp4
 clc
 adc bES
 php
 xba
 and #$00FF
 sta jT
 plp
 lda bES+2
 adc #0
 and #$000F
 xba
 ora jT
 tax
 lda >pg_map,x
 lsr
 bcs :on
 inx
 txa
 and #$0FFF
 tax
 lda >pg_map,x
 lsr
 bcs :on
 lda tmp4
 clc
 adc #$0100
 bcs :look
 sta tmp4
 cmp tmp5
 bcc :pg
 beq :pg
:look
 jmp jt_look
:on
 lda >jt_nep4
 inc
 sta >jt_nep4
 jmp je_on
* h_disp - from translated code: on at IP Y. Every one counts for the
* guard, which gives the slot its turn.
h_disp
 mx %00
 dec jG
 bne jt_look
 jmp h_gx
jt_look
 mx %00
 tya
 clc
 adc rCS
 asl
 tax
 lda >JIT_MAP,x
 cmp #$0100
 bcc :cnt
 eor rt_flag               ; a stub, which looks at the IP, at CS and at the epoch (not this address's:
 lsr                       ; h_miss, and the second word). Bit 0: in the other bank of code
 bcs :far
 asl
 pha
 rts
:far
 asl
 jmp st_far
:cnt                       ; a count: the piece may be at the second word all the same
 pha
 stx tmp5
 txa
 eor #$8000
 tax
 lda >JIT_MAP,x
 cmp #$0100
 bcc :count
 jsr st_same
 bcc :count
 pla
 lda #ST_LF
 jmp st_go
:count
 ldx tmp5
 pla
jl_cnt                     ; X = the word's place, A = the word: count there. (jSTEP at a time: four, so
 mx %00                    ; that an address translated code comes to is wanted at the fourth asking;
 cmp #M_STEP               ; one, sixteen askings, for a program that has filled the cache four times.)
 bcs :mark
 clc
 adc jSTEP
 sta >JIT_MAP,x
 bit #$0010
 bne :hot
:plain
 lda #0                    ; the interpreter from here
 rtl
:mark
 cmp #M_NEVER
 beq :plain
 sta jT                    ; an instruction of the interpreter's, and then here again
 lda #$0103
 sec
 sbc jT
 rtl
:hot
 sta >tr_w
 txa
 sta >tr_s
 sty rIP
 jsl jt_tr0
 ldy rIP
 bcc :not
 sta tmp4                  ; (its word of the map: the stub less one, and the bank of code)
 lda #0
 jmp st_go
:not
 rtl                       ; (A = 0, or 5 to 8)
h_gx                       ; the guard ran out: the slot, then on from Y
 mx %00
 lda #2
 rtl
* h_miss - the first word's stub is another address's: the second word
* is this one's place, for its piece or its count
h_miss
 mx %00
 tya
 clc
 adc rCS
 asl
 eor #$8000
 tax
 lda >JIT_MAP,x
 cmp #$0100
 bcs :stub
 jmp jl_cnt
:stub
 jsr st_same
 bcc :none
 lda #ST_LF
 jmp st_go
:none                      ; both are others': the interpreter's
 lda >jt_nmiss
 inc
 sta >jt_nmiss
 lda >jt_dbgi
 tax
 clc
 adc #4
 and #$00FC
 sta >jt_dbgi
 tya
 sta >jt_dbg,x
 lda rCS
 sta >jt_dbg+2,x
 lda #0
 rtl

* h_linkf, h_linkb - from a place in translated code that goes on at
* an IP it knows (Y), by JSR: when the map has that IP's piece, for
* this CS, the JSR is made a JMP to the piece (its entry for a link:
* back, the guard first; both, the epoch) and is never here again.
h_linkb
 mx %00
 dec jG
 bne :go
 pla
 bra h_gx
:go
 lda #1-ST_LB              ; (from the map's word, the stub less one)
 bra lk_go
h_linkf
 mx %00
 lda #ST_LF+1
lk_go
 mx %00
 sta >lk_ofs
 tya
 clc
 adc rCS
 asl
 sta tmp5
 tax
 lda >JIT_MAP,x
 cmp #$0100
 bcc :two
 jsr st_same
 bcs :ours
:two                       ; (the address's second word)
 lda tmp5
 eor #$8000
 tax
 lda >JIT_MAP,x
 cmp #$0100
 bcc :no
 jsr st_same
 bcc :no
:ours
 lda tmp4                  ; in this bank of code the JSR becomes the JMP; a piece in the other is come to
 eor rt_flag               ; by this way every time
 lsr
 bcs :cross
 asl
 sta tmp4
 pla                       ; the JSR's last byte
 dec
 dec
 tax
 lda >lk_ofs
 clc
 adc tmp4
 sta rt_start+1,x
 sep #$20
 mx %10
 lda #$4C
 sta rt_start,x
 rep #$20
 mx %00
 lda tmp4                  ; and into the piece (this once the guard is counted already)
 clc
 adc #ST_LF
 pha
 rts
:cross
 pla
 lda #ST_LF
 jmp st_go
:no
 pla
 jmp jt_look

* jt_resume - back into a piece after an instruction the interpreter
* did for it (the STEP template left the place in jtmp)
jt_resume
 mx %00
 jsr sp_sync
 lda jtmp
 dec
 pha
 rts

* h_verify - a piece's stub: are the guest's bytes the ones the piece
* was made from? X = its record: the epoch it last compared in, its
* entry, the bank, the runs (where, words, the words). Keeps Y.
h_verify
 mx %00
 phy
 stx jT
 lda >jt_nver
 inc
 sta >jt_nver
 lda rt_start+4,x
 sta pEA+2                 ; the guest's bank,
 lda rt_me+2
 sta pSTK+2                ; and the record's
 lda rt_start+6,x
 sta tmp5
 txa
 clc
 adc #8
 tax
:run                       ; a run: where it is in the guest's bank, its words, the words (never past
 lda rt_start,x             ; the bank's end: sc_scan)
 sta pEA
 lda rt_start+2,x
 asl
 sta tmp4
 txa
 clc
 adc #4
 sta pSTK
 clc
 adc tmp4
 tax                       ; (the run after it)
 ldy tmp4
 dey
 dey
:l
 lda [pEA],y
 cmp [pSTK],y
 bne :bad
 dey
 dey
 bpl :l
 dec tmp5
 bne :run
 ldx jT
 lda jEP
 sta rt_start,x
 ply
 rts
:bad
 ldx jT
 lda rt_start+2,x
 tax
 jsl stale0
 ply
 pla                       ; (the stub's JSR)
 lda #0
 rtl

* h_bailr - the interpreter is to do the instruction after all. On
* the stack: the return address of the piece's JSR to a helper, which
* has LDY #IP straight before it (gen_jit.py): the IP from there.
h_bailr
 mx %00
 pla
 sec
 sbc #4
 tax
 lda rt_start,x
 tay
 lda #0
 rtl

* h_hi - an operand's bank (A) is A000 or above (the pointer routines
* come here by JMP). The text buffer's: its 256 is marked (both, for a
* word across two), as the interpreter marks it. A000 while the screen
* is the EGA's mode 0Dh is the planes behind the graphics controller:
* the interpreter's, and a piece that keeps coming to them is given up.
* The rest is memory like any other.
h_hi
 mx %00
 cmp #^H_TXTBANK
 beq :text
 cmp #^H_EGA
 bne :plain
 lda >EGA_ON
 bne :bail
:plain
 rts
:text
 lda pEA
 and #$7F00
 xba
 tax
 sep #$20
 mx %10
 lda #1
 sta >VID_DIRTY,x
 lda pEA
 inc
 bne :one
 txa
 inc
 and #$7F
 tax
 lda #1
 sta >VID_DIRTY,x
:one
 rep #$20
 mx %00
 rts
:bail
 lda 1,s                   ; (where the piece was)
 jsl give0
 jmp h_bailr

* pg_chk - is the word at pEA on a page that translated code was made
* from? Z clear: it is, or was (smc0 knows). (X is used; not Y.)
pg_chk
 mx %00
 lda pEA+1
 and #$0FFF
 tax
 lda >pg_map,x
 lsr                       ; (odd: code)
 bcs :yes
 lda pEA
 and #$00FF
 clc
 adc >sm_len
 cmp #$0100
 bcc :no                   ; (all of the store is on the one page)
 lda pEA+1
 inc
 and #$0FFF
 tax
 lda >pg_map,x
 lsr
 bcs :yes
:no
 lda #0
 rts
:yes
 lda #1
 rts

* pg_dead - the page of pEA has its flag in pg_map: has it a sixteen
* that is code's? Z set: none, the flag was dead pieces' and is taken
* away (not for a word that lies across two pages: Z clear).
pg_dead
 mx %00
 lda pEA
 inc
 and #$00FF
 beq :no
 lda pEA+1
 and #$0FFF
 asl
 tax
 lda >cl_map,x
 bne :no
 lda pEA+1
 and #$0FFF
 tax
 sep #$20
 mx %10
 lda #0
 sta >pg_map,x
 rep #$20
 mx %00
 lda #0
 rts
:no
 lda #1
 rts

* cl_chk - is the word at pEA in sixteen bytes that translated code was
* made from? Z clear: it is. (X and pSTK are used; not Y.)
cl_chk
 mx %00
 lda pEA+1
 and #$0FFF
 asl
 sta pSTK
 lda pEA
 and #$0080
 beq :lo
 inc pSTK
:lo
 lda pEA
 and #$0070
 lsr
 lsr
 lsr
 lsr
 tax
 lda >cl_bits,x
 and #$00FF
 sta pSTK+2
 lda pEA                   ; (its last byte in the next sixteen: that one's bit too)
 and #$000F
 clc
 adc >sm_len
 cmp #$0010
 bcc :one
 lda pSTK+2
 asl
 tsb pSTK+2
:one
 ldx pSTK
 lda >cl_map,x
 and pSTK+2
 rts

* h_smc - a store (pEA) onto a page translated code was made from, or
* for a word or four bytes with such a page next (the pointer routines
* come here by JMP, by the entry for the store's length: sm_len). The
* pieces it lands in are dead (smc0), and when the running one is among
* them the interpreter does the store. A byte in the byte before a
* piece's code is beside it, not in it: a program's variable there
* (Arkanoid's, before the routine that sets it) costs the piece nothing.
h_smcb                     ; a byte
 mx %00
 lda #0
 bra h_smcx
h_smcf                     ; four bytes
 mx %00
 lda #3
 bra h_smcx
h_smc                      ; a word
 mx %00
 lda #1
h_smcx
 mx %00
 sta >sm_len
 jsr pg_chk
 bne :hit
 rts
:hit
 jsr pg_dead
 beq :clean
 jsr cl_chk
 bne :cell
:clean
 rts
:cell
 lda 1,s                   ; (where the piece is)
 jsl smc0
 bcs :self
 rts
:self
 jmp h_bailr

* h_push - PUSH: A = the word. The offsets under SS that are known to
* hold no translated code's bytes and to be plain memory are a range
* (jSPO to jSPO2, the last one a word may begin at; FFFFh and FFFFh:
* none): a word pushed inside it goes through SS's base with no more
* asked. Outside it the bytes are looked up (the page's flag, the
* sixteen's bit), and when no code is made from the two pages that the
* 256 of offsets lies on, the 256 is the range, or is added to the range
* when it lies next to it; else the sixteen is. The range is this SS's
* (sp_sync, wherever SS may have changed), and a new piece forgets it
* (pg_mark).
h_push
 mx %00
 ldy rSP
 dey
 dey
 cpy jSPO
 bcc :look
 cpy jSPO2
 bcs :look
 sty rSP
 sta [bSS],y
 rts
:look
 sta tmp4
 sty tmp5
 lda #1
 sta >sm_len
 cpy #$FFFF                ; (the word would lie across the segment's end)
 beq :bail
 tya
 clc
 adc bSS
 sta pEA
 lda bSS+2
 bcc :nc
 adc #0
 and #$000F
 ora #GUEST_BANK
:nc
 sta pEA+2
 cmp #^H_EGA
 bcs :bail
 jsr pg_chk
 beq :clean
 jsr pg_dead
 beq :clean
 jsr cl_chk
 beq :clean
 lda 1,s
 jsl smc0
 bcc :store
:bail                      ; (a push into the running piece's own code, or to where the interpreter must look)
 jmp h_bailr
:clean
 lda pEA+2                 ; remembered, when the store through SS's base is right for it: below the
 cmp #^H_HIGH9             ; video memory
 bcs :store
 lda tmp5                  ; the 256 of offsets the word is in: on two pages of memory. A sixteen
 and #$FF00                ; of code on either?
 clc
 adc bSS
 php
 xba
 and #$00FF
 sta pSTK
 plp
 lda bSS+2
 adc #0
 and #$000F
 xba
 ora pSTK
 asl
 tax
 lda >cl_map,x
 ora >cl_map+2,x
 bne :cell
 lda tmp5                  ; none: the 256, from its first offset to its last
 and #$FF00
 sta pSTK
 ora #$00FF
 sta pSTK+2
 lda jSPO2
 inc
 beq :new                  ; (no range, or one with nothing above it)
 cmp pSTK
 bne :below
 lda pSTK+2                ; on top of the range
 sta jSPO2
 bra :store
:below
 lda pSTK+2
 inc
 beq :new
 cmp jSPO
 bne :new
 lda pSTK                  ; under it
 sta jSPO
 bra :store
:new
 lda pSTK
 sta jSPO
 lda pSTK+2
 sta jSPO2
 bra :store
:cell                      ; the sixteen the word begins in, which was found to be no code's
 lda tmp5
 and #$FFF0
 sta jSPO
 ora #$000F
 sta jSPO2
:store
 lda tmp5
 sta rSP
 lda tmp4
 sta [pEA]
 rts

* sp_sync - translated code is about to run, or has loaded SS: the
* range h_push keeps is this SS's or none, and jSPM says whether SS's
* base is low enough for a pop to read through it (FFFFh: every offset
* but the last; 0: none). Keeps X and Y.
sp_sync
 mx %00
 phk                       ; (and the data bank is this one from here on: the routines and the pieces reach
 plb                       ; what is theirs in it by its own addresses, whichever bank of code they are in)
 lda bSS+2
 cmp #^H_HIGH9
 lda #$FFFF
 bcc :low
 lda #0
:low
 sta jSPM
 lda rSS
 cmp jSPS
 beq :same
 sta jSPS
 lda #$FFFF
 sta jSPO
 sta jSPO2
:same
 rts

* h_pop - POP: A = the word. (pEA is kept: POP to memory has its
* operand's pointer there.)
h_pop
 mx %00
 ldy rSP
 cpy jSPM
 bcs :slow
 lda [bSS],y
 iny
 iny
 sty rSP
 rts
:slow
 lda rSP
 cmp #$FFFF
 beq :bail
 clc
 adc bSS
 sta pSTK
 lda bSS+2
 bcc :nc
 adc #0
 and #$000F
 ora #GUEST_BANK
:nc
 sta pSTK+2
 cmp #^H_EGA
 bcs :bail
 lda rSP
 inc
 inc
 sta rSP
 lda [pSTK]
 rts
:bail
 jmp h_bailr

* h_retf - RETF. When the CS on the stack is the one now it is a return
* like any other: Y = the IP from the stack. Else it is the
* interpreter's, which writes nothing doing it.
h_retf
 mx %00
 ldy rSP
 cpy #$FFFD
 bcs :far
 cpy jSPM
 bcs :far
 iny
 iny
 lda [bSS],y
 cmp rCS
 bne :far
 dey
 dey
 lda [bSS],y
 tax
 tya
 clc
 adc #4
 sta rSP
 txy
 rts
:far
 pla
 sec
 sbc #4
 tax
 lda rt_start,x
 tay
 lda #7
 rtl

 put gen/jrt.s
rt_end
jt_cache   = rt_end          ; the code cache: from here to CACHE_END
 err rt_end-JIT_RT/$1000    ; (the routines are small)
 err rt_image-JIT_BASE+rt_end-rt_start-1/$10000   ; (and the image one bank)
