*----------------------------------------------------------
* cpu.s - the interpreter loop and its helpers.
*
* Conventions (BOOTSTRAP.md section 5): native mode, M=0
* X=0 at fetch and at retire, D = GUEST_DP, DBR = K = CORE,
* Y = IP. A handler ends with JMP (NEXTVEC): normally
* `next`, which counts the slot and falls into `fetch`; the
* harness points it at step_done. A prefix handler JMPs
* fetch directly, so a prefixed instruction retires as one,
* and points the vector at `next_pfx` first: only an
* instruction that had a prefix pays for clearing them.
* vnext0 is the vector an unprefixed instruction retires
* through (whoever sets vNEXT for a run sets it too).
*----------------------------------------------------------
 err NEXTVEC-GUEST_DP-vNEXT
 err HALTVEC-GUEST_DP-vHALTVEC

*--- retire, then fetch and dispatch the next instruction
next
 mx %00
 dec vSLOT
 bne fetch
 jmp slot
* next_pfx - the instruction had a prefix: clear them, put
* the vector back and retire.
next_pfx
 mx %00
 stz vSEGOVR
 stz vOVR
 stz vREP
 lda vnext0
 sta vNEXT
 jmp (NEXTVEC)
vnext0 dw next
* next_trace - `next` with vTRACE set (run_guest): record CS,
* IP(Y), opcode byte, FLAGS to the ring.
next_trace
 mx %00
 jsr flags_get
 sta tmp5
 ldx vTRPTR
 lda rCS
 sta >TRACE_BASE,x
 tya
 sta >TRACE_BASE+2,x
 lda [bCS],y              ; the upcoming opcode (low byte)
 and #$00FF
 sta >TRACE_BASE+4,x
 lda tmp5                 ; log FLAGS (the ZF after compares)
 sta >TRACE_BASE+6,x
 txa
 clc
 adc #8
 cmp #TRACE_LEN           ; wrapping ring
 bcc :keep
 lda #0
:keep
 sta vTRPTR
 bra next
fetch
 mx %00
 lda [bCS],y
 iny
 and #$00FF
 asl
 tax
 jmp (optab,x)

*--- every SLOT_N instructions: the counters; later the VBL
* tick, the keyboard and interrupt delivery.
slot
 mx %00
 lda #SLOT_N
 sta vSLOT
 lda vICOUNT
 clc
 adc #SLOT_N
 sta vICOUNT
 bcc :nc
 inc vICOUNT+2
:nc
 lda vPCMODE               ; running a PC program?
 bne :pc
 jmp fetch                 ; bench: no services
:pc
 cmp #2                    ; Mode B: the interrupt lines, looked at EVERY slot
 bne :vbl                  ; (not only on the VBL edge) so they reach the guest's
 lda rFL                   ; handlers promptly. do_int clears IF, so delivery
 and #F_IF                 ; self-serializes with the handler; interrupts off ->
 beq :vbl                  ; hold them (vTICK counts the IRQ0s owed).
 lda vTICK                 ; IRQ0: the DOC timer oscillator wrapped (sound.s)
 beq :kbd
 lda >PIC_MASK             ; held back at the 8259: it stays owed
 lsr
 bcs :kbd
 dec vTICK                 ; (one instruction: the interrupt cannot split it)
 sty rIP
 lda >PIC_BASE
 jsr do_int                ; INT 08h, or where the guest moved IRQ0
 jmp fetch
:kbd                       ; IRQ1: a queued keyboard scancode
 lda >KBD_QHEAD
 and #KBD_QMASK
 cmp >KBD_QTAIL
 beq :fdc                  ; scancode queue empty
 lda >PIC_MASK
 and #$0002
 bne :fdc
 sty rIP
 lda >PIC_BASE
 inc
 jsr do_int                ; INT 09h (IRQ1): the guest handler reads port 0x60
 jmp fetch
