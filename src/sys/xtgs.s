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
*      volume if ProDOS left it empty, then to the directory
*      of our own pathname ($0280) when a launcher gave one.
*   2. Read XTGS.CMD (optional) into the mailbox: the first
*      line is the command for the core (P probe, V vectors,
*      B bench, C NAME: .COM program, D: boot a disk image).
*      Default: P. A leading '+' is the layout test: nothing
*      may be where it was assembled for.
*   3. Decide the bank-$00 pages (set_pages): the ones CORE
*      and SVC were assembled for (src/include/layout.s),
*      which this program owns under ProDOS 8; for '+' the
*      NAME_ALTPG ones, and the loader moves its own front
*      page (the file-call entry and the mailbox) to match.
*   4. Start the Tool Locator and Misc Tools and take
*      ownership of memory (ProDOS 8 TN #27, IIGS TN #17):
*      on a direct ProDOS 8 boot (OS_BOOT = 0) get a master
*      user ID from GetNewID($1000) and reserve the ranges
*      GS/OS would have given ProDOS 8; then claim, with
*      fixed-address handles, the regions XT/GS lives in
*      (claim_region): CORE, SVC and the results bank, the
*      guest's 1 MiB, and by the command the disk image's
*      banks (D) or the translator's (K). Each goes to the
*      bank it was assembled for when that is free, else to
*      the first place that is. Then MMStartUp, which must
*      return the master ID.
*   5. Read CORE and SVC into their banks through the
*      bank-$00 bounce buffer; for a V command, read VEC
*      into banks claimed by its size; then add (actual -
*      assembled) to every bank byte and page byte listed at
*      the end of CORE and SVC (reloc_image). MB_LAYOUT has
*      the bank of each region and the page of each area.
*   6. JSL to the core entry in native mode, 16-bit M/X,
*      with S = $0BFF; the core RTLs with its exit code in A.
*   7. Release everything, set MB_DONE and MB_MAGIC, print
*      the exit code, wait for a key, MLI QUIT.
*
* The front page (src/include/mailbox.s) is this image's
* first: JMP start, the file-call entry CORE and SVC JSL to
* (MB_FILECALL -> mli_glue) and the mailbox. The results the
* host judge reads are final once MB_MAGIC is $5A5A; the
* loader then waits for a key before quitting so a headless
* run can dump memory at leisure.
*
* Bank $00 while the core runs. The first three lines are
* this program's own business; the rest are layout.s's
* areas, at their assembled pages unless '+' moved them:
*   $0800-$0BFF  the native stack (S = $0BFF at the JSL)
*   $2000-$3FFF  this loader (resident)
*   page 1       the MLI's stack (mli_glue), and the
*                firmware's while it services an interrupt
*   ZP    $1000  guest CPU state: the direct page
*   MBX   $2000  the front page
*   PATH  $0C00  pathnames for the MLI
*   XFER  $4000  file transfer buffer, 8 KB
*   IOB   $6000  the MLI's I/O buffers, 8 KB
* While it loads, the loader reads through its own IOBUF and
* BOUNCE, which lie where PATH and XFER were assembled.
*----------------------------------------------------------

 xc
 xc
 org $2000
 dsk xtgs
 typ $FF
 mx %11

 put ../include/hw.s
 put ../include/layout.s
 put ../include/mailbox.s

* The loader's own bank-$00 places (not layout.s's: CORE and SVC
* never see them). The two buffers are idle once the core runs.
IOBUF    = $0C00           ; ProDOS 8 I/O buffer (1 KB, page-aligned)
BOUNCE   = $4000           ; transfer buffer for the loads
CHUNK    = $2000           ; bytes per READ
CORE_S   = $0BFF           ; native stack top while the core runs

