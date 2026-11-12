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
 bcs :ms
 asl
 tax
 jsr (rd_tab,x)
 bra :cont
:ms                        ; then the mouse driver's (mouse.s)
 sbc #RD_NCALLS
 cmp #MS_NCALLS
 bcs :xms
 asl
 tax
 jsr (ms_calls,x)
 bra :cont
:xms                       ; then the XMS driver's (xms.s)
 sbc #MS_NCALLS
 cmp #XMS_NCALLS
 bcs :cont
 asl
 tax
 jsr (xms_calls,x)
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
 lda gfx_mode
 cmp #GFX_EGA
 beq :ega
 txa
 jmp (v10_tab,x)
:unk
 lda #$10
 jmp note_unhandled
* mode 0Dh has eight pages, each with its cursor: BH is the page for
* the cursor's functions, the character's and the string's; the rest
* (the scroll, the teletype) work on the page shown
:ega
 lda >H_BDA+BDA_PAGE
 and #$0007
 sta eg_wpg
 cpx #$02*2
 beq :pg
 cpx #$03*2
 beq :pg
 cpx #$08*2
 beq :pg
 cpx #$09*2
 beq :pg
 cpx #$0A*2
 beq :pg
 cpx #$13*2
 beq :pg
 txa
 jmp (v10_tab,x)
:pg
 phx
 lda rBX
 xba
 jsr eg_curin
 inc eg_in
 plx
 txa
 jsr (v10_tab,x)
 stz eg_in
 jmp eg_curout
v10_tab da v10_00,v10_01,v10_02,v10_03,v10_nop,v10_05,v10_06,v10_07
 da v10_08,v10_09,v10_0A,v10_0B,v10_0C,v10_0D,v10_0E,v10_0F
 da v10_10,v10_11,v10_12,v10_13
v10_nop
 mx %00
 rts
v10_05                     ; select the page: mode 0Dh has eight
 mx %00
 lda gfx_mode
 cmp #GFX_EGA
 bne :tdy
 lda rAX
 jmp eg_setpage
:tdy
 lda >TDY_ON               ; a Tandy: AL = 80h-83h, the page register's two
 beq :out
 jmp tdy_05
:out
 rts
v10_10                     ; the EGA's palette registers (mode 0Dh)
 mx %00
 lda gfx_mode
 cmp #GFX_EGA
 bne :tdy
 jmp eg_10
:tdy
 lda >TDY_ON               ; a Tandy: its array's
 beq :out
 jmp tdy_10
:out
 rts
v10_11                     ; the EGA's character generator: AL=30h, where
 mx %00                    ; the font is
 lda eg_none
 bne v10_noega
 jmp eg_11
v10_12                     ; BL=10h: the EGA's description
 mx %00
 lda eg_none
 bne v10_noega
 jmp eg_12
v10_noega                  ; (VIDEO=CGA: a CGA's BIOS has neither)
 rts
v10_00                     ; set mode: text, or CGA graphics (4/5, 6)
 mx %00
 lda rAX
 and #$0080                ; bit 7: the screen is not cleared (acted on
 sta eg_keep               ; in mode 0Dh)
 lda rAX
 and #$007F
 sta sv8
 cmp #GFX_EGA
 bne :mode
 lda eg_none               ; no EGA: 0Dh is no mode
 bne v10_noega
:mode
 sep #$20
 mx %10
 lda sv8
 sta >H_BDA+BDA_VMODE
 rep #$20
 mx %00
 ldx #80                   ; the BDA's columns: 40 in the 320 modes, where
 lda sv8                   ; the text services draw 40 (gtext.s). (Modes 0
 cmp #4                    ; and 1 are shown as 80-column text and say so.)
 beq :c40
 cmp #GFX_EGA
 beq :c40
 cmp #5
 beq :c40
 cmp #GFX_TDY8             ; (a Tandy's 160x200 in 16 colours: 20)
 bne :t9
 lda >TDY_ON
 beq :cols
 ldx #20
 bra :cols
:t9
 cmp #GFX_TDY9             ; (and its 320x200)
 bne :cols
 lda >TDY_ON
 beq :cols
:c40
 ldx #40
:cols
 txa
 sta >H_BDA+BDA_COLS
 lda #0
 sta >H_BDA+BDA_CURPOS     ; the cursor home in every mode
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
 jsr gt_on
 beq :text
 jsr gt_read               ; graphics: the character the pixels spell
 sep #$20
 mx %10
 sta rAX
 rep #$20
 mx %00
 rts
:text
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
 jsr gt_on
 beq :text
 jmp gt_write              ; graphics: drawn, BL the colour
:text
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
 jsr gt_on
 beq :text
 jmp gt_write              ; graphics: as 09h
:text
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
v10_0B                     ; the colour-select register (3D9h): BH=0 its
 mx %00                    ; bits 0-4 from BL (the background of modes 4
 lda gfx_mode              ; and 5, mode 6's colour, and bit 4 the bright
 cmp #GFX_EGA              ; three), BH=1 its bit 5 from BL's bit 0 (the
 bne :cga                  ; palette). The BDA's copy at 40:66 follows.
 jmp eg_0B                 ; mode 0Dh: the same of its palette registers
:cga
 lda rBX
 xba
 and #$00FF                ; BH
 bne :pal
 lda rBX
 and #$000F
 sta cga_bg
 ldx #0
 lda rBX
 and #$0010
 beq :int
 inx
:int
 stx cga_int
 lda rBX
 jsr tdy_0B                ; (a Tandy: the border, register 0 in 08h and 09h)
 bra :mark
:pal
 lda rBX                   ; BH=1: palette 0/1
 and #$0001
 sta cga_pal
:mark
 lda #1
 sta cga_pd
 jmp cga_bda66
v10_0C                     ; write pixel: AL at CX, DX (graphics only)
 mx %00
 jsr gt_on
 beq :out
 jmp gt_setpix
:out
 rts
v10_0D                     ; read pixel: AL = the one at CX, DX
 mx %00
 jsr gt_on
 beq :out
 jmp gt_getpix
:out
 rts
v10_0E                     ; teletype AL
 mx %00
 lda rAX
 and #$00FF
 jsr cap_putc
 jsr gt_on
 beq :text
 lda rBX                   ; graphics: BL is the colour
 and #$00FF
 sta tty_attr
 lda rAX
 jsr vid_tty
 lda #$FFFF
 sta tty_attr
 rts
:text
 lda rAX
 jmp vid_tty
v10_0F                     ; get mode: AL = mode, AH = columns, BH = page
 mx %00
 lda >H_BDA+BDA_COLS
 xba
 and #$FF00
 sta sv0
 lda >H_BDA+BDA_VMODE
 and #$00FF
 ora sv0
 sta rAX
 sep #$20
 mx %10
 lda >H_BDA+BDA_PAGE
 sta rBX+1
 rep #$20
 mx %00
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
* INT 15h: only the joystick (AH=84h), which is the IIGS's
* (joystick.s): the buttons, and the paddles as they read. With
* none attached the buttons are up and the positions 0. GW-BASIC
* asks for the buttons on every timer tick; left unserviced, AL
* kept whatever it held and read as buttons.
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
 jsr joy_trig              ; positions: stick A's as the paddles read, no
 stz rAX                   ; stick B; all 0 with no adapter
 stz rBX
 stz rCX
 stz rDX
 lda >JOY_HAVE
 beq :nojoy
 lda >JOY_X
 sta rAX
 lda >JOY_Y
 sta rBX
:nojoy
 jmp clr_cf
:btn
 jsr joy_btn               ; switches in bits 4-7, 1 = not pressed
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
