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
gfx_mode   dw 0              ; 0 = text; 4/5 = CGA 320x200x4 graphics (SCREEN 1)

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
 lda gfx_mode
 beq :txt
 jmp gfx_flush            ; CGA graphics: repack only dirty scanlines (rts)
:txt
 jsr pages_to_rows
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
* pages_to_rows - the core's 256-byte page marks (direct B800 writes)
* become dirty rows: page p covers rows p*256/160 .. (p*256+255)/160.
pages_to_rows
 mx %00
 ldx #0
:p
 lda >VID_DIRTY,x
 and #$00FF
 beq :next
 lda #0
 sep #$20
 mx %10
 sta >VID_DIRTY,x
 rep #$20
 mx %00
 lda page_row0,x
 and #$00FF
 pha
 lda page_row1,x
 and #$00FF
 sta sv9
 pla
:r
 cmp sv9
 beq :last
 bcs :next
:last
 pha
 jsr mark_row
 pla
 inc
 cmp sv9
 bcc :r
 beq :r
:next
 inx
 cpx #16
 bcc :p
 rts
page_row0 hex 00010304060809
 hex 0B0C0E0F11121416
 hex 1718
page_row1 hex 01030406080A0B
 hex 0D0E101113141617
 hex 1818
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

*--- post_banner: the boot-time BIOS sign-on, teletyped into
* the freshly-cleared screen at the home cursor before the
* guest's boot sector runs, so it reads like a PC POST: a
* title line and the conventional-RAM figure (from the BDA,
* not a second copy of the constant). Drawn in bright white
* via tty_attr, restored to "keep the cell attribute" after.
post_banner
 mx %00
 lda #$000F                ; white on black (attribute in tty_attr's low byte)
 sta tty_attr
 ldx #0
:t
 lda post_msg,x
 and #$00FF
 beq :ram
 phx
 jsr vid_tty
 plx
 inx
 bra :t
:ram
 lda >H_BDA+BDA_MEMKB      ; the conventional RAM figure, in KB
 jsr post_dec             ; e.g. "640"
 ldx #0
:k
 lda post_kb,x
 and #$00FF
 beq :done
 phx
 jsr vid_tty
 plx
 inx
 bra :k
:done
 lda #$FFFF                ; teletype keeps each cell's attribute again
 sta tty_attr
 rts

*--- post_dec: teletype the 16-bit value in A as decimal with
* no leading zeros. State lives in sv6/sv7/sv8 (vid_tty only
* touches sv0-sv2); X is saved around each vid_tty.
post_dec
 mx %00
 sta sv6                   ; the running value
 stz sv7                   ; 0 until the first significant digit prints
 ldx #0
:place
 lda post_pow,x
 bmi :units                ; $FFFF sentinel = the ones place (always print)
 sta sv8
 ldy #0
:sub
 lda sv6
 cmp sv8
 bcc :emit
 sec
 sbc sv8
 sta sv6
 iny
 bra :sub
:emit
 tya
 ora sv7                   ; print this digit if non-zero or one already did
 beq :next
 tya
 ora #$0030
 phx
 jsr vid_tty
 plx
 lda #1
 sta sv7
:next
 inx
 inx
 bra :place
:units
 lda sv6
 ora #$0030
 phx
 jsr vid_tty
 plx
 rts

post_msg  asc 'XT/GS 65816 Native BIOS Active'
          hex 0D0A00
post_kb   asc ' KB RAM OK'
          hex 0D0A0D0A00
post_pow  dw 10000,1000,100,10
          dw $FFFF

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
 bne :lj1
 jmp :cr
:lj1
 cmp #$0A
 beq :lf
 cmp #$08
 bne :lj2
 jmp :bs
:lj2
 cmp #$07
 bne :lj3
 jmp :done
:lj3
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
 bne :lj4
 jmp :clear
:lj4
 cmp sv7
 bcc :lj5
 jmp :clear
:lj5
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
 bcc :lj6
 jmp :marks
:lj6
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

