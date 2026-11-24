*----------------------------------------------------------
* mouse.s - the IIGS's mouse as the PC's, behind the Microsoft
* mouse driver's INT 33h (Mode B; docs/mouse.md). There is no
* driver to load: the BIOS answers INT 33h itself, unless
* XTGS.CMD has the line MOUSE=OFF (ms_cfg, rd_readcfg). DOS
* points vectors 20h-3Fh at an IRET of its own as it starts,
* as it would before any driver loaded: half a second after
* vector 33h has left the BIOS, ms_poll takes it back, once
* (a program that hooks it later keeps its hook).
*
*   the mouse    read once a frame (ms_poll, from svc_vbl) at the
*                ADB GLU: KMSTATUS bit 7 says a movement is
*                waiting, MOUSEDATA then gives X and Y, seven
*                bits signed each, bit 7 a button (0 = down):
*                the mouse's own in Y, a second one's in X.
*   positions    the driver's 640 by 200 whatever the mode: a
*                count of the IIGS mouse is two across and one
*                down, and two mickeys either way.
*   the cursor   in the text modes the driver's software cursor:
*                the cell's word through the two masks, in the
*                guest's buffer as a driver does it (ms_cursor).
*                None in the graphics modes.
*   the handler  function 0Ch: ms_poll raises PIC_MOUSE, the
*                core's slot enters the stub at F000:MS_OFF as
*                an interrupt would (by no vector), and the stub
*                saves the registers, asks hypercall 259 for
*                the event, calls the handler far and tells
*                hypercall 260 it is back. One call at a time
*                (ms_busy); events in between are joined.
*----------------------------------------------------------
ms_cfg     dw 1              ; XTGS.CMD: 0 after MOUSE=OFF
ms_on      dw 0              ; INT 33h answers
ms_irq     dw 0              ; KMSTATUS's mouse interrupt bit as we found it
ms_hook    dw 0              ; frames since DOS took vector 33h; $FFFF: taken back
ms_pos     dw 320,100        ; x, y
ms_min     dw 0,0
ms_max     dw 639,199
ms_mick    dw 0,0            ; mickeys since function 0Bh
ms_btn     dw 0              ; bit 0 left, bit 1 right: down
ms_vis     dw $FFFF          ; 0: the cursor shows; below: hidden that many times
ms_and     dw $77FF          ; the text cursor's screen mask
ms_xor     dw $7700          ; and cursor mask
ms_drawn   dw 0              ; the cursor is in the buffer,
ms_off     dw 0              ; at this offset of B800,
ms_save    dw 0              ; over this word,
ms_wrote   dw 0              ; as this one
ms_hmask   dw 0              ; function 0Ch: the events the handler wants
ms_evt     dw 0              ; events owed to it
ms_busy    dw 0              ; it is running
ms_pc      dw 0,0            ; presses of each button since function 05h
ms_px      dw 0,0            ; where the last was
ms_py      dw 0,0
ms_rc      dw 0,0            ; releases, function 06h
ms_rx      dw 0,0
ms_ry      dw 0,0

* The guest's side, at F000:MS_OFF, entered by the slot.
ms_stub
 hex 5053515256571E0655    ; +00 push ax bx cx dx si di ds es bp
 hex FE380301              ; +09 hypercall 259: the event, AX = 0 none
 hex 0BC07405              ; +0D or ax,ax / jz +5
 hex 2EFF1E                ; +11 call far [cs:handler]
 dw MS_OFF+$24
 hex FE380401              ; +16 hypercall 260: it is back
 hex 5D071F5F5E5A595B58    ; +1A pop bp es ds di si dx cx bx ax
 hex CF                    ; +23 iret
 adrl 0                    ; +24 handler
ms_stubend
 err ms_stubend-ms_stub-$28

