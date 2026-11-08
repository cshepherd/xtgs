*----------------------------------------------------------
* SVC - the services bank ($04:0000): video, and later the
* stub BIOS and DOS hypercall handlers, keyboard and timer.
*
* Entry: JSL $040000 + 3*n from the core, native mode,
* 16-bit M/X, D = GUEST_DP (the services use sv0.. and
* pCELL/pTXT there). Each entry sets DBR = $04 and restores
* the caller's; returns A = status (0 = ok) with 16-bit M/X.
*----------------------------------------------------------
 typ $06
 dsk svc
 org $040000
 mx %00

 put ../include/hw.s
 put ../include/mailbox.s
 put ../include/guest.s

* Vector table: the ABI between CORE and SVC. Do not reorder.
 jmp svc_init              ; $040000  SHR 640 text screen on, cleared
 jmp svc_render_all        ; $040003  render the whole text buffer
 jmp svc_testframe         ; $040006  fill the text buffer with the M0 pattern
 jmp svc_render_row        ; $040009  render row A (0-24)
 jmp svc_hypercall         ; $04000C  hypercall A (from FE 38 lo hi); D = GUEST_DP

* svc_hypercall - no services yet: ignore. Preserves D; A = 0.
svc_hypercall
 mx %00
 lda #0
 rtl

 put video.s
 put gen/font.s
 put gen/tables.s

 err *-1-SVC_BASE/$10000   ; one bank
