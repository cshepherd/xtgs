*----------------------------------------------------------
* video.s - the PC's 80x25 colour text buffer at B800:0000
* (host $2B:8000, 2,000 char/attribute words) rendered to
* the IIGS Super Hi-Res screen in 640 mode: 8x8 cells, 160
* bytes a line, 2 bits a pixel.
*
* Colour: with 2 bits a pixel and one palette, a cell gets
* four levels. Pixel value 3 is white, 2 light grey, 1 dark
* grey, 0 black, in every pixel position (the four palette
* groups of 640 mode are set identically). An attribute's
* foreground maps to 3 (bright, 8-15), 2 (normal, 1-7) or 0
* (black); its background to 1 (any colour) or 0 (black).
* Legibility first; CGA colour fidelity is later work.
*
* Rendering a cell: each of the 8 font rows is one byte,
* MSB the leftmost pixel; exp_tab turns it into the 16-bit
* pixel pair (value 3 where the bit is set), which is then
* masked: pixels = (exp & fgmask) | (~exp & bgmask), where
* a mask is the 2-bit level replicated eight times.
*----------------------------------------------------------

TXT_BASE  = $2B8000          ; B800:0000 in host memory
TXT_LEN   = 4000
ROW_BYTES = 1280             ; 8 scan lines x 160 bytes

*----------------------------------------------------------
* svc_init - SHR on, 640 mode, palette 0 for every line,
* pixels cleared. Preserves D; returns A = 0.
*----------------------------------------------------------
svc_init
 mx %00
 phb
 phk
 plb
 sep #$20
 mx %10
 lda >NEWVIDEO
 ora #$C0                  ; SHR on, linear
 sta >NEWVIDEO
 lda >BORDER
 and #$F0                  ; black border
 sta >BORDER
 rep #$20
 mx %00
 ldx #0
 lda #$8080                ; SCB: 640 mode, palette 0
:scb
 sta >SHR_SCB,x
 inx
 inx
 cpx #200
 bcc :scb
 ldx #0
:pal
 lda pal_tab,x
 sta >SHR_PAL,x
 inx
 inx
 cpx #32
 bcc :pal
 lda #0
 ldx #0
:clr
 sta >SHR_PIX,x
 inx
 inx
 cpx #32000
 bcc :clr
 plb
 lda #0
 rtl

* Palette 0: each 640-mode pixel group gets black, dark
* grey, light grey, white for values 0-3.
pal_tab
 dw $0000,$0555,$0AAA,$0FFF
 dw $0000,$0555,$0AAA,$0FFF
 dw $0000,$0555,$0AAA,$0FFF
 dw $0000,$0555,$0AAA,$0FFF

* Foreground level masks by colour 0-15, background by 0-7.
fg_mask
 dw $0000,$AAAA,$AAAA,$AAAA,$AAAA,$AAAA,$AAAA,$AAAA
 dw $5555,$FFFF,$FFFF,$FFFF,$FFFF,$FFFF,$FFFF,$FFFF
bg_mask
 dw $0000,$5555,$5555,$5555,$5555,$5555,$5555,$5555

*----------------------------------------------------------
* svc_render_all - every cell of the text buffer to the
* screen. Preserves D; returns A = 0.
*----------------------------------------------------------
svc_render_all
 mx %00
 phb
 phk
 plb
 lda #0
:row
 pha
 jsr render_row
 pla
 inc
 cmp #25
 bcc :row
 plb
 lda #0
 rtl

*----------------------------------------------------------
* svc_render_row - row A (0-24) to the screen.
*----------------------------------------------------------
svc_render_row
 mx %00
 phb
 phk
 plb
 jsr render_row
 plb
 lda #0
 rtl

*----------------------------------------------------------
* render_row - A = row. DBR = $04. Clobbers A, X, Y, sv0-sv3,
* pCELL, pTXT.
*----------------------------------------------------------
render_row
 mx %00
 sta sv3
 asl                       ; row * 160 = row * (128 + 32)
 asl
 asl
 asl
 asl
 sta sv2                   ; row * 32
 asl
 asl
 clc
 adc sv2                   ; row * 160 = text offset
 clc
 adc #TXT_BASE
 sta pTXT
 lda #^TXT_BASE
 sta pTXT+2
 lda sv3
 asl                       ; row * 1280 = row * 256 * 5
 asl
 asl
 asl
 asl
 asl
 asl
 asl
 sta sv2                   ; row * 256
 asl
 asl
 clc
 adc sv2
 clc
 adc #SHR_PIX
 sta pCELL
 lda #^SHR_PIX
 sta pCELL+2
 lda #80
 sta sv3