*==========================================================
* CGA graphics (SCREEN 1): mode 4/5, 320x200x4. The guest's
* CGA framebuffer is the same B800 segment ($2B:8000, 16 KB)
* used for text, but as a bitmap: 2 bits a pixel, 4 pixels a
* byte, 80 bytes a scanline, even scanlines at B800:0000 and
* odd scanlines at B800:2000 (the CGA interleave). It is
* repacked each frame into IIGS SHR 320 mode (4 bits a pixel,
* 2 pixels a byte, 160 bytes a line, linear at $E1:2000) via
* a 256-entry expand table. vid_setmode switches in and out.
*==========================================================
CGA_SRC    = $2B8000          ; B800:0000, the even field
CGA_ODD    = $2BA000          ; B800:2000, the odd field

* vid_setmode - A = BIOS video mode (low 7 bits). Modes 4 and
* 5 select CGA 320 graphics; everything else is text. DBR=$04.
vid_setmode
 mx %00
 and #$00FF
 cmp #4
 bcc :text                 ; 0-3: text
 cmp #7
 bcs :text                 ; 7+: text
 sta gfx_mode              ; 4/5 (320x200x4) or 6 (640x200 mono)
 jmp gfx_setup
:text
 stz gfx_mode
 jsr init_shr              ; 640 text mode, text palette, pixels cleared
 jmp vid_clear             ; blank the text buffer, home the cursor (rts)

* gfx_setup - SHR to 320 mode, CGA palette, screen and the CGA
* framebuffer cleared. DBR=$04.
gfx_setup
 mx %00
 ldx #0                    ; clear the 64 dirty-page marks
 sep #$20
 mx %10
 lda #0
:cd
 sta >VID_DIRTY,x
 inx
 cpx #64
 bcc :cd
 rep #$20
 mx %00
 lda gfx_mode              ; SCB + palette depend on the mode
 cmp #6
 beq :m6
 ldx #0                    ; 320 mode: SCB $00 (320, palette 0) on every line
 lda #$0000
:scb3
 sta >SHR_SCB,x
 inx
 inx
 cpx #200
 bcc :scb3
 lda #0                    ; default: palette 1, non-intensified, bg 0
 sta cga_bg                ; (faithful CGA: cyan/magenta/white; palette 0 is
 sta cga_int               ; green/red/brown)
 lda #1
 sta cga_pal
 stz cga_pd
 jsr cga_setpal
 bra :clrpix
:m6
 ldx #0                    ; 640 mode: SCB $80 on every line
 lda #$8080
:scb6
 sta >SHR_SCB,x
 inx
 inx
 cpx #200
 bcc :scb6
 jsr cga_setpal6
:clrpix
 ldx #0                    ; clear 32000 SHR pixel bytes
 lda #0
:clr
 sta >SHR_PIX,x
 inx
 inx
 cpx #32000
 bcc :clr
 lda #<CGA_SRC             ; clear the 16 KB CGA framebuffer
 sta gDST
 lda #^CGA_SRC
 sta gDST+2
 ldy #0
 lda #0
:cfb
 sta [gDST],y
 iny
 iny
 cpy #$4000
 bcc :cfb
 rts

* cga_setpal - set SHR palette 0 entries 0-3 for 320 mode from the
* current CGA background/palette/intensity. Entry 0 = background,
* 1-3 = the selected palette's three foreground colours. DBR=$04.
cga_setpal
 mx %00
 lda cga_bg                ; entry 0 = cga_rgb[background]
 and #$000F
 asl
 tax
 lda cga_rgb,x
 sta >SHR_PAL
 lda cga_pal               ; combo = pal*2 + intensity ; base = combo*3
 and #$0001
 asl
 clc
 adc cga_int
 sta gL
 asl
 clc
 adc gL                    ; base into fg_tab (0,3,6,9)
 tax
 lda fg_tab,x              ; entry 1
 and #$00FF
 asl
 phx
 tax
 lda cga_rgb,x
 sta >SHR_PAL+2
 plx
 inx
 lda fg_tab,x              ; entry 2
 and #$00FF
 asl
 phx
 tax
 lda cga_rgb,x
 sta >SHR_PAL+4
 plx
 inx
 lda fg_tab,x              ; entry 3
 and #$00FF
 asl
 tax
 lda cga_rgb,x
 sta >SHR_PAL+6
 rts

