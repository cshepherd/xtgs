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
 lda #$0607                ; the 6845 as a text mode has it: 8 scan lines a row
 sta >CRTC_REG+9           ; (R9 = 7), the cursor from line 6
 lda #0                    ; the screen from B800:0000, the cursor the BIOS's
 sta >CRTC_REG+12
 sta >CRTC_REG+14
 sta >CRTC_CUR
 lda #run_done
 sta vHALTVEC
 lda #fetch                ; (the slot is counted by next_ct, cpu.s)
 ldx vTRACE
 beq :plain
 lda #next_trace
:plain
 sta vNEXT
 sta vnext0
 sta vnextb
 stz vSEGOVR
 stz vOVR
 stz vREP
 lda #SLOT_N
 sta vSLOT
 lda #1                    ; the slot's first look at the lines is a whole one
 sta >PIC_PEND
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
 asl vICOUNT               ; slots, times SLOT_N
 rol vICOUNT+2
 asl vICOUNT
 rol vICOUNT+2
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
 jsr ega_sync              ; the EGA as the PC's start left it (off)
 jsr jit_start             ; the translator, if it is there and asked for (jitc.s)
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
*
* The S command has no image: svc_bootinit returns 1 with
* FreeDOS's KERNEL.SYS from the shared folder at 0060:0000,
* entered as its boot sector would with BL = 80h (drive C:),
* or 2 when there is none, and nothing runs.
boot_run
 mx %00
 jsl SVC_BASE+24           ; svc_bootinit: stubs/IVT/BDA, sector 0 -> 0000:7C00
 cmp #2
 bcc :ok
 lda #$FFFF
 rts
:ok
 stz rCS
 stz rDS
 stz rES
 stz rSS
 stz rAX
 stz rBX
 stz rCX
 stz rDX                   ; DL = 0: floppy A
 stz rSI
 stz rDI
 stz rBP
 ldx #BOOT_LIN
 stx rIP
 ldx #$7C00                ; stack just below the boot sector
 stx rSP
 cmp #1
 bne :bases
 lda #KERNEL_SEG
 sta rCS
 stz rIP
 lda #BOOTSTK_SEG
 sta rSS
 lda #BOOTSTK_SP
 sta rSP
 lda #$0080                ; BL (and DL): the first hard disk
 sta rBX
 sta rDX
:bases
 jsr set_all_bases
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
 jsr ega_sync              ; the EGA as the PC's start left it (off)
 jsr jit_start             ; the translator, if it is there and asked for (jitc.s)
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
