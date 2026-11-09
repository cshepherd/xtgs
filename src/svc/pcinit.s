*----------------------------------------------------------
* pcinit.s - build the PC the program sees (Mode A): the
* interrupt vector table pointing every vector at a stub in
* the BIOS segment, the stubs themselves (hypercall + IRET),
* the BIOS data area, the PSP with the command tail from
* XTGS.CMD, the environment block, video mode 3.
* Returns A = PSP_SEG.
*----------------------------------------------------------
svc_pcinit
 mx %00
 phb
 phk
 plb
 jsr init_diag
 jsr build_stubs
 jsr build_ivt
 jsr build_bda
 jsr build_psp
 jsr build_env
 jsr build_dosdata
 jsr parse_cmd
 jsr state_init
 jsr handle_init
 jsr get_prefix
 jsr psp_fcbs
 jsr redirect_setup
 jsr load_program
 jsr init_shr
 jsr vid_clear
 jsr flush
 plb
 lda #PSP_SEG
 rtl

* build_dosdata - what programs peek at through INT 21h/1Fh and 52h:
* a drive parameter block, a list of lists whose first MCB is the
* one block below the PSP covering the program's memory.
build_dosdata
 mx %00
 ldx #0
 lda #0
:z
 sta >H_DOSDATA,x
 inx
 inx
 cpx #$100
 bcc :z
 ldx #DPB_OFF              ; DPB: drive 2 (C), unit 0, 512 bytes a sector,
 lda #$0002
 sta >H_DOSDATA,x
 lda #512
 sta >H_DOSDATA+2,x
 lda #$0403                ; 4 sectors a cluster (3, shift 2)... as DOS stores: sectors-1, shift
 sta >H_DOSDATA+4,x
 lda #1                    ; reserved sectors
 sta >H_DOSDATA+6,x
 lda #$0002                ; 2 FATs, root entries low
 sta >H_DOSDATA+8,x
 lda #$0002
 sta >H_DOSDATA+9,x
 lda #$00E0                ; 224 root entries
 sta >H_DOSDATA+9,x
 lda #$0021                ; first data sector
 sta >H_DOSDATA+11,x
 lda #$0FFF                ; highest cluster
 sta >H_DOSDATA+13,x
 lda #$0008                ; sectors a FAT (byte), first dir sector follows
 sta >H_DOSDATA+15,x
 lda #$0019
 sta >H_DOSDATA+16,x
 ldx #LOL_OFF
 lda #MCB_FIRST
 sta >H_DOSDATA-2,x        ; LOL-2: segment of the first MCB
 lda #DPB_OFF              ; LOL+0: DPB pointer
 sta >H_DOSDATA,x
 lda #DOSDATA_SEG
 sta >H_DOSDATA+2,x
 ; the MCB: 'Z', owner PSP, size up to the top of memory
 lda #$005A
 sta >H_MCB
 lda #PSP_SEG
 sta >H_MCB+1
 lda #TOP_PARA-PSP_SEG
 sta >H_MCB+3
 rts

* get_prefix - the ProDOS prefix (the DOS root) into PREFIXBUF
get_prefix
 mx %00
 lda #1
 sta >MB_MLI_PARMS
 lda #PREFIXBUF
 sta >MB_MLI_PARMS+1
 lda #$C7
 jmp mli

* psp_fcbs - the tail's first two arguments parsed into the PSP's FCBs
psp_fcbs
 mx %00
 lda #$0081
 sta pARG
 lda #^H_PSP
 sta pARG+2
 lda #$005C
 sta pGST
 lda #^H_PSP
 sta pGST+2
 lda #1
 sta sv4
 jsr parse_fcb
 lda pARG
 clc
 adc sv5
 sta pARG
 lda #$006C
 sta pGST
 lda #1
 sta sv4
 jmp parse_fcb

* redirect_setup - "< FILE" / "> FILE" in the tail: open them as handles
* 0 / 1 and cut them out of the tail.
redirect_setup
 mx %00
 ldx #0                    ; X = offset in the tail text (PSP+81)
