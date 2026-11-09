*----------------------------------------------------------
* run.s - running guest code for real (not single-stepped):
* run_guest executes from the current state until HLT.
* bench_run is the B command.
*----------------------------------------------------------
run_guest                  ; until HLT; rIP = IP after it
 mx %00
 lda #run_done
 sta vHALTVEC
 lda #next
 sta vNEXT
 lda #SLOT_N
 sta vSLOT
 ldy rIP
 jmp fetch
run_done                   ; from op_F4 through HALTVEC
 mx %00
 sty rIP
 rts

bench_run
 mx %00
 jsr set_all_bases         ; every segment 0 (the DP was zeroed)
 lda #$100
 sta rIP
 lda #$FFFE
 sta rSP
 lda #F_FIXED
 jsr flags_set
 stz vICOUNT
 stz vICOUNT+2
 lda #$BE57
 sta >MB_RUNIDX
 jsr run_guest
 lda vICOUNT
 sta >MB_ICOUNT
 lda vICOUNT+2
 sta >MB_ICOUNT+2
 lda #$D04E
 sta >MB_RUNIDX
 lda #0
 rts

* com_run - the C command: the PC the program expects, then run
* it until a terminate hypercall (or HLT: exit code $FFFF).
com_run
 mx %00
 jsl SVC_BASE+21           ; pcinit sets CS:IP SS:SP DS ES for a .COM or .EXE
 jsr set_all_bases
 lda #F_FIXED+F_IF
 jsr flags_set
 stz vEXIT
 stz vHALT
 stz vVBL
 lda #1
 sta vPCMODE
 lda #$BE57
 sta >MB_RUNIDX
 jsr run_guest
 stz vPCMODE
 jsl SVC_BASE+18           ; final screen flush
 lda #$D04E
 sta >MB_RUNIDX
 lda vHALT                 ; a byte: HLT ended the run
 and #$00FF
 beq :exit
 lda #$FFFF
 rts
:exit
 lda vEXIT
 rts