:cell
 jsr render_cell
 lda pTXT
 inc
 inc
 sta pTXT
 lda pCELL
 inc
 inc
 sta pCELL
 dec sv3
 bne :cell
 rts

* rrow - one font row (]1 = 0-7) of the cell: X = glyph
* offset, sv0/sv1 = fg/bg masks, pCELL = the cell's top line.
rrow mac
 lda font+]1,x
 and #$00FF
 asl
 tay
 lda exp_tab,y
 and sv0
 pha
 lda exp_tab,y
 eor #$FFFF
 and sv1
 ora 1,s
 ply
 ldy #]1*160
 sta [pCELL],y
 <<<

*----------------------------------------------------------
* render_cell - the char/attribute word at [pTXT] to the
* 8x8 cell at [pCELL]. DBR = $04. Clobbers A, X, Y, sv0, sv1.
*----------------------------------------------------------
render_cell
 mx %00
 lda [pTXT]                ; low: character, high: attribute
 pha
 and #$00FF
 asl
 asl
 asl
 tax                       ; X = glyph offset
 pla
 xba                       ; A low = attribute
 pha
 and #$000F
 asl
 tay
 lda fg_mask,y
 sta sv0
 pla
 lsr
 lsr
 lsr
 and #$000E
 tay
 lda bg_mask,y
 sta sv1
 rrow 0
 rrow 1
 rrow 2
 rrow 3
 rrow 4
 rrow 5
 rrow 6
 rrow 7
 rts

*----------------------------------------------------------
* svc_testframe - the M0 pattern into the text buffer: a
* title, every glyph twice (normal and inverse), the 16
* foreground and 8 background levels, corner markers.
* Preserves D; returns A = 0.
*----------------------------------------------------------
svc_testframe
 mx %00
 phb
 phk
 plb
 lda #TXT_BASE
 sta pTXT
 lda #^TXT_BASE
 sta pTXT+2
 ldy #0
 lda #$0720                ; space on grey
:clear
 sta [pTXT],y
 iny
 iny
 cpy #TXT_LEN
 bcc :clear
* Row 0: the title, bright white.
 ldx #0
 ldy #0
 sep #$20
 mx %10
:title
 lda msg_title,x
 beq :title_done
 sta [pTXT],y
 iny
 lda #$0F
 sta [pTXT],y
 iny
 inx
 bra :title
:title_done
 rep #$20
 mx %00
* Rows 2-9: glyphs $00-$FF, 32 a row, at column 0 on grey
* and at column 40 inverse.
 ldx #0                    ; glyph
 ldy #2*160
:glyphs
 txa
 and #$00FF
 ora #$0700
 sta [pTXT],y
 ora #$7000
 and #$70FF                ; attribute $70: black on grey
 pha
 tya
 clc
 adc #80                   ; 40 columns right
 tay
 pla
 sta [pTXT],y
 tya
 sec
 sbc #80
 tay
 iny
 iny
 inx
 txa
 and #$001F
 bne :glyphs
 tya
 clc
 adc #96                   ; next row: 160 - 64
 tay
 cpx #256
 bcc :glyphs
* Row 12: 'A'-'P' in foreground colours 0-15 on black; row
* 13: 'a'-'h' in white on backgrounds 0-7.
 ldy #12*160
 ldx #0
:fgl
 txa
 xba                       ; attribute = colour in the high byte
 sta sv0
 txa
 clc
 adc #'A'
 and #$00FF
 ora sv0
 sta [pTXT],y
 iny
 iny
 inx
 cpx #16
 bcc :fgl
 ldy #13*160
 ldx #0
:bgl
 txa
 asl
 asl
 asl
 asl
 ora #$000F                ; white on background X
 xba
 sta sv0
 txa
 clc
 adc #'a'
 and #$00FF
 ora sv0
 sta [pTXT],y
 iny
 iny
 inx
 cpx #8
 bcc :bgl
* Corners: 'X' bright at (0,79), (24,0), (24,79).
 lda #$0F58
 ldy #79*2
 sta [pTXT],y
 ldy #24*160
 sta [pTXT],y
 ldy #24*160+79*2
 sta [pTXT],y
 plb
 lda #0
 rtl

msg_title asc 'XT/GS M0  80x25 TEXT ON SUPER HI-RES 640',00
