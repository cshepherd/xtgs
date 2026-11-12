*----------------------------------------------------------
* tandy.s - the Tandy 1000's video: the page register, the
* video array and its three modes: 09h (320x200) and 08h
* (160x200) in 16 colours, 0Ah (640x200) in four
* (docs/tandy.md). The PC is one when XTGS.CMD says
* VIDEO=TANDY (rd_readcfg), and then it has no EGA.
*
* The Tandy's video memory is eight pages of 16K. The page
* register (3DFh) names the page the CPU has at B800 (an
* even one brings the next with it at BC00: 32K) and the
* page the screen shows. Here B800-BFFF is always what the
* CPU has: a write of the register moves 16K pieces between
* the window and where the other pages wait (the slots of
* src/include/pc.s; tdy_setpage), so the core's addresses
* are as they were and all it does for this is mark the
* 256s of the 32K it writes (VID_DIRTY, 128 of them).
*
* Mode 09h: a pixel is four bits, the left one a byte's high
* four, 160 bytes a line, and line y is in the 8K bank y & 3
* of the two pages shown, at (y >> 2) * 160. That is the
* SHR's 320 mode a byte for a byte: tdy_flush moves the
* lines whose 256s were written, or all 200 after the page
* register or the mode changed. The colours are the array's
* sixteen palette registers (each one of the CGA's sixteen),
* reached through the palette mask.
*
* Mode 08h: one page of 16K is shown, any of the eight (the
* page register's bits 0-2), laid out as the CGA's graphics
* are: 80 bytes a line, the even lines in the page's first 8K
* and the odd ones in its second. A byte is two pixels, each
* 1/160 of the line: tdy_flush8 writes each twice (tdy8_tab,
* gen/tdytab.s). The colours are mode 09h's.
*
* Mode 0Ah: 640x200 in four colours, in mode 09h's 32K and
* its four line banks. A line is eighty pairs of bytes, eight
* pixels a pair: the even byte holds the low bit of each
* pixel's colour and the odd byte the high bit. The SHR is in
* 640 mode for it, two bits a pixel: tdy_row weaves a pair
* into one of its words. The colours are palette registers
* 0-3, through the mask.
*
* The BIOS here: the mode set, the pages (05h, AL = 80h-83h),
* the palette (10h), the pixel (0Ch, 0Dh), and for gtext.s
* the character services' cell, glyph and scroll lines
* (tdy_cell, tdy_draw, tdy_read, tdys_copy, tdys_fill): 20
* columns in mode 08h, 40 in 09h and 80 in 0Ah, in the pages
* the CPU has. DBR=SVC.
*----------------------------------------------------------
TDY_WIN    = 6               ; the slots at B800 and BC00
TDY_NSLOT  = 9
tdy_cfg    dw 0              ; XTGS.CMD's VIDEO=TANDY (rd_readcfg)
tdy_where  ds 16             ; the slot each page is in (words)
tdy_held   ds 18             ; the page in each slot; $FFFF the one to spare
tdy_pald   dw 0              ; nonzero: a palette register or the mask changed
tdy_alld   dw 0              ; nonzero: the whole screen is to be drawn
tdy_nx     dw 0              ; the partial flush: the 8K's first row not yet drawn
tdy_moved  dw 0              ; tdy_setpage: a page was moved
tdy_off    dw 0              ; tdy_slot's answer
tdy_so     dw 0              ; tdy_move: the source
tdy_sb     dw 0
tdy_c      dw 0              ; tdy_setpage: the CPU's page
tdy_p      dw 0              ; tdy_bring: the page and the slot
tdy_t      dw 0
tdy_e      dw 0              ; tdy_evict: the slot, its page, the spare slot
tdy_q      dw 0
tdy_s      dw 0
tdy_t0     dw 0
tdy_w      dw 0              ; a pixel's bits and the mask of the others
tdy_m      dw 0
tdy_pm     dw 0              ; tdy_setpal: the bits of an entry's number that count
tdy_cy     dw 0              ; tdy_cell: the cell's first line
tdy_fw     dw 0              ; tdy_fillw: a scroll's filling bytes, a pair
tdy_ln     dw 0              ; tdy_lnoff's line
tdy_ntab   hex 000FF0FF      ; two font bits as two pixels of a byte
tdy_d0     dw 0              ; tdy_flush: the first page shown
tdy_bs     ds 8              ; and where each of the four line banks is: the
tdy_bb     ds 8              ; offset and the host bank
tdy_r0     hex 000103040608090B0C0E101113141618191B1C1E202123242628292B2C2E3031
tdy_r1     hex 0103040607090B0C0E0F1113141617191B1C1E1F2123242627292B2C2E2F3131
           dw 0

* tdy_setup - the PC is a Tandy 1000 (rd_readcfg, after the BDA and
* the BIOS's stubs): its two identifying bytes, no EGA, the pages
* where a text mode has them and the registers as its BIOS leaves them.
tdy_name asc 'Tandy'
tdy_setup
 mx %00
 jsr ega_off               ; no EGA: its banks hold the pages
 lda #1
 sta >TDY_ON
 lda #0
 sta >TDY_MOVES
 sep #$20
 mx %10
 lda #$FF
 sta >H_BIOS+$FFFE         ; the model byte, and the 21h a 1000's BIOS has
 lda #$21                  ; at F000:C000
 sta >H_BIOS+$C000
 ldx #4                    ; and its maker's name a little after, where a
:name                      ; program looks for it (Arkanoid: FC00:0000-0100)
 lda >tdy_name,x
 sta >H_BIOS+$C008,x
 dex
 bpl :name
 rep #$20
 mx %00
 ldx #0
 txa
:p
 sta tdy_where,x           ; pages 0-5 in slots 0-5
 sta tdy_held,x
 inc
 inx
 inx
 cpx #12
 bcc :p
 lda #8                    ; page 6 in slot 8, page 7 at B800 (text is
 sta tdy_where+12          ; there), nothing at BC00
 lda #6
 sta tdy_held+16
 sta tdy_where+14
 lda #7
 sta tdy_held+12
 lda #$FFFF
 sta tdy_held+14
 lda #$003F
 sta >TDY_PAGE
 jsr tdy_publish
 lda #3
 jmp tdy_regs

* tdy_publish - where the pages are, for whoever reads the results
* bank, and the page register's copy at 0040:008A
tdy_publish
 mx %00
 ldx #0
 ldy #0
 sep #$20
 mx %10
:l
 lda tdy_where,y
 sta >TDY_SLOT,x
 iny
 iny
 inx
 cpx #8
 bcc :l
 lda >TDY_PAGE
 sta >H_BDA+$8A
 rep #$20
 mx %00
 rts

* tdy_regs - the array as the BIOS leaves it after setting mode A: every
* colour through the mask, the palette 0-15, the mode register 16
* colours in modes 08h and 09h (14h) and four at 640 in mode 0Ah (0Ch)
tdy_regs
 mx %00
 pha
 ldx #0
 sep #$20
 mx %10
:z
 lda #0
 sta >TDY_REG,x
 inx
 cpx #16
 bcc :z
:pal
 txa
 and #$0F
 sta >TDY_REG,x
 inx
 cpx #32
 bcc :pal
 lda #$0F
 sta >TDY_REG+1
 rep #$20
 mx %00
 pla
 ldx #$0014
 cmp #GFX_TDY8
 beq :mr
 cmp #GFX_TDY9
 beq :mr
 ldx #$000C                ; (mode 0Ah: 640 across in four colours)
 cmp #GFX_TDYA
 bne :o
:mr
 txa
 sep #$20
 mx %10
 sta >TDY_REG+3
 rep #$20
 mx %00
:o
 lda #0
 sta >TDY_IDX
 lda #1
 sta tdy_pald
 rts

* tdy_modeset - vid_setmode, mode A: the array and the page register
* as the BIOS sets them (pages 6 and 7 for both in modes 09h and 0Ah,
* page 7 in mode 08h and the CGA's). Nothing unless the PC is a Tandy.
tdy_modeset
 mx %00
 pha
 lda >TDY_ON
 bne :on
 pla
 rts
:on
 lda 1,s
 jsr tdy_regs
 pla
 ldx #$003F
 cmp #9
 bcc :pg
 cmp #$0B
 bcs :pg
 ldx #$00F6
:pg
 txa                       ; (falls into tdy_setpage)

* tdy_setpage - the page register <- A. Bits 3-5 are the CPU's page:
* it is brought to B800, and when its number is even the next one to
* BC00; with an odd one nothing is at BC00 (the Tandy shows the same
* 16K there again). Bits 0-2 are the page shown, which tdy_flush
* finds wherever it is.
tdy_setpage
 mx %00
 and #$00FF
 cmp >TDY_PAGE
 bne :new
 rts
:new
 sta >TDY_PAGE
 lsr
 lsr
 lsr
 and #$0007
 sta tdy_c
 stz tdy_moved
 ldx #TDY_WIN
 jsr tdy_bring
 lda tdy_c
 lsr
 bcs :odd
 lda tdy_c
 inc
 ldx #TDY_WIN+1
 jsr tdy_bring
 bra :done
:odd
 lda #TDY_WIN+1
 jsr tdy_evict
:done
 jsr tdy_publish
 lda #1
 sta tdy_alld
 lda tdy_moved             ; B800 is other bytes now: a text screen or the
 beq :out                  ; CGA's graphics are drawn again from it
 lda gfx_mode
 bne :gfx
 jmp mark_all
:gfx
 cmp #7
 bcs :out
 ldx #0
 lda #$0101
:m
 sta >VID_DIRTY,x
 inx
 inx
 cpx #64
 bcc :m
:out
 rts

* tdy_bring - page A to slot X of the window. What the slot held goes
* to the spare slot first, and the slot the page leaves is the spare.
tdy_bring
 mx %00
 sta tdy_p
 stx tdy_t
 asl
 tay
 lda tdy_where,y
 cmp tdy_t
 bne :go
 rts
:go
 lda tdy_t
 jsr tdy_evict
 lda tdy_p
 asl
 tay
 lda tdy_where,y
 pha
 ldx tdy_t
 jsr tdy_move
 lda tdy_p
 asl
 tay
 lda tdy_t
 sta tdy_where,y
 asl
 tay
 lda tdy_p
 sta tdy_held,y
 pla
 asl
 tay
 lda #$FFFF
 sta tdy_held,y
 rts

* tdy_evict - the page in slot A to the spare slot; A is the spare then
tdy_evict
 mx %00
 sta tdy_e
 asl
 tay
 lda tdy_held,y
 cmp #$FFFF
 bne :has
 rts
:has
 sta tdy_q
 ldy #0
:f
 lda tdy_held,y
 cmp #$FFFF
 beq :sp
 iny
 iny
 cpy #TDY_NSLOT*2
 bcc :f
 rts                       ; (there is always one)
:sp
 tya
 lsr
 sta tdy_s
 tax
 lda tdy_e
 jsr tdy_move
 lda tdy_s
 asl
 tay
 lda tdy_q
 sta tdy_held,y
 asl
 tay
 lda tdy_s
 sta tdy_where,y
 lda tdy_e
 asl
 tay
 lda #$FFFF
 sta tdy_held,y
 rts

* tdy_slot - slot A: its offset in tdy_off, A = its host bank.
* Keeps Y.
tdy_slot
 mx %00
 cmp #8
 bcs :c8
 pha
 and #$0003
 xba
 asl
 asl
 asl
 asl
 asl
 asl
 sta tdy_off               ; (slot & 3) * 16K
 pla
 cmp #TDY_WIN
 bcs :b
 cmp #4
 bcs :c
 lda #^H_TDYA
 rts
:b
 lda #^H_TXTBANK
 rts
:c8
 lda #$8000
 sta tdy_off
:c
 lda #^H_TDYC
 rts

* tdy_move - the 16K of slot A to slot X
tdy_move
 mx %00
 phx
 jsr tdy_slot
 sta tdy_sb
 lda tdy_off
 sta tdy_so
 pla
 jsr tdy_slot
 sep #$20
 mx %10
 sta :mvn+1                ; destination bank
 lda tdy_sb
 sta :mvn+2                ; source bank
 rep #$20
 mx %00
 phb
 ldx tdy_so
 ldy tdy_off
 lda #$3FFF
:mvn
 dfb $54,$00,$00
 plb
 lda >TDY_MOVES
 inc
 sta >TDY_MOVES
 inc tdy_moved
 rts

* tdy_port - a write to port A, 3DAh-3DFh, value in tmp0: 3DAh chooses
* the array's register and 3DEh writes it; 3DFh is the page register.
tdy_port
 mx %00
 tax
 lda >TDY_ON
 bne :on
 rts
:on
 cpx #$03DA
 beq :idx
 cpx #$03DE
 beq :dat
 cpx #$03DF
 beq :page
 rts
:idx
 lda tmp0
 and #$001F
 sta >TDY_IDX
 rts
:page
 lda tmp0
 jmp tdy_setpage
:dat
 lda >TDY_IDX
 tax
 cmp #$0010
 bcs :pal                  ; 10h-1Fh: the palette
 cmp #1
 beq :pal                  ; the palette mask
 cmp #2
 beq :st                   ; the border (kept, not shown)
 cmp #3
 beq :mode
 rts
:mode
 lda #1                    ; the mode register: svc_vbl looks, as for 3D8h
 sta >CGA_MODECHG
 bra :st
:pal
 lda #1
 sta tdy_pald
:st
 sep #$20
 mx %10
 lda tmp0
 sta >TDY_REG,x
 rep #$20
 mx %00
 rts

* tdy_mode - apply_cgamode on a Tandy: the mode-control register
* (3D8h) or the array's mode register was written. Graphics with the
* array's 16 colours is mode 09h when 3D8h's bit 0 says 320 across and
* mode 08h, 160 across, without it; graphics with the array's four
* colours at 640 and 3D8h's 640 (bit 4) is mode 0Ah: each entered as
* memory is (C set: that is all). Anything else is the CGA's (C
* clear), and a text mode that is enabled ends any of the three.
tdy_mode
 mx %00
 lda >CGA_MODEREQ
 and #$0002
 beq :none
 lda >TDY_REG+3
 and #$0010
 beq :n16
 lda >CGA_MODEREQ
 and #$0001
 clc
 adc #GFX_TDY8
 bra :is
:n16
 lda >TDY_REG+3
 and #$0008
 beq :none
 lda >CGA_MODEREQ
 and #$0010
 beq :none
 lda #GFX_TDYA
:is
 cmp gfx_mode
 beq :done
 jsr tdy_show
:done
 sec
 rts
:none
 lda gfx_mode
 cmp #GFX_TDY8
 bcc :cga
 cmp #GFX_TDYA+1
 bcs :cga
 lda >CGA_MODEREQ
 and #$0002
 bne :gfx
 lda >CGA_MODEREQ
 and #$0008
 beq :done
 stz gfx_mode
 jsr init_shr
 jsr mark_all
 sec
 rts
:gfx
 stz gfx_mode
:cga
 clc
 rts

* tdy_enter - mode A, 08h, 09h or 0Ah (vid_setmode, after
* tdy_modeset): the window cleared unless eg_keep (all 32K: in mode
* 08h the CPU has the first 16K and the rest is nobody's), the SHR in
* 320 mode, or 640 for mode 0Ah.
tdy_enter
 mx %00
 pha
 cmp #GFX_TDYA
 bne :m16
 lda #$000F                ; mode 0Ah: 3Bh in 3D8h and 3Fh in 3D9h
 sta cga_bg
 lda #$003B
 bra :mc
:m16
 and #$0001                ; what the BIOS leaves in 3D8h: 2Ah, 2Bh
 ora #$002A
:mc
 sta >CGA_MODEREQ
 jsr cga_bda               ; (and in the BDA)
 lda eg_keep
 bne :show
 lda #0
 sta >H_TXT
 phb
 ldx #<H_TXT
 ldy #<H_TXT+2
 lda #$7FFD
 mvn H_TXTBANK,H_TXTBANK
 plb
:show
 pla
* tdy_show - the screen is mode A's from the next frame
tdy_show
 mx %00
 sta gfx_mode
 jsr shd_inval             ; the text pixels are gone
 ldx #0
 ldy #0                    ; 320 mode, palette 0, on every line
 lda gfx_mode
 cmp #GFX_TDYA
 bne :m320
 ldy #$8080                ; (mode 0Ah: 640)
:m320
 tya
:scb
 sta >SHR_SCB,x
 inx
 inx
 cpx #200
 bcc :scb
 lda #1
 sta tdy_alld
 sta tdy_pald
 rts

* tdy_setpal - the SHR's sixteen colours: entry n is the palette
* register n & the mask, and that one of the CGA's sixteen (on a PC
* that is no Tandy: colour n). In mode 0Ah a pixel is two bits and
* the SHR is in 640 mode, where the four pixels of a byte read the
* entries from 8, 12, 0 and 4: entry n is the colour of n & 3.
tdy_setpal
 mx %00
 lda #$000F
 sta tdy_pm
 lda gfx_mode
 cmp #GFX_TDYA
 bne :all
 lda #$0003
 sta tdy_pm
:all
 ldy #0
:e
 tya
 lsr
 and tdy_pm
 jsr tdy_col
 asl
 tax
 lda cga_rgb,x
 tyx
 sta >SHR_PAL,x
 iny
 iny
 cpy #32
 bcc :e
 rts

* tdy_col - A (its low four bits) is one of sixteen colours as the
* CGA's logic makes it: a pixel of modes 4-6 through the colour-select
* register, a 16-colour pixel, a cell's nibble in the 160x100 mode.
* On a Tandy the array has the last word: the colour is ANDed with the
* palette mask and is the number of a palette register, which holds
* the colour shown. A <- that; on a PC with no array, A as it came.
* Keeps Y.
tdy_col
 mx %00
 and #$000F
 tax
 lda >TDY_ON
 beq :pc
 txa
 and >TDY_REG+1
 tax
 lda >TDY_REG+$10,x
 and #$000F
 rts
:pc
 txa
 rts

* tdy_0B - INT 10h 0Bh, BH=0, on a Tandy: BL (in A) is the border's
* colour as well, except in mode 6, and in modes 08h and 09h palette
* register 0's (in mode 0Ah the border's alone)
tdy_0B
 mx %00
 tax
 lda >TDY_ON
 bne :on
 rts
:on
 lda gfx_mode
 cmp #6
 beq :out
 sep #$20
 mx %10
 txa
 and #$0F
 sta >TDY_REG+2
 rep #$20
 mx %00
 lda gfx_mode
 cmp #GFX_TDY8
 beq :p0
 cmp #GFX_TDY9
 bne :out
:p0
 sep #$20
 mx %10
 txa
 and #$0F
 sta >TDY_REG+$10
 rep #$20
 mx %00
 lda #1
 sta tdy_pald
:out
 rts

* tdy_flush - the frame of modes 08h, 09h and 0Ah: the palette if it
* changed, then the lines. Modes 09h and 0Ah: the two pages shown are
* found in their slots; all 200 lines are drawn when tdy_alld, and
* otherwise those of the 256s the core marked, when the half of the
* window they are in is a page shown.
tdy_flush
 mx %00
 lda tdy_pald
 beq :nopal
 stz tdy_pald
 jsr tdy_setpal
:nopal
 lda gfx_mode
 cmp #GFX_TDY8
 bne :m9
 jmp tdy_flush8
:m9
 lda >TDY_PAGE             ; the pages shown: an even one and the next
 and #$0006
 sta tdy_d0
 asl
 tay
 lda tdy_where,y
 jsr tdy_slot
 sta tdy_bb
 sta tdy_bb+2
 lda tdy_off
 sta tdy_bs
 clc
 adc #$2000
 sta tdy_bs+2
 lda tdy_where+2,y
 jsr tdy_slot
 sta tdy_bb+4
 sta tdy_bb+6
 lda tdy_off
 sta tdy_bs+4
 clc
 adc #$2000
 sta tdy_bs+6
 lda tdy_alld
 beq :part
 stz tdy_alld
 ldx #0
 lda #0
:cf
 sta >VID_DIRTY,x
 inx
 inx
 cpx #128
 bcc :cf
 stz gPAR
:ab
 stz gROW
:ar
 jsr tdy_row
 inc gROW
 lda gROW
 cmp #50
 bcc :ar
 inc gPAR
 lda gPAR
 cmp #4
 bcc :ab
 rts
:part
 jsr tdy_dirty
 bne :some
 rts                       ; (most frames)
:some
 stz gPG
:pg
 lda gPG
 and #$001F
 bne :same
 stz tdy_nx                ; an 8K begins: none of its rows is drawn
:same
 ldx gPG
 lda >VID_DIRTY,x
 and #$00FF
 beq :next
 sep #$20
 mx %10
 lda #0
 sta >VID_DIRTY,x
 rep #$20
 mx %00
 ldy #TDY_WIN*2            ; the page in this half of the window
 lda gPG
 cmp #64
 bcc :h0
 ldy #TDY_WIN*2+2
:h0
 lda tdy_held,y
 eor tdy_d0                ; 0: the first page shown, 1: the second
 cmp #2
 bcs :next                 ; another, or none: not on the screen
 asl
 sta gPAR                  ; its line banks are 0 and 1, or 2 and 3
 lda gPG
 and #$0020
 beq :lo
 inc gPAR                  ; the page's second 8K
:lo
 lda gPG
 and #$001F
 tax
 lda tdy_r1,x
 and #$00FF
 sta gR1
 lda tdy_r0,x
 and #$00FF
 cmp tdy_nx                ; (the row two 256s share was drawn for
 bcs :st                   ; the first of them)
 lda tdy_nx
:st
 sta gROW
:row
 lda gR1
 cmp gROW
 bcc :next
 jsr tdy_row
 inc gROW
 lda gROW
 sta tdy_nx
 bra :row
:next
 inc gPG
 lda gPG
 cmp #128
 bcc :pg
 rts

* tdy_dirty - is any of VID_DIRTY's 128 flags set? Z when none: eight
* flags a turn, since this is what a frame costs when nothing changed
tdy_dirty
 mx %00
 ldx #0
:q
 lda >VID_DIRTY,x
 ora >VID_DIRTY+2,x
 ora >VID_DIRTY+4,x
 ora >VID_DIRTY+6,x
 bne :out
 txa
 clc
 adc #8
 tax
 cpx #128
 bcc :q
 lda #0
:out
 rts

* tdy_row - the 160 bytes of row gROW (0-49) of line bank gPAR (0-3)
* to the SHR's line gROW * 4 + gPAR: moved in mode 09h. In mode 0Ah
* they are eighty pairs, eight pixels each, the even byte the low bit
* of each pixel's colour and the odd byte the high bit: the two go
* through cga640_tab (a bit to both bits of an SHR pixel) and one
* gives the pixels' low bits, the other their high ones.
tdy_row
 mx %00
 lda gROW
 asl
 asl
 ora gPAR
 asl
 asl
 asl
 asl
 asl
 sta gL
 asl
 asl
 clc
 adc gL                    ; the line * 160
 adc #<SHR_PIX
 tay
 lda gROW
 asl
 asl
 asl
 asl
 asl
 sta gL
 asl
 asl
 clc
 adc gL                    ; the row * 160
 sta gL
 lda gPAR
 asl
 tax
 lda tdy_bs,x
 clc
 adc gL
 pha
 lda tdy_bb,x
 plx
 sta gSRC+2
 lda gfx_mode
 cmp #GFX_TDYA
 beq :four
 lda gSRC+2
 phb
 cmp #^H_TXTBANK
 beq :b
 cmp #^H_TDYA
 beq :a
 lda #159
 mvn H_TDYC,SHR_PIX
 plb
 rts
:a
 lda #159
 mvn H_TDYA,SHR_PIX
 plb
 rts
:b
 lda #159
 mvn H_TXTBANK,SHR_PIX
 plb
 rts
:four
 stx gSRC
 sty gDST
 lda #^SHR_PIX
 sta gDST+2
 ldy #0
:pr
 lda [gSRC],y              ; the pair: the low bits, the high bits
 pha
 and #$00FF
 asl
 tax
 lda cga640_tab,x
 and #$5555
 sta gE
 pla
 xba
 and #$00FF
 asl
 tax
 lda cga640_tab,x
 and #$AAAA
 ora gE
 sta [gDST],y
 iny
 iny
 cpy #160
 bcc :pr
 rts

* tdy_flush8 - mode 08h's lines. The page shown is found in its slot,
* its even lines in the first 8K and its odd ones in the second; all
* 200 are drawn when tdy_alld, and otherwise the rows of the 256s the
* core marked (gpg_r0 and gpg_r1, video.s: 80 bytes a row as in the
* CGA's modes) in the half of the window where the page is, if it is
* there.
tdy_flush8
 mx %00
 lda >TDY_PAGE
 and #$0007
 sta tdy_d0
 asl
 tay
 lda tdy_where,y
 jsr tdy_slot
 sta gSRC+2
 lda tdy_off
 sta tdy_bs
 clc
 adc #$2000
 sta tdy_bs+2
 lda tdy_alld
 beq :part
 stz tdy_alld
 ldx #0
 lda #0
:cf
 sta >VID_DIRTY,x
 inx
 inx
 cpx #128
 bcc :cf
 stz gPAR
:ab
 stz gROW
:ar
 jsr tdy_row8
 inc gROW
 lda gROW
 cmp #100
 bcc :ar
 inc gPAR
 lda gPAR
 cmp #2
 bcc :ab
 rts
:part
 jsr tdy_dirty
 bne :some
 rts                       ; (most frames)
:some
 stz gPG
:pg
 lda gPG
 and #$001F
 bne :same
 stz tdy_nx                ; an 8K begins: none of its rows is drawn
:same
 ldx gPG
 lda >VID_DIRTY,x
 and #$00FF
 beq :next
 sep #$20
 mx %10
 lda #0
 sta >VID_DIRTY,x
 rep #$20
 mx %00
 ldy #TDY_WIN*2            ; the page in this half of the window
 lda gPG
 cmp #64
 bcc :h0
 ldy #TDY_WIN*2+2
:h0
 lda tdy_held,y
 cmp tdy_d0
 bne :next                 ; another, or none: not on the screen
 stz gPAR
 lda gPG
 and #$0020
 beq :lo
 inc gPAR                  ; the page's second 8K: the odd lines
:lo
 lda gPG
 and #$001F
 tax
 lda gpg_r1,x
 and #$00FF
 sta gR1
 lda gpg_r0,x
 and #$00FF
 cmp tdy_nx                ; (the row two 256s share was drawn for
 bcs :st                   ; the first of them)
 lda tdy_nx
:st
 sta gROW
:row
 lda gROW
 cmp #100
 bcs :next                 ; (the 8K's last 192 bytes are no line)
 lda gR1
 cmp gROW
 bcc :next
 jsr tdy_row8
 inc gROW
 lda gROW
 sta tdy_nx
 bra :row
:next
 inc gPG
 lda gPG
 cmp #128
 bcc :pg
 rts

* tdy_row8 - the 80 bytes of row gROW (0-99) of the field gPAR (0 the
* even lines, 1 the odd) to the SHR's line gROW * 2 + gPAR, each pixel
* twice. gSRC+2 is the page's host bank, tdy_bs where its fields are.
tdy_row8
 mx %00
 lda gROW
 asl
 ora gPAR
 asl
 asl
 asl
 asl
 asl
 sta gL
 asl
 asl
 clc
 adc gL                    ; the line * 160
 adc #<SHR_PIX
 sta gDST
 lda #^SHR_PIX
 sta gDST+2
 lda gROW
 asl
 asl
 asl
 asl
 sta gL
 asl
 asl
 clc
 adc gL                    ; the row * 80
 sta gL
 lda gPAR
 asl
 tax
 lda tdy_bs,x
 clc
 adc gL
 sta gSRC
 ldy #0
:px
 lda [gSRC],y
 and #$00FF
 asl
 tax
 lda tdy8_tab,x
 sta [gDST],y              ; (gDST goes on one a byte and Y one: two)
 inc gDST
 iny
 cpy #80
 bcc :px
 rts

* tdy_05 - INT 10h 05h with AL = 80h-83h: 80h BH = the page shown,
* BL = the CPU's; 81h the CPU's <- BL; 82h the one shown <- BH; 83h
* both
tdy_05
 mx %00
 lda rAX
 and #$00FF
 cmp #$0080
 beq :get
 cmp #$0081
 beq :cpu
 cmp #$0082
 beq :crt
 cmp #$0083
 beq :both
 rts
:get
 lda >TDY_PAGE
 and #$0007
 xba
 sta tdy_t0
 lda >TDY_PAGE
 lsr
 lsr
 lsr
 and #$0007
 ora tdy_t0
 sta rBX
 rts
:cpu
 lda >TDY_PAGE
 and #$00C7
 sta tdy_t0
 bra :bl
:crt
 lda >TDY_PAGE
 and #$00F8
 sta tdy_t0
 lda rBX
 xba
 and #$0007
 ora tdy_t0
 jmp tdy_setpage
:both
 lda >TDY_PAGE
 and #$00C0
 sta tdy_t0
 lda rBX
 xba
 and #$0007
 ora tdy_t0
 sta tdy_t0
:bl
 lda rBX
 and #$0007
 asl
 asl
 asl
 ora tdy_t0
 jmp tdy_setpage

* tdy_10 - INT 10h 10h: AL = 0 palette register BL <- BH; 1 the border
* <- BH; 2 all sixteen and the border from the 17 bytes at ES:DX
tdy_10
 mx %00
 lda rAX
 and #$00FF
 beq :one
 cmp #1
 beq :over
 cmp #2
 beq :all
 rts
:one
 lda rBX
 and #$000F
 tax
 sep #$20
 mx %10
 lda rBX+1
 sta >TDY_REG+$10,x
 rep #$20
 mx %00
 bra :pd
:over
 sep #$20
 mx %10
 lda rBX+1
 sta >TDY_REG+2
 rep #$20
 mx %00
 rts
:all
 ldx #bES
 lda rDX
 jsr gptr
 ldy #0
 sep #$20
 mx %10
:c
 lda [pGST],y
 tyx
 sta >TDY_REG+$10,x
 iny
 cpy #16
 bcc :c
 lda [pGST],y
 sta >TDY_REG+2
 rep #$20
 mx %00
:pd
 lda #1
 sta tdy_pald
 rts

* tdy_pixel - the pixel CX, DX of mode 09h, in the CPU's 32K, or of
* mode 08h, in its 16K: X = its byte's offset in the text bank (the
* left pixel is the high four bits); C set when it is off the screen.
* Mode 0Ah, 640 across: X = the offset of the pixel's pair of bytes.
tdy_pixel
 mx %00
 lda rDX
 cmp #200
 bcs :bad
 jsr tdy_lnoff
 sta tdy_t0
 lda gfx_mode
 cmp #GFX_TDY8
 beq :m8
 cmp #GFX_TDYA
 beq :xa
 lda rCX
 cmp #320
 bcs :bad
 lsr
 bra :xo
:xa
 lda rCX                   ; eight pixels a pair
 cmp #640
 bcs :bad
 lsr
 lsr
 and #$FFFE
 bra :xo
:m8
 lda rCX
 cmp #160
 bcs :bad
 lsr
:xo
 clc
 adc tdy_t0
 tax
 clc
 rts
:bad
 sec
 rts

* tdy_lnoff - A = a line of the screen, 0-199 -> A = where its first
* byte is in the text bank, in the pages the CPU has: in modes 09h
* and 0Ah the 8K bank y & 3 at (y >> 2) * 160, in mode 08h the 8K
* y & 1 at (y >> 1) * 80. Keeps X and Y.
tdy_lnoff
 mx %00
 sta tdy_ln
 lda gfx_mode
 cmp #GFX_TDY8
 beq :m8
 lda tdy_ln
 lsr
 lsr
 asl
 asl
 asl
 asl
 asl
 sta tdy_t0
 asl
 asl
 clc
 adc tdy_t0
 sta tdy_t0                ; (y >> 2) * 160
 lda tdy_ln
 and #$0003
 bra :bank
:m8
 lda tdy_ln
 lsr
 asl
 asl
 asl
 asl
 sta tdy_t0
 asl
 asl
 clc
 adc tdy_t0
 sta tdy_t0                ; (y >> 1) * 80
 lda tdy_ln
 and #$0001
:bank
 xba
 asl
 asl
 asl
 asl
 asl                       ; the bank's 8K
 clc
 adc tdy_t0
 adc #<H_TXT
 rts

* tdy_setpix - INT 10h 0Ch: the pixel CX, DX <- AL (bit 7: XOR). In
* the 16-colour modes the pixel of an even CX is its byte's high four
* bits; in mode 0Ah it is one bit in each byte of its pair, AL's bit 0
* in the even byte and bit 1 in the odd.
tdy_setpix
 mx %00
 jsr tdy_pixel
 bcc :ok
 rts
:ok
 lda gfx_mode
 cmp #GFX_TDYA
 bne :m16
 jmp tdy_setpixA
:m16
 sep #$20
 mx %10
 lda rAX
 and #$0F
 sta tdy_w
 lda #$F0
 sta tdy_m
 lda rCX
 lsr
 bcs :odd
 lda tdy_w
 asl
 asl
 asl
 asl
 sta tdy_w
 lda #$0F
 sta tdy_m
:odd
 lda rAX
 bmi :xor
 lda >H_TXTBANK,x
 and tdy_m
 ora tdy_w
 bra :st
:xor
 lda >H_TXTBANK,x
 eor tdy_w
:st
 sta >H_TXTBANK,x
 rep #$20
 mx %00
tdy_pmark                  ; the 256 of the byte at X was written
 mx %00
 txa
 and #$7F00
 xba
 tax
 sep #$20
 mx %10
 lda #1
 sta >VID_DIRTY,x
 rep #$20
 mx %00
 rts

* tdy_setpixA - mode 0Ah's: X is the pair's offset
tdy_setpixA
 mx %00
 lda rCX
 and #$0007
 tay
 sep #$20
 mx %10
 lda gp_m6,y               ; the pixel's bit, the left one bit 7
 sta tdy_m
 lda rAX
 bmi :xor
 lda tdy_m                 ; the even byte: the colour's bit 0
 eor #$FF
 and >H_TXTBANK,x
 sta tdy_w
 lda rAX
 lsr
 bcc :p0
 lda tdy_w
 ora tdy_m
 sta tdy_w
:p0
 lda tdy_w
 sta >H_TXTBANK,x
 lda tdy_m                 ; the odd byte: bit 1
 eor #$FF
 and >H_TXTBANK+1,x
 sta tdy_w
 lda rAX
 and #$02
 beq :p1
 lda tdy_w
 ora tdy_m
 sta tdy_w
:p1
 lda tdy_w
 sta >H_TXTBANK+1,x
 bra :mark
:xor
 lda rAX
 lsr
 bcc :x0
 lda >H_TXTBANK,x
 eor tdy_m
 sta >H_TXTBANK,x
:x0
 lda rAX
 and #$02
 beq :mark
 lda >H_TXTBANK+1,x
 eor tdy_m
 sta >H_TXTBANK+1,x
:mark
 rep #$20
 mx %00
 jmp tdy_pmark             ; (the pair is in one 256: its offset is even)

* tdy_getpix - INT 10h 0Dh: AL = the pixel CX, DX
tdy_getpix
 mx %00
 jsr tdy_pixel
 bcc :ok
 lda #0
 bra :ret
:ok
 lda gfx_mode
 cmp #GFX_TDYA
 bne :m16
 lda rCX
 and #$0007
 tay
 lda gp_m6,y
 and #$00FF
 sta tdy_m
 lda >H_TXTBANK,x          ; the pair: the low bit, the high bit
 sta tdy_w
 ldy #0
 and tdy_m
 beq :a0
 iny
:a0
 lda tdy_w
 xba
 and tdy_m
 beq :a1
 iny
 iny
:a1
 tya
 bra :ret
:m16
 lda >H_TXTBANK,x
 and #$00FF
 tax
 lda rCX
 lsr
 txa
 bcs :ret
 lsr
 lsr
 lsr
 lsr
:ret
 and #$000F
 sep #$20
 mx %10
 sta rAX
 rep #$20
 mx %00
 rts

*--- the BIOS's text in modes 08h, 09h and 0Ah (gtext.s) ------
* A character is the font's eight lines of eight pixels, as it is in
* the CGA's modes: four bytes a line in the sixteen colours (twenty
* columns of the 160 pixels, forty of the 320), a pair of bytes in
* mode 0Ah's eighty. It goes to the pages the CPU has at B800, where
* the pixel calls go.

* tdy_gm - C set when gfx_mode is one of the three. Keeps A, X, Y.
tdy_gm
 mx %00
 pha
 lda gfx_mode
 cmp #GFX_TDY8
 bcc :out
 cmp #GFX_TDYA+1
 bcs :no
 sec
 bra :out
:no
 clc
:out
 pla
 rts

* tdy_cell - gt_cell: A = col | row<<8 -> gt_off, the cell's first
* byte in a line, and tdy_cy, its first line; C set when there is
* no such cell
tdy_cell
 mx %00
 sta gt_pos
 and #$00FF
 sta gt_off
 jsr gt_cols
 dec
 cmp gt_off
 bcc :bad                  ; cols-1 < col
 lda gt_pos
 xba
 and #$00FF
 cmp #25
 bcs :bad
 asl
 asl
 asl
 sta tdy_cy
 asl gt_off                ; a pair of bytes a cell in mode 0Ah,
 lda gfx_mode
 cmp #GFX_TDYA
 beq :ok
 asl gt_off                ; four in the others
:ok
 clc
 rts
:bad
 sec
 rts

* tdy_glin - X = where line gt_i of the cell is
tdy_glin
 mx %00
 lda tdy_cy
 clc
 adc gt_i
 jsr tdy_lnoff
 clc
 adc gt_off
 tax
 rts

* tdy_draw - gt_draw: the character gt_ch in the cell of tdy_cell, in
* the colour gt_col (of sixteen, or of mode 0Ah's four), its bit 7
* for XOR; the background is colour 0
tdy_draw
 mx %00
 lda gt_ch
 and #$00FF
 asl
 asl
 asl
 sta gt_g
 stz gt_i
 lda gt_col
 and #$000F
 sta gt_msk
 asl
 asl
 asl
 asl
 ora gt_msk
 sta gt_msk                ; the colour in both pixels of a byte
:row
 jsr tdy_glin
 ldy gt_g
 lda font,y
 and #$00FF
 sta gt_w
 lda gfx_mode
 cmp #GFX_TDYA
 beq :four
 lda #4
 sta tdy_w
:byte
 lda gt_w                  ; two bits of the font a byte, the left one its
 asl                       ; high four
 asl
 sta gt_w
 xba
 and #$0003
 tay
 sep #$20
 mx %10
 lda tdy_ntab,y
 and gt_msk
 bit gt_col
 bpl :st
 eor >H_TXTBANK,x
:st
 sta >H_TXTBANK,x
 rep #$20
 mx %00
 inx
 dec tdy_w
 bne :byte
 dex                       ; (the four are in one 256: a cell's offset is
 bra :mark                 ; a multiple of four)
:four
 sep #$20                  ; mode 0Ah: the glyph's line is the even byte for
 mx %10                    ; the colour's bit 0 and the odd one for bit 1
 lda gt_col
 lsr
 lda #0
 bcc :e
 lda gt_w
:e
 bit gt_col
 bpl :es
 eor >H_TXTBANK,x
:es
 sta >H_TXTBANK,x
 lda gt_col
 and #$02
 beq :o
 lda gt_w
:o
 bit gt_col
 bpl :os
 eor >H_TXTBANK+1,x
:os
 sta >H_TXTBANK+1,x
 rep #$20
 mx %00
:mark
 jsr tdy_pmark
 inc gt_g
 inc gt_i
 lda gt_i
 cmp #8
 bcs :done
 jmp :row
:done
 rts

* tdy_read - gt_read: the cell at the cursor as a glyph in gt_pat (a
* pixel of any colour but 0 is a set bit), and gt_find for the character
tdy_read
 mx %00
 lda >H_BDA+BDA_CURPOS
 jsr tdy_cell
 bcc :ok
 lda #0
 rts
:ok
 stz gt_i
:row
 jsr tdy_glin
 lda gfx_mode
 cmp #GFX_TDYA
 beq :four
 ldy #4
:byte
 lda >H_TXTBANK,x
 pha
 and #$00F0
 cmp #1                    ; (C: there is a pixel)
 rol gt_n
 pla
 and #$000F
 cmp #1
 rol gt_n
 inx
 dey
 bne :byte
 lda gt_n
 bra :put
:four
 lda >H_TXTBANK,x          ; either bit of the colour
 sta gt_n
 xba
 ora gt_n
:put
 ldx gt_i
 sep #$20
 mx %10
 sta gt_pat,x
 rep #$20
 mx %00
 inc gt_i
 lda gt_i
 cmp #8
 bcc :row
 jmp gt_find

* tdy_fillw - a scroll's filling byte gs_fillb (BH) is a colour here:
* tdy_fw = the pair of bytes that are eight pixels of it (sixteen
* colours: it in every four bits; mode 0Ah: its bit 0 in the even
* byte and bit 1 in the odd)
tdy_fillw
 mx %00
 lda gfx_mode
 cmp #GFX_TDYA
 beq :four
 lda gs_fillb
 and #$000F
 sta tdy_fw
 asl
 asl
 asl
 asl
 ora tdy_fw
 sta tdy_fw
 xba
 ora tdy_fw
 sta tdy_fw
 rts
:four
 stz tdy_fw
 lda gs_fillb
 lsr
 bcc :f1
 ldx #$00FF
 stx tdy_fw
:f1
 lsr
 bcc :f2
 lda tdy_fw
 ora #$FF00
 sta tdy_fw
:f2
 rts

* tdys_copy - gs_copy: line gs_s to line gs_d, the window's bytes
* (gs_lb, gs_w), and the 256s they are in marked
tdys_copy
 mx %00
 lda gs_s
 jsr tdy_lnoff
 clc
 adc gs_lb
 tax
 lda gs_d
 jsr tdy_lnoff
 clc
 adc gs_lb
 sta gs_do
 tay
 lda gs_w
 dec
 phb
 mvn H_TXTBANK,H_TXTBANK
 plb
tdy_mkln                   ; the line's bytes from gs_do were written
 mx %00
 ldx gs_do
 jsr tdy_pmark
 lda gs_do
 clc
 adc gs_w
 dec
 tax
 jmp tdy_pmark             ; (under 256 of them: the first's and the last's)

* tdys_fill - gs_fill: line gs_d, the window's bytes, <- tdy_fw
tdys_fill
 mx %00
 lda gs_d
 jsr tdy_lnoff
 clc
 adc gs_lb
 sta gs_do
 tax
 lda tdy_fw
 sta >H_TXTBANK,x          ; the first pair, copied along the rest
 lda gs_w
 sec
 sbc #3
 bcc tdy_mkln
 txy
 iny
 iny
 phb
 mvn H_TXTBANK,H_TXTBANK
 plb
 bra tdy_mkln
