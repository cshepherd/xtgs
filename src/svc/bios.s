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

* svc_hypercall - A = number. 0-255: interrupt vector stub.
* Returns C=1 to stop the program with A = exit code.
svc_hypercall
 mx %00
 phb
 phk
 plb
 stz stop_flag
 cmp #256
 bcs :cont
 sta cur_vec
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
 bne :done
 lda sv8
 sta >DIAG_UNH
:done
 rts

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
 da v10_08,v10_09,v10_0A,v10_nop,v10_nop,v10_nop,v10_0E,v10_0F
 da v10_nop,v10_nop,v10_nop,v10_13
v10_nop
 mx %00
 rts
v10_00                     ; set mode: text modes only; clear unless AL bit 7
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
 lda rAX
 and #$0080
 bne :noclear
 jsr vid_clear
:noclear
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
 jmp mark_all
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
 jmp mark_all
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
 lda #0
 jmp set_al
:n0
 cmp #1
 bne :n1
 lda rDX
 sta >H_BDA+BDA_TICKS
 lda rCX
 sta >H_BDA+BDA_TICKS+2
 rts
:n1
 cmp #2
 bne :n2
 lda #$1200                ; RTC time 12:00:00 (fixed until M3)
 sta rCX
 stz rDX
 jmp clr_cf
:n2
 cmp #4
 bne :unk
 lda #$1987                ; RTC date 1987-01-01
 sta rCX
 lda #$0101
 sta rDX
 jmp clr_cf
:unk
 jsr set_cf
 lda #$1A
 jmp note_unhandled
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
 jsr kb_wait
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
