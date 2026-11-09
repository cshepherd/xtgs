*----------------------------------------------------------
* dos.s - INT 20h/21h: the DOS the program sees (Mode A).
* Console I/O through the BIOS teletype plus the host
* capture; a handful of information calls; a bump
* allocator for INT 21h/48h. File functions are M3.
*----------------------------------------------------------
alloc_next dw 0              ; next free paragraph for AH=48h
dta_seg    dw 0
dta_off    dw 0
linebuf    ds 258

int_20
 mx %00
 lda #0
 jmp dos_exit
dos_4C                     ; terminate with AL
 mx %00
 lda rAX
 and #$00FF
dos_exit
 mx %00
 sta exit_code
 lda #1
 sta stop_flag
 rts
dos_00
 mx %00
 lda #0
 jmp dos_exit

int_21
 mx %00
 jsr ah_val
 sta >DIAG_LAST
 cmp #$80
 bcs dos_unknown
 asl
 tax
 jmp (dos_tab,x)
dos_unknown                ; unknown function: AL = 0, noted
 mx %00
 lda #$21
 jsr note_unhandled
 lda #0
 jmp set_al

*--- console output: capture, DOS tab expansion, BIOS teletype
con_out                    ; A = character
 mx %00
 and #$00FF
 pha
 jsr cap_putc
 pla
 cmp #$09
 beq :tab
 jmp vid_tty
:tab
 lda #' '
 jsr vid_tty
 lda >H_BDA+BDA_CURPOS
 and #$0007
 bne :tab
 rts

*--- console input: a DOS key is the ASCII, or 0 then the scan code
dos_getkey                 ; A = next DOS input byte (waits)
 mx %00
 lda key_pending
 beq :fresh
 stz key_pending
 rts
:fresh
 jsr kb_wait
 sta sv8
 and #$00FF
 bne :ascii
 lda sv8
 xba
 and #$00FF
 sta key_pending
 lda #0
:ascii
 rts

dos_01                     ; read with echo
 mx %00
 jsr dos_getkey
 pha
 jsr con_out
 pla
 jmp set_al
dos_02                     ; display DL
 mx %00
 lda rDX
 jsr con_out
 lda rDX
 jmp set_al
dos_06                     ; direct console: DL = FF reads, else writes DL
 mx %00
 lda rDX
 and #$00FF
 cmp #$FF
 beq :in
 jsr con_out
 lda rDX
 jmp set_al
:in
 lda key_pending
 bne :have
 jsr kb_poll
 jsr vbl_check
 jsr kb_pop
 bcc :none
 sta sv8
 and #$00FF
 bne :have
 lda sv8
 xba
 and #$00FF
 sta key_pending
 lda #0
:have
 pha
 jsr clr_zf
 pla
 cmp #0                    ; a pending scan code comes next
 bne :set
 lda key_pending
 beq :set
 lda #0
:set
 jsr set_al
 lda key_pending
 beq :done
 lda rAX                   ; AL = 0 now; the scan code is owed
 and #$FF00
 sta rAX
:done
 rts
:none
 jsr set_zf
 lda #0
 jmp set_al
dos_07                     ; direct input, no echo
dos_08                     ; input, no echo
 mx %00
 jsr dos_getkey
 jmp set_al
dos_09                     ; display the $-terminated string at DS:DX
 mx %00
 ldx #bDS
 lda rDX
 jsr gptr
 ldy #0
:ch
 lda [pGST]
 and #$00FF
 cmp #'$'
 beq :done
 jsr con_out
 inc pGST
 iny
 bne :ch
:done
 rts
dos_0A                     ; buffered line input at DS:DX
 mx %00
 ldx #bDS
 lda rDX
 jsr gptr
 lda [pGST]
 and #$00FF
 sta sv6                   ; max (including the CR)
 beq :end
 stz sv7                   ; count