:fdc                       ; IRQ6: the diskette controller finished (ports.s)
 lda >PIC_IRQ6
 beq :vbl
 lda >PIC_MASK
 and #$0040
 bne :vbl
 lda #0
 sta >PIC_IRQ6
 sty rIP
 lda >PIC_BASE
 clc
 adc #6
 jsr do_int                ; INT 0Eh
 jmp fetch
:vbl                       ; once-a-frame services, on entering the vertical blank
 lda >VBLBAR
 and #$0080
 cmp vVBL
 beq :fetch
 sta vVBL
 tax                       ; (STA sets no flags) one edge a frame, not both
 beq :fetch
 sty rIP
 jsl SVC_BASE+15           ; svc_vbl: keyboard poll, screen flush, the Mode A tick
 ldy rIP
:fetch
 jmp fetch

*--- an instruction that can turn interrupts on retires here (Mode B).
* The slot looks every SLOT_N instructions, and a loop whose length
* divides SLOT_N meets it at the same instruction every time. When that
* one is inside a BIOS stub (IF is clear from the INT to its IRET) no
* interrupt was ever delivered: a program polling INT 1Ah for the tick it
* was waiting for waited for ever. So with an IRQ owed the slot looks at
* once after IRET and POPF, and after STI one instruction later, which is
* when the 8088 takes it.
irq_sti
 mx %00
 lda #2
 bra irq_chk
irq_soon
 mx %00
 lda #1
irq_chk
 mx %00
 ldx vPCMODE
 cpx #2
 bne :no
 ldx vTICK                 ; IRQ0
 bne :yes
 tax
 lda >PIC_IRQ6             ; IRQ6
 bne :some
 lda >KBD_QHEAD            ; IRQ1
 and #KBD_QMASK
 cmp >KBD_QTAIL
 beq :no
:some
 txa
:yes
 sta vSLOT
:no
 jmp (NEXTVEC)

*--- prefixes: note it and fetch the next byte
op_26
 mx %00
 lda #bES
 sta vSEGOVR
 lda #$8000
 sta vOVR
 lda #next_pfx
 sta vNEXT
 jmp fetch
op_2E
 mx %00
 lda #bCS
 sta vSEGOVR
 lda #$8000
 sta vOVR
 lda #next_pfx
 sta vNEXT
 jmp fetch
op_36
 mx %00
 lda #bSS
 sta vSEGOVR
 lda #$8000
 sta vOVR
 lda #next_pfx
 sta vNEXT
 jmp fetch
op_3E
 mx %00
 lda #bDS
 sta vSEGOVR
 lda #$8000
 sta vOVR
 lda #next_pfx
 sta vNEXT
 jmp fetch
op_F0                      ; LOCK
 mx %00
 jmp fetch
op_F2                      ; REPNE
 mx %00
 lda #$F2
 sta vREP
 lda #next_pfx
 sta vNEXT
 jmp fetch
op_F3                      ; REP / REPE
 mx %00
 lda #$F3
 sta vREP
 lda #next_pfx
 sta vNEXT
 jmp fetch

*--- ModR/M: fetch the byte and dispatch to its routine
* (gen/eatab.s), which sets vREGOFF and pEA (vEA too for a
* memory operand) and returns to our caller.
modrm_b
 mx %00
 lda [bCS],y
 iny
 and #$00FF
 sta vMODRM
 asl
 tax
 jmp (eatab_b,x)
modrm_w
 mx %00
 lda [bCS],y
 iny
 and #$00FF
 sta vMODRM
 asl
 tax
 jmp (eatab_w,x)

*--- effective-address tails, for the routines modrm_b and
* modrm_w reach (gen/eatab.s, eab_xx and eaw_xx) and for a
* handler with an offset of its own. On entry A = vEA = the
* offset; X becomes the DP offset of the segment base after
* the override (kept in vEASEG for ea_plus2); pEA = base +
* offset, wrapped to the guest's 1 MiB. A base's bank word is
* the host's already (set_ds), so only a carry out of the low
* word needs the wrap worked out.
ea_ds_b
 mx %00
 ldx vSEGOVR
 bne ea_seg_b
 ldx #bDS
 bra ea_seg_b
