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
e_bank     ds MAXE*2         ; the bank,
e_life     ds MAXE*2         ; the lives its IP had used when it was made,
e_bail     ds MAXE*2         ; times it gave up at memory it cannot write
bk_code    ds 32             ; a word for each bank of the guest's: translated code was made from bytes there
tr_w       dw 0              ; jt_tr0: the map's word for the IP
tr_x       dw 0
tr_s       dw 0              ; and where that word is (the dispatcher says: the address's first word, or its second)

jt_init
 mx %00
 phb
 phk
 plb
 ldx #rt_image             ; the run-time routines to their bank
 ldy #rt_start
 lda #rt_end-rt_start-1
 mvn JIT_BASE,JIT_RT
 phk
 plb
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
 lda jt_nflush             ; (a program with more code than the cache holds: only what is asked for
 cmp #5                    ; sixteen times from now on. jt_init's own emptying is the first.)
 bcc :gen
 lda #1
 sta jSTEP
:gen
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
 ldx e_desc,y
 lda #$FFFF
 sta >JIT_RT,x
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
 cmp #CACHE_END-ROOM
 bcc :room
:full
 jsr jt_flush
 lda #$0010                ; (the map is new: this IP has used no life)
 sta tr_w
:room
 jsr sc_scan
 bcc :no
 jsr sc_resolve
 jsr sc_live
 jsr sc_live
 jsr pg_mark               ; (a page of data and code: the interpreter's)
 bcs :pgok
 lda #2
 jsr rej_note
 bra :never
:pgok
 jsr em_region
 bcs :emok
 lda #3
 jsr rej_note
 bra :never
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
 lda sc_cb
 sta e_bank,x
 stz e_bail,x
 lda tr_w
 lsr
 lsr
 lsr
 lsr
 lsr
 sta e_life,x
 ldx tr_s
 lda em_entry
 dec
 sta >JIT_MAP,x
 inc jt_ntr
 inc e_n
 inc e_n2
 inc e_n2
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
:l
 lda pg_map,x
 lsr
 bcs :have
 lda #1
 sta pg_map,x
:have
 cpx sc_t
 beq :done
 inx
 bra :l
:done
 rep #$20
 mx %00
 sec
 rts
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
 ldx e_slot,y
 pla
 sta >JIT_MAP,x
 lda e_nat,y
 sec
 sbc #ST_LB-1              ; the entry for links back; the stub is ST_LB on, and the one for links ahead ST_LF more
 tax
 lda #h_disp
 sta >JIT_RT+1,x
 sta >JIT_RT+ST_LB+1,x
 sta >JIT_RT+ST_LB+ST_LF+1,x
 sep #$20
 mx %10
 lda #$4C
 sta >JIT_RT,x
 sta >JIT_RT+ST_LB,x
 sta >JIT_RT+ST_LB+ST_LF,x
 rep #$20
 mx %00
 lda #0
 sta e_nat,y
 ply
 rts

* in_runs - C set: the word at pEA touches a byte of entry Y's guest
* code (its record's runs: where, words). Keeps Y.
ir_n       dw 0
ir_lo      dw 0
in_runs
 mx %00
 ldx e_desc,y
 lda >JIT_RT+6,x
 sta ir_n
 beq :no
 txa
 clc
 adc #8
 tax
:r
 lda >JIT_RT,x
 sta ir_lo
 lda >JIT_RT+2,x
 asl
 sta tr_x                  ; the run's bytes
 lda pEA
 inc
 cmp ir_lo
 bcc :nr                   ; (the word ends before it)
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
 adc #4
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
 lda #0
 jsr kill
 plb
 rtl

* which - Y = the entry (twice) of the piece whose code the address A
* is in, e_n2 when it is nobody's. DBR this bank.
which
 mx %00
 sta tr_x
 ldy #0
:l
 cpy e_n2
 bcs :out
 lda e_nat,y
 beq :next
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
 jsr which
 cpy e_n2
 bcs :out
 tyx
 inc e_bail,x
 lda e_bail,x
 cmp #BAILS
 bcc :out
 inc jt_ngive
 lda #M_NEVER
 jsr kill
:out
 ply
 plb
 rtl

* smc0 - the word at pEA is on a page that pg_map says translated code
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
bc_lo      ds 8              ; the last stores beside code, four of them by the address's bits 1 and 2: where,
bc_bk      ds 8              ; the bank,
bc_tr      ds 8              ; and jt_ntr then: the same store with no piece made since lands in none again
bc_x       dw 0
bc_same    dw 0
smc0
 mx %00
 phy
 phb
 phk
 plb
 pha
 stz bc_same
 lda pEA
 and #$0006
 tax
 stx bc_x
 lda bc_lo,x
 cmp pEA
 bne :new
 lda bc_bk,x
 cmp pEA+2
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
 lda e_hi,y                ; (its bytes among the sixteens the word is in?)
 cmp sh_clo
 beq :far
 bcc :far
 lda e_lo,y
 cmp sh_chi
 bcs :far
 inc sh_cell
:far
 lda pEA
 inc
 beq :next                 ; (a word across the bank's end: its second byte is no piece's here)
 cmp e_lo,y
 bcc :next
 lda pEA
 cmp e_hi,y
 bcs :next
 jsr in_runs               ; (between its first byte and its last: in one of its runs?)
 bcc :next
 inc sh_n
 cpy sh_run
 bne :kill
 inc sh_self
:kill
 tyx
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
 lda pEA+1                 ; the word's page, and the next one when it lies across two
 and #$0FFF
 jsr :page
 lda pEA
 inc
 and #$00FF
 bne :out
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
 lda pEA+2
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
 lda e_hi,y                ; its bytes are lo to hi-1: on the page when hi > the page's first
 cmp sh_lo                 ; and lo < the page's end
 beq :pn
 bcc :pn
 lda sh_hi
 beq :on
 lda e_lo,y
 cmp sh_hi
 bcs :pn
:on
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
 cmp #17
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
 lda e_hi,y
 cmp sh_lo
 beq :mn
 bcc :mn
 lda sh_hi
 beq :mk
 lda e_lo,y
 cmp sh_hi
 bcs :mn
:mk
 cpy sh_run
 bne :mk2
 inc sh_self               ; (the running piece's own page: it ends here too)
:mk2
 tyx
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
* jt_init. DBR is the core's in them, so everything outside
* the direct page is reached long, and what is not done
* every time is the image's (JSL).
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

*--- the dispatcher. Y = the IP, A 16 bits wide.

* jt_enter - from the interpreter: whatever it did since translated
* code last ran may have written anywhere
jt_enter
 mx %00
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
 lda >jt_nep2
 inc
 sta >jt_nep2
 bra je_on
* jt_enter_s - after an instruction that pushed, or an interrupt: were
* the six bytes at the stack's top on a page translated code is made
* from?
jt_enter_s
 mx %00
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
 lda >jt_ndisp
 inc
 sta >jt_ndisp
 jmp jt_look
* jt_enter_r - after a REP MOVS or STOS that wrote the bytes from offset
* tmp4 to offset tmp5 of ES: is a page among them one that translated
* code is made from? (A 256 of the segment is on two pages of memory.)
jt_enter_r
 mx %00
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
 beq h_gx
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
 pha                       ; a stub, which looks at the IP, at CS and at the epoch (not this
 rts                       ; address's: h_miss, and the second word)
:cnt                       ; a count: the piece may be at the second word all the same
 sta tmp4
 stx tmp5
 txa
 eor #$8000
 tax
 lda >JIT_MAP,x
 cmp #$0100
 bcc :count
 tax
 tya
 cmp >JIT_RT+ST_IP+1,x
 bne :count
 lda rCS
 cmp >JIT_RT+ST_CS+1,x
 bne :count
 txa
 clc
 adc #ST_LF
 pha
 rts
:count
 ldx tmp5
 lda tmp4
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
 pha
 rts
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
 bcc jl_cnt
 tax
 tya
 cmp >JIT_RT+ST_IP+1,x
 bne :none
 lda rCS
 cmp >JIT_RT+ST_CS+1,x
 bne :none
 txa
 clc
 adc #ST_LF
 pha
 rts
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
 sta jT
 tya
 clc
 adc rCS
 asl
 sta tmp5
 tax
 lda >JIT_MAP,x
 cmp #$0100
 bcc :two
 sta tmp4
 tax
 tya
 cmp >JIT_RT+ST_IP+1,x
 bne :two
 lda rCS
 cmp >JIT_RT+ST_CS+1,x
 beq :ours
:two                       ; (the address's second word)
 lda tmp5
 eor #$8000
 tax
 lda >JIT_MAP,x
 cmp #$0100
 bcc :no
 sta tmp4
 tax
 tya
 cmp >JIT_RT+ST_IP+1,x
 bne :no
 lda rCS
 cmp >JIT_RT+ST_CS+1,x
 bne :no
:ours
 pla                       ; the JSR's last byte
 dec
 dec
 tax
 lda tmp4
 clc
 adc jT
 sta >JIT_RT+1,x
 sep #$20
 mx %10
 lda #$4C
 sta >JIT_RT,x
 rep #$20
 mx %00
 lda tmp4                  ; and into the piece (this once the guard is counted already)
 clc
 adc #ST_LF
 pha
 rts
:no
 pla
 jmp jt_look

* jt_resume - back into a piece after an instruction the interpreter
* did for it (the STEP template left the place in jtmp)
jt_resume
 mx %00
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
 stz pEA
 lda >JIT_RT+4,x
 sta pEA+2
 lda >JIT_RT+6,x
 sta tmp5
 txa
 clc
 adc #8
 tax
:run
 lda >JIT_RT,x
 tay
 lda >JIT_RT+2,x
 sta tmp4
 inx
 inx
 inx
 inx
:l
 lda [pEA],y
 cmp >JIT_RT,x
 bne :bad
 iny
 iny
 inx
 inx
 dec tmp4
 bne :l
 dec tmp5
 bne :run
 ldx jT
 lda jEP
 sta >JIT_RT,x
 ply
 rts
:bad
 ldx jT
 lda >JIT_RT+2,x
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
 lda >JIT_RT,x
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
 inc
 and #$00FF
 bne :no                   ; (the word is on one page)
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
 lda pEA                   ; (its second byte in the next sixteen: that one's bit too)
 and #$000F
 cmp #$000F
 bne :one
 lda pSTK+2
 asl
 tsb pSTK+2
:one
 ldx pSTK
 lda >cl_map,x
 and pSTK+2
 rts

* h_smc - a store (pEA) into a bank this CS's code can be in. Onto a
* page translated code was made from: the pieces it lands in are dead
* (smc0), and when the running one is among them the interpreter does
* the store.
h_smc
 mx %00
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

* h_push - PUSH: A = the word. The bytes the word goes to are looked
* up once (the page's flag, the sixteen's bit), and remembered by SS
* and offset (jSPS, jSPO, jSPO2: two places; a new piece forgets them):
* a whole 256 of offsets when no code is made from any of it, else the
* sixteen (jSPM). While the stack stays there the store is through
* SS's base, which is known to be low enough for that.
h_push
 mx %00
 tax
 ldy rSP
 dey
 dey
 lda rSS
 cmp jSPS
 bne :look
 tya
 eor jSPO
 and jSPM
 beq :ok
 tya
 eor jSPO2
 and jSPM
 bne :look
:ok
 sty rSP
 txa
 sta [bSS],y
 rts
:look
 stx tmp4
 sty tmp5
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
 lda tmp5                  ; remembered, when the store through SS's base is right for it: an even
 lsr                       ; offset, below the video memory
 bcs :store
 lda pEA+2
 cmp #^H_HIGH9
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
 beq :wide
 lda #$FFF1
 bra :key
:wide
 lda #$FF01
:key
 sta pSTK+2
 cmp jSPM
 bne :other
 lda rSS
 cmp jSPS
 beq :same
:other                     ; (another SS, or another width: the second place is nothing's)
 lda #$FFFF
 sta jSPO
 lda rSS
 sta jSPS
 lda pSTK+2
 sta jSPM
:same
 lda jSPO
 sta jSPO2
 lda tmp5
 and jSPM
 and #$FFF0
 sta jSPO
:store
 lda tmp5
 sta rSP
 lda tmp4
 sta [pEA]
 rts

* h_pop - POP: A = the word. (pEA is kept: POP to memory has its
* operand's pointer there.)
h_pop
 mx %00
 lda bSS+2
 cmp #^H_HIGH9
 bcs :slow
 ldy rSP
 cpy #$FFFF
 beq :slow
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
 lda bSS+2
 cmp #^H_HIGH9
 bcs :far
 ldy rSP
 cpy #$FFFD
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
 lda >JIT_RT,x
 tay
 lda #7
 rtl

 put gen/jrt.s
rt_end
jt_cache   = rt_end          ; the code cache: from here to CACHE_END
 err rt_end-JIT_RT/$1000    ; (the routines are small)
 err rt_image-JIT_BASE+rt_end-rt_start-1/$10000   ; (and the image one bank)