:key
 jsr dos_getkey
 and #$00FF
 beq :key                  ; extended keys ignored
 cmp #$0D
 beq :enter
 cmp #$08
 beq :bs
 cmp #$20
 bcc :key                  ; other controls ignored
 ldy sv7
 iny
 cpy sv6
 bcs :key                  ; full (room for the CR)
 ldy sv7
 iny
 iny
 sta sv8
 sep #$20
 mx %10
 lda sv8
 sta [pGST],y
 rep #$20
 mx %00
 inc sv7
 lda sv8
 jsr con_out
 bra :key
:bs
 lda sv7
 beq :key
 dec sv7
 lda #$08
 jsr con_out
 lda #' '
 jsr con_out
 lda #$08
 jsr con_out
 bra :key
:enter
 ldy sv7
 iny
 iny
 lda #$0D
 sta sv8
 sep #$20
 mx %10
 lda sv8
 sta [pGST],y
 ldy #1
 lda sv7
 sta [pGST],y
 rep #$20
 mx %00
 lda #$0D
 jsr con_out
:end
 rts
dos_0B                     ; AL = FF when a key waits
 mx %00
 lda key_pending
 bne :yes
 jsr kb_poll
 jsr vbl_check
 jsr kb_peek
 bcs :yes
 lda #0
 jmp set_al
:yes
 lda #$FF
 jmp set_al
dos_0C                     ; flush, then function AL
 mx %00
 jsr kb_flush
 lda rAX
 and #$00FF
 cmp #1
 beq :go
 cmp #6
 beq :go
 cmp #7
 beq :go
 cmp #8
 beq :go
 cmp #$0A
 beq :go
 lda #0
 jmp set_al
:go
 jsr set_ah
 jmp int_21
dos_0D                     ; disk reset
 mx %00
 rts
dos_0E                     ; select disk: AL = drives
 mx %00
 lda #3
 jmp set_al
dos_19                     ; current drive: C
 mx %00
 lda #2
 jmp set_al
dos_1A                     ; set DTA
 mx %00
 lda rDX
 sta dta_off
 lda rDS
 sta dta_seg
 rts
dos_25                     ; set vector AL = DS:DX
 mx %00
 lda rAX
 and #$00FF
 asl
 asl
 tax
 lda rDX
 sta >H_IVT,x
 lda rDS
 sta >H_IVT+2,x
 rts
dos_2A                     ; date: 1987-01-01, Thursday (fixed until M3)
 mx %00
 lda #1987
 sta rCX
 lda #$0101
 sta rDX
 lda #4
 jmp set_al
dos_2C                     ; time 12:00:00.00
 mx %00
 lda #$0C00
 sta rCX
 stz rDX
 rts
dos_2F                     ; get DTA
 mx %00
 lda dta_off
 sta rBX
 lda dta_seg
 sta rES
 jsr svc_set_es
 rts
dos_30                     ; version 3.30, OEM 0, serial 0
 mx %00
 lda #$1E03
 sta rAX
 stz rBX
 stz rCX
 rts
dos_33                     ; Ctrl-Break: off
 mx %00
 lda rAX
 and #$00FF
 bne :done
 lda rDX
 and #$FF00
 sta rDX
:done
 rts
dos_35                     ; get vector AL -> ES:BX
 mx %00
 lda rAX
 and #$00FF
 asl
 asl
 tax
 lda >H_IVT,x
 sta rBX
 lda >H_IVT+2,x
 sta rES
 jsr svc_set_es
 rts
dos_36                     ; disk free space (a fixed, plausible disk)
 mx %00
 lda #8
 sta rAX
 lda #1000
 sta rBX
 lda #512
 sta rCX
 lda #2000
 sta rDX
 rts
dos_3C                     ; create / open: no files yet (M3)
dos_3D
dos_4B
 mx %00
 lda #2                    ; file not found
dos_fail
 mx %00
 sta rAX
 jsr set_cf
 lda #$21
 jmp note_unhandled