:scan
 txa
 cmp >H_PSP+$80            ; (count byte, 16-bit read: low byte)
 pha
 lda >H_PSP+$80
 and #$00FF
 sta sv9
 pla
 cmp sv9
 bcc :more
 jmp :done
:more
 lda >H_PSP+$81,x
 and #$00FF
 cmp #'<'
 beq :redir
 cmp #'>'
 beq :redir
 inx
 bra :scan
:redir
 sta sv6                   ; which
 stx sv5                   ; where it starts
 inx
:sp
 lda >H_PSP+$81,x
 and #$00FF
 cmp #' '
 bne :name
 inx
 bra :sp
:name
 ldy #0
:nm
 lda >H_PSP+$81,x
 and #$00FF
 beq :nmdone
 cmp #' '
 beq :nmdone
 cmp #$0D
 beq :nmdone
 sta tmpname,y
 inx
 iny
 cpy #14
 bcc :nm
:nmdone
 lda #0
 sta tmpname,y
 ; cut [sv5, x) from the tail: shift the rest down
 phx
 lda >H_PSP+$80
 and #$00FF
 sta sv9                   ; count
 ldy sv5
:shift
 txa
 cmp sv9
 bcs :cut
 lda >H_PSP+$81,x
 sta sv8
 phx
 tyx
 sep #$20
 mx %10
 lda sv8
 sta >H_PSP+$81,x
 rep #$20
 mx %00
 plx
 inx
 iny
 bra :shift
:cut
 plx                       ; the new count
 txa
 sec
 sbc sv5
 sta sv8
 lda sv9
 sec
 sbc sv8
 sta sv9
 sep #$20
 mx %10
 lda sv9
 sta >H_PSP+$80
 lda #$0D
 tyx
 sta >H_PSP+$81,x
 rep #$20
 mx %00
 ; open it
 lda #tmpname
 sta pGST
 lda #^tmpname
 sta pGST+2
 ldx #0
 jsr dos_path
 bcs :next
 lda sv6
 cmp #'>'
 beq :out
 ldx #0
 lda #0
 jsr p_open
 bcs :next
 ldy #0
 bra :install
:out
 ldx #0
 jsr p_create
 bcs :next
 ldx #0
 lda #1
 jsr p_open
 bcs :next
 ldy #8
:install                   ; entry X moves onto handle Y (0 or 8)
 lda htab,x
 sta htab,y
 lda htab+2,x
 sta htab+2,y
 lda htab+3,x
 sta htab+3,y
 stz htab,x
 txa
 lsr
 lsr
 lsr
 sta sv2
 tya
 lsr
 lsr
 lsr
 sta sv3
 jsr hpath_copy
:next
 ldx sv5
 jmp :scan
:done
 rts

* load_program - the file the loader put at PSP:0100: a .COM, or an
* MZ .EXE to relocate. Sets the entry registers.
load_program
 mx %00
 lda >H_COM
 cmp #'ZM'                 ; "MZ"
 beq :exe
 cmp #'MZ'                 ; "ZM"
 beq :exe
 lda #PSP_SEG
 sta rCS
 sta rSS
 sta rDS
 sta rES
 lda #$100
 sta rIP
 lda #$FFFE
 sta rSP
 lda #0
 sta >H_PSP+$FFFE          ; the word a RET at the end finds: PSP:0000 = INT 20h
 lda #PSP_SEG+$1000
 sta alloc_next
 rts
:exe
 lda >H_COM+8              ; header paragraphs
 asl
 asl
 asl
 asl
 sta sv0                   ; header bytes
 lda >H_COM+4              ; pages
 dec
 xba
 asl                       ; (pages-1)*512
 sta sv1
 lda >H_COM+4
 dec
 and #$0080
 beq :nohi
 lda #1
 bra :hi
:nohi
 lda #0
:hi
 sta sv2                   ; total size high byte
 lda >H_COM+2              ; bytes in the last page (0 = 512)
 bne :last
 lda #512