* The front page (mailbox.s): the ABI, do not reorder. The mailbox
* is the DUM block: it is this page from +$10 up as loaded, and the
* same offsets of the '+' layout's page once set_pages has moved it,
* so the mb_ labels follow MBX_PAGE and tools/gen_reloc.py lists
* every byte of this file that holds one's high byte. `image` and the
* labels on it are the file as ProDOS loaded it and do not move.
image
 jmp start                 ; +$00
 dfb 1                     ; +$03  interface version
filecall
 jmp mli_glue              ; +$04  MB_FILECALL: JSL from native code
 dfb 0
self_len dw 0              ; +$08  this file's length (tools/gen_reloc.py)
 ds MB_END-MB_BASE-10,0    ; the mailbox
 err filecall-image+MB_BASE-MB_FILECALL
 err self_len-image+MB_BASE-MB_SELFLEN
 err *-image+MB_BASE-MB_END

 dum MB_STAGE
mb_stage   ds 2
mb_magic   ds 2
mb_exit    ds 2
mb_err     ds 2
mb_osboot  ds 2
mb_master  ds 2
mb_mmid    ds 2
mb_downerr ds 2
mb_done    ds 2
mb_filelen ds 4
mb_sp      ds 2
mb_perrs   ds 2
mb_pfirst  ds 4
mb_runidx  ds 2
mb_cmd     ds 32
mb_dbg_owner ds 2
mb_dbg_addr ds 4
mb_dbg_size ds 4
mb_mli_cmd ds 2
mb_mli_res ds 2
mb_mli_parms ds 32
mb_icount  ds 4
mb_layout  ds RG_COUNT*2   ; a word a region or area, in RG_ order
mb_layalt  ds 2
mb_end
 dend
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
 err mb_layout-MB_LAYOUT
 err mb_layalt-MB_LAYALT
 err mb_end-MB_END

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

* A launcher (GS/OS, a program selector) leaves our pathname at
* $0280 and its own idea of the prefix; CORE, SVC and the rest
* are beside us, so the pathname's directory becomes the prefix.
* A direct boot leaves the bare name there: nothing to do. Not
* fatal: the files may still be in the prefix we were given.
 ldx SYSPATH
 beq :pfx_done
 cpx #65
 bcs :pfx_done
:pfx_scan
 lda SYSPATH,x
 and #$7F
 cmp #'/'
 beq :pfx_cut
 dex
 bne :pfx_scan
 beq :pfx_done
:pfx_cut
 dex                       ; without the slash; "/NAME" has no directory
 beq :pfx_done
 stx pathbuf
:pfx_copy
 lda SYSPATH,x
 and #$7F
 sta pathbuf,x
 dex
 bne :pfx_copy
 jsr MLI
 dfb $C6                   ; SET_PREFIX
 da gp_parms
:pfx_done
 jsr MLI                   ; the prefix the files are in, kept: the shared drive
 dfb $C7                   ; makes its folder the prefix, and a reboot (boot_pc)
 da gp_parms               ; loads CORE and SVC again
 ldx #63
:pfx_keep
 lda pathbuf,x
 sta pfx_save,x
 dex
 bpl :pfx_keep

* The command first, so tools_up can claim the Mode B disk region
* only when it is needed (D); it would otherwise block a large VEC load.
* Then the pages, which '+' decides; the mailbox may move here.
 jsr read_cmd
 jsr set_pages
 bcc :pages_ok
 stz fail_err
 stz fail_err+1
 jmp fail8
:pages_ok

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
 jsr show_banks

* The images, each at offset 0 of its bank. The desk accessory's
* reboot comes back here (below): CORE and SVC as they are on the
* disk, and the PC started again.
boot_pc
 mx %11
 lda #4
 sta mb_stage
 lda rebooting
 beq :pfx_ok
 ldx #63
:pfx_back
 lda pfx_save,x
 sta pathbuf,x
 dex
 bpl :pfx_back
 jsr MLI
 dfb $C6                   ; SET_PREFIX
 da gp_parms
