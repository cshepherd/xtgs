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
 jsr tty_cur
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
 bne :lj1
 jmp :end
:lj1
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
dos_2A                     ; date: the IIGS's clock (clock.s). AL = weekday, 0 Sunday
 mx %00
 jsr clk_read
 lda clk_hour
 xba
 and #$00FF
 clc
 adc #1900
 sta rCX
 lda clk_date
 clc
 adc #$0101                ; (month and day from 0; neither carries)
 sta rDX
 lda clk_wday
 xba
 and #$00FF
 dec
 jmp set_al
dos_2C                     ; time: the same clock, whole seconds
 mx %00
 jsr clk_read
 lda clk_hour
 and #$00FF
 xba
 sta rCX
 lda clk_sec
 xba
 and #$00FF
 ora rCX
 sta rCX
 lda clk_sec
 and #$00FF
 xba
 sta rDX
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
dos_4B                     ; exec: not yet
 mx %00
 lda #2
dos_fail                   ; A = DOS error: noted (with the function in AH), then AX, CF
 mx %00
 pha
 lda #$21
 jsr note_unhandled
 pla
 sta rAX
 jmp set_cf
dos_3F_con                 ; read handle: the console reads a line
 mx %00
 jsr read_line             ; linebuf, sv7 = length including CR LF
 ldx #bDS
 lda rDX
 jsr gptr
 lda rCX
 cmp sv7
 bcc :n
 lda sv7
:n
 sta sv6
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
dos_40_con                 ; write handle: the console
 mx %00
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
dos_44                     ; IOCTL: AL=0 device info for BX
 mx %00
 lda rAX
 and #$00FF
 bne :other
 lda rBX
 jsr h_lookup
 bcs :bad
 lda htab,x
 and #$00FF
 cmp #H_FILE
 beq :file
 lda htab,x
 xba
 and #$00FF
 beq :con
 lda #$80C4                ; NUL and the rest: a device, not the console
 bra :info
:con
 lda #$80D3
 bra :info
:file
 lda #$0002                ; drive C, a file
:info
 sta rDX
 jmp clr_cf
:other
 cmp #1
 beq :ok
 cmp #8                    ; removable? no
 bne :unk
 stz rAX
 jmp clr_cf
:ok
 jmp clr_cf
:bad
 lda #6
 jmp dos_fail
:unk
 lda #1
 jmp dos_fail
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
cur_psp    dw 0
dos_50                     ; set current PSP = BX
 mx %00
 lda rBX
 sta cur_psp
 rts
dos_51                     ; get current PSP -> BX
dos_62
 mx %00
 lda cur_psp
 sta rBX
 rts
dos_26                     ; create a PSP at segment DX: a copy of the current one
 mx %00
 lda rDX
 asl
 asl
 asl
 asl
 sta pGST
 lda rDX
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 ora #GUEST_BANK
 sta pGST+2
 lda cur_psp               ; source: the current PSP
 asl
 asl
 asl
 asl
 sta pARG
 lda cur_psp
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 ora #GUEST_BANK
 sta pARG+2
 ldy #0
:c
 lda [pARG],y
 sta [pGST],y
 iny
 iny
 cpy #256
 bcc :c
 lda cur_psp               ; parent
 ldy #$16
 sta [pGST],y
 ldy #$0A                  ; the vectors 22h 23h 24h as they are now
 ldx #$22*4
:v
 lda >H_IVT,x
 sta [pGST],y
 iny
 iny
 inx
 inx
 cpx #$25*4
 bcc :v
 rts
dos_37                     ; switch character: AL=0 get -> DL='/'
 mx %00
 lda rAX
 and #$00FF
 bne :set
 lda rDX
 and #$FF00
 ora #'/'
 sta rDX
:set
 lda #0
 jmp set_al
dos_1F                     ; default drive parameter block -> DS:BX (a fixed, plausible one)
 mx %00
 lda #DOSDATA_SEG
 sta rDS
 jsr svc_set_ds
 lda #DPB_OFF
 sta rBX
 lda #0
 jmp set_al
dos_52                     ; list of lists -> ES:BX (undocumented; a stub block)
 mx %00
 lda #DOSDATA_SEG
 sta rES
 jsr svc_set_es
 lda #LOL_OFF
 sta rBX
 rts
dos_29                     ; parse filename DS:SI -> FCB at ES:DI; AL flags
 mx %00
 ldx #bDS
 lda rSI
 jsr gptr                  ; pGST = source
 lda pGST
 sta pARG
 lda pGST+2
 sta pARG+2
 ldx #bES
 lda rDI
 jsr gptr                  ; pGST = the FCB
 lda rAX
 and #$00FF
 sta sv4                   ; flags
 jsr parse_fcb             ; from [pARG] into [pGST]; sv5 = chars consumed, A = result
 pha
 lda rSI
 clc
 adc sv5
 sta rSI
 pla
 jmp set_al

