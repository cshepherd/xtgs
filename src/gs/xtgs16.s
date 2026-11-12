*----------------------------------------------------------
* XTGS - the GS/OS front end (S16): what XTGS.SYSTEM is to
* ProDOS 8, as a native application (docs/relocation.md,
* stage 3). It owns nothing but what the Memory Manager
* gives it:
*
*   - one block of bank $00 for the areas CORE and SVC use
*     there (ZP, MBX, PATH, XFER; IOB is the MLI's and stays
*     unclaimed), wherever there is room;
*   - the SHR screen, and each region's banks as the ProDOS 8
*     loader claims them (the assembled bank when it is free,
*     else the first that is).
*
* It then reads XTGS.CMD, loads CORE and SVC and the
* command's file from its own folder (prefix 1), fixes
* their bank and page bytes from MB_LAYOUT, runs the core
* on the stack GS/OS gave it, and quits to GS/OS.
*
* The front page is built in the block: "XTGS" at +0 (the
* harness finds the page by it), the file-call entry at
* MB_FILECALL -- a JML to filecall below, which carries out
* the ProDOS 8 MLI call in the mailbox with GS/OS calls --
* and the mailbox, which this file addresses through the
* direct page (D = the front page from set_low to quit).
*
* Native mode, 16-bit M/X throughout; data is in this
* segment (DBR = K). A relocatable segment: Merlin32 writes
* the OMF load file.
*----------------------------------------------------------
 rel
 typ $B3
 dsk xtgs16
 mx %00
 put ../include/layout.s
 put ../include/hw.s
 put ../include/mailbox.s

* The mailbox through the direct page
mb_sig      = 0
mb_filecall = MB_FILECALL-MB_BASE
mb_stage    = MB_STAGE-MB_BASE
mb_magic    = MB_MAGIC-MB_BASE
mb_exit     = MB_EXIT-MB_BASE
mb_err      = MB_ERR-MB_BASE
mb_osboot   = MB_OSBOOT-MB_BASE
mb_master   = MB_MASTER-MB_BASE
mb_mmid     = MB_MMID-MB_BASE
mb_downerr  = MB_DOWNERR-MB_BASE
mb_done     = MB_DONE-MB_BASE
mb_filelen  = MB_FILELEN-MB_BASE
mb_sp       = MB_SP-MB_BASE
mb_cmd      = MB_CMD-MB_BASE
mb_dbg_owner = MB_DBG_OWNER-MB_BASE
mb_dbg_addr = MB_DBG_ADDR-MB_BASE
mb_dbg_size = MB_DBG_SIZE-MB_BASE
mb_mli_cmd  = MB_MLI_CMD-MB_BASE
mb_mli_res  = MB_MLI_RES-MB_BASE
mb_mli_parms = MB_MLI_PARMS-MB_BASE
mb_layout   = MB_LAYOUT-MB_BASE
mb_layalt   = MB_LAYALT-MB_BASE
* ... and this file's scratch after it
ptr         = $A0             ; a long pointer
ptr2        = $A4             ; another
t0          = $A8
t1          = $AA
t2          = $AC
t3          = $AE
 err MB_END-MB_BASE-1/$A0     ; the mailbox ends below the scratch

LOW_PAGES   = 35              ; the bank-$00 block: ZP, MBX, PATH, XFER (32)
ATTR_LOW    = $C005           ; locked, fixed, page-aligned, in the bank given

start
 mx %00
 phk
 plb
 rep #$30
 sta user_id
 ora #$0100                ; an ID of our own kind for DisposeAll
 sta aux_id
 tdc
 sta entry_d
 tsc
 sta entry_s
 sep #$20
 mx %10
 lda >NEWVIDEO             ; SVC switches to SHR; put these back at the end
 sta sv_video
 lda >BORDER
 sta sv_border
 rep #$20
 mx %00
 ldx #$0201                ; TLStartUp
 jsl TOOLS
 pha
 ldx #$0202                ; MMStartUp
 jsl TOOLS
 pla
 sta mm_id
 jsr text_up
 lda #msg_hello
 jsr puts
 lda #^start               ; the bank of every pathname given to GS/OS
 sta op_path+2
 sta rd_buf+2

 jsr read_cmd              ; (before the mailbox: '+' decides where it goes)
 jsr set_low
 bcc :low_ok
 lda #msg_nolow
 jsr puts
 lda fail_err
 jsr prword
 jsr crout
 jmp wait_quit
:low_ok

 lda #3
 sta mb_stage
 jsr claim_all
 bcc :claimed
 jmp fail
:claimed
 jsr show_banks

 lda #4
 sta mb_stage
 lda #path_core
 sta ld_path
 stz ld_dst
 lda mb_layout+RG_CORE+RG_CORE
 sta ld_dst+2
 stz ld_alloc
 lda #1
 sta ld_max
 ldx #$10
 jsr load_file
 lda mb_filelen            ; (the relocation list is at its end)
 sta img_len
 lda #5
 sta mb_stage
 lda #path_svc
 sta ld_path
 stz ld_dst
 lda mb_layout+RG_SVC+RG_SVC
 sta ld_dst+2
 ldx #$20
 jsr load_file
 lda mb_filelen
 sta img_len+2

 lda mb_cmd+1
 and #$00FF
 cmp #'V'
 bne :nodata
 lda #6
 sta mb_stage
 lda #path_vec
 sta ld_path
 lda #1                    ; alloc_data claims the banks and sets ld_dst
 sta ld_alloc
 lda #$00FF
 sta ld_max
 ldx #$30
 jsr load_file
 jmp :loaded
:nodata
 cmp #'C'
 bne :nocom
 jsr com_name              ; NAME from the command line into path_com
 bcc :havecom
 jmp :loaded               ; none given: the core will complain
:havecom
 lda #7
 sta mb_stage
 lda #path_com
 sta ld_path
 lda #COM_BASE
 sta ld_dst
 lda mb_layout+RG_GUEST+RG_GUEST
 clc
 adc #COM_BASE-GUEST_BASE/$10000
 sta ld_dst+2
 stz ld_alloc
 lda #9                    ; a program fits below A000:0000 (576 KB)
 sta ld_max
 ldx #$50
 jsr load_file
 bra :loaded
:nocom
 cmp #'D'
 bne :nodisk
 lda #7                    ; D: the raw disk image into its banks
 sta mb_stage
 lda #path_disk
 sta ld_path
 stz ld_dst
 lda mb_layout+RG_DISK+RG_DISK
 sta ld_dst+2
 stz ld_alloc
 lda #DISK_BANKS
 sta ld_max
 ldx #$30
 jsr load_file
 bra :loaded
