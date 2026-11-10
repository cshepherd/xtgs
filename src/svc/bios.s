*----------------------------------------------------------
* bios.s - the hypercall dispatcher and the BIOS services:
* INT 10h (video), 11h, 12h, 16h (keyboard), 1Ah (time),
* 29h (fast console out). Handlers read and write the guest
* registers in the direct page; flags that an IRET will
* restore are set in the stacked FLAGS word.
*----------------------------------------------------------
stop_flag  dw 0
exit_code  dw 0
cur_vec    dw 0

* svc_hypercall - A = number. 0-255: interrupt vector stub;
* 256 up: the shared drive's calls (rd_tab).
* Returns C=1 to stop the program with A = exit code.
svc_hypercall
 mx %00
 phb
 phk
 plb
 stz stop_flag
 cmp #256
 bcs :redir
 sta cur_vec
 ldx rd_early              ; DOS boots from the shared folder: its INT 21h
 beq :call                 ; is hooked from here, at once (rd_poll)
 jsr rd_poll
 lda cur_vec
:call
 asl
 tax
 jsr (int_tab,x)
 lda stop_flag
 bne :stop
:cont
 plb
 clc
 rtl
:stop
 lda exit_code
 plb
 sec
 rtl
:redir                     ; 256..: the shared drive's (redir.s)
 sec
 sbc #256
 cmp #RD_NCALLS
 bcs :cont
 asl
 tax
 jsr (rd_tab,x)
 bra :cont

* int_default - an unserviced vector: note it, return (IRET)
int_default
 mx %00
 lda cur_vec
note_unhandled             ; A = vector; AH goes in the high byte
 mx %00
 and #$00FF
 sta sv8
 lda rAX
 and #$FF00
 ora sv8
 sta sv8
 lda >DIAG_UNHN
 inc
 sta >DIAG_UNHN
 lda >DIAG_UNH
 cmp #$FFFF
 bne :maps
 lda sv8
 sta >DIAG_UNH
:maps
 lda sv8                   ; INT 21h: bit AH in the function map;
 and #$00FF                ; else bit n in the vector map
 cmp #$21
 bne :vec
 lda sv8
 xba
 and #$007F
 ldx #DIAG_FNMAP
 bra :setbit
:vec
 ldx #DIAG_INTMAP
:setbit                    ; A = bit number, X = map base (low 16 of a bank-5 address)
 stx sv9
 pha
 lsr
 lsr
 lsr
 clc
 adc sv9
 tax
 pla
 and #$0007
 tay
 lda diag_bits,y
 and #$00FF
 sta sv9
 lda >RES_BASE,x
 and #$00FF
 ora sv9
 sep #$20
 mx %10
 sta >RES_BASE,x
 rep #$20
 mx %00
 rts
diag_bits hex 0102040810204080

*--- stacked FLAGS (SS:SP+4 inside an INT stub)
stk_flags                  ; pGST -> the pushed FLAGS word
 mx %00
 lda rSP
 clc
 adc #4
 clc
 adc bSS
 sta pGST
 lda bSS+2
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pGST+2
 rts
set_cf
 mx %00
 jsr stk_flags
 lda [pGST]
 ora #F_CF
 sta [pGST]
 rts
clr_cf
 mx %00
 jsr stk_flags
 lda [pGST]
 and #$FFFF-F_CF
 sta [pGST]
 rts
set_zf
 mx %00
 jsr stk_flags
 lda [pGST]
 ora #F_ZF
 sta [pGST]
 rts
clr_zf
 mx %00
 jsr stk_flags
 lda [pGST]
 and #$FFFF-F_ZF
 sta [pGST]
 rts

*--- gptr: A = offset, X = DP offset of a segment base -> pGST
gptr
 mx %00
 clc
 adc 0,x
 sta pGST
 lda 2,x
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pGST+2
 rts

*--- svc_set_es: recompute ES's host base after writing rES
svc_set_es
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

svc_set_ds
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

*--- register halves
ah_val                     ; A = AH
 mx %00
 lda rAX
 xba
 and #$00FF
 rts
set_al                     ; AL = A (low byte)
 mx %00
 sep #$20
 mx %10
 sta rAX
 rep #$20
 mx %00
 rts
set_ah                     ; AH = A (low byte)
 mx %00
 sep #$20
 mx %10
 sta rAX+1
 rep #$20
 mx %00
 rts

*=== INT 10h: video =========================================
int_10
 mx %00
 jsr ah_val
 cmp #$14
 bcs :unk
 asl
 tax
 jmp (v10_tab,x)
:unk
 lda #$10
 jmp note_unhandled
v10_tab da v10_00,v10_01,v10_02,v10_03,v10_nop,v10_nop,v10_06,v10_07
 da v10_08,v10_09,v10_0A,v10_0B,v10_nop,v10_nop,v10_0E,v10_0F
 da v10_nop,v10_nop,v10_nop,v10_13