* parse_fcb - the filename at [pARG] (ASCIIZ-ish) into the FCB at [pGST]:
* drive, 8 name, 3 ext ('*' fills '?'); sv4 = AL flags (bit 0 skip leading
* separators, bit 1 keep the drive when none given, bits 2/3 keep name/ext
* when none given). sv5 = bytes consumed. A = 0 no wildcards, 1 wildcards,
* $FF invalid drive.
parse_fcb
 mx %00
 stz sv5
 stz sv6                   ; wildcard seen
 ldy #0
 lda sv4
 and #1
 beq :nosep
:sep
 lda [pARG],y
 and #$00FF
 jsr is_sep
 bcc :nosep
 iny
 bra :sep
:nosep
:sp
 lda [pARG],y
 and #$00FF
 cmp #' '
 beq :spc
 cmp #9
 bne :drive
:spc
 iny
 bra :sp
:drive
 lda [pARG],y
 and #$00FF
 beq :nodrive
 pha
 iny
 lda [pARG],y
 and #$00FF
 cmp #':'
 bne :notdrive
 pla
 and #$5F
 sec
 sbc #'A'-1
 sta sv7
 iny
 sep #$20
 mx %10
 lda sv7
 sta [pGST]
 rep #$20
 mx %00
 bra :name
:notdrive
 pla
 dey
:nodrive
 lda sv4
 and #2
 bne :name
 sep #$20
 mx %10
 lda #0
 sta [pGST]
 rep #$20
 mx %00
:name
 ldx #1
 lda [pARG],y
 and #$00FF
 jsr is_term
 bcc :lj2
 jmp :nameblank
:lj2
:nl
 lda [pARG],y
 and #$00FF
 cmp #'.'
 bne :lj3
 jmp :dot
:lj3
 jsr is_term
 bcs :namepad
 cmp #'*'
 beq :nstar
 cmp #'a'
 bcc :nup
 cmp #'z'+1
 bcs :nup
 and #$5F
:nup
 cmp #'?'
 bne :nq
 inc sv6
:nq
 cpx #9
 bcs :nskip
 jsr fcb_putc
:nskip
 iny
 bra :nl
:nstar
 inc sv6
 iny
:nfill
 cpx #9
 bcs :nl2
 lda #'?'
 jsr fcb_putc
 bra :nfill
:nl2
 lda [pARG],y              ; skip the rest of the name part
 and #$00FF
 cmp #'.'
 beq :dot
 jsr is_term
 bcs :namepad
 iny
 bra :nl2
:namepad
 cpx #9
 bcc :lj4
 jmp :ext0
:lj4
 lda #' '
 jsr fcb_putc
 bra :namepad
:nameblank                 ; no name: blanks unless bit 2 says keep
 lda sv4
 and #4
 beq :lj5
 jmp :ext0
:lj5
 bra :namepad
:dot
 iny
 jsr pad_name
 ldx #9
:el
 lda [pARG],y
 and #$00FF
 jsr is_term
 bcs :extpad
 cmp #'*'
 beq :estar
 cmp #'a'
 bcc :eup
 cmp #'z'+1
 bcs :eup
 and #$5F
:eup
 cmp #'?'
 bne :eq
 inc sv6
:eq
 cpx #12
 bcs :eskip
 jsr fcb_putc
:eskip
 iny
 bra :el
:estar
 inc sv6
 iny
:efill
 cpx #12
 bcs :el2
 lda #'?'
 jsr fcb_putc
 bra :efill
:el2
 lda [pARG],y
 and #$00FF
 jsr is_term
 bcs :extpad
 iny
 bra :el2
:extpad
 cpx #12
 bcs :done
 lda #' '
 jsr fcb_putc
 bra :extpad
:ext0                      ; no extension given
 lda sv4
 and #8
 bne :done
 ldx #9
 bra :extpad
:done
 sty sv5
 lda sv6
 beq :nowild
 lda #1
 rts
:nowild
 lda #0
 rts
pad_name                   ; blanks to the end of the name field (X -> 9)
 mx %00
 cpx #9
 bcs :d
 lda #' '
 jsr fcb_putc
 bra pad_name
:d
 rts
fcb_putc                   ; A (low) -> [pGST],x (X = field offset 1-11), X++
 mx %00
 sta sv9
 phy
 txy
 sep #$20
 mx %10
 lda sv9
 sta [pGST],y
 rep #$20
 mx %00
 ply
 inx
 rts
is_sep                     ; A = char: C set if a DOS filename separator  : ; , = + and white space
 mx %00
 cmp #':'
 beq :y
 cmp #$3B                  ; ';'
 beq :y
 cmp #$2C                  ; ','
 beq :y
 cmp #'='
 beq :y
 cmp #'+'
 beq :y
 cmp #' '
 beq :y
 cmp #9
 beq :y
 clc
 rts
:y
 sec
 rts
is_term                    ; A = char: C set if it ends a filename (NUL CR separators / \ [ ] | < > ")
 mx %00
 beq :y
 cmp #$0D
 beq :y
 cmp #'/'
 beq :y
 cmp #$5C                  ; backslash
 beq :y
 cmp #'['
 beq :y
 cmp #']'
 beq :y
 cmp #'|'
 beq :y
 cmp #'<'
 beq :y
 cmp #'>'
 beq :y
 cmp #$22
 beq :y
 jmp is_sep
:y
 sec
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
