*----------------------------------------------------------
* redir.s - Mode B: a ProDOS directory as a DOS drive.
*
* A line "C=/VOL/DIR" (or "C=DIR", below the launch folder)
* after the command in XTGS.CMD shares that directory as
* drive C: of the DOS the disk image boots (docs/share.md).
* The drive is a network drive to DOS: its kernel hands the
* file calls for it to INT 2Fh AH=11h, the redirector
* interface, and those are answered here from ProDOS
* through the same file layer as Mode A (files.s). The
* share is the ProDOS prefix, so a DOS path is a partial
* pathname.
*
* Nothing is loaded in the guest. Three stubs sit in the
* BIOS segment at F000:RD_OFF (rd_stub):
*   hook21  INT 21h, in front of DOS's own: hypercall 256
*           (rd_int21), then DOS. It waits for the kernel's
*           first EXEC (AX=4B00h, the shell): DOS is whole
*           then and its drive table exists.
*   install run once in place of that call's first
*           instruction: asks DOS its version, its list of
*           lists and its swappable data area, hypercall 258
*           (rd_install) marks the drive's CDS entry as a
*           network drive and takes INT 2Fh, and the EXEC
*           goes on to DOS. INT 21h is given back.
*   hook2F  INT 2Fh: AH=11h is hypercall 257 (rd_int2f);
*           a call that is not for the drive goes on down
*           the chain.
* rd_poll (once a frame) puts hook21 in when the kernel has
* set its INT 21h vector.
*
* The kernel's side is DOS 4+'s: the swappable data area's
* layout (first filename +9Eh, second +11Eh, the search
* attribute +24Dh, the extended open's words +2DDh), the
* 58h-byte CDS and the SFT. FreeDOS is the DOS this was
* written against.
*----------------------------------------------------------
SDA_DTA    = $0C             ; far pointer: the transfer address
SDA_FN1    = $9E             ; "C:\DIR\NAME.EXT", fully qualified
SDA_FN2    = $11E            ; rename's second
SDA_SATTR  = $24D            ; find first's attribute mask
SDA_XACT   = $2DD            ; extended open: action, attribute, mode
SDA_XATTR  = $2DF
SDA_XMODE  = $2E1
SFT_COUNT  = $00
SFT_MODE   = $02
SFT_ATTR   = $04
SFT_FLAGS  = $05
SFT_SLOT   = $0B             ; (the start cluster) our handle entry * 8
SFT_TIME   = $0D
SFT_DATE   = $0F
SFT_SIZE   = $11
SFT_POS    = $15
SFT_NAME   = $20
RD_DONE    = RD_OFF+$1F      ; the stubs' IRET
RD_INST    = RD_OFF+$20
RD_NDIRS   = 8

rd_state   dw 0              ; 0 off, 1 waiting for DOS's INT 21h, 2 for its EXEC,
                             ; 3 installing, 4 the drive is there, 5 it could not be
rd_cfg     dw 0              ; 0 no share asked for, 1 found, 2 not a directory
rd_boot    dw 0              ; the S command: DOS itself comes from the share
rd_early   dw 0              ; while it boots from there: hook21 goes in at the
                             ; first BIOS call and stays until the shell's EXEC
rd_lol     ds 4              ; DOS's list of lists (host pointer)
rd_drive   dw 2              ; 0 = A:
rd_old21   ds 4
rd_ivt21   ds 4              ; INT 21h as it was a frame ago
rd_sda     ds 4              ; the swappable data area (host pointer)
rd_len     dw 0
rd_ent     dw 0              ; the handle entry * 8 at work
rd_mode    dw 0
rd_arg     dw 0
rd_wr      dw 0
rd_fn      dw 0              ; the AL of the call at work
rd_trunc   dw 0
rd_attr    dw 0
rd_time    dw 0
rd_date    dw 0
rd_fidx    dw 0              ; find: entry in the block, block, directory slot
rd_fblk    dw 0
rd_fdir    dw 0
rd_dnext   dw 0
rd_n83     ds 12             ; the last component of the path, 8+3
rd_root    ds 66             ; the share's ProDOS pathname (Pascal)
rd_dgen    ds RD_NDIRS*2     ; a word a slot: its generation
rd_dpath   ds 64             ; the directory a search names
rd_dirs    ds RD_NDIRS*64    ; the directories being searched (Pascal, partial)
rd_kname   hex 0A
           asc 'KERNEL.SYS'
rd_defroot hex 06
           asc 'SHARED'
rd_cmdname hex 08
           asc 'XTGS.CMD'
rd_m1      asc 'Drive '
           hex 00
rd_m2      asc ': is '
           hex 00
rd_m3      asc ' (not found)'
           hex 00
rd_m4      asc 'No KERNEL.SYS there to boot.'
           hex 0D0A00

* The guest's side, at F000:RD_OFF.
rd_stub
 hex FE380001              ; +00 hook21: hypercall 256
 hex 2EFF2E                ; +04 jmp far [cs:old21]
 dw RD_OFF+9
 adrl 0                    ; +09 old21
 hex 80FC117504            ; +0D hook2F: cmp ah,11h / jne +16
 hex FE380101              ; +12 hypercall 257
 hex 2EFF2E                ; +16 jmp far [cs:old2F]
 dw RD_OFF+$1B
 adrl 0                    ; +1B old2F
 hex CF                    ; +1F iret
 hex 5053515256571E06      ; +20 install: push ax bx cx dx si di ds es
 hex B430CD2150            ; +28 mov ah,30h / int 21h / push ax
 hex B452CD210653          ; +2D mov ah,52h / int 21h / push es / push bx
 hex B8065DCD21            ; +33 mov ax,5D06h / int 21h
 hex FE380201              ; +38 hypercall 258
 hex 83C406                ; +3C add sp,6
 hex 071F5F5E5A595B58      ; +3F pop es ds di si dx cx bx ax
 hex 2EFF2E                ; +47 jmp far [cs:old21]
 dw RD_OFF+9
rd_stubend
 err rd_stubend-rd_stub-$4C

* rd_tab - hypercalls 256.. (svc_hypercall)
rd_tab     da rd_int21,rd_int2f,rd_install
RD_NCALLS  = 3

*=== setting up ==============================================
* rd_setup - from svc_bootinit: the share XTGS.CMD names, if
* any, becomes the ProDOS prefix and the stubs go in.
rd_setup
 mx %00
 stz rd_state
 stz rd_cfg
 stz rd_ivt21
 stz rd_ivt21+2
 stz rd_dnext
 lda #0
 sta >RD_STATE
 sta >RD_DIAG
 sta >RD_CALLS
 sta >RD_LAST
 ldx #0
:z
 stz rd_dgen,x
 inx
 inx
 cpx #RD_NDIRS*2
 bcc :z
 jsr handle_init
 stz rd_early
 jsr rd_readcfg
 bcc :named
 lda rd_boot               ; S and no folder named: SHARED, beside the program
 beq :out
 ldx #0
:df
 lda rd_defroot,x
 sta rd_root,x
 inx
 inx
 cpx #8
 bcc :df
:named
 lda rd_boot               ; the drive FreeDOS boots from is C:
 beq :any
 lda #2
 sta rd_drive
:any
 lda #2
 sta rd_cfg
 jsr rd_mkroot
 bcs :out
 lda #1
 sta rd_cfg
 ldx #0
 sep #$20
 mx %10
:c
 lda rd_stub,x
 sta >H_BIOS+RD_OFF,x
 inx
 cpx #rd_stubend-rd_stub
 bcc :c
 rep #$20
 mx %00
 lda #1
 sta rd_state
 sta >RD_STATE
 lda rd_boot
 sta rd_early
:out
 rts

* rd_kernel - the S command: KERNEL.SYS of the share to
* 0060:0000, where a FreeDOS boot sector puts it. C set when
* there is no share or no such file.
rd_kernel
 mx %00
 lda rd_cfg
 cmp #1
 bne :bad
 ldx #0
:n
 lda rd_kname,x            ; (a word at a time: one byte past is the default's)
 sta >PATHBUF0,x
 inx
 inx
 cpx #12
 bcc :n
 ldx #0
 lda #0
 jsr p_open
 bcs :bad
 stx rd_ent
 lda #KERNEL_LIN
 sta pGST
 lda #GUEST_BANK
 sta pGST+2
 stz rd_len                ; blocks read
:rd
 lda #BOUNCE_LEN
 sta sv0
 ldx rd_ent
 jsr p_read                ; pGST goes on
 bcs :end
 cmp #0
 beq :end
 inc rd_len
 lda rd_len
 cmp #KERNEL_MAX/BOUNCE_LEN
 bcc :rd
:end
 ldx rd_ent
 jsr p_close
 lda rd_len
 beq :bad
 clc
 rts
:bad
 sec
 rts

* rd_nokernel - what the screen says then
rd_nokernel
 mx %00
 lda #$000F
 sta tty_attr
 lda #rd_m4
 jsr rd_puts
 lda #$FFFF
 sta tty_attr
 rts

* rd_readcfg - XTGS.CMD's lines after the first: "X=path"
* is the share (X a drive letter from C). C clear: rd_drive
* and rd_root (as written, upper case) are set.
rd_readcfg
 mx %00
 ldx #0
 sep #$20
 mx %10
:n
 lda rd_cmdname,x
 sta >PATHBUF0,x
 inx
 cpx #9
 bcc :n
 rep #$20
 mx %00
 stz rd_len
 stz rd_root
 ldx #0
 lda #0
 jsr p_open
 bcc :open
 rts
:open
 stx rd_ent
 lda #4
 sta >MB_MLI_PARMS
 jsr h_ref
 lda #BOUNCEBUF
 sta >MB_MLI_PARMS+2
 lda #512
 sta >MB_MLI_PARMS+4
 lda #$CA
 jsr mli
 bcs :close
 lda >MB_MLI_PARMS+6
 sta rd_len
:close
 ldx rd_ent
 jsr p_close
 ldx #0
 bra :first
:nf
 jmp :none
:first                     ; the command's line
 jsr rd_cfgch
 beq :nf
 cmp #$0D
 beq :line
 cmp #$0A
 bne :first
:line
 jsr rd_cfgch
 beq :nf
 cmp #$21
 bcc :line                 ; line ends and blanks
 sta sv0
 jsr rd_cfgch
 beq :nf
 cmp #'='
 bne :skip
 lda sv0
 cmp #'C'
 bcc :skip
 cmp #'Z'+1
 bcs :skip
 sec
 sbc #'A'
 sta rd_drive
 ldy #0
:p
 jsr rd_cfgch
 beq :pend
 cmp #$0D
 beq :pend
 cmp #$0A
 beq :pend
 cpy #63
 bcs :p
 sep #$20
 mx %10
 sta rd_root+1,y
 rep #$20
 mx %00
 iny
 bra :p
:pend                      ; trailing blanks and slashes go
 tya
 beq :none
 lda rd_root,y
 and #$00FF
 cmp #$21
 bcc :cut
 cmp #'/'
 bne :have
:cut
 dey
 bra :pend
:have
 sep #$20
 mx %10
 tya
 sta rd_root
 rep #$20
 mx %00
 clc
 rts
:skip                      ; another setting: to the end of its line
 cmp #$0D
 beq :line
 cmp #$0A
 beq :line
 jsr rd_cfgch
 bne :skip
:none
 sec
 rts

* rd_cfgch - A = the file's next character (X, in the bounce
* buffer), upper case; 0 and Z at its end
rd_cfgch
 mx %00
 cpx rd_len
 bcs :end
 lda >BOUNCEBUF,x
 inx
 and #$007F
 cmp #'a'
 bcc :ok
 cmp #'z'+1
 bcs :ok
 and #$005F
:ok
 cmp #0
 rts
:end
 lda #0
 rts

* rd_mkroot - rd_root as a full pathname (a partial one is
* below the launch folder, the prefix), checked to be a
* directory, made the prefix. C set when it is not there.
rd_mkroot
 mx %00
 stz sv5                   ; length so far
 lda rd_root+1
 and #$00FF
 cmp #'/'
 beq :own
 jsr get_prefix
 bcc :lr1
 jmp :bad
:lr1
 lda >PREFIXBUF
 and #$00FF
 sta sv5
 cmp #63
 bcs :bad
 ldx #0
:pf
 cpx sv5
 bcs :own
 lda >PREFIXBUF+1,x
 sta >PATHBUF0+1,x
 inx
 bra :pf
:own
 lda rd_root
 and #$00FF
 sta sv4
 ldy #0
 ldx sv5
:cp
 cpy sv4
 bcs :done
 cpx #63
 bcs :bad
 lda rd_root+1,y
 sta >PATHBUF0+1,x         ; (a word: the byte after it is the next one's)
 inx
 iny
 bra :cp
:done
 stx sv5
 sep #$20
 mx %10
 txa
 sta >PATHBUF0
 ldx #0                    ; the full name back, for the banner and the volume
:bk
 lda >PATHBUF0,x
 sta rd_root,x
 inx
 cpx #64
 bcc :bk
 rep #$20
 mx %00
 ldx #0
 jsr p_getinfo
 bcs :bad
 lda >MB_MLI_PARMS+4
 and #$00FF
 cmp #$0F
 bne :bad
 lda #1
 sta >MB_MLI_PARMS
 lda #PATHBUF0
 sta >MB_MLI_PARMS+1
 lda #$C6                  ; SET_PREFIX
 jsr mli
 bcs :bad
 jmp get_prefix            ; PREFIXBUF: the share, "/VOL/DIR/"
:bad
 sec
 rts

* rd_banner - after the sign-on: the share's line, then the
* blank line that ends the banner
rd_banner
 mx %00
 lda rd_cfg
 beq :end
 lda #$000F
 sta tty_attr
 lda #rd_m1
 jsr rd_puts
 lda rd_drive
 clc
 adc #'A'
 jsr vid_tty
 lda #rd_m2
 jsr rd_puts
 ldy #1
:r
 lda rd_root
 and #$00FF
 sta sv3
 cpy sv3
 beq :last
 bcs :rend
:last
 lda rd_root,y
 and #$00FF
 phy
 jsr vid_tty
 ply
 iny
 bra :r
:rend
 lda rd_cfg
 cmp #2
 bne :nl
 lda #rd_m3
 jsr rd_puts
:nl
 lda #$0D
 jsr vid_tty
 lda #$0A
 jsr vid_tty
 lda #$FFFF
 sta tty_attr
:end
 lda #$0D
 jsr vid_tty
 lda #$0A
 jmp vid_tty

rd_puts                    ; A = a zero-ended string in this bank
 mx %00
 sta sv3
 ldy #0
:l
 lda (sv3),y
 and #$00FF
 beq :out
 phy
 jsr vid_tty
 ply
 iny
 bra :l
:out
 rts

*=== getting into DOS ========================================
* rd_poll - once a frame. State 1: DOS has set INT 21h (the
* vector left the BIOS segment and stood still for a frame):
* hook21 goes in front of it. State 2: the kernel set its
* vector again over the hook: in front again.
*
* When DOS boots from the share (rd_early) this is also run
* at every BIOS call (svc_hypercall) and does not wait for
* the frame: the kernel sets its vectors and then prints its
* name and asks for the disks, all before it looks for a
* drive, so hook21 is in by then. It stays in, and is
* watched, until the shell's EXEC (rd_int21).
rd_poll
 mx %00
 lda rd_state
 cmp #1
 beq :wait
 cmp #2
 beq :watch
 lda rd_early
 bne :watch
 rts
:wait
 lda >H_IVT+$86
 cmp #BIOS_SEG
 beq :out
 ldx rd_early
 bne :take
 cmp rd_ivt21+2
 bne :sample
 lda >H_IVT+$84
 cmp rd_ivt21
 bne :sample
:take
 lda >H_IVT+$84
 sta rd_old21
 lda >H_IVT+$86
 sta rd_old21+2
:hook
 lda rd_old21
 sta >H_BIOS+RD_OFF+9
 lda rd_old21+2
 sta >H_BIOS+RD_OFF+11
 lda #RD_OFF
 sta >H_IVT+$84
 lda #BIOS_SEG
 sta >H_IVT+$86
 lda rd_state
 cmp #1
 bne :out
 lda #2
 sta rd_state
 sta >RD_STATE
 rts
:sample
 lda >H_IVT+$84
 sta rd_ivt21
 lda >H_IVT+$86
 sta rd_ivt21+2
:out
 rts
:watch
 lda >H_IVT+$84
 cmp rd_old21
 bne :out
 lda >H_IVT+$86
 cmp rd_old21+2
 bne :out
 bra :hook

* rd_int21 - hypercall 256, from hook21 before DOS sees the
* call. The first EXEC (the kernel loading the shell) runs
* the install stub first.
*
* When DOS boots from the share the kernel needs the drive
* long before that, to read its configuration and load the
* shell, and it builds its drive table twice on the way
* (FreeDOS's FsConfig, before and after CONFIG.SYS), wiping
* the entry each time. So the install stub runs at the first
* call that goes through DOS's dispatcher proper (33h, 50h,
* 51h, 62h and 64h are answered on the caller's stack, and
* the kernel's first call is a 50h with no PSP set yet), and
* from then until the shell's EXEC every call looks at the
* entry first and marks it again (rd_mark).
rd_int21
 mx %00
 lda rd_state
 cmp #2
 beq :first
 cmp #4
 bne :out
 lda rd_early
 beq :out
 jsr rd_mark
 sta sv4
 lda rAX
 cmp #$4B00
 bne :out
 stz rd_early              ; the shell: DOS is whole, the entry stays
 lda sv4
 beq :unhook
 sta >RD_DIAG
 lda #5
 sta rd_state
:unhook
 jmp rd_unhook
:first
 lda rd_early
 bne :early
 lda rAX
 cmp #$4B00
 bne :out
:inst
 lda #3
 sta rd_state
 sta >RD_STATE
 lda #RD_INST
 sta rIP
:out
 rts
:early
 lda rAX
 cmp #$4B00                ; the shell already: the last try
 bne :pick
 stz rd_early
 bra :inst
:pick
 and #$FF00
 cmp #$3300
 beq :out
 cmp #$5000
 beq :out
 cmp #$5100
 beq :out
 cmp #$6200
 beq :out
 cmp #$6400
 beq :out
 bra :inst

* rd_install - hypercall 258, from the install stub: the DOS
* version at SS:SP+4, the list of lists' address at SS:SP+0,
* DS:SI the swappable data area. The drive's CDS entry must
* be free; it becomes a network drive at its root (rd_mark).
* When DOS boots from the share the table may not be there
* yet: rd_int21 goes on marking.
rd_install
 mx %00
 lda rd_state
 cmp #3
 beq :go
 rts
:go
 lda #5
 sta rd_state
 ldx #bSS
 lda rSP
 jsr gptr
 ldy #4
 lda [pGST],y
 and #$00FF
 cmp #4                    ; DOS 4 or later: the layouts above
 bcs :ver
 lda rd_early              ; (a kernel still starting has no version
 beq :old                  ; to give: the next call asks again)
 lda #2
 sta rd_state
 sta >RD_STATE
 rts
:old
 lda #1
 bra :fail
:ver
 lda [pGST]
 sta sv0
 ldy #2
 lda [pGST],y
 sta sv1
 jsr rd_farptr             ; the list of lists
 lda pGST
 sta rd_lol
 lda pGST+2
 sta rd_lol+2
 ldx #bDS
 lda rSI
 jsr gptr
 lda pGST
 sta rd_sda
 lda pGST+2
 sta rd_sda+2
 jsr rd_mark
 cmp #0
 beq :marked
 ldx rd_early
 beq :fail
:marked
 lda >H_IVT+$BC            ; INT 2Fh
 sta >H_BIOS+RD_OFF+$1B
 lda >H_IVT+$BE
 sta >H_BIOS+RD_OFF+$1D
 lda #RD_OFF+$0D
 sta >H_IVT+$BC
 lda #BIOS_SEG
 sta >H_IVT+$BE
 lda #4
 sta rd_state
 lda rd_early              ; booting from the share: hook21 stays
 beq rd_unhook
 lda #4
 sta >RD_STATE
 rts
:fail
 sta >RD_DIAG
 stz rd_early

* rd_unhook - INT 21h is DOS's again
rd_unhook
 mx %00
 lda rd_state
 sta >RD_STATE
 lda >H_IVT+$84
 cmp #RD_OFF
 bne :nop
 lda >H_IVT+$86
 cmp #BIOS_SEG
 bne :nop
 lda rd_old21
 sta >H_IVT+$84
 lda rd_old21+2
 sta >H_IVT+$86
 rts
:nop                       ; someone hooked it after us: the stub only chains
 lda #$9090
 sta >H_BIOS+RD_OFF
 sta >H_BIOS+RD_OFF+2
 rts

* rd_mark - the drive's CDS entry (58h bytes each, from the
* list of lists) becomes a network drive at its root.
* A = 0 done (or it is one already, while DOS boots from the
* share), 2 the drive is past LASTDRIVE or there is no table,
* 3 the entry is in use.
rd_mark
 mx %00
 lda rd_lol
 sta pGST
 lda rd_lol+2
 sta pGST+2
 ldy #$21
 lda [pGST],y
 and #$00FF
 sta sv2                   ; LASTDRIVE
 lda rd_drive
 cmp sv2
 bcs :past
 ldy #$18
 lda [pGST],y
 sta sv1
 ldy #$16
 lda [pGST],y
 sta sv0
 ora sv1
 beq :past
 lda rd_drive
 asl
 asl
 asl
 sta sv3                   ; * 8
 asl
 clc
 adc sv3
 sta sv3                   ; * 24
 lda rd_drive
 xba
 lsr
 lsr                       ; * 64
 clc
 adc sv3
 clc
 adc sv0
 sta sv0
 jsr rd_farptr
 ldy #$43
 lda [pGST],y
 and #$C000                ; a drive DOS has itself, or another redirector's
 beq :free
 cmp #$C000
 bne :used
 lda rd_early              ; ours, from an earlier call
 bne :ok
:used
 lda #3
 rts
:past
 lda #2
 rts
:free
 lda rd_drive
 clc
 adc #'A'
 ora #$3A00
 sta [pGST]                ; "C:"
 ldy #2
 lda #$005C
 sta [pGST],y              ; "\", 0
 ldy #$43
 lda #$C000                ; network + physical
 sta [pGST],y
 lda #0
 ldy #$45
 sta [pGST],y              ; no DPB
 ldy #$47
 sta [pGST],y
 ldy #$4F
 lda #2
 sta [pGST],y              ; the root's backslash
:ok
 lda #0
 rts

* rd_farptr - the guest's sv1:sv0 -> pGST
rd_farptr
 mx %00
 lda sv1
 asl
 asl
 asl
 asl
 clc
 adc sv0
 sta pGST
 php
 lda sv1
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 plp
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pGST+2
 rts

*=== INT 2Fh AH=11h ==========================================
* rd_int2f - hypercall 257, from hook2F with AH = 11h. A
* handler that answers ends in rd_ok or rd_fail (the stub's
* IRET); one that returns leaves the call to the chain.
* pARG = the swappable data area throughout.
rd_int2f
 mx %00
 lda rd_state
 cmp #4
 bne :chain
 lda rAX
 and #$00FF
 cmp #$2F
 bcs :chain
 sta rd_fn
 asl
 tax
 lda rd_sda
 sta pARG
 lda rd_sda+2
 sta pARG+2
 stz rd_wr
 jmp (rd_ftab,x)
:chain
 rts
rd_ftab
 da rd_none,rd_rmdir,rd_none,rd_mkdir      ; 00
 da rd_none,rd_chdir,rd_close,rd_commit    ; 04
 da rd_read,rd_write,rd_lock,rd_lock       ; 08
 da rd_space,rd_none,rd_setattr,rd_getattr ; 0C
 da rd_none,rd_rename,rd_none,rd_delete    ; 10
 da rd_none,rd_none,rd_open,rd_create      ; 14
 da rd_none,rd_none,rd_none,rd_ffirst      ; 18
 da rd_fnext,rd_none,rd_none,rd_none       ; 1C
 da rd_none,rd_seek,rd_none,rd_none        ; 20
 da rd_none,rd_none,rd_none,rd_none        ; 24
 da rd_none,rd_none,rd_none,rd_none        ; 28
 da rd_none,rd_none,rd_extopen             ; 2C
rd_none                    ; not answered: DOS's own answer stands
 mx %00
 lda rd_fn
 ora #$FF00
 jmp rd_note

rd_ok
 mx %00
 lda rd_fn
 jsr rd_note
 jsr clr_cf
 lda #RD_DONE
 sta rIP
 rts
rd_fail                    ; A = the DOS error
 mx %00
 and #$00FF
 pha
 xba
 ora rd_fn
 jsr rd_note
 pla
 sta rAX
 jsr set_cf
 lda #RD_DONE
 sta rIP
 rts
* rd_note - A = function | DOS error << 8 ($FF: passed on) into
* RD_LAST and the ring of the last 32 at RD_LOG
rd_note
 mx %00
 sta >RD_LAST
 pha
 lda >RD_CALLS
 and #$001F
 asl
 tax
 pla
 sta >RD_LOG,x
 lda >RD_CALLS
 inc
 sta >RD_CALLS
 rts
rd_perr                    ; A = the ProDOS error
 mx %00
 jsr perr
 bra rd_fail

* rd_ownpath - C clear when the first filename is on the drive
rd_ownpath
 mx %00
 ldy #SDA_FN1
 lda [pARG],y
 sec
 sbc #$3A41                ; "A:"
 cmp rd_drive
 beq :yes
 sec
 rts
:yes
 clc
 rts

* rd_path - the filename at SDA + A (past its "C:") -> the
* partial pathname at PATHBUF0 (X = 0) or PATHBUF1 ($40), its
* last component in rd_n83. C set, A = DOS error: the root,
* a name ProDOS cannot hold, a device.
rd_path
 mx %00
 clc
 adc pARG
 sta pGST
 lda pARG+2
 adc #0
 sta pGST+2
 phx
 ldy #0
:v                         ; letters, digits, dots (and a search's wildcards)
 lda [pGST],y
 and #$00FF
 beq :vend
 cmp #'\'
 beq :vok
 cmp #'.'
 beq :vok
 cmp #'?'
 beq :vok
 cmp #'0'
 bcc :vbad
 cmp #'9'+1
 bcc :vok
 cmp #'A'
 bcc :vbad
 cmp #'Z'+1
 bcs :vbad
:vok
 iny
 bra :v
:vbad
 plx
 lda #5                    ; access denied
 sec
 rts
:vend
 plx
 jsr dos_path
 bcs :out
 lda sv7
 cmp #$FFFF
 bne :vdev
 jsr last_comp             ; X = its start, sv8 = its length
 lda sv8
 cmp #16
 bcc :len
 lda #15
:len
 sta sv9
 txa
 clc
 adc sv6
 tax
 ldy #0
 sep #$20
 mx %10
 lda sv9
 sta tmpname
:c
 cpy sv9
 bcs :cd
 lda >PATHBUF0+1,x
 sta tmpname+1,y
 inx
 iny
 bra :c
:cd
 rep #$20
 mx %00
 jsr split83
 ldx #0
:n
 lda name83,x
 sta rd_n83,x
 inx
 inx
 cpx #12
 bcc :n
 clc
:out
 rts
:vdev
 lda #5
 sec
 rts

* rd_sft - pDTA = the SFT at ES:DI; C clear when it is a file
* of ours
rd_sft
 mx %00
 ldx #bES
 lda rDI
 jsr gptr
 lda pGST
 sta pDTA
 lda pGST+2
 sta pDTA+2
 ldy #SFT_FLAGS
 lda [pDTA],y
 bpl :no                   ; bit 15: a network file
 and #$001F
 cmp rd_drive
 bne :no
 clc
 rts
:no
 sec
 rts

* rd_slot - X = the SFT's handle entry * 8; C set when it is
* not an open file
rd_slot
 mx %00
 ldy #SFT_SLOT
 lda [pDTA],y
 cmp #NHANDLES*8
 bcs :bad
 tax
 and #$0007
 bne :bad
 lda htab,x
 and #$00FF
 cmp #H_FILE
 bne :bad
 stx rd_ent
 clc
 rts
:bad
 sec
 rts

* rd_stkarg - A = the word the kernel pushed before INT 2Fh
rd_stkarg
 mx %00
 lda rSP
 clc
 adc #6
 ldx #bSS
 jsr gptr
 lda [pGST]
 rts

* rd_xfer - pGST = the transfer address (the SDA's DTA pointer)
rd_xfer
 mx %00
 ldy #SDA_DTA
 lda [pARG],y
 sta sv0
 ldy #SDA_DTA+2
 lda [pARG],y
 sta sv1
 jmp rd_farptr

*=== files ===================================================
* 1116h open: the mode byte is the pushed word
rd_open
 mx %00
 jsr rd_ownpath
 bcc :mine
 rts
:mine
 lda #SDA_FN1+2
 ldx #0
 jsr rd_path
 bcs :fail
 jsr rd_stkarg
 and #$007F
 sta rd_mode
 ldx #0
 jsr p_getinfo
 bcs :perr
 jsr rd_openit
 bcs :fail
 jmp rd_ok
:perr
 jmp rd_perr
:fail
 jmp rd_fail

* 1117h create or truncate: the pushed word is the attribute,
* bit 8 set for "only if it is not there" (INT 21h AH=5Bh)
rd_create
 mx %00
 jsr rd_ownpath
 bcc :mine
 rts
:mine
 lda #SDA_FN1+2
 ldx #0
 jsr rd_path
 bcs :fail
 jsr rd_stkarg
 sta rd_arg
 ldx #0
 jsr p_getinfo
 bcs :new
 lda rd_arg
 and #$0100
 beq :new
 lda #$50                  ; file exists
:fail
 jmp rd_fail
:new
 jsr rd_make
 bcs :fail
 jmp rd_ok

* 112Eh extended open (INT 21h AX=6C00h): action, attribute
* and mode are in the SDA; CX = 1 opened, 2 created, 3 replaced
rd_extopen
 mx %00
 jsr rd_ownpath
 bcc :mine
 rts
:mine
 lda #SDA_FN1+2
 ldx #0
 jsr rd_path
 bcs :fail
 ldy #SDA_XMODE
 lda [pARG],y
 and #$007F
 sta rd_mode
 ldy #SDA_XACT
 lda [pARG],y
 sta rd_arg
 ldx #0
 jsr p_getinfo
 bcs :missing
 lda rd_arg                ; it exists: fail, open or replace
 and #$000F
 cmp #1
 beq :open
 cmp #2
 beq :replace
 lda #$50
:fail
 jmp rd_fail
:open
 jsr rd_openit
 bcs :fail
 lda #1
 bra :done
:replace
 jsr rd_make
 bcs :fail
 lda #3
 bra :done
:missing
 cmp #$46                  ; anything but "file not found" is an error
 beq :nofile
 jmp rd_perr
:nofile
 lda rd_arg
 and #$0010
 bne :make
 lda #2
 bra :fail
:make
 jsr rd_make
 bcs :fail
 lda #2
:done
 sta rCX
 jmp rd_ok

* rd_make - create the file at PATHBUF0, or empty the one
* that is there, and open it for reading and writing.
* C set, A = DOS error.
rd_make
 mx %00
 stz rd_trunc
 ldx #0
 jsr p_getinfo
 bcs :create
 lda >MB_MLI_PARMS+4       ; there already: not a directory, not locked
 and #$00FF
 cmp #$0F
 beq :denied
 lda >MB_MLI_PARMS+3
 and #$0002
 beq :denied
 inc rd_trunc
 bra :open
:create
 ldx #0
 jsr p_create
 bcs :perr
 ldx #0
 jsr p_getinfo
 bcs :perr
:open
 lda #2
 sta rd_mode
 jsr rd_openit
 bcs :out
 lda rd_trunc
 beq :ok
 stz sv8
 stz sv9
 ldx rd_ent
 jsr p_seteof
 bcs :cut
 ldx #bES
 lda rDI
 jsr gptr
 lda #0
 ldy #SFT_SIZE
 sta [pGST],y
 ldy #SFT_SIZE+2
 sta [pGST],y
:ok
 clc
:out
 rts
:cut                       ; it would not be cut: not opened either
 pha
 ldx rd_ent
 jsr p_close
 pla
:perr
 jsr perr
 sec
 rts
:denied
 lda #5
 sec
 rts

* rd_openit - open the file at PATHBUF0, whose GET_FILE_INFO
* list is at MB_MLI_PARMS, and fill the SFT at ES:DI.
* C set, A = DOS error.
rd_openit
 mx %00
 lda >MB_MLI_PARMS+4
 and #$00FF
 cmp #$0F                  ; a directory is not a file
 bne :file
 lda #5
 sec
 rts
:file
 lda #$0020                ; archive; read-only when ProDOS will not write it
 sta rd_attr
 lda >MB_MLI_PARMS+3
 and #$0002
 bne :rw
 inc rd_attr
:rw
 lda >MB_MLI_PARMS+12
 jsr ptime_dos
 sta rd_time
 lda >MB_MLI_PARMS+10
 jsr pdate_dos
 sta rd_date
 ldx #0
 lda rd_mode
 jsr p_open
 bcc :open
 rts
:open
 stx rd_ent
 jsr p_geteof              ; sv8, sv9
 ldx #bES
 lda rDI
 jsr gptr
 lda rd_mode
 ldy #SFT_MODE
 sta [pGST],y
 lda rd_drive              ; flags: network, not written, the drive
 ora #$8040
 ldy #SFT_FLAGS
 sta [pGST],y
 lda #0
 ldy #SFT_FLAGS+2
 sta [pGST],y              ; no device or DPB
 ldy #SFT_FLAGS+4
 sta [pGST],y
 ldy #SFT_POS
 sta [pGST],y
 ldy #SFT_POS+2
 sta [pGST],y
 lda rd_ent
 ldy #SFT_SLOT
 sta [pGST],y
 lda rd_time
 ldy #SFT_TIME
 sta [pGST],y
 lda rd_date
 ldy #SFT_DATE
 sta [pGST],y
 lda sv8
 ldy #SFT_SIZE
 sta [pGST],y
 lda sv9
 and #$00FF
 ldy #SFT_SIZE+2
 sta [pGST],y
 sep #$20
 mx %10
 lda rd_attr
 ldy #SFT_ATTR
 sta [pGST],y
 ldx #0
 ldy #SFT_NAME
:n
 lda rd_n83,x
 sta [pGST],y
 iny
 inx
 cpx #11
 bcc :n
 rep #$20
 mx %00
 clc
 rts

* 1106h close: the SFT's count is ours to bring down; at zero
* the ProDOS file closes
rd_close
 mx %00
 jsr rd_sft
 bcc :mine
 rts
:mine
 lda [pDTA]
 beq :last
 dec
 sta [pDTA]
 bne :ok
:last
 jsr rd_slot
 bcs :ok
 jsr p_close
:ok
 jmp rd_ok

* 1107h commit
rd_commit
 mx %00
 jsr rd_sft
 bcc :mine
 rts
:mine
 jsr rd_slot
 bcs :ok
 lda #1
 sta >MB_MLI_PARMS
 jsr h_ref
 lda #$CD                  ; FLUSH
 jsr mli
:ok
 jmp rd_ok

* 110Ah/110Bh lock and unlock a region: nobody else is here
rd_lock
 mx %00
 jsr rd_sft
 bcc :mine
 rts
:mine
 jmp rd_ok

* rd_seekpos - the ProDOS mark to the SFT's position. X =
* the entry. C set: A = DOS error, or 0 for a read at or
* past the end (a write there lengthens the file first).
rd_seekpos
 mx %00
 jsr rd_slot
 bcc :open
 lda #6                    ; invalid handle
 sec
 rts
:open
 ldy #SFT_POS
 lda [pDTA],y
 sta sv8
 ldy #SFT_POS+2
 lda [pDTA],y
 sta sv9
 cmp #$0100                ; ProDOS files end at 16 MB
 bcs :past
 jsr p_setmark
 bcc :ok
 cmp #$4D                  ; past the end
 bne :perr
 lda rd_wr
 beq :past
 jsr p_seteof
 bcs :perr
 jsr p_setmark
 bcs :perr
:ok
 clc
 rts
:past
 lda rd_wr
 bne :full
 sec                       ; (A = 0)
 rts
:full
 lda #5
 sec
 rts
:perr
 jsr perr
 sec
 rts

* 1108h read: CX bytes at the SFT's position to the transfer
* address; CX = the bytes read, and the position moves
rd_read
 mx %00
 jsr rd_sft
 bcc :mine
 rts
:mine
 jsr rd_seekpos
 bcc :at
 cmp #0
 beq :none
:fail
 jmp rd_fail
:none
 stz rCX
 jmp rd_ok
:at
 jsr rd_xfer
 lda rCX
 sta sv0
 ldx rd_ent
 jsr p_read
 bcs :fail
 sta rCX
 jsr rd_advance
 jmp rd_ok

* 1109h write; CX = 0 cuts the file off at the position
rd_write
 mx %00
 jsr rd_sft
 bcc :mine
 rts
:mine
 inc rd_wr
 jsr rd_seekpos
 bcc :at
 jmp rd_fail
:at
 jsr rd_xfer
 lda rCX
 sta sv0
 ldx rd_ent
 jsr p_write
 bcc :done
 jmp rd_fail
:done
 ldx rCX                   ; (asked for: zero is the truncation)
 sta rCX
 jsr rd_advance            ; sv8, sv9 = the position now
 ldy #SFT_FLAGS            ; written
 lda [pDTA],y
 and #$FFBF
 sta [pDTA],y
 txa
 beq :size
 ldy #SFT_SIZE+2           ; the file grew?
 lda sv9
 cmp [pDTA],y
 bcc :ok
 bne :size
 ldy #SFT_SIZE
 lda sv8
 cmp [pDTA],y
 bcc :ok
:size
 ldy #SFT_SIZE
 lda sv8
 sta [pDTA],y
 ldy #SFT_SIZE+2
 lda sv9
 sta [pDTA],y
:ok
 jmp rd_ok

* rd_advance - the SFT's position += A; sv8, sv9 = it
rd_advance
 mx %00
 clc
 ldy #SFT_POS
 adc [pDTA],y
 sta [pDTA],y
 sta sv8
 ldy #SFT_POS+2
 lda [pDTA],y
 adc #0
 sta [pDTA],y
 sta sv9
 rts

* 1121h seek from the end: CX:DX the offset; DX:AX = the
* position (the kernel stores it)
rd_seek
 mx %00
 jsr rd_sft
 bcc :mine
 rts
:mine
 jsr rd_slot
 bcc :open
 lda #6
 jmp rd_fail
:open
 jsr p_geteof
 lda sv8
 clc
 adc rDX
 sta rAX
 lda sv9
 and #$00FF
 adc rCX
 sta rDX
 jmp rd_ok

*=== directories and names ===================================
* 1101h remove a directory (ProDOS refuses one with files in it)
rd_rmdir
 mx %00
 jsr rd_ownpath
 bcc :mine
 rts
:mine
 lda #SDA_FN1+2
 ldx #0
 jsr rd_path
 bcs :fail
 ldx #0
 jsr p_getinfo
 bcs :perr
 lda >MB_MLI_PARMS+4
 and #$00FF
 cmp #$0F
 beq :dir
 lda #3
:fail
 jmp rd_fail
:dir
 jsr p_destroy
 bcs :perr
 jmp rd_ok
:perr
 jmp rd_perr

* 1103h make a directory
rd_mkdir
 mx %00
 jsr rd_ownpath
 bcc :mine
 rts
:mine
 lda #SDA_FN1+2
 ldx #0
 jsr rd_path
 bcc :name
 jmp rd_fail
:name
 lda #7
 sta >MB_MLI_PARMS
 lda #PATHBUF0
 sta >MB_MLI_PARMS+1
 lda #$0FC3                ; access $C3, type $0F
 sta >MB_MLI_PARMS+3
 lda #0
 sta >MB_MLI_PARMS+5
 lda #$000D                ; storage type: a directory (the date is ProDOS's)
 sta >MB_MLI_PARMS+7
 lda #0
 sta >MB_MLI_PARMS+9
 sta >MB_MLI_PARMS+11
 lda #$C0
 jsr mli
 bcs :err
 jmp rd_ok
:err
 cmp #$47                  ; it is there already
 beq :denied
 jmp rd_perr
:denied
 lda #5
 jmp rd_fail

* 1105h change directory: only whether it is one (the kernel
* keeps the path)
rd_chdir
 mx %00
 jsr rd_ownpath
 bcc :mine
 rts
:mine
 ldy #SDA_FN1+2
 lda [pARG],y
 cmp #$005C                ; "\": the share itself
 beq :ok
 lda #SDA_FN1+2
 ldx #0
 jsr rd_path
 bcs :no
 ldx #0
 jsr p_getinfo
 bcs :no
 lda >MB_MLI_PARMS+4
 and #$00FF
 cmp #$0F
 bne :no
:ok
 jmp rd_ok
:no
 lda #3
 jmp rd_fail

* 1113h delete a file
rd_delete
 mx %00
 jsr rd_ownpath
 bcc :mine
 rts
:mine
 lda #SDA_FN1+2
 ldx #0
 jsr rd_path
 bcs :fail
 ldx #0
 jsr p_getinfo
 bcs :perr
 lda >MB_MLI_PARMS+4
 and #$00FF
 cmp #$0F
 bne :file
 lda #5
:fail
 jmp rd_fail
:file
 jsr p_destroy
 bcs :perr
 jmp rd_ok
:perr
 jmp rd_perr

* 1111h rename: the first filename to the second. ProDOS
* renames within a directory.
rd_rename
 mx %00
 jsr rd_ownpath
 bcc :mine
 rts
:mine
 lda #SDA_FN1+2
 ldx #0
 jsr rd_path
 bcs :fail
 lda #SDA_FN2+2
 ldx #$40
 jsr rd_path
 bcs :fail
 jsr p_rename
 bcs :err
 jmp rd_ok
:err
 cmp #$47                  ; the new name is taken
 beq :denied
 jmp rd_perr
:denied
 lda #5
:fail
 jmp rd_fail

* 110Fh get the attributes: AX. A locked ProDOS file is
* read-only.
rd_getattr
 mx %00
 jsr rd_ownpath
 bcc :mine
 rts
:mine
 lda #SDA_FN1+2
 ldx #0
 jsr rd_path
 bcc :name
 jmp rd_fail
:name
 ldx #0
 jsr p_getinfo
 bcc :info
 jmp rd_perr
:info
 lda >MB_MLI_PARMS+4
 and #$00FF
 cmp #$0F
 bne :file
 lda #$10
 bra :set
:file
 lda >MB_MLI_PARMS+3
 and #$0002
 beq :ro
 lda #$20
 bra :set
:ro
 lda #$21
:set
 sta rAX
 jmp rd_ok

* 110Eh set the attributes (the pushed word): read-only
* locks the file, anything else unlocks it
rd_setattr
 mx %00
 jsr rd_ownpath
 bcc :mine
 rts
:mine
 lda #SDA_FN1+2
 ldx #0
 jsr rd_path
 bcc :name
 jmp rd_fail
:name
 jsr rd_stkarg
 sta rd_arg
 ldx #0
 jsr p_getinfo
 bcs :perr
 lda >MB_MLI_PARMS+3       ; access, and the type above it
 ora #$00C3
 sta sv8
 lda rd_arg
 and #$0001
 beq :wr
 lda sv8
 and #$FF3D                ; no write, rename or destroy
 sta sv8
:wr
 lda #7                    ; (the pathname is at the page's start)
 sta >MB_MLI_PARMS
 lda sv8
 sta >MB_MLI_PARMS+3
 lda #$C3                  ; SET_FILE_INFO: the rest as GET left it
 jsr mli
 bcs :perr
 jmp rd_ok
:perr
 jmp rd_perr

* 110Ch disk space: ES:DI the drive's CDS entry. AL sectors
* a cluster, AH the media byte, BX clusters, CX bytes a
* sector, DX clusters free: the ProDOS volume's blocks.
rd_space
 mx %00
 ldx #bES
 lda rDI
 jsr gptr
 lda [pGST]
 and #$00FF
 sec
 sbc #'A'
 cmp rd_drive
 beq :mine
 rts
:mine
 lda rd_root               ; "/VOL" of the share's pathname
 and #$00FF
 sta sv0
 ldx #2
:v
 cpx sv0
 beq :vc
 bcs :vend
:vc
 lda rd_root,x
 and #$00FF
 cmp #'/'
 beq :vend
 inx
 bra :v
:vend
 dex
 stx sv0                   ; its length
 sep #$20
 mx %10
 txa
 sta >PATHBUF0
 ldx #1
:cp
 cpx sv0
 beq :cc
 bcs :cpd
:cc
 lda rd_root,x
 sta >PATHBUF0,x
 inx
 bra :cp
:cpd
 rep #$20
 mx %00
 ldx #0
 jsr p_getinfo
 bcs :guess
 lda >MB_MLI_PARMS+5       ; a volume's auxiliary type: its blocks
 beq :guess
 sta rBX
 sec
 sbc >MB_MLI_PARMS+8       ; the blocks in use
 bcc :guess
 sta rDX
 bra :out
:guess
 lda #$FFFF
 sta rBX
 lda #$8000
 sta rDX
:out
 lda #512
 sta rCX
 lda #$0001                ; AL: sectors a cluster. AH, the media byte, stays 0:
 sta rAX                   ; FreeDOS's AX=7303h takes all of AX as the cluster size
 jmp rd_ok

*=== searches ================================================
* The search block DOS keeps for us is at the transfer
* address: +0 the drive (bit 7: ours to continue), +1 the
* pattern (8 + 3), +0Ch the attributes asked for, +0Dh the
* next entry in the block, +0Eh the block, +0Fh the
* directory: its slot in rd_dirs and, above that, the
* slot's generation. The directory entry found goes after
* it, at +15h. DOS never says a search is over, so the
* directory is opened and closed for every entry; its
* pathname waits in one of RD_NDIRS slots, and a search
* whose slot has gone to another directory ends.

* 111Bh find first: the first filename is the pattern
rd_ffirst
 mx %00
 jsr rd_ownpath
 bcc :mine
 rts
:mine
 ldy #SDA_SATTR
 lda [pARG],y
 and #$00FF
 sta rd_attr
 cmp #$08                  ; the volume label alone: there is none
 bne :files
:none
 lda #$12
 jmp rd_fail
:files
 lda #SDA_FN1+2
 ldx #0
 jsr rd_path
 bcs :none
 jsr last_comp             ; X = the pattern's start, sv8 = its length
 stx sv3
 jsr rd_xfer
 lda pGST
 sta pDTA
 lda pGST+2
 sta pDTA+2
 jsr pattern_fill
 lda sv3                   ; the directory: what is before the pattern's slash
 beq :dlen
 dec
:dlen
 sta sv4                   ; (0: the share itself)
 sep #$20
 mx %10
 sta rd_dpath
 ldx #0
:dc
 cpx sv4
 bcs :dcd
 lda >PATHBUF0+1,x
 sta rd_dpath+1,x
 inx
 bra :dc
:dcd
 rep #$20
 mx %00
 stz sv0                   ; a slot that has this directory?
:slot
 lda sv0
 xba
 lsr
 lsr
 tax
 ldy #0
 sep #$20
 mx %10
:cmp
 lda rd_dirs,x
 cmp rd_dpath,y
 bne :differs
 inx
 iny
 cpy sv4
 bcc :cmp
 beq :cmp
 rep #$20
 mx %00
 bra :have
:differs
 rep #$20
 mx %00
 inc sv0
 lda sv0
 cmp #RD_NDIRS
 bcc :slot
 lda rd_dnext              ; no: the next slot round, for a new search
 sta sv0
 inc
 and #RD_NDIRS-1
 sta rd_dnext
 lda sv0
 asl
 tax
 inc rd_dgen,x
 lda sv0
 xba
 lsr
 lsr
 tax
 ldy #0
 sep #$20
 mx %10
:put
 lda rd_dpath,y
 sta rd_dirs,x
 inx
 iny
 cpy sv4
 bcc :put
 beq :put
 rep #$20
 mx %00
:have
 lda sv0
 asl
 tax
 lda rd_dgen,x
 xba
 and #$FF00
 ora sv0
 ldy #$0F
 sta [pDTA],y              ; slot | generation << 8
 lda #0
 ldy #$0D
 sta [pDTA],y              ; entry 0 of block 0
 sep #$20
 mx %10
 lda rd_drive
 ora #$80
 sta [pDTA]
 lda rd_attr
 ldy #$0C
 sta [pDTA],y
 rep #$20
 mx %00
 jmp rd_fwalk

* 111Ch find next
rd_fnext
 mx %00
 jsr rd_xfer
 lda pGST
 sta pDTA
 lda pGST+2
 sta pDTA+2
 lda [pDTA]
 and #$00FF
 sec
 sbc #$0080
 cmp rd_drive
 beq rd_fwalk
 rts

* rd_fwalk - on from the search block at pDTA to the next
* entry that matches; the call's answer
rd_fwalk
 mx %00
 ldy #$0F
 lda [pDTA],y
 sta sv0
 and #$00FF
 cmp #RD_NDIRS
 bcc :slot
 jmp :nomore
:slot
 sta rd_fdir
 asl
 tax
 lda rd_dgen,x
 eor sv0+1                 ; (a byte each)
 and #$00FF
 beq :gen
 jmp :nomore
:gen
 lda rd_fdir
 xba
 lsr
 lsr
 tay
 lda rd_dirs,y
 and #$00FF
 bne :sub
 jsr prefix_to_path0       ; the share itself
 bra :open
:sub
 inc
 sta sv0                   ; its bytes, the length's too
 ldx #0
 sep #$20
 mx %10
:cp
 lda rd_dirs,y
 sta >PATHBUF0,x
 iny
 inx
 cpx sv0
 bcc :cp
 rep #$20
 mx %00
:open
 ldx #0
 lda #0
 jsr p_open
 bcc :block
 jmp :nomore
:block
 stx rd_ent
 ldy #$0E
 lda [pDTA],y
 and #$00FF
 sta rd_fblk
 cmp #$0080                ; (block 128 is 64 KB in: no directory here)
 bcc :seek
 jmp :end
:seek
 xba
 asl                       ; * 512
 sta sv8
 stz sv9
 ldx rd_ent
 jsr p_setmark
 bcc :read
 jmp :end
:read
 lda #4
 sta >MB_MLI_PARMS
 ldx rd_ent
 jsr h_ref
 lda #BOUNCEBUF
 sta >MB_MLI_PARMS+2
 lda #512
 sta >MB_MLI_PARMS+4
 lda #$CA
 jsr mli
 bcc :got
 jmp :end
:got
 lda >MB_MLI_PARMS+6
 cmp #512
 bcs :entry
 jmp :end
:entry                     ; 13 entries of 39 bytes from offset 4
 ldy #$0D
 lda [pDTA],y
 and #$00FF
 cmp #13
 bcc :in
 jmp :nextblock
:in
 sta sv3
 asl
 asl
 asl
 asl
 asl
 sta sv9                   ; * 32
 lda sv3
 asl
 asl
 clc
 adc sv9
 sta sv9                   ; * 36
 lda sv3
 asl
 clc
 adc sv9
 clc
 adc sv3                   ; * 39
 clc
 adc #4
 tax
 stx sv6                   ; the entry's offset in the block
 sep #$20
 mx %10
 lda sv3
 inc
 sta [pDTA],y              ; the next one, for the next call
 rep #$20
 mx %00
 lda rd_fblk               ; block 0's first is the directory's header
 ora sv3
 beq :entry
 lda >BOUNCEBUF,x
 and #$000F
 beq :entry                ; deleted
 sta sv4                   ; the name's length
 lda >BOUNCEBUF,x
 and #$00F0
 cmp #$00D0
 beq :dir
 cmp #$0040                ; storage types 1-3: a file's data
 bcs :entry                ; (a forked file has no DOS reading)
 lda #$0020
 sta sv5
 lda >BOUNCEBUF+$1E,x      ; access: locked is read-only
 and #$0002
 bne :name
 inc sv5
 bra :name
:dir                       ; directories when the search asks for them
 ldy #$0C
 lda [pDTA],y
 and #$0010
 beq :entry
 sta sv5
:name
 jsr entry_name            ; -> tmpname
 jsr rd_clean83            ; DOS could not name it: not shown
 bcc :lr2
 jmp :entry
:lr2
 jsr name_match            ; -> name83
 bcs :lr3
 jmp :entry
:lr3
 ldy #$15                  ; the directory entry: name,
 ldx #0
 sep #$20
 mx %10
:nm
 lda name83,x
 sta [pDTA],y
 iny
 inx
 cpx #11
 bcc :nm
 lda sv5
 ldy #$20                  ; attribute,
 sta [pDTA],y
 rep #$20
 mx %00
 ldx sv6
 lda >BOUNCEBUF+$23,x
 jsr ptime_dos
 ldy #$2B                  ; time,
 sta [pDTA],y
 ldx sv6
 lda >BOUNCEBUF+$21,x
 jsr pdate_dos
 ldy #$2D                  ; date,
 sta [pDTA],y
 lda sv5
 and #$0010
 bne :found                ; (a directory's size is 0)
 ldx sv6
 lda >BOUNCEBUF+$15,x
 ldy #$31                  ; size
 sta [pDTA],y
 lda >BOUNCEBUF+$17,x
 and #$00FF
 ldy #$33
 sta [pDTA],y
:found
 ldx rd_ent
 jsr p_close
 jmp rd_ok
:nextblock
 sep #$20
 mx %10
 lda #0
 ldy #$0D
 sta [pDTA],y
 lda rd_fblk
 inc
 ldy #$0E
 sta [pDTA],y
 rep #$20
 mx %00
 ldx rd_ent
 jmp :block
:end
 ldx rd_ent
 jsr p_close
:nomore
 lda #$12
 jmp rd_fail

* rd_clean83 - C clear when tmpname reads as a DOS name: one
* dot at most, 1-8 characters before it and 1-3 after
rd_clean83
 mx %00
 lda tmpname
 and #$00FF
 sta sv7
 ldx #0
 ldy #$FFFF                ; where the dot is
:l
 cpx sv7
 bcs :end
 lda tmpname+1,x
 and #$00FF
 cmp #'.'
 bne :n
 cpy #$FFFF
 bne :bad
 txy
:n
 inx
 bra :l
:end
 cpy #$FFFF
 bne :dot
 lda sv7
 cmp #9                    ; no extension: 8 at most
 rts
:dot
 cpy #1
 bcc :bad
 cpy #9
 bcs :bad
 tya
 inc
 sta sv8
 lda sv7
 sec
 sbc sv8                   ; the extension's length
 beq :bad
 cmp #4
 rts
:bad
 sec
 rts
