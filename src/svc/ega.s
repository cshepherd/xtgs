*----------------------------------------------------------
* ega.s - the EGA's mode 0Dh: 320x200 in 16 colours
* (docs/ega.md).
*
* Four planes of 64K, a bit of each to a pixel, eight pixels
* to a byte, 40 bytes a line, eight pages of $2000. The
* planes are host banks (H_EGA, H_EGA1-3, src/include/pc.s)
* and the guest reaches them at A000 through the core's trap
* (src/core/ega.s), which flags every byte of the screen it
* writes in EGA_DIRTY (by place on the screen) and the flag's
* 256 in VID_DIRTY. ega_flush draws the flagged bytes: four
* plane bytes are eight pixels, which is four bytes of the
* SHR's 320 mode, a pixel for a pixel, by the tables of
* gen/egatab.s. The 16 colours are the attribute
* controller's palette registers (EGA_AC), each one of the
* CGA's 16 (a 200-line mode's monitor has no others).
*
* The BIOS here: the mode set, the page (05h), the palette
* (0Bh, 10h), the font's whereabouts (11h/30h), the card's
* description (12h/10h), and for gtext.s the character
* cell, the pixel and the window scrolled in the planes
* (eg_cell, eg_draw, eg_read, eg_setpix, eg_getpix, egs_copy,
* egs_fill). These write the planes as they are, whatever
* the guest left in the graphics controller. DBR=SVC.
*----------------------------------------------------------
 err EGA_SEQ+8-EGA_GC      ; (ega_enter clears the three as one)
 err EGA_GC+16-EGA_AC
eg_wpg     dw 0              ; the page a text service works on (eg_pgoff)
eg_wx      dw 0              ; its cursor's slot in the BDA, while it is in the first
eg_in      dw 0              ; nonzero: INT 10h named the page, the teletype does not
eg_none    dw 0              ; nonzero: the PC has no EGA (XTGS.CMD's VIDEO=CGA,
                             ; rd_readcfg): INT 10h is a CGA's
