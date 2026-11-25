*----------------------------------------------------------
* state.s - the boot state (docs/state.md, "M7"): the PC as
* it was at a DOS prompt, written to the file XTGS.STATE
* beside CORE (bs_save, the desk accessory's sixth choice),
* and at a later start put back in place of the boot
* (bs_try from svc_bootinit, svc_stload from the core) when
* XTGS.CMD says STATE=ON and the file is this build's, this
* layout's and this configuration's.
*
* The file: a header of BS_HLEN bytes, the map and the data
* of the desk accessory's saved state (control.s: st_save's
* seven regions, a word a page in the map, 256 bytes in the
* data for each page that is not one byte 256 times), with
* a sum for every BS_CH pages of the data between the two:
* a piece of the data is read, added up and held to its sum
* before it goes to its places.
*
*   +0   "XTGSboot"
*   +8   version (BS_VER), +10 the header's length
*   +12  the build (tools/gen_buildid.py: CORE's and SVC's
*        sources; their banks are in the file as they were)
*   +16  MB_LAYOUT and MB_LAYALT: where everything is (the
*        banks' bytes are in the saved code and pointers)
*   +42  XTGS.CMD's first 128 bytes as this start read them
*   +170 the regions (st_rg), +212 the map's bytes, +214 the
*        data's pages, +216 the bytes of the pieces' sums (4
*        a piece), +218 the sum of the map's and of those
*        sums' words (32 bits), +222 the sum of the header's
*        words before it
*   +256 the map, the pieces' sums, the data
*
* Up to +170 the header is what this start would write
* itself: any difference and the state is another PC's. The
* header, the map, the sums and the file's length are
* checked before a byte of memory is changed (BS_BOOT 4 and
* the PC boots). The data is read once: a piece that is not
* what its sum says, or cannot be read, stops the load with
* the PC half another's, and it is begun again from nothing
* (BS_BOOT 6: the front end loads CORE and SVC again and
* clears the PC's memory, as for the desk accessory's hard
* reboot; the start after that boots, BS_BOOT 7). No byte
* that failed its sum is ever put in memory, so the code
* this runs in stays its own.
*
* What is not in the file is the host's: the sound's saved
* page and vector, the mouse's interrupt, the paths, this
* file's own handles (bs_keep: kept across the load, where
* SVC's bank is the saved one); the DOC's registers, the
* tick count and the translator are brought into line after
* it, as after the accessory's restore.
*----------------------------------------------------------
BS_VER     = 2
BS_HLEN    = 256
H_BUILD    = 12
H_LAY      = 16
H_CMD      = 42
H_RG       = 170
H_MAPB     = 212
H_PAGES    = 214
H_TABB     = 216
H_MSUM     = 218
H_MFB      = 222
H_DAY      = 224
H_HSUM     = 254
BS_CH      = 32              ; pages a piece: the bounce buffer's
 err BS_CH*256-BOUNCE_LEN
BS_KEEPMAX = 1024
BS_DAYS    = 250             ; the days a state may be old: what the BIOS's midnight count can hand over
 err RG_COUNT*2+2+H_LAY-H_CMD     ; (the layout's words fill +16 to +42)
 err ST_NRG*6+H_RG-H_MAPB

bs_cmd     = bs_hdr+H_CMD    ; XTGS.CMD as this start read it (rd_readcfg), where the header has it
*bs_hdr, the header, and bs_home, the start's folder, are past the image's end: svc.s
bs_ent     dw 0              ; the file's handle entry * 8
bs_ref     dw 0              ; and its ProDOS reference
bs_s       adrl 0            ; a sum of words
bs_n       dw 0
bs_left    dw 0
bs_blk     adrl 0            ; bs_try's block: the map, a page for the direct page, the host's own fields
bs_blkh    adrl 0
bs_magic   asc 'XTGSboot'
bs_name    str 'XTGS.STATE'
bs_tmp     str 'XTGS.STATE.NEW'
bs_run     dw 0              ; pages of the piece in hand
bs_cs      adrl 0            ; and its sum
bs_day0    dw 0              ; the day the state in hand was written (clk_days)
bs_keep    dw snd_oldp,2,snd_pg1,256,snd_oldvec,4,snd_ctlr,2,snd_on,2,ms_irq,2
           dw rd_root,66,bs_home,66,bs_cmd,128,bs_blk,8,bs_day0,2,0
 err BS_HLEN-256

* bs_path - PATHBUF0 (X = 0) or PATHBUF1 (X = $40) = the start's
* folder and the name at A (Pascal). C set: too long.
bs_path
 mx %00
 sta sv8
 stx sv9
 lda bs_home
 and #$00FF
 sta sv7
 lda (sv8)
 and #$00FF
 clc
 adc sv7
 cmp #64
 bcc :fits
 rts
:fits
 ldx sv9
 sep #$20
 mx %10
 sta >PATHBUF0,x
 ldy #1
:h
 cpy sv7
 beq :hl
 bcs :name
:hl
 lda bs_home,y
 inx
 sta >PATHBUF0,x
 iny
 bra :h
:name
 lda (sv8)
 sta sv7
 ldy #1
:n
 cpy sv7
 beq :nl
 bcs :done
:nl
 lda (sv8),y
 inx
 sta >PATHBUF0,x
 iny
 bra :n
:done
 rep #$20
 mx %00
 clc
 rts

*----------------------------------------------------------
* The files the PC was started from (M7.3). While a PC from
* the folder runs, every partial pathname SVC opens (p_open)
* or looks for and does not find (p_open, p_getinfo) is kept
* in the table MF_TAB, in the results bank and so in a state:
* KERNEL.SYS, FDCONFIG.SYS, the drivers, COMMAND.COM,
* AUTOEXEC.BAT and what that runs, as it turns out. Full
* pathnames are XT/GS's own files and are not kept.
*
* An entry's state: 1 looked for and not there, 2 opened, 3
* the PC's own making (p_create came first, or after a 1).
* The PC changing one of the first two kinds (writing it,
* making it anew after it was read, destroying or renaming
* it) sets bit 7 and MF_BAD: the PC is then no longer what a
* boot would make of the folder, and bs_save refuses.
*
* bs_save writes each entry of the first two kinds with what
* the file is then (mf_ident: there or not; its dates and its
* length; the sum of its bytes when it is no more than the
* transfer buffer; of a directory only that it is there), and
* bs_try holds the folder to that before the state is used.
* A file longer than the buffer that is changed to the same
* length within the same minute is not noticed, nor is a new
* file that the boot would now find where it looked by a
* search of a directory and not by name.
*----------------------------------------------------------
mf_s       dw 0              ; what is being kept (1, 2), or done (3 made, 4 gone)
mf_l       dw 0              ; a name's length (the high byte stays 0)
mf_end     dw 0              ; the table's length, as mf_find went by it
mf_at      dw 0              ; mf_put: the entry in hand
mf_x       dw 0              ; mf_ident: its file's handle entry
mf_id      ds 12             ; mf_ident: 1 not there / 2 a file / 3 a directory; date; time; length (4); sum
mf_cur     adrl 0            ; mf_chk: the record in hand,
mf_left    dw 0              ; the bytes after it
mf_rl      dw 0              ; and its length
*mf_rec, a record (a length, the name, to an even length, mf_id), is past the image's end: svc.s

* mf_begin - a PC from the folder begins: nothing kept yet
mf_begin
 mx %00
 lda #0
 sta >MF_LEN
 sta >MF_BAD
 inc
 sta >MF_ON
 rts

* mf_miss - A = the ProDOS error of looking for the pathname at
* PATHBUF0+X: "no such file" is kept. (Y as mf_do.)
mf_miss
 mx %00
 and #$00FF
 cmp #$46
 beq :gone
 cmp #$44
 beq :gone
 ldy #0
 rts
:gone
 lda #1
* mf_do - the pathname at PATHBUF0+X (X = 0 or $40): A = 1 it was
* looked for and is not there, 2 it was opened, 3 the PC makes it,
* 4 the PC destroys or renames it. Y = the offset of its state in the
* table, + 1 (0: it is not kept). Uses A, X, Y and nothing else.
mf_do
 mx %00
 sta mf_s
 ldy #0
 lda >MF_ON
 bne :on
 rts
:on
 lda pTXT
 pha
 lda pTXT+2
 pha
 txa
 clc
 adc #PATHBUF0
 sta pTXT
 stz pTXT+2
 jsr mf_find
 bcs :new
 tyx                       ; in the table: its state
 lda mf_s
 cmp #3
 bcc :ret                  ; (seen again: what was first seen stands)
 sep #$20
 mx %10
 lda >MF_TAB,x
 and #$7F
 cmp #3
 beq :ret8                 ; the PC's own: its to change
 ldy mf_s
 cpy #3
 bne :dirty                ; destroyed or renamed
 cmp #1
 bne :dirty                ; read, and now made anew
 lda #3                    ; not there, and now the PC's own
 sta >MF_TAB,x
 bra :ret8
:dirty
 lda >MF_TAB,x
 ora #$80
 sta >MF_TAB,x
 rep #$20
 mx %00
 lda >MF_BAD
 ora #2
 sta >MF_BAD
 bra :ret
:ret8
 rep #$20
 mx %00
:ret
 txy
 iny
:out
 pla
 sta pTXT+2
 pla
 sta pTXT
 rts
:new
 tya
 bne :out0                 ; (not a name to keep)
 lda mf_s
 cmp #4
 beq :out0
 lda [pTXT]
 and #$00FF
 sta mf_l
 clc
 adc #2
 adc mf_end
 cmp #MF_MAX+1
 bcc :room
 lda >MF_BAD               ; the table is too small: no state of this PC
 ora #1
 sta >MF_BAD
 bra :out0
:room
 sta >MF_LEN
 ldx mf_end
 ldy #0
 sep #$20
 mx %10
:cp
 lda [pTXT],y              ; the length and the name
 sta >MF_TAB,x
 inx
 tya
 cmp mf_l
 iny
 bcc :cp
 lda mf_s
 sta >MF_TAB,x
 rep #$20
 mx %00
 bra :ret
:out0
 ldy #0
 bra :out

* mf_find - the pathname at [pTXT] in the table. C clear: Y = the
* offset of its state. C set: Y = 0 it is not there, $FFFF it is
* not a name to keep (none, or a full pathname).
mf_find
 mx %00
 lda >MF_LEN               ; (never past the table, whatever the word says)
 cmp #MF_MAX+1
 bcc :lenok
 lda #0
:lenok
 sta mf_end
 ldx #0
 sep #$20
 mx %10
 lda [pTXT]
 beq :noname
 ldy #1
 lda [pTXT],y
 cmp #'/'
 beq :noname
:ent
 cpx mf_end
 bcs :none
 lda >MF_TAB,x
 sta mf_l
 cmp [pTXT]
 bne :next
 phx
 ldy #1
:c
 inx
 lda >MF_TAB,x
 cmp [pTXT],y
 bne :diff
 tya
 cmp mf_l
 iny
 bcc :c
 inx
 txy
 plx
 rep #$20
 mx %00
 clc
 rts
:diff
 mx %10
 plx
:next
 rep #$20
 mx %00
 txa
 clc
 adc mf_l
 adc #2
 tax
 sep #$20
 mx %10
 bra :ent
:noname
 rep #$20
 mx %00
 ldy #$FFFF
 sec
 rts
:none
 mx %10
 rep #$20
 mx %00
 ldy #0
 sec
 rts

* mf_wr - the file of handle entry X is written or cut short: when
* it is one the PC was started from, it is that no more. Keeps X.
mf_wr
 mx %00
 lda htab+5,x
 beq :no
 phx
 tax
 dex
 sep #$20
 mx %10
 lda >MF_TAB,x
 cmp #2
 bne :n8
 ora #$80
 sta >MF_TAB,x
 rep #$20
 mx %00
 lda >MF_BAD
 ora #2
 sta >MF_BAD
:n8
 rep #$20
 mx %00
 plx
:no
 rts

* mf_ident - mf_id = what the file at PATHBUF0 is now. (MF_ON must
* be 0: this looks at files for itself.)
mf_ident
 mx %00
 ldx #10
:z
 stz mf_id,x
 dex
 dex
 bpl :z
 ldx #0
 jsr p_getinfo
 bcc :is
 lda #1                    ; not there
 sta mf_id
 rts
:is
 lda >MB_MLI_PARMS+7
 and #$00FF
 cmp #$0D
 bcc :file
 lda #3                    ; a directory: that it is there
 sta mf_id
 rts
:file
 lda #2
 sta mf_id
 lda >MB_MLI_PARMS+10
 sta mf_id+2
 lda >MB_MLI_PARMS+12
 sta mf_id+4
 ldx #0
 lda #0
 jsr p_open
 bcs :out                  ; (there, and not to be opened: its dates are all)
 stx mf_x
 lda htab,x
 xba
 and #$00FF
 sta sv5
 jsr bs_geteof
 bcs :cl
 lda >MB_MLI_PARMS+2
 sta mf_id+6
 lda >MB_MLI_PARMS+4
 and #$00FF
 sta mf_id+8
 bne :cl                   ; longer than the buffer: its dates and its length
 lda mf_id+6
 beq :cl
 cmp #BOUNCE_LEN+1
 bcs :cl
 jsr bs_rd
 bcs :cl
 ldx #0                    ; the sum of its bytes, turned as it goes
:s
 lda >BOUNCEBUF,x
 and #$00FF
 clc
 adc mf_id+10
 asl
 adc #0
 sta mf_id+10
 inx
 cpx mf_id+6
 bcc :s
:cl
 ldx mf_x
 jsr p_close
:out
 rts

* mf_put - bs_save: every entry that is not the PC's own, with what
* its file is now, to the state's file; bs_hdr+H_MFB their bytes,
* bs_s their words added in. C set: the disk.
mf_put
 mx %00
 stz bs_hdr+H_MFB
 stz mf_at
:ent
 lda mf_at
 cmp >MF_LEN
 bcc :more
 clc
 rts
:more
 stz mf_s
 ldx mf_at
 lda >MF_TAB,x
 and #$00FF
 sta mf_l
 ldy #0
 sep #$20
 mx %10
:cp
 lda >MF_TAB,x
 sta mf_rec,y
 inx
 tya
 cmp mf_l
 iny
 bcc :cp
 lda >MF_TAB,x
 sta mf_s
 rep #$20
 mx %00
 inx
 stx mf_at
 lda mf_s
 and #$007F
 cmp #3
 beq :ent                  ; the PC's own: nothing to hold it to
 ldx #62
:pp
 lda mf_rec,x
 sta >PATHBUF0,x
 dex
 dex
 bpl :pp
 jsr mf_ident
 ldx mf_l
 stz mf_rec+1,x            ; (to an even length)
 txa
 inc
 inc
 and #$FFFE
 tay
 ldx #0
:id
 lda mf_id,x
 sta mf_rec,y
 iny
 iny
 inx
 inx
 cpx #12
 bcc :id
 sty bs_n
 tya
 clc
 adc bs_hdr+H_MFB
 sta bs_hdr+H_MFB
 jsr :rec
 jsr bs_add
 jsr :rec
 lda bs_n
 jsr bs_write
 bcs :wno
 jmp :ent
:wno
 rts
:rec
 lda #mf_rec
 sta pGST
 lda #^mf_rec
 sta pGST+2
 rts

* mf_chk - bs_try: the H_MFB bytes of records at bs_blk: is every
* file what it was? C set: no (or they are no records).
mf_chk
 mx %00
 lda bs_blk
 sta mf_cur
 lda bs_blk+2
 sta mf_cur+2
 lda bs_hdr+H_MFB
 sta mf_left
:rec
 lda mf_left
 bne :more
 clc
 rts
:more
 lda mf_cur
 sta pGST
 lda mf_cur+2
 sta pGST+2
 lda [pGST]
 and #$00FF
 beq :bad
 cmp #64
 bcs :bad
 sta mf_l
 inc
 inc
 and #$FFFE
 sta mf_at                 ; where the record has what the file was
 clc
 adc #12
 sta mf_rl
 lda mf_left
 cmp mf_rl
 bcc :bad
 ldy #0
 sep #$20
 mx %10
:cp
 lda [pGST],y
 tyx
 sta >PATHBUF0,x
 tya
 cmp mf_l
 iny
 bcc :cp
 rep #$20
 mx %00
 ldy mf_at
 ldx #0
:id
 lda [pGST],y
 sta mf_rec,x
 iny
 iny
 inx
 inx
 cpx #12
 bcc :id
 jsr mf_ident
 ldx #10
:cmp
 lda mf_id,x
 cmp mf_rec,x
 bne :bad
 dex
 dex
 bpl :cmp
 lda mf_cur
 clc
 adc mf_rl
 sta mf_cur
 bcc :nc
 inc mf_cur+2
:nc
 lda mf_left
 sec
 sbc mf_rl
 sta mf_left
 jmp :rec
:bad
 sec
 rts

* bs_geteof - the file of reference sv5: MB_MLI_PARMS+2 (three bytes)
* its length. C set: no.
bs_geteof
 mx %00
 lda #2
 sta >MB_MLI_PARMS
 sep #$20
 mx %10
 lda sv5
 sta >MB_MLI_PARMS+1
 rep #$20
 mx %00
 lda #$D1
 jmp mli

* bs_now - bs_hdr's first part, as this start writes it
bs_now
 mx %00
 ldx #H_CMD-2              ; (the command file's part is there since rd_readcfg)
:z
 stz bs_hdr,x
 dex
 dex
 bpl :z
 ldx #BS_HLEN-H_RG-2
:z2
 stz bs_hdr+H_RG,x
 dex
 dex
 bpl :z2
 ldx #6
:m
 lda bs_magic,x
 sta bs_hdr,x
 dex
 dex
 bpl :m
 lda #BS_VER
 sta bs_hdr+8
 lda #BS_HLEN
 sta bs_hdr+10
 lda #BUILD_LO
 sta bs_hdr+H_BUILD
 lda #BUILD_HI
 sta bs_hdr+H_BUILD+2
 ldx #RG_COUNT*2
:l
 lda >MB_LAYOUT,x
 sta bs_hdr+H_LAY,x
 dex
 dex
 bpl :l
 rts

* bs_add - bs_s += the words of the bs_n bytes (even, not 0) at
* [pGST]; pGST goes on
bs_add
 mx %00
 lda bs_n
 beq :out
 ldx bs_s+2
 lda bs_s
 ldy #0
 clc
:w
 adc [pGST],y
 bcc :nc
 inx
 clc
:nc
 iny
 iny
 cpy bs_n
 bcc :w
 sta bs_s
 stx bs_s+2
 tya
 clc
 adc pGST
 sta pGST
 bcc :out
 inc pGST+2
:out
 rts

* bs_hsum - A = the sum of the header's words before H_HSUM
bs_hsum
 mx %00
 lda #0
 ldx #H_HSUM-2
:l
 clc
 adc bs_hdr,x
 dex
 dex
 bpl :l
 rts

* bs_setp - pGST = the long at A (an address in this bank)
bs_setp
 mx %00
 sta sv8
 lda (sv8)
 sta pGST
 ldy #2
 lda (sv8),y
 sta pGST+2
 rts

* bs_tabb - A = the bytes of the sums of A pages of data
bs_tabb
 mx %00
 clc
 adc #BS_CH-1
 lsr
 lsr
 lsr
 lsr
 lsr
 asl
 asl
 rts
 err BS_CH-32

* bs_piece - bs_run = the pages of the next piece of the bs_left
* that are left (taken from bs_left); Z set: none
bs_piece
 mx %00
 lda bs_left
 cmp #BS_CH+1
 bcc :few
 lda #BS_CH
:few
 sta bs_run
 lda bs_left
 sec
 sbc bs_run
 sta bs_left
 lda bs_run
 rts

* bs_save - the PC as it is now, to XTGS.STATE. BS_STAT: 1 written,
* 2 not now (a file open or a serial port in use), 3 no memory, 4 the
* disk, 5 not this PC (booted from a disk image), 6 the PC has changed
* a file it was started from, 7 it has opened more files than the
* table holds (either way it is not what a boot would make).
bs_save
 mx %00
 jsr bs_can
 beq :asboot
 sta >BS_STAT
 rts
:asboot
 jsr st_save
 lda >CTL_STAT
 cmp #1
 beq :saved
 lda #3
 sta >BS_STAT
 rts
:saved
 lda >MF_ON                ; (what follows looks at files for itself: none of it is kept)
 pha
 lda #0
 sta >MF_ON
 jsr bs_file
 pla
 sta >MF_ON
 rts

* bs_can - may the PC as it is now be written? A = 0, or what
* BS_STAT is to say: 2, 5, 6 or 7. It changes nothing and looks at
* no file: the desk accessory asks it too, when the choice is made
* (control.s), so that "not now" is said there and then and not
* found out at the next start.
bs_can
 mx %00
 lda rd_boot               ; (a PC booted from an image has written to a copy of it in memory)
 bne :folder
 lda #5
 rts
:folder
 lda >COM_OPEN
 bne :busy
 ldx #0
:q
 lda htab,x
 and #$00FF
 cmp #H_FILE
 beq :busy
 txa
 clc
 adc #8
 tax
 cpx #NHANDLES*8
 bcc :q
 lda >MF_BAD               ; still what a boot makes of the folder's files?
 beq :ok
 and #2
 beq :many
 lda #6                    ; it has changed one of them
 rts
:many
 lda #7                    ; or opened more than the table holds
 rts
:busy
 lda #2
 rts
:ok
 lda #0
 rts

* bs_file - bs_save's: the state that st_save made, to the file
bs_file
 mx %00
 jsr bs_now
 jsr clk_read              ; the day it is written on (svc_stload makes up the days since)
 jsr clk_days
 sta bs_hdr+H_DAY
 ldx #ST_NRG*6-2
 lda #0
 sta bs_left
:rg
 lda st_rg,x
 sta bs_hdr+H_RG,x
 dex
 dex
 bpl :rg
 ldx #4                    ; the map: a word a page
:pg
 lda st_rg,x
 clc
 adc bs_left
 sta bs_left
 txa
 clc
 adc #6
 tax
 cpx #ST_NRG*6
 bcc :pg
 lda bs_left
 asl
 sta bs_hdr+H_MAPB
 lda st_pages
 sta bs_hdr+H_PAGES
 jsr bs_tabb
 sta bs_hdr+H_TABB
 lda #bs_tmp               ; written under another name, and the old one's taken when it is whole
 ldx #0
 jsr bs_path
 bcc :named
 jmp :disk
:named
 jsr p_destroy             ; (one left from a save that did not finish)
 jsr bs_create
 bcc :made
 jmp :disk
:made
 ldx #0
 lda #2
 jsr p_open
 bcc :open
 jmp :disk
:open
 stx bs_ent
 lda #bs_hdr               ; the header's place (written again at the end, when the sums are known)
 sta pGST
 lda #^bs_hdr
 sta pGST+2
 lda #BS_HLEN
 jsr bs_write
 bcc :w1
 jmp :wfail
:w1
 stz bs_s                  ; the files the PC was started from, as they are now
 stz bs_s+2
 jsr mf_put
 bcc :m1
 jmp :wfail
:m1
 lda #st_map               ; the map
 jsr bs_setp
 lda bs_hdr+H_MAPB
 sta bs_n
 jsr bs_add
 lda #st_map
 jsr bs_setp
 lda bs_hdr+H_MAPB
 jsr bs_write
 bcc :w2
 jmp :wfail
:w2
 lda st_dat                ; the sum of each piece of the data
 sta pARG
 lda st_dat+2
 sta pARG+2
 lda bs_hdr+H_PAGES
 sta bs_left
:sums
 jsr bs_piece
 beq :w3
 lda bs_s                  ; (the sum so far waits)
 pha
 lda bs_s+2
 pha
 stz bs_s
 stz bs_s+2
 lda pARG
 sta pGST
 lda pARG+2
 sta pGST+2
 lda bs_run
 xba
 sta bs_n
 jsr bs_add
 lda pGST
 sta pARG
 lda pGST+2
 sta pARG+2
 lda bs_s
 sta bs_cs
 lda bs_s+2
 sta bs_cs+2
 pla
 sta bs_s+2
 pla
 sta bs_s
 jsr :cs                   ; its words into the sum of the map and the sums,
 lda #4
 sta bs_n
 jsr bs_add
 jsr :cs                   ; and to the file
 lda #4
 jsr bs_write
 bcc :sums
 jmp :wfail
:cs
 lda #bs_cs
 sta pGST
 lda #^bs_cs
 sta pGST+2
 rts
:w3
 lda bs_s
 sta bs_hdr+H_MSUM
 lda bs_s+2
 sta bs_hdr+H_MSUM+2
 lda st_dat                ; the data, a piece a write
 sta pARG
 lda st_dat+2
 sta pARG+2
 lda bs_hdr+H_PAGES
 sta bs_left
:data
 jsr bs_piece
 beq :w4
 lda pARG
 sta pGST
 lda pARG+2
 sta pGST+2
 lda bs_run
 xba
 pha
 clc
 adc pARG
 sta pARG
 bcc :dn
 inc pARG+2
:dn
 pla
 jsr bs_write
 bcc :data
 bra :wfail
:w4
 jsr bs_hsum
 sta bs_hdr+H_HSUM
 stz sv8                   ; and the header as it is now, at the file's start
 stz sv9
 ldx bs_ent
 jsr p_setmark
 bcs :wfail
 lda #bs_hdr
 sta pGST
 lda #^bs_hdr
 sta pGST+2
 lda #BS_HLEN
 jsr bs_write
 bcc :wrote
:wfail
 ldx bs_ent
 jsr p_close
 lda #bs_tmp
 ldx #0
 jsr bs_path
 jsr p_destroy
:disk
 jsr st_drop
 lda #4
 sta >BS_STAT
 rts
:wrote
 ldx bs_ent
 jsr p_close
 lda #bs_name              ; the one before goes, and this is the state
 ldx #0
 jsr bs_path
 jsr p_destroy
 lda #bs_tmp
 ldx #0
 jsr bs_path
 lda #bs_name
 ldx #$40
 jsr bs_path
 jsr p_rename
 bcs :disk
 jsr st_drop               ; (the memory it took goes back)
 lda #1
 sta >BS_STAT
 rts

* bs_write - A bytes from [pGST] to the file. C set: not all of them.
bs_write
 mx %00
 sta sv0
 pha
 ldx bs_ent
 jsr p_write
 bcs :no
 cmp 1,s
 bne :no
 pla
 clc
 rts
:no
 pla
 sec
 rts

* bs_create - PATHBUF0: a new file, type $06
bs_create
 mx %00
 lda #7
 sta >MB_MLI_PARMS
 lda #PATHBUF0
 sta >MB_MLI_PARMS+1
 lda #$06C3                ; access $C3, file type $06 BIN
 sta >MB_MLI_PARMS+3
 lda #0
 sta >MB_MLI_PARMS+5
 lda #1                    ; a standard file; the date and time ProDOS's
 sta >MB_MLI_PARMS+7
 lda #0
 sta >MB_MLI_PARMS+9
 sta >MB_MLI_PARMS+11
 lda #$C0
 jmp mli

* bs_rd - A bytes of the file (its reference in sv5) to BOUNCEBUF. C
* set: not that many (MB_MLI_PARMS+6 has how many).
bs_rd
 mx %00
 sta sv0
 sta >MB_MLI_PARMS+4
 lda #0
 sta >MB_MLI_PARMS+6
 lda #4
 sta >MB_MLI_PARMS
 sep #$20
 mx %10
 lda sv5
 sta >MB_MLI_PARMS+1
 rep #$20
 mx %00
 lda #BOUNCEBUF
 sta >MB_MLI_PARMS+2
 lda #$CA
 jsr mli
 bcs :no
 lda >MB_MLI_PARMS+6
 cmp sv0
 beq :ok
 sec
 rts
:ok
 clc
:no
 rts

* bs_try - svc_bootinit: is there a boot state to start from? C set:
* there is: its header, its map and its pieces' sums are sound, its
* length is what they say, the map and the sums are in memory
* (bs_blk) and the file is open at the data; svc_stload does the
* rest. C clear: the PC boots. BS_BOOT says which and why: 0 not
* asked for, 2 no file, 3 another build's, layout's or
* configuration's, 4 damaged (BS_WHERE: how far the look got), 5 no
* memory, 7 its data was found damaged in the load at the start
* before this one (which began the PC again: this one boots).
* bs_said - under the sign-on of a PC that boots although a boot
* state was asked for and there is a file: why the file was not
* what it started from (BS_BOOT 3 to 9; for 3, bs_at is where the
* header and this start part: XTGS.CMD's bytes are its last part,
* the layout before them, the build before that).
bs_said
 mx %00
 lda >BS_CFG
 beq :out
 lda >BS_BOOT
 and #$00FF
 cmp #3
 bcc :out                  ; (not asked for, used, none there)
 cmp #10
 bcs :out                  ; (the hard reboot asked for the boot)
 cmp #3
 bne :not3
 ldx #0
 lda bs_at
 cmp #H_CMD
 bcs :say
 inx
 inx
 cmp #H_LAY
 bcs :say
 inx
 inx
 bra :say
:not3
 asl
 tax
:say
 phx
 lda #$000F
 sta tty_attr
 lda #bs_t0
 jsr rd_puts
 plx
 lda bs_tt,x
 jsr rd_puts
 lda #$0D
 jsr vid_tty
 lda #$0A
 jsr vid_tty
 lda #$FFFF
 sta tty_attr
:out
 rts
bs_at      dw 0
bs_tt      da bs_t1,bs_t2,bs_t3,0,bs_t4,bs_t5,bs_t4,bs_t4,bs_t8,bs_t9   ; (0-2: BS_BOOT 3 by bs_at; from 4: BS_BOOT)
bs_t0      asc 'Boot state not used: ',00
bs_t1      asc 'XTGS.CMD has changed',00
bs_t2      asc 'XT/GS is elsewhere in memory',00
bs_t3      asc 'another build of XT/GS',00
bs_t4      asc 'the file is damaged',00
bs_t5      asc 'no memory',00
bs_t8      asc 'a file DOS boots from has changed',00
bs_t9      asc 'its date',00

bs_try
 mx %00
 lda >BS_SKIP              ; (the desk accessory's hard reboot: a boot, this once)
 tax
 lda #0
 sta >BS_SKIP
 lda >BS_CFG
 bne :on
 lda #0
 sta >BS_BOOT
 clc
 rts
:on
 lda rd_boot               ; (the S command only, as bs_save)
 beq :nofile
 cpx #BS_SKIPV
 bne :asked
 lda #10
 bra :why
:asked
 lda >BS_BOOT              ; a load that failed half way: not again
 cmp #6
 bne :look
 lda #7
 bra :why
:nofile
 lda #2
:why
 sta >BS_BOOT
 clc
 rts
:look
 lda #bs_name
 ldx #0
 jsr bs_path
 bcs :nofile
 ldx #0
 lda #0
 jsr p_open
 bcs :nofile
 stx bs_ent
 lda htab,x
 xba
 and #$00FF
 sta bs_ref
 sta sv5
 lda #1
 sta >BS_WHERE
 lda #BS_HLEN
 jsr bs_rd
 bcc :hdr
:damaged
 lda #4
:close
 pha
 ldx bs_ent
 jsr p_close
 pla
 bra :why
:hdr
 jsr bs_now                ; the header's first part must be this start's own
 ldx #H_RG-2
:same
 lda >BOUNCEBUF,x
 cmp bs_hdr,x
 beq :s2
 stx bs_at                 ; (where it is not: bs_said)
 lda #3
 bra :close
:s2
 dex
 dex
 bpl :same
 ldx #BS_HLEN-2            ; the rest is the file's
:cp
 lda >BOUNCEBUF,x
 sta bs_hdr,x
 dex
 dex
 bpl :cp
 lda #2
 sta >BS_WHERE
 jsr bs_hsum
 cmp bs_hdr+H_HSUM
 beq :k1
 jmp :damaged
:k1
 lda #3
 sta >BS_WHERE
 jsr st_regs               ; the regions: this start's own, but for how much XMS memory was in use
 ldx #ST_NRG*6-2
:rg
 cpx #28                   ; (the XMS region's pages)
 beq :rn
 lda st_rg,x
 cmp bs_hdr+H_RG,x
 beq :k2
 jmp :damaged
:k2
:rn
 dex
 dex
 bpl :rg
 lda #4
 sta >BS_WHERE
 lda bs_hdr+H_RG+28
 beq :xok
 lda xms_on                ; XMS memory in the state: this PC must have the driver, and the room
 bne :k3
 jmp :damaged
:k3
 lda bs_hdr+H_RG+28
 cmp #DISK_BANKS*256+1
 bcc :k4
 jmp :damaged
:k4
:xok
 lda #5
 sta >BS_WHERE
 lda #4993                 ; the pages of the six regions that do not vary
 clc
 adc bs_hdr+H_RG+28
 asl
 cmp bs_hdr+H_MAPB
 beq :k5
 jmp :damaged
:k5
 lsr
 cmp bs_hdr+H_PAGES
 bcs :k6
 jmp :damaged
:k6
 lda bs_hdr+H_PAGES
 jsr bs_tabb
 cmp bs_hdr+H_TABB
 beq :k7
 jmp :damaged
:k7
 lda bs_hdr+H_MFB          ; the files' records: an even number of bytes, and not a silly one
 bit #1
 beq :f1
 jmp :damaged
:f1
 cmp #$1001
 bcc :f2
 jmp :damaged
:f2
 jsr clk_read              ; the day: not before the state's, and not so long after it that the
 jsr clk_days              ; days cannot be made up
 sec
 sbc bs_hdr+H_DAY
 cmp #BS_DAYS+1
 bcc :dayok
 lda #9
 jmp :close
:dayok
 lda bs_hdr+H_DAY
 sta bs_day0
 lda #6
 sta >BS_WHERE
 lda bs_ref                ; the header, the records, the map, the sums and the data, and no more
 sta sv5
 jsr bs_geteof
 bcc :k8
 jmp :damaged
:k8
 lda bs_hdr+H_PAGES
 xba
 and #$FF00
 sta sv0
 lda bs_hdr+H_PAGES
 xba
 and #$00FF
 sta sv1
 lda bs_hdr+H_MAPB
 clc
 adc bs_hdr+H_TABB
 adc bs_hdr+H_MFB
 adc #BS_HLEN
 clc
 adc sv0
 sta sv0
 bcc :e1
 inc sv1
:e1
 lda >MB_MLI_PARMS+2
 cmp sv0
 beq :k9
 jmp :damaged
:k9
 lda >MB_MLI_PARMS+4
 and #$00FF
 cmp sv1
 beq :k10
 jmp :damaged
:k10
 lda #7
 sta >BS_WHERE
 lda bs_hdr+H_MAPB         ; the block: the records, the map, the sums, a page, the host's fields
 clc
 adc bs_hdr+H_TABB
 adc bs_hdr+H_MFB
 adc #BS_KEEPMAX+256
 sta st_sz
 stz st_sz+2
 jsr st_new
 bcc :mem
 lda #5
 jmp :close
:mem
 sta bs_blk
 stx bs_blk+2
 lda st_h
 sta bs_blkh
 lda st_h+2
 sta bs_blkh+2
 lda #8
 sta >BS_WHERE
 lda bs_blk                ; the records, the map and the sums, read to where they stay
 sta pGST
 lda bs_blk+2
 sta pGST+2
 lda bs_hdr+H_MAPB
 clc
 adc bs_hdr+H_TABB
 adc bs_hdr+H_MFB
 sta bs_n
 sta sv0
 ldx bs_ent
 jsr p_read
 bcc :k11
 jmp :bad
:k11
 cmp bs_n
 beq :k12
 jmp :bad
:k12
 stz bs_s
 stz bs_s+2
 lda #bs_blk
 jsr bs_setp
 jsr bs_add
 lda bs_s
 cmp bs_hdr+H_MSUM
 beq :k13
 jmp :bad
:k13
 lda bs_s+2
 cmp bs_hdr+H_MSUM+2
 beq :k14
 jmp :bad
:k14
 lda #9
 sta >BS_WHERE
 jsr mf_chk                ; and the files the PC was started from: each as it was?
 bcc :files
 lda bs_blkh+2
 ldx bs_blkh
 jsr st_free
 lda #8
 jmp :close
:files
 lda #10
 sta >BS_WHERE
 sec
 rts
:bad
 lda bs_blkh+2
 ldx bs_blkh
 jsr st_free
 jmp :damaged

* svc_stload - the core's, after the sound is open: the state that
* bs_try found into its places, a region after the other; SVC's bank
* last but for the direct page, which waits in the block. Everything
* this routine keeps is in the direct page as it loads (its variables
* in this bank become the saved PC's under it), and it changes no code
* of its own for the same reason: a page it puts over its own code is
* that code again, the build being the same and the piece held to its
* sum first. C set: a piece was not what its sum says, or was not
* read: the PC is half another's and must be begun again from nothing
* (BS_BOOT 6).
svc_stload
 mx %00
 phb
 phk
 plb
 lda bs_blk                ; the map (after the files' records),
 clc
 adc bs_hdr+H_MFB
 sta pDTA
 lda bs_blk+2
 adc #0
 sta pDTA+2
 lda pDTA                  ; the pieces' sums after it,
 clc
 adc bs_hdr+H_MAPB
 sta pIMG
 lda pDTA+2
 adc #0
 sta pIMG+2
 lda pIMG                  ; the page the direct page waits in
 clc
 adc bs_hdr+H_TABB
 sta pARG
 lda pIMG+2
 adc #0
 sta pARG+2
 lda pARG                  ; and the host's fields after it
 clc
 adc #256
 sta pCELL
 lda pARG+2
 adc #0
 sta pCELL+2
 jsr bs_stash
 lda bs_ref
 sta sv5
 lda bs_hdr+H_PAGES
 sta sv4                   ; pages of data the file still has
 stz sv2                   ; pages in the buffer
 stz sv6                   ; the region * 6
:region
 ldx sv6
 lda bs_hdr+H_RG,x
 sta pGST+2
 lda bs_hdr+H_RG+2,x
 sta pGST
 lda bs_hdr+H_RG+4,x
 sta sv1
 cpx #0
 bne :pages
 lda pARG                  ; (the direct page is in use)
 sta pGST
 lda pARG+2
 sta pGST+2
:pages
 lda sv1
 bne :page
 jmp :nextreg
:page
 lda [pDTA]
 and #$FF00
 beq :raw
 lda [pDTA]                ; a page of one byte
 and #$00FF
 sta sv3
 xba
 ora sv3
 ldy #254
:fill
 sta [pGST],y
 dey
 dey
 bpl :fill
 bra :adv
:raw
 lda sv2
 bne :have
 lda sv4                   ; the next piece: BS_CH pages, or what is left
 bne :more
 jmp :fail
:more
 cmp #BS_CH+1
 bcc :few
 lda #BS_CH
:few
 sta sv2
 lda sv4
 sec
 sbc sv2
 sta sv4
 lda sv2
 xba
 sta sv3
 jsr bs_rd
 bcc :got
 jmp :fail
:got
 lda #BOUNCEBUF
 sta pTXT
 stz pTXT+2
 ldx #0                    ; held to its sum before a byte of it is used
 txa
 tay
 clc
:sum
 adc [pTXT],y
 bcc :snc
 inx
 clc
:snc
 iny
 iny
 cpy sv3
 bcc :sum
 cmp [pIMG]
 bne :failj
 txa
 ldy #2
 cmp [pIMG],y
 beq :sok
:failj
 jmp :fail
:sok
 lda pIMG
 clc
 adc #4
 sta pIMG
 bcc :have
 inc pIMG+2
:have
 ldy #254
:copy
 lda [pTXT],y
 sta [pGST],y
 dey
 dey
 bpl :copy
 inc pTXT+1
 dec sv2
:adv
 inc pGST+1                ; (a page on: the word at +1 is the page and the bank)
 lda pDTA
 clc
 adc #2
 sta pDTA
 bcc :nc
 inc pDTA+2
:nc
 dec sv1
 jmp :pages
:nextreg
 lda sv6
 clc
 adc #6
 sta sv6
 cmp #ST_NRG*6
 bcs :loaded
 jmp :region
:loaded
 jsr bs_unstash            ; (this bank's variables are the saved PC's now: the host's own back)
 lda sv4                   ; and that was all of the data?
 bne :fail2
 jsr bs_shut
 ldy #254                  ; the direct page, by way of the buffer (the pointers are in it)
:d1
 lda [pARG],y
 tyx
 sta >BOUNCEBUF,x
 dey
 dey
 bpl :d1
 ldx #254
:d2
 lda >BOUNCEBUF,x
 sta >GUEST_DP,x
 dex
 dex
 bpl :d2
 lda bs_blkh+2
 ldx bs_blkh
 jsr st_free
 lda #0                    ; and the host is brought into line, as after the accessory's restore
 sta >CTL_STAT
 sta >CTL_REQ
 sta >BS_STAT
 inc
 sta >CTL_LIVE
 sta >EGA_SYNC
 sta >BS_BOOT
 jsr st_docs
 jsr clk_init              ; the tick count: the time it is now,
 jsr clk_days              ; and the days gone by since the state was written (of the same reading
 sec                       ; of the clock) are midnights DOS has yet to be told of: INT 1Ah's
 sbc bs_day0               ; function 00h hands over their count, and FreeDOS adds it to its date
 beq :today
 cmp #BS_DAYS+1
 bcs :today
 sta sv0
 sep #$20
 mx %10
 lda >H_BDA+BDA_MIDNT
 clc
 adc sv0
 bcc :fits
 lda #$FF
:fits
 sta >H_BDA+BDA_MIDNT
 rep #$20
 mx %00
:today
 stz vTICK
 plb
 clc
 rtl
:fail
 jsr bs_unstash
:fail2
 jsr bs_shut
 lda bs_blkh+2
 ldx bs_blkh
 jsr st_free
 lda #0                    ; the results bank is half another PC's: all of it away
 sta >RES_BASE
 ldx #<RES_BASE
 ldy #<RES_BASE+2
 lda #$FFFD
 mvn RES_BASE,RES_BASE
 phk
 plb
 lda #6
 sta >BS_BOOT
 plb
 sec
 rtl

* bs_shut - the state's file closed (by its reference: the handle
* table is the saved PC's, where it is no file)
bs_shut
 mx %00
 lda #1
 sta >MB_MLI_PARMS
 sep #$20
 mx %10
 lda sv5
 sta >MB_MLI_PARMS+1
 rep #$20
 mx %00
 lda #$CC
 jmp mli

* bs_stash, bs_unstash - the host's own fields (bs_keep) to the block
* at pCELL and back
bs_stash
 mx %00
 lda #0
 bra bs_st
bs_unstash
 mx %00
 lda #1
bs_st
 mx %00
 sta sv7
 lda pCELL
 sta pTXT
 lda pCELL+2
 sta pTXT+2
 ldx #0
:item
 lda bs_keep,x
 beq :done
 sta sv8
 lda bs_keep+2,x
 sta sv9
 ldy #0
 sep #$20
 mx %10
:b
 lda sv7
 bne :back
 lda (sv8),y
 sta [pTXT],y
 bra :n
:back
 lda [pTXT],y
 sta (sv8),y
:n
 iny
 cpy sv9
 bcc :b
 rep #$20
 mx %00
 lda pTXT
 clc
 adc sv9
 sta pTXT
 bcc :nc
 inc pTXT+2
:nc
 inx
 inx
 inx
 inx
 bra :item
:done
 rts
