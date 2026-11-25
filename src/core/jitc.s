*----------------------------------------------------------
* jitc.s - the core's side of the translator (docs/jit.md,
* "M6.3"). The translator is its own image, in the JIT
* region (src/jit), there only when the front end found the
* file JIT (MB_LAYOUT's word for the region says) and used
* only when XTGS.CMD says JIT=ON (JIT_CFG). The interpreter
* owns the run: at a jump back that is taken (jcc_back and
* op_E9, where jit_start then puts a JMP to here: jcc_hook,
* e9_hook) it looks the target up in the map.
*
* JIT_MAP has a word for an IP (two IPs 8000h apart share
* it; src/jit/jit.s has what it holds; the translator's
* run-time routines are in the bank at JIT_RT). Under $FE it is a
* count: with bit 4 set the translator is asked. $0100 and
* over, translated code is there (if it is this IP's and
* this CS's: its stub looks).
*
* Translated code comes back here (jit_ret) with Y the IP
* and A why:
*   0  the interpreter goes on from Y
*   2  the guard ran out: the slot, one instruction, and
*      then translated code again if Y has any
*   3  the instruction at Y is the interpreter's, and then
*      the same piece again where it left (jtmp), if the IP
*      after it is the one expected (jtmp2), CS is what it
*      was and nothing wrote memory meanwhile (the epoch)
*   5  the instruction at Y is the interpreter's, and then
*      whatever translated code there is for where it lands
*      (jt_enter: the epoch goes on first)
*   6  the same; all the instruction writes is the stack
*   7  the same; it writes nothing
*   8  the same, a REP MOVS or STOS: the epoch goes on if
*      what it wrote is on a page of code
*   9  the same, an IRET: nothing is written, and CS may
*      be another afterwards
* An instruction the interpreter does for translated code
* retires into jit_hook: the run's vector is put aside for
* it (vNEXT, vnext0), as the JIT spike's fallback does.
*----------------------------------------------------------
jit_on     dw 0              ; nonzero: the translator is used in this run
jit_sv     ds 6              ; vNEXT, vnext0 and CS, kept over an instruction
jit_after  dw 0              ; what jit_hook does: 0 back into the piece, 2 4 6 jt_enter and its kin
jit_cb     dw 0              ; what translated code last came back with,
jit_sb     dw 0              ; and which bank of code a piece that is to be gone on with is in (0, 1)
jit_pli    dw 0
jit_pl     ds 384
jit_dbgi   dw 0
jit_dbg    ds 384
jit_di     dw 0              ; DI and CX before a REP MOVS or STOS
jit_cx     dw 0

jit_start                  ; a PC starts
 mx %00
 stz jit_on
 lda >MB_LAYOUT+RG_JIT+RG_JIT
 beq :no
 lda >JIT_CFG
 beq :no
 jsl JIT_BASE              ; the map and the cache empty
 inc jit_on
 sep #$20                  ; and the probe is in the way of every jump back from
 mx %10                    ; now on: JMP jit_bk where the short jumps count the
 lda #$4C                  ; slot, JMP e9_jit where the near jump does (a run
 sta jcc_hook              ; without the translator pays nothing for it)
 sta e9_hook
 rep #$20
 mx %00
 lda #jit_bk
 sta jcc_hook+1
 lda #e9_jit
 sta e9_hook+1
:no
 rts

jit_bk                     ; a jump back was taken, to Y
 mx %00
 tya
 clc
 adc rCS
 asl
 tax
 lda >JIT_MAP,x
 cmp #$00FB
 bcs :sp
 inc
 bit #$0010
 bne :go                   ; (often enough: the translator's turn, and it counts this one)
 sta >JIT_MAP,x
:cold
 jmp next_ct
:sp
 cmp #$0100
 bcc :cold                 ; (the interpreter's for good)
:go
 lda #JIT_GUARD
 sta jG
 lda vNEXT                 ; the jump was the one instruction the interpreter was given (the hook is
 cmp #jit_hook             ; waiting still): a jump writes nothing, and nothing else has run
 bne :ran
 jsl JIT_RT+6              ; jt_enter_n
 bra jit_ret
:ran
 jsl JIT_RT                ; jt_enter: the interpreter has run by itself, and may have written anywhere
jit_ret                    ; A = why (and above it, for 3, which bank of code), Y = the IP
 mx %00
 phk                       ; (translated code's data bank is its own: jit.s)
 plb
 sta jit_cb
 and #$00FF
 asl
 tax
 jmp (jr_tab,x)
jr_tab da jr_plain,jr_plain,jr_guard,jr_step,jr_plain,jr_any,jr_stack,jr_pure,jr_str,jr_iret
jr_plain
 mx %00
 ldx jit_pli               ; (a look at where the interpreter is given the run: the last 96, IP and CS)
 tya
 sta jit_pl,x
 lda rCS
 sta jit_pl+2,x
 txa
 clc
 adc #4
 cmp #384
 bcc :k
 lda #0
:k
 sta jit_pli
 jmp next_ct
jr_guard                   ; the slot's turn. Has it anything to do? (What the slot itself asks,
 mx %00                    ; cpu.s: a line that can be delivered, the frame's work.) When it
 lda #JIT_GUARD            ; has not, translated code goes on and nothing was written meanwhile.
 sta jG
 lda vPCMODE
 beq :none
 cmp #2
 bne :vbl
 lda vTICK
 bne :lines
 lda >PIC_PEND
 beq :vbl
:lines
 lda rFL
 and #F_IF
 bne :work
:vbl
 lda >VBLBAR
 and #$0080
 cmp vVBL
 beq :none
 tax                       ; an edge: into the blank is the frame's work; out of it nothing but
 bne :work                 ; the note that it was seen
 sta vVBL
:none
 lda #SLOT_N               ; (the slot was met, as far as the interpreter's count goes)
 sta vSLOT
 jsl JIT_RT+6              ; jt_enter_n
 jmp jit_ret
:work                      ; it has: the slot, which comes back here in place of the next instruction
 lda #jit_slotret
 sta slot_x+1
 jmp slot
jit_slotret                ; Y = the IP now (an interrupt's handler, when one was delivered). The slot
 mx %00                    ; wrote the guest's stack at most, and the frame's work memory that no
 lda #fetch                ; code is in (the vectors, the BIOS's data, the screen: SVC's promise).
 sta slot_x+1
 jsl JIT_RT+3              ; jt_enter_s
 jmp jit_ret
jr_step
 mx %00
 lda jit_cb                ; (the step's way out says which bank of code its piece is in: 0 or 1, above the 3)
 xba
 and #$00FF
 sta jit_sb
 lda rCS
 sta jit_sv+4
 lda jEP
 sta jSV
 lda #0
 bra jr_go
jr_any
 mx %00
 stz jCLN                  ; (a hypercall that writes only the BIOS's data will say so)
 ldx jit_dbgi              ; (a look at what these are: the last 64, IP, CS, the first two bytes)
 tya
 sta jit_dbg,x
 lda rCS
 sta jit_dbg+2,x
 lda [bCS],y
 sta jit_dbg+4,x
 txa
 clc
 adc #6
 cmp #384
 bcc :k
 lda #0
:k
 sta jit_dbgi
 lda #2
 bra jr_go
jr_stack
 mx %00
 lda #4
 bra jr_go
jr_iret                    ; IRET: under the same CS afterwards nothing was written; under
 mx %00                    ; another, that code's own stores were not looked at for this one
 lda rCS
 sta jit_sv+4
 lda #8
 bra jr_go
jr_str                     ; a REP MOVS or STOS: what it writes is from where DI is to where it will be
 mx %00
 lda rDI
 sta jit_di
 lda rCX
 sta jit_cx
 lda #10
 bra jr_go
jr_pure
 mx %00
 lda #6
jr_go
 mx %00
 jsr jit_sethook
 jmp fetch
jit_sethook
 mx %00
 sta jit_after
 lda vNEXT                 ; (one may be waiting still: the instruction it was set for
 cmp #jit_hook             ; was a jump back, and the probe took it. The vectors kept
 beq :have                 ; are the run's already.)
 sta jit_sv
 lda vnext0
 sta jit_sv+2
:have
 lda #jit_hook
 sta vNEXT
 sta vnext0
 rts
jit_hook                   ; the instruction has retired: Y = the IP now
 mx %00
 lda jit_sv+2
 sta vnext0
 lda jit_sv
 sta vNEXT
 lda vSLOT                 ; (the slot is wanted: an IRET or a POPF with an interrupt owed.
 cmp #2                    ; The guard's next count is its last.)
 bcs :go
 lda #1
 sta jG
:go
 ldx jit_after
 jmp (jh_tab,x)
jh_tab da jh_back,jh_any,jh_stack,jh_pure,jh_iret,jh_str
jh_str                     ; the bytes between the two DIs (two more at each end: a word, either way): on
 mx %00                    ; a page of code? A long one, or one round the segment's end, is taken to be.
 lda jit_cx
 beq jh_pure               ; (nothing was written)
 cmp #$0401
 bcs jh_bump
 lda rDI
 cmp jit_di
 beq jh_bump
 bcs :up
 sta tmp4                  ; (down: the new DI is the lower)
 lda jit_di
 bra :hi
:up
 lda jit_di
 sta tmp4
 lda rDI
:hi
 clc
 adc #2
 bcs jh_bump
 sta tmp5
 lda tmp4
 sec
 sbc #2
 bcc jh_bump
 sta tmp4
 jsl JIT_RT+12             ; jt_enter_r
 jmp jit_ret
jh_iret
 mx %00
 lda rCS
 cmp jit_sv+4
 beq jh_pure
 bra jh_bump
jh_back
 mx %00
 cpy jtmp2
 bne jh_bump
 lda rCS
 cmp jit_sv+4
 bne jh_bump
 lda jEP
 cmp jSV
 bne jh_bump
 lda jit_sb                ; (the piece's bank of code: each has the routines)
 bne :second
 jsl JIT_RT+9              ; jt_resume
 jmp jit_ret
:second
 jsl JIT_RT2+9
 jmp jit_ret
jh_any
 mx %00
 lda jCLN
 bne jh_stack
jh_bump
 mx %00
 jsl JIT_RT+15             ; jt_enter_b
 jmp jit_ret
jh_stack
 mx %00
 jsl JIT_RT+3              ; jt_enter_s
 jmp jit_ret
jh_pure
 mx %00
 jsl JIT_RT+6              ; jt_enter_n
 jmp jit_ret