:last
 clc
 adc sv1
 sta sv1
 bcc :nc
 inc sv2
:nc
 ; image size = total - header: sv2:sv1 - sv0
 lda sv1
 sec
 sbc sv0
 sta sv1
 lda sv2
 sbc #0
 sta sv2
 ; move sv2:sv1 bytes from H_COM+sv0 down to H_COM
 jsr exe_move
 ; relocations: count at +6, table at +$18 (header-relative, so from H_COM+off - already moved!)
 ; (the table was inside the header: read it from where the header was... it has been
 ;  overwritten only if the image covers it: copy the table first — done inside exe_move)
 jsr exe_reloc
 lda #PSP_SEG+$10
 clc
 adc exe_cs
 sta rCS
 lda exe_ip
 sta rIP
 lda #PSP_SEG+$10
 clc
 adc exe_ss
 sta rSS
 lda exe_sp
 sta rSP
 lda #PSP_SEG
 sta rDS
 sta rES
 ; the program's block: image paragraphs + minimum extra, from the load segment
 lda sv1
 clc
 adc #15
 sta sv8
 lda sv2
 adc #0
 lsr                       ; (sv2:sv8) >> 4 -> paragraphs
 ror sv8
 lsr
 ror sv8
 lsr
 ror sv8
 lsr
 ror sv8
 lda sv8
 clc
 adc #PSP_SEG+$10
 clc
 adc exe_minalloc
 sta alloc_next
 rts
exe_cs     dw 0
exe_ip     dw 0
exe_ss     dw 0
exe_sp     dw 0
exe_minalloc dw 0
exe_nreloc dw 0
exe_reltab ds 4            ; host pointer of the relocation table (saved copy)

* exe_move - save the header fields, copy the relocation table to
* RELSAVE (bank $05), then move the image down over the header.
RELSAVE    = RES_BASE+$2000
exe_move
 mx %00
 lda >H_COM+$16
 sta exe_cs
 lda >H_COM+$14
 sta exe_ip
 lda >H_COM+$0E
 sta exe_ss
 lda >H_COM+$10
 sta exe_sp
 lda >H_COM+$0A
 sta exe_minalloc
 lda >H_COM+6
 sta exe_nreloc
 ; relocation table -> RELSAVE (4 bytes an entry, up to 2048 entries)
 lda >H_COM+$18
 clc
 adc #H_COM
 sta pGST
 lda #^H_COM
 adc #0
 sta pGST+2
 lda exe_nreloc
 asl
 asl
 sta sv9
 ldy #0
:r
 cpy sv9
 bcs :moved
 lda [pGST],y
 tyx
 sta >RELSAVE,x
 iny
 iny
 bra :r
:moved
 ; memmove: src = H_COM + sv0, dst = H_COM, len = sv2:sv1, forward, in bank-safe MVN chunks
 lda #H_COM
 sta pTXT                  ; dst (lo16), bank in pTXT+2
 lda #^H_COM
 sta pTXT+2
 lda #H_COM
 clc
 adc sv0
 sta pCELL                 ; src
 lda #^H_COM
 adc #0
 sta pCELL+2
:chunk
 lda sv1
 ora sv2
 bne :lj1
 jmp :done
:lj1
 ; chunk = min(len, $10000 - src_off, $10000 - dst_off), as a 16-bit count (0 = 65536 not needed: cap at $8000)
 lda #$8000
 sta sv3
 lda sv2
 bne :cap
 lda sv1
 cmp sv3
 bcs :cap
 sta sv3
:cap
 lda pCELL
 eor #$FFFF
 inc                       ; $10000 - src_off (0 when src_off = 0 -> full)
 beq :srcok
 cmp sv3
 bcs :srcok
 sta sv3
:srcok
 lda pTXT
 eor #$FFFF
 inc
 beq :dstok
 cmp sv3
 bcs :dstok
 sta sv3
