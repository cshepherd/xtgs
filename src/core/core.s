*----------------------------------------------------------
* CORE - the emulator core bank ($03:0000).
*
* Entry: JSL $030000 from XTGS.SYSTEM, native mode, 16-bit
* M/X, DBR = $00, D = $0000, S = $0BFF. Returns by RTL with
* A = exit code (0 = ok), 16-bit M/X, DBR and D restored.
* The command is the Pascal string at MB_CMD:
*   P        memory probe and the 80x25 test frame (M0)
*   V        run the CPU test vectors loaded at DATA_BASE (M1)
*   C NAME   run the .COM the loader put at PSP_SEG:0100 under the
*            stub BIOS/DOS until it terminates; A = its exit code
*   B        run the program at 0000:0100 until HLT; MB_RUNIDX is
*            $BE57 while it runs and $D04E after, MB_ICOUNT the
*            retired-instruction count (bench, tools/bench.py)
*----------------------------------------------------------
 typ $06
 dsk core
 org $030000
 mx %00

 put ../include/hw.s
 put ../include/mailbox.s
 put ../include/guest.s
 put ../include/pc.s

core_entry
 phb
 phd
 phk
 plb                       ; DBR = $03
 lda #GUEST_DP
 tcd                       ; D = $1000
 ldx #0
:zero
 stz 0,x
 inx
 inx
 cpx #$100
 bcc :zero
 lda >MB_CMD
 and #$00FF
 beq :probe                ; no command: probe
 lda >MB_CMD+1
 and #$00FF
 cmp #'P'
 beq :probe
 cmp #'V'
 beq :vectors
 cmp #'B'
 beq :bench
 cmp #'C'
 beq :com
 lda #$FFFF                ; unknown command
 bra :exit
:com
 jsr com_run
 bra :exit
:probe
 jsr probe_run
 bra :exit
:vectors
 jsr harness_run
 bra :exit
:bench
 jsr bench_run
:exit
 rep #$30
 pld
 plb
 rtl

 put probe.s
 put run.s
 put cpu.s
 put flags.s
 put ops_mov.s
 put ops_ctrl.s
 put ops_grp.s
 put ops_str.s
 put ops_misc.s
 put harness.s
 put gen/optab.s
 put gen/eatab.s
 put gen/alu.s
 put gen/flagtab.s

 err *-1-CORE_BASE/$10000  ; one bank