:pfx_ok
 lda #<path_core
 sta ld_path
 lda #>path_core
 sta ld_path+1
 stz ld_dst
 stz ld_dst+1
 lda mb_layout+RG_CORE+RG_CORE
 sta ld_dst+2
 stz ld_alloc
 ldx #$10
 jsr load_file
 lda mb_filelen            ; (the relocation list is at its end)
 sta img_len
 lda mb_filelen+1
 sta img_len+1
 lda #5
 sta mb_stage
 lda #<path_svc
 sta ld_path
 lda #>path_svc
 sta ld_path+1
 stz ld_dst
 stz ld_dst+1
 lda mb_layout+RG_SVC+RG_SVC
 sta ld_dst+2
 ldx #$20
 jsr load_file
 lda mb_filelen
 sta img_len+2
 lda mb_filelen+1
 sta img_len+3
* The translator (docs/jit.md), when its banks were claimed and the
* file JIT is on the volume: without the file the region's word in
* MB_LAYOUT goes back to 0, which is what the core asks.
 stz img_len+4
 stz img_len+5
 lda mb_cmd+1
 cmp #'K'                  ; (K is the first M6's own, in the core)
 beq :jitdone
 lda mb_layout+RG_JIT+RG_JIT
 beq :jitdone
 lda #<path_jit
 sta ld_path
 lda #>path_jit
 sta ld_path+1
 stz ld_dst
 stz ld_dst+1
 lda mb_layout+RG_JIT+RG_JIT
 sta ld_dst+2
 stz ld_alloc
 lda #1
 sta ld_opt
 ldx #$60
 jsr load_file
 lda ld_opt
 stz ld_opt
 bmi :nojitf
 lda mb_filelen
 sta img_len+4
 lda mb_filelen+1
 sta img_len+5
 bra :jitdone
:nojitf
 stz mb_layout+RG_JIT+RG_JIT
 stz mb_layout+RG_JIT+RG_JIT+1
:jitdone

* A data file, by the command letter (a reboot keeps what is loaded:
* the disk image is as the PC left it).
 lda rebooting
 beq :first
 jmp :loaded
:first
 lda mb_cmd+1
 cmp #'V'
 bne :nodata
 lda #6
 sta mb_stage
 lda #<path_vec
 sta ld_path
 lda #>path_vec
 sta ld_path+1
 lda #1                    ; alloc_data claims the banks and sets ld_dst
 sta ld_alloc
 ldx #$30
 jsr load_file
 jmp :loaded
:nodata
 lda mb_cmd+1
 cmp #'C'
 bne :nocom
 jsr com_name              ; NAME from the command line into path_com
 bcc :havecom
 jmp :loaded               ; none given: the core will complain
:havecom
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
 lda mb_layout+RG_GUEST+RG_GUEST
 clc
 adc #COM_BASE-GUEST_BASE/$10000
 sta ld_dst+2
 stz ld_alloc
 ldx #$50
 jsr load_file
 lda mb_filelen+2          ; a program fits below A000:0000 (576 KB)
 cmp #9
 bcc :loaded
:toobig
 ldx #$5F
 stz fail_err
 stz fail_err+1
 jmp fail8
:nocom
 lda mb_cmd+1
 cmp #'D'
 bne :nodisk
 lda #7                    ; D: the raw disk image into its banks
 sta mb_stage
 lda #<path_disk
 sta ld_path
 lda #>path_disk
 sta ld_path+1
 stz ld_dst
 stz ld_dst+1
 lda mb_layout+RG_DISK+RG_DISK
 sta ld_dst+2
 stz ld_alloc
 ldx #$30
 jsr load_file
 jmp :loaded
:nodisk
 lda mb_cmd+1
 cmp #'B'
 beq :loadbench
 cmp #'K'                  ; K: JIT runs the same bench at 0000:0100
 bne :loaded
