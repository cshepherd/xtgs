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
 jsr parse_cmd
 jsr state_init
 jsr init_shr
 jsr vid_clear
 jsr flush
 plb
 lda #PSP_SEG
 rtl

init_diag
 mx %00
 lda #0
 sta >CAP_LEN
 sta >DIAG_UNHN
 sta >DIAG_LAST
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
 lda #$009A                ; 04: 00, 05: CALL FAR F000:CALL5_OFF
 sta >H_PSP+4
 lda #CALL5_OFF
 sta >H_PSP+6
 lda #BIOS_SEG
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
 stz tick_acc
 stz vbl_count
 stz key_pending
 stz stop_flag
 stz exit_code
 lda #$FFFF
 sta tty_attr
 lda #PSP_SEG+$1000
 sta alloc_next
 lda #PSP_SEG
 sta dta_seg
 lda #$80
 sta dta_off
 stz vVBL
 rts
