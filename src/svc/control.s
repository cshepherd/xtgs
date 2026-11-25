*----------------------------------------------------------
* control.s - "XTGS Control", a classic desk accessory
* (docs/control.md). The front end installs it with the
* Desk Manager while a PC runs (cda_on: its start routine is
* SVC's entry 14), so Control-Apple-Esc shows it in the
* desk accessories' menu.
*
* The accessory runs inside whatever was interrupted, the
* core in the middle of an instruction as likely as not, so
* it does nothing to the PC itself: it draws its menu on
* the 40-column text screen the Desk Manager has put up
* (straight into the page at $E0/0400), reads the keyboard
* at $C000 and leaves a request in CTL_REQ. svc_vbl finds
* it at the next frame and returns it to the core with the
* carry set, the core stops as for a program's exit, and
* the front end does the rest: it loads CORE and SVC anew
* and runs the PC again (after a hard reboot's request, with
* the PC's memory cleared first).
*
* No direct page is used here and no firmware called: D and
* the mode are the Desk Manager's and are given back.
*----------------------------------------------------------
CTL_SOFT   = 1               ; CTL_REQ: the PC restarted, its memory kept
CTL_HARD   = 2               ; restarted with its memory cleared
CTL_QUIT   = 3               ; XT/GS left, with no key waited for
CTL_SAVE   = 4               ; the PC's state kept in memory (st_save)
CTL_REST   = 5               ; and put back (st_restore)
CTL_BOOT   = 6               ; the PC's state written to XTGS.STATE, to start from (state.s: bs_save)
CTL_EXIT   = $B0C0           ; the core's exit code is this + the request
TXT40      = $E00000         ; the text page is at +$400
ctl_row    dw $400,$480,$500,$580,$600,$680,$700,$780
           dw $428,$4A8,$528,$5A8,$628,$6A8,$728,$7A8
           dw $450,$4D0,$550,$5D0,$650,$6D0,$750,$7D0
ctl_pick   dw 0

* Lines: the place on the screen (a row's address + the column), the
* text, 0. $FFFF ends a list.
ctl_head   dw $500+14
           asc 'XTGS Control'
           hex 00
           dw $750+4
           asc 'Esc  Back'
           hex 00
           dw $FFFF
ctl_items  dw $600+4
           asc '1  Soft reboot (as Ctrl-Alt-Del)'
           hex 00
           dw $680+4
           asc '2  Hard reboot (memory cleared)'
           hex 00
           dw $700+4
           asc '3  Save state'
           hex 00
           dw $780+4
           asc '4  Restore state'
           hex 00
           dw $FFFF
ctl_qp8    dw $428+4
           asc '5  Quit to ProDOS'
           hex 00
           dw $FFFF
ctl_qgs    dw $428+4
           asc '5  Quit to GS/OS'
           hex 00
           dw $FFFF
ctl_nost   dw $780+22
           asc '(none saved)'
           hex 00
           dw $FFFF
ctl_nomem  dw $528+4
           asc 'The last save found no memory.'
           hex 00
           dw $FFFF
ctl_when   dw $628+4
           asc 'when you leave the desk'
           hex 00
           dw $6A8+4
           asc 'accessories. Press a key.'
           hex 00
           dw $FFFF
ctl_wquit  dw $5A8+4
           asc 'XT/GS quits'
           hex 00
           dw $FFFF
ctl_wsave  dw $5A8+4
           asc 'The PC is saved'
           hex 00
           dw $FFFF
ctl_wrest  dw $5A8+4
           asc 'The PC goes back to its saved state'
           hex 00
           dw $FFFF
ctl_wsoft  dw $5A8+4
           asc 'The PC restarts'
           hex 00
           dw $FFFF
ctl_whard  dw $5A8+4
           asc 'The PC restarts, its memory cleared,'
           hex 00
           dw $FFFF
ctl_keys   dw CTL_SOFT,CTL_HARD,CTL_SAVE,CTL_REST,CTL_QUIT,CTL_BOOT
ctl_what   dw ctl_wsoft-ctl_row,ctl_whard-ctl_row,ctl_wquit-ctl_row
           dw ctl_wsave-ctl_row,ctl_wrest-ctl_row,ctl_wboot-ctl_row
ctl_wboot  dw $5A8+4
           asc 'The PC is written to disk, to start'
           hex 00
           dw $5D0+4
           asc 'from (STATE=ON in XTGS.CMD),'
           hex 00
           dw $FFFF
ctl_boot   dw $4A8+4
           asc '6  Save to start from'
           hex 00
           dw $FFFF
ctl_bs     dw ctl_bs1-ctl_row,ctl_bs2-ctl_row,ctl_bs3-ctl_row,ctl_bs4-ctl_row,ctl_bs5-ctl_row
           dw ctl_bs6-ctl_row,ctl_bs7-ctl_row
ctl_bs1    dw $528+4
           asc 'The start state is on the disk.'
           hex 00
           dw $FFFF
ctl_bs2    dw $528+4
           asc 'Not saved: a file or a port is open.'
           hex 00
           dw $FFFF
ctl_bs3    dw $528+4
           asc 'Not saved: no memory.'
           hex 00
           dw $FFFF
ctl_bs4    dw $528+4
           asc 'Not saved: the disk refused it.'
           hex 00
           dw $FFFF
ctl_bs6    dw $528+4
           asc 'Not saved: its boot files changed.'
           hex 00
           dw $FFFF
ctl_bs7    dw $528+4
           asc 'Not saved: too many files opened.'
           hex 00
           dw $FFFF
ctl_bs5    dw $528+4
           asc 'Not saved: only a PC from a folder.'
           hex 00
           dw $FFFF
ctl_pend   dw $528+4
           asc 'Start state: written as you leave.'
           hex 00
           dw $FFFF
ctl_none   dw $680+4
           asc 'No PC is running.'
           hex 00
           dw $FFFF

* svc_cda - the accessory's start routine (the Desk Manager's JSL).
svc_cda
 php
 clc
 xce
 php                       ; (the carry: the mode it came in)
 rep #$30
 mx %00
 phb
 phk
 plb
 jsr ctl_menu
 plb
 plp
 xce
 plp
 rtl

ctl_menu
 mx %00
 jsr ctl_clear
 ldy #ctl_head-ctl_row
 jsr ctl_say
 lda >CTL_LIVE
 bne :live
 ldy #ctl_none-ctl_row
 jsr ctl_say
:wait
 jsr ctl_key
 cmp #$1B
 bne :wait
 rts
:live
 ldy #ctl_items-ctl_row
 jsr ctl_say
 ldy #ctl_qp8-ctl_row      ; the front end by its page: the GS/OS application's
 lda >MB_BASE              ; begins "XTGS" (a constant of two characters has the first one low:
 cmp #'XT'                 ; 'TX' here said "Quit to ProDOS" under GS/OS too)
 bne :p8
 ldy #ctl_qgs-ctl_row
:p8
 jsr ctl_say
 ldy #ctl_boot-ctl_row
 jsr ctl_say
 lda >CTL_REQ              ; a start state waits to be written (as the desk accessories are left):
 tax                       ; that, in place of what came of the last one
 and #$007F
 cmp #CTL_BOOT
 beq :pend
 txa
 and #$0080
 beq :last
:pend
 ldy #ctl_pend-ctl_row
 jsr ctl_say
 bra :nobs
:last
 lda >BS_STAT              ; the last save to the disk: what came of it
 beq :nobs
 cmp #8
 bcs :nobs
 dec
 asl
 tax
 ldy ctl_bs,x
 jsr ctl_say
:nobs
 lda >CTL_STAT
 cmp #1
 beq :have
 ldy #ctl_nost-ctl_row
 jsr ctl_say
 lda >CTL_STAT
 cmp #2
 bne :have
 ldy #ctl_nomem-ctl_row
 jsr ctl_say
:have
:key
 jsr ctl_key
 cmp #$1B
 bne :digit
 rts
:digit
 sec
 sbc #'1'
 cmp #6
 bcs :key
 asl
 tax
 lda ctl_keys,x            ; the menu's digit to its request
 cmp #CTL_REST             ; nothing to restore: not a choice
 bne :pick
 tax
 lda >CTL_STAT
 cmp #1
 bne :key
 txa
:pick
 sta ctl_pick
 cmp #CTL_BOOT             ; a start state that cannot be written now (a program has a file open,
 bne :ask                  ; the boot's files were changed): said here and now, on the menu, and
 jsr bs_can                ; not left to be found out when the PC is next started (state.s)
 beq :ask
 sta >BS_STAT
 jmp ctl_menu
:ask
 jsr ctl_clear
 ldy #ctl_head-ctl_row
 jsr ctl_say
 lda ctl_pick
 dec
 asl
 tax
 ldy ctl_what,x
 jsr ctl_say
 ldy #ctl_when-ctl_row
 jsr ctl_say
 jsr ctl_key
 cmp #$1B                  ; Esc here: not after all
 beq :out
 lda ctl_pick
 cmp #CTL_REST
 bcs :set
 lda >CTL_REQ              ; a restart, the quit or a save, and a start state waits to be written: it is
 tax                       ; not let go of. Bit 7 has ctl_poll write it first (CTL_REQ holds one request)
 and #$007F
 cmp #CTL_BOOT
 beq :first
 txa
 and #$0080
 beq :plain
:first
 lda ctl_pick
 ora #$0080
 bra :set
:plain
 lda ctl_pick
:set
 sta >CTL_REQ
 cmp #CTL_BOOT             ; the start state is not written yet: the menu again, which says so, and
 bne :out                  ; whatever is chosen next (the quit) comes after it
 jmp ctl_menu
:out
 rts

* ctl_clear - the 24 lines to spaces
ctl_clear
 mx %00
 ldy #0
:row
 lda ctl_row,y
 tax
 phy
 ldy #20
 lda #$A0A0
:c
 sta >TXT40,x
 inx
 inx
 dey
 bne :c
 ply
 iny
 iny
 cpy #48
 bcc :row
 rts

* ctl_say - the list of lines at ctl_row + Y
ctl_say
 mx %00
:line
 lda ctl_row,y
 cmp #$FFFF
 beq :done
 tax
 iny
 iny
 sep #$20
 mx %10
:ch
 lda ctl_row,y
 beq :eol
 ora #$80
 sta >TXT40,x
 inx
 iny
 bra :ch
:eol
 rep #$20
 mx %00
 iny
 bra :line
:done
 rts

* ctl_key - wait for a key: A = its ASCII
ctl_key
 mx %00
 sep #$20
 mx %10
:w
 lda >$E0C000
 bpl :w
 sta >$E0C010
 rep #$20
 mx %00
 and #$007F
 rts

* ctl_poll - from svc_vbl: the accessory's request, when a PC is
* running. A reboot or the quit: C set and A = the exit code, and
* the core stops. Save and restore are done here and now, where the
* core is between two instructions, and it goes on.
ctl_poll
 mx %00
 lda >CTL_REQ
 beq :no
 tax
 lda #0
 sta >CTL_REQ
 lda >CTL_LIVE
 beq :no
 txa
 and #$0080
 beq :one
 txa                       ; a start state was asked for before this request: written first
 and #$007F
 pha
 jsr bs_save
 plx
:one
 cpx #CTL_SAVE
 bcc :stop
 bne :rest
 jsr st_save
 bra :no
:rest
 cpx #CTL_REST
 bne :boot
 jsr st_restore
 bra :no
:boot
 jsr bs_save
:no
 clc
 rts
:stop
 cpx #CTL_HARD             ; as after the power switch: a boot, whatever state there is to start from
 bne :exit
 lda #BS_SKIPV
 sta >BS_SKIP
:exit
 txa
 clc
 adc #CTL_EXIT
 sec
 rts

*----------------------------------------------------------
* The saved state: everything the PC is, kept in memory of
* the Memory Manager's for as long as this run lasts
* (st_drop, at svc_sndclose, gives it back; a reboot is the
* end of it too).
*
* What is kept (st_rg): the direct page (the CPU), the
* results bank (the devices), the SHR screen with its line
* controls and palettes, the PC's megabyte, as much of the
* XMS region as has blocks in it, and CORE's and SVC's own
* banks, where their variables are. A page at a time (256
* bytes): a page that is one byte 256 times is a word in the
* map (st_maph: $01vv), any other a word of 0 there and its
* 256 bytes in the data (st_dath). Two passes to save: the
* first makes the map and counts the pages the data will
* hold, so that the block can be asked for.
*
* The walk (st_walk) is one routine for the first pass, the
* copy out and the copy back, and it must stay so: on the
* way back it runs in SVC as SVC's own pages come back, and
* reads its pointers from the direct page as that comes
* back. The bytes that arrive are the ones that were there
* when the copy out went past the same place, so nothing
* changes under it, but only because both copies keep the
* same things in the same variables at every step. What
* differs (the pass) is on the stack, which is not saved:
* save and restore are both called from svc_vbl at the
* slot, so the stack is the same shape both times.
*
* After the copy back the hardware is brought into line:
* the DOC's registers written again from DOC_REG, the tick
* count set to the time of day, files the PC has opened
* since closed (a file it has closed since stays closed: its
* handle is dropped).
*----------------------------------------------------------
ST_NRG     = 7
st_maph    adrl 0            ; the map's handle
st_dath    adrl 0            ; the data's
st_map     adrl 0            ; and the blocks themselves
st_dat     adrl 0
st_rg      ds ST_NRG*6       ; a region: bank, offset, pages
st_reg     dw 0
st_left    dw 0
st_raw     dw 0              ; pages the data holds (as the walk counts them)
st_pages   dw 0              ; and when it has (state.s writes them to a file)
st_v       dw 0
st_j       dw 0
st_sz      adrl 0
st_h       adrl 0
ST_OLD     = BOUNCEBUF       ; restore: the handle table and the pathnames as they
                             ; were before it (the transfer buffer is not the PC's)
ST_OLDLEN  = NHANDLES*72
 err hpath-htab-NHANDLES-NHANDLES-NHANDLES-NHANDLES-NHANDLES-NHANDLES-NHANDLES-NHANDLES

* st_drop - no state: the blocks given back
st_drop
 mx %00
 lda >CTL_STAT
 cmp #1
 bne :none
 lda st_dath+2
 ldx st_dath
 jsr st_free
 lda st_maph+2
 ldx st_maph
 jsr st_free
:none
 lda #0
 sta >CTL_STAT
 rts

* st_free - DisposeHandle(A:X)
st_free
 mx %00
 phd
 phb
 pha
 phx
 ldx #$1002                ; DisposeHandle
 jsl TOOLS
 rep #$30
 mx %00
 plb
 pld
 rts

* st_new - a block of st_sz bytes: its handle in st_h and the block's
* address in A (low) and X (high), or C set
st_new
 mx %00
 phd
 phb
 pha                       ; the result
 pha
 lda st_sz+2
 pha
 lda st_sz
 pha
 lda >MB_MASTER
 pha
 pea $C008                 ; locked, fixed, not in the special memory
 pea $0000
 pea $0000
 ldx #$0902                ; NewHandle
 jsl TOOLS
 rep #$30
 mx %00
 pla
 plx
 plb
 pld
 bcs :no
 sta st_h
 stx st_h+2
 sta pGST
 stx pGST+2
 ldy #2
 lda [pGST],y
 tax
 lda [pGST]
 clc
:no
 rts

st_save
 mx %00
 jsr st_drop               ; (the one before goes first: its room may be needed)
 jsr st_regs
 jmp st_save2
* st_regs - st_rg: what a state is made of, for the PC as it is now
* (state.s asks too, for a state from a file)
st_regs
 mx %00
 ldx #0                    ; the regions
:rz
 stz st_rg,x
 inx
 inx
 cpx #ST_NRG*6
 bcc :rz
 lda #GUEST_DP             ; the direct page: bank 0 (the 0 is there)
 sta st_rg+2
 lda #1
 sta st_rg+4
 lda #^RES_BASE
 sta st_rg+6
 lda #256
 sta st_rg+10
 lda #^SHR_PIX
 sta st_rg+12
 lda #SHR_PIX
 sta st_rg+14
 lda #128
 sta st_rg+16
 lda #^GUEST_BASE
 sta st_rg+18
 lda #4096
 sta st_rg+22
 lda #^DISK_BASE           ; the XMS region as far as its last block reaches
 sta st_rg+24
 lda xms_on
 beq :noxms
 stz st_v
 ldx #0
:xh
 lda xh_used,x
 beq :xn
 lda xh_start,x
 clc
 adc xh_size,x
 cmp st_v
 bcc :xn
 sta st_v
:xn
 inx
 inx
 cpx #XMS_NH*2
 bcc :xh
 lda st_v
 asl
 asl
 sta st_rg+28
:noxms
 lda #^CORE_BASE
 sta st_rg+30
 lda #256
 sta st_rg+34
 lda #^SVC_BASE
 sta st_rg+36
 lda #256
 sta st_rg+40
 rts
st_save2
 mx %00
 lda st_rg+4               ; the map: a word a page
 clc
 adc st_rg+10
 clc
 adc st_rg+16
 clc
 adc st_rg+22
 clc
 adc st_rg+28
 clc
 adc st_rg+34
 clc
 adc st_rg+40
 asl
 sta st_sz
 lda #0
 rol
 sta st_sz+2
 jsr st_new
 bcs :nomem
 sta st_map
 stx st_map+2
 lda st_h
 sta st_maph
 lda st_h+2
 sta st_maph+2
 lda #1                    ; (said before the first pass looks at the pages
 sta >CTL_STAT             ; that say it)
 lda #0
 jsr st_walk               ; the map, and st_raw
 lda st_raw
 sta st_pages
 bne :some
 inc
:some
 xba
 pha
 and #$FF00
 sta st_sz
 pla
 and #$00FF
 sta st_sz+2
 jsr st_new
 bcs :nodata
 sta st_dat
 stx st_dat+2
 lda st_h
 sta st_dath
 lda st_h+2
 sta st_dath+2
 lda #1
 jmp st_walk               ; the pages (rts)
:nodata
 lda st_maph+2
 ldx st_maph
 jsr st_free
:nomem
 lda #2
 sta >CTL_STAT
 rts

st_restore
 mx %00
 lda >CTL_STAT
 cmp #1
 beq :go
 rts
:go
 ldx #0                    ; the files open now: the handles and their names
:keep
 lda htab,x
 sta >ST_OLD,x
 inx
 inx
 cpx #ST_OLDLEN
 bcc :keep
 lda #2
 jsr st_walk
 ldx #0                    ; (SVC's variables are the saved ones from here)
:f                         ; a file open then: still the same file by its
 lda htab,x                ; reference and its name? Else it was closed
 and #$00FF                ; since, and the handle is no file now
 cmp #H_FILE
 bne :fn
 jsr st_same
 bcc :fn
 lda htab+2,x
 and #$00FF
 tay
 sep #$20
 mx %10
 lda #0
 sta iobuf_used,y
 rep #$20
 mx %00
 stz htab,x
:fn
 txa
 clc
 adc #8
 tax
 cpx #NHANDLES*8
 bcc :f
 ldx #0                    ; a file open before that no handle has now: closed
:c
 lda >ST_OLD,x
 and #$00FF
 cmp #H_FILE
 bne :cn
 lda >ST_OLD,x
 xba
 and #$00FF
 sta >MB_MLI_PARMS+1
 lda #1
 sta >MB_MLI_PARMS
 phx
 lda #$CC                  ; CLOSE
 jsr mli
 plx
:cn
 txa
 clc
 adc #8
 tax
 cpx #NHANDLES*8
 bcc :c
 jsr st_docs
 jsr clk_init              ; the tick count: the time it is now
 lda >MB_LAYOUT+RG_JIT+RG_JIT
 beq :nojit                ; the translator's code is of the PC that was: all of it away
 lda >JIT_CFG              ; (and its epoch, which is in the direct page, starts again)
 beq :nojit
 jsl JIT_BASE
:nojit
 lda >FPU_ON               ; the 8087's image: what it knew of SANE begins again
 beq :nofpu
 lda >MB_LAYOUT+RG_DATA+RG_DATA
 beq :nofpu
 jsl FPU_BASE+6
:nofpu
 lda #1
 sta >EGA_SYNC             ; (the core's copies of the EGA's registers)
 lda #0
 sta >CTL_REQ
 rts
* st_docs - the DOC as the saved PC left it: each oscillator's
* registers written again from DOC_REG, its control last
st_docs
 mx %00
 php
 sei
 sep #$20
 mx %10
 ldx #0
:osc
 lda >DOC_REG,x            ; frequency low, high
 jsr doc_w
 lda >DOC_REG+$20,x
 jsr st_dw20
 lda >DOC_REG+$40,x        ; volume
 jsr st_dw40
 lda >DOC_REG+$80,x        ; the table's page, and its size
 jsr st_dw80
 lda >DOC_REG+$C0,x
 jsr st_dwC0
 lda >DOC_REG+$A0,x        ; control
 jsr st_dwA0
 inx
 txa
 cmp >DOC_NOSC
 bcc :osc
 rep #$20
 mx %00
 plp
 rts

* st_dwNN - DOC register X + NN = A (8-bit A; keeps X)
st_dw20
 mx %10
 phx
 pha
 rep #$20
 mx %00
 txa
 clc
 adc #$0020
 bra st_dwgo
st_dw40
 mx %10
 phx
 pha
 rep #$20
 mx %00
 txa
 clc
 adc #$0040
 bra st_dwgo
st_dw80
 mx %10
 phx
 pha
 rep #$20
 mx %00
 txa
 clc
 adc #$0080
 bra st_dwgo
st_dwC0
 mx %10
 phx
 pha
 rep #$20
 mx %00
 txa
 clc
 adc #$00C0
 bra st_dwgo
st_dwA0
 mx %10
 phx
 pha
 rep #$20
 mx %00
 txa
 clc
 adc #$00A0
st_dwgo
 mx %00
 tax
 sep #$20
 mx %10
 pla
 jsr doc_w
 plx
 rts

* st_same - the handle entry X (a file) against the table kept in
* ST_OLD: C clear when an entry there is a file with the same
* reference and the same pathname, and that entry is marked taken
* ($FF). Keeps X.
st_same
 mx %00
 stx st_j
 ldy #0
:e
 tyx
 lda >ST_OLD,x
 and #$00FF
 cmp #H_FILE
 bne :next
 lda >ST_OLD,x
 ldx st_j
 cmp htab,x                ; the kind and the reference
 bne :next
 phy                       ; the names: entry * 8 (64 bytes each)
 tya
 asl
 asl
 asl
 sta st_v                  ; the old one's, from the kept pathnames
 txa
 asl
 asl
 asl
 tay                       ; the handle's
 lda #32
 sta st_left
:cmp
 ldx st_v
 lda >NHANDLES*8+ST_OLD,x
 cmp hpath,y
 bne :differ
 inc st_v
 inc st_v
 iny
 iny
 dec st_left
 bne :cmp
 ply
 tyx
 lda #$00FF                ; taken
 sta >ST_OLD,x
 ldx st_j
 clc
 rts
:differ
 ply
:next
 tya
 clc
 adc #8
 tay
 cpy #NHANDLES*8
 bcc :e
 ldx st_j
 sec
 rts

* st_walk - every page of every region: A = 0 the map made (uniform
* or not) and st_raw counted, 1 the pages that are not uniform copied
* to the data, 2 all of them put back. pGST the page, pARG its place
* in the data, pDTA its word of the map. See the note above before
* changing anything here.
st_walk
 mx %00
 pha                       ; the pass: 1,s
 stz st_reg
 stz st_raw
 lda st_map
 sta pDTA
 lda st_map+2
 sta pDTA+2
 lda st_dat
 sta pARG
 lda st_dat+2
 sta pARG+2
:region
 ldx st_reg
 lda st_rg,x
 sta pGST+2
 lda st_rg+2,x
 sta pGST
 lda st_rg+4,x
 sta st_left
 bne :page
 jmp :nextreg
:page
 lda 1,s
 beq :scan
 cmp #1
 beq :save
 lda [pDTA]                ; back: a uniform page filled, any other copied
 and #$FF00
 beq :rraw
 lda [pDTA]
 and #$00FF
 sta st_v
 xba
 ora st_v
 ldy #254
:fill
 sta [pGST],y
 dey
 dey
 bpl :fill
 bra :adv
:rraw
 ldy #254
:rc
 lda [pARG],y
 sta [pGST],y
 dey
 dey
 bpl :rc
 inc pARG+1                ; (a page on: the word at +1 is the page and the bank)
 bra :adv
:save
 lda [pDTA]
 and #$FF00
 bne :adv
 ldy #254
:sc
 lda [pGST],y
 sta [pARG],y
 dey
 dey
 bpl :sc
 inc pARG+1
 bra :adv
:scan
 lda [pGST]
 sta st_v
 xba
 cmp st_v
 bne :raw
 ldy #254
:t
 lda [pGST],y
 cmp st_v
 bne :raw
 dey
 dey
 bne :t
 lda st_v
 and #$00FF
 ora #$0100
 sta [pDTA]
 bra :adv
:raw
 lda #0
 sta [pDTA]
 inc st_raw
:adv
 lda pDTA
 clc
 adc #2
 sta pDTA
 bcc :m1
 inc pDTA+2
:m1
 inc pGST+1
 dec st_left
 beq :nextreg
 jmp :page
:nextreg
 lda st_reg
 clc
 adc #6
 sta st_reg
 cmp #ST_NRG*6
 bcs :end
 jmp :region
:end
 pla
 rts