ea_ss_b
 mx %00
 ldx vSEGOVR
 bne ea_seg_b
 ldx #bSS
ea_seg_b
 mx %00
 stx vEASEG
 clc
 adc 0,x
 sta pEA
 lda 2,x
 bcs ea_carry
 sta pEA+2
 cmp #^H_TXT
 beq vid_mark
 rts
ea_carry                   ; A = the base's bank word, C set
 mx %00
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pEA+2
 cmp #^H_TXT
 beq vid_mark
 rts

* Word operands: an offset of $FFFF wraps within the
* segment (second byte at offset 0), so that case goes
* through a bounce word in the direct page.
ea_ds_w
 mx %00
 ldx vSEGOVR
 bne ea_seg_w
 ldx #bDS
 bra ea_seg_w
ea_ss_w
 mx %00
 ldx vSEGOVR
 bne ea_seg_w
 ldx #bSS
ea_seg_w
 mx %00
 stx vEASEG
 cmp #$FFFF
 beq ea_split
 clc
 adc 0,x
 sta pEA
 lda 2,x
 bcs ea_carry
 sta pEA+2
 cmp #^H_TXT
 beq vid_mark
 rts

*--- the rare ways out of a fast EA routine (gen/eatab.s,
* emb_xx and emw_xx: the tail is inline there, with the
* default segment's base as a direct operand). X is the
* handler's ModR/M index and is kept.
efb_ovr                    ; a segment override: A = the offset
 mx %00
 phx
 ldx vSEGOVR
 jsr ea_seg_b
 plx
 rts
efw_ovr
 mx %00
 phx
 ldx vSEGOVR
 jsr ea_seg_w
 plx
 rts
efw_split_ds               ; a word at offset $FFFF
 mx %00
 phx
 ldx #bDS
 jsr ea_split
 plx
 rts
efw_split_ss
 mx %00
 phx
 ldx #bSS
 jsr ea_split
 plx
 rts
ef_carry                   ; A = the base's bank word, C set
 mx %00
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pEA+2
 cmp #^H_TXT
 beq ef_vid
 rts
ef_vid                     ; the operand is in the text buffer's bank
 mx %00
 phx
 jsr vid_mark
 plx
 rts
* vid_mark - the operand is in the text buffer's bank: note its
* 256-byte page for the next screen flush (a read marks too; harmless).
vid_mark
 mx %00
 lda vPCMODE               ; only in PC mode: the vector harness uses bank $05
 bne :go
 rts
:go
 lda pEA
 bra vid_mark_a
vid_mark_dst
 mx %00
 lda vPCMODE
 bne :go2
 rts
:go2
 lda pDST
vid_mark_a
 mx %00
 and #$3F00                ; 64 pages: the full 16 KB B800 bank (CGA graphics).
 xba                       ; text writes fall in pages 0-15 as before.
 tax
 sep #$20
 mx %10
 lda #1
 sta >VID_DIRTY,x
 rep #$20
 mx %00
 rts
ea_split
 mx %00
 lda 0,x                   ; seg:FFFF
 clc
 adc #$FFFF
 sta pSPLIT
 lda 2,x
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pSPLIT+2
 lda 0,x                   ; seg:0000
 sta pTMP
 lda 2,x
 sta pTMP+2
 sep #$20
 mx %10
 lda [pSPLIT]
 sta vBOUNCE
 lda [pTMP]
 sta vBOUNCE+1
 rep #$20
 mx %00
 lda #GUEST_DP+vBOUNCE
 sta pEA
 stz pEA+2
 lda vNEXT
 sta vNEXT2
 lda #split_retire
 sta vNEXT
 rts
* ea_plus2 - pEA for the word at vEA+2 in the same segment (the
* segment half of a far pointer), wrapping within the segment.
ea_plus2
 mx %00
 lda vEA
 inc
 inc
 sta vEA
 ldx vEASEG
 jmp ea_seg_w

split_retire               ; write the bounce word back, then retire
 mx %00
 sep #$20
 mx %10
 lda vBOUNCE
 sta [pSPLIT]
 lda vBOUNCE+1
 sta [pTMP]
 rep #$20
 mx %00
 lda vNEXT2
 sta vNEXT
 jmp (NEXTVEC)

*--- segment bases: bXX = GUEST_BASE + (seg << 4), as lo16
* and a bank word, wrapped to 20 bits.
set_es
 mx %00
 lda rES
 asl
 asl
 asl
 asl
 sta bES
 lda rES
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 ora #GUEST_BANK
 sta bES+2
 rts
set_cs
 mx %00
 lda rCS
 asl
 asl
 asl
 asl
 sta bCS
 lda rCS
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 ora #GUEST_BANK
 sta bCS+2
 rts
set_ss
 mx %00
 lda rSS
 asl
 asl
 asl
 asl
 sta bSS
 lda rSS
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 ora #GUEST_BANK
 sta bSS+2
 rts
set_ds
 mx %00
 lda rDS
 asl
 asl
 asl
 asl
 sta bDS
 lda rDS
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 ora #GUEST_BANK
 sta bDS+2
 rts
set_seg_x                  ; X = sreg number * 2 (ES CS SS DS)
 mx %00
 jmp (setseg_tab,x)
setseg_tab da set_es,set_cs,set_ss,set_ds
set_all_bases
 mx %00
 jsr set_es
 jsr set_cs
 jsr set_ss
 jmp set_ds

*--- stack: push16 pushes A at SS:SP-2; pop16 returns the
* word at SS:SP and adds 2. Both preserve X and Y. SP = $FFFF
* splits the word across SS:FFFF and SS:0000.
push16
 mx %00
 sta tmp4
 lda rSP
 dec
 dec
 sta rSP
 cmp #$FFFF
 beq :split
 clc
 adc bSS
 sta pSTK
 lda bSS+2
 bcs :carry
:bank
 sta pSTK+2
 lda tmp4
 sta [pSTK]
 rts
:carry
 jsr stk_carry
 bra :bank
:split
 jsr stk_split
 sep #$20
 mx %10
 lda tmp4
 sta [pSTK]
 lda tmp4+1
 sta [pSTK2]
 rep #$20
 mx %00
 rts
pop16
 mx %00
 lda rSP
 cmp #$FFFF
 beq :split
 clc
 adc bSS
 sta pSTK
 lda bSS+2
 bcs :carry
:bank
 sta pSTK+2
 lda rSP
 inc
 inc
 sta rSP
 lda [pSTK]
 rts
:carry
 jsr stk_carry
 bra :bank
:split
 jsr stk_split
 lda rSP
 inc
 inc
 sta rSP
 sep #$20
 mx %10
 lda [pSTK]
 sta tmp4
 lda [pSTK2]
 sta tmp4+1
 rep #$20
 mx %00
 lda tmp4
 rts
stk_carry                  ; A = bSS's bank word, C set: the bank past a carry
 mx %00
 adc #0
 and #$000F
 ora #GUEST_BANK
 rts
stk_split                  ; pSTK = SS:FFFF, pSTK2 = SS:0000
 mx %00
 lda bSS
 clc
 adc #$FFFF
 sta pSTK
 lda bSS+2
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pSTK+2
 lda bSS
 sta pSTK2
 lda bSS+2
 sta pSTK2+2
 rts

*--- do_int: A = vector. rIP holds the return IP (the caller
* stored Y there). Pushes FLAGS, CS, IP; clears IF and TF;
* loads CS:IP from the IVT. Y = the new IP on return.
do_int
 mx %00
 sta tmp6
 jsr flags_get
 jsr push16
 lda rFL
 and #$FCFF
 sta rFL
 lda rCS
 jsr push16
 lda rIP
 jsr push16
 lda tmp6
 asl
 asl
 sta pSTK
 lda #GUEST_BANK
 sta pSTK+2
 ldy #2
 lda [pSTK],y
 sta rCS
 jsr set_cs
 lda [pSTK]
 tay
 rts

*--- unimplemented or undefined: count it and move on
op_bad
 mx %00
 inc vBAD
 jmp (NEXTVEC)