:dstok
 lda pCELL+2
 sep #$20
 mx %10
 sta :mvn+2                ; source bank
 lda pTXT+2
 sta :mvn+1                ; destination bank
 rep #$20
 mx %00
 phb
 ldx pCELL
 ldy pTXT
 lda sv3
 dec
:mvn
 dfb $54,$00,$00
 plb
 lda pCELL
 clc
 adc sv3
 sta pCELL
 bcc :s1
 inc pCELL+2
:s1
 lda pTXT
 clc
 adc sv3
 sta pTXT
 bcc :d1
 inc pTXT+2
:d1
 lda sv1
 sec
 sbc sv3
 sta sv1
 lda sv2
 sbc #0
 sta sv2
 jmp :chunk
:done
 rts
* exe_reloc - add the load segment to each far pointer the table names
exe_reloc
 mx %00
 lda exe_nreloc
 beq :done
 sta sv9
 ldx #0
:e
 lda >RELSAVE+2,x          ; segment
 clc
 adc #PSP_SEG+$10
 sta sv8                   ; absolute segment
 asl
 asl
 asl
 asl
 clc
 adc >RELSAVE,x            ; + offset
 sta pGST
 lda sv8
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 adc #0                    ; carry from the offset add
 and #$000F
 ora #GUEST_BANK
 sta pGST+2
 lda [pGST]
 clc
 adc #PSP_SEG+$10
 sta [pGST]
 inx
 inx
 inx
 inx
 dec sv9
 bne :e
:done
 rts

init_diag
 mx %00
 lda #0
 sta >CAP_LEN
 sta >DIAG_UNHN
 sta >DIAG_LAST
 ldx #0
:z
 sta >DIAG_FNMAP,x
 inx
 inx
 cpx #48
 bcc :z
 lda #$FFFF
 sta >DIAG_UNH
 rts

* build_stubs - 256 x "FE 38 vec 00 CF" at F000:0000, the call-5
* target, the reset vector (HLT) and the BIOS signature bytes.
build_stubs
 mx %00
 ldx #0
 stz sv0
 sep #$20
 mx %10
:s
 lda #$FE
 sta >H_BIOS,x
 inx
 lda #$38
 sta >H_BIOS,x
 inx
 lda sv0
 sta >H_BIOS,x
 inx
 lda #0
 sta >H_BIOS,x
 inx
 lda #$CF
 sta >H_BIOS,x
 inx
 inc sv0
 bne :s
 ldx #9*STUB_LEN           ; INT 09h (IRQ1) default handler: PUSH AX; IN AL,60h;
 lda #$50                  ; POP AX; IRET. Drains the scancode port so our queue
 sta >H_BIOS,x            ; advances when no guest handler is installed. It fires
 lda #$E4                  ; asynchronously, so it MUST preserve AX (an ISR that
 sta >H_BIOS+1,x           ; clobbers a live register corrupts the interrupted code).
 lda #$60
 sta >H_BIOS+2,x
 lda #$58
 sta >H_BIOS+3,x
 lda #$CF
 sta >H_BIOS+4,x
 lda #$CF                  ; INT 1Ch (the user timer hook): a bare IRET
 sta >H_BIOS+$8C           ; (1Ch * STUB_LEN)
 ldx #TICK_OFF             ; INT 08h (IRQ0): hypercall 8 (the BDA tick), then
 lda #$FE                  ; INT 1Ch as the BIOS does, so a program's hook on
 sta >H_BIOS,x             ; the user timer vector runs; IRET
 lda #$38
 sta >H_BIOS+1,x
 lda #$08
 sta >H_BIOS+2,x
 lda #$00
 sta >H_BIOS+3,x
 lda #$CD
 sta >H_BIOS+4,x
 lda #$1C
 sta >H_BIOS+5,x
 lda #$CF
 sta >H_BIOS+6,x
 ldx #CALL5_OFF            ; mov ah,cl / int 21h / retf
 lda #$88
 sta >H_BIOS,x
 lda #$CC
 sta >H_BIOS+1,x
 lda #$CD
 sta >H_BIOS+2,x
 lda #$21
 sta >H_BIOS+3,x
 lda #$CB
 sta >H_BIOS+4,x
 lda #$F4                  ; reset vector: HLT
 sta >H_BIOS+$FFF0
 lda #$FE                  ; PC model byte
 sta >H_BIOS+$FFFE
 ldx #0
