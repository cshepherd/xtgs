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

 put video.s
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
 put capture.s
 put gen/font.s
 put gen/tables.s
 put gen/t160.s
 put gen/dostab.s

 err *-1-SVC_BASE/$10000   ; one bank