:nodisk
 cmp #'B'
 beq :loadbench
 cmp #'K'                  ; K: JIT runs the same bench at 0000:0100
 bne :loaded
:loadbench
 lda #7                    ; load the bench program into guest 0000:0100
 sta mb_stage
 lda #path_bench
 sta ld_path
 lda #BENCH_BASE
 sta ld_dst
 lda mb_layout+RG_GUEST+RG_GUEST
 sta ld_dst+2
 stz ld_alloc
 lda #1
 sta ld_max
 ldx #$40
 jsr load_file
:loaded

 lda #$0B
 sta mb_stage
 jsr reloc_all
 bcc :reloc_ok
 stz fail_err
 jmp fail
:reloc_ok

 lda #msg_run
 jsr puts
 lda #8
 sta mb_stage
 sep #$20
 mx %10
 lda mb_layout+RG_CORE+RG_CORE
 sta :core+3               ; the JSL's bank
 rep #$20
 mx %00
 tsc
 sta mb_sp
:core
 jsl CORE_BASE
 rep #$30                  ; whatever the core left
 phk
 plb
 tax
 lda mbx_dp
 tcd
 stx mb_exit
 lda mb_sp
 tcs
 lda #9
 sta mb_stage
 jsr release
 lda #$A5A5
 sta mb_done
 lda #msg_exit             ; (on the text screen, under the guest's last
 jsr puts                  ; picture: wait_quit shows it after the key)
 lda mb_exit
 jsr prword
 jsr crout
 lda #10
 sta mb_stage
 lda #$5A5A
 sta mb_magic
 jmp wait_quit

*----------------------------------------------------------
* fail - X = stage, fail_err = the tool or GS/OS error.
* Record both, say so, give everything back and quit after
* a key. Jumped to from anywhere once the mailbox exists.
*----------------------------------------------------------
fail
 mx %00
 rep #$30
 phk
 plb
 lda mbx_dp
 tcd
 lda entry_s
 tcs
 stx mb_stage
 lda fail_err
 sta mb_err
 jsr video_back
 lda #msg_fail
 jsr puts
 lda mb_stage
 jsr prbyte
 lda #' '
 jsr putc
 lda fail_err
 jsr prword
 jsr crout
 jsr release
 lda #$5A5A                ; the judge reads MB_STAGE for the why
 sta mb_magic
wait_quit
 mx %00
 lda #msg_key
 jsr puts
 sep #$20
 mx %10
:wait
 lda >KBD
 bpl :wait
 sta >KBDSTRB
 rep #$20
 mx %00
 jsr video_back
 lda mbx_dp                ; the front page goes back with the block: no
 beq :nopage               ; signature may outlive it (a relaunch may get
 tcd                       ; another page, and the harness looks for it)
 stz mb_sig
 stz mb_sig+2
:nopage
 lda entry_d
 tcd
 lda entry_s
 tcs
 lda aux_id
 pha
 ldx #$1102                ; DisposeAll: the bank-$00 block and whatever is left
 jsl TOOLS
 lda user_id
 pha
 ldx #$0302                ; MMShutDown
 jsl TOOLS
 ldx #$0301                ; TLShutDown
 jsl TOOLS
 jsl GSOS
 dw $2029                  ; QuitGS
 adrl quit_blk
 brk $00

*----------------------------------------------------------
* Text: the 80-column firmware through the Text Tools.
*----------------------------------------------------------
text_up
 mx %00
 pea $0000                 ; a BASIC device
 pea $0000                 ; in slot 3
 pea $0003
 ldx #$100C                ; SetOutputDevice
 jsl TOOLS
 pea $00FF                 ; AND mask
 pea $0080                 ; OR mask: the firmware wants the high bit
 ldx #$0A0C                ; SetOutGlobals
 jsl TOOLS
 pea $0001                 ; the output device
 ldx #$150C                ; InitTextDev
 jsl TOOLS
 rts

* puts - A = a C string in this segment
puts
 mx %00
 tax
 lda #^puts
 pha
 phx
 ldx #$200C                ; WriteCString
 jsl TOOLS
 rts

* prword / prbyte - A in hex; putc - the character in A; crout
prword
 mx %00
 pha
 xba
 jsr prbyte
 pla
prbyte
 mx %00
 pha
 lsr
 lsr
 lsr
 lsr
 jsr :nib
 pla
:nib
 and #$000F
 cmp #10
 bcc :dig
 adc #6                    ; (carry set: 7)
:dig
 adc #'0'
putc
 mx %00
 pha
 ldx #$180C                ; WriteChar
 jsl TOOLS
 rts
crout
 mx %00
 lda #$0D
 bra putc

* video_back - the display as it was at entry
video_back
 mx %00
 sep #$20
 mx %10
 lda sv_video
 sta >NEWVIDEO
 lda sv_border
 sta >BORDER
 rep #$20
 mx %00
 rts

*----------------------------------------------------------
* set_low - the bank-$00 block: its pages to the areas in
* RG_ order, then the front page (D from here on). For the
* '+' test layout no area may be on its assembled page, so
* a block that puts one there is kept and another asked for.
* D = the direct page GS/OS gave us on entry; carry set and
* fail_err when there is no room.
*----------------------------------------------------------
set_low
 mx %00
 lda #8
 sta sl_tries
:again
 lda #LOW_PAGES*$100
 sta nh_size
 stz nh_size+2
 stz nh_addr
 stz nh_addr+2
 lda aux_id
 sta nh_id
 lda #ATTR_LOW
 sta nh_attr
 jsr new_handle
 bcc :have
 rts
:have
 lda nh_result
 sta 0
 lda nh_result+2
 sta 2
 lda [0]                   ; the block's address: $pp00
 xba
 and #$00FF
 sta low_page
 lda layalt
 beq :take
 dec sl_tries
 beq :take
 lda low_page
 cmp #ZP_PAGE
 beq :again
 inc
 cmp #MBX_PAGE
 beq :again
 inc
 cmp #PATH_PAGE
 beq :again
 inc
 cmp #XFER_PAGE
 beq :again
:take
 lda low_page
 inc
 xba
 sta mbx_dp
 tcd
 ldx #$00FE
