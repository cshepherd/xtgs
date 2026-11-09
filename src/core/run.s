*----------------------------------------------------------
* run.s - running guest code for real (not single-stepped):
* run_guest executes from the current state until HLT.
* bench_run is the B command.
*----------------------------------------------------------
run_guest                  ; until HLT; rIP = IP after it
 mx %00
 lda #0
 sta >CGA_MODECHG          ; no CGA mode-control (0x3D8) write pending yet
 sta >PIT_CTR              ; seed the free-running PIT state
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
 jsl SVC_BASE+27           ; svc_sndopen: the DOC is the speaker and the IRQ0 timer
 jsr run_guest
 jsl SVC_BASE+30           ; svc_sndclose
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

* boot_run - the D command: Mode B. Build the stub BIOS/IVT/BDA,
* load the image's boot sector to 0000:7C00, and run it as an
* XT would, delivering the IRQ0 timer. The guest's own DOS
* kernel installs INT 20h-2Fh; we keep serving the BIOS.
boot_run
 mx %00
 jsl SVC_BASE+24           ; svc_bootinit: stubs/IVT/BDA, sector 0 -> 0000:7C00
 stz rCS
 stz rDS
 stz rES
 stz rSS
 jsr set_all_bases
 lda #BOOT_LIN
 sta rIP
 lda #$7C00                ; stack just below the boot sector
 sta rSP
 stz rAX
 stz rBX
 stz rCX
 stz rDX                   ; DL = 0: floppy A
 stz rSI
 stz rDI
 stz rBP
 lda #F_FIXED+F_IF         ; interrupts enabled
 jsr flags_set
 stz vEXIT
 stz vHALT
 stz vVBL
 lda #2                    ; Mode B
 sta vPCMODE
 lda #0
 sta vTRACE
 stz vTRPTR
 lda #$BE57
 sta >MB_RUNIDX
 jsl SVC_BASE+27           ; svc_sndopen: the DOC is the speaker and the IRQ0 timer
 jsr run_guest
 jsl SVC_BASE+30           ; svc_sndclose
 stz vPCMODE
 jsl SVC_BASE+18           ; final screen flush
 lda #$D04E
 sta >MB_RUNIDX
 lda vHALT
 and #$00FF
 beq :exit
 lda #$FFFF
 rts
:exit
 lda vEXIT
 rts
