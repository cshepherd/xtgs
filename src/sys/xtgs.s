*----------------------------------------------------------
* XTGS.SYSTEM - ProDOS 8 loader for the XT/GS 8088 emulator.
*
* ProDOS 8 loads this SYS file at $2000 and enters it in
* emulation mode. It stays resident for the life of the
* program and owns bank $00 below $BF00. Shape and the
* memory-ownership dance are taken from the Monkey Island
* IIGS loader (../somi-iigs-port/iigs/asm/loader.s).
*
*   1. Check for an Apple IIGS; set the prefix to the boot
*      volume if ProDOS left it empty.
*   2. Start the Tool Locator and Misc Tools and take
*      ownership of memory (ProDOS 8 TN #27, IIGS TN #17):
*      on a direct ProDOS 8 boot (OS_BOOT = 0) get a master
*      user ID from GetNewID($1000) and reserve the ranges
*      GS/OS would have given ProDOS 8; then claim, with
*      fixed-address handles, the banks XT/GS lives in:
*      $03 (CORE), $04 (SVC), $05 (results) and the guest's
*      1 MiB at $20:0000; then call MMStartUp, which must
*      return the master ID.
*   3. Read XTGS.CMD (optional) into the mailbox: the first
*      line is the command for the core (P probe, V vectors,
*      B bench, C NAME args: the .COM program). Default: P.
*   4. Read CORE into $03:0000 and SVC into $04:0000 through
*      the bank-$00 bounce buffer; for a V command, read VEC
*      into banks from $30 up (claimed first, by its size).
*   5. JSL to the core entry in native mode, 16-bit M/X,
*      with S = $0BFF; the core RTLs with its exit code in A.
*   6. Release everything, set MB_DONE and MB_MAGIC, print
*      the exit code, wait for a key, MLI QUIT.
*
* Mailbox and entry points: src/include/mailbox.s. The
* results the host judge reads are final once MB_MAGIC is
* $5A5A; the loader then waits for a key before quitting so
* a headless run can dump memory at leisure.
*
*   $2004  mli_glue  JSL target for native code: MLI command
*                    MB_MLI_CMD with parameters MB_MLI_PARMS,
*                    result in MB_MLI_RES and A (0 = ok).
*
* Bank-$00 layout owned by the loader:
*   $0800-$0BFF  core native stack (S = $0BFF)
*   $0C00-$0FFF  ProDOS 8 I/O buffer
*   $1000-$10FF  guest CPU state direct page (the core's)
*   $2000-$3FFF  this loader (resident)
*   $4000-$5FFF  bounce buffer for file reads
*----------------------------------------------------------

 xc
 xc
 org $2000
 dsk xtgs
 typ $FF
 mx %11

 put ../include/hw.s
 put ../include/mailbox.s

IOBUF    = $0C00           ; ProDOS 8 I/O buffer (1 KB, page-aligned)
BOUNCE   = $4000           ; bank-$00 transfer buffer
CHUNK    = $2000           ; bytes per READ
CORE_S   = $0BFF           ; native stack top while the core runs
COM_BASE = $210100         ; the .COM program: guest PSP_SEG:0100

* Fixed entry points and mailbox: the ABI, do not reorder.
 jmp start                 ; $2000
 dfb 1                     ; $2003  interface version
 jmp mli_glue              ; $2004  JSL $002004 from native code
 ds $2010-*,0
mb_stage   dw 0            ; $2010
mb_magic   dw 0            ; $2012
mb_exit    dw 0            ; $2014
mb_err     dw 0            ; $2016
mb_osboot  dw 0            ; $2018
mb_master  dw 0            ; $201A
mb_mmid    dw 0            ; $201C
mb_downerr dw 0            ; $201E
mb_done    dw 0            ; $2020
mb_filelen adrl 0          ; $2022
mb_sp      dw 0            ; $2026
mb_perrs   dw 0            ; $2028
mb_pfirst  adrl 0          ; $202A
mb_runidx  dw 0            ; $202E
mb_cmd     ds 32,0         ; $2030
mb_dbg_owner dw 0          ; $2050
mb_dbg_addr adrl 0         ; $2052
mb_dbg_size adrl 0         ; $2056
mb_mli_cmd dw 0            ; $205A
mb_mli_res dw 0            ; $205C
mb_mli_parms ds 32,0       ; $205E
mb_icount  adrl 0          ; $207E
 err mb_stage-MB_STAGE
 err mb_magic-MB_MAGIC
 err mb_exit-MB_EXIT
 err mb_err-MB_ERR
 err mb_osboot-MB_OSBOOT
 err mb_master-MB_MASTER
 err mb_mmid-MB_MMID
 err mb_downerr-MB_DOWNERR
 err mb_done-MB_DONE
 err mb_filelen-MB_FILELEN
 err mb_sp-MB_SP
 err mb_perrs-MB_PROBE_ERRS
 err mb_pfirst-MB_PROBE_FIRST
 err mb_runidx-MB_RUNIDX
 err mb_cmd-MB_CMD
 err mb_dbg_owner-MB_DBG_OWNER
 err mb_dbg_addr-MB_DBG_ADDR
 err mb_dbg_size-MB_DBG_SIZE
 err mb_mli_cmd-MB_MLI_CMD
 err mb_mli_res-MB_MLI_RES
 err mb_mli_parms-MB_MLI_PARMS
 err mb_icount-MB_ICOUNT
 err *-MB_END

*----------------------------------------------------------
* start - emulation mode, 8-bit M/X throughout the main
* flow; native-mode work happens inside subroutines.
*----------------------------------------------------------
start
 mx %11
 cld
 jsr HOME
 sec
 jsr IDROUT
 bcc :isgs
 lda #<msg_notgs
 ldy #>msg_notgs
 jsr puts
 jmp wait_quit
:isgs
 lda #1
 sta mb_stage
 lda #<msg_hello
 ldy #>msg_hello
 jsr puts

* Prefix: ProDOS 8 may leave it empty after a cold boot.
 jsr MLI
 dfb $C7                   ; GET_PREFIX
 da gp_parms
 bcs :prefix_err
 lda pathbuf
 bne :have_prefix
 lda DEVNUM
 sta ol_unit
 jsr MLI
 dfb $C5                   ; ON_LINE
 da ol_parms
 bcs :prefix_err
 lda pathbuf+1             ; length nibble of the volume name
 and #$0F
 tax
 inx                       ; + leading slash
 stx pathbuf
 lda #'/'
 sta pathbuf+1
 jsr MLI
 dfb $C6                   ; SET_PREFIX
 da gp_parms
 bcc :have_prefix
:prefix_err
 ldx #2
 jmp fail8
:have_prefix

* Toolbox and memory ownership.
 lda #3
 sta mb_stage
 jsr tools_up
 bcc :tools_ok
 jmp fail8
:tools_ok
 jsr mm_startup
 bcc :mm_ok
 jmp fail8
:mm_ok

* The command, then the images.
 jsr read_cmd
 lda #4
 sta mb_stage
 lda #<path_core
 sta ld_path
 lda #>path_core
 sta ld_path+1
 lda #<CORE_BASE
 sta ld_dst
 lda #>CORE_BASE
 sta ld_dst+1
 lda #^CORE_BASE
 sta ld_dst+2
 stz ld_alloc
 ldx #$10
 jsr load_file
 lda #5
 sta mb_stage
 lda #<path_svc
 sta ld_path
 lda #>path_svc
 sta ld_path+1
 lda #<SVC_BASE
 sta ld_dst
 lda #>SVC_BASE
 sta ld_dst+1
 lda #^SVC_BASE
 sta ld_dst+2
 ldx #$20
 jsr load_file

* A data file, by the command letter.
 lda mb_cmd+1
 cmp #'V'
 bne :nodata
 lda #6
 sta mb_stage
 lda #<path_vec
 sta ld_path
 lda #>path_vec
 sta ld_path+1
 lda #<DATA_BASE
 sta ld_dst
 lda #>DATA_BASE
 sta ld_dst+1
 lda #^DATA_BASE
 sta ld_dst+2
 lda #1
 sta ld_alloc
 ldx #$30
 jsr load_file
 bra :loaded
:nodata
 lda mb_cmd+1
 cmp #'C'
 bne :nocom
 jsr com_name              ; NAME from the command line into path_com
 bcs :loaded               ; none given: the core will complain
 lda #7
 sta mb_stage
 lda #<path_com
 sta ld_path
 lda #>path_com
 sta ld_path+1
 lda #<COM_BASE
 sta ld_dst
 lda #>COM_BASE
 sta ld_dst+1
 lda #^COM_BASE
 sta ld_dst+2
 stz ld_alloc
 ldx #$50
 jsr load_file
 lda mb_filelen+2          ; a .COM is at most 65,024 bytes
 bne :toobig
 lda mb_filelen+1
 cmp #$FE
 bcc :loaded
:toobig
 ldx #$5F
 stz fail_err
 stz fail_err+1
 jmp fail8
:nocom
 lda mb_cmd+1
 cmp #'B'
 bne :loaded
 lda #7                    ; B: the bench program into guest 0000:0100
 sta mb_stage
 lda #<path_bench
 sta ld_path
 lda #>path_bench
 sta ld_path+1
 lda #<BENCH_BASE
 sta ld_dst
 lda #>BENCH_BASE
 sta ld_dst+1
 lda #^BENCH_BASE
 sta ld_dst+2
 stz ld_alloc
 ldx #$40
 jsr load_file
:loaded

* Run the core: native mode, 16-bit M/X, its own stack.
 lda #<msg_run
 ldy #>msg_run
 jsr puts
 lda #8
 sta mb_stage
 clc
 xce
 rep #$30
 mx %00
 tsc
 sta mb_sp
 lda #CORE_S
 tcs
 jsl CORE_BASE
 rep #$30                  ; whatever the core left
 pea $0000
 plb
 plb
 sta mb_exit
 lda #0
 tcd
 lda mb_sp
 tcs
 sec
 xce
 mx %11
 lda #9
 sta mb_stage
 jsr tools_down
 lda #$A5
 sta mb_done
 sta mb_done+1
 lda #<msg_exit
 ldy #>msg_exit
 jsr puts
 lda mb_exit+1
 jsr PRBYTE
 lda mb_exit
 jsr PRBYTE
 jsr CROUT
 lda #10
 sta mb_stage
 lda #$5A
 sta mb_magic
 sta mb_magic+1
 jmp wait_quit

*----------------------------------------------------------
* tools_up - TLStartUp, MTStartUp; the master user ID; the
* TN #27 reservations on a direct boot; then the fixed
* blocks XT/GS lives in. Emulation in/out. Carry set on
* error with X = stage and fail_err = tool error.
*----------------------------------------------------------
tools_up
 clc
 xce
 rep #$30
 mx %00
 ldx #$0201                ; TLStartUp
 jsl TOOLS
 ldx #$0203                ; MTStartUp
 jsl TOOLS
 sta fail_err
 bcc :mt_ok
 jmp :mt_err
:mt_ok
 lda #1
 sta tools_on
 lda >OS_BOOT
 and #$00FF
 sta mb_osboot
 bne :from_gsos

* Direct boot: we own the machine; make our own master ID.
 pha                       ; result
 pea $1000                 ; application ID type
 ldx #$2003                ; GetNewID
 jsl TOOLS
 sta fail_err
 pla
 bcc :id_ok
 jmp :id_err
:id_ok
 sta mb_master
 ldx #0                    ; every entry: TN #27 ranges first
 bra :reserve

* Launched from GS/OS: MMStartUp names our memory; TN #27
* says the low 128K is already ours. Only the fixed blocks.
:from_gsos
 pha
 ldx #$0202                ; MMStartUp
 jsl TOOLS
 sta fail_err
 pla
 bcs :id_err
 sta mb_master
 sta mb_mmid
 lda #1
 sta mm_started
 ldx #tn27_end-resv_tab

:reserve
 lda resv_tab+6,x          ; size high
 sta nh_size+2
 lda resv_tab+4,x          ; size low
 sta nh_size
 lda resv_tab+2,x          ; address high
 sta nh_addr+2
 lda resv_tab,x            ; address low
 sta nh_addr
 lda mb_master
 sta nh_id
 lda #ATTR_FIXED
 sta nh_attr
 phx
 jsr new_handle
 plx
 bcs :resv_err
 lda nh_result             ; keep every handle for tools_down
 sta resv_h,x
 lda nh_result+2
 sta resv_h+2,x
 txa
 clc
 adc #8
 tax
 cpx #resv_end-resv_tab
 bcc :reserve
 sec
 xce
 mx %11
 clc
 rts
 mx %00                    ; the error paths below are entered
:mt_err                    ; in native mode with 16-bit M/X
 ldx #$41
 bra :err
:id_err
 ldx #$42
 bra :err
:resv_err
 phx
 jsr who_owns              ; record the block in the way
 pla                       ; stage $43 + reservation index
 lsr
 lsr
 lsr
 clc
 adc #$43
 tax
:err
 sec
 xce
 mx %11
 sec
 rts

*----------------------------------------------------------
* mm_startup - on a direct boot, MMStartUp now that the
* block holding this code belongs to the master ID. It must
* return that ID. Emulation in/out; carry set on error.
*----------------------------------------------------------
mm_startup
 mx %11
 lda mb_osboot
 bne :skip                 ; already started for GS/OS
 clc
 xce
 rep #$30
 mx %00
 pha
 ldx #$0202                ; MMStartUp
 jsl TOOLS
 sta fail_err
 pla
 sta mb_mmid
 php
 sec
 xce
 mx %11
 plp
 bcs :err
 lda #1
 sta mm_started
 lda mb_mmid
 cmp mb_master
 bne :mismatch
 lda mb_mmid+1
 cmp mb_master+1
 bne :mismatch
:skip
 clc
 rts
:mismatch
 stz fail_err
 stz fail_err+1
:err
 ldx #$61
 sec
 rts

*----------------------------------------------------------
* tools_down - release memory and shut the tools down:
*   DisposeHandle  each reservation and fixed block held
*   MMShutDown, DeleteID(master), MTShutDown, TLShutDown
* (direct boot); from GS/OS only the handles, then MT and
* TL. Emulation in/out. Errors are recorded, not fatal.
*----------------------------------------------------------
tools_down
 mx %11
 lda tools_on
 bne :go
 rts
:go
 clc
 xce
 rep #$30
 mx %00
 stz down_err
 ldx #0
:resv_loop
 lda resv_h,x
 ora resv_h+2,x
 beq :resv_next
 phx
 lda resv_h+2,x
 pha
 lda resv_h,x
 pha
 ldx #$1002                ; DisposeHandle
 jsl TOOLS
 jsr note_err
 plx
 stz resv_h,x
 stz resv_h+2,x
:resv_next
 txa
 clc
 adc #8
 tax
 cpx #resv_end-resv_tab
 bcc :resv_loop
 lda data_h
 ora data_h+2
 beq :nodata
 lda data_h+2
 pha
 lda data_h
 pha
 ldx #$1002                ; DisposeHandle (the VEC banks)
 jsl TOOLS
 jsr note_err
 stz data_h
 stz data_h+2
:nodata
 lda mb_osboot
 and #$00FF
 bne :mt
 lda mm_started
 beq :delid
 lda mb_master
 pha
 ldx #$0302                ; MMShutDown
 jsl TOOLS
 jsr note_err
:delid
 lda mb_master
 beq :mt
 pha
 ldx #$2103                ; DeleteID
 jsl TOOLS
 jsr note_err
:mt
 ldx #$0303                ; MTShutDown
 jsl TOOLS
 ldx #$0301                ; TLShutDown
 jsl TOOLS
 stz tools_on
 stz mm_started
 lda down_err
 sta mb_downerr
 sec
 xce
 mx %11
 rts

* note_err - keep the first nonzero tool error (native).
note_err
 mx %00
 bcc :ok
 pha
 lda down_err
 bne :keep
 pla
 sta down_err
 rts
:keep
 pla
:ok
 rts

*----------------------------------------------------------
* who_owns - diagnostics for a failed fixed-address
* NewHandle: FindHandle(nh_addr) and copy the block's owner
* ID, address and size into the mailbox. Native, 16-bit.
* Handle record: +0 address, +4 attributes, +6 owner ID,
* +8 size (Toolbox Reference vol. 1, ch. 12).
*----------------------------------------------------------
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
 sta $F0
 pla
 sta $F2
 ora $F0
 beq :none
 ldy #6
 lda [$F0],y
 sta mb_dbg_owner
 ldy #0
 lda [$F0],y
 sta mb_dbg_addr
 ldy #2
 lda [$F0],y
 sta mb_dbg_addr+2
 ldy #8
 lda [$F0],y
 sta mb_dbg_size
 ldy #10
 lda [$F0],y
 sta mb_dbg_size+2
 rts
:none
 lda #$FFFF
 sta mb_dbg_owner
 rts

*----------------------------------------------------------
* new_handle - NewHandle(nh_size, nh_id, nh_attr, nh_addr).
* Native, 16-bit M/X. Carry set on error, fail_err = code.
*----------------------------------------------------------
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

*----------------------------------------------------------
* read_cmd - XTGS.CMD's first line into mb_cmd as a Pascal
* string; "P" when the file is missing. Emulation in/out.
*----------------------------------------------------------
read_cmd
 mx %11
 lda #1
 sta mb_cmd
 lda #'P'
 sta mb_cmd+1
 lda #<path_cmd
 sta open_path
 lda #>path_cmd
 sta open_path+1
 jsr MLI
 dfb $C8                   ; OPEN
 da open_parms
 bcs :none
 lda open_ref
 sta read_ref
 sta close_ref
 lda #<cmdbuf
 sta read_buf
 lda #>cmdbuf
 sta read_buf+1
 lda #31
 sta read_len
 stz read_len+1
 jsr MLI
 dfb $CA                   ; READ (a short read is fine)
 da read_parms
 bcs :close
 ldx #0
:scan
 cpx read_xfer
 bcs :len
 lda cmdbuf,x
 cmp #$0D
 beq :len
 cmp #$0A
 beq :len
 inx
 bne :scan
:len
 stx mb_cmd
 txa
 beq :close
:copy
 lda cmdbuf-1,x
 sta mb_cmd,x
 dex
 bne :copy
:close
 jsr MLI
 dfb $CC                   ; CLOSE
 da close_parms
:none
 rts

*----------------------------------------------------------
* load_file - read the file ld_path to the 24-bit address
* ld_dst in CHUNK pieces through BOUNCE. With ld_alloc set,
* claim the destination banks first (by the file's size).
* X = stage base for errors. Emulation in/out; fatal on
* error (fail8).
*----------------------------------------------------------
load_file
 mx %11
 stx ld_stage
 lda ld_path
 sta open_path
 lda ld_path+1
 sta open_path+1
 jsr MLI
 dfb $C8                   ; OPEN
 da open_parms
 bcc :opened
 ldx #1
 jmp :fail
:opened
 lda open_ref
 sta eof_ref
 sta read_ref
 sta close_ref
 jsr MLI
 dfb $D1                   ; GET_EOF
 da eof_parms
 bcc :eof_ok
 ldx #2
 jmp :fail
:eof_ok
 lda eof_val
 sta mb_filelen
 sta rem
 lda eof_val+1
 sta mb_filelen+1
 sta rem+1
 lda eof_val+2
 sta mb_filelen+2
 sta rem+2
 stz mb_filelen+3
 lda ld_alloc
 beq :noalloc
 jsr alloc_data
 bcc :noalloc
 ldx #3
 jmp :fail
:noalloc
 lda #<BOUNCE
 sta read_buf
 lda #>BOUNCE
 sta read_buf+1
:loop
 lda rem
 ora rem+1
 ora rem+2
 beq :done
 lda rem+2
 bne :full
 lda rem+1
 cmp #>CHUNK
 bcs :full
 lda rem
 sta read_len
 lda rem+1
 sta read_len+1
 bra :read
:full
 lda #<CHUNK
 sta read_len
 lda #>CHUNK
 sta read_len+1
:read
 jsr MLI
 dfb $CA                   ; READ
 da read_parms
 bcc :read_ok
 ldx #4
 jmp :fail
:read_ok
 lda read_xfer
 cmp read_len
 bne :short
 lda read_xfer+1
 cmp read_len+1
 beq :copy
:short
 lda #0
 ldx #5
 jmp :fail
:copy
 jsr copy_chunk
 sec
 lda rem
 sbc read_len
 sta rem
 lda rem+1
 sbc read_len+1
 sta rem+1
 lda rem+2
 sbc #0
 sta rem+2
 bra :loop
:done
 jsr MLI
 dfb $CC                   ; CLOSE
 da close_parms
 lda #'.'
 jsr COUT
 rts
:fail
 sta fail_err
 stz fail_err+1
 txa
 clc
 adc ld_stage
 tax
 jmp fail8

*----------------------------------------------------------
* com_name - the token after "C " in mb_cmd into path_com
* (Pascal string). Carry set when there is none.
*----------------------------------------------------------
com_name
 mx %11
 ldx #2
:skip
 cpx mb_cmd
 bcs :none
 lda mb_cmd+1,x
 cmp #' '
 bne :copy
 inx
 bne :skip
:copy
 ldy #0
:c
 cpx mb_cmd
 bcs :done
 lda mb_cmd+1,x
 cmp #' '
 beq :done
 sta path_com+1,y
 inx
 iny
 cpy #15
 bcc :c
:done
 sty path_com
 clc
 rts
:none
 sec
 rts

*----------------------------------------------------------
* alloc_data - claim (filelen rounded up to banks) at ld_dst
* for the master ID; the handle is kept in data_h. Emulation
* in/out; carry set on error (fail_err = tool error).
*----------------------------------------------------------
alloc_data
 mx %11
 clc
 xce
 rep #$30
 mx %00
 lda mb_filelen+2          ; whole banks
 ldx mb_filelen
 beq :exact
 inc
:exact
 bne :some
 inc                       ; an empty file still gets a bank
:some
 sta nh_size+2
 stz nh_size
 lda ld_dst
 sta nh_addr
 lda ld_dst+2
 and #$00FF
 sta nh_addr+2
 lda mb_master
 sta nh_id
 lda #ATTR_FIXED
 sta nh_attr
 jsr new_handle
 bcs :err
 lda nh_result
 sta data_h
 lda nh_result+2
 sta data_h+2
 clc
 bra :out
:err
 jsr who_owns
 sec
:out
 php
 sec
 xce
 mx %11
 plp
 rts

*----------------------------------------------------------
* copy_chunk - copy read_len bytes from $00:BOUNCE to the
* 24-bit address ld_dst with MVN, then advance ld_dst.
* Emulation in/out. MVN's bank operands are immediate, so
* the destination bank is patched into the instruction. A
* chunk never crosses a bank: destinations are bank-aligned
* and CHUNK divides $10000.
*----------------------------------------------------------
copy_chunk
 mx %11
 lda ld_dst+2
 sta :mvn+1                ; MVN encoding: $54 dstbank srcbank
 clc
 xce
 rep #$30
 mx %00
 phb
 lda read_len
 dec                       ; MVN copies A+1 bytes
 ldx #BOUNCE
 ldy ld_dst
:mvn
 dfb $54,$00,$00           ; MVN $00 -> dst (dst bank patched)
 plb
 lda ld_dst
 clc
 adc read_len
 sta ld_dst
 bcc :nocarry
 inc ld_dst+2
:nocarry
 sec
 xce
 mx %11
 rts

*----------------------------------------------------------
* mli_glue - native entry (JSL $002004), any M/X. Calls MLI
* command mb_mli_cmd with parameters at mb_mli_parms on the
* loader's page-1 stack in emulation mode. Preserves D, DBR
* and P; returns A = error code (0 = ok), also in
* mb_mli_res.
*----------------------------------------------------------
mli_glue
 mx %00
 phb
 phd
 php
 rep #$30
 pea $0000
 plb
 plb                       ; DBR = $00
 lda #0
 tcd                       ; D = $0000 (the MLI uses zero page)
 tsc
 sta glue_sp
 lda mb_sp                 ; the loader's page-1 stack, below
 sec                       ; anything it may still hold
 sbc #$10
 tcs
 sep #$30
 mx %11
 lda mb_mli_cmd
 sta :cmd
 sec
 xce
 jsr MLI
:cmd dfb $00
 da mb_mli_parms
 clc
 xce
 rep #$30
 mx %00
 and #$00FF
 sta mb_mli_res
 ldx glue_sp
 txs
 plp
 lda >mb_mli_res
 pld
 plb
 rtl

*----------------------------------------------------------
* fail8 - fatal loader error: print stage X and fail_err,
* release what tools_up took, and quit after a key.
*----------------------------------------------------------
fail8
 mx %11
 stx mb_stage
 lda fail_err
 sta mb_err
 lda fail_err+1
 sta mb_err+1
 lda #<msg_fail
 ldy #>msg_fail
 jsr puts
 lda mb_stage
 jsr PRBYTE
 lda #' '
 jsr COUT
 lda fail_err+1
 jsr PRBYTE
 lda fail_err
 jsr PRBYTE
 jsr CROUT
 jsr tools_down
 lda #$5A                  ; the judge reads MB_STAGE for the why
 sta mb_magic
 sta mb_magic+1
wait_quit
 mx %11
 lda #<msg_key
 ldy #>msg_key
 jsr puts
:wait
 lda $C000
 bpl :wait
 sta $C010
quit
 mx %11
 jsr MLI
 dfb $65                   ; QUIT
 da quit_parms
 brk $00

*----------------------------------------------------------
* puts - print the zero-terminated string at Y:A.
*----------------------------------------------------------
puts
 mx %11
 sta $06
 sty $07
 ldy #0
:loop
 lda ($06),y
 beq :done
 ora #$80
 jsr COUT
 iny
 bne :loop
:done
 rts

*----------------------------------------------------------
* Data
*----------------------------------------------------------
msg_hello  asc 'XT/GS LOADER',8D,00
msg_run    asc 8D,'RUNNING CORE',8D,00
msg_exit   asc 'CORE EXIT $',00
msg_fail   asc 'LOADER ERROR ',00
msg_notgs  asc 'THIS PROGRAM REQUIRES AN APPLE IIGS.',8D,00
msg_key    asc 'PRESS A KEY TO QUIT.',00

* Fixed blocks: address (u32), size (u32). The first four
* are the TN #27 reservations for a directly booted ProDOS 8
* program; the rest are XT/GS's own and are claimed under
* GS/OS too.
resv_tab   adrl $000800,$B800
           adrl $010800,$B800
           adrl $E02000,$4000
           adrl $E12000,$8000
tn27_end
           adrl CORE_BASE,$10000
           adrl SVC_BASE,$10000
           adrl RES_BASE,$10000
           adrl GUEST_BASE,$100000
resv_end

gp_parms   dfb 1
           da pathbuf
ol_parms   dfb 2
ol_unit    dfb 0
           da pathbuf+1
open_parms dfb 3
open_path  da 0
           da IOBUF
open_ref   dfb 0
eof_parms  dfb 2
eof_ref    dfb 0
eof_val    ds 3
read_parms dfb 4
read_ref   dfb 0
read_buf   da 0
read_len   dw 0
read_xfer  dw 0
close_parms dfb 1
close_ref  dfb 0
quit_parms dfb 4,0,0,0,0,0,0

path_core  str 'CORE'
path_svc   str 'SVC'
path_vec   str 'VEC'
path_bench str 'BENCH'
path_cmd   str 'XTGS.CMD'
path_com   ds 16

tools_on   dw 0
mm_started dw 0
fail_err   dw 0
down_err   dw 0
glue_sp    dw 0
nh_size    adrl 0
nh_addr    adrl 0
nh_id      dw 0
nh_attr    dw 0
nh_result  adrl 0
resv_h     ds resv_end-resv_tab   ; one 4-byte handle per 8-byte entry
data_h     adrl 0
ld_path    da 0
ld_dst     ds 4
ld_alloc   dfb 0
ld_stage   dfb 0
rem        ds 3
cmdbuf     ds 32
pathbuf    ds 64

 err *-1/$4000             ; the loader must end below the bounce buffer