:loadbench
 lda #7                    ; load the bench program into guest 0000:0100
 sta mb_stage
 lda #<path_bench
 sta ld_path
 lda #>path_bench
 sta ld_path+1
 lda #<BENCH_BASE
 sta ld_dst
 lda #>BENCH_BASE
 sta ld_dst+1
 lda mb_layout+RG_GUEST+RG_GUEST
 sta ld_dst+2
 stz ld_alloc
 ldx #$40
 jsr load_file
:loaded

* Every region has its bank now: fix the images' bank and page bytes.
 lda #$0B
 sta mb_stage
 jsr reloc_all
 bcc :reloc_ok
 stz fail_err
 stz fail_err+1
 jmp fail8
:reloc_ok

* Run the core: native mode, 16-bit M/X, its own stack.
 lda #<msg_run
 ldy #>msg_run
 jsr puts
 jsr cda_on                ; "XTGS Control" among the desk accessories
 lda #8
 sta mb_stage
 lda mb_layout+RG_CORE+RG_CORE
 sta :core+3               ; the JSL's bank
 clc
 xce
 rep #$30
 mx %00
 tsc
 sta mb_sp
 lda #CORE_S
 tcs
:core
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
 stz close_ref             ; reference 0: whatever the guest left open
 jsr MLI                   ; (its data is not on the disk until then)
 dfb $CC                   ; CLOSE
 da close_parms
 jsr cda_off               ; (SVC is about to go, or to be loaded again)
 lda mb_exit+1             ; the desk accessory asked for a reboot
 cmp #>CTL_EXIT            ; (src/svc/control.s: CTL_EXIT + 1 soft, + 2 hard)?
 bne :final
 lda mb_exit
 cmp #<CTL_EXIT+1
 beq :again
 cmp #<CTL_EXIT+2
 bne :final
 jsr zero_guest
:again
 lda #1
 sta rebooting
 jmp boot_pc
:final
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
 lda mb_exit+1             ; the desk accessory's "Quit": no key to wait for
 cmp #>CTL_EXIT
 bne :key
 lda mb_exit
 cmp #<CTL_EXIT+3
 bne :key
 jmp quit
:key
 jmp wait_quit

*----------------------------------------------------------
* tools_up - TLStartUp, MTStartUp; the master user ID; the
* TN #27 reservations on a direct boot; then the regions
* XT/GS lives in. Emulation in/out. Carry set on error
* with X = stage ($43-$46 a TN #27 range, $47 + RG_ index
* a region) and fail_err = tool error.
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
 ldx #0                    ; the TN #27 ranges first
 bra :reserve

* Launched from GS/OS: MMStartUp names our memory; TN #27
* says the low 128K is already ours. Only the regions.
:from_gsos
 pha
 ldx #$0202                ; MMStartUp
 jsl TOOLS
 sta fail_err
 pla
 bcc :gs_ok
 jmp :id_err
:gs_ok
 sta mb_master
 sta mb_mmid
 lda #1
 sta mm_started
 bra :regions

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
 bcc :resv_ok
 jmp :resv_err
:resv_ok
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

* The regions, the big ones first while the room is whole. The
* disk image's banks only for D (they would block a large VEC
* load), the translator's only for K.
:regions
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
 bne :nok
 ldx #RG_JIT+RG_JIT
 jsr claim_region
 bcs :rg_err
 bra :nojit
:nok
 cmp #'C'                  ; a PC: the translator's banks when they can be
 beq :jit                  ; had (it is done without when they cannot)
 cmp #'D'
 beq :jit
 cmp #'S'
 bne :nojit
:jit
 ldx #RG_JIT+RG_JIT
 jsr claim_region
:nojit
 jsr claim_xms
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
:rg_err
 jsr who_owns              ; what holds the first choice (nh_addr)
 lda cr_x                  ; stage $47 + region
 lsr
 clc
 adc #$47
 tax
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
*   DisposeHandle  each reservation and region held
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
 ldx #0