:clear
 stz 0,x
 dex
 dex
 bpl :clear
 lda #$5458                ; "XTGS"
 sta mb_sig
 lda #$5347
 sta mb_sig+2
 lda #filecall             ; JML filecall
 sta mb_filecall+1
 sep #$20
 mx %10
 lda #$5C
 sta mb_filecall
 phk
 pla
 sta mb_filecall+3
 lda >OS_BOOT
 sta mb_osboot
 rep #$20
 mx %00
 lda low_page
 sta mb_layout+RG_ZP+RG_ZP
 inc
 sta mb_layout+RG_MBX+RG_MBX
 inc
 sta mb_layout+RG_PATH+RG_PATH
 inc
 sta mb_layout+RG_XFER+RG_XFER
 lda user_id
 sta mb_master
 lda mm_id
 sta mb_mmid
 lda layalt
 sta mb_layalt
 ldx #30
:cmd
 lda cmd_p,x
 sta mb_cmd,x
 dex
 dex
 bpl :cmd
 lda #1
 sta mb_stage
 clc
 rts
 err RG_MBX-RG_ZP-1         ; the block's pages go out in this order
 err RG_PATH-RG_MBX-1
 err RG_XFER-RG_PATH-1

*----------------------------------------------------------
* claim_all - the SHR screen (written directly, so nobody
* else may have it) and the command's regions. Carry set
* with X = the stage ($46 the screen, $47 + RG_ a region)
* and the block in the way in the mailbox (who_owns).
*----------------------------------------------------------
claim_all
 mx %00
 lda #SHR_PIX
 sta nh_addr
 lda #^SHR_PIX
 sta nh_addr+2
 lda #$8000
 sta nh_size
 stz nh_size+2
 lda aux_id
 sta nh_id
 lda #ATTR_FIXED
 sta nh_attr
 jsr new_handle
 bcc :shr_ok
 jsr who_owns
 ldx #$46
 sec
 rts
:shr_ok
 lda nh_result
 sta shr_h
 lda nh_result+2
 sta shr_h+2
 ldx #RG_GUEST+RG_GUEST
 jsr claim_region
 bcs :rg_err
 lda mb_cmd+1
 and #$00FF
 cmp #'D'
 bne :nodisk
 ldx #RG_DISK+RG_DISK
 jsr claim_region
 bcs :rg_err
:nodisk
 ldx #RG_CORE+RG_CORE
 jsr claim_region
 bcs :rg_err
 ldx #RG_SVC+RG_SVC
 jsr claim_region
 bcs :rg_err
 ldx #RG_RES+RG_RES
 jsr claim_region
 bcs :rg_err
 lda mb_cmd+1
 and #$00FF
 cmp #'K'
 bne :nojit
 ldx #RG_JIT+RG_JIT
 jsr claim_region
 bcs :rg_err
:nojit
 lda mb_cmd+1              ; S has no disk image: its banks are the guest's
 and #$00FF                ; XMS memory (src/svc/xms.s) when they can be had,
 cmp #'S'                  ; last, so that nothing above goes without for it
 bne :noxms
 ldx #RG_DISK+RG_DISK
 jsr claim_region
:noxms
 clc
 rts
:rg_err
 jsr who_owns              ; what holds the first choice (nh_addr)
 lda cr_x                  ; stage $47 + region
 lsr
 clc
 adc #$47
 tax
 sec
 rts

*----------------------------------------------------------
* claim_region - X = region * 2: as the ProDOS 8 loader's
* (src/sys/xtgs.s). Its rg_banks whole banks at the bank
* the images were assembled for when that is free and this
* is not the '+' layout, else at the first bank from
* SCAN_LO up that the Memory Manager will give (a multiple
* of rg_align + 1). The bank goes to mb_layout, the handle
* to rg_h. Carry set when there is no room: fail_err = the
* last tool error, nh_addr = the assembled address.
*----------------------------------------------------------
SCAN_LO  = $02
SCAN_HI  = $E0             ; one past the last expansion RAM bank
claim_region
 mx %00
 stx cr_x
 lda rg_banks,x
 sta nh_size+2
 stz nh_size
 stz nh_addr
 lda aux_id
 sta nh_id
 lda #ATTR_FIXED
 sta nh_attr
 lda mb_layalt
 bne :scan
 lda rg_asm,x
 jsr :try
 bcc :got
:scan
 lda #SCAN_LO
 sta cr_bank
:next
 ldx cr_x
 lda cr_bank
 and rg_align,x
 bne :skip
 lda cr_bank
 cmp rg_asm,x              ; tried already, or the test forbids it
 beq :skip
 clc
 adc rg_banks,x
 cmp #SCAN_HI+1            ; the rest would not fit below SCAN_HI
 bcs :fail
 lda cr_bank
 jsr :try
 bcc :got
:skip
 inc cr_bank
 lda cr_bank
 cmp #SCAN_HI
 bcc :next
:fail
 ldx cr_x
 lda rg_asm,x
 sta nh_addr+2
 sec
 rts
:got
 lda cr_x
 tax
 asl
 tay
 lda nh_addr+2
 sta mb_layout,x
 tyx
 lda nh_result             ; kept for release
 sta rg_h,x
 lda nh_result+2
 sta rg_h+2,x
 clc
 rts
:try
 sta nh_addr+2
* new_handle - NewHandle(nh_size, nh_id, nh_attr, nh_addr).
* Carry set on error, fail_err = the code.
new_handle
 mx %00
 pha                       ; result space (handle)
 pha
 lda nh_size+2
 pha
 lda nh_size
 pha
 lda nh_id
 pha
 lda nh_attr
 pha
 lda nh_addr+2
 pha
 lda nh_addr
 pha
 ldx #$0902                ; NewHandle
 jsl TOOLS
 sta fail_err
 pla
 sta nh_result
 pla
 sta nh_result+2
 lda fail_err
 cmp #1                    ; carry set iff error
 rts

* who_owns - diagnostics for a failed fixed-address NewHandle:
* FindHandle(nh_addr), and the block's owner ID, address and
* size into the mailbox (handle record: +0 address, +6 owner
* ID, +8 size).
who_owns
 mx %00
 pha
 pha
 lda nh_addr+2
 pha
 lda nh_addr
 pha
 ldx #$1A02                ; FindHandle
 jsl TOOLS
 pla
 sta ptr
 pla
 sta ptr+2
 ora ptr
 beq :none
 ldy #6
 lda [ptr],y
 sta mb_dbg_owner
 lda [ptr]
 sta mb_dbg_addr
 ldy #2
 lda [ptr],y
 sta mb_dbg_addr+2
 ldy #8
 lda [ptr],y
 sta mb_dbg_size
 ldy #10
 lda [ptr],y
 sta mb_dbg_size+2
 rts
:none
 lda #$FFFF
 sta mb_dbg_owner
 rts

