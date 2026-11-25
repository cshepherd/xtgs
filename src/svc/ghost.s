*----------------------------------------------------------
* ghost.s - a document XT/GS was opened with (docs/finder.md).
*
* The Finder opens the GS/OS application for a file named
* *.EXE, *.COM, *.BAT or *.BAS (the application's bundle,
* tools/gsos_rfork.py), and the front end leaves the file's
* pathname at MB_ARG, MB_ARGN 1. gh_check, from svc_bootinit
* once the shared drive is known, makes of it the keys that
* run the file at a DOS prompt, in the same buffer (MB_ARGN 2):
*
*     [E: Return]  CD \DIR\DIR Return  NAME.EXT Return
*
* (the drive only when DOS was not booted from it; and for a
* NAME.BAS the last line is \GWBASIC NAME.BAS, GW-BASIC run
* with the program: gh_basic), or refuses it: MB_ARGN $8000 +
* why, C set, and no PC is started; the front end says so and
* quits.
*
*     1  the file is not in the folder DOS has as a drive
*     2  there is no such folder (XTGS.CMD)
*     3  DOS has no name for it: a name or a folder that is
*        not 8.3 as the drive spells it, a path past 63
*
* gh_poll, from kb_poll when the IIGS has no key of its own,
* types them as kb_poll's own keys: the first when the guest
* has been asking an empty keyboard for half a second with a
* '>' before the cursor of a text screen (a prompt: at the end
* of a boot, or straight after a boot state), each of the
* others when the guest is asking again, the one before taken
* and its key up. Until there is such a prompt they wait.
*
* The keys and how far they have got are in the front end's
* page and not the PC's: no saved state has them, and a state
* that is loaded changes nothing of them.
*----------------------------------------------------------
GH_PROMPT  = 30              ; frames of asking before the first key
GH_NEAR    = 4               ; asking: it asked this few frames ago
gh_seen    dw 0              ; vbl_count when the guest last asked for a key and there was none
gh_idle    dw 0              ; the frames in a row it has been asking
gh_last    dw 0              ; vbl_count at gh_poll's last look

* gh_ask - INT 16h found no key (bios.s)
gh_ask
 mx %00
 lda vbl_count
 sta gh_seen
 rts

* gh_poll - C set: a key in sv0, no modifiers in sv1
gh_poll
 mx %00
 lda >MB_ARGN
 cmp #2
 bne :no
 lda vbl_count
 cmp gh_last
 beq :no                   ; (a wait calls kb_poll many times a frame)
 sta gh_last
 sec
 sbc gh_seen
 cmp #GH_NEAR
 bcc :asking
 stz gh_idle
:no
 clc
 rts
:asking
 inc gh_idle
 lda kb_held               ; the key before is still down,
 bne :no
 lda >H_BDA+BDA_KBHEAD     ; or not taken
 cmp >H_BDA+BDA_KBTAIL
 bne :no
 lda >MB_ARGI
 cmp #2
 bcs :key                  ; (under way)
 lda gh_idle
 cmp #GH_PROMPT
 bcc :no
 jsr gh_prompt
 bcc :no
:key
 lda pGST+2                ; (whoever waits here may have a pointer of its own)
 pha
 lda pGST
 pha
 lda >MB_ARG
 sta pGST
 lda >MB_ARG+2
 sta pGST+2
 lda [pGST]
 and #$00FF
 sta sv2                   ; how many there are
 lda >MB_ARGI
 tay
 lda [pGST],y
 and #$00FF
 sta sv0
 stz sv1
 pla
 sta pGST
 pla
 sta pGST+2
 cpy sv2
 bcc :more
 lda #0                    ; that was the last
 sta >MB_ARGN
 stz gh_idle
:more
 iny
 tya
 sta >MB_ARGI
 sec
 rts