* cga_setpal6 - 640-mode mono palette: cga640_tab emits pixel value
* 0 (black) or 3 (white); in 640 mode the four pixel positions read
* groups based at entries 8,12,0,4, so make entry base+0 black and
* base+3 white for each group. DBR=$04.
cga_setpal6
 mx %00
 ldx #0
 lda #$0000
:z
 sta >SHR_PAL,x
 inx
 inx
 cpx #32
 bcc :z
 lda #$0FFF
 sta >SHR_PAL+6            ; entry 3  (group at base 0)
 sta >SHR_PAL+14          ; entry 7  (group at base 4)
 sta >SHR_PAL+22          ; entry 11 (group at base 8)
 sta >SHR_PAL+30          ; entry 15 (group at base 12)
 rts

* gfx_flush - repack only the scanlines the guest changed since the
* last frame. The core sets 64 dirty-page bits in VID_DIRTY (cpu.s
* vid_mark, one per 256 bytes of the B800 bank). Each page maps to a
* short run of rows in its field (gpg_r0/gpg_r1); pages 0-31 are the
* even field, 32-63 the odd, and screen line = row*2 + parity. A
* scanline that straddles two pages is fully re-blitted whenever
* either page is dirty, so nothing is missed. DBR=$04.
gfx_flush
 mx %00
 lda cga_pd               ; apply a pending COLOR / 3D9h palette change
 beq :nopd
 stz cga_pd
 lda gfx_mode
 cmp #6
 beq :nopd                ; mode 6 palette is fixed mono
 jsr cga_setpal
:nopd
 stz gPG
:pg
 ldx gPG
 lda >VID_DIRTY,x
 and #$00FF
 beq :next
 lda #0                    ; consume the dirty mark
 sep #$20
 mx %10
 sta >VID_DIRTY,x
 rep #$20
 mx %00
 lda gPG                   ; parity + position within the field
 cmp #32
 bcc :even
 sec
 sbc #32
 ldy #1
 bra :pos
:even
 ldy #0
:pos
 sty gPAR
 tax                       ; X = page position 0-31
 lda gpg_r0,x
 and #$00FF
 sta gROW
 lda gpg_r1,x
 and #$00FF
 sta gR1
:rows
 lda gROW
 cmp #100
 bcs :next                 ; past the last real row
 asl                       ; row*2
 ora gPAR                  ; + parity = screen line
 jsr gfx_blit_line
 lda gROW
 inc
 sta gROW
 cmp gR1
 bcc :rows
 beq :rows
:next
 lda gPG
 inc
 sta gPG
 cmp #64
 bcc :pg
 rts

* gfx_blit_line - repack one scanline (A = screen line 0-199) from
* the CGA framebuffer into SHR 320. DBR=$04. Clobbers A/X/Y and
* gL/gO/gE/gSRC/gDST.
gfx_blit_line
 mx %00
 pha                       ; keep the line on the stack
 lda 1,s                   ; dst = $E1:2000 + line*160
 asl
 asl
 asl
 asl
 asl                       ; line*32
 sta gL
 asl
 asl                       ; line*128
 clc
 adc gL                    ; line*160
 clc
 adc #<SHR_PIX
 sta gDST
 lda #^SHR_PIX
 sta gDST+2
 lda 1,s                   ; fieldbase from parity
 and #$0001
 beq :even
 lda #$A000
 bra :row
:even
 lda #$8000
:row
 sta gE
 lda 1,s                   ; src = fieldbase + (line>>1)*80
 lsr
 sta gL                    ; row = line>>1
 asl
 asl
 asl
 asl                       ; row*16
 sta gO
 lda gL
 asl
 asl
 asl
 asl
 asl
 asl                       ; row*64
 clc
 adc gO                    ; row*80
 clc
 adc gE                    ; + fieldbase
 sta gSRC
 lda #^CGA_SRC
 sta gSRC+2
 ldy #80                   ; 80 CGA bytes -> 160 SHR bytes
 lda gfx_mode
 cmp #6
 beq :px6
:px3                       ; 320 mode: one byte -> two 4bpp bytes
 lda [gSRC]
 and #$00FF
 asl
 tax
 lda cga320_tab,x
 sta [gDST]
 inc gSRC
 inc gDST
 inc gDST
 dey
 bne :px3
 pla
 rts