v10_nop
 mx %00
 rts
v10_00                     ; set mode: text, or CGA 320 graphics (4/5)
 mx %00
 lda rAX
 and #$007F
 sta sv8
 sep #$20
 mx %10
 lda sv8
 sta >H_BDA+BDA_VMODE
 rep #$20
 mx %00
 lda sv8
 jsr vid_setmode
 rts
v10_01                     ; cursor shape
 mx %00
 lda rCX
 sta >H_BDA+BDA_CURSHP
 rts
v10_02                     ; set cursor position (page ignored)
 mx %00
 lda rDX
 sta >H_BDA+BDA_CURPOS
 rts
v10_03                     ; get cursor position and shape
 mx %00
 lda >H_BDA+BDA_CURPOS
 sta rDX
 lda >H_BDA+BDA_CURSHP
 sta rCX
 rts
v10_06                     ; scroll window up
 mx %00
 stz sv6
 bra scroll_args
v10_07                     ; scroll window down
 mx %00
 lda #1
 sta sv6
scroll_args
 mx %00
 lda rAX
 and #$00FF
 sta sv0                   ; lines
 lda rBX
 and #$FF00
 ora #$0020
 sta sv1                   ; blank word
 lda rCX
 xba
 and #$00FF
 sta sv2                   ; top
 lda rCX
 and #$00FF
 sta sv3                   ; left
 lda rDX
 xba
 and #$00FF
 sta sv4                   ; bottom
 lda rDX
 and #$00FF
 sta sv5                   ; right
 jmp vid_scroll_win
v10_08                     ; read char/attr at the cursor
 mx %00
 lda >H_BDA+BDA_CURPOS
 jsr cell_off
 clc
 adc #$8000
 tax
 lda >H_TXTBANK,x
 sta rAX
 rts
v10_09                     ; write char + attr CX times at the cursor
 mx %00
 lda rBX
 and #$00FF
 xba
 sta sv0
 lda rAX
 and #$00FF
 ora sv0
 sta sv0                   ; the cell word
 lda >H_BDA+BDA_CURPOS
 jsr cell_off
 clc
 adc #$8000
 tax
 ldy rCX
 beq :done
:w
 lda sv0
 sta >H_TXTBANK,x
 inx
 inx
 cpx #$8000+TXT_LEN
 bcs :done
 dey
 bne :w
:done
 jmp mark_run
v10_0A                     ; write char only CX times at the cursor
 mx %00
 lda >H_BDA+BDA_CURPOS
 jsr cell_off
 clc
 adc #$8000
 tax
 ldy rCX
 beq :done
 sep #$20
 mx %10
 lda rAX
:w
 sta >H_TXTBANK,x
 inx
 inx
 cpx #$8000+TXT_LEN
 bcs :d8
 dey
 bne :w
:d8
 rep #$20
 mx %00
:done
 jmp mark_run
* mark_run - CX cells from the cursor were written: its row is
* dirty, or every row when the run goes past the end of the line.
mark_run
 mx %00
 lda >H_BDA+BDA_CURPOS
 and #$00FF
 clc
 adc rCX
 bcs :all
 cmp #81
 bcs :all
 lda >H_BDA+BDA_CURPOS
 xba
 and #$00FF
 jmp mark_row
:all
 jmp mark_all
v10_0B                     ; set palette: BH=0 background (BL 0-15),
 mx %00                    ; BH=1 palette select (BL bit 0). CGA graphics.
 lda rBX
 xba
 and #$00FF                ; BH
 bne :pal
 lda rBX                   ; BH=0: background colour
 and #$000F
 sta cga_bg
 bra :mark
:pal
 lda rBX                   ; BH=1: palette 0/1
 and #$0001
 sta cga_pal
:mark
 lda #1
 sta cga_pd
 rts
v10_0E                     ; teletype AL
 mx %00
 lda rAX
 and #$00FF
 jsr cap_putc
 lda rAX
 jmp vid_tty
v10_0F                     ; get mode: AL = mode, AH = columns, BH = page
 mx %00
 lda >H_BDA+BDA_VMODE
 and #$00FF
 ora #80*256
 sta rAX
 lda rBX
 and #$00FF
 sta rBX
 rts
v10_13                     ; write string ES:BP, CX chars, at DH/DL, BL attr,
 mx %00                    ; AL bit 0: leave the cursor after it; bit 1: attrs inline
 lda >H_BDA+BDA_CURPOS
 sta sv7                   ; saved cursor
 lda rDX
 sta >H_BDA+BDA_CURPOS
 lda rBX
 and #$00FF
 sta tty_attr
 lda rCX
 sta sv6                   ; remaining
 ldx #bES
 lda rBP
 jsr gptr