* gh_prompt - C set: a text screen, and the cell before the cursor is '>'
gh_prompt
 mx %00
 lda gfx_mode
 bne :no
 lda >H_BDA+BDA_CURPOS
 and #$00FF
 beq :no                   ; (a line's start)
 lda >H_BDA+BDA_CURPOS
 dec
 jsr cell_off
 clc
 adc #$8000
 tax
 lda >H_TXTBANK,x
 and #$00FF
 cmp #'>'
 bne :no
 sec
 rts
:no
 clc
 rts

* gh_check - from svc_bootinit, after rd_setup. C set: refused.
gh_check
 mx %00
 stz gh_idle
 stz gh_seen
 stz gh_last
 lda >MB_ARGN
 cmp #2
 bne :new
 lda #1                    ; (the PC is started again before they were typed: from the first)
 sta >MB_ARGI
:none
 clc
 rts
:new
 cmp #1
 bne :none
 lda >MB_ARG
 sta pGST
 lda >MB_ARG+2
 sta pGST+2
 lda rd_cfg
 cmp #1
 beq :share
 lda #2
 jmp :refuse
:share
 lda [pGST]
 and #$00FF
 sta sv9                   ; the pathname's length
 lda rd_root
 and #$00FF
 sta sv8                   ; the share's
 cmp sv9
 bcc :fits
:outside
 lda #1
 jmp :refuse
:fits
 ldy #1
:same
 lda [pGST],y
 jsr gh_up
 sta sv7
 lda rd_root,y
 jsr gh_up
 cmp sv7
 bne :outside
 cpy sv8
 iny                       ; (INY keeps the carry)
 bcc :same
 lda [pGST],y              ; and a '/' after it: the share's name is not the start of another's
 and #$00FF
 cmp #'/'
 bne :outside
 ldx #1                    ; the keys, in the transfer buffer for now
 lda rd_boot
 bne :cd
 lda rd_drive
 clc
 adc #'A'
 jsr gh_put
 lda #':'
 jsr gh_put
 lda #$0D
 jsr gh_put
:cd
 lda #'C'
 jsr gh_put
 lda #'D'
 jsr gh_put
 lda #' '
 jsr gh_put
 stx sv5                   ; where the folders begin
:comp                      ; Y at a '/': the name after it into tmpname
 stx sv6
 ldx #0
:ch
 cpy sv9
 bcs :file                 ; the pathname ends: this one is the file
 iny
 lda [pGST],y
 jsr gh_up
 cmp #'/'
 beq :dir
 cpx #15
 bcs :noname
 sep #$20
 mx %10
 sta tmpname+1,x
 rep #$20
 mx %00
 inx
 bra :ch
:dir
 jsr gh_name
 bcs :noname
 ldx sv6
 lda #'\'
 jsr gh_put
 jsr gh_putname
 txa
 sec
 sbc sv5
 cmp #64                   ; (CD takes a path of 63)
 bcc :comp
:noname
 lda #3
:refuse
 ora #$8000
 sta >MB_ARGN
 sec
 rts
:file
 jsr gh_name
 bcs :noname
 ldx sv6
 cpx sv5
 bne :cr
 lda #'\'                  ; (no folder: the drive's root)
 jsr gh_put
:cr
 lda #$0D
 jsr gh_put
 jsr gh_basic
 jsr gh_putname
 lda #$0D
 jsr gh_put
 dex
 stx sv7                   ; how many keys: into the front end's buffer, their count first
 ldy #1
:out
 cpy sv7
 beq :o1
 bcs :done
:o1
 tyx
 lda >BOUNCEBUF,x
 sep #$20
 mx %10
 sta [pGST],y
 rep #$20
 mx %00
 iny
 bra :out
:done
 sep #$20
 mx %10
 lda sv7
 sta [pGST]
 rep #$20
 mx %00
 lda #1
 sta >MB_ARGI
 inc
 sta >MB_ARGN
 clc
 rts

* gh_basic - before the name of a NAME.BAS, the interpreter's:
* "\GWBASIC " when GWBASIC.EXE is in the drive's root (the folder
* that was just made the current one is not where it is), and
* "GWBASIC " when it is not, for DOS to find along its PATH. X is
* the next key's place and goes on; Y is not kept.
gh_basic
 mx %00
 lda tmpname
 and #$00FF
 cmp #5
 bcc :no
 tay
 lda tmpname-3,y           ; its last four characters
 cmp #'.B'
 bne :no
 lda tmpname-1,y
 cmp #'AS'
 bne :no
 phx
 ldx #0
:n
 lda gh_gw,x
 sta >PATHBUF0,x
 inx
 inx
 cpx #12
 bcc :n
 ldx #0                    ; (the folder is the prefix: rd_mkroot)
 jsr p_getinfo
 plx                       ; (PLX keeps the carry)
 bcs :path
 lda #'\'
 jsr gh_put
:path
 ldy #1
:c
 lda gh_gw,y
 and #$00FF
 cmp #'.'
 beq :sp
 jsr gh_put
 iny
 bra :c
:sp
 lda #' '
 jsr gh_put
:no
 rts
gh_gw      str 'GWBASIC.EXE'

* gh_up - A's low byte, a letter in upper case
gh_up
 mx %00
 and #$00FF
 cmp #'a'
 bcc :out
 cmp #'z'+1
 bcs :out
 and #$005F
:out
 rts

* gh_put - A's low byte is the key at X, which goes on
gh_put
 mx %00
 sep #$20
 mx %10
 sta >BOUNCEBUF,x
 rep #$20
 mx %00
 inx
 rts

* gh_putname - tmpname's characters. Y kept.
gh_putname
 mx %00
 phy
 lda tmpname
 and #$00FF
 sta sv7
 ldy #0
:c
 lda tmpname+1,y
 jsr gh_put
 iny
 cpy sv7
 bcc :c
 ply
 rts

* gh_name - tmpname's X characters, a ProDOS name, as the drive
* spells it for DOS (rd_unname). C set when that is no 8.3 name:
* DOS could not name the file. Y kept.
gh_name
 mx %00
 txa
 beq :bad
 sep #$20
 mx %10
 sta tmpname
 rep #$20
 mx %00
 jsr rd_unname
 lda tmpname
 and #$00FF
 beq :bad
 sta sv7
 stz sv3                   ; characters since the start or the dot
 stz sv4                   ; 1: after the dot
 ldx #0
:c
 lda tmpname+1,x
 and #$00FF
 cmp #'.'
 bne :ch
 lda sv4
 bne :bad                  ; a second one
 lda sv3
 beq :bad                  ; nothing before it
 inc sv4
 stz sv3
 bra :next
:ch
 cmp #'_'
 beq :ok
 cmp #'0'
 bcc :bad
 cmp #'9'+1
 bcc :ok
 cmp #'A'
 bcc :bad
 cmp #'Z'+1
 bcs :bad
:ok
 inc sv3
 lda sv4
 beq :n8
 lda sv3
 cmp #4
 bcs :bad
 bra :next
:n8
 lda sv3
 cmp #9
 bcs :bad
:next
 inx
 cpx sv7
 bcc :c
 lda sv3
 beq :bad                  ; (nothing after the dot)
 clc
 rts
:bad
 sec
 rts