:rg_loop
 lda rg_h,x
 ora rg_h+2,x
 beq :rg_next
 phx
 lda rg_h+2,x
 pha
 lda rg_h,x
 pha
 ldx #$1002                ; DisposeHandle (a region)
 jsl TOOLS
 jsr note_err
 plx
 stz rg_h,x
 stz rg_h+2,x
:rg_next
 inx
 inx
 inx
 inx
 cpx #RG_BANKS*4
 bcc :rg_loop
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
* claim_region - X = region * 2. Claim its rg_banks whole
* banks with a fixed-address handle: at the bank the images
* were assembled for when that is free, else at the first
* bank from SCAN_LO up that the Memory Manager will give
* (a multiple of rg_align + 1). The '+' test layout skips
* the assembled bank, so every region moves. The bank goes
* to mb_layout, the handle to rg_h. Native, 16-bit M/X.
* Carry set when there is no room: fail_err = the last
* tool error, nh_addr = the assembled address (who_owns).
*----------------------------------------------------------
SCAN_LO  = $02             ; banks $00/$01 are ProDOS 8's and the firmware's
SCAN_HI  = $E0             ; one past the last expansion RAM bank
claim_region
 mx %00
 stx cr_x
 lda rg_banks,x
 sta nh_size+2
 stz nh_size
 stz nh_addr
 lda mb_master
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
 lda nh_result             ; kept for tools_down
 sta rg_h,x
 lda nh_result+2
 sta rg_h+2,x
 clc
 rts
:try
 sta nh_addr+2
 jmp new_handle

*----------------------------------------------------------
* cda_on - "XTGS Control" (src/svc/control.s) installed with the
* Desk Manager: a header in a handle of ours, the name and the
* start and shutdown routines, which are SVC's entries 14 and 15.
* No error is one: there is no accessory then. cda_off takes it
* out and gives the handle back; both before SVC's bank is loaded
* again or freed. Emulation in/out.
*----------------------------------------------------------
cda_on
 mx %11
 clc
 xce
 rep #$30
 mx %00
 lda #cda_end-cda_hdr
 sta nh_size
 stz nh_size+2
 stz nh_addr
 stz nh_addr+2
 lda mb_master
 sta nh_id
 lda #$C018                ; locked, fixed, anywhere but the special memory
 sta nh_attr
 jsr new_handle
 bcs :out
 lda nh_result
 sta cda_h
 sta CDA_P
 lda nh_result+2
 sta cda_h+2
 sta CDA_P+2
 lda [CDA_P]               ; the block
 tax
 ldy #2
 lda [CDA_P],y
 sta CDA_P+2
 stx CDA_P
 lda mb_layout+RG_SVC+RG_SVC ; the block's own code: a jump to SVC's entry 14
 and #$00FF
 ora #$EA00                ; (and a NOP)
 sta cda_jml+3
 lda CDA_P                 ; the start routine is that jump, the shutdown
 clc                       ; routine the RTL after it
 adc #cda_jml-cda_hdr
 sta cda_start
 lda CDA_P+2
 sta cda_start+2
 sta cda_stop+2
 lda CDA_P
 clc
 adc #cda_rtl-cda_hdr
 sta cda_stop
 ldy #0
 sep #$20
 mx %10
:c
 lda cda_hdr,y
 sta [CDA_P],y
 iny
 cpy #cda_end-cda_hdr
 bcc :c
 rep #$20
 mx %00
 lda cda_h+2
 pha
 lda cda_h
 pha
 ldx #$0F05                ; InstallCDA
 jsl TOOLS
 bcs :out
 lda #1
 sta cda_in
:out
 sec
 xce
 mx %11
 rts