:ch
 lda sv6
 beq :end
 dec sv6
 lda [pGST]
 and #$00FF
 pha
 lda rAX
 and #$0002
 beq :one
 lda [pGST]
 xba
 and #$00FF
 sta tty_attr
 inc pGST
:one
 inc pGST
 pla
 jsr vid_tty
 bra :ch
:end
 lda #$FFFF
 sta tty_attr
 lda rAX
 and #$0001
 bne :keep
 lda sv7
 sta >H_BDA+BDA_CURPOS
:keep
 rts

*=== INT 11h, 12h, 1Ah, 29h ==================================
int_11
 mx %00
 lda >H_BDA+BDA_EQUIP
 sta rAX
 rts
int_12
 mx %00
 lda >H_BDA+BDA_MEMKB
 sta rAX
 rts
int_1A
 mx %00
 jsr ah_val
 bne :n0
 lda >H_BDA+BDA_TICKS
 sta rDX
 lda >H_BDA+BDA_TICKS+2
 sta rCX
 sep #$20
 mx %10
 lda >H_BDA+BDA_MIDNT      ; midnights since the last call, and no more
 sta rAX
 lda #0
 sta >H_BDA+BDA_MIDNT
 rep #$20
 mx %00
 rts
:n0
 cmp #1
 bne :n1
 lda rDX
 sta >H_BDA+BDA_TICKS
 lda rCX
 sta >H_BDA+BDA_TICKS+2
 sep #$20
 mx %10
 lda #0
 sta >H_BDA+BDA_MIDNT
 rep #$20
 mx %00
 jmp clk_mark              ; the guest's own time: kept, at the clock's rate
:n1
 cmp #2
 bne :n2
 jsr clk_rtctime           ; the IIGS's clock (clock.s)
 jmp clr_cf
:n2
 cmp #4
 bne :n4
 jsr clk_rtcdate
 jmp clr_cf
:n4
 cmp #3                    ; set the time, set the date: the IIGS's clock
 beq :ro                   ; is not the guest's to set. Taken and dropped.
 cmp #5
 bne :unk
:ro
 jmp clr_cf
:unk
 jsr set_cf
 lda #$1A
 jmp note_unhandled
* INT 15h: only the joystick (AH=84h), and that with nothing
* attached. GW-BASIC asks for the buttons on every timer tick;
* left unserviced, AL kept whatever it held and read as buttons.
* Everything else is the XT's answer: CF set, AH=86h.
int_15
 mx %00
 jsr ah_val
 cmp #$84
 bne :unk
 lda rDX
 beq :btn
 cmp #1
 bne :unk
 stz rAX                   ; positions: all four axes 0 (no adapter)
 stz rBX
 stz rCX
 stz rDX
 jmp clr_cf
:btn
 lda #$F0                  ; switches in bits 4-7, 1 = not pressed
 jsr set_al
 jmp clr_cf
:unk
 lda #$86
 jsr set_ah
 jmp set_cf
int_29                     ; fast console out AL
 mx %00
 lda rAX
 and #$00FF
 jmp con_out

*=== INT 16h: keyboard =======================================
int_16
 mx %00
 jsr ah_val
 and #$00EF                ; 1x = enhanced forms of 0x
 beq :read
 cmp #1
 beq :peek
 cmp #2
 beq :shift
 cmp #5
 beq :push
 rts                       ; 03 typematic etc.: nothing
:read
 lda vPCMODE
 cmp #2
 beq :readb
 jsr kb_wait
 sta rAX
 rts
* Mode B: waiting here would stop the guest's interrupts (the
* IRQ0 timer above all) while a prompt sits idle. Wait only
* until there is a key or an interrupt to deliver; for an
* interrupt, go back to this stub's hypercall with interrupts on
* (the PC BIOS's STI-and-loop) and have the slot look at once.
:readb
 jsr kb_pop
 bcs :gotb
:idle
 jsr kb_poll
 jsr vbl_check
 jsr kb_pop
 bcs :gotb
 lda vTICK                 ; IRQ0 owed?
 bne :again
 lda >KBD_QHEAD            ; IRQ1: a scancode queued?
 and #KBD_QMASK
 cmp >KBD_QTAIL
 beq :idle
:again
 lda rIP
 sec
 sbc #4                    ; FE 38 16 00
 sta rIP
 lda rFL
 ora #F_IF
 sta rFL
 lda #1
 sta vSLOT                 ; the slot runs before the next instruction
 rts
:gotb
 sta rAX
 rts
:peek
 jsr kb_peek
 bcc :none
 sta rAX
 jmp clr_zf
:none
 jsr kb_poll               ; give the IIGS keyboard a look first
 jsr vbl_check
 jsr kb_peek
 bcc :really
 sta rAX
 jmp clr_zf
:really
 jmp set_zf
:shift
 lda >H_BDA+BDA_KBFLAG
 and #$00FF
 sta rAX
 rts
:push
 lda rCX
 jsr kb_push
 lda #0
 jmp set_al
