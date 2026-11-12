*----------------------------------------------------------
* xms.s - extended memory for the guest, by the XMS driver's
* interface (docs/xms.md). Nothing is loaded in the guest:
* INT 2Fh AX=4300h says a driver is there and AX=4310h gives
* its entry, a stub at F000:XMS_OFF that is hypercall 261
* and a far return.
*
* The memory is the disk image's region (DISK_BASE,
* DISK_BANKS banks), which the S command has no image for:
* the front ends claim it under S when the Memory Manager
* has it, and MB_LAYOUT says whether they did. So there is
* XMS when FreeDOS booted from the shared folder, and none
* under D or after the line XMS=OFF in XTGS.CMD (xms_cfg,
* rd_readcfg). INT 2Fh is the shared drive's hook (redir.s,
* rd_int2f), which is in before the shell starts.
*
* It is the memory and no more: blocks allocated, moved to
* and from (function 0Bh), freed. There is no A20 line and
* no high memory area on this PC (an 8088's addresses wrap
* at 1 MiB), so 01h-06h fail and 07h says "off"; no upper
* memory blocks either. What it is for is FreeCOM, which
* swaps itself into a block while a program runs and so
* leaves the program some 90 KB more.
*----------------------------------------------------------
XMS_NH     = 32              ; handles: DX = 1..XMS_NH
XMS_KB     = DISK_BANKS*64
xms_on     dw 0
xms_cfg    dw 1              ; XTGS.CMD: 0 after XMS=OFF
xh_used    ds XMS_NH*2
xh_start   ds XMS_NH*2       ; KB from the region's start
xh_size    ds XMS_NH*2       ; KB
xh_lock    ds XMS_NH*2
xm_s       dw 0
xm_lim     dw 0
xm_need    dw 0
xm_i       dw 0
xm_c       dw 0
xm_len     ds 4
xm_sh      dw 0              ; the move's source: handle, offset
xm_so      ds 4
xm_dh      dw 0              ; and its destination
xm_do      ds 4
xm_ptr     ds 4
xm_end     ds 4

