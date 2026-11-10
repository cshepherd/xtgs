*----------------------------------------------------------
* start16.s - start.s for the native front end: a GS/OS
* startup program (S16, */System/Start on the test volume)
* that quits to */XTGS/XTGS, the S16 application
* (src/gs/xtgs16.s), as the Finder launches one: asking to
* be returned to. When XT/GS quits, GS/OS runs this again
* and so XT/GS again. (Without the flag System 6.0.1 puts
* up its own Program Launcher after the application quits.)
*----------------------------------------------------------
 rel
 typ $B3
 dsk gsstart16
 mx %00
start
 phk
 plb
 jsl $E100A8               ; GS/OS, inline call
 dw $2029                  ; QuitGS
 adrl :parms
 brk $00                   ; (it does not return)
:parms dw 2                ; pCount
 adrl :path
 dw $8000                  ; flags: come back here when that program quits
:path dw :end-:text        ; a GS/OS string: length word, then the text
:text asc '*/XTGS/XTGS'       ; '*' is the boot volume
:end