:d
 lda bios_date,x
 beq :dd
 sta >H_BIOS+$FFF5,x
 inx
 bra :d
:dd
 rep #$20
 mx %00
 rts
bios_date asc '11/08/26',00

* build_ivt - vector n -> F000:(n*5)
build_ivt
 mx %00
 ldx #0
 stz sv0
:v
 lda sv0
 sta >H_IVT,x
 lda #BIOS_SEG
 sta >H_IVT+2,x
 lda sv0
 clc
 adc #STUB_LEN
 sta sv0
 inx
 inx
 inx
 inx
 cpx #1024
 bcc :v
 lda #TICK_OFF             ; INT 08h has the longer stub (it chains INT 1Ch)
 sta >H_IVT+$20
 rts

build_bda
 mx %00
 ldx #0
 lda #0
:z
 sta >H_BDA,x
 inx
 inx
 cpx #256
 bcc :z
 lda #$0021                ; 80x25 colour, one floppy
 sta >H_BDA+BDA_EQUIP
 lda #640
 sta >H_BDA+BDA_MEMKB
 lda #BDA_KBBUF
 sta >H_BDA+BDA_KBHEAD
 sta >H_BDA+BDA_KBTAIL
 lda #80
 sta >H_BDA+BDA_COLS
 lda #$1000
 sta >H_BDA+BDA_PGSIZE
 lda #$0607
 sta >H_BDA+BDA_CURSHP
 lda #$03D4
 sta >H_BDA+BDA_CRTC
 lda #8
 sta >H_BDA+BDA_CHARHT
 sep #$20
 mx %10
 lda #3
 sta >H_BDA+BDA_VMODE
 lda #24
 sta >H_BDA+BDA_ROWS
 rep #$20
 mx %00
 rts

* build_psp - the program segment prefix at PSP_SEG:0000
build_psp
 mx %00
 ldx #0
 lda #0
:z
 sta >H_PSP,x
 inx
 inx
 cpx #256
 bcc :z
 lda #$20CD                ; INT 20h
 sta >H_PSP
 lda #TOP_PARA
 sta >H_PSP+2
 lda #$9A00                ; 04: 00; 05: CALL FAR (9A), offset/segment below
 sta >H_PSP+4
 lda #$FFF0                ; 06: bytes available in the segment (programs like
 sta >H_PSP+6              ; EDLIN and SORT read DS:[6] to size their buffers);
 lda #BIOS_SEG             ; this doubles as the CALL 5 target offset
 sta >H_PSP+8
 lda #$22*STUB_LEN         ; 0A: INT 22h vector
 sta >H_PSP+$0A
 lda #BIOS_SEG
 sta >H_PSP+$0C
 lda #$23*STUB_LEN         ; 0E: INT 23h
 sta >H_PSP+$0E
 lda #BIOS_SEG
 sta >H_PSP+$10
 lda #$24*STUB_LEN         ; 12: INT 24h
 sta >H_PSP+$12
 lda #BIOS_SEG
 sta >H_PSP+$14
 lda #PSP_SEG              ; 16: parent PSP
 sta >H_PSP+$16
 lda #$0101                ; 18: job file table: stdin stdout stderr aux prn
 sta >H_PSP+$18
 lda #$0001
 sta >H_PSP+$1A
 lda #$FF02
 sta >H_PSP+$1C
 ldx #$1E
 lda #$FFFF
