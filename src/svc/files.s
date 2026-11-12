*----------------------------------------------------------
* files.s - the DOS file system on ProDOS 8, through the
* front end's file call (JSL MB_FILECALL with the command
* byte in MB_MLI_CMD and the parameter list at
* MB_MLI_PARMS; mailbox.s).
*
* DOS handles 0-4 are the devices (CON CON CON AUX PRN);
* 5-19 are files: a ProDOS ref number with a 1 KB I/O buffer
* in bank $00 (IOBUFS, eight of them: ProDOS 8's limit)
* and the ProDOS pathname (for attribute and date calls).
* Reads and writes move through the 8 KB bounce buffer
* (BOUNCEBUF). The MLI takes bank-$00 addresses, so these
* are the bank-$00 areas of layout.s, wherever the front
* end put them. DOS paths map onto the boot volume: the DOS
* root is the ProDOS prefix the loader set, "\" is "/",
* a drive letter is ignored, CON and NUL are devices.
*
* The FCB functions (DOS 1 style, used by EDLIN and DEBUG)
* sit on the handle layer: the handle lives in the FCB's
* reserved bytes.
*----------------------------------------------------------
PATHBUF0   = PATH_PAGE*$100  ; two 64-byte ProDOS pathnames (bank $00)
PATHBUF1   = PATHBUF0+$40
PREFIXBUF  = PATHBUF0+$80    ; the volume prefix (GET_PREFIX result)
IOBUFS     = IOB_PAGE*$100   ; 8 x 1 KB ProDOS I/O buffers
BOUNCEBUF  = XFER_PAGE*$100  ; 8 KB transfer buffer
BOUNCE_LEN = $2000
NHANDLES   = 20
H_FREE     = 0
H_DEVICE   = 1
H_FILE     = 2
DEV_CON    = 0
DEV_NUL    = 1
DEV_AUX    = 2
DEV_PRN    = 3

* handle table: 8 bytes an entry
*   +0 kind (H_*)  +1 ref (ProDOS) or device  +2 iobuf index  +3 mode
*   +4 share count (dups)  +5..7 unused
htab       ds NHANDLES*8
hpath      ds NHANDLES*64    ; ProDOS pathname (Pascal) per handle
iobuf_used ds 8
cwd        ds 66             ; DOS current directory, no leading "\", Pascal
fcb_ptr    dw 0              ; the current FCB (guest offset in DS)
err_dos    dw 0              ; last DOS error code
tmpname    ds 16
dp_pfx     dw 0              ; the shared drive's: names ProDOS cannot hold are respelt (dp_prefix)
dp_us      dw 0              ; this component had a "_"
dp_dot     dw 0              ; and a "."

*=== the MLI =================================================
* mli - A = command; the parameter list is already at
* MB_MLI_PARMS. Returns A = ProDOS error (0 ok), C set on error.
mli
 mx %00
 sta >MB_MLI_CMD
 jsl MB_FILECALL
 cmp #1                    ; C = (error != 0)
 rts

* perr - A = ProDOS error -> A = DOS error code
perr
 mx %00
 and #$00FF
 cmp #$46                  ; file not found
 bne :n1
 lda #2
 rts
:n1
 cmp #$44                  ; path not found
 bne :n2
 lda #3
 rts
:n2
 cmp #$40                  ; invalid pathname
 bne :n3
 lda #3
 rts
:n3
 cmp #$42                  ; too many files open
 bne :n4
 lda #4
 rts
:n4
 cmp #$4E                  ; access denied
 bne :n5
 lda #5
 rts
:n5
 cmp #$4B                  ; unsupported storage type (a directory as a file)
 bne :n6
 lda #5
 rts
:n6
 cmp #$48                  ; volume full
 bne :n7
 lda #$27                  ; insufficient disk space... DOS has no code; general failure
 rts
:n7
 cmp #$47                  ; duplicate filename
 bne :n8
 lda #$50                  ; file exists
 rts
:n8
 lda #$1F                  ; general failure
 rts

* dos_err - A = DOS error: AX = error, CF set
dos_err
 mx %00
 sta rAX
 sta err_dos
 jmp set_cf

*=== pathnames ===============================================
* dos_path - the ASCIIZ DOS path at [pGST] -> ProDOS pathname
* (Pascal) at bank-0 PATHBUF0 (X = 0) or PATHBUF1 (X = $40).
* Returns C set with A = DOS error when the name is unusable;
* sv7 = DEV_* device (A = $FFFF) for CON/NUL/AUX/PRN.
dos_path
 mx %00
 stx sv6                   ; destination offset in bank 0
 stz dp_us
 stz dp_dot
 lda #$FFFF
 sta sv7
 ldy #0
 lda [pGST],y              ; a drive letter?
 and #$00FF
 bne :some
 jmp :empty
:some
 iny
 lda [pGST],y
 and #$00FF
 cmp #':'
 bne :nodrive
 iny
 bra :start
:nodrive
 ldy #0
:start
 lda [pGST],y
 and #$00FF
 cmp #'\'
 bne :lj1
 jmp :absolute
:lj1
 cmp #'/'
 bne :lj2
 jmp :absolute
:lj2
 ; relative: start from the current directory
 ldx #0
 lda cwd
 and #$00FF
 sta sv5                   ; cwd length
 beq :rel0
 ldx #0
:cw
 lda cwd+1,x
 sta sv8
 phx
 txa
 clc
 adc sv6
 tax
 sep #$20
 mx %10
 lda sv8
 sta >PATHBUF0+1,x
 rep #$20
 mx %00
 plx
 inx
 cpx sv5
 bcc :cw
 lda #'/'
 sta sv8
 txa
 clc
 adc sv6
 tax
 sep #$20
 mx %10
 lda sv8
 sta >PATHBUF0+1,x
 rep #$20
 mx %00
 lda sv5
 inc
 sta sv5                   ; output length so far
 bra :copy
:rel0
 stz sv5
 bra :copy
:absolute
 iny
 stz sv5
:copy
 ; components: uppercase, '\' -> '/', '.' kept, "." and ".." handled, bad chars -> '.'
 lda [pGST],y
 and #$00FF
 bne :lj3
 jmp :done
:lj3
 cmp #'\'
 beq :sepj
 cmp #'/'
 bne :lj3b
:sepj
 jmp :sep
:lj3b
 cmp #'a'
 bcc :nolow
 cmp #'z'+1
 bcs :nolow
 and #$5F
:nolow
 cmp #'.'
 bne :nodot
 sta dp_dot
 bra :ok
:nodot
 cmp #'?'                  ; wildcards stay: find first takes the last component
 beq :ok                   ; as its pattern, and ProDOS refuses them anywhere else
 cmp #'*'
 beq :ok
 cmp #'0'
 bcc :bad
 cmp #'9'+1
 bcc :ok
 cmp #'A'
 bcc :bad
 cmp #'Z'+1
 bcc :ok
:bad
 cmp #'_'
 bne :bad2
 ldx dp_pfx
 beq :bad2
 jsr dp_under              ; the shared drive: "_" is kept as a "."
 bcc :bad2
 jmp :toolong
:bad2
 lda #'.'
:ok
 sta sv8
 cmp #'0'
 bcc :nopfx
 cmp #'9'+1
 bcs :nopfx
 jsr dp_prefix             ; a component may not start with a digit
 bcc :nopfx
 jmp :toolong
:nopfx
 lda sv5
 cmp #63
 bcc :room
 jmp :toolong
:room
 clc
 adc sv6
 tax
 sep #$20
 mx %10
 lda sv8
 sta >PATHBUF0+1,x
 rep #$20
 mx %00
 inc sv5
 iny
 jmp :copy
:sep
 iny
 jsr dp_close
 ; drop a "." component; ".." removes the previous one
 jsr path_dots
 lda sv5
 bne :lj5
 jmp :copy ; nothing yet: keep relative
:lj5
 lda #'/'
 sta sv8
 lda sv5
 clc
 adc sv6
 tax
 sep #$20
 mx %10
 lda sv8
 sta >PATHBUF0+1,x
 rep #$20
 mx %00
 inc sv5
 jmp :copy
:done
 jsr dp_close
 jsr path_dots
 ; a trailing '/' goes
 lda sv5
 beq :device
 dec
 clc
 adc sv6
 tax
 lda >PATHBUF0+1,x
 and #$00FF
 cmp #'/'
 bne :device
 dec sv5
:device
 jsr path_device           ; CON NUL AUX PRN -> sv7
 lda sv7
 cmp #$FFFF
 bne :isdev
 lda sv5
 beq :empty
 ldx sv6
 sep #$20
 mx %10
 lda sv5
 sta >PATHBUF0,x
 rep #$20
 mx %00
 clc
 rts
:isdev
 clc
 rts
:toolong
:empty
 lda #3                    ; path not found
 sec
 rts

* The shared drive's names (dp_pfx set by rd_path). ProDOS takes
* a letter, then letters, digits and dots; DOS names also start
* with digits and hold "_". So for that drive:
*   a "_" in the name's first part is stored as a ".", and a name
*   with one and no extension gets a "." at its end: every dot
*   but the last is an underscore (MW_MAIN.EXE is MW.MAIN.EXE,
*   A_B is A.B.);
*   a name that starts with a digit gets "X.." first (6X6.FNT is
*   X..6X6.FNT).
* rd_unname reads them back.

* dp_first - C set when the next character starts a component.
* Y kept.
dp_first
 mx %00
 lda sv5
 beq :yes
 dec
 clc
 adc sv6
 tax
 lda >PATHBUF0+1,x
 and #$00FF
 cmp #'/'
 beq :yes
 clc
 rts
:yes
 sec
 rts

* dp_prefix - a digit is about to be stored: "X.." before it when
* it starts a component. Y kept; C set when there is no room.
dp_prefix
 mx %00
 lda dp_pfx
 beq :no
 jsr dp_first
 bcc :no
 lda sv5
 cmp #60
 bcs :long
 clc
 adc sv6
 tax
 sep #$20
 mx %10
 lda #'X'
 sta >PATHBUF0+1,x
 lda #'.'
 sta >PATHBUF0+2,x
 sta >PATHBUF0+3,x
 rep #$20
 mx %00
 lda sv5
 clc
 adc #3
 sta sv5
:no
 clc
 rts
:long
 sec
 rts

* dp_under - a "_": C clear when it may be a "." (not the first
* character, which ProDOS would refuse, and not in the extension,
* which could not be told from the name). Y kept.
dp_under
 mx %00
 lda dp_dot
 bne :no
 jsr dp_first
 bcs :no
 inc dp_us
 clc
 rts
:no
 sec
 rts

* dp_close - a component ends: one with a "_" and no extension
* gets its last ".". Y kept.
dp_close
 mx %00
 lda dp_us
 beq :out
 lda dp_dot
 bne :out
 lda sv5
 cmp #63
 bcs :out
 clc
 adc sv6
 tax
 sep #$20
 mx %10
 lda #'.'
 sta >PATHBUF0+1,x
 rep #$20
 mx %00
 inc sv5
:out
 stz dp_us
 stz dp_dot
 rts

* path_dots - the last component of the path under construction
* (sv5 bytes at PATHBUF0+sv6) is "." or "..": remove it (and the
* component before it for "..").
path_dots
 mx %00
 lda sv5
 beq :out
 jsr last_comp             ; X = start offset of the last component, sv8 = its length
 lda sv8
 cmp #1
 beq :one
 cmp #2
 bne :out
 txa
 clc
 adc sv6
 tax
 lda >PATHBUF0+1,x
 and #$00FF
 cmp #'.'
 bne :out
 lda >PATHBUF0+2,x
 and #$00FF
 cmp #'.'
 bne :out
 ; "..": drop it and the previous component
 jsr last_comp
 stx sv5                   ; cut to the start of ".."
 lda sv5
 beq :out
 dec sv5                   ; and the '/' before it
 jsr last_comp
 stx sv5
 bra :out
:one
 txa
 clc
 adc sv6
 tax
 lda >PATHBUF0+1,x
 and #$00FF
 cmp #'.'
 bne :out
 jsr last_comp
 stx sv5
:out
 rts
last_comp                  ; X = offset where the last component starts, sv8 = length
 mx %00
 ldx sv5
 stz sv8
:back
 txa
 beq :found
 dex
 txa
 clc
 adc sv6
 phx
 tax
 lda >PATHBUF0+1,x
 and #$00FF
 plx
 cmp #'/'
 bne :more
 inx
 bra :found
:more
 inc sv8
 bra :back
:found
 rts

path_device                ; CON NUL AUX PRN (3 letters, whole path) -> sv7
 mx %00
 lda sv5
 cmp #3
 beq :lj7
 jmp :no
:lj7
 ldx sv6
 lda >PATHBUF0+1,x
 cmp #'CO'
 bne :n1
 lda >PATHBUF0+3,x
 and #$00FF
 cmp #'N'
 bne :no
 lda #DEV_CON
 sta sv7
 rts
:n1
 cmp #'NU'
 bne :n2
 lda >PATHBUF0+3,x
 and #$00FF
 cmp #'L'
 bne :no
 lda #DEV_NUL
 sta sv7
 rts
:n2
 cmp #'AU'
 bne :n3
 lda >PATHBUF0+3,x
 and #$00FF
 cmp #'X'
 bne :no
 lda #DEV_AUX
 sta sv7
 rts
:n3
 cmp #'PR'
 bne :no
 lda >PATHBUF0+3,x
 and #$00FF
 cmp #'N'
 bne :no
 lda #DEV_PRN
 sta sv7
:no
 rts

*=== handles ================================================
handle_init                ; devices on 0-4, the rest free
 mx %00
 ldx #0
 lda #0
:z
 sta htab,x
 inx
 inx
 cpx #NHANDLES*8
 bcc :z
 ldx #0
:dev
 lda #H_DEVICE             ; kind, device in the high byte
 sta htab,x
 txa
 clc
 adc #8
 tax
 cpx #5*8
 bcc :dev
 lda #DEV_AUX*256+H_DEVICE
 sta 3*8+htab               ; (left to right: htab+3*8 is (htab+3)*8)
 lda #DEV_PRN*256+H_DEVICE
 sta 4*8+htab
 ldx #0
 lda #0
:ib
 sta iobuf_used,x
 inx
 inx
 cpx #8
 bcc :ib
 stz cwd
 rts

* h_find_free - X = a free handle * 8; C set if none
h_find_free
 mx %00
 ldx #5*8
:l
 lda htab,x
 and #$00FF
 beq :got
 txa
 clc
 adc #8
 tax
 cpx #NHANDLES*8
 bcc :l
 sec
 rts
:got
 clc
 rts

* iobuf_alloc - A = free I/O buffer index (0-7); C set if none
iobuf_alloc
 mx %00
 ldx #0
:l
 lda iobuf_used,x
 and #$00FF
 beq :got
 inx
 cpx #8
 bcc :l
 sec
 rts
:got
 sep #$20
 mx %10
 lda #1
 sta iobuf_used,x
 rep #$20
 mx %00
 txa
 clc
 rts

* h_lookup - A = DOS handle -> X = entry * 8; C set when not open
h_lookup
 mx %00
 cmp #NHANDLES
 bcs :bad
 asl
 asl
 asl
 tax
 lda htab,x
 and #$00FF
 beq :bad
 clc
 rts
:bad
 sec
 rts

* p_open - open the ProDOS path at PATHBUF0 (X = 0 / PATHBUF1
* (X = $40); A = DOS access mode (ignored by ProDOS). Returns
* X = handle entry * 8 (C clear) or A = DOS error (C set).
p_open
 mx %00
 stx sv4                   ; which path buffer
 sta sv3
 jsr h_find_free
 bcc :h
 lda #4                    ; too many open files
 sec
 rts
:h
 stx sv2                   ; the entry
 jsr iobuf_alloc
 bcc :b
 lda #4
 sec
 rts
:b
 sta sv1                   ; buffer index
 ; OPEN: count 3, pathname, io_buffer, ref_num
 lda #3
 sta >MB_MLI_PARMS
 lda sv4
 clc
 adc #PATHBUF0
 sta >MB_MLI_PARMS+1
 lda sv1
 xba                       ; index * 1024 = index << 10
 asl
 asl
 clc
 adc #IOBUFS
 sta >MB_MLI_PARMS+3
 lda #$C8
 jsr mli
 bcs :err
 lda >MB_MLI_PARMS+5       ; ref_num
 and #$00FF
 xba
 ora #H_FILE
 ldx sv2
 sta htab,x
 lda sv1
 sta htab+2,x
 lda sv3
 xba
 and #$FF00
 ora #1                    ; share count 1
 sta htab+3,x
 ; keep the pathname for later info calls
 jsr h_savepath
 ldx sv2
 clc
 rts
:err
 pha
 ldx sv1
 sep #$20
 mx %10
 lda #0
 sta iobuf_used,x
 rep #$20
 mx %00
 pla
 jsr perr
 sec
 rts

h_savepath                 ; the path at PATHBUF0+sv4 -> hpath[sv2]
 mx %00
 lda sv2
 asl
 asl
 asl                       ; entry*8 -> *64
 tay
 ldx sv4
 lda >PATHBUF0,x
 and #$00FF
 sta sv8
 inc sv8
 ldx #0
:c
 phx
 txa
 clc
 adc sv4
 tax
 lda >PATHBUF0,x
 plx
 sta sv9
 sep #$20
 mx %10
 lda sv9
 sta hpath,y
 rep #$20
 mx %00
 iny
 inx
 cpx sv8
 bcc :c
 rts

* p_close - X = entry * 8: close the ProDOS file (last dup), free it
p_close
 mx %00
 lda htab+3,x
 and #$00FF
 cmp #2
 bcc :last
 dec
 sta sv8
 lda htab+3,x
 and #$FF00
 ora sv8
 sta htab+3,x
 stz htab,x                ; this entry goes; the file stays open for its dup
 clc
 rts
:last
 lda htab,x
 xba
 and #$00FF
 sta sv8                   ; ref
 lda #1
 sta >MB_MLI_PARMS
 lda sv8
 sta >MB_MLI_PARMS+1
 phx
 lda #$CC
 jsr mli
 plx
 pha
 lda htab+2,x
 and #$00FF
 phx
 tax
 sep #$20
 mx %10
 lda #0
 sta iobuf_used,x
 rep #$20
 mx %00
 plx
 stz htab,x
 pla
 cmp #1
 bcc :ok
 jsr perr
 sec
 rts
:ok
 clc
 rts

* h_ref - X = entry * 8 -> A = ref number (also into MB_MLI_PARMS+1)
h_ref
 mx %00
 lda htab,x
 xba
 and #$00FF
 sta >MB_MLI_PARMS+1
 rts

* p_read - X = entry*8, sv0 = bytes requested, pGST = guest
* destination. Returns A = bytes read (C clear) or DOS error (C set).
p_read
 mx %00
 stz sv1                   ; total
:chunk
 lda sv0
 beq :done
 cmp #BOUNCE_LEN+1
 bcc :n
 lda #BOUNCE_LEN
:n
 sta sv2                   ; this chunk
 phx
 lda #4
 sta >MB_MLI_PARMS
 jsr h_ref
 lda #BOUNCEBUF
 sta >MB_MLI_PARMS+2
 lda sv2
 sta >MB_MLI_PARMS+4
 lda #$CA
 jsr mli
 plx
 bcc :ok
 cmp #$4C                  ; EOF: what we have
 beq :done
 jsr perr
 sec
 rts
:ok
 lda >MB_MLI_PARMS+6       ; transferred
 sta sv3
 beq :done
 jsr bounce_to_guest       ; sv3 bytes at BOUNCEBUF -> [pGST], pGST advances
 lda sv1
 clc
 adc sv3
 sta sv1
 lda sv0
 sec
 sbc sv3
 sta sv0
 lda sv3
 cmp sv2
 bcc :done                 ; short read: EOF
 jmp :chunk
:done
 lda sv1
 clc
 rts

* p_write - X = entry*8, sv0 = bytes, pGST = guest source.
* A = bytes written (C clear) or DOS error (C set).
p_write
 mx %00
 stz sv1
 lda sv0
 bne :chunk
 ; zero bytes: truncate at the mark
 phx
 lda #2
 sta >MB_MLI_PARMS
 jsr h_ref
 lda #$CF                  ; GET_MARK
 jsr mli
 lda >MB_MLI_PARMS+2
 sta sv8
 lda >MB_MLI_PARMS+3
 sta sv9
 lda #2
 sta >MB_MLI_PARMS
 lda sv8
 sta >MB_MLI_PARMS+2
 lda sv9
 sta >MB_MLI_PARMS+3
 lda #$D0                  ; SET_EOF
 jsr mli
 plx
 lda #0
 clc
 rts
:chunk
 lda sv0
 beq :done
 cmp #BOUNCE_LEN+1
 bcc :n
 lda #BOUNCE_LEN
:n
 sta sv2
 sta sv3
 jsr guest_to_bounce       ; sv3 bytes from [pGST] -> BOUNCEBUF, pGST advances
 phx
 lda #4
 sta >MB_MLI_PARMS
 jsr h_ref
 lda #BOUNCEBUF
 sta >MB_MLI_PARMS+2
 lda sv2
 sta >MB_MLI_PARMS+4
 lda #$CB
 jsr mli
 plx
 bcc :ok
 jsr perr
 sec
 rts
:ok
 lda >MB_MLI_PARMS+6
 sta sv3
 lda sv1
 clc
 adc sv3
 sta sv1
 lda sv0
 sec
 sbc sv3
 sta sv0
 lda sv3
 cmp sv2
 bcc :done
 bra :chunk
:done
 lda sv1
 clc
 rts

* bounce_to_guest - sv3 bytes BOUNCEBUF -> [pGST]; pGST += sv3.
* X is preserved (the caller's handle entry, across chunks).
bounce_to_guest
 mx %00
 phx
 ldy #0
 ldx #0
 lda sv3
 lsr
 beq :odd
 sta sv9
:w
 lda >BOUNCEBUF,x
 sta [pGST],y
 inx
 inx
 iny
 iny
 dec sv9
 bne :w
:odd
 lda sv3
 and #1
 beq :adv
 lda >BOUNCEBUF,x
 sep #$20
 mx %10
 sta [pGST],y
 rep #$20
 mx %00
:adv
 lda pGST
 clc
 adc sv3
 sta pGST
 bcc :done
 inc pGST+2
:done
 plx
 rts

* guest_to_bounce - sv3 bytes [pGST] -> BOUNCEBUF; pGST += sv3.
* X is preserved.
guest_to_bounce
 mx %00
 phx
 ldy #0
 ldx #0
 lda sv3
 lsr
 beq :odd
 sta sv9
:w
 lda [pGST],y
 sta >BOUNCEBUF,x
 inx
 inx
 iny
 iny
 dec sv9
 bne :w
:odd
 lda sv3
 and #1
 beq :adv
 lda [pGST],y
 sep #$20
 mx %10
 sta >BOUNCEBUF,x
 rep #$20
 mx %00
:adv
 lda pGST
 clc
 adc sv3
 sta pGST
 bcc :done
 inc pGST+2
:done
 plx
 rts

* p_getmark / p_geteof - X = entry*8 -> sv8 (lo16), sv9 (hi byte)
p_getmark
 mx %00
 lda #2
 sta >MB_MLI_PARMS
 jsr h_ref
 lda #$CF
 bra p_get3
p_geteof
 mx %00
 lda #2
 sta >MB_MLI_PARMS
 jsr h_ref
 lda #$D1
p_get3
 mx %00
 phx
 jsr mli
 plx
 lda >MB_MLI_PARMS+2
 sta sv8
 lda >MB_MLI_PARMS+3
 xba
 and #$00FF
 sta sv9
 rts
* p_setmark / p_seteof - X = entry*8, sv8/sv9 = position
p_setmark
 mx %00
 lda #$CE
 bra p_set3
p_seteof
 mx %00
 lda #$D0
p_set3
 mx %00
 sta sv7
 lda #2
 sta >MB_MLI_PARMS
 jsr h_ref
 lda sv8
 sta >MB_MLI_PARMS+2
 lda sv9
 and #$00FF
 sep #$20
 mx %10
 sta >MB_MLI_PARMS+4
 rep #$20
 mx %00
 phx
 lda sv7
 jsr mli
 plx
 rts

* p_create - PATHBUF0 (X=0)/PATHBUF1 (X=$40): a new file (TXT),
* or truncate an existing one; A = ProDOS error (C set) or 0.
p_create
 mx %00
 stx sv4
 lda #7
 sta >MB_MLI_PARMS
 lda sv4
 clc
 adc #PATHBUF0
 sta >MB_MLI_PARMS+1
 lda #$04C3                ; access $C3, file type $04 TXT
 sta >MB_MLI_PARMS+3
 lda #0                    ; aux type
 sta >MB_MLI_PARMS+5
 lda #1                    ; storage type: standard file (date/time 0: ProDOS fills)
 sta >MB_MLI_PARMS+7
 lda #0
 sta >MB_MLI_PARMS+9
 sta >MB_MLI_PARMS+11
 lda #$C0
 jsr mli
 bcc :ok
 cmp #$47                  ; exists: truncate it
 bne :err
 ldx sv4
 lda #1
 jsr p_open
 bcs :err2
 stz sv8
 stz sv9
 jsr p_seteof
 jsr p_close
 lda #0
 clc
 rts
:err
 sec
 rts
:err2
 sec
 rts
:ok
 lda #0
 clc
 rts

* p_destroy - PATHBUF0 -> A = ProDOS error / 0
p_destroy
 mx %00
 lda #1
 sta >MB_MLI_PARMS
 lda #PATHBUF0
 sta >MB_MLI_PARMS+1
 lda #$C1
 jmp mli
* p_rename - PATHBUF0 -> PATHBUF1
p_rename
 mx %00
 lda #2
 sta >MB_MLI_PARMS
 lda #PATHBUF0
 sta >MB_MLI_PARMS+1
 lda #PATHBUF1
 sta >MB_MLI_PARMS+3
 lda #$C2
 jmp mli
* p_getinfo - PATHBUF0 (X=0) / PATHBUF1 (X=$40): GET_FILE_INFO into
* MB_MLI_PARMS (+3 access, +4 type, +5 aux, +7 storage, +8 blocks,
* +10 mod date, +12 mod time, +14 create date, +16 create time)
p_getinfo
 mx %00
 txa
 clc
 adc #PATHBUF0
 sta >MB_MLI_PARMS+1
 lda #$0A
 sta >MB_MLI_PARMS
 lda #$C4
 jmp mli

*=== DOS handle functions ====================================
* ds_dx_path - the DOS path at DS:DX -> PATHBUF0; C set + DOS error
ds_dx_path
 mx %00
 ldx #bDS
 lda rDX
 jsr gptr
 ldx #0
 jmp dos_path

dos_3C                     ; create (truncate), CX = attributes (ignored)
 mx %00
 jsr ds_dx_path
 bcs :fail
 lda sv7
 cmp #$FFFF
 bne dos_3D_dev
 ldx #0
 jsr p_create
 bcs :perr
 ldx #0
 lda #2
 jsr p_open
 bcs :fail
 jmp h_return
:perr
 jsr perr
:fail
 jmp dos_err
dos_5B                     ; create new: fails when it exists
 mx %00
 jsr ds_dx_path
 bcs :fail
 ldx #0
 jsr p_getinfo
 bcc :exists
 bra dos_3C
:exists
 lda #$50
:fail
 jmp dos_err
dos_3D                     ; open, AL = mode
 mx %00
 jsr ds_dx_path
 bcs :fail
 lda sv7
 cmp #$FFFF
 bne dos_3D_dev
 lda rAX
 and #$0007
 ldx #0
 jsr p_open
 bcs :fail
 jmp h_return
:fail
 jmp dos_err
dos_3D_dev                 ; a device: a device entry
 mx %00
 jsr h_find_free
 bcc :h
 lda #4
 jmp dos_err
:h
 lda sv7
 xba
 and #$FF00
 ora #H_DEVICE
 sta htab,x
 lda #1
 sta htab+3,x
h_return                   ; X = entry*8 -> AX = handle, CF clear
 mx %00
 txa
 lsr
 lsr
 lsr
 sta rAX
 jmp clr_cf
dos_3E                     ; close BX
 mx %00
 lda rBX
 jsr h_lookup
 bcs :bad
 lda htab,x
 and #$00FF
 cmp #H_FILE
 bne :dev
 jsr p_close
 bcs :err
 jmp clr_cf
:dev
 cpx #5*8                  ; the standard devices stay open
 bcc :ok
 stz htab,x
:ok
 jmp clr_cf
:err
 jmp dos_err
:bad
 lda #6
 jmp dos_err
dos_3F                     ; read BX, CX bytes to DS:DX
 mx %00
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
 cmp #DEV_CON
 beq :con
 stz rAX                   ; NUL AUX PRN: nothing to read
 jmp clr_cf
:con
 jmp dos_3F_con
:file
 lda rCX
 sta sv0
 phx
 ldx #bDS
 lda rDX
 jsr gptr
 plx
 jsr p_read
 bcs :err
 sta rAX
 jmp clr_cf
:err
 jmp dos_err
:bad
 lda #6
 jmp dos_err
dos_40                     ; write BX, CX bytes from DS:DX
 mx %00
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
 cmp #DEV_CON
 beq :con
 lda rCX                   ; NUL AUX PRN swallow it
 sta rAX
 jmp clr_cf
:con
 jmp dos_40_con
:file
 lda rCX
 sta sv0
 phx
 ldx #bDS
 lda rDX
 jsr gptr
 plx
 jsr p_write
 bcs :err
 sta rAX
 jmp clr_cf
:err
 jmp dos_err
:bad
 lda #6
 jmp dos_err
dos_42                     ; lseek BX: AL origin, CX:DX offset -> DX:AX
 mx %00
 lda rBX
 jsr h_lookup
 bcc :lj9
 jmp :bad
:lj9
 lda htab,x
 and #$00FF
 cmp #H_FILE
 beq :lj10
 jmp :dev
:lj10
 lda rAX
 and #$00FF
 beq :set                  ; from the start: CX:DX
 cmp #1
 beq :cur
 jsr p_geteof
 bra :add
:cur
 jsr p_getmark
:add
 lda sv8                   ; + CX:DX (signed 32; the result clamps at 0)
 clc
 adc rDX
 sta sv8
 lda sv9
 adc rCX
 sta sv9
 bpl :pos
 stz sv8
 stz sv9
 bra :pos
:set
 lda rDX
 sta sv8
 lda rCX
 sta sv9
:pos
 lda sv9
 and #$FF00
 beq :fits
 lda #$FFFF                ; beyond 16 MB: clamp
 sta sv8
 lda #$00FF
 sta sv9
:fits
 phx
 jsr p_setmark
 plx
 bcc :done
 cmp #$4D                  ; past EOF: extend, then seek
 bne :done
 jsr p_seteof
 jsr p_setmark
:done
 lda sv8
 sta rAX
 lda sv9
 and #$00FF
 sta rDX
 jmp clr_cf
:dev
 stz rAX
 stz rDX
 jmp clr_cf
:bad
 lda #6
 jmp dos_err
dos_43                     ; AL=0 get attributes -> CX; AL=1 set CX
 mx %00
 jsr ds_dx_path
 bcc :lj11
 jmp :fail
:lj11
 lda sv7
 cmp #$FFFF
 beq :lj12
 jmp :dev
:lj12
 ldx #0
 jsr p_getinfo
 bcc :lj13
 jmp :perr
:lj13
 lda rAX
 and #$00FF
 bne :set
 lda >MB_MLI_PARMS+3       ; access: bit 1 write enable; type $0F = directory
 and #$00FF
 sta sv8
 lda >MB_MLI_PARMS+4
 and #$00FF
 cmp #$0F
 bne :notdir
 lda #$10
 bra :attr
:notdir
 lda #$20                  ; archive
:attr
 sta sv9
 lda sv8
 and #$0002
 bne :rw
 lda sv9
 ora #1
 sta sv9
:rw
 lda sv9
 sta rCX
 jmp clr_cf
:set                       ; read-only bit -> access byte, via SET_FILE_INFO
 lda >MB_MLI_PARMS+3
 and #$00FF
 ora #$C3
 sta sv8
 lda rCX
 and #1
 beq :wr
 lda sv8
 and #$FF-$02
 sta sv8
:wr
 lda #7
 sta >MB_MLI_PARMS
 lda sv8
 sep #$20
 mx %10
 sta >MB_MLI_PARMS+3
 rep #$20
 mx %00
 lda >MB_MLI_PARMS+10      ; keep type/aux (already in place); mod date/time move up
 sta >MB_MLI_PARMS+10
 lda #$C3
 jsr mli
 bcs :perr
 jmp clr_cf
:dev
 lda #$20
 sta rCX
 jmp clr_cf
:perr
 jsr perr
:fail
 jmp dos_err
dos_45                     ; dup BX
 mx %00
 lda rBX
 jsr h_lookup
 bcs :bad
 stx sv2
 jsr h_find_free
 bcs :full
 ; copy the entry; a file's share count goes up on the original
 ldy sv2
 lda htab,y
 sta htab,x
 lda htab+2,y
 sta htab+2,x
 lda htab+3,y
 and #$FF00
 ora #1
 sta htab+3,x
 lda htab,y
 and #$00FF
 cmp #H_FILE
 bne :ret
 lda htab+3,y
 inc
 sta htab+3,y
 phx
 tya
 lsr
 lsr
 lsr
 sta sv2
 txa
 lsr
 lsr
 lsr
 sta sv3
 jsr hpath_copy            ; the pathname too
 plx
:ret
 jmp h_return
:full
 lda #4
 jmp dos_err
:bad
 lda #6
 jmp dos_err
hpath_copy                 ; hpath[sv2] -> hpath[sv3]
 mx %00
 lda sv2
 asl
 asl
 asl
 asl
 asl
 asl
 tax
 lda sv3
 asl
 asl
 asl
 asl
 asl
 asl
 tay
 lda #32
 sta sv9
:c
 lda hpath,x
 sta hpath,y
 inx
 inx
 iny
 iny
 dec sv9
 bne :c
 rts
dos_46                     ; force dup BX onto CX
 mx %00
 lda rCX
 jsr h_lookup
 bcs :free
 lda htab,x
 and #$00FF
 cmp #H_FILE
 bne :devfree
 jsr p_close
 bra :free
:devfree
 stz htab,x
:free
 lda rBX
 jsr h_lookup
 bcs :bad
 stx sv2
 lda rCX
 cmp #NHANDLES
 bcs :bad
 asl
 asl
 asl
 tax
 ldy sv2
 lda htab,y
 sta htab,x
 lda htab+2,y
 sta htab+2,x
 lda htab+3,y
 and #$FF00
 ora #1
 sta htab+3,x
 lda htab,y
 and #$00FF
 cmp #H_FILE
 bne :done
 lda htab+3,y
 inc
 sta htab+3,y
 tya
 lsr
 lsr
 lsr
 sta sv2
 txa
 lsr
 lsr
 lsr
 sta sv3
 jsr hpath_copy
:done
 jmp clr_cf
:bad
 lda #6
 jmp dos_err
dos_41                     ; delete DS:DX
 mx %00
 jsr ds_dx_path
 bcs :fail
 jsr p_destroy
 bcs :perr
 jmp clr_cf
:perr
 jsr perr
:fail
 jmp dos_err
dos_56                     ; rename DS:DX -> ES:DI
 mx %00
 jsr ds_dx_path
 bcs :fail
 ldx #bES
 lda rDI
 jsr gptr
 ldx #$40
 jsr dos_path
 bcs :fail
 jsr p_rename
 bcs :perr
 jmp clr_cf
:perr
 jsr perr
:fail
 jmp dos_err
dos_39                     ; mkdir
 mx %00
 jsr ds_dx_path
 bcs :fail
 lda #7
 sta >MB_MLI_PARMS
 lda #PATHBUF0
 sta >MB_MLI_PARMS+1
 lda #$0FC3                ; directory
 sta >MB_MLI_PARMS+3
 lda #0
 sta >MB_MLI_PARMS+5
 lda #$0D                  ; storage type: directory
 sta >MB_MLI_PARMS+7
 lda #0
 sta >MB_MLI_PARMS+9
 sta >MB_MLI_PARMS+11
 lda #$C0
 jsr mli
 bcs :perr
 jmp clr_cf
:perr
 jsr perr
:fail
 jmp dos_err
dos_3A                     ; rmdir
 mx %00
 bra dos_41
dos_3B                     ; chdir DS:DX
 mx %00
 jsr ds_dx_path
 bcc :lj14
 jmp :fail
:lj14
 lda sv5
 beq :root
 ldx #0
 jsr p_getinfo
 bcs :perr
 lda >MB_MLI_PARMS+4
 and #$00FF
 cmp #$0F
 bne :notdir
 ; the new cwd is the path we built (relative to the prefix), with '\'
 lda sv5
 cmp #64
 bcs :notdir
 sta cwd
 ldx #0
:c
 lda >PATHBUF0+1,x
 and #$00FF
 cmp #'/'
 bne :k
 lda #'\'
:k
 sta sv8
 sep #$20
 mx %10
 lda sv8
 sta cwd+1,x
 rep #$20
 mx %00
 inx
 cpx sv5
 bcc :c
 jmp clr_cf
:root
 stz cwd
 jmp clr_cf
:notdir
 lda #3
 jmp dos_err
:perr
 jsr perr
:fail
 jmp dos_err
dos_47                     ; getcwd -> DS:SI (ASCIIZ, no leading '\')
 mx %00
 ldx #bDS
 lda rSI
 jsr gptr
 lda cwd
 and #$00FF
 sta sv8
 ldy #0
:c
 cpy sv8
 bcs :end
 lda cwd+1,y
 sta sv9
 sep #$20
 mx %10
 lda sv9
 sta [pGST],y
 rep #$20
 mx %00
 iny
 bra :c
:end
 sep #$20
 mx %10
 lda #0
 sta [pGST],y
 rep #$20
 mx %00
 jmp clr_cf
dos_57                     ; AL=0 get file date/time of BX -> CX time, DX date
 mx %00
 lda rBX
 jsr h_lookup
 bcs :bad
 lda htab,x
 and #$00FF
 cmp #H_FILE
 bne :dev
 lda rAX
 and #$00FF
 bne :set
 jsr h_pathinfo
 bcs :perr
 lda >MB_MLI_PARMS+10      ; ProDOS mod date
 jsr pdate_dos
 sta rDX
 lda >MB_MLI_PARMS+12
 jsr ptime_dos
 sta rCX
 jmp clr_cf
:set
 jmp clr_cf                ; setting a timestamp: accepted, not done
:dev
 lda #0
 sta rCX
 lda #$0021                ; 1980-01-01
 sta rDX
 jmp clr_cf
:perr
 jsr perr
 jmp dos_err
:bad
 lda #6
 jmp dos_err
h_pathinfo                 ; X = entry*8: GET_FILE_INFO on its pathname (copied to PATHBUF1)
 mx %00
 txa
 asl
 asl
 asl
 tay
 ldx #0
:c
 lda hpath,y
 sta sv9
 sep #$20
 mx %10
 lda sv9
 sta >PATHBUF1,x
 rep #$20
 mx %00
 inx
 iny
 cpx #64
 bcc :c
 ldx #$40
 jmp p_getinfo
* ProDOS date/time -> DOS
pdate_dos                  ; A = ProDOS date (yyyyyyym mmmddddd) -> DOS (yyyyyyym mmmddddd, year since 1980)
 mx %00
 pha
 and #$FE00
 xba
 lsr                       ; year 0-99 (ProDOS: < 40 means 2000s)
 cmp #40
 bcs :c19
 clc
 adc #100
:c19
 sec
 sbc #80
 bpl :ok
 lda #0
:ok
 xba
 asl                       ; year << 9
 sta sv9
 pla
 and #$01FF
 ora sv9
 rts
ptime_dos                  ; ProDOS time (000hhhhh 00mmmmmm) -> DOS (hhhhhmmm mmmsssss)
 mx %00
 pha
 and #$1F00
 asl
 asl
 asl                       ; hours << 11
 sta sv9
 pla
 and #$003F
 asl
 asl
 asl
 asl
 asl                       ; minutes << 5
 ora sv9
 rts

*=== find first / next =======================================
* The DTA (43 bytes): our state in the reserved 21, then
* attribute (1), time (2), date (2), size (4), name (13).
* State: +0 search attribute, +1 pattern (11: name 8 + ext 3),
* +12 directory handle entry*8, +13 entry index in the block,
* +14 block number (2), +16 entries per block, +17 'X' marker.
dos_4E                     ; find first: DS:DX pattern, CX attributes
 mx %00
 jsr ds_dx_path
 bcc :lj15
 jmp :fail
:lj15
 jsr dta_pointer
 ; split PATHBUF0 into directory and pattern
 lda sv5
 sta sv6                   ; path length (sv6 was the buffer offset 0)
 stz sv6
 jsr last_comp             ; X = start of the name, sv8 = its length
 stx sv3                   ; name start
 ; the pattern -> DTA+1 as 8+3
 jsr pattern_fill
 ; the directory: everything before the name, or the prefix
 lda sv3
 beq :prefix
 dec                       ; drop the '/'
 beq :prefix
 sta sv8
 sep #$20
 mx %10
 lda sv8
 sta >PATHBUF0
 rep #$20
 mx %00
 bra :open
:prefix
 jsr prefix_to_path0
:open
 ldx #0
 lda #0
 jsr p_open
 bcs :fail
 txa
 ldy #12
 sep #$20
 mx %10
 sta [pDTA],y
 lda #0
 ldy #13
 sta [pDTA],y
 ldy #14
 sta [pDTA],y
 ldy #15
 sta [pDTA],y
 lda #$0D
 ldy #16
 sta [pDTA],y
 lda #'X'
 ldy #17
 sta [pDTA],y
 rep #$20
 mx %00
 lda rCX
 sep #$20
 mx %10
 sta [pDTA]
 rep #$20
 mx %00
 jmp find_next
:fail
 jmp dos_err
dos_4F                     ; find next
 mx %00
 jsr dta_pointer
 ldy #17
 lda [pDTA],y
 and #$00FF
 cmp #'X'
 bne :nomore
 jmp find_next
:nomore
 lda #$12                  ; no more files
 jmp dos_err
dta_pointer                ; pDTA = host pointer to the DTA
 mx %00
 lda dta_seg
 sta rES                   ; borrow the ES base computation
 pha
 lda bES
 pha
 lda bES+2
 pha
 jsr svc_set_es
 lda dta_off
 clc
 adc bES
 sta pDTA
 lda bES+2
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pDTA+2
 pla
 sta bES+2
 pla
 sta bES
 pla
 ; rES restored from the saved base? simpler: recompute ES from its base
 lda bES
 lsr
 lsr
 lsr
 lsr
 sta sv9
 lda bES+2
 and #$000F
 xba
 asl
 asl
 asl
 asl
 ora sv9
 sta rES
 rts
pattern_fill               ; the name at PATHBUF0+sv3 (sv8 long) -> DTA+1..+11, 8.3 with '?' for '*'
 mx %00
 ldy #1
 lda #' '
 sep #$20
 mx %10
:blank
 sta [pDTA],y
 iny
 cpy #12
 bcc :blank
 rep #$20
 mx %00
 ldy #1                    ; name part
 ldx sv3
 stz sv9                   ; chars taken
:n
 lda sv8
 bne :lj16
 jmp :done
:lj16
 lda >PATHBUF0+1,x
 and #$00FF
 cmp #'.'
 beq :dot
 cmp #'*'
 beq :star
 cpy #9
 bcs :skipn
 jsr dta_putc
:skipn
 inx
 dec sv8
 bra :n
:star
 lda #'?'
:fillstar
 cpy #9
 bcs :skipn
 jsr dta_putc
 bra :fillstar
:dot
 ldy #9
 inx
 dec sv8
:e
 lda sv8
 beq :done
 lda >PATHBUF0+1,x
 and #$00FF
 cmp #'*'
 beq :estar
 cpy #12
 bcs :skipe
 jsr dta_putc
:skipe
 inx
 dec sv8
 bra :e
:estar
 lda #'?'
:fillestar
 cpy #12
 bcs :skipe
 jsr dta_putc
 bra :fillestar
:done
 rts
dta_putc                   ; A (low byte) -> [pDTA],y ; y++
 mx %00
 sta sv9
 sep #$20
 mx %10
 lda sv9
 sta [pDTA],y
 rep #$20
 mx %00
 iny
 rts
prefix_to_path0            ; the volume prefix -> PATHBUF0 (Pascal)
 mx %00
 ldx #0
 lda >PREFIXBUF
 and #$00FF
 sta sv8
 inc sv8
:c
 lda >PREFIXBUF,x
 sta sv9
 sep #$20
 mx %10
 lda sv9
 sta >PATHBUF0,x
 rep #$20
 mx %00
 inx
 cpx sv8
 bcc :c
 rts

* find_next - walk the directory from the DTA's state; fill the
* DTA on a match (CF clear) or close it and report no more (CF set).
find_next
 mx %00
:again
 ldy #12
 lda [pDTA],y
 and #$00FF
 tax                       ; entry*8
 stx sv2
 ; block number -> mark = block*512, read 512 bytes to the bounce
 ldy #14
 lda [pDTA],y
 sta sv8
 lda sv8
 xba
 asl                       ; *512: (block << 8) << 1
 sta sv8
 lda sv8
 bcc :nocarry
 lda #1
 bra :hi
:nocarry
 lda #0
:hi
 sta sv9
 ldy #14
 lda [pDTA],y
 and #$0080                ; blocks >= 128 would be 64 KB: beyond any directory here
 beq :lj17
 jmp :end
:lj17
 ldx sv2
 jsr p_setmark
 bcc :lj18
 jmp :end
:lj18
 lda #4
 sta >MB_MLI_PARMS
 jsr h_ref
 lda #BOUNCEBUF
 sta >MB_MLI_PARMS+2
 lda #512
 sta >MB_MLI_PARMS+4
 lda #$CA
 jsr mli
 bcc :lj19
 jmp :end
:lj19
 lda >MB_MLI_PARMS+6
 cmp #512
 bcs :lj20
 jmp :end
:lj20
 ; entries: 13 of 39 bytes from offset 4; the first entry of block 0 is the header
:entry
 ldy #13
 lda [pDTA],y
 and #$00FF
 cmp #13
 bcc :lj21
 jmp :nextblock
:lj21
 sta sv3                   ; entry index; *39 = *32 + *4 + *2 + *1
 asl
 asl
 asl
 asl
 asl
 sta sv9                   ; *32
 lda sv3
 asl
 asl
 clc
 adc sv9
 sta sv9                   ; *36
 lda sv3
 asl
 clc
 adc sv9
 clc
 adc sv3                   ; *39
 clc
 adc #4
 tax                       ; X = entry offset in the bounce
 ; advance the index now
 lda sv3
 inc
 sta sv9
 ldy #13
 sep #$20
 mx %10
 lda sv9
 sta [pDTA],y
 rep #$20
 mx %00
 ; block 0 entry 0 is the header
 ldy #14
 lda [pDTA],y
 and #$00FF
 ora sv3
 bne :lj22
 jmp :entry
:lj22
 lda >BOUNCEBUF,x
 and #$00FF
 bne :lj23
 jmp :entry ; deleted/empty
:lj23
 and #$000F
 sta sv4                   ; name length
 lda >BOUNCEBUF,x
 and #$00F0
 cmp #$D0                  ; subdirectory entry
 bne :isfile
 ; directories: only if the search attributes include $10
 lda [pDTA]
 and #$0010
 bne :lj24
 jmp :entry
:lj24
 lda #$10
 bra :attr
:isfile
 lda #$20
:attr
 sta sv5                   ; DOS attribute
 ; the name -> tmpname (Pascal), then match
 phx
 jsr entry_name
 jsr name_match            ; (X is its index)
 plx
 bcs :lj25
 jmp :entry
:lj25
 ; fill the DTA: attribute, time, date, size, 8.3 name
 lda sv5
 ldy #21
 jsr dta_putc
 lda >BOUNCEBUF+$21,x      ; last mod time (date at +$21, time at +$23)
 pha
 lda >BOUNCEBUF+$23,x
 jsr ptime_dos
 ldy #22
 jsr dta_putw
 pla
 jsr pdate_dos
 ldy #24
 jsr dta_putw
 lda >BOUNCEBUF+$15,x      ; EOF: 3 bytes at +$15
 ldy #26
 jsr dta_putw
 lda >BOUNCEBUF+$17,x
 and #$00FF
 ldy #28
 jsr dta_putw
 jsr dta_name              ; tmpname as "NAME.EXT",0 at +30
 jmp clr_cf
:nextblock
 ldy #13
 lda #0
 sep #$20
 mx %10
 sta [pDTA],y
 rep #$20
 mx %00
 ldy #14
 lda [pDTA],y
 inc
 sta sv9
 sep #$20
 mx %10
 lda sv9
 sta [pDTA],y
 rep #$20
 mx %00
 jmp :again
:end
 ldx sv2
 jsr p_close
 ldy #17
 lda #0
 sep #$20
 mx %10
 sta [pDTA],y
 rep #$20
 mx %00
 lda #$12
 jmp dos_err
dta_putw                   ; A -> [pDTA],y (word)
 mx %00
 sta sv9
 sep #$20
 mx %10
 lda sv9
 sta [pDTA],y
 iny
 lda sv9+1
 sta [pDTA],y
 rep #$20
 mx %00
 rts
entry_name                 ; the ProDOS name at BOUNCEBUF+x (sv4 chars) -> tmpname; X kept
 mx %00
 ldy #0
 stx sv9
 sep #$20
 mx %10
:c
 cpy sv4
 bcs :done
 lda >BOUNCEBUF+1,x
 sta tmpname+1,y
 inx
 iny
 bra :c
:done
 mx %10
 tya
 sta tmpname
 rep #$20
 mx %00
 ldx sv9
 rts
* name_match - tmpname (ProDOS) against the 8.3 pattern at DTA+1 (? wildcards);
* C set on a match. The ProDOS name splits at its last '.'.
name_match
 mx %00
 ; build the entry's 8.3 in sv-scratch: name part padded, ext padded
 jsr split83               ; fills name83 (11 bytes)
 ldy #1
 ldx #0
:cmp
 lda name83,x
 and #$00FF
 sta sv9
 lda [pDTA],y
 and #$00FF
 cmp #'?'
 beq :next
 cmp sv9
 beq :next
 clc
 rts
:next
 inx
 iny
 cpx #11
 bcc :cmp
 sec
 rts
name83     ds 12
split83                    ; tmpname -> name83: 8 chars name, 3 chars ext, space padded
 mx %00
 ldx #0
 lda #$2020
:b
 sta name83,x
 inx
 inx
 cpx #12
 bcc :b
 lda tmpname
 and #$00FF
 sta sv9                   ; length
 tax                       ; the last '.': sv8 = index of the first extension
 stz sv8                   ; character (0 = no extension)
:f
 txa
 beq :split
 dex
 lda tmpname+1,x
 and #$00FF
 cmp #'.'
 bne :f
 inx
 stx sv8
:split
 lda sv8                   ; the name: up to the '.', or all of it; 8 at most
 beq :nlen
 dec
 bra :nl
:nlen
 lda sv9
:nl
 cmp #9
 bcc :n
 lda #8
:n
 sta sv7
 ldx #0
 sep #$20
 mx %10
:cn
 cpx sv7
 bcs :ext
 lda tmpname+1,x
 sta name83,x
 inx
 bra :cn
:ext
 mx %10
 rep #$20
 mx %00
 ldx sv8
 beq :done
 ldy #8
 sep #$20
 mx %10
:ce
 cpx sv9
 bcs :edone
 cpy #11
 bcs :edone
 lda tmpname+1,x
 sta name83,y
 inx
 iny
 bra :ce
:edone
 mx %10
 rep #$20
 mx %00
:done
 rts
dta_name                   ; name83 -> "NAME.EXT",0 at DTA+30
 mx %00
 ldy #30
 ldx #0
:n
 cpx #8
 bcs :dot
 lda name83,x
 and #$00FF
 cmp #' '
 beq :dot
 jsr dta_putc
 inx
 bra :n
:dot
 lda name83+8
 and #$00FF
 cmp #' '
 beq :end
 lda #'.'
 jsr dta_putc
 ldx #8
:e
 cpx #11
 bcs :end
 lda name83,x
 and #$00FF
 cmp #' '
 beq :end
 jsr dta_putc
 inx
 bra :e
:end
 lda #0
 jmp dta_putc

*=== FCB functions ===========================================
* fcb_ptr: pGST -> the FCB at DS:DX (an extended FCB's $FF
* header is skipped). The handle lives at FCB+$18 (reserved).
fcb_point
 mx %00
 ldx #bDS
 lda rDX
 jsr gptr
 lda [pGST]
 and #$00FF
 cmp #$FF
 bne :plain
 lda pGST
 clc
 adc #7
 sta pGST
 bcc :plain
 inc pGST+2
:plain
 rts
* fcb_path - the FCB's 8.3 name -> PATHBUF0 (relative to the cwd)
fcb_path
 mx %00
 ; "NAME.EXT" into tmpname, then through dos_path for the cwd and validation
 ldy #1
 ldx #0
:n
 cpy #9
 bcs :dot
 lda [pGST],y
 and #$00FF
 cmp #' '
 beq :dot
 sta tmpname+1,x
 inx
 iny
 bra :n
:dot
 ldy #9
 lda [pGST],y
 and #$00FF
 cmp #' '
 beq :end
 lda #'.'
 sta tmpname+1,x
 inx
:e
 cpy #12
 bcs :end
 lda [pGST],y
 and #$00FF
 cmp #' '
 beq :end
 sta tmpname+1,x
 inx
 iny
 bra :e
:end
 lda #0
 sta tmpname+1,x           ; ASCIIZ for dos_path
 ; dos_path reads [pGST]: point it at tmpname (bank $04)
 lda pGST
 pha
 lda pGST+2
 pha
 lda #tmpname+1
 sta pGST
 lda #^tmpname
 sta pGST+2
 ldx #0
 jsr dos_path
 pla
 sta pGST+2
 pla
 sta pGST
 rts
fcb_handle                 ; A = the handle entry*8 stored at FCB+$18 (C set if none)
 mx %00
 ldy #$18
 lda [pGST],y
 and #$00FF
 cmp #$FF
 beq :none
 tax
 lda htab,x
 and #$00FF
 cmp #H_FILE
 bne :none
 clc
 rts
:none
 sec
 rts
fcb_set                    ; after opening entry X: FCB fields: handle, block 0, record size 128, size, date/time
 mx %00
 txa
 ldy #$18
 jsr gst_putc
 lda #0
 ldy #$0C
 jsr gst_putw              ; current block
 lda #128
 ldy #$0E
 jsr gst_putw              ; record size
 jsr p_geteof
 lda sv8
 ldy #$10
 jsr gst_putw
 lda sv9
 and #$00FF
 ldy #$12
 jsr gst_putw
 lda #0
 ldy #$20
 jsr gst_putc              ; current record
 rts
gst_putc                   ; A (low) -> [pGST],y
 mx %00
 sta sv9
 sep #$20
 mx %10
 lda sv9
 sta [pGST],y
 rep #$20
 mx %00
 rts
gst_putw
 mx %00
 sta [pGST],y
 rts
fcb_ok
 mx %00
 lda #0
 jmp set_al
fcb_fail
 mx %00
 lda #$FF
 jmp set_al

dos_0F                     ; FCB open
 mx %00
 jsr fcb_point
 jsr fcb_path
 bcs fcb_fail
 ldx #0
 lda #2
 jsr p_open
 bcs fcb_fail
 jsr fcb_set
 bra fcb_ok
dos_16                     ; FCB create
 mx %00
 jsr fcb_point
 jsr fcb_path
 bcs fcb_fail
 ldx #0
 jsr p_create
 bcs fcb_fail
 ldx #0
 lda #2
 jsr p_open
 bcs fcb_fail
 jsr fcb_set
 bra fcb_ok
dos_10                     ; FCB close
 mx %00
 jsr fcb_point
 jsr fcb_handle
 bcs fcb_fail
 jsr p_close
 lda #$FF
 ldy #$18
 jsr gst_putc
 bra fcb_ok
dos_13                     ; FCB delete
 mx %00
 jsr fcb_point
 jsr fcb_path
 bcs fcb_fail
 jsr p_destroy
 bcs fcb_fail
 bra fcb_ok
dos_17                     ; FCB rename: the new name at FCB+$11
 mx %00
 jsr fcb_point
 jsr fcb_path
 bcs fcb_fail
 lda pGST                  ; the second name as an FCB at +$10
 clc
 adc #$10
 sta pGST
 bcc :nc
 inc pGST+2
:nc
 jsr fcb_path              ; -> PATHBUF0 again: move it to PATHBUF1
 bcs fcb_fail
 ldx #0
:mv
 lda >PATHBUF0,x
 sta >PATHBUF1,x
 inx
 inx
 cpx #64
 bcc :mv
 lda pGST
 sec
 sbc #$10
 sta pGST
 bcs :nb
 dec pGST+2
:nb
 jsr fcb_path              ; the old name back into PATHBUF0
 jsr p_rename
 bcs fcb_fail2
 jmp fcb_ok
fcb_fail2
 jmp fcb_fail
* record position: (current block * 128 + current record) * record size (sequential),
* or random record * record size (random). sv8/sv9 = 24-bit position.
fcb_recsize                ; A = record size (0 -> 128)
 mx %00
 ldy #$0E
 lda [pGST],y
 bne :ok
 lda #128
:ok
 rts
fcb_seqpos
 mx %00
 ldy #$0C
 lda [pGST],y              ; block
 sta tmp0
 ldy #$20
 lda [pGST],y
 and #$007F                ; record
 sta tmp1
 lda tmp0                  ; block*128 + record
 xba
 lsr                       ; block << 7
 clc
 adc tmp1
 sta tmp1
 lda tmp0
 and #$0180                ; carries into the high byte
 xba
 lsr
 and #$0003
 sta tmp2
 bra fcb_mulrec
fcb_randpos
 mx %00
 ldy #$21
 lda [pGST],y              ; random record lo16
 sta tmp1
 ldy #$23
 lda [pGST],y
 and #$00FF
 sta tmp2
fcb_mulrec                 ; tmp2:tmp1 (records) * record size -> sv9:sv8
 mx %00
 jsr fcb_recsize
 sta tmp0
 jsr mul24                 ; tmp2:tmp1 * tmp0 -> sv9:sv8 (24 bits)
 rts
mul24                      ; (tmp2:tmp1) * tmp0 -> sv9:sv8, truncated to 24 bits
 mx %00
 stz sv8
 stz sv9
 lda tmp0
 beq :done
 sta sv7
:loop
 lsr sv7
 bcc :noadd
 lda sv8
 clc
 adc tmp1
 sta sv8
 lda sv9
 adc tmp2
 sta sv9
:noadd
 asl tmp1
 rol tmp2
 lda sv7
 bne :loop
:done
 lda sv9
 and #$00FF
 sta sv9
 rts
fcb_advance                ; sequential record++ (carry into the block)
 mx %00
 ldy #$20
 lda [pGST],y
 and #$00FF
 inc
 cmp #128
 bcc :store
 lda #0
 pha
 ldy #$0C
 lda [pGST],y
 inc
 sta [pGST],y
 pla
:store
 ldy #$20
 jmp gst_putc
dos_14                     ; FCB sequential read -> DTA; AL 0 ok, 1 EOF, 3 partial
 mx %00
 jsr fcb_point
 jsr fcb_handle
 bcs :fail
 stx sv2
 jsr fcb_seqpos
 jsr fcb_xfer_read
 bcs :eof
 jsr fcb_point
 jsr fcb_advance
 lda sv3                   ; result code
 jmp set_al
:eof
 lda #1
 jmp set_al
:fail
 lda #1
 jmp set_al
dos_15                     ; FCB sequential write from the DTA
 mx %00
 jsr fcb_point
 jsr fcb_handle
 bcs :fail
 stx sv2
 jsr fcb_seqpos
 jsr fcb_xfer_write
 bcs :fail
 jsr fcb_point
 jsr fcb_advance
 lda #0
 jmp set_al
:fail
 lda #1
 jmp set_al
dos_21                     ; FCB random read
 mx %00
 jsr fcb_point
 jsr fcb_handle
 bcs :fail
 stx sv2
 jsr fcb_randpos
 jsr fcb_xfer_read
 bcs :eof
 lda sv3
 jmp set_al
:eof
 lda #1
 jmp set_al
:fail
 lda #1
 jmp set_al
dos_22                     ; FCB random write
 mx %00
 jsr fcb_point
 jsr fcb_handle
 bcs :fail
 stx sv2
 jsr fcb_randpos
 jsr fcb_xfer_write
 bcs :fail
 lda #0
 jmp set_al
:fail
 lda #1
 jmp set_al
* fcb_xfer_read - one record from position sv9:sv8 of entry sv2 into the DTA.
* sv3 = 0 full, 3 partial (zero padded); C set at EOF (nothing read).
fcb_xfer_read
 mx %00
 ldx sv2
 jsr p_setmark
 bcc :lj26
 jmp :eof
:lj26
 jsr fcb_recsize
 sta sv0
 sta sv4
 jsr dta_pointer
 lda pDTA
 sta pGST
 lda pDTA+2
 sta pGST+2
 ldx sv2
 jsr p_read
 bcs :eof
 cmp #0
 beq :eof
 cmp sv4
 bcs :full
 ; partial: zero the rest
 sta sv3
 pha
 lda sv4
 sec
 sbc sv3
 sta sv9                   ; bytes to zero
 pla
 tay                       ; from offset (bytes read)
 sep #$20
 mx %10
 lda #0
:z
 sta [pGST],y
 iny
 dec sv9
 bne :z
 rep #$20
 mx %00
 lda #3
 sta sv3
 clc
 rts
:full
 stz sv3
 clc
 rts
:eof
 sec
 rts
fcb_xfer_write             ; one record from the DTA to position sv9:sv8 of entry sv2
 mx %00
 ldx sv2
 jsr p_setmark
 bcc :pos
 cmp #$4D                  ; beyond EOF: extend first
 bne :fail
 jsr p_seteof
 jsr p_setmark
 bcs :fail
:pos
 jsr fcb_recsize
 sta sv0
 jsr dta_pointer
 lda pDTA
 sta pGST
 lda pDTA+2
 sta pGST+2
 ldx sv2
 jsr p_write
 bcs :fail
 clc
 rts
:fail
 sec
 rts
dos_27                     ; FCB random block read: CX records from the random
 mx %00                    ; record, read CONTIGUOUSLY in one transfer (a record
 jsr fcb_point             ; size of 1 must not mean one disk read per byte).
 jsr fcb_handle
 bcc :lj1
 jmp :fail
:lj1
 stx sv2
 lda rCX
 bne :some
 jmp set_al                ; zero records: AL = 0
:some
 jsr fcb_randpos           ; sv9:sv8 = byte position
 ldx sv2
 jsr p_setmark
 bcc :lj2
 jmp :eof0
:lj2
 lda rCX                   ; total = CX * record size (low 16 bits; DTA buffers fit)
 sta tmp1
 stz tmp2
 jsr fcb_recsize
 sta sv6                   ; record size
 sta tmp0
 jsr mul24                 ; sv9:sv8 = total bytes
 lda sv8
 sta sv0
 jsr dta_pointer
 lda pDTA
 sta pGST
 lda pDTA+2
 sta pGST+2
 ldx sv2
 jsr p_read                ; A = bytes read in one go
 bcc :lj3
 jmp :eof0
:lj3
 sta sv5                   ; bytes read
 lda sv8                   ; bytes requested (total)
 sta sv1
 lda sv5
 sta tmp1                  ; records = bytes / record size
 stz tmp2
 lda sv6
 sta tmp0
 jsr div_by_rec            ; sv3 = records, sv4 = remainder
 lda sv4
 beq :whole
 ; partial final record: zero-pad it, count it, AL = 3
 lda sv6
 sec
 sbc sv4
 sta sv9                   ; pad bytes
 ldy sv5
 sep #$20
 mx %10
 lda #0
:z
 sta [pGST],y
 iny
 dec sv9
 bne :z
 rep #$20
 mx %00
 lda sv3
 inc
 sta rCX                   ; records read (incl. the partial)
 jsr fcb_point             ; the transfer left pGST on the DTA; back to the FCB
 jsr fcb_add_rand
 lda #3
 jmp set_al
:whole
 lda sv3
 sta rCX
 jsr fcb_point
 jsr fcb_add_rand
 lda sv5                   ; all requested bytes present?
 cmp sv1
 bcc :eofn
 lda #0
 jmp set_al
:eofn
 lda #1                    ; fewer than CX records: EOF reached
 jmp set_al
:eof0
 stz rCX
 lda #1
 jmp set_al
:fail
 stz rCX
 lda #1
 jmp set_al

* div_by_rec - tmp1 / tmp0 (16-bit) -> sv3 quotient, sv4 remainder.
* Fast paths for the common record sizes 1 and 128.
div_by_rec
 mx %00
 lda tmp0
 cmp #1
 bne :n128
 lda tmp1
 sta sv3
 stz sv4
 rts
:n128
 cmp #128
 bne :gen
 lda tmp1
 and #$007F
 sta sv4
 lda tmp1
 lsr
 lsr
 lsr
 lsr
 lsr
 lsr
 lsr
 sta sv3
 rts
:gen
 stz sv3
 lda tmp1
:loop
 cmp tmp0
 bcc :done
 sec
 sbc tmp0
 inc sv3
 bra :loop
:done
 sta sv4
 rts

* fcb_add_rand - advance the FCB's random record field by rCX records
* and keep the block/record fields in step.
fcb_add_rand
 mx %00
 ldy #$21
 lda [pGST],y
 clc
 adc rCX
 sta [pGST],y
 bcc :nc
 ldy #$23
 lda [pGST],y
 inc
 sta [pGST],y
:nc
 ldy #$21
 lda [pGST],y
 and #$007F
 ldy #$20
 jsr gst_putc
 ldy #$21
 lda [pGST],y
 lsr
 lsr
 lsr
 lsr
 lsr
 lsr
 lsr
 sta sv9
 ldy #$23
 lda [pGST],y
 and #$00FF
 xba
 asl
 ora sv9
 ldy #$0C
 jmp gst_putw

dos_28                     ; FCB random block write: CX records contiguously
 mx %00                    ; (0 records: truncate at the random record)
 jsr fcb_point
 jsr fcb_handle
 bcs :fail
 stx sv2
 jsr fcb_randpos           ; sv9:sv8 = byte position
 lda rCX
 bne :write
 ldx sv2                   ; CX = 0: set EOF here
 jsr p_seteof
 lda #0
 jmp set_al
:write
 ldx sv2
 jsr p_setmark
 bcc :pos
 cmp #$4D                  ; past EOF: extend first
 bne :fail
 jsr p_seteof
 ldx sv2
 jsr p_setmark
 bcs :fail
:pos
 lda rCX
 sta tmp1
 stz tmp2
 jsr fcb_recsize
 sta tmp0
 jsr mul24
 lda sv8
 sta sv0
 jsr dta_pointer
 lda pDTA
 sta pGST
 lda pDTA+2
 sta pGST+2
 ldx sv2
 jsr p_write
 bcs :fail
 jsr fcb_point
 jsr fcb_add_rand
 lda #0
 jmp set_al
:fail
 stz rCX
 lda #1
 jmp set_al

fcb_xfer_write_at          ; like fcb_xfer_write but from [pGST] as set
 mx %00
 ldx sv2
 jsr p_setmark
 bcc :pos
 cmp #$4D
 bne :fail
 jsr p_seteof
 jsr p_setmark
 bcs :fail
:pos
 jsr fcb_recsize
 sta sv0
 ldx sv2
 jsr p_write
 bcs :fail
 clc
 rts
:fail
 sec
 rts
fcb_randinc                ; random record++ and the sequential fields to match
 mx %00
 ldy #$21
 lda [pGST],y
 inc
 sta [pGST],y
 bne :nc
 ldy #$23
 lda [pGST],y
 inc
 sta [pGST],y
:nc
 ldy #$21
 lda [pGST],y
 and #$007F
 ldy #$20
 jsr gst_putc
 ldy #$21
 lda [pGST],y
 lsr
 lsr
 lsr
 lsr
 lsr
 lsr
 lsr
 sta sv9
 ldy #$23
 lda [pGST],y
 and #$00FF
 xba
 asl
 ora sv9
 ldy #$0C
 jmp gst_putw