*----------------------------------------------------------
* release - give back the screen, the guest's open files and
* the regions (stage 9).
* The first error goes to MB_DOWNERR. The bank-$00 block,
* and with it the mailbox, stays until quit (DisposeAll).
*----------------------------------------------------------
release
 mx %00
 stz down_err
 lda shr_h
 ora shr_h+2
 beq :regions
 lda shr_h+2
 pha
 lda shr_h
 pha
 ldx #$1002                ; DisposeHandle
 jsl TOOLS
 jsr :note
 stz shr_h
 stz shr_h+2
:regions
 ldx #0                    ; a file the guest left open would stay
:files                     ; open in GS/OS after we quit
 lda sl_ref,x
 beq :nofile
 phx
 sta cl_ref
 stz sl_ref,x
 jsl GSOS
 dw $0014                  ; CLOSE
 adrl cl_blk
 plx
:nofile
 inx
 inx
 cpx #SLOTS*2
 bcc :files
 ldx #0
:loop
 lda rg_h,x
 ora rg_h+2,x
 beq :next
 phx
 lda rg_h+2,x
 pha
 lda rg_h,x
 pha
 ldx #$1002                ; DisposeHandle (a region)
 jsl TOOLS
 jsr :note
 plx
 stz rg_h,x
 stz rg_h+2,x
:next
 inx
 inx
 inx
 inx
 cpx #RG_BANKS*4
 bcc :loop
 lda down_err
 sta mb_downerr
 rts
:note
 bcc :ok
 ldx down_err
 bne :ok
 sta down_err
:ok
 rts

* show_banks - the bank of each region and the page of each
* bank-$00 area, in RG_ order (00 = not claimed)
show_banks
 mx %00
 lda #msg_banks
 jsr puts
 ldx #0
 lda #RG_BANKS*2
 jsr :row
 lda #msg_pages
 jsr puts
 ldx #RG_BANKS*2
 lda #RG_COUNT*2
:row
 sta sb_end
:loop
 phx
 lda #' '
 jsr putc
 plx
 phx
 lda mb_layout,x
 jsr prbyte
 plx
 inx
 inx
 cpx sb_end
 bcc :loop
 jmp crout

*----------------------------------------------------------
* read_cmd - XTGS.CMD's first line into cmd_p as a Pascal
* string ("P" when the file is missing); a leading '+' is
* taken off and noted in layalt. set_low copies both to the
* mailbox once there is one.
*----------------------------------------------------------
read_cmd
 mx %00
 lda #path_cmd
 sta op_path
 jsl GSOS
 dw $0010                  ; OPEN
 adrl op_blk
 bcs :none
 lda op_ref
 sta rd_ref
 sta cl_ref
 lda #cmdbuf
 sta rd_buf
 lda #31
 sta rd_req
 stz rd_req+2
 stz rd_xfer
 jsl GSOS
 dw $0012                  ; READ (a short read is fine)
 adrl rd_blk
 bcs :close
 sep #$20
 mx %10
 ldx #0
:scan
 cpx rd_xfer
 bcs :len
 lda cmdbuf,x
 cmp #$0D
 beq :len
 cmp #$0A
 beq :len
 inx
 bra :scan
:len
 txa
 sta cmd_p
 beq :close
:copy
 lda cmdbuf-1,x
 sta cmd_p,x
 dex
 bne :copy
:close
 rep #$20
 mx %00
 jsl GSOS
 dw $0014                  ; CLOSE
 adrl cl_blk
:none
 sep #$20
 mx %10
 lda cmd_p+1               ; '+': the layout test; the command follows
 cmp #'+'
 bne :plain
 lda #1
 sta layalt
 ldx #0
:shift
 lda cmd_p+2,x
 sta cmd_p+1,x
 inx
 cpx #30
 bcc :shift
 dec cmd_p
 bne :plain
 lda #1                    ; nothing after it: the default
 sta cmd_p
 lda #'P'
 sta cmd_p+1
:plain
 rep #$20
 mx %00
 rts

*----------------------------------------------------------
* com_name - "C NAME args": NAME (up to 15 characters) after
* the "1/" of path_com. Carry set when there is none.
*----------------------------------------------------------
com_name
 mx %00
 lda mb_cmd
 and #$00FF
 sta t0                    ; the command's length
 sep #$20
 mx %10
 ldx #2
:skip
 cpx t0
 bcs :none
 lda mb_cmd+1,x
 cmp #' '
 bne :copy
 inx
 bra :skip
:copy
 ldy #0
:c
 cpx t0
 bcs :done
 lda mb_cmd+1,x
 cmp #' '
 beq :done
 sta path_com+3,y
 inx
 iny
 cpy #15
 bcc :c
:done
 tya
 clc
 adc #2
 sta path_com
 rep #$20
 mx %00
 clc
 rts
 mx %10
:none
 rep #$20
 mx %00
 sec
 rts

*----------------------------------------------------------
* load_file - the file ld_path (a Pascal pathname in this
* segment) to ld_dst, in one READ. ld_alloc non-zero: claim
* the data region for it first (alloc_data sets ld_dst).
* ld_max = the banks it may fill. X = the stage's error
* base: + 1 OPEN, 2 GET_EOF, 3 no memory, 4 READ, 5 a short
* read, $F too long; fail_err = the GS/OS error.
*----------------------------------------------------------
load_file
 mx %00
 stx ld_stage
 lda ld_path
 sta op_path
 jsl GSOS
 dw $0010                  ; OPEN
 adrl op_blk
 bcc :opened
 ldx #1
 jmp :fail
:opened
 lda op_ref
 sta eof_ref
 sta rd_ref
 sta cl_ref
 jsl GSOS
 dw $0019                  ; GET_EOF
 adrl eof_blk
 bcc :eof_ok
 ldx #2
 jmp :close_fail
:eof_ok
 lda eof_val
 sta mb_filelen
 sta rd_req
 lda eof_val+2
 sta mb_filelen+2
 sta rd_req+2
 cmp ld_max
 bcc :fits
 lda #0
 ldx #$0F
 jmp :close_fail
:fits
 lda ld_alloc
 beq :noalloc
 jsr alloc_data
 bcc :noalloc
 lda fail_err
 ldx #3
 jmp :close_fail
