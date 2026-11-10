*----------------------------------------------------------
* start.s - a GS/OS startup program (S16, */System/Start on
* the test volume) that quits to XTGS.SYSTEM, the way the
* Finder launches a ProDOS 8 system file: GS/OS shuts down,
* loads ProDOS 8 and enters the loader with OS_BOOT nonzero
* and its pathname at $0280 (make test-gsos, docs/relocation.md).
* When the loader QUITs, GS/OS comes back and runs this again.
*----------------------------------------------------------
 rel
 typ $B3
 dsk gsstart
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
 dw 0                      ; flags: not restartable, do not return here
:path dw :end-:text        ; a GS/OS string: length word, then the text
:text asc '*/XTGS/XTGS.SYSTEM' ; '*' is the boot volume
:end