* The guest's side, at F000:XMS_OFF.
xms_stub
 hex EB03909090            ; +00 jmp short +3 / nop nop nop (a driver's first bytes)
 hex FE380501              ; +05 hypercall 261
 hex CB                    ; +09 retf
xms_stubend

* xms_calls - hypercall 261 (svc_hypercall, after ms_calls')
xms_calls  da xms_call
XMS_NCALLS = 1

* xms_setup - from svc_bootinit, after XTGS.CMD was read.
xms_setup
 mx %00
 stz xms_on
 lda xms_cfg
 beq :out
 lda rd_boot               ; S: the disk image's banks are free
 beq :out
 lda >RG_DISK*2+MB_LAYOUT  ; and the front end claimed them
 beq :out
 ldx #0
 sep #$20
 mx %10
:c
 lda xms_stub,x
 sta >H_BIOS+XMS_OFF,x
 inx
 cpx #xms_stubend-xms_stub
 bcc :c
 rep #$20
 mx %00
 ldx #0
:z
 stz xh_used,x
 stz xh_lock,x
 inx
 inx
 cpx #XMS_NH*2
 bcc :z
 inc xms_on
:out
 rts

* xms_int2f - from rd_int2f with AH = 43h. Answers by the
* stub's IRET, or returns for the chain.
xms_int2f
 mx %00
 lda xms_on
 beq :chain
 lda rAX
 and #$00FF
 beq :inst
 cmp #$0010
 bne :chain
 lda #BIOS_SEG             ; 4310h: ES:BX = the entry
 sta rES
 jsr svc_set_es
 lda #XMS_OFF
 sta rBX
 bra :done
:inst
 lda rAX                   ; 4300h: AL = 80h
 and #$FF00
 ora #$0080
 sta rAX
:done
 lda #RD_DONE
 sta rIP
:chain
 rts

* xms_call - hypercall 261: the function in AH.
xms_call
 mx %00
 lda rAX
 xba
 and #$00FF
 cmp #$0012
 bcs xm_nofn
 asl
 tax
 jmp (xm_ftab,x)
xm_ftab
 da xm_ver,xm_nohma,xm_nohma,xm_noa20      ; 00
 da xm_noa20,xm_noa20,xm_noa20,xm_qa20     ; 04
 da xm_query,xm_alloc,xm_free,xm_move      ; 08
 da xm_lockf,xm_unlock,xm_info,xm_resize   ; 0C
 da xm_noumb,xm_noumb2                     ; 10
xm_nofn
 mx %00
 lda #$0080                ; not implemented
xm_err                     ; AX = 0, BL = A
 mx %00
 and #$00FF
 sta xm_c
 lda rBX
 and #$FF00
 ora xm_c
 sta rBX
 stz rAX
 rts
xm_ok                      ; AX = 1
 mx %00
 lda #1
 sta rAX
 rts
xm_ver
 mx %00
 lda #$0200                ; XMS 2.00, driver 1.00, no HMA
 sta rAX
 lda #$0100
 sta rBX
 stz rDX
 rts
xm_nohma
 mx %00
 lda #$0090                ; the HMA does not exist
 bra xm_err
xm_noa20
 mx %00
 lda #$0082                ; an A20 error: there is no line
 bra xm_err
xm_qa20
 mx %00
 stz rAX                   ; off, and no error
 lda rBX
 and #$FF00
 sta rBX
 rts
xm_noumb
 mx %00
 stz rDX
 lda #$00B1                ; no UMBs
 bra xm_err
xm_noumb2
 mx %00
 lda #$00B2
 bra xm_err

* xm_gap - A = the free KB from xm_s on (0 when xm_s is
* inside a block).
xm_gap
 mx %00
 lda #XMS_KB
 sta xm_lim
 ldx #0
:l
 lda xh_used,x
 beq :n
 lda xh_size,x
 beq :n
 lda xh_start,x
 cmp xm_s
 beq :in
 bcs :above
 clc
 adc xh_size,x
 cmp xm_s
 beq :n
 bcs :in
 bra :n
:above
 cmp xm_lim
 bcs :n
 sta xm_lim
:n
 inx
 inx
 cpx #XMS_NH*2
 bcc :l
 lda xm_lim
 sec
 sbc xm_s
 rts
:in
 lda #0
 rts

* xm_cand - the places a block can start: the region's
* start, then each block's end. xm_i = 0 before the first;
* C set when there are no more, else xm_s is the next.
xm_cand
 mx %00
 ldx xm_i
 bne :blk
 stz xm_s
 inc xm_i
 inc xm_i
 clc
 rts
:blk
 cpx #XMS_NH*2+2
 bcs :end
 inc xm_i
 inc xm_i
 lda xh_used-2,x
 beq xm_cand
 lda xh_start-2,x
 clc
 adc xh_size-2,x
 sta xm_s
 cmp #XMS_KB
 bcs xm_cand
 clc
 rts
:end
 sec
 rts

* xm_find - a place for xm_need KB: C clear and xm_s, or C set.
xm_find
 mx %00
 stz xm_i
:l
 jsr xm_cand
 bcs :no
 jsr xm_gap
 cmp xm_need
 bcc :l
 clc
:no
 rts

* xm_hand - DX as a handle: X = its index * 2, or C set.
xm_hand
 mx %00
 lda rDX
xm_hand_a
 dec
 cmp #XMS_NH
 bcs :bad
 asl
 tax
 lda xh_used,x
 beq :bad
 clc
 rts
:bad
 sec
 rts

xm_query                   ; 08h: AX = the largest free block, DX = all free (KB)
 mx %00
 lda #XMS_KB
 sta xm_need               ; (here: what is free in all)
 ldx #0
:s
 lda xh_used,x
 beq :sn
 lda xm_need
 sec
 sbc xh_size,x
 sta xm_need
:sn
 inx
 inx
 cpx #XMS_NH*2
 bcc :s
 stz xm_c
 stz xm_i
:l
 jsr xm_cand
 bcs :done
 jsr xm_gap
 cmp xm_c
 bcc :l
 sta xm_c
 bra :l
:done
 lda xm_need
 sta rDX
 lda xm_c
 sta rAX
 bne :some
 lda #$00A0                ; all of it is allocated
 jmp xm_err
:some
 lda rBX
 and #$FF00
 sta rBX
 rts

xm_alloc                   ; 09h: DX KB -> DX = a handle
 mx %00
 ldy #0
:fh
 lda xh_used,y
 beq :slot
 iny
 iny
 cpy #XMS_NH*2
 bcc :fh
 lda #$00A1                ; no handle left
 jmp xm_err
:slot
 sty xm_end
 lda rDX
 sta xm_need
 stz xm_s
 beq :have                 ; a block of no length is anywhere
 cmp #XMS_KB+1
 bcs :full
 jsr xm_find
 bcc :have
:full
 lda #$00A0
 jmp xm_err
:have
 ldx xm_end
 lda #1
 sta xh_used,x
 lda xm_s
 sta xh_start,x
 lda xm_need
 sta xh_size,x
 stz xh_lock,x
 txa
 lsr
 inc
 sta rDX
 jmp xm_ok

xm_free                    ; 0Ah
 mx %00
 jsr xm_hand
 bcc :ok
 lda #$00A2                ; no such handle
 jmp xm_err
:ok
 lda xh_lock,x
 beq :go
 lda #$00AB                ; locked
 jmp xm_err
:go
 stz xh_used,x
 jmp xm_ok

xm_lockf                   ; 0Ch: DX:BX = where it is (above the megabyte, as a
 mx %00                    ; PC with the memory would say; nothing can go there)
 jsr xm_hand
 bcc :ok
 lda #$00A2
 jmp xm_err
:ok
 inc xh_lock,x
 lda xh_start,x
 and #$003F
 xba
 asl
 asl
 sta rBX
 lda xh_start,x
 lsr
 lsr
 lsr
 lsr
 lsr
 lsr
 clc
 adc #$0011
 sta rDX
 jmp xm_ok

xm_unlock                  ; 0Dh
 mx %00
 jsr xm_hand
 bcc :ok
 lda #$00A2
 jmp xm_err
:ok
 lda xh_lock,x
 bne :go
 lda #$00AA                ; not locked
 jmp xm_err
:go
 dec xh_lock,x
 jmp xm_ok

xm_info                    ; 0Eh: BH = locks, BL = handles free, DX = KB
 mx %00
 jsr xm_hand
 bcc :ok
 lda #$00A2
 jmp xm_err
:ok
 lda xh_size,x
 sta rDX
 lda xh_lock,x
 and #$00FF
 xba
 sta rBX
 ldy #0
 ldx #0
:c
 lda xh_used,x
 bne :u
 iny
:u
 inx
 inx
 cpx #XMS_NH*2
 bcc :c
 tya
 ora rBX
 sta rBX
 jmp xm_ok

xm_resize                  ; 0Fh: DX's block to BX KB, where it is if it can be
 mx %00
 jsr xm_hand
 bcc :ok
 lda #$00A2
 jmp xm_err
:ok
 lda xh_lock,x
 beq :free
 lda #$00AB
 jmp xm_err
:free
 lda rBX
 cmp xh_size,x
 bcc :set
 beq :set
 stx xm_end
 stz xh_used,x             ; the room from its start, itself aside
 lda xh_start,x
 sta xm_s
 lda xh_size,x
 bne :grow
 lda rBX                   ; it had no length: anywhere
 sta xm_need
 jsr xm_find
 bcs :full
 ldx xm_end
 lda xm_s
 sta xh_start,x
 bra :fits
:grow
 jsr xm_gap
 cmp rBX
 bcc :full
:fits
 ldx xm_end
 lda #1
 sta xh_used,x
:set
 lda rBX
 sta xh_size,x
 jmp xm_ok
:full
 ldx xm_end
 lda #1
 sta xh_used,x
 lda #$00A0
 jmp xm_err

* xm_res - one end of a move: the handle and offset at
* xm_sh,y (y = 0 the source, 6 the destination) -> xm_ptr,
* the host pointer; C set when the handle (A = 0) or the
* offset and length (A = 1) are wrong. A handle of 0 is
* real memory, the offset a segment and an offset.
xm_res
 mx %00
 lda xm_sh,y
 bne :blk
 lda xm_sh+4,y             ; the segment
 asl
 asl
 asl
 asl
 clc
 adc xm_sh+2,y
 sta xm_ptr
 php
 lda xm_sh+4,y
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 plp
 adc #0
 sta xm_ptr+2
 lda xm_ptr                ; it ends within the megabyte
 clc
 adc xm_len
 sta xm_end
 lda xm_ptr+2
 adc xm_len+2
 cmp #$0010
 bcc :real
 bne :badoff
 lda xm_end
 bne :badoff
:real
 lda xm_ptr+2
 and #$000F
 ora #GUEST_BANK
 sta xm_ptr+2
 clc
 rts
:blk
 phy
 jsr xm_hand_a
 ply
 bcc :hok
 lda #0
 rts                       ; (C set)
:hok
 lda xm_sh+2,y             ; offset + length <= its KB * 1024
 clc
 adc xm_len
 sta xm_end
 lda xm_sh+4,y
 adc xm_len+2
 sta xm_end+2
 bcs :badoff
 lda xh_size,x
 lsr
 lsr
 lsr
 lsr
 lsr
 lsr
 cmp xm_end+2
 bcc :badoff
 bne :in
 lda xh_size,x
 and #$003F
 xba
 asl
 asl
 cmp xm_end
 bcc :badoff
:in
 lda xh_start,x            ; the region + its KB * 1024 + the offset
 and #$003F
 xba
 asl
 asl
 clc
 adc xm_sh+2,y
 sta xm_ptr
 php
 lda xh_start,x
 lsr
 lsr
 lsr
 lsr
 lsr
 lsr
 plp
 adc xm_sh+4,y
 clc
 adc #DISK_BANK
 and #$00FF
 sta xm_ptr+2
 clc
 rts
:badoff
 lda #1
 sec
 rts

xm_move                    ; 0Bh: DS:SI = length, handle, offset, handle, offset
 mx %00
 lda rSI
 ldx #bDS
 jsr gptr
 ldy #0
:cp
 lda [pGST],y
 sta xm_len,y
 iny
 iny
 cpy #16
 bcc :cp
 lda xm_len
 lsr
 bcc :even
 lda #$00A7                ; an odd length
 jmp xm_err
:even
 ldy #0
 jsr xm_res
 bcc :sok
 adc #$00A2                ; (C set) A3 the handle, A4 the offset
 jmp xm_err
:sok
 lda xm_ptr
 sta pARG
 lda xm_ptr+2
 sta pARG+2
 ldy #6
 jsr xm_res
 bcc :dok
 adc #$00A4                ; A5, A6
 jmp xm_err
:dok
 lda xm_ptr
 sta pGST
 lda xm_ptr+2
 sta pGST+2
:loop
 lda xm_len
 ora xm_len+2
 beq :done
 lda #$FFFF                ; a run: to the end of either bank, or of the move
 sec
 sbc pARG
 sta xm_c
 lda #$FFFF
 sec
 sbc pGST
 cmp xm_c
 bcs :k1
 sta xm_c
:k1
 lda xm_len+2
 bne :go
 lda xm_len
 dec
 cmp xm_c
 bcs :go
 sta xm_c
:go
 sep #$20
 mx %10
 lda pGST+2
 sta :mv+1
 lda pARG+2
 sta :mv+2
 rep #$20
 mx %00
 ldx pARG
 ldy pGST
 lda xm_c
 phb
:mv
 hex 540000                ; mvn source,destination: the banks stored above
 plb
 lda xm_c                  ; both on by the run (xm_c + 1)
 sec
 adc pARG
 sta pARG
 bcc :a1
 inc pARG+2
:a1
 lda xm_c
 sec
 adc pGST
 sta pGST
 bcc :a2
 inc pGST+2
:a2
 lda xm_len
 clc
 sbc xm_c
 sta xm_len
 bcs :loop
 dec xm_len+2
 bra :loop
:done
 jmp xm_ok
