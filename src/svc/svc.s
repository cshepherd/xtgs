*----------------------------------------------------------
* SVC - the services bank ($04:0000): the text screen, the
* stub BIOS and DOS services (hypercalls), keyboard, timer.
*
* Entry: JSL $040000 + 3*n from the core, native mode,
* 16-bit M/X, D = GUEST_DP (the services use sv0.., pGST,
* pCELL, pTXT there and read the guest registers rAX..).
* Each entry sets DBR = $04 and restores the caller's;
* returns with 16-bit M/X.
*----------------------------------------------------------
 typ $06
 dsk svc
 put ../include/layout.s
 org SVC_BASE
 mx %00

 put ../include/hw.s
 put ../include/mailbox.s
 put ../include/guest.s
 put ../include/pc.s

* Vector table: the ABI between CORE and SVC. Do not reorder.
 jmp svc_init              ; $040000  SHR 640 text screen on, cleared
 jmp svc_render_all        ; $040003  render the whole text buffer
 jmp svc_testframe         ; $040006  fill the text buffer with the M0 pattern
 jmp svc_render_row        ; $040009  render row A (0-24)
 jmp svc_hypercall         ; $04000C  hypercall A; C=1 on return: stop, A = exit code
 jmp svc_vbl               ; $04000F  once a frame: keyboard, tick, screen flush
 jmp svc_flush             ; $040012  render dirty rows and the cursor
 jmp svc_pcinit            ; $040015  build IVT/BDA/BIOS stubs/PSP/env; A = PSP_SEG
 jmp svc_bootinit          ; $040018  Mode B: IVT/BDA/stubs, boot sector -> 7C00
 jmp svc_sndopen           ; $04001B  take the DOC: speaker and the IRQ0 timer
 jmp svc_sndclose          ; $04001E  give it back
 jmp svc_sndport           ; $040021  a write to port A (40h-61h), value in tmp0
 jmp svc_portout           ; $040024  Mode B: a write to any other port A, value in tmp0
 jmp svc_portin            ; $040027  Mode B: a read of port A the core has not -> A
 jmp svc_cda               ; $04002A  the desk accessory's start routine (control.s)
 jmp svc_stload            ; $04002D  the boot state bs_try found, into its places (state.s)

 put video.s
 put gtext.s
 put ega.s
 put tandy.s
 put pcinit.s
 put bios.s
 put dos.s
 put files.s
 put disk.s
 put ports.s
 put redir.s
 put keyboard.s
 put sound.s
 put clock.s
 put joystick.s
 put serial.s
 put mouse.s
 put xms.s
 put control.s
 put state.s
 put gen/buildid.s
 put capture.s
 put gen/font.s
 put gen/tables.s
 put gen/t160.s
 put gen/egatab.s
 put gen/tdytab.s
 put gen/dostab.s

* What follows is in the bank and not in the file: buffers that are
* written before they are read, past the image's end (the file with
* its list of bank bytes must fit the bank too, and the list is done
* with once the image is in its place: these lie where it was).
           dum *
snd_pg1    ds 256            ; sound.s: bank $00 page 1 while interrupts are live
bs_hdr     ds 256            ; state.s: the boot state's header (XTGS.CMD as this start read it at +42)
bs_home    ds 66             ; and the folder XT/GS was started from (Pascal, "/VOL/DIR/")
mf_rec     ds 78             ; state.s: a record of a file the PC was started from
svc_end    ds 0
           dend
 err svc_end-1-SVC_BASE/$10000   ; one bank
