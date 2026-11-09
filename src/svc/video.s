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
 jsr init_shr
 plb
 lda #0
 rtl
init_shr                   ; DBR = $04
 mx %00
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
 rts

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

*==========================================================
* The text screen as the PC sees it: operations on the
* B800 buffer that mark rows dirty, flushed once a frame.
*==========================================================
BLANK      = $0720           ; space, light grey on black

dirty_rows ds 25
dirty_any  dw 0
cur_on     dw 0              ; an underline cursor is drawn
cur_at     dw 0              ; where: col | row<<8
blink      dw 0              ; frame counter; bit 5 = cursor visible
tty_attr   dw $FFFF          ; $FFFF: teletype keeps the cell's attribute

mark_row                   ; A = row
 mx %00
 cmp #25
 bcs :out
 tax
 sep #$20
 mx %10
 lda #1
 sta dirty_rows,x
 sta dirty_any
 rep #$20
 mx %00
:out
 rts
mark_all
 mx %00
 ldx #0
 sep #$20
 mx %10
 lda #1
:l
 sta dirty_rows,x
 inx
 cpx #25
 bcc :l
 sta dirty_any
 rep #$20
 mx %00
 rts

* row_off - A = row -> A = row*160
row_off
 mx %00
 asl
 asl
 asl
 asl
 asl
 sta sv9
 asl
 asl
 clc
 adc sv9
 rts
* cell_off - A = col | row<<8 -> A = row*160 + col*2 (text buffer offset)
cell_off
 mx %00
 pha
 xba
 and #$00FF
 jsr row_off
 sta sv9
 pla
 and #$00FF
 asl
 clc
 adc sv9
 rts
* cell_shr - A = col | row<<8 -> A = row*1280 + col*2 (SHR offset)
cell_shr
 mx %00
 pha
 xba
 and #$00FF
 asl
 asl
 asl
 asl
 asl
 asl
 asl
 asl
 sta sv9
 asl
 asl
 clc
 adc sv9
 sta sv9
 pla
 and #$00FF
 asl
 clc
 adc sv9
 rts
* cell_ptrs - sv4 = row, sv5 = col -> pTXT, pCELL for render_cell
cell_ptrs
 mx %00
 lda sv4
 jsr row_off
 clc
 adc sv5
 clc
 adc sv5
 clc
 adc #TXT_BASE
 sta pTXT
 lda #^TXT_BASE
 sta pTXT+2
 lda sv4
 xba
 ora sv5
 jsr cell_shr
 clc
 adc #SHR_PIX
 sta pCELL
 lda #^SHR_PIX
 sta pCELL+2
 rts

*--- svc_flush: dirty rows, then the cursor
svc_flush
 mx %00
 phb
 phk
 plb
 jsr flush
 plb
 rtl
flush
 mx %00
 lda dirty_any
 beq :cursor
 stz dirty_any
 lda #0
:row
 pha
 tax
 sep #$20
 mx %10
 lda dirty_rows,x
 stz dirty_rows,x
 rep #$20
 mx %00
 and #$00FF
 beq :next
 lda 1,s
 jsr render_row
 lda cur_on                ; the row's cursor underline went with it
 beq :next
 lda cur_at
 xba
 and #$00FF
 cmp 1,s
 bne :next
 stz cur_on
:next
 pla
 inc
 cmp #25
 bcc :row
:cursor
 lda blink
 and #$0020
 bne :want
 lda cur_on
 beq :done
 jmp cursor_erase
:want
 lda >H_BDA+BDA_CURPOS
 sta sv8
 lda cur_on
 beq :draw
 lda cur_at
 cmp sv8
 beq :done
 jsr cursor_erase
:draw
 lda sv8
 sta cur_at
 jsr cursor_draw
 lda #1
 sta cur_on
:done
 rts
cursor_draw                ; underline (pixel rows 6-7) at cur_at
 mx %00
 lda cur_at
 jsr cell_shr
 tax
 lda #$FFFF
 sta >SHR_PIX+960,x
 sta >SHR_PIX+1120,x
 rts
cursor_erase               ; re-render the cell under the cursor
 mx %00
 lda cur_at
 xba
 and #$00FF
 sta sv4
 lda cur_at
 and #$00FF
 sta sv5
 jsr cell_ptrs
 jsr render_cell
 stz cur_on
 rts

*--- vid_clear: the whole buffer blank, cursor home
vid_clear
 mx %00
 ldx #$8000
 lda #BLANK
:f
 sta >H_TXTBANK,x
 inx
 inx
 cpx #$8000+TXT_LEN
 bcc :f
 lda #0
 sta >H_BDA+BDA_CURPOS
 jmp mark_all