:px6                       ; 640 mode: one byte -> two 2bpp (mono) bytes
 lda [gSRC]
 and #$00FF
 asl
 tax
 lda cga640_tab,x
 sta [gDST]
 inc gSRC
 inc gDST
 inc gDST
 dey
 bne :px6
 pla
 rts

* gpg_r0/gpg_r1 - for page position p (0-31) within a field, the
* first and last row-in-field its 256 bytes touch (row = offset/80,
* clamped to 99). Built by tools; see docs/cga.md.
gpg_r0
 hex 000306090C101316191C202326292C30
 hex 3336393C404346494C505356595C6063
gpg_r1
 hex 0306090C0F1316191C1F2326292C2F33
 hex 36393C3F4346494C4F5356595C5F6363

* cga320_tab - one CGA byte (4 pixels x 2 bits) -> a word = two
* SHR 320 bytes (4 pixels x 4 bits). CGA pixel value n maps to
* SHR palette index n (palette 0 holds the CGA colours).
cga320_tab
 dw $0000,$0100,$0200,$0300,$1000,$1100,$1200,$1300
 dw $2000,$2100,$2200,$2300,$3000,$3100,$3200,$3300
 dw $0001,$0101,$0201,$0301,$1001,$1101,$1201,$1301
 dw $2001,$2101,$2201,$2301,$3001,$3101,$3201,$3301
 dw $0002,$0102,$0202,$0302,$1002,$1102,$1202,$1302
 dw $2002,$2102,$2202,$2302,$3002,$3102,$3202,$3302
 dw $0003,$0103,$0203,$0303,$1003,$1103,$1203,$1303
 dw $2003,$2103,$2203,$2303,$3003,$3103,$3203,$3303
 dw $0010,$0110,$0210,$0310,$1010,$1110,$1210,$1310
 dw $2010,$2110,$2210,$2310,$3010,$3110,$3210,$3310
 dw $0011,$0111,$0211,$0311,$1011,$1111,$1211,$1311
 dw $2011,$2111,$2211,$2311,$3011,$3111,$3211,$3311
 dw $0012,$0112,$0212,$0312,$1012,$1112,$1212,$1312
 dw $2012,$2112,$2212,$2312,$3012,$3112,$3212,$3312
 dw $0013,$0113,$0213,$0313,$1013,$1113,$1213,$1313
 dw $2013,$2113,$2213,$2313,$3013,$3113,$3213,$3313
 dw $0020,$0120,$0220,$0320,$1020,$1120,$1220,$1320
 dw $2020,$2120,$2220,$2320,$3020,$3120,$3220,$3320
 dw $0021,$0121,$0221,$0321,$1021,$1121,$1221,$1321
 dw $2021,$2121,$2221,$2321,$3021,$3121,$3221,$3321
 dw $0022,$0122,$0222,$0322,$1022,$1122,$1222,$1322
 dw $2022,$2122,$2222,$2322,$3022,$3122,$3222,$3322
 dw $0023,$0123,$0223,$0323,$1023,$1123,$1223,$1323
 dw $2023,$2123,$2223,$2323,$3023,$3123,$3223,$3323
 dw $0030,$0130,$0230,$0330,$1030,$1130,$1230,$1330
 dw $2030,$2130,$2230,$2330,$3030,$3130,$3230,$3330
 dw $0031,$0131,$0231,$0331,$1031,$1131,$1231,$1331
 dw $2031,$2131,$2231,$2331,$3031,$3131,$3231,$3331
 dw $0032,$0132,$0232,$0332,$1032,$1132,$1232,$1332
 dw $2032,$2132,$2232,$2332,$3032,$3132,$3232,$3332
 dw $0033,$0133,$0233,$0333,$1033,$1133,$1233,$1333
 dw $2033,$2133,$2233,$2333,$3033,$3133,$3233,$3333