dos_41
dos_43
dos_56
 mx %00
 lda #2
 jmp dos_fail
dos_3E                     ; close: fine
 mx %00
 jmp clr_cf
dos_3F                     ; read handle BX: stdin reads a line
 mx %00
 lda rBX
 bne :bad
 jsr read_line             ; linebuf, sv7 = length including CR LF
 ldx #bDS
 lda rDX
 jsr gptr
 lda rCX
 cmp sv7
 bcc :n
 lda sv7
:n
 sta sv6                   ; bytes to copy
 sta rAX
 ldy #0
:cp
 cpy sv6
 bcs :done
 lda linebuf,y
 sta sv8
 sep #$20
 mx %10
 lda sv8
 sta [pGST],y
 rep #$20
 mx %00
 iny
 bra :cp
:done
 jmp clr_cf
:bad
 lda #6
 jmp dos_fail
dos_40                     ; write handle BX: 1 and 2 are the console
 mx %00
 lda rBX
 cmp #1
 beq :con
 cmp #2
 beq :con
 lda #6
 jmp dos_fail
:con
 ldx #bDS
 lda rDX
 jsr gptr
 ldy rCX
 beq :done
:ch
 lda [pGST]
 jsr con_out
 inc pGST
 dey
 bne :ch
:done
 lda rCX
 sta rAX
 jmp clr_cf
dos_42                     ; seek: no files
 mx %00
 lda #6
 jmp dos_fail
dos_44                     ; IOCTL: AL=0 get device info for the console handles
 mx %00
 lda rAX
 and #$00FF
 bne :unk
 lda rBX
 cmp #3
 bcs :bad
 lda #$80D3
 sta rDX
 jmp clr_cf
:bad
 lda #6
 jmp dos_fail
:unk
 lda #1
 jmp dos_fail
dos_47                     ; current directory: the root
 mx %00
 ldx #bDS
 lda rSI
 jsr gptr
 sep #$20
 mx %10
 lda #0
 sta [pGST]
 rep #$20
 mx %00
 jmp clr_cf
dos_48                     ; allocate BX paragraphs
 mx %00
 lda alloc_next
 clc
 adc rBX
 cmp #TOP_PARA
 bcs :nomem
 bcc :ok
:ok
 lda alloc_next
 sta rAX
 clc
 adc rBX
 sta alloc_next
 jmp clr_cf
:nomem
 lda #TOP_PARA
 sec
 sbc alloc_next
 sta rBX
 lda #8
 jmp dos_fail
dos_49                     ; free: fine
dos_4A                     ; resize: fine
 mx %00
 jmp clr_cf
dos_4D                     ; child's return code
 mx %00
 stz rAX
 rts
dos_51                     ; PSP segment
dos_62
 mx %00
 lda #PSP_SEG
 sta rBX
 rts
dos_54                     ; verify flag: off
 mx %00
 lda #0
 jmp set_al

* read_line - a line from the keyboard into linebuf with echo;
* sv7 = its length including the CR LF appended.
read_line
 mx %00
 stz sv7
:key
 jsr dos_getkey
 and #$00FF
 beq :key
 cmp #$0D
 beq :enter
 cmp #$08
 beq :bs
 cmp #$20
 bcc :key
 ldy sv7
 cpy #254
 bcs :key
 sta sv8
 sep #$20
 mx %10
 lda sv8
 sta linebuf,y
 rep #$20
 mx %00
 inc sv7
 lda sv8
 jsr con_out
 bra :key
:bs
 lda sv7
 beq :key
 dec sv7
 lda #$08
 jsr con_out
 lda #' '
 jsr con_out
 lda #$08
 jsr con_out
 bra :key
:enter
 ldy sv7
 lda #$0A0D
 sta linebuf,y
 inc sv7
 inc sv7
 lda #$0D
 jsr con_out
 lda #$0A
 jmp con_out