eg_stride  dw 40             ; bytes from a line to the next (the 6845's R13h, twice)
eg_pan     dw 0              ; pixels the screen is panned left (the attribute controller's 13h)
eg_ln      dw 0              ; the wide draw: a line's first byte, lines to go
eg_cnt     dw 0
eg_keep    dw 0              ; mode set: AL's bit 7, the planes are not cleared
eg_f       ds 8              ; a fill: each plane's byte (words)
eg_fw      dw 0              ; and the SHR's two bytes
eg_si      dw 0              ; a line moved: its source and destination on
eg_di      dw 0              ; the screen
FONT_OFF   = $F000           ; F000:F000, the font where a guest can read it
FONT_LOW   = $FA6E           ; and its first half where the PC's BIOS has it

* ega_init - with the BDA: the card is there and the mode is not;
* the font in the BIOS segment, INT 1Fh (characters 80h-FFh) and
* INT 43h (all of them) pointing at it.
ega_init
 mx %00
 lda #0
 sta >TDY_ON               ; (nor is the PC a Tandy until XTGS.CMD says so)
 sta >EGA_ON
 sta >EGA_SYNC
 sta >EGA_ACFF
 sta >EGA_PALD
 sta >EGA_ALLD
 sta >EGA_START
 lda #EGA_LEN
 sta >EGA_WINLEN
 lda eg_none
 bne :nocard
 lda #$F760                ; 0040:0087 60h: 256K, the EGA is the active card;
 sta >H_BDA+$87            ; 0088 F7h: its switches, a 200-line colour monitor
:nocard
 ldx #0
:f
 lda font,x
 sta >H_BIOS+FONT_OFF,x
 inx
 inx
 cpx #2048
 bcc :f
 ldx #0
:g
 lda font,x
 sta >H_BIOS+FONT_LOW,x
 inx
 inx
 cpx #1024
 bcc :g
 lda #FONT_OFF+1024
 sta >H_IVT+$7C            ; INT 1Fh
 lda #FONT_OFF
 sta >H_IVT+$10C           ; INT 43h
 lda #BIOS_SEG
 sta >H_IVT+$7E
 sta >H_IVT+$10E
 rts

* ega_off - the PC has no EGA: mode 0Dh is not set, 11h and 12h answer
* nothing, the BDA has no EGA bytes
ega_off
 mx %00
 lda #1
 sta eg_none
 lda #0
 sta >H_BDA+$87
 rts

* ega_enter - mode 0Dh (vid_setmode): the registers as the BIOS leaves
* them, page 0, the planes cleared unless eg_keep, the SHR in 320 mode.
ega_enter
 mx %00
 lda #GFX_EGA
 sta gfx_mode
 jsr shd_inval             ; the text pixels are gone
 ldx #0
 lda #0
:zr
 sta >EGA_SEQ,x
 inx
 inx
 cpx #56
 bcc :zr
 sta >EGA_SEQI
 sta >EGA_GCI
 sta >EGA_ACI
 sta >EGA_ACFF
 sta >EGA_START
 sta >EGA_ALLD
 sta >H_BDA+BDA_PGOFF
 lda #EGA_LEN
 sta >EGA_WINLEN
 lda #40
 sta eg_stride
 stz eg_pan
 sep #$20
 mx %10
 lda #20                   ; the 6845's offset register: 40 bytes a line
 sta >CRTC_REG+$13
 rep #$20
 mx %00
 lda #0
 stz eg_wpg
 stz eg_wx
 stz eg_in
 ldx #14
:cur
 sta >H_BDA+BDA_CURPOS,x   ; every page's cursor home
 dex
 dex
 bpl :cur
 lda #$2000
 sta >H_BDA+BDA_PGSIZE
 sep #$20
 mx %10
 lda #0
 sta >H_BDA+BDA_PAGE
 lda #$0F
 sta >EGA_SEQ+2            ; every plane written
 sta >EGA_GC+7             ; and compared (read mode 1)
 lda #$FF
 sta >EGA_GC+8             ; every bit
 ldx #0
:pal
 txa                       ; the palette: 0-7, and 10h-17h (bit 4 is the
 cmp #8                    ; intensity on a 200-line monitor)
 bcc :p1
 clc
 adc #8
:p1
 sta >EGA_AC,x
 inx
 cpx #16
 bcc :pal
 rep #$20
 mx %00
 lda #1
 sta >EGA_ON
 sta >EGA_SYNC             ; (the core takes the trap up after this call)
 ldx #0
 lda #0
:cd
 sta >VID_DIRTY,x
 inx
 inx
 cpx #64
 bcc :cd
 jsr eg_noflags
 ldx #0                    ; 320 mode, palette 0, on every line
 lda #0
:scb
 sta >SHR_SCB,x
 inx
 inx
 cpx #200
 bcc :scb
 jsr ega_setpal
 ldx #0
 lda #0
:clr
 sta >SHR_PIX,x
 inx
 inx
 cpx #32000
 bcc :clr
 lda eg_keep
 beq :planes
 lda #1                    ; kept: what the planes hold is the picture
 sta >EGA_ALLD
 rts
:planes
 lda #0
 sta >H_EGA
 sta >H_EGA1
 sta >H_EGA2
 sta >H_EGA3
 phb
 ldx #0
 ldy #2
 lda #$FFFD
 mvn H_EGA,H_EGA
 ldx #0
 ldy #2
 lda #$FFFD
 mvn H_EGA1,H_EGA1
 ldx #0
 ldy #2
 lda #$FFFD
 mvn H_EGA2,H_EGA2
 ldx #0
 ldy #2
 lda #$FFFD
 mvn H_EGA3,H_EGA3
 plb
 rts

* ega_leave - another mode is set
ega_leave
 mx %00
 lda #0
 sta >EGA_ON
 sta >H_BDA+BDA_PGOFF
 lda #1
 sta >EGA_SYNC
 lda #$1000
 sta >H_BDA+BDA_PGSIZE
 sep #$20
 mx %10
 lda #0
 sta >H_BDA+BDA_PAGE
 rep #$20
 mx %00
 rts

* eg_noflags - no byte of the screen is to be drawn
eg_noflags
 mx %00
 ldx #0
 lda #0
:l
 sta >EGA_DIRTY,x
 inx
 inx
 cpx #EGA_LEN+2
 bcc :l
 rts

* ega_setpal - the SHR's palette 0 from the 16 palette registers: a
* register's bits 0-2 are blue, green and red and bit 4 the intensity
ega_setpal
 mx %00
 stz sv8
:l
 ldx sv8
 lda >EGA_AC,x
 and #$0017
 cmp #$0010
 bcc :c
 and #$0007
 ora #$0008
:c
 asl
 tay
 lda sv8
 asl
 tax
 lda cga_rgb,y
 sta >SHR_PAL,x
 inc sv8
 lda sv8
 cmp #16
 bcc :l
 lda #0
 sta >EGA_PALD
 rts

* ega_flush - the frame's drawing: the palette when a register
* changed, the whole screen when it starts somewhere else in the
* planes (the 6845's R12/R13, in bytes: a page shown, or a scroll)
* or EGA_ALLD says so, and otherwise the bytes flagged in EGA_DIRTY,
* looked for in the 256s VID_DIRTY marks.
ega_flush
 mx %00
 lda >CRTC_REG+12
 xba
 cmp >EGA_START
 beq :same
 sta >EGA_START
 lda #1
 sta >EGA_ALLD
:same
 lda >CRTC_REG+$13         ; the offset register: words from a line to the next
 and #$00FF
 bne :off
 lda #20
:off
 asl
 sta gE
 lda >EGA_AC+$13           ; and the pixels panned
 and #$0007
 sta gO
 cmp eg_pan
 bne :geom
 lda gE
 cmp eg_stride
 beq :geomok
:geom
 lda gO
 sta eg_pan
 lda gE
 sta eg_stride
 lda #1
 sta >EGA_ALLD
 jsr eg_winlen
:geomok
 lda >EGA_PALD
 beq :np
 jsr ega_setpal
:np
 lda >EGA_WINLEN
 cmp #EGA_LEN
 beq :narrow
 jmp eg_wide
:narrow
 lda >EGA_ALLD
 beq :pages
 lda #0
 sta >EGA_ALLD
 ldx #0
:cv
 sta >VID_DIRTY,x
 inx
 inx
 cpx #32
 bcc :cv
 jsr eg_noflags
 stz gROW
 stz gL
:all
 lda gROW
 clc
 adc >EGA_START
 tax
 jsr eg_conv
 lda gL
 clc
 adc #4
 sta gL
 inc gROW
 lda gROW
 cmp #EGA_LEN
 bcc :all
 rts
:pages
 stz gPG
:pg
 ldx gPG
 lda >VID_DIRTY,x
 and #$00FF
 beq :nextpg
 sep #$20
 mx %10
 lda #0
 sta >VID_DIRTY,x
 rep #$20
 mx %00
 txa
 xba                       ; the 256's first byte
 sta gROW
 clc
 adc #256
 cmp #EGA_LEN
 bcc :lim
 lda #EGA_LEN
:lim
 sta gR1
:scan
 ldx gROW
 lda >EGA_DIRTY,x          ; two flags at a time
 beq :skip
 and #$00FF
 beq :second
 jsr eg_one
 ldx gROW
:second
 inx
 lda >EGA_DIRTY,x
 and #$00FF
 beq :skip
 jsr eg_one
:skip
 lda gROW
 clc
 adc #2
 sta gROW
 cmp gR1
 bcc :scan
:nextpg
 inc gPG
 lda gPG
 cmp #32
 bcc :pg
 rts

* eg_winlen - EGA_WINLEN from eg_stride and eg_pan: EGA_LEN as the
* mode is set, else the bytes from the screen's first to its last
* (200 lines of eg_stride and the byte panned in), all of a plane when
* that is more than one holds.
eg_winlen
 mx %00
 lda eg_pan
 bne :wide
 lda eg_stride
 cmp #40
 bne :wide
 lda #EGA_LEN
 bra :set
:wide
 lda eg_stride
 cmp #321
 bcc :fits
 lda #$FFFF
 bra :set
:fits
 asl
 asl
 asl                       ; * 8
 sta gE
 asl                       ; * 16
 sta gO
 clc
 adc gE                    ; * 24
 clc
 adc gO                    ; * 40
 asl
 asl                       ; * 160
 clc
 adc gO                    ; * 176
 clc
 adc gO                    ; * 192
 clc
 adc gE                    ; * 200
 inc
 cmp #EGA_LEN              ; (shorter lines: never the narrow path's number)
 bne :set
 inc
:set
 sta >EGA_WINLEN
 rts

* eg_wide - the frame's drawing when a line of the planes is not 40
* bytes from the next or the screen is panned (a program that scrolls
* by the 6845's start address and offset register and the attribute
* controller's panning: a window on a buffer wider than the screen).
* No byte has a flag then: anything written in the window, or the
* window moved, and all of it is drawn, 40 bytes of each line.
eg_wide
 mx %00
 lda >EGA_ALLD
 bne :draw
 ldx #0
:chk
 lda >VID_DIRTY,x
 bne :draw
 inx
 inx
 cpx #32
 bcc :chk
 rts
:draw
 lda #0
 sta >EGA_ALLD
 ldx #0
:cv
 sta >VID_DIRTY,x
 inx
 inx
 cpx #32
 bcc :cv
 stz gL
 lda >EGA_START
 sta eg_ln
 lda #200
 sta eg_cnt
:line
 lda eg_ln
 sta gROW
 lda #40
 sta gR1
 lda eg_pan
 bne :pan
:byte
 ldx gROW
 jsr eg_conv
 lda gL
 clc
 adc #4
 sta gL
 inc gROW
 dec gR1
 bne :byte
 bra :next
:pan
 ldx gROW
 jsr eg_convp
 lda gL
 clc
 adc #4
 sta gL
 inc gROW
 dec gR1
 bne :pan
:next
 lda eg_ln
 clc
 adc eg_stride
 sta eg_ln
 dec eg_cnt
 bne :line
 rts

* eg_convp - as eg_conv, the eight pixels that begin eg_pan (1-7)
* pixels into the byte at X: each plane's byte and the next, shifted.
eg_convp
 mx %00
 lda >H_EGA,x
 xba
 ldy eg_pan
:s0
 asl
 dey
 bne :s0
 xba
 and #$00FF
 asl
 tay
 lda eg_t0lo,y
 sta gE
 lda eg_t0hi,y
 sta gO
 lda >H_EGA1,x
 beq :p2
 xba
 ldy eg_pan
:s1
 asl
 dey
 bne :s1
 xba
 and #$00FF
 asl
 tay
 lda eg_t1lo,y
 tsb gE
 lda eg_t1hi,y
 tsb gO
:p2
 lda >H_EGA2,x
 beq :p3
 xba
 ldy eg_pan
:s2
 asl
 dey
 bne :s2
 xba
 and #$00FF
 asl
 tay
 lda eg_t2lo,y
 tsb gE
 lda eg_t2hi,y
 tsb gO
:p3
 lda >H_EGA3,x
 beq :out
 xba
 ldy eg_pan
:s3
 asl
 dey
 bne :s3
 xba
 and #$00FF
 asl
 tay
 lda eg_t3lo,y
 tsb gE
 lda eg_t3hi,y
 tsb gO
:out
 ldx gL
 lda gE
 sta >SHR_PIX,x
 lda gO
 sta >SHR_PIX+2,x
 rts

* eg_one - the screen's byte X is flagged: not any more, and drawn
eg_one
 mx %00
 sep #$20
 mx %10
 lda #0
 sta >EGA_DIRTY,x
 rep #$20
 mx %00
 txa
 asl
 asl
 sta gL
 txa
 clc
 adc >EGA_START
 tax
* eg_conv - the planes' byte at X to the four SHR bytes at gL
eg_conv
 mx %00
 lda >H_EGA,x
 and #$00FF
 asl
 tay
 lda eg_t0lo,y
 sta gE
 lda eg_t0hi,y
 sta gO
 lda >H_EGA1,x
 and #$00FF
 beq :p2
 asl
 tay
 lda eg_t1lo,y
 tsb gE
 lda eg_t1hi,y
 tsb gO
:p2
 lda >H_EGA2,x
 and #$00FF
 beq :p3
 asl
 tay
 lda eg_t2lo,y
 tsb gE
 lda eg_t2hi,y
 tsb gO
:p3
 lda >H_EGA3,x
 and #$00FF
 beq :out
 asl
 tay
 lda eg_t3lo,y
 tsb gE
 lda eg_t3hi,y
 tsb gO
:out
 ldx gL
 lda gE
 sta >SHR_PIX,x
 lda gO
 sta >SHR_PIX+2,x
 rts

* eg_mk1 - the planes' byte at X was written: its flag and its 256,
* when it is on the screen. Keeps X and Y.
eg_mk1
 mx %00
 phx
 txa
 sec
 sbc >EGA_START
 cmp #EGA_LEN
 bcc :in
 cmp >EGA_WINLEN           ; (longer or panned lines: ega_flush's wide path)
 bcs :out
 lda >VID_DIRTY
 ora #$0001
 sta >VID_DIRTY
 bra :out
:in
 tax
 sep #$20
 mx %10
 lda #1
 sta >EGA_DIRTY,x
 rep #$20
 mx %00
 txa
 xba
 and #$00FF
 tax
 sep #$20
 mx %10
 lda #1
 sta >VID_DIRTY,x
 rep #$20
 mx %00
:out
 plx
 rts

* eg_mkrun - the same for the A bytes from X (A not 0), one by one
eg_mkrun
 mx %00
 tay
:l
 jsr eg_mk1
 inx
 dey
 bne :l
 rts

* eg_curin - a text service is to work on page A: eg_wpg, and that
* page's cursor changes places with the first in the BDA, where
* every service looks for it, until eg_curout. Keeps the sv's.
eg_curin
 mx %00
 and #$0007
 sta eg_wpg
 asl
 sta eg_wx
 bne eg_curswap
 rts
eg_curout
 mx %00
 lda eg_wx
 bne :sw
 rts
:sw
 jsr eg_curswap
 stz eg_wx
 rts
eg_curswap
 mx %00
 ldx eg_wx
 lda >H_BDA+BDA_CURPOS,x
 pha
 lda >H_BDA+BDA_CURPOS
 sta >H_BDA+BDA_CURPOS,x
 pla
 sta >H_BDA+BDA_CURPOS
 rts

* eg_pgoff - A = where the page a service works on starts in the
* planes (eg_wpg: the page shown, or the one INT 10h's BH named)
eg_pgoff
 mx %00
 lda eg_wpg
eg_pgA                     ; A = where page A does
 mx %00
 and #$0007
 xba
 asl
 asl
 asl
 asl
 asl
 rts

* eg_setpage - INT 10h 05h: page A (0-7) is the one shown, and the
* one the BIOS writes to
eg_setpage
 mx %00
 and #$0007
 pha
 sep #$20
 mx %10
 sta >H_BDA+BDA_PAGE
 rep #$20
 mx %00
 pla
 jsr eg_pgA
 sta >H_BDA+BDA_PGOFF
 xba
 sta >CRTC_REG+12          ; R12 its high byte, R13 its low: ega_flush
 rts

* eg_cell - gt_cell in mode 0Dh: A = col | row<<8 -> gt_off, the
* cell's first byte in the planes (a byte wide, eight lines of 40)
eg_cell
 mx %00
 sta gt_pos
 and #$00FF
 cmp #40
 bcs :bad
 sta gt_off
 lda gt_pos
 xba
 and #$00FF
 cmp #25
 bcs :bad
 sta gs_tmp
 xba                       ; row*256
 clc
 adc gt_off
 sta gt_off
 lda gs_tmp
 asl
 asl
 asl
 asl
 asl
 asl                       ; and row*64: 320 bytes a character row
 clc
 adc gt_off
 sta gt_off
 jsr eg_pgoff
 clc
 adc gt_off
 sta gt_off
 clc
 rts
:bad
 sec
 rts

* eg_draw - gt_draw: the character gt_ch at gt_off in the colour
* gt_col, its bit 7 for XOR; the background is colour 0
eg_draw
 mx %00
 lda gt_ch
 and #$00FF
 asl
 asl
 asl
 sta gt_g
 stz gt_i
 lda gt_off
 sta gs_tmp
:row
 ldx gt_g
 lda font,x
 sta gt_w
 ldx gs_tmp
 sep #$20
 mx %10
 lda gt_col
 bmi :xor
 and #$01
 beq :s0
 lda gt_w
:s0
 sta >H_EGA,x
 lda gt_col
 and #$02
 beq :s1
 lda gt_w
:s1
 sta >H_EGA1,x
 lda gt_col
 and #$04
 beq :s2
 lda gt_w
:s2
 sta >H_EGA2,x
 lda gt_col
 and #$08
 beq :s3
 lda gt_w
:s3
 sta >H_EGA3,x
 bra :next
:xor
 and #$01
 beq :x1
 lda >H_EGA,x
 eor gt_w
 sta >H_EGA,x
:x1
 lda gt_col
 and #$02
 beq :x2
 lda >H_EGA1,x
 eor gt_w
 sta >H_EGA1,x
:x2
 lda gt_col
 and #$04
 beq :x3
 lda >H_EGA2,x
 eor gt_w
 sta >H_EGA2,x
:x3
 lda gt_col
 and #$08
 beq :next
 lda >H_EGA3,x
 eor gt_w
 sta >H_EGA3,x
:next
 rep #$20
 mx %00
 jsr eg_mk1
 txa
 clc
 adc #40
 sta gs_tmp
 inc gt_g
 inc gt_i
 lda gt_i
 cmp #8
 bcs :done
 jmp :row
:done
 rts

* eg_read - gt_read: the cell at the cursor as a glyph in gt_pat (a
* pixel of any colour is a set bit), and gt_find for the character
eg_read
 mx %00
 lda >H_BDA+BDA_CURPOS
 jsr eg_cell
 bcc :ok
 lda #0
 rts
:ok
 ldx gt_off
 ldy #0
:row
 sep #$20
 mx %10
 lda >H_EGA,x
 ora >H_EGA1,x
 ora >H_EGA2,x
 ora >H_EGA3,x
 sta gt_pat,y
 rep #$21                  ; (and the carry clear)
 mx %00
 txa
 adc #40
 tax
 iny
 cpy #8
 bcc :row
 jmp gt_find

* eg_pixel - where the pixel CX, DX of page BH is: X = its byte in
* the planes, Y = its place in the byte (0 leftmost); C set when it
* is off the screen
eg_pixel
 mx %00
 lda rDX
 cmp #200
 bcs :bad
 asl
 asl
 asl
 sta gt_off
 asl
 asl
 clc
 adc gt_off                ; line*40
 sta gt_off
 lda rCX
 cmp #320
 bcs :bad
 and #$0007
 tay
 lda rCX
 lsr
 lsr
 lsr
 clc
 adc gt_off
 sta gt_off
 lda rBX
 xba
 jsr eg_pgA
 clc
 adc gt_off
 tax
 clc
 rts
:bad
 sec
 rts

* eg_setpix - INT 10h 0Ch: the pixel CX, DX <- AL (bit 7: XOR)
eg_setpix
 mx %00
 jsr eg_pixel
 bcc :ok
 rts
:ok
 sep #$20
 mx %10
 lda gp_m6,y
 sta gt_msk                ; the pixel's bit
 lda rAX
 sta gt_w
 bmi :xor
 lda #$01
 bit gt_w
 beq :c0
 lda >H_EGA,x
 ora gt_msk
 bra :w0
:c0
 lda gt_msk
 eor #$FF
 and >H_EGA,x
:w0
 sta >H_EGA,x
 lda #$02
 bit gt_w
 beq :c1
 lda >H_EGA1,x
 ora gt_msk
 bra :w1
:c1
 lda gt_msk
 eor #$FF
 and >H_EGA1,x
:w1
 sta >H_EGA1,x
 lda #$04
 bit gt_w
 beq :c2
 lda >H_EGA2,x
 ora gt_msk
 bra :w2
:c2
 lda gt_msk
 eor #$FF
 and >H_EGA2,x
:w2
 sta >H_EGA2,x
 lda #$08
 bit gt_w
 beq :c3
 lda >H_EGA3,x
 ora gt_msk
 bra :w3
:c3
 lda gt_msk
 eor #$FF
 and >H_EGA3,x
:w3
 sta >H_EGA3,x
 bra :done
:xor
 lda #$01
 bit gt_w
 beq :x1
 lda >H_EGA,x
 eor gt_msk
 sta >H_EGA,x
:x1
 lda #$02
 bit gt_w
 beq :x2
 lda >H_EGA1,x
 eor gt_msk
 sta >H_EGA1,x
:x2
 lda #$04
 bit gt_w
 beq :x3
 lda >H_EGA2,x
 eor gt_msk
 sta >H_EGA2,x
:x3
 lda #$08
 bit gt_w
 beq :done
 lda >H_EGA3,x
 eor gt_msk
 sta >H_EGA3,x
:done
 rep #$20
 mx %00
 jmp eg_mk1

* eg_getpix - INT 10h 0Dh: AL = the pixel CX, DX
eg_getpix
 mx %00
 stz gt_w
 jsr eg_pixel
 bcs :ret
 sep #$20
 mx %10
 lda gp_m6,y
 sta gt_msk
 lda >H_EGA3,x
 and gt_msk
 cmp #1                    ; (carry: the bit is set)
 rol gt_w
 lda >H_EGA2,x
 and gt_msk
 cmp #1
 rol gt_w
 lda >H_EGA1,x
 and gt_msk
 cmp #1
 rol gt_w
 lda >H_EGA,x
 and gt_msk
 cmp #1
 rol gt_w
 rep #$20
 mx %00
:ret
 sep #$20
 mx %10
 lda gt_w
 sta rAX
 rep #$20
 mx %00
 rts

* egs_off - A = a line of the screen -> A = where the window's part
* of it starts in the active page's planes
egs_off
 mx %00
 asl
 asl
 asl
 sta gs_tmp
 asl
 asl
 clc
 adc gs_tmp                ; line*40
 clc
 adc gs_lb
 sta gs_tmp
 jsr eg_pgoff
 clc
 adc gs_tmp
 rts

* egs_vis - carry clear when the active page is the page shown: X =
* gs_do's place on the screen. Then what the scroll does to the
* planes it can do to the SHR's pixels and to the flags, and nothing
* is drawn again.
egs_vis
 mx %00
 jsr eg_pgoff
 cmp >EGA_START
 bne :no
 lda gs_do
 sec
 sbc >EGA_START
 sta eg_di
 tax
 clc
 rts
:no
 sec
 rts

* egs_copy - gs_copy: line gs_s to line gs_d, the window's bytes
egs_copy
 mx %00
 lda gs_s
 jsr egs_off
 sta gs_so
 lda gs_d
 jsr egs_off
 sta gs_do
 ldx gs_so
 ldy gs_do
 lda gs_w
 dec
 phb
 mvn H_EGA,H_EGA
 plb
 ldx gs_so
 ldy gs_do
 lda gs_w
 dec
 phb
 mvn H_EGA1,H_EGA1
 plb
 ldx gs_so
 ldy gs_do
 lda gs_w
 dec
 phb
 mvn H_EGA2,H_EGA2
 plb
 ldx gs_so
 ldy gs_do
 lda gs_w
 dec
 phb
 mvn H_EGA3,H_EGA3
 plb
 jsr egs_vis
 bcc :vis
 ldx gs_do                 ; a page not shown (or not yet): flag what of
 lda gs_w                  ; it is on the screen
 jmp eg_mkrun
:vis
 lda gs_so
 sec
 sbc >EGA_START
 sta eg_si
 clc                       ; the flags go with the bytes: a byte not yet
 adc #<EGA_DIRTY           ; drawn is not drawn where it went either
 tax
 lda eg_di
 clc
 adc #<EGA_DIRTY
 tay
 lda gs_w
 dec
 phb
 mvn EGA_DIRTY,EGA_DIRTY
 plb
 lda eg_si                 ; and the pixels: four bytes to the planes' one
 asl
 asl
 clc
 adc #<SHR_PIX
 tax
 lda eg_di
 asl
 asl
 clc
 adc #<SHR_PIX
 tay
 lda gs_w
 asl
 asl
 dec
 phb
 mvn SHR_PIX,SHR_PIX
 plb
 lda eg_di                 ; (a flag may have come: its 256s are looked at)
 xba
 and #$00FF
 tax
 lda eg_di
 clc
 adc gs_w
 dec
 xba
 and #$00FF
 tay
 sep #$20
 mx %10
 lda #1
 sta >VID_DIRTY,x
 tyx
 sta >VID_DIRTY,x
 rep #$20
 mx %00
 rts

* egs_fill - gs_fill: line gs_d, the window's bytes, <- the colour
* gs_fillb
egs_fill
 mx %00
 lda gs_fillb
 and #$000F
 sta gs_tmp
 asl
 asl
 asl
 asl
 ora gs_tmp
 sta gs_tmp
 xba
 ora gs_tmp
 sta eg_fw                 ; the colour in four SHR pixels
 ldx #0
:pf
 lsr gs_tmp
 lda #0
 bcc :z
 lda #$00FF
:z
 sta eg_f,x
 inx
 inx
 cpx #8
 bcc :pf
 lda gs_d
 jsr egs_off
 sta gs_do
 tax
 ldy gs_w
 sep #$20
 mx %10
:f
 lda eg_f
 sta >H_EGA,x
 lda eg_f+2
 sta >H_EGA1,x
 lda eg_f+4
 sta >H_EGA2,x
 lda eg_f+6
 sta >H_EGA3,x
 inx
 dey
 bne :f
 rep #$20
 mx %00
 jsr egs_vis
 bcc :vis
 ldx gs_do
 lda gs_w
 jmp eg_mkrun
:vis
 ldy gs_w                  ; X = the line's place on the screen: drawn,
 sep #$20                  ; whatever the flags said
 mx %10
 lda #0
:cf
 sta >EGA_DIRTY,x
 inx
 dey
 bne :cf
 rep #$20
 mx %00
 lda eg_di
 asl
 asl
 tax
 lda gs_w
 asl
 tay
 lda eg_fw
:px
 sta >SHR_PIX,x
 inx
 inx
 dey
 bne :px
 rts

*--- INT 10h in mode 0Dh (bios.s comes here)
* eg_0B - 0Bh: BH = 0, palette register 0 <- the colour BL; BH = 1,
* registers 1-3 <- the CGA's palette BL (0 green, red and brown; 1
* cyan, magenta and white)
eg_0B
 mx %00
 lda rBX
 and #$FF00
 bne :pal
 lda rBX
 and #$000F
 cmp #$0008
 bcc :st
 clc
 adc #8                    ; 8-15: 10h-17h
:st
 sep #$20
 mx %10
 sta >EGA_AC
 rep #$20
 mx %00
 bra :pd
:pal
 lda rBX
 and #$0001
 sta sv8
 sep #$20
 mx %10
 lda #2
 ora sv8
 sta >EGA_AC+1
 lda #4
 ora sv8
 sta >EGA_AC+2
 lda #6
 ora sv8
 sta >EGA_AC+3
 rep #$20
 mx %00
:pd
 lda #1
 sta >EGA_PALD
 rts

* eg_10 - 10h: AL = 0 palette register BL <- BH; 1 the overscan <- BH;
* 2 all sixteen and the overscan from the 17 bytes at ES:DX
eg_10
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
 and #$001F
 tax
 sep #$20
 mx %10
 lda rBX+1
 sta >EGA_AC,x
 rep #$20
 mx %00
 bra :pd
:over
 sep #$20
 mx %10
 lda rBX+1
 sta >EGA_AC+$11
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
 sta >EGA_AC,x
 iny
 cpy #16
 bcc :c
 lda [pGST],y
 sta >EGA_AC+$11
 rep #$20
 mx %00
:pd
 lda #1
 sta >EGA_PALD
 rts

* eg_11 - 11h, AL = 30h: where the font is. BH = 0 INT 1Fh's, 1 INT
* 43h's, 4 the 8x8's second half; anything else the 8x8 font, the only
* one there is. ES:BP -> it, CX = 8 bytes a character, DL = 24.
eg_11
 mx %00
 lda rAX
 and #$00FF
 cmp #$0030
 bne :out
 lda rBX
 xba
 and #$00FF
 beq :v1F
 cmp #1
 beq :v43
 cmp #4
 beq :hi
 lda #FONT_OFF
 bra :rom
:hi
 lda #FONT_OFF+1024
:rom
 sta rBP
 lda #BIOS_SEG
 bra :seg
:v1F
 lda >H_IVT+$7C
 sta rBP
 lda >H_IVT+$7E
 bra :seg
:v43
 lda >H_IVT+$10C
 sta rBP
 lda >H_IVT+$10E
:seg
 sta rES
 jsr svc_set_es
 lda #8
 sta rCX
 sep #$20
 mx %10
 lda #24
 sta rDX
 rep #$20
 mx %00
:out
 rts

* eg_12 - 12h, BL = 10h: the card. BH = 0 colour, BL = 3 256K, CH = 0
* the feature bits, CL = 7 the switches: a 200-line colour monitor, so
* the 350-line modes are not there to ask for.
eg_12
 mx %00
 lda rBX
 and #$00FF
 cmp #$0010
 bne :out
 lda #$0003
 sta rBX
 lda #$0007
 sta rCX
:out
 rts