* cga640_tab - one CGA mode-6 byte (8 px x 1 bit) -> a word = two
* SHR 640-mode bytes. Each CGA bit becomes a 2-bit pixel value 3
* (white) or 0 (black); cga_setpal6 makes those render mono.
cga640_tab
 dw $0000,$0300,$0C00,$0F00,$3000,$3300,$3C00,$3F00
 dw $C000,$C300,$CC00,$CF00,$F000,$F300,$FC00,$FF00
 dw $0003,$0303,$0C03,$0F03,$3003,$3303,$3C03,$3F03
 dw $C003,$C303,$CC03,$CF03,$F003,$F303,$FC03,$FF03
 dw $000C,$030C,$0C0C,$0F0C,$300C,$330C,$3C0C,$3F0C
 dw $C00C,$C30C,$CC0C,$CF0C,$F00C,$F30C,$FC0C,$FF0C
 dw $000F,$030F,$0C0F,$0F0F,$300F,$330F,$3C0F,$3F0F
 dw $C00F,$C30F,$CC0F,$CF0F,$F00F,$F30F,$FC0F,$FF0F
 dw $0030,$0330,$0C30,$0F30,$3030,$3330,$3C30,$3F30
 dw $C030,$C330,$CC30,$CF30,$F030,$F330,$FC30,$FF30
 dw $0033,$0333,$0C33,$0F33,$3033,$3333,$3C33,$3F33
 dw $C033,$C333,$CC33,$CF33,$F033,$F333,$FC33,$FF33
 dw $003C,$033C,$0C3C,$0F3C,$303C,$333C,$3C3C,$3F3C
 dw $C03C,$C33C,$CC3C,$CF3C,$F03C,$F33C,$FC3C,$FF3C
 dw $003F,$033F,$0C3F,$0F3F,$303F,$333F,$3C3F,$3F3F
 dw $C03F,$C33F,$CC3F,$CF3F,$F03F,$F33F,$FC3F,$FF3F
 dw $00C0,$03C0,$0CC0,$0FC0,$30C0,$33C0,$3CC0,$3FC0
 dw $C0C0,$C3C0,$CCC0,$CFC0,$F0C0,$F3C0,$FCC0,$FFC0
 dw $00C3,$03C3,$0CC3,$0FC3,$30C3,$33C3,$3CC3,$3FC3
 dw $C0C3,$C3C3,$CCC3,$CFC3,$F0C3,$F3C3,$FCC3,$FFC3
 dw $00CC,$03CC,$0CCC,$0FCC,$30CC,$33CC,$3CCC,$3FCC
 dw $C0CC,$C3CC,$CCCC,$CFCC,$F0CC,$F3CC,$FCCC,$FFCC
 dw $00CF,$03CF,$0CCF,$0FCF,$30CF,$33CF,$3CCF,$3FCF
 dw $C0CF,$C3CF,$CCCF,$CFCF,$F0CF,$F3CF,$FCCF,$FFCF
 dw $00F0,$03F0,$0CF0,$0FF0,$30F0,$33F0,$3CF0,$3FF0
 dw $C0F0,$C3F0,$CCF0,$CFF0,$F0F0,$F3F0,$FCF0,$FFF0
 dw $00F3,$03F3,$0CF3,$0FF3,$30F3,$33F3,$3CF3,$3FF3
 dw $C0F3,$C3F3,$CCF3,$CFF3,$F0F3,$F3F3,$FCF3,$FFF3
 dw $00FC,$03FC,$0CFC,$0FFC,$30FC,$33FC,$3CFC,$3FFC
 dw $C0FC,$C3FC,$CCFC,$CFFC,$F0FC,$F3FC,$FCFC,$FFFC
 dw $00FF,$03FF,$0CFF,$0FFF,$30FF,$33FF,$3CFF,$3FFF
 dw $C0FF,$C3FF,$CCFF,$CFFF,$F0FF,$F3FF,$FCFF,$FFFF

* cga_rgb - the 16 CGA colours as IIGS $0RGB palette words.
cga_rgb
 dw $0000,$000A,$00A0,$00AA,$0A00,$0A0A,$0A50,$0AAA
 dw $0555,$055F,$05F5,$05FF,$0F55,$0F5F,$0FF5,$0FFF