cda_off
 mx %11
 clc
 xce
 rep #$30
 mx %00
 lda cda_in
 beq :free
 stz cda_in
 lda cda_h+2
 pha
 lda cda_h
 pha
 ldx #$2105                ; RemoveCDA
 jsl TOOLS
 bcc :free
 lda cda_h                 ; a Desk Manager without the call (ROM 01 and no
 sta CDA_P                 ; system disk's tools): the accessory stays in the
 lda cda_h+2               ; menu, so its block stays too and its jump becomes
 sta CDA_P+2               ; a return
 lda [CDA_P]
 tax
 ldy #2
 lda [CDA_P],y
 sta CDA_P+2
 stx CDA_P
 ldy #cda_jml-cda_hdr
 sep #$20
 mx %10
 lda #$6B
 sta [CDA_P],y
 rep #$20
 mx %00
 stz cda_h
 stz cda_h+2
:free
 lda cda_h
 ora cda_h+2
 beq :out
 lda cda_h+2
 pha
 lda cda_h
 pha
 ldx #$1002                ; DisposeHandle
 jsl TOOLS
 stz cda_h
 stz cda_h+2
:out
 sec
 xce
 mx %11
 rts

CDA_P      = $06             ; a long pointer in the zero page (ours while we run)
CTL_EXIT   = $B0C0           ; (src/svc/control.s)
cda_in     dw 0
cda_h      adrl 0
cda_hdr    str 'XTGS Control'
cda_start  adrl 0            ; cda_jml, where the block is
cda_stop   adrl 0            ; cda_rtl
cda_jml    hex 5C            ; jml SVC's entry 14 (its bank put in)
           dw 42
           hex 00EA
cda_rtl    rtl
cda_end
rebooting  dw 0
pfx_save   ds 64

*----------------------------------------------------------
* zero_guest - a hard reboot: the PC's megabyte cleared, a
* bank a move. Emulation in/out.
*----------------------------------------------------------
zero_guest
 mx %11
 clc
 xce
 rep #$30
 mx %00
 lda mb_layout+RG_GUEST+RG_GUEST
 and #$00FF
 sta zg_b
 lda #16
 sta zg_n
:bank
 sep #$20
 mx %10
 lda zg_b
 sta :st+3
 sta :mv+1
 sta :mv+2
 rep #$20
 mx %00
 lda #0
:st
 sta >$000000              ; (the bank stored above)
 ldx #0
 ldy #2
 lda #$FFFD
 phb
:mv
 hex 540000                ; mvn bank,bank
 plb
 inc zg_b
 dec zg_n
 bne :bank
 sec
 xce
 mx %11
 rts
zg_b       dw 0
zg_n       dw 0

*----------------------------------------------------------
* claim_xms - S has no disk image: its banks are the guest's
* XMS memory (src/svc/xms.s) when they can be had; claimed
* last, so that nothing else goes without for it, and no
* error when they cannot. Native, 16-bit M/X.
*----------------------------------------------------------
claim_xms
 mx %00
 lda mb_cmd+1
 and #$00FF
 cmp #'S'
 bne :no
 ldx #RG_DISK+RG_DISK
 jsr claim_region
:no
 rts

*----------------------------------------------------------
* show_banks - print the bank of each region and the page
* of each bank-$00 area, in RG_ order (00 = not claimed).
* Emulation in/out.
*----------------------------------------------------------
show_banks
 mx %11
 lda #<msg_banks
 ldy #>msg_banks
 jsr puts
 ldx #0
 lda #RG_BANKS*2
 jsr :row
 lda #<msg_pages
 ldy #>msg_pages
 jsr puts
 ldx #RG_BANKS*2
 lda #RG_COUNT*2
:row
 sta sb_end
:loop
 phx
 lda #' '+$80
 jsr COUT
 plx
 phx
 lda mb_layout,x
 jsr PRBYTE
 plx
 inx
 inx
 cpx sb_end
 bcc :loop
 jmp CROUT

*----------------------------------------------------------
* set_pages - the page of each bank-$00 area into mb_layout:
* the assembled ones, which are this program's to give under
* ProDOS 8 (the TN #27 reservation covers them); for the '+'
* test layout the NAME_ALTPG ones. CORE and SVC are fixed up
* from mb_layout with everything else (reloc_all).
*
* The front page is this program's own, so for '+' it moves
* itself: the page as loaded is copied to its new place and
* every byte of the loader that holds its page -- the list
* at the end of this file, like CORE's -- gets the
* difference. From there on the mb_ labels mean the copy,
* reloc_image's among them: both pages hold the same until
* it returns. Emulation in/out; carry set with X = $70 when
* the file has no list (a plain assembly, a short load).
*----------------------------------------------------------
set_pages
 mx %11
 clc
 xce
 rep #$30
 mx %00
 ldx #RG_COUNT-RG_BANKS*2-2
:fill
 lda pg_asm,x
 ldy mb_layalt
 beq :asm
 lda pg_alt,x
:asm
 sta mb_layout+RG_BANKS+RG_BANKS,x
 dex
 dex
 bpl :fill
 lda mb_layalt
 beq :ok
 lda mb_layout+RG_MBX+RG_MBX
 xba                       ; page -> its address
 sta $F0
 stz $F2
 ldy #$00FE
:copy
 lda image,y
 sta [$F0],y
 dey
 dey
 bpl :copy
 lda #image
 sta $F0                   ; [$F0] = this file in memory
 lda self_len
 jsr reloc_image
 bcc :ok
 sec
 xce
 mx %11
 ldx #$70
 sec
 rts
 mx %00
:ok
 sec
 xce
 mx %11
 clc
 rts

*----------------------------------------------------------
* reloc_all - fix the bank and page bytes of CORE and SVC,
* once every region has its bank. Emulation in/out; carry
* set on a bad list with X = stage ($71 CORE, $72 SVC).
*----------------------------------------------------------
reloc_all
 mx %11
 clc
 xce
 rep #$30
 mx %00
 stz $F0
 lda mb_layout+RG_CORE+RG_CORE
 sta $F2
 lda img_len
 jsr reloc_image
 ldx #$71
 bcs :out
 lda mb_layout+RG_SVC+RG_SVC
 sta $F2                   ; ($F0 is still 0)
 lda img_len+2
 jsr reloc_image
 ldx #$72
 bcs :out
 lda img_len+4             ; the translator, when it was loaded
 beq :out                  ; (the carry is clear)
 lda mb_layout+RG_JIT+RG_JIT
 sta $F2
 lda img_len+4
 jsr reloc_image
 ldx #$73
:out
 php
 sec
 xce
 mx %11
 plp
 rts

*----------------------------------------------------------
* reloc_image - [$F0] = an image in memory, A = its file's
* length. The file ends with the list tools/gen_reloc.py
* appended:
*
*     groups   dfb RG_ index, assembled bank or page
*              dw  count, then count offsets
*     dw       bytes of groups
*     dw       RELOC_MAGIC
*
* Each offset is a byte of the image holding that region's
* bank, or the high byte of an address in that bank-$00
* area, as assembled: add (mb_layout's bank or page now -
* the assembled one). A region nobody claimed is left alone
* (its code does not run). Native, 16-bit M/X; carry set
* when the list is not there or makes no sense.
*----------------------------------------------------------
reloc_image
 mx %00
 sec
 sbc #4
 bcc :bad
 sta rl_end                ; offset of the two closing words
 ldy rl_end
 iny
 iny
 lda [$F0],y
 cmp #RELOC_MAGIC
 bne :bad
 ldy rl_end
 lda rl_end
 sec
 sbc [$F0],y
 bcc :bad
 tay                       ; the first group
:group
 cpy rl_end
 beq :done
 bcs :bad
 lda [$F0],y               ; RG_ index (low), assembled bank or page (high)
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
 lda [$F0],y
 iny
 iny
 sta rl_count
:fix
 lda rl_count
 beq :group
 dec rl_count
 lda [$F0],y
 iny
 iny
 phy
 tay
 sep #$20
 mx %10
 lda [$F0],y
 clc
 adc rl_add
 sta [$F0],y
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
* string; "P" when the file is missing. A leading '+' is
* taken off and noted in mb_layalt. Emulation in/out.
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
 lda mb_cmd+1              ; '+': the layout test; the command follows
 cmp #'+'
 bne :plain
 lda #1
 sta mb_layalt
 ldx #0
:shift
 lda mb_cmd+2,x
 sta mb_cmd+1,x
 inx
 cpx #30
 bcc :shift
 dec mb_cmd
 bne :plain
 lda #1                    ; nothing after it: the default
 sta mb_cmd
 lda #'P'
 sta mb_cmd+1
:plain
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
 ldy ld_opt                ; a file that may be missing: ld_opt comes back $FF
 beq :must
 ldy #$FF
 sty ld_opt
 rts
:must
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
* alloc_data - claim the data region, (filelen rounded up
* to banks), and point ld_dst at it. Emulation in/out;
* carry set on error (fail_err = tool error).
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
 sta rg_banks+RG_DATA+RG_DATA
 ldx #RG_DATA+RG_DATA
 jsr claim_region
 bcs :err
 stz ld_dst
 lda mb_layout+RG_DATA+RG_DATA
 sta ld_dst+2
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
* mli_glue - native entry (JSL MB_FILECALL), any M/X. Calls MLI
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
 sei                       ; the DOC timer interrupt is live while a guest runs
 rep #$30                  ; (sound.s): none across the switch to emulation mode
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
msg_banks  asc 'BANKS',00
msg_pages  asc 'PAGES',00

* Fixed blocks: address (u32), size (u32). The TN #27
* reservations for a directly booted ProDOS 8 program.
resv_tab   adrl $000800,$B800
           adrl $010800,$B800
           adrl $E02000,$4000
           adrl $E12000,$8000
resv_end

* The regions, in RG_ order: the bank each was assembled
* for, its size in banks (the data region's is set from the
* file), and the mask its first bank must be clear of.
rg_asm     dw CORE_BANK,SVC_BANK,RES_BANK,JIT_BANK,GUEST_BANK,DATA_BANK,DISK_BANK
rg_banks   dw 1,1,1,3,16,0,DISK_BANKS
rg_align   dw 0,0,0,0,$000F,0,0
 err rg_banks-rg_asm-RG_BANKS-RG_BANKS
 err rg_align-rg_banks-RG_BANKS-RG_BANKS
 err *-rg_align-RG_BANKS-RG_BANKS
 err GUEST_BANK&$0F         ; the 20-bit wrap needs a 1 MiB-aligned guest

* The bank-$00 areas, in RG_ order from RG_BANKS: the page each
* was assembled for, and its page in the '+' test layout.
pg_asm     dw ZP_PAGE,MBX_PAGE,PATH_PAGE,XFER_PAGE,IOB_PAGE
pg_alt     dw ZP_ALTPG,MBX_ALTPG,PATH_ALTPG,XFER_ALTPG,IOB_ALTPG
 err pg_alt-pg_asm/2+RG_BANKS-RG_COUNT
 err *-pg_alt/2+RG_BANKS-RG_COUNT

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
path_jit   str 'JIT'
path_vec   str 'VEC'
path_bench str 'BENCH'
path_disk  str 'DISK'
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
rg_h       ds RG_BANKS*4          ; a handle a region
sb_end     dfb 0
cr_x       dw 0
cr_bank    dw 0
img_len    dw 0,0,0               ; CORE's, SVC's and JIT's file lengths (0: not loaded)
ld_opt     dfb 0                  ; load_file: nonzero, the file may be missing
rl_end     dw 0
rl_delta   dw 0
rl_add     dw 0
rl_count   dw 0
ld_path    da 0
ld_dst     ds 4
ld_alloc   dfb 0
ld_stage   dfb 0
rem        ds 3
cmdbuf     ds 32
pathbuf    ds 64

 err *-1/$4000             ; the loader ends below the bounce buffer (and
                           ; gen_reloc.py checks it does with its list)
