*----------------------------------------------------------
* gtext.s - the BIOS's text in the CGA graphics modes.
*
* In modes 4/5 (320x200, 40 columns) and 6 (640x200, 80
* columns) B800 holds pixels, and INT 10h's character
* services draw the 8x8 font into them, as a PC's BIOS does:
* write character (09h/0Ah: BL the colour, bit 7 XOR),
* teletype (0Eh), scroll and clear a window (06h/07h: BH the
* byte the freed lines are filled with), read character (08h:
* the cell's pixels matched against the font) and the pixel
* calls (0Ch/0Dh). video.s and bios.s come here when gt_on
* says so; the 160x100 mode is text cells and does not.
*
* A character row is four lines of the even field and four
* of the odd ($2000 further on); a cell is two bytes wide in
* 320 mode and one in 640. Every byte written marks its page
* in VID_DIRTY, which is what gfx_flush draws from. DBR=SVC.
*----------------------------------------------------------
gt_ch      dw 0              ; the character
gt_col     dw 0              ; its colour (BL); bit 7: XOR into the screen
gt_pos     dw 0              ; col | row<<8
gt_off     dw 0              ; the cell's first byte in the even field
gt_g       dw 0              ; offset of the glyph's row in font
gt_i       dw 0              ; glyph row 0-7
gt_w       dw 0              ; that row's pixels
gt_msk     dw 0              ; 320 mode: the colour in every pixel
gt_n       dw 0
gt_cx      dw 0              ; teletype: column, row
gt_cy      dw 0
gt_pat     ds 8              ; read character: the cell as a glyph
gs_lines   dw 0              ; scroll: rows to move (0: clear the window)
gs_fillb   dw 0              ; the filling byte
gs_top     dw 0              ; the window, in characters
gs_left    dw 0
gs_bot     dw 0
gs_right   dw 0
gs_down    dw 0              ; 0 up, else down
gs_lb      dw 0              ; first byte column and bytes a line
gs_w       dw 0
gs_t       dw 0              ; first field line, and one past the last
gs_e       dw 0
gs_n       dw 0              ; field lines to move
gs_s       dw 0              ; source and destination field lines
gs_d       dw 0
gs_so      dw 0              ; and their offsets in a field
gs_do      dw 0
gs_tmp     dw 0
gt_rtab    dw 0,$2000,80,$2000+80,160,$2000+160,240,$2000+240
gt_mtab    dw $0000,$5555,$AAAA,$FFFF
gp_m4      hex C0300C03      ; a pixel's bits in its byte, 320 mode
gp_m6      hex 8040201008040201
gp_rep     hex 0055AAFF      ; a colour in all four pixels

* gt_on - A (and Z) = 0 unless the screen is CGA graphics
gt_on
 mx %00
 lda gfx_mode
 beq :out
 cmp #GFX_T160
 bne :out
 lda #0
:out
 rts

* gt_cols - A = characters a row: 40 in modes 4/5, 80 in 6
gt_cols
 mx %00
 lda gfx_mode
 cmp #6
 beq :w
 lda #40
 rts
:w
 lda #80
 rts

* gt_cell - A = col | row<<8 -> gt_off; C set when there is no
* such cell on the screen
gt_cell
 mx %00
 ldx gfx_mode
 cpx #GFX_EGA
 bne :cga
 jmp eg_cell               ; mode 0Dh: the planes (ega.s)
:cga
 sta gt_pos
 and #$00FF
 sta gt_off                ; (the column, for now)
 jsr gt_cols
 dec
 cmp gt_off
 bcc :bad                  ; cols-1 < col
 lda gt_pos
 xba
 and #$00FF
 cmp #25
 bcs :bad
 sta gs_tmp                ; row
 lda gfx_mode
 cmp #6
 beq :m6
 asl gt_off                ; two bytes a cell
:m6
 lda gs_tmp
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
 asl                       ; row*64: 320 bytes a character row in a field
 clc
 adc gt_off
 sta gt_off
 clc
 rts
:bad
 sec
 rts

* gt_rowoff - X = where row gt_i of the cell at gt_off is
gt_rowoff
 mx %00
 lda gt_i
 asl
 tax
 lda gt_rtab,x
 clc
 adc gt_off
 tax
 rts

* gt_mark2 / gt_mark1 - the bytes at X and X+1, or at X, were written
gt_mark2
 mx %00
 phx
 inx
 jsr gt_mark1
 plx
gt_mark1
 mx %00
 phx
 txa
 xba
 and #$003F
 tax
 sep #$20
 mx %10
 lda #1
 sta >VID_DIRTY,x
 rep #$20
 mx %00
 plx
 rts

* gt_draw - the character gt_ch in the colour gt_col at gt_off
gt_draw
 mx %00
 lda gfx_mode
 cmp #GFX_EGA
 bne :cga
 jmp eg_draw
:cga
 lda gt_ch
 and #$00FF
 asl
 asl
 asl
 sta gt_g
 stz gt_i
 lda gfx_mode
 cmp #6
 beq :r6
 lda gt_col
 and #$0003
 asl
 tax
 lda gt_mtab,x
 sta gt_msk
:r4
 ldx gt_g
 lda font,x
 and #$00FF
 asl
 tax
 lda exp_tab,x             ; a font bit is a pixel: two bits, the leftmost high
 and gt_msk
 sta gt_w
 jsr gt_rowoff
 lda gt_col
 and #$0080
 beq :st4
 lda >H_TXT,x
 eor gt_w
 bra :put4
:st4
 lda gt_w
:put4
 sta >H_TXT,x
 jsr gt_mark2
 inc gt_g
 inc gt_i
 lda gt_i
 cmp #8
 bcc :r4
 rts
:r6
 ldx gt_g
 lda font,x
 sta gt_w
 jsr gt_rowoff
 sep #$20
 mx %10
 lda gt_col
 bpl :st6
 lda >H_TXT,x
 eor gt_w
 bra :put6
:st6
 lda gt_w
:put6
 sta >H_TXT,x
 rep #$20
 mx %00
 jsr gt_mark1
 inc gt_g
 inc gt_i
 lda gt_i
 cmp #8
 bcc :r6
 rts

* gt_write - INT 10h 09h/0Ah: AL the character, BL the colour, CX
* times from the cursor, which stays; the run ends with its row
gt_write
 mx %00
 lda rAX
 and #$00FF
 sta gt_ch
 lda rBX
 and #$00FF
 sta gt_col
 lda rCX
 beq :done
 sta gt_n
 lda >H_BDA+BDA_CURPOS
:l
 jsr gt_cell
 bcs :done
 jsr gt_draw
 lda gt_n
 dec
 beq :done
 sta gt_n
 lda gt_pos
 inc
 bra :l
:done
 rts

* gt_tty - the teletype: A = character, in the colour tty_attr
* ($FFFF: 3). BEL ignored, BS, CR, LF; the screen moves up a row,
* the new one empty, when the cursor leaves it. Keeps sv3-sv8.
gt_tty
 mx %00
 and #$00FF
 sta gt_ch
 lda tty_attr
 cmp #$FFFF
 bne :col
 lda #3
 ldx gfx_mode
 cpx #GFX_EGA
 bne :col
 lda #7                    ; (of sixteen)
:col
 and #$00FF
 sta gt_col
 lda >H_BDA+BDA_CURPOS
 and #$00FF
 sta gt_cx
 lda >H_BDA+BDA_CURPOS
 xba
 and #$00FF
 sta gt_cy
 lda gt_ch
 cmp #$0D
 beq :cr
 cmp #$0A
 beq :lf
 cmp #$08
 beq :bs
 cmp #$07
 beq :done
 lda gt_cy
 xba
 ora gt_cx
 jsr gt_cell
 bcs :adv
 jsr gt_draw
:adv
 inc gt_cx
 jsr gt_cols
 dec
 cmp gt_cx
 bcs :store                ; col <= cols-1
 stz gt_cx
:lf
 inc gt_cy
 lda gt_cy
 cmp #25
 bcc :store
 lda #24
 sta gt_cy
 jsr gt_up1
 bra :store
:cr
 stz gt_cx
 bra :store
:bs
 lda gt_cx
 beq :store
 dec gt_cx
:store
 lda gt_cy
 xba
 ora gt_cx
 sta >H_BDA+BDA_CURPOS
:done
 rts

* gt_up1 - the whole screen up a row, the last one background
gt_up1
 mx %00
 lda #1
 sta gs_lines
 stz gs_fillb
 stz gs_top
 stz gs_left
 stz gs_down
 lda #24
 sta gs_bot
 lda #79
 sta gs_right
 bra gt_scroll

* gt_scrollsv - INT 10h 06h/07h with vid_scroll_win's arguments:
* sv0 = lines (0 = clear), sv1 high = the filling byte, sv2 = top,
* sv3 = left, sv4 = bottom, sv5 = right, sv6 = 0 up / 1 down
gt_scrollsv
 mx %00
 lda sv0
 sta gs_lines
 lda sv1
 xba
 and #$00FF
 sta gs_fillb
 lda sv2
 sta gs_top
 lda sv3
 sta gs_left
 lda sv4
 sta gs_bot
 lda sv5
 sta gs_right
 lda sv6
 sta gs_down
gt_scroll
 mx %00
 lda gs_bot
 cmp #25
 bcc :b1
 lda #24
 sta gs_bot
:b1
 jsr gt_cols
 dec
 cmp gs_right
 bcs :b2
 sta gs_right
:b2
 lda gs_bot
 cmp gs_top
 bcs :b3
 rts
:b3
 lda gs_right
 sec
 sbc gs_left
 bcs :b4
 rts
:b4
 inc
 sta gs_w
 lda gs_left
 sta gs_lb
 lda gfx_mode
 cmp #6
 beq :m6
 cmp #GFX_EGA
 beq :m6
 asl gs_w
 asl gs_lb
:m6
 lda gs_top
 asl
 asl
 sta gs_t
 lda gs_bot
 inc
 asl
 asl
 sta gs_e
 lda gs_lines
 asl
 asl
 sta gs_n
 lda gfx_mode
 cmp #GFX_EGA
 bne :fld
 asl gs_t                  ; mode 0Dh: eight lines a row, not four in
 asl gs_e                  ; each field
 asl gs_n
:fld
 lda gs_t
 sta gs_d
 lda gs_n
 beq :fill                 ; no lines: the window is cleared
 clc
 adc gs_t
 cmp gs_e
 bcs :fill                 ; as it is when they are all of it
 lda gs_down
 bne :down
:ul
 lda gs_d                  ; up: from the top, each line from n below it
 clc
 adc gs_n
 cmp gs_e
 bcs :fill
 sta gs_s
 jsr gs_copy
 inc gs_d
 bra :ul
:fill
 lda gs_d                  ; and the rest, to the bottom, filled
 cmp gs_e
 bcs :marks
 jsr gs_fill
 inc gs_d
 bra :fill
:down
 lda gs_e                  ; down: from the bottom, each line from n above
 dec
 sta gs_d
:dl
 lda gs_d
 sec
 sbc gs_n
 bcc :dfill
 cmp gs_t
 bcc :dfill
 sta gs_s
 jsr gs_copy
 dec gs_d
 bra :dl
:dfill
 lda gs_d                  ; and the rest, to the top, filled
 bmi :marks
 cmp gs_t
 bcc :marks
 jsr gs_fill
 dec gs_d
 bra :dfill
:marks
 lda gfx_mode
 cmp #GFX_EGA
 bne :mk0
 rts                       ; (egs_copy and egs_fill saw to it)
:mk0
 lda gs_t                  ; the pages of both fields the window lies in
 jsr gs_l80
 clc
 adc gs_lb
 xba
 and #$00FF
 sta gs_s
 lda gs_e
 dec
 jsr gs_l80
 clc
 adc gs_lb
 clc
 adc gs_w
 dec
 xba
 and #$00FF
 sta gs_d
 ldx gs_s
 sep #$20
 mx %10
 lda #1
:mk
 sta >VID_DIRTY,x
 sta >VID_DIRTY+32,x
 inx
 cpx gs_d
 bcc :mk
 beq :mk
 rep #$20
 mx %00
 rts

* gs_l80 - A = a field line -> A = its offset in the field (80 bytes a line)
gs_l80
 mx %00
 asl
 asl
 asl
 asl
 sta gs_tmp
 asl
 asl
 clc
 adc gs_tmp
 rts

* gs_copy - field line gs_s to field line gs_d, the window's bytes,
* in both fields
gs_copy
 mx %00
 lda gfx_mode
 cmp #GFX_EGA
 bne :cga
 jmp egs_copy
:cga
 lda gs_s
 jsr gs_l80
 clc
 adc gs_lb
 sta gs_so
 lda gs_d
 jsr gs_l80
 clc
 adc gs_lb
 sta gs_do
 clc
 adc #$8000                ; B800:0000 in its bank: the even field
 tay
 lda gs_so
 clc
 adc #$8000
 tax
 lda gs_w
 dec
 phb
 mvn H_TXTBANK,H_TXTBANK
 plb
 lda gs_do
 clc
 adc #$A000                ; the odd field
 tay
 lda gs_so
 clc
 adc #$A000
 tax
 lda gs_w
 dec
 phb
 mvn H_TXTBANK,H_TXTBANK
 plb
 rts

* gs_fill - field line gs_d, the window's bytes, <- gs_fillb in both fields
gs_fill
 mx %00
 lda gfx_mode
 cmp #GFX_EGA
 bne :cga
 jmp egs_fill
:cga
 lda gs_d
 jsr gs_l80
 clc
 adc gs_lb
 sta gs_do
 clc
 adc #$8000
 jsr :one
 lda gs_do
 clc
 adc #$A000
:one
 tax
 sep #$20
 mx %10
 lda gs_fillb
 sta >H_TXTBANK,x
 rep #$20
 mx %00
 lda gs_w
 dec
 beq :out
 dec                       ; the first byte, copied along the rest
 txy
 iny
 phb
 mvn H_TXTBANK,H_TXTBANK
 plb
:out
 rts

* gt_read - INT 10h 08h: A = the character whose glyph is at the
* cursor (a pixel of any colour is a set bit), 0 when there is none
gt_read
 mx %00
 lda gfx_mode
 cmp #GFX_EGA
 bne :cga
 jmp eg_read
:cga
 lda >H_BDA+BDA_CURPOS
 jsr gt_cell
 bcc :cell
 lda #0
 rts
:cell
 stz gt_i
:row
 jsr gt_rowoff
 lda gfx_mode
 cmp #6
 beq :b6
 lda >H_TXT,x
 xba                       ; the left byte high
 sta gt_w
 ldy #8
:px
 asl gt_w
 bcs :p1
 asl gt_w
 bra :sh
:p1
 asl gt_w
 sec
:sh
 rol gt_n
 dey
 bne :px
 lda gt_n
 bra :put
:b6
 lda >H_TXT,x
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
* gt_find - A = the character whose glyph is gt_pat, 0 when none is
gt_find
 mx %00
 ldx #0
:srch
 lda font,x
 cmp gt_pat
 bne :nx
 lda font+2,x
 cmp gt_pat+2
 bne :nx
 lda font+4,x
 cmp gt_pat+4
 bne :nx
 lda font+6,x
 cmp gt_pat+6
 beq :hit
:nx
 txa
 clc
 adc #8
 tax
 cpx #2048
 bcc :srch
:none
 lda #0
 rts
:hit
 txa
 lsr
 lsr
 lsr
 rts

* gt_pixel - where the pixel CX, DX is: X = its byte, Y = its place
* in the byte (0 leftmost); C set when it is off the screen
gt_pixel
 mx %00
 lda rDX
 cmp #200
 bcs :bad
 lsr
 jsr gs_l80
 sta gt_off
 lda rDX
 lsr
 bcc :even
 lda gt_off
 clc
 adc #$2000
 sta gt_off
:even
 lda gfx_mode
 cmp #6
 beq :m6
 lda rCX
 cmp #320
 bcs :bad
 and #$0003
 tay
 lda rCX
 lsr
 lsr
 bra :add
:m6
 lda rCX
 cmp #640
 bcs :bad
 and #$0007
 tay
 lda rCX
 lsr
 lsr
 lsr
:add
 clc
 adc gt_off
 tax
 clc
 rts
:bad
 sec
 rts

* gt_setpix - INT 10h 0Ch: the pixel CX, DX <- AL (bit 7: XOR)
gt_setpix
 mx %00
 lda gfx_mode
 cmp #GFX_EGA
 bne :cga
 jmp eg_setpix
:cga
 jsr gt_pixel
 bcc :ok
 rts
:ok
 lda rAX
 and #$0003
 sta gt_n
 sep #$20
 mx %10
 lda gfx_mode
 cmp #6
 beq :m6
 lda gp_m4,y
 sta gt_msk                ; the pixel's bits
 phx
 ldx gt_n
 lda gp_rep,x
 plx
 and gt_msk
 bra :put
:m6
 lda gp_m6,y
 sta gt_msk
 lda rAX
 lsr
 lda #0
 bcc :put
 lda gt_msk
:put
 sta gt_w                  ; the colour in them
 lda rAX
 bmi :xor
 lda gt_msk
 eor #$FF
 and >H_TXT,x
 ora gt_w
 bra :st
:xor
 lda >H_TXT,x
 eor gt_w
:st
 sta >H_TXT,x
 rep #$20
 mx %00
 jmp gt_mark1

* gt_getpix - INT 10h 0Dh: AL = the pixel CX, DX
gt_getpix
 mx %00
 lda gfx_mode
 cmp #GFX_EGA
 bne :cga
 jmp eg_getpix
:cga
 jsr gt_pixel
 bcc :ok
 lda #0
 bra :ret
:ok
 lda gfx_mode
 cmp #6
 beq :m6
 lda >H_TXT,x
 and #$00FF
 cpy #0
 beq :top
:s4
 asl
 asl
 dey
 bne :s4
:top
 and #$00C0
 lsr
 lsr
 lsr
 lsr
 lsr
 lsr
 bra :ret
:m6
 lda >H_TXT,x
 and gp_m6,y               ; (the byte after it in the high half: masked off)
 and #$00FF
 beq :ret
 lda #1
:ret
 sep #$20
 mx %10
 sta rAX
 rep #$20
 mx %00
 rts