* fg_tab - CGA foreground colour indices for the four (palette,
* intensity) combos, three per combo: pal0/i0, pal0/i1, pal1/i0,
* pal1/i1. pal0 = green/red/brown, pal1 = cyan/magenta/white.
fg_tab
 hex 0204060A0C0E0305070B0D0F



*==========================================================
* WIP, NOT WIRED IN: no caller, and not yet confirmed to emit
* sound under MAME in this ProDOS 8 environment (see memory
* xtgs-doc-sound). The reference that does work is
* ../somi-iigs-port/iigs/asm/audio_doc.s (GS/OS).
*
* PC speaker via the Ensoniq DOC (ES5503), after somi-iigs-
* port's audio_doc.s but reaching the sound GLU at $E0:C03C
* (MAME maps $E0:C000-C07F to the GLU unconditionally, unlike
* bank 0 which depends on the I/O soft switch). One oscillator
* free-runs a 256-byte square wave (no $00, which would halt
* it); its frequency tracks the guest PIT. Init follows the
* DOC bring-up: halt all 32 oscillators, zero all volumes,
* enable one, configure, then key it on.
*==========================================================
SGCTL  = $E0C03C
SGDATA = $E0C03D
SGADRL = $E0C03E
SGADRH = $E0C03F
R_FCL  = $00
R_FCH  = $20
R_VOL  = $40
R_PTR  = $80
R_CTL  = $A0
R_SIZ  = $C0
R_OSCENA = $E1

snd_vol    dw 0
snd_ctlreg dw 0              ; registers + auto-increment + volume
snd_ctlram dw 0              ; RAM + auto-increment + volume
snd_fc     dw 0

* snd_wreg - DOC register X(8) = A(8). 8-bit A/X. DBR any.
snd_wreg
 pha
 lda snd_ctlreg
 sta >SGCTL
 txa
 sta >SGADRL
 lda #0
 sta >SGADRH
 pla
 sta >SGDATA
 rts

* snd_fill - Y bytes of A to the DOC target the address points at. 8-bit.
snd_fill
:l sta >SGDATA
 dey
 bne :l
 rts

* snd_init - silence the DOC, load the square wave, enable one
* oscillator, configure it. DBR=$04. 16-bit in/out.
snd_init
 mx %00
 php
 sei
 sep #$30
 mx %11
 lda #$0F                  ; master volume (full)
 sta snd_vol
 ora #$20
 sta snd_ctlreg            ; registers, auto-increment, volume
 lda snd_vol
 ora #$60
 sta snd_ctlram            ; RAM, auto-increment, volume
 lda snd_ctlreg            ; halt all 32 oscillators
 sta >SGCTL
 lda #R_CTL
 sta >SGADRL
 lda #0
 sta >SGADRH
 ldy #32
 lda #$01
 jsr snd_fill
 lda snd_ctlreg            ; all 32 volumes 0
 sta >SGCTL
 lda #R_VOL
 sta >SGADRL
 lda #0
 sta >SGADRH
 ldy #32
 lda #0
 jsr snd_fill
 lda snd_ctlram            ; square wave to DOC RAM page 0
 sta >SGCTL
 lda #0
 sta >SGADRL
 sta >SGADRH
 ldx #0
:sq
 lda sqwave,x
 sta >SGDATA
 inx
 bne :sq
 ldx #R_OSCENA             ; enable 1 oscillator ((1-1)*2 = 0)
 lda #0
 jsr snd_wreg
 ldx #R_VOL                ; osc 0 volume full
 lda #$FF
 jsr snd_wreg
 ldx #R_PTR                ; wavetable page 0
 lda #0
 jsr snd_wreg
 ldx #R_SIZ                ; 256 bytes, resolution 0
 lda #0
 jsr snd_wreg
 ldx #R_FCL
 lda #0
 jsr snd_wreg
 ldx #R_FCH
 lda #0
 jsr snd_wreg
 ldx #R_CTL                ; halted
 lda #$01
 jsr snd_wreg
 rep #$30
 mx %00
 plp
 rts

sqwave
 hex FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
 hex FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
 hex FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
 hex FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
 hex 01010101010101010101010101010101
 hex 01010101010101010101010101010101
 hex 01010101010101010101010101010101
 hex 01010101010101010101010101010101
