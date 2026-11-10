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
*   D        boot the disk image (Mode B): load sector 0 to 0000:7C00
*            and run; the guest's DOS kernel takes over
*   B        run the program at 0000:0100 until HLT; MB_RUNIDX is
*            $BE57 while it runs and $D04E after, MB_ICOUNT the
*            retired-instruction count (bench, tools/bench.py)
*   J        M6 JIT spike: run the hand-translated native reg loop
*            with the same MB_RUNIDX marks (tools/jit_spike.py)
*----------------------------------------------------------
 typ $06
 dsk core
 put ../include/layout.s
 org CORE_BASE
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
 tcd                       ; D = the guest state page
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
 cmp #'D'
 beq :boot
 cmp #'S'                  ; DOS from the shared folder, no disk image
 beq :boot
 cmp #'J'
 beq :jit
 cmp #'K'
 beq :jitk
 lda #$FFFF                ; unknown command
 bra :exit
:jit
 jsr jit_run
 bra :exit
:jitk
 jsr jitk_run
 bra :exit
:com
 jsr com_run
 bra :exit
:boot
 jsr boot_run
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
 put jit.s
 put jit2.s
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