*--- vid_tty: A = character (low byte). BIOS teletype on page
* 0: BEL ignored, BS, CR, LF with scrolling, else the character
* at the cursor (attribute kept unless tty_attr says otherwise)
* and the cursor advances with wrap.
vid_tty
 mx %00
 and #$00FF
 sta sv0
 lda >H_BDA+BDA_CURPOS
 and #$00FF
 sta sv1                   ; col
 lda >H_BDA+BDA_CURPOS
 xba
 and #$00FF
 sta sv2                   ; row
 lda sv0
 cmp #$0D
 beq :cr
 cmp #$0A
 beq :lf
 cmp #$08
 beq :bs
 cmp #$07
 beq :done
 lda sv2
 jsr row_off
 clc
 adc sv1
 clc
 adc sv1
 clc
 adc #$8000
 tax
 lda tty_attr
 cmp #$FFFF
 beq :charonly
 xba
 and #$FF00
 ora sv0
 sta >H_TXTBANK,x
 bra :advance
:charonly
 sep #$20
 mx %10
 lda sv0
 sta >H_TXTBANK,x
 rep #$20
 mx %00
:advance
 lda sv2
 jsr mark_row
 inc sv1
 lda sv1
 cmp #80
 bcc :store
 stz sv1
:lf
 inc sv2
 lda sv2
 cmp #25
 bcc :store
 dec sv2
 jsr vid_scroll_all
 bra :store
:cr
 stz sv1
 bra :store
:bs
 lda sv1
 beq :store
 dec sv1
:store
 lda sv2
 xba
 ora sv1
 sta >H_BDA+BDA_CURPOS
:done
 rts

*--- vid_scroll_all: up one line, the last row blank
vid_scroll_all
 mx %00
 phb
 ldx #$80A0
 ldy #$8000
 lda #TXT_LEN-160-1
 mvn $2B,$2B
 plb
 ldx #$8000+TXT_LEN-160
 lda #BLANK
:f
 sta >H_TXTBANK,x
 inx
 inx
 cpx #$8000+TXT_LEN
 bcc :f
 jmp mark_all

*--- vid_scroll_win: INT 10h 06/07. sv0 = lines (0 = clear),
* sv1 = blank word, sv2 = top, sv3 = left, sv4 = bottom,
* sv5 = right, sv6 = 0 up / 1 down.
vid_scroll_win
 mx %00
 lda sv4
 cmp #25
 bcc :b1
 lda #24
 sta sv4
:b1
 lda sv5
 cmp #80
 bcc :b2
 lda #79
 sta sv5
:b2
 lda sv4
 sec
 sbc sv2
 bpl :go
 rts
:go
 inc
 sta sv7                   ; height
 lda sv0
 beq :clear
 cmp sv7
 bcs :clear
 lda sv6
 bne :down
 lda sv2
 sta sv8                   ; up: dst rows from the top
:uploop
 lda sv8
 clc
 adc sv0
 cmp sv4
 beq :upcopy
 bcs :upblank
:upcopy
 sta sv9                   ; src = dst + lines
 jsr copy_row
 inc sv8
 bra :uploop
:upblank
 lda sv8
 cmp sv4
 beq :ub
 bcs :marks
:ub
 jsr blank_row
 inc sv8
 bra :upblank
:down
 lda sv4
 sta sv8                   ; down: dst rows from the bottom
:dnloop
 lda sv8
 cmp sv0
 bcc :dnblank
 sec
 sbc sv0
 cmp sv2
 bcc :dnblank
 sta sv9                   ; src = dst - lines
 jsr copy_row
 dec sv8
 bra :dnloop
:dnblank
 lda sv8
 cmp #25
 bcs :marks
 cmp sv2
 bcc :marks
 jsr blank_row
 dec sv8
 bra :dnblank
:clear
 lda sv2
 sta sv8
:cl
 lda sv8
 cmp sv4
 beq :cl1
 bcs :marks
:cl1
 jsr blank_row
 inc sv8
 bra :cl
:marks
 lda sv2
:mk
 cmp sv4
 beq :mk1
 bcs :out
:mk1
 pha
 jsr mark_row
 pla
 inc
 bra :mk
:out
 rts
copy_row                   ; row sv9 -> row sv8, columns sv3..sv5
 mx %00
 lda sv9
 jsr row_off
 clc
 adc #TXT_BASE
 sta pTXT
 lda #^TXT_BASE
 sta pTXT+2
 lda sv8
 jsr row_off
 clc
 adc #TXT_BASE
 sta pCELL
 lda #^TXT_BASE
 sta pCELL+2
 lda sv5
 asl
 sta sv9
 lda sv3
 asl
 tay
:c
 lda [pTXT],y
 sta [pCELL],y
 iny
 iny
 tya
 cmp sv9
 bcc :c
 beq :c
 rts
blank_row                  ; row sv8, columns sv3..sv5 <- sv1
 mx %00
 lda sv8
 jsr row_off
 clc
 adc #TXT_BASE
 sta pCELL
 lda #^TXT_BASE
 sta pCELL+2
 lda sv5
 asl
 sta sv9
 lda sv3
 asl
 tay
:b
 lda sv1
 sta [pCELL],y
 iny
 iny
 tya
 cmp sv9
 bcc :b
 beq :b
 rts
