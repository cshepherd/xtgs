*----------------------------------------------------------
* start16.s - start.s for the native front end: a GS/OS
* startup program (S16, */System/Start on the test volume)
* that quits to */XTGS/XTGS, the S16 application
* (src/gs/xtgs16.s), as the Finder launches one: asking to
* be returned to. When XT/GS quits, GS/OS runs this again
* and so XT/GS again. (Without the flag System 6.0.1 puts
* up its own Program Launcher after the application quits.)
*
* And as the Finder opens it for a document (docs/finder.md):
* when there is a file */XTGS/ARG, its first line is a
* pathname, which goes to the Message Center as message 1,
* what the Finder leaves there for the application it
* launches (+6 a word, 0 for "open"; +8 the pathnames, Pascal
* strings, a zero after the last). The file is deleted, so
* the next launch has no document.
*----------------------------------------------------------
 rel
 typ $B3
 dsk gsstart16
 mx %00
start
 phk
 plb
 sta my_id
 jsl $E100A8               ; GS/OS, inline call
 dw $2010                  ; OPEN
 adrl op
 bcc :there
 jmp go
:there
 lda op+2
 sta rd+2
 sta cl+2
 jsl $E100A8
 dw $2012                  ; READ (a short one is fine)
 adrl rd
 jsl $E100A8
 dw $2014                  ; CLOSE
 adrl cl
 jsl $E100A8
 dw $2002                  ; DESTROY
 adrl de
 ldx #0                    ; the line's length
 sep #$20
 mx %10
:len
 cpx rd+12
 bcs :got
 lda text,x
 cmp #$0D
 beq :got
 cmp #$0A
 beq :got
 inx
 bra :len
:got
 txa
 sta pname
 rep #$20
 mx %00
 txa
 bne :some
 jmp go
:some
 pha                       ; NewHandle: 6 bytes of the Message Center's, the word, the
 pha                       ; string and the zero
 pea $0000
 clc
 adc #10
 pha
 lda my_id
 pha
 pea $8000                 ; locked
 pea $0000
 pea $0000
 ldx #$0902
 jsl $E10000
 pla
 sta mh
 pla
 sta mh+2
 bcc :made
 jmp go
:made
 lda mh
 sta 0
 lda mh+2
 sta 2
 ldy #2
 lda [0],y
 tax
 lda [0]
 sta 0
 stx 2
 lda #0
 sta [0]
 sta [0],y
 ldy #6
 sta [0],y                 ; "open"
 ldy #4
 lda #1
 sta [0],y
 lda pname
 and #$00FF
 inc
 sta count
 ldx #0
 ldy #8
 sep #$20
 mx %10
:copy
 lda pname,x
 sta [0],y
 iny
 inx
 cpx count
 bcc :copy
 lda #0
 sta [0],y
 rep #$20
 mx %00
 pea $0001                 ; addMessage
 pea $0001                 ; the file message
 lda mh+2
 pha
 lda mh
 pha
 ldx #$1501                ; MessageCenter
 jsl $E10000
go
 mx %00
 jsl $E100A8
 dw $2029                  ; QuitGS
 adrl parms
 brk $00                   ; (it does not return)
parms dw 2                 ; pCount
 adrl path
 dw $8000                  ; flags: come back here when that program quits
path dw pathend-pathtext   ; a GS/OS string: length word, then the text
pathtext asc '*/XTGS/XTGS'    ; '*' is the boot volume
pathend
op dw 2                    ; OPEN: pCount, the reference number, the pathname
 dw 0
 adrl argpath
rd dw 4                    ; READ: the reference number, where, how much, how much it was
 dw 0
 adrl text
 adrl 255
 adrl 0
cl dw 1
 dw 0
de dw 1
 adrl argpath
argpath dw argend-argtext
argtext asc '*/XTGS/ARG'
argend
my_id dw 0
mh adrl 0
count dw 0
pname dfb 0                ; the pathname as a Pascal string
text ds 256