* ms_calls - hypercalls 259.. (svc_hypercall, after rd_tab's)
ms_calls   da ms_event,ms_done
MS_NCALLS  = 2

* ms_setup - from svc_bootinit, after XTGS.CMD was read.
ms_setup
 mx %00
 stz ms_on
 lda #0
 sta >PIC_MOUSE
 lda ms_cfg
 beq :out
 inc ms_on
 ldx #0
 sep #$20
 mx %10
:c
 lda ms_stub,x
 sta >H_BIOS+MS_OFF,x
 inx
 cpx #ms_stubend-ms_stub
 bcc :c
 rep #$20
 mx %00
 stz ms_drawn
 stz ms_hook
 jsr ms_reset
 php                       ; the mouse's interrupt off while the PC has it:
 sei                       ; were it on (a system that used the mouse) the
 sep #$20                  ; firmware's handler would take the data first
 mx %10
 lda >KMSTATUS
 and #$40
 sta ms_irq
 lda >KMSTATUS
 and #$BF
 sta >KMSTATUS
 rep #$20
 mx %00
 plp
:out
 rts

* ms_close - from svc_sndclose: the mouse's interrupt as it was
ms_close
 mx %00
 lda ms_on
 beq :out
 stz ms_on
 lda ms_irq
 and #$0040
 beq :out
 php
 sei
 sep #$20
 mx %10
 lda >KMSTATUS
 ora #$40
 sta >KMSTATUS
 rep #$20
 mx %00
 plp
:out
 rts

* ms_reset - functions 00h and 21h: the driver as loaded.
ms_reset
 mx %00
 jsr ms_erase
 lda #320
 sta ms_pos
 lda #100
 sta ms_pos+2
 stz ms_min
 stz ms_min+2
 lda #639
 sta ms_max
 lda #199
 sta ms_max+2
 lda #$FFFF
 sta ms_vis
 lda #$77FF
 sta ms_and
 lda #$7700
 sta ms_xor
 stz ms_mick
 stz ms_mick+2
 stz ms_hmask
 stz ms_evt
 stz ms_busy
 lda #0
 sta >PIC_MOUSE
 sta >H_BIOS+MS_OFF+$24
 sta >H_BIOS+MS_OFF+$26
 ldx #6
:z
 stz ms_pc,x               ; (the twelve words from ms_pc)
 stz ms_py,x
 stz ms_rx,x
 dex
 dex
 bpl :z
 rts

* ms_clamp - A = a position, X = 0 (x) or 2 (y) -> A within the range
ms_clamp
 mx %00
 bmi :lo
 cmp ms_min,x
 bcs :hi
:lo
 lda ms_min,x
 rts
:hi
 cmp ms_max,x
 bcc :ok
 lda ms_max,x
:ok
 rts

* ms_sx - A = MOUSEDATA's byte -> A = its seven bits, signed
ms_sx
 mx %00
 and #$007F
 cmp #$0040
 bcc :p
 ora #$FF80
:p
 rts

* ms_poll - once a frame: the mouse moved or a button changed?
ms_poll
 mx %00
 lda ms_on
 bne :on
 rts
:on
 lda ms_hook
 bmi :hooked
 lda >H_IVT+$CE            ; vector 33h's segment
 cmp #BIOS_SEG
 beq :hooked               ; (still the BIOS's)
 inc ms_hook
 lda ms_hook
 cmp #30
 bcc :hooked
 lda #$33*STUB_LEN
 sta >H_IVT+$CC
 lda #BIOS_SEG
 sta >H_IVT+$CE
 lda #$FFFF
 sta ms_hook
:hooked
 sep #$20
 mx %10
 lda >KMSTATUS
 bmi :data
:none
 rep #$20
 mx %00
 rts
 mx %10
:data
 and #$02                  ; Y is next: out of step, drop it
 beq :x
 lda >MOUSEDATA
 bra :none
:x
 lda >MOUSEDATA
 sta sv0
 lda >MOUSEDATA
 sta sv1
 rep #$20
 mx %00
 lda sv0
 sta >MS_RAW               ; (for the test)
 stz sv2                   ; the events
 lda sv0
 and #$00FF
 jsr ms_sx
 sta sv3                   ; dx
 lda sv1
 and #$00FF
 jsr ms_sx
 sta sv4                   ; dy
 ora sv3
 beq :still
 inc sv2                   ; bit 0: it moved
 lda sv3
 asl
 sta sv3
 clc
 adc ms_mick
 sta ms_mick
 lda sv4
 asl
 clc
 adc ms_mick+2
 sta ms_mick+2
 lda ms_pos
 clc
 adc sv3
 ldx #0
 jsr ms_clamp
 sta ms_pos
 lda ms_pos+2
 clc
 adc sv4
 ldx #2
 jsr ms_clamp
 sta ms_pos+2
:still
 stz sv5                   ; the buttons: bit 7 clear is down
 lda sv1
 and #$0080
 bne :b1
 inc sv5
:b1
 lda sv0
 and #$0080
 bne :b2
 lda sv5
 ora #$0002
 sta sv5
:b2
 lda sv5
 eor ms_btn
 sta sv6                   ; which changed
 lda sv5
 sta ms_btn
 lda sv6
 and #$0001
 beq :right
 ldx #0
 lda #$0002
 jsr ms_edge
:right
 lda sv6
 and #$0002
 beq :tell
 ldx #2
 lda #$0008
 jsr ms_edge
:tell
 lda sv2
 beq :out
 and ms_hmask
 beq :cur
 lda sv2
 tsb ms_evt
 jsr ms_raise
:cur
 lda sv2
 lsr
 bcc :out
 jsr ms_cursor
:out
 rts

* ms_edge - button X/2 changed: A = its "pressed" event bit (the
* "released" one is the next); counts and places for 05h/06h
ms_edge
 mx %00
 sta sv7
 txa
 lsr
 inc
 and ms_btn                ; (1 or 2: that button's bit)
 beq :up
 lda sv7
 tsb sv2
 inc ms_pc,x
 lda ms_pos
 sta ms_px,x
 lda ms_pos+2
 sta ms_py,x
 rts
:up
 lda sv7
 asl
 tsb sv2
 inc ms_rc,x
 lda ms_pos
 sta ms_rx,x
 lda ms_pos+2
 sta ms_ry,x
 rts

* ms_raise - an event is owed and the handler is not running: the slot's
ms_raise
 mx %00
 lda ms_busy
 bne :no
 lda vPCMODE
 cmp #2
 bne :no
 lda #1
 sta >PIC_MOUSE
 sta >PIC_PEND             ; (the slot looks at the lines only when this is set)
:no
 rts

* ms_event - hypercall 259, from the stub: the handler's registers
ms_event
 mx %00
 stz rAX
 lda ms_evt
 beq :out
 lda >H_BIOS+MS_OFF+$24
 ora >H_BIOS+MS_OFF+$26
 beq :out
 lda ms_evt
 sta rAX
 stz ms_evt
 lda #1
 sta ms_busy
 lda ms_btn
 sta rBX
 lda ms_pos
 sta rCX
 lda ms_pos+2
 sta rDX
 lda ms_mick
 sta rSI
 lda ms_mick+2
 sta rDI
:out
 rts

* ms_done - hypercall 260: the handler is back
ms_done
 mx %00
 stz ms_busy
 lda ms_evt
 beq :out
 jsr ms_raise
:out
 rts

* ms_erase - the cursor out of the buffer, if the cell is still ours
ms_erase
 mx %00
 lda ms_drawn
 beq :out
 stz ms_drawn
 ldx ms_off
 lda >H_TXT,x
 cmp ms_wrote
 bne :out
 lda ms_save
 sta >H_TXT,x
 jsr ms_mark
:out
 rts

* ms_mark - the page of B800 the cursor's cell is in, for the flush
ms_mark
 mx %00
 lda ms_off
 xba
 and #$003F
 tax
 sep #$20
 mx %10
 lda #1
 sta >VID_DIRTY,x
 rep #$20
 mx %00
 rts

* ms_cursor - the text cursor where the mouse is, if it shows
ms_cursor
 mx %00
 jsr ms_erase
 lda ms_vis
 bne :out
 lda >H_BDA+BDA_VMODE
 and #$00FF
 cmp #4
 bcc :text
 cmp #7
 bne :out
:text
 lda ms_pos+2
 lsr
 lsr
 lsr
 asl
 asl
 asl
 sta sv0                   ; row * 8
 asl
 asl
 clc
 adc sv0
 sta sv0                   ; row * 40
 lda ms_pos
 lsr
 lsr
 lsr
 sta sv1                   ; the column of 80
 lda >H_BDA+BDA_COLS
 cmp #40
 beq :c40
 asl sv0
 bra :cell
:c40
 lsr sv1
:cell
 lda sv0
 clc
 adc sv1
 asl
 clc
 adc >H_BDA+BDA_PGOFF
 and #$3FFE
 sta ms_off
 tax
 lda >H_TXT,x
 sta ms_save
 and ms_and
 eor ms_xor
 sta >H_TXT,x
 sta ms_wrote
 lda #1
 sta ms_drawn
 jsr ms_mark
:out
 rts

*=== INT 33h ================================================
int_33
 mx %00
 lda ms_on
 bne :on
 jmp int_default
:on
 lda rAX
 cmp #$0025
 bcs :out
 asl
 tax
 jmp (ms_tab,x)
:out
 rts
ms_tab     da ms_f00,ms_f01,ms_f02,ms_f03,ms_f04,ms_f05,ms_f06,ms_f07
           da ms_f08,ms_nop,ms_f0A,ms_f0B,ms_f0C,ms_nop,ms_nop,ms_nop
           da ms_nop,ms_nop,ms_nop,ms_nop,ms_nop,ms_nop,ms_nop,ms_nop
           da ms_nop,ms_nop,ms_nop,ms_nop,ms_nop,ms_nop,ms_nop,ms_nop
           da ms_nop,ms_f00,ms_nop,ms_nop,ms_f24
ms_nop
 mx %00
 rts
ms_f00                     ; reset: AX = FFFF a mouse, BX = 2 buttons
 mx %00
 jsr ms_reset
 lda #$FFFF
 sta rAX
 lda #2
 sta rBX
 rts
ms_f01                     ; show
 mx %00
 lda ms_vis
 beq :at
 inc ms_vis
:at
 jmp ms_cursor
ms_f02                     ; hide
 mx %00
 dec ms_vis
 jmp ms_cursor
ms_f03                     ; where, and the buttons
 mx %00
 lda ms_btn
 sta rBX
 lda ms_pos
 sta rCX
 lda ms_pos+2
 sta rDX
 rts
ms_f04                     ; put it at CX, DX
 mx %00
 lda rCX
 ldx #0
 jsr ms_clamp
 sta ms_pos
 lda rDX
 ldx #2
 jsr ms_clamp
 sta ms_pos+2
 jmp ms_cursor
ms_f05                     ; presses of button BX
 mx %00
 lda rBX
 and #$0001
 asl
 tax
 lda ms_btn
 sta rAX
 lda ms_pc,x
 sta rBX
 stz ms_pc,x
 lda ms_px,x
 sta rCX
 lda ms_py,x
 sta rDX
 rts
ms_f06                     ; releases
 mx %00
 lda rBX
 and #$0001
 asl
 tax
 lda ms_btn
 sta rAX
 lda ms_rc,x
 sta rBX
 stz ms_rc,x
 lda ms_rx,x
 sta rCX
 lda ms_ry,x
 sta rDX
 rts
ms_f07                     ; the range across, CX to DX
 mx %00
 ldx #0
 bra ms_range
ms_f08                     ; and down
 mx %00
 ldx #2
ms_range
 mx %00
 lda rCX
 cmp rDX
 bcc :ord
 lda rDX
 sta ms_min,x
 lda rCX
 sta ms_max,x
 bra :in
:ord
 sta ms_min,x
 lda rDX
 sta ms_max,x
:in
 lda ms_pos,x
 jsr ms_clamp
 sta ms_pos,x
 jmp ms_cursor
ms_f0A                     ; the text cursor: BX = 0, the masks in CX and DX
 mx %00
 lda rBX
 bne :hw
 jsr ms_erase
 lda rCX
 sta ms_and
 lda rDX
 sta ms_xor
 jmp ms_cursor
:hw
 rts
ms_f0B                     ; mickeys since the last call
 mx %00
 lda ms_mick
 sta rCX
 lda ms_mick+2
 sta rDX
 stz ms_mick
 stz ms_mick+2
 rts
ms_f0C                     ; the handler: ES:DX for the events in CX
 mx %00
 lda rCX
 sta ms_hmask
 lda rDX
 sta >H_BIOS+MS_OFF+$24
 lda rES
 sta >H_BIOS+MS_OFF+$26
 rts
ms_f24                     ; the driver: version 8.00, a PS/2 mouse
 mx %00
 lda #$0800
 sta rBX
 lda #$0400
 sta rCX
 rts