:noalloc
 lda rd_req
 ora rd_req+2
 beq :done                 ; (GS/OS will not read nothing)
 lda ld_dst
 sta rd_buf
 lda rd_buf+2
 pha                       ; (this segment's bank, for read_cmd)
 lda ld_dst+2
 sta rd_buf+2
 jsl GSOS
 dw $0012                  ; READ
 adrl rd_blk
 plx
 stx rd_buf+2
 bcc :read_ok
 ldx #4
 jmp :close_fail
:read_ok
 lda rd_xfer
 cmp rd_req
 bne :short
 lda rd_xfer+2
 cmp rd_req+2
 beq :done
:short
 lda #0
 ldx #5
 jmp :close_fail
:done
 jsl GSOS
 dw $0014                  ; CLOSE
 adrl cl_blk
 lda #'.'
 jmp putc
:close_fail
 pha
 phx
 jsl GSOS
 dw $0014                  ; CLOSE
 adrl cl_blk
 plx
 pla
:fail
 sta fail_err
 txa
 clc
 adc ld_stage
 tax
 jmp fail

* alloc_data - claim whole banks for the file of mb_filelen
* bytes (an empty one still gets a bank) and point ld_dst at
* them. Carry set with fail_err when there is no room.
alloc_data
 mx %00
 lda mb_filelen+2
 ldx mb_filelen
 beq :exact
 inc
:exact
 cmp #0
 bne :some
 inc
:some
 sta rg_banks+RG_DATA+RG_DATA
 ldx #RG_DATA+RG_DATA
 jsr claim_region
 bcs :err
 stz ld_dst
 lda mb_layout+RG_DATA+RG_DATA
 sta ld_dst+2
 clc
 rts
:err
 jsr who_owns
 sec
 rts

*----------------------------------------------------------
* reloc_all - fix the bank and page bytes of CORE and SVC,
* once every region has its bank. Carry set on a bad list
* with X = the stage ($71 CORE, $72 SVC).
*----------------------------------------------------------
reloc_all
 mx %00
 stz ptr
 lda mb_layout+RG_CORE+RG_CORE
 sta ptr+2
 lda img_len
 jsr reloc_image
 ldx #$71
 bcs :out
 lda mb_layout+RG_SVC+RG_SVC
 sta ptr+2                 ; (ptr is still 0)
 lda img_len+2
 jsr reloc_image
 ldx #$72
:out
 rts

*----------------------------------------------------------
* reloc_image - [ptr] = an image in memory, A = its file's
* length: the list tools/gen_reloc.py appended to it, as in
* the ProDOS 8 loader (src/sys/xtgs.s has the format). Each
* listed byte gets (mb_layout's bank or page now - the
* assembled one); a region nobody claimed is left alone.
* Carry set when the list is not there or makes no sense.
*----------------------------------------------------------
reloc_image
 mx %00
 sec
 sbc #4
 bcc :bad
 sta rl_end                ; offset of the two closing words
 tay
 iny
 iny
 lda [ptr],y
 cmp #RELOC_MAGIC
 bne :bad
 ldy rl_end
 lda rl_end
 sec
 sbc [ptr],y
 bcc :bad
 tay                       ; the first group
:group
 cpy rl_end
 beq :done
 bcs :bad
 lda [ptr],y               ; RG_ index (low), assembled bank or page (high)
 iny
 iny
 sta rl_delta
 and #$00FF
 cmp #RG_COUNT
 bcs :bad
 asl
 tax
 lda mb_layout,x
 beq :unclaimed
 sec
 sbc rl_delta+1            ; now - assembled: the low byte counts
:unclaimed
 sta rl_add
 lda [ptr],y
 iny
 iny
 sta rl_count
:fix
 lda rl_count
 beq :group
 dec rl_count
 lda [ptr],y
 iny
 iny
 phy
 tay
 sep #$20
 mx %10
 lda [ptr],y
 clc
 adc rl_add
 sta [ptr],y
 rep #$20
 mx %00
 ply
 bra :fix
:done
 clc
 rts
:bad
 sec
 rts

*----------------------------------------------------------
* filecall - MB_FILECALL's far end: native entry (JSL), any
* M/X, any D and DBR. Carries out the ProDOS 8 MLI command
* MB_MLI_CMD with the parameter list at MB_MLI_PARMS (whose
* pointers are bank-$00 addresses) by GS/OS calls, class 0
* where there is one: their error codes are the MLI's.
* Preserves D, DBR and P; A = the error (0 = ok), also in
* MB_MLI_RES.
*
* File references are slot numbers 1..SLOTS, not GS/OS's. A
* directory is read as ProDOS 8 reads one, in 512-byte
* blocks of 13 entries: straight from GS/OS when it will
* (the ProDOS FST does), otherwise -- any other file
* system, and always in the '+' test layout so that this
* runs somewhere -- built from GetDirEntry (dir_read).
*----------------------------------------------------------
p        = mb_mli_parms    ; the MLI parameter list, in the direct page
SLOTS    = 16
PBUF     = 80              ; a pathname buffer
filecall
 mx %00
 phb
 phd
 php
 rep #$30
 phk
 plb
 lda mbx_dp
 tcd
 lda mb_mli_cmd
 and #$00FF
 sec
 sbc #$00C0
 cmp #fc_end-fc_tab/2
 bcs :bad
 asl
 tax
 jsr (fc_tab,x)
 rep #$30
 bra :out
:bad
 lda #$0001                ; bad system call number
:out
 cmp #$0100                ; a GS/OS error the MLI has no code for:
 bcc :low
 lda #$0027                ; I/O error
:low
 sta mb_mli_res
 plp
 lda mb_mli_res
 pld
 plb
 rtl
fc_tab   da fc_create,fc_destroy,fc_rename,fc_setinfo
         da fc_getinfo,fc_bad,fc_setprefix,fc_getprefix
         da fc_open,fc_bad,fc_read,fc_write
         da fc_close,fc_ok,fc_setmark,fc_getmark
         da fc_seteof,fc_geteof
fc_end

fc_bad
 mx %00
 lda #$0001
 rts
fc_ok
 mx %00
 lda #0
 rts

* fc_setpath - A = a ProDOS 8 pathname's address (bank $00),
* X = 0 or PBUF: copy it to fc_path+X for GS/OS. A partial
* pathname gets "1/" (our folder) in front; a trailing
* slash goes ("/VOL/DIR/" is how the prefix is spelled).
fc_setpath
 mx %00
 sta ptr
 stz ptr+2
 stx t0
 lda [ptr]
 and #$00FF
 sta t1                    ; its length
 sep #$20
 mx %10
 ldy #1
 lda t1
 beq :done
 lda [ptr],y
 and #$7F
 cmp #'/'
 beq :copy
 lda #'1'
 sta fc_path+1,x
 lda #'/'
 sta fc_path+2,x
 inx
 inx
:copy
 lda [ptr],y
 and #$7F
 sta fc_path+1,x
 inx
 cpy t1
 iny
 bcc :copy
:done
 rep #$20
 mx %00
 txa
 sec
 sbc t0                    ; the length now; fc_path,x is the last character
 sep #$20
 mx %10
 cmp #2
 bcc :set
 pha
 lda fc_path,x
 cmp #'/'
 bne :keep
 pla
 dec
 bra :set
:keep
 pla
:set
 ldx t0
 sta fc_path,x
 rep #$20
 mx %00
 rts

* fc_path0 - the pathname at p+1 into fc_path and fc_blk+0
fc_path0
 mx %00
 lda p+1
 ldx #0
 jsr fc_setpath
 lda #fc_path
 sta fc_blk
 lda #^fc_path
 sta fc_blk+2
 rts

fc_create
 mx %00
 jsr fc_path0
 lda p+3
 and #$00FF
 sta fc_blk+4              ; access
 lda p+4
 and #$00FF
 sta fc_blk+6              ; file type
 lda p+5
 sta fc_blk+8              ; aux type
 stz fc_blk+10
 lda p+7
 and #$00FF
 sta fc_blk+12             ; storage type
 lda p+8
 sta fc_blk+14             ; creation date and time
 lda p+10
 sta fc_blk+16
 jsl GSOS
 dw $0001                  ; CREATE
 adrl fc_blk
 rts

fc_destroy
 mx %00
 jsr fc_path0
 jsl GSOS
 dw $0002                  ; DESTROY
 adrl fc_blk
 rts

fc_rename
 mx %00
 jsr fc_path0
 lda p+3
 ldx #PBUF
 jsr fc_setpath
 lda #fc_path+PBUF
 sta fc_blk+4
 lda #^fc_path
 sta fc_blk+6
 jsl GSOS
 dw $0004                  ; CHANGE_PATH
 adrl fc_blk
 rts

* GET_FILE_INFO's list: pathname, access +4, file type +6,
* aux type +8, storage type +12, creation date +14 and time
* +16, modification date +18 and time +20, blocks +22.
* SET_FILE_INFO's is the same with nothing at +12.
fc_getinfo
 mx %00
 jsr fc_path0
 jsl GSOS
 dw $0006                  ; GET_FILE_INFO
 adrl fc_blk
 bcs :out
 sep #$20
 mx %10
 lda fc_blk+4
 sta p+3
 lda fc_blk+6
 sta p+4
 lda fc_blk+12
 sta p+7
 rep #$20
 mx %00
 lda fc_blk+8
 sta p+5
 lda fc_blk+22
 sta p+8
 lda fc_blk+18
 sta p+10
 lda fc_blk+20
 sta p+12
 lda fc_blk+14
 sta p+14
 lda fc_blk+16
 sta p+16
 lda #0
:out
 rts

fc_setinfo                 ; (the MLI's leaves the creation date alone)
 mx %00
 jsr fc_path0
 jsl GSOS
 dw $0006                  ; GET_FILE_INFO
 adrl fc_blk
 bcs :out
 lda p+3
 and #$00FF
 sta fc_blk+4
 lda p+4
 and #$00FF
 sta fc_blk+6
 lda p+5
 sta fc_blk+8
 stz fc_blk+10
 stz fc_blk+12
 lda p+10
 sta fc_blk+18
 lda p+12
 sta fc_blk+20
 jsl GSOS
 dw $0005                  ; SET_FILE_INFO
 adrl fc_blk
:out
 rts

* SET_PREFIX: prefix 1, the one a partial pathname is read
* against here (fc_setpath) -- the shared drive's directory
* (redir.s). GS/OS sets it again for the next program.
fc_setprefix
 mx %00
 lda p+1
 ldx #0
 jsr fc_setpath
 lda #1
 sta fc_blk
 lda #fc_path
 sta fc_blk+2
 lda #^fc_path
 sta fc_blk+4
 jsl GSOS
 dw $0009                  ; SET_PREFIX
 adrl fc_blk
 rts

* GET_PREFIX: prefix 1, spelled the MLI's way ("/VOL/DIR/")
fc_getprefix
 mx %00
 lda #1
 sta fc_blk
 lda #fc_path
 sta fc_blk+2
 lda #^fc_path
 sta fc_blk+4
 jsl GSOS
 dw $000A                  ; GET_PREFIX
 adrl fc_blk
 bcc :have
 rts
:have
 lda p+1
 sta ptr
 stz ptr+2
 lda fc_path
 and #$00FF
 sta t1
 sep #$20
 mx %10
 ldy #1
 ldx #1
 lda t1
 beq :len
 lda fc_path+1
 cmp #':'
 beq :loop
 cmp #'/'
 beq :loop
 lda #'/'
 sta [ptr],y
 iny
:loop
 lda fc_path,x
 cmp #':'
 bne :store
 lda #'/'
:store
 sta [ptr],y
 sta t2
 iny
 cpx t1
 inx
 bcc :loop
 lda t2
 cmp #'/'
 beq :len
 lda #'/'
 sta [ptr],y
 iny
:len
 dey
 tya
 sta [ptr]
 rep #$20
 mx %00
 lda #0
 rts

fc_open
 mx %00
 jsr fc_path0
 ldx #0
:find
 lda sl_ref,x
 beq :free
 inx
 inx
 cpx #SLOTS*2
 bcc :find
 lda #$0042                ; too many files open
 rts
:free
 stx t3
 jsl GSOS
 dw $0006                  ; GET_FILE_INFO: a directory?
 adrl fc_blk
 bcs :out
 ldy #0
 lda fc_blk+6
 cmp #$000F
 bne :kind
 iny                       ; 1: read its blocks
 lda mb_layalt
 beq :kind
 iny                       ; 2: build them
:kind
 ldx t3
 tya
 sta sl_dir,x
 stz sl_mark,x
 lda #fc_path
 sta op_path
 jsl GSOS
 dw $0010                  ; OPEN
 adrl op_blk
 bcs :out
 ldx t3
 lda op_ref
 sta sl_ref,x
 txa
 lsr
 inc
 sep #$20
 mx %10
 sta p+5
 rep #$20
 mx %00
 lda #0
:out
 rts

* fc_ref - the reference at p+1: X = its slot * 2 (also in
* t3), A = GS/OS's reference (also in fc_blk). Carry set
* with A = $43 when it is not an open file's.
fc_ref
 mx %00
 lda p+1
 and #$00FF
 beq :bad
 cmp #SLOTS+1
 bcs :bad
 dec
 asl
 tax
 stx t3
 lda sl_ref,x
 beq :bad
 sta fc_blk
 clc
 rts
:bad
 lda #$0043
 sec
 rts

* fc_rw - buffer p+2 and count p+4 into fc_blk for READ and
* WRITE: reference, buffer +2, count +6, transferred +10
fc_rw
 mx %00
 lda p+2
 sta fc_blk+2
 stz fc_blk+4
 lda p+4
 sta fc_blk+6
 stz fc_blk+8
 stz fc_blk+10
 stz fc_blk+12
 rts

fc_read
 mx %00
 jsr fc_ref
 bcs :out
 lda sl_dir,x
 beq :file
 jmp dir_read
:file
 jsr fc_rw
 jsl GSOS
 dw $0012                  ; READ
 adrl fc_blk
 tax
 lda fc_blk+10
 sta p+6
 cpx #$004C                ; end of file counts only when nothing came
 bne :err
 cmp #0
 beq :err
 ldx #0
:err
 txa
:out
 rts

fc_write
 mx %00
 jsr fc_ref
 bcs :out
 jsr fc_rw
 jsl GSOS
 dw $0013                  ; WRITE
 adrl fc_blk
 tax
 lda fc_blk+10
 sta p+6
 txa
:out
 rts

fc_close
 mx %00
 lda p+1
 and #$00FF
 bne :one
 ldx #0                    ; reference 0: every file
:all
 phx
 lda sl_ref,x
 beq :next
 sta fc_blk
 stz sl_ref,x
 jsl GSOS
 dw $0014                  ; CLOSE
 adrl fc_blk
:next
 plx
 inx
 inx
 cpx #SLOTS*2
 bcc :all
 lda #0
 rts
:one
 jsr fc_ref
 bcs :out
 stz sl_ref,x
 jsl GSOS
 dw $0014                  ; CLOSE
 adrl fc_blk
:out
 rts

fc_setmark
 mx %00
 jsr fc_ref
 bcs :out
 lda sl_dir,x
 beq :file
 lda p+3                   ; a directory: note the block (mark / 512)
 lsr
 sta sl_mark,x
 lda #0
 rts
:file
 jsr fc_pos
 jsl GSOS
 dw $0016                  ; SET_MARK
 adrl fc_blk
:out
 rts

fc_seteof
 mx %00
 jsr fc_ref
 bcs :out
 jsr fc_pos
 jsl GSOS
 dw $0018                  ; SET_EOF
 adrl fc_blk
:out
 rts

* fc_pos - the 3-byte position at p+2 into fc_blk+2
fc_pos
 mx %00
 lda p+2
 sta fc_blk+2
 lda p+4
 and #$00FF
 sta fc_blk+4
 rts

fc_getmark
 mx %00
 jsr fc_ref
 bcs fc_posout
 jsl GSOS
 dw $0017                  ; GET_MARK
 adrl fc_blk
 bra fc_posback
fc_geteof
 mx %00
 jsr fc_ref
 bcs fc_posout
 jsl GSOS
 dw $0019                  ; GET_EOF
 adrl fc_blk
fc_posback                 ; fc_blk+2 back to the 3 bytes at p+2
 mx %00
 bcs fc_posout
 lda fc_blk+2
 sta p+2
 sep #$20
 mx %10
 lda fc_blk+4
 sta p+4
 rep #$20
 mx %00
 lda #0
fc_posout
 mx %00
 rts

*----------------------------------------------------------
* dir_read - READ on a directory (from fc_read: t3 = the
* slot * 2, fc_blk = the reference): the 512-byte block
* sl_mark names into the buffer at p+2, and on to the next.
*
* Kind 1 asks GS/OS for the bytes. When it refuses (not the
* ProDOS FST), and for kind 2, the block is built: entry n
* of the directory (GetDirEntry, absolute, n from 1) goes
* where ProDOS keeps its n-th entry -- slot n mod 13 of
* block n / 13, entry 0 being the header, left empty -- with
* the fields files.s reads and the rest of a ProDOS entry
* where GS/OS has them. A name over 15 characters has no
* ProDOS spelling and its slot stays empty. Past the last
* entry: end of file. (GetDirEntry counts live entries, so
* deleting one while reading on renumbers those after it;
* ProDOS's own blocks do not move.)
*----------------------------------------------------------
dir_read
 mx %00
 ldx t3
 lda sl_dir,x
 cmp #2
 beq :build
 lda sl_mark,x             ; mark = block * 512
 xba
 and #$FF00
 asl
 sta fc_blk+2
 lda #0
 rol
 sta fc_blk+4
 jsl GSOS
 dw $0016                  ; SET_MARK
 adrl fc_blk
 bcs :refused
 jsr fc_rw
 jsl GSOS
 dw $0012                  ; READ
 adrl fc_blk
 bcs :refused
 lda fc_blk+10
 sta p+6
 ldx t3
 inc sl_mark,x
 lda #0
 rts
:refused
 cmp #$004C
 beq :eof
 cmp #$004D                ; position out of range
 beq :eof
 ldx t3
 lda #2                    ; this directory is built from here on
 sta sl_dir,x
:build
 lda p+2
 sta ptr
 stz ptr+2
 ldy #510
 lda #0
:zero
 sta [ptr],y
 dey
 dey
 bpl :zero
 ldx t3
 lda sl_mark,x
 sta t0
 asl
 asl
 sta t1
 asl
 clc
 adc t1
 adc t0
 sta t0                    ; the block's first entry number: block * 13
 stz t1                    ; the slot, 0..12
 lda #4
 sta t2                    ; and its offset in the block
 lda #1
 sta de_first
:entry
 lda t0
 beq :next                 ; the header's slot
 sta de_disp
 stz de_base
 lda fc_blk
 sta de_ref
 jsl GSOS
 dw $201C                  ; GetDirEntry
 adrl de_blk
 bcc :have
 cmp #$0061                ; end of directory
 beq :end
 cmp #$004F                ; the name does not fit: no ProDOS spelling
 beq :skip
 rts
:end
 lda de_first
 beq :full
:eof
 stz p+6
 lda #$004C
 rts
:have
 lda de_name+2
 beq :skip
 cmp #16
 bcs :skip
 jsr dir_entry
:skip
 stz de_first
:next
 inc t0
 lda t2
 clc
 adc #39
 sta t2
 inc t1
 lda t1
 cmp #13
 bcc :entry
:full
 lda #512
 sta p+6
 ldx t3
 inc sl_mark,x
 lda #0
 rts

* dir_entry - de_blk as a ProDOS directory entry at [ptr]+t2
dir_entry
 mx %00
 ldy t2
 sep #$20
 mx %10
 lda #$10                  ; storage type: a file...
 ldx de_type
 cpx #$000F
 bne :kind
 lda #$D0                  ; ...or a directory
:kind
 ora de_name+2
 sta [ptr],y
 ldx #0
:name
 iny
 lda de_name+4,x
 cmp #'a'
 bcc :put
 cmp #'z'+1
 bcs :put
 and #$DF
:put
 sta [ptr],y
 inx
 cpx de_name+2
 bcc :name
 rep #$20
 mx %00
 lda de_type               ; (ascending: a word's high byte is the next field's)
 and #$00FF
 ldx #$10
 jsr :word
 lda de_blocks
 ldx #$13
 jsr :word
 lda de_eof
 ldx #$15
 jsr :word
 lda de_eof+2
 and #$00FF
 ldx #$17
 jsr :word
 ldx #de_create-de_blk
 jsr dir_time
 lda dt_date
 ldx #$18
 jsr :word
 lda dt_time
 ldx #$1A
 jsr :word
 lda de_access
 and #$00FF
 ldx #$1E
 jsr :word
 lda de_aux
 ldx #$1F
 jsr :word
 ldx #de_mod-de_blk
 jsr dir_time
 lda dt_date
 ldx #$21
 jsr :word
 lda dt_time
 ldx #$23
:word                      ; A to offset X of the entry
 pha
 txa
 clc
 adc t2
 tay
 pla
 sta [ptr],y
 rts

* dir_time - the TimeRec at de_blk+X (second, minute, hour,
* year - 1900, day - 1, month - 1) as ProDOS's date and time
dir_time
 mx %00
 stz dt_date
 stz dt_time
 lda de_blk+3,x            ; year, day
 bne :set
 lda de_blk+5,x            ; month
 and #$00FF
 bne :set
 rts                       ; no date
:set
 lda de_blk+3,x
 and #$00FF
:century
 cmp #100
 bcc :year
 sbc #100
 bra :century
:year
 xba
 asl
 sta dt_date               ; year << 9
 lda de_blk+5,x
 and #$00FF
 inc
 asl
 asl
 asl
 asl
 asl
 ora dt_date
 sta dt_date               ; month << 5
 lda de_blk+4,x
 and #$00FF
 inc
 ora dt_date
 sta dt_date               ; day
 lda de_blk+1,x            ; minute, hour
 sta dt_time
 rts

*----------------------------------------------------------
* Data
*----------------------------------------------------------
msg_hello  asc 'XT/GS (GS/OS)',0D,00
msg_run    asc 0D,'RUNNING CORE',0D,00
msg_exit   asc 'CORE EXIT $',00
msg_fail   asc 'LOADER ERROR ',00
msg_nolow  asc 'NO ROOM IN BANK 0: $',00
msg_key    asc 'PRESS A KEY TO QUIT.',00
msg_banks  asc 'BANKS',00
msg_pages  asc 'PAGES',00

* The regions, in RG_ order: the bank each was assembled
* for, its size in banks (the data region's is set from the
* file), and the mask its first bank must be clear of.
rg_asm     dw CORE_BANK,SVC_BANK,RES_BANK,JIT_BANK,GUEST_BANK,DATA_BANK,DISK_BANK
rg_banks   dw 1,1,1,1,16,0,DISK_BANKS
rg_align   dw 0,0,0,0,$000F,0,0
 err rg_banks-rg_asm-RG_BANKS-RG_BANKS
 err rg_align-rg_banks-RG_BANKS-RG_BANKS
 err *-rg_align-RG_BANKS-RG_BANKS
 err GUEST_BANK&$0F         ; the 20-bit wrap needs a 1 MiB-aligned guest

* Pathnames: prefix 1 is the folder this program was launched from
path_core  dfb 6
           asc '1/CORE'
path_svc   dfb 5
           asc '1/SVC'
path_vec   dfb 5
           asc '1/VEC'
path_bench dfb 7
           asc '1/BENCH'
path_disk  dfb 6
           asc '1/DISK'
path_cmd   dfb 10
           asc '1/XTGS.CMD'
path_com   dfb 0
           asc '1/'
           ds 16

* GS/OS parameter lists
op_blk                     ; OPEN
op_ref     dw 0
op_path    adrl 0
           adrl 0
rd_blk                     ; READ
rd_ref     dw 0
rd_buf     adrl 0
rd_req     adrl 0
rd_xfer    adrl 0
eof_blk                    ; GET_EOF
eof_ref    dw 0
eof_val    adrl 0
cl_blk                     ; CLOSE
cl_ref     dw 0
quit_blk   dw 2            ; QuitGS: no pathname, no flags
           adrl 0
           dw 0
fc_blk     ds 32           ; filecall's
de_blk     dw 13           ; GetDirEntry
de_ref     dw 0
de_flags   dw 0
de_base    dw 0            ; 0: de_disp is the entry's number
de_disp    dw 0
           adrl de_name
de_num     dw 0
de_type    dw 0
de_eof     adrl 0
de_blocks  adrl 0
de_create  ds 8
de_mod     ds 8
de_access  dw 0
de_aux     adrl 0
de_name    dw 36           ; a result buffer: its size, the length, the text
           ds 34
de_first   dw 0
dt_date    dw 0
dt_time    dw 0

user_id    dw 0
aux_id     dw 0
mm_id      dw 0
entry_d    dw 0
entry_s    dw 0
mbx_dp     dw 0
low_page   dw 0
sl_tries   dw 0
layalt     dw 0
sv_video   dw 0
sv_border  dw 0
fail_err   dw 0
down_err   dw 0
nh_size    adrl 0
nh_addr    adrl 0
nh_id      dw 0
nh_attr    dw 0
nh_result  adrl 0
shr_h      adrl 0
rg_h       ds RG_BANKS*4      ; a handle a region
sb_end     dw 0
cr_x       dw 0
cr_bank    dw 0
img_len    dw 0,0             ; CORE's and SVC's file lengths
rl_end     dw 0
rl_delta   dw 0
rl_add     dw 0
rl_count   dw 0
ld_path    dw 0
ld_dst     adrl 0
ld_alloc   dw 0
ld_max     dw 0
ld_stage   dw 0
sl_ref     ds SLOTS*2         ; GS/OS's reference, 0 = free
sl_dir     ds SLOTS*2         ; 0 a file, 1 a directory read, 2 one built
sl_mark    ds SLOTS*2         ; a directory's next block
cmd_p      dfb 1,'P'
           ds 32
cmdbuf     ds 32
fc_path    ds PBUF*2