:jft
 sta >H_PSP,x
 inx
 inx
 cpx #$2C
 bcc :jft
 lda #ENV_SEG              ; 2C: environment
 sta >H_PSP+$2C
 lda #20                   ; 32: JFT size
 sta >H_PSP+$32
 lda #$0018                ; 34: JFT pointer PSP:0018
 sta >H_PSP+$34
 lda #PSP_SEG
 sta >H_PSP+$36
 lda #$FFFF                ; 38: previous PSP
 sta >H_PSP+$38
 sta >H_PSP+$3A
 lda #$21CD                ; 50: INT 21h / RETF
 sta >H_PSP+$50
 sep #$20
 mx %10
 lda #$CB
 sta >H_PSP+$52
 ldx #0                    ; 5C, 6C: blank FCBs (drive 0, name spaces)
 lda #$20
:fcb
 sta >H_PSP+$5D,x
 sta >H_PSP+$6D,x
 inx
 cpx #11
 bcc :fcb
 rep #$20
 mx %00
 rts

* build_env - PATH, COMSPEC, the count word, the program path
build_env
 mx %00
 ldx #0
 sep #$20
 mx %10
:e
 lda env_text,x
 sta >H_ENV,x
 inx
 cpx #env_text_len
 bcc :e
 rep #$20
 mx %00
 rts
env_text asc 'PATH=C:\',00,'COMSPEC=C:\COMMAND.COM',00,00,01,00,'C:\'
env_text_len = *-env_text

* parse_cmd - XTGS.CMD's line "C NAME args": NAME (uppercased) to
* the environment's program path, " args" to the PSP command tail.
parse_cmd
 mx %00
 lda >MB_CMD
 and #$00FF
 sta sv0                   ; length
 ldx #2                    ; past "C"
:sp1
 cpx sv0
 bcc :ok1
 jmp :noname
:ok1
 lda >MB_CMD+1,x
 and #$00FF
 cmp #' '
 bne :name
 inx
 bra :sp1
:name
 lda #H_ENV
 sta pGST
 lda #^H_ENV
 sta pGST+2
 ldy #env_text_len
:nm
 cpx sv0
 bcs :nmdone
 lda >MB_CMD+1,x
 and #$00FF
 cmp #' '
 beq :nmdone
 cmp #'a'
 bcc :up
 cmp #'z'+1
 bcs :up
 and #$5F
:up
 sta sv1
 sep #$20
 mx %10
 lda sv1
 sta [pGST],y
 rep #$20
 mx %00
 iny
 inx
 cpy #$F0
 bcc :nm
:nmdone
 sep #$20
 mx %10
 lda #0
 sta [pGST],y
 rep #$20
 mx %00
:sp2                       ; spaces before the tail
 cpx sv0
 bcc :ok2
 jmp :notail
:ok2
 lda >MB_CMD+1,x
 and #$00FF
 cmp #' '
 bne :tail
 inx
 bra :sp2
:tail
 lda #H_PSP
 sta pGST
 lda #^H_PSP
 sta pGST+2
 ldy #$81
 sep #$20
 mx %10
 lda #' '
 sta [pGST],y
 rep #$20
 mx %00
 iny
:tl
 cpx sv0
 bcs :tldone
 lda >MB_CMD+1,x
 sta sv1
 sep #$20
 mx %10
 lda sv1
 sta [pGST],y
 rep #$20
 mx %00
 iny
 inx
 cpy #$FF
 bcc :tl
:tldone
 tya
 sec
 sbc #$81
 sta sv1                   ; count
 sep #$20
 mx %10
 lda sv1
 sta >H_PSP+$80
 lda #$0D
 sta [pGST],y
 rep #$20
 mx %00
 rts
:noname
:notail
 sep #$20
 mx %10
 lda #0
 sta >H_PSP+$80
 lda #$0D
 sta >H_PSP+$81
 rep #$20
 mx %00
 rts

state_init
 mx %00
 stz cur_on
 stz blink
 stz vbl_count
 stz key_pending
 stz stop_flag
 stz exit_code
 lda #$FFFF
 sta tty_attr
 lda #PSP_SEG
 sta cur_psp
 sta dta_seg
 lda #$80
 sta dta_off
 stz vVBL
 rts
