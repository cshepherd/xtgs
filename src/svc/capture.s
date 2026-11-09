*----------------------------------------------------------
* capture.s - host-side copy of everything the program
* writes to the console (bank $05), for the judge.
*----------------------------------------------------------
cap_putc                   ; A = byte (low)
 mx %00
 sta sv8
 lda >CAP_LEN
 cmp #CAP_MAX
 bcs :full
 tax
 sep #$20
 mx %10
 lda sv8
 sta >CAP_BUF,x
 rep #$20
 mx %00
 inx
 txa
 sta >CAP_LEN
:full
 rts
