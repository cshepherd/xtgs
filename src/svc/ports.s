*----------------------------------------------------------
* ports.s - Mode B: the chips a guest that does not go
* through the BIOS talks to (Minix; docs/minix.md). The
* core sends here every port it does not answer itself:
*
*   20h/21h    the 8259: where the interrupts go (ICW2) and
*              which are held back (the mask), kept in
*              PIC_BASE and PIC_MASK for the slot in cpu.s.
*              An EOI is accepted and means nothing.
*   04h/05h, 08h, 0Ch, 81h
*              the 8237's channel 2: the address and count
*              of the diskette controller's next transfer.
*   3F2h, 3F4h, 3F5h
*              the 765 diskette controller: seek, read and
*              write on the image INT 13h serves (disk.s),
*              done at once, IRQ6 (PIC_IRQ6) at the next slot.
*
* One drive, with the disk the image is. A command for
* another drive ends "not ready"; a sector the disk has
* not, or a read with the head on another cylinder, ends
* "no data", which is how a driver that tries one format
* after another finds the right one.
*----------------------------------------------------------
pic_step   dw 0              ; the ICW port 21h takes next (2-4); 0: it is the mask
pic_icw1   dw 0
dma_ff     dw 0              ; the 8237's byte flip-flop: 0 = low byte next
dma_addr   dw 0              ; channel 2: address (the low 16 bits)
dma_cnt    dw 0              ; bytes - 1 (follows dma_addr: dma_wr indexes)
dma_page   dw 0              ; bits 16-19 (port 81h)
dma_stat   dw 0              ; bit 2: channel 2 has reached its count
fdc_dor    dw $000C          ; port 3F2h as last written
fdc_n      dw 0              ; command bytes taken so far
fdc_need   dw 0              ; how many the command has
fdc_cmd    ds 10
fdc_rn     dw 0              ; result bytes to give
fdc_ri     dw 0              ; the next one
fdc_res    ds 8
fdc_st0    dw $0080          ; SENSE INTERRUPT STATUS's answer; $80: nothing to report
fdc_pcn    ds 4              ; the cylinder each drive's head is at
fdc_c      dw 0
fdc_h      dw 0
fdc_r      dw 0
fdc_ns     dw 0              ; sectors in the transfer
fdc_part   dw 0              ; bytes of the last one when it is not whole
* bytes in a command, by its low five bits (1: it is not one)
fdc_len    hex 0101090302090902
           hex 0109020109060103
           hex 0101010101010101
           hex 0101010101010101

* ports_init - a PC's 8259 after its BIOS, an idle controller.
ports_init
 mx %00
 lda #8
 sta >PIC_BASE
 lda #0
 sta >PIC_MASK
 sta >PIC_IRQ6
 stz pic_step
 stz dma_ff
 stz dma_stat
 lda #$000C
 sta fdc_dor
 stz fdc_pcn
 stz fdc_pcn+2
* fdc_reset - the controller idle, nothing to report.
fdc_reset
 mx %00
 stz fdc_n
 stz fdc_rn
 stz fdc_ri
 lda #$0080
 sta fdc_st0
 rts

*----------------------------------------------------------
* svc_portout - a write to port A, the value in tmp0's low
* byte. Keeps Y (the core's IP).
*----------------------------------------------------------
svc_portout
 mx %00
 phb
 phk
 plb
 phy
 cmp #$03DA                ; 3DAh-3DFh: the Tandy's video array and page
 bcc :ntdy                 ; register (tandy.s; the .COM runner sends these
 cmp #$03E0                ; and the sound chip's, no others)
 bcs :ntdy
 jsr tdy_port
 bra :out
:ntdy
 cmp #$00C0                ; C0h-C7h: the Tandy's sound chip (sound.s; the
 bcc :npsg                 ; .COM runner sends these too)
 cmp #$00C8
 bcs :npsg
 jsr psg_write
 bra :out
:npsg
 cmp #$0021
 bne :n21
 jsr pic_data
 bra :out
:n21
 cmp #$0020
 bne :n20
 jsr pic_cmd
 bra :out
:n20
 cmp #$0004
 bne :n04
 ldx #0
 jsr dma_wr
 bra :out
:n04
 cmp #$0005
 bne :n05
 ldx #2
 jsr dma_wr
 bra :out
:n05
 cmp #$000C                ; any write clears the flip-flop
 bne :n0C
 stz dma_ff
 bra :out
:n0C
 cmp #$0081
 bne :n81
 lda tmp0
 and #$000F
 sta dma_page
 bra :out
:n81
 cmp #$03F2
 bne :n3F2
 jsr fdc_dorw
 bra :out
:n3F2
 cmp #$03F5
 bne :out
 jsr fdc_dataw
:out
 ply
 plb
 rtl

*----------------------------------------------------------
* svc_portin - a read of port A -> A (the low byte). Keeps Y.
*----------------------------------------------------------
svc_portin
 mx %00
 phb
 phk
 plb
 phy
 cmp #$0021
 bne :n21
 lda >PIC_MASK
 bra :out
:n21
 cmp #$0020                ; nothing requested, nothing in service
 bne :n20
 lda #0
 bra :out
:n20
 cmp #$03F4
 bne :n3F4
 jsr fdc_msr
 bra :out
:n3F4
 cmp #$03F5
 bne :n3F5
 jsr fdc_datar
 bra :out
:n3F5
 cmp #$0008                ; the 8237's status: read once
 bne :n08
 lda dma_stat
 stz dma_stat
 bra :out
:n08
 cmp #$0004
 bne :n04
 ldx #0
 jsr dma_rd
 bra :out
:n04
 cmp #$0005
 bne :nobody
 ldx #2
 jsr dma_rd
 bra :out
:nobody
 lda #$00FF
:out
 ply
 plb
 rtl

*--- the 8259
pic_cmd
 mx %00
 lda tmp0
 and #$0010
 beq :ocw                  ; an EOI, or which register to read: nothing
 lda tmp0                  ; ICW1: the vector base follows at port 21h
 sta pic_icw1
 lda #2
 sta pic_step
 lda #0
 sta >PIC_MASK
:ocw
 rts
pic_data
 mx %00
 lda pic_step
 bne :icw
 lda tmp0
 and #$00FF
 sta >PIC_MASK
 rts
:icw
 cmp #2
 bne :not2
 lda tmp0                  ; ICW2: IRQ0's vector
 and #$00F8
 sta >PIC_BASE
 lda pic_icw1
 and #$0002                ; one 8259: no ICW3
 bne :want4
 lda #3
 sta pic_step
 rts
:not2
 cmp #3
 bne :end                  ; that was ICW4
:want4
 lda pic_icw1
 and #$0001
 beq :end
 lda #4
 sta pic_step
 rts
:end
 stz pic_step
 rts

*--- the 8237, channel 2. X = 0 the address, 2 the count.
dma_wr
 mx %00
 lda tmp0
 and #$00FF
 sta sv0
 lda dma_ff
 bne :hi
 lda dma_addr,x
 and #$FF00
 ora sv0
 sta dma_addr,x
 inc dma_ff
 rts
:hi
 lda sv0
 xba
 sta sv0
 lda dma_addr,x
 and #$00FF
 ora sv0
 sta dma_addr,x
 stz dma_ff
 rts
dma_rd
 mx %00
 lda dma_ff
 bne :hi
 inc dma_ff
 lda dma_addr,x
 and #$00FF
 rts
:hi
 stz dma_ff
 lda dma_addr,x
 xba
 and #$00FF
 rts

*--- the 765
* fdc_irq - the controller's interrupt, when port 3F2h lets it out.
fdc_irq
 mx %00
 lda fdc_dor
 and #$0008
 beq :off
 lda #1
 sta >PIC_IRQ6
:off
 rts
* Port 3F2h: motors, drive select; bit 2 going up ends a reset, and
* the controller says so with an interrupt.
fdc_dorw
 mx %00
 lda fdc_dor
 eor #$FFFF
 and tmp0
 and #$0004
 tax                       ; nonzero: out of reset
 lda tmp0
 and #$00FF
 sta fdc_dor
 txa
 beq :same
 lda disk_have
 beq :same                 ; (no controller without a disk image)
 jsr fdc_reset
 lda #$00C0
 sta fdc_st0
 jsr fdc_irq
:same
 rts
* Port 3F4h: ready for a command byte, or a result byte is waiting.
fdc_msr
 mx %00
 lda disk_have
 beq :none
 lda fdc_dor
 and #$0004
 beq :held
 lda fdc_ri
 cmp fdc_rn
 bcc :result
 lda fdc_n
 beq :idle
 lda #$0090
 rts
:idle
 lda #$0080
 rts
:result
 lda #$00D0
 rts
:held
 lda #0
 rts
:none
 lda #$00FF
 rts
* Port 3F5h read: the next result byte.
fdc_datar
 mx %00
 ldx fdc_ri
 cpx fdc_rn
 bcs :none
 lda fdc_res,x
 and #$00FF
 inx
 stx fdc_ri
 cpx fdc_rn
 bcc :more
 stz fdc_ri
 stz fdc_rn
:more
 rts
:none
 lda #$00FF
 rts
* Port 3F5h write: a command byte; the last one runs the command.
fdc_dataw
 mx %00
 lda disk_have
 bne :have
 rts
:have
 stz fdc_rn                ; (results not collected are gone)
 stz fdc_ri
 ldx fdc_n
 sep #$20
 mx %10
 lda tmp0
 sta fdc_cmd,x
 rep #$20
 mx %00
 inx
 stx fdc_n
 cpx #1
 bne :more
 lda fdc_cmd
 and #$001F
 tax
 lda fdc_len,x
 and #$00FF
 sta fdc_need
:more
 lda fdc_n
 cmp fdc_need
 bcs :run
 rts
:run
 stz fdc_n
 lda fdc_cmd+1             ; most results start the same way: ST0 is the
 and #$0007                ; head and drive, ST1 and ST2 clear
 sta fdc_res
 stz fdc_res+1
 lda fdc_cmd
 and #$001F
 cmp #$03                  ; SPECIFY: step rate and head times
 bne :n03
 rts
:n03
 cmp #$08
 bne :n08
 jmp fdc_sense
:n08
 cmp #$0F
 bne :n0F
 jmp fdc_seek
:n0F
 cmp #$07
 bne :n07
 jmp fdc_recal
:n07
 cmp #$06
 bne :n06
 jmp fdc_xfer
:n06
 cmp #$05
 bne :n05
 jmp fdc_xfer
:n05
 cmp #$04
 bne :n04
 jmp fdc_drvst
:n04
 cmp #$0A
 bne :n0A
 jmp fdc_readid
:n0A
 cmp #$0D
 bne :bad
 jmp fdc_format
:bad
 lda #$0080                ; not a command
 sta fdc_res
 lda #1
 sta fdc_rn
 rts

* SENSE INTERRUPT STATUS: why the interrupt, and the cylinder.
fdc_sense
 mx %00
 lda fdc_st0
 sta fdc_res
 cmp #$0080
 beq :nothing
 and #$0003
 tax
 lda fdc_pcn,x
 and #$00FF
 xba
 ora fdc_st0
 sta fdc_res
 lda #$0080
 sta fdc_st0
 lda #2
 sta fdc_rn
 rts
:nothing
 lda #1
 sta fdc_rn
 rts
* SEEK and RECALIBRATE: the head is there at once.
fdc_seek
 mx %00
 lda fdc_cmd+2
 bra fdc_move
fdc_recal
 mx %00
 lda #0
fdc_move
 mx %00
 and #$00FF
 sta sv0
 lda fdc_cmd+1
 and #$0003
 tax
 sep #$20
 mx %10
 lda sv0
 sta fdc_pcn,x
 rep #$20
 mx %00
 txa
 beq :there
 ora #$0050                ; no such drive: abnormal end, equipment check
:there
 ora #$0020                ; seek end
 sta fdc_st0
 jmp fdc_irq
* SENSE DRIVE STATUS: ST3.
fdc_drvst
 mx %00
 lda fdc_cmd+1
 and #$0003
 bne :st3                  ; a drive that is not there: not ready
 lda fdc_res
 ora #$0028                ; ready, two sides
 sta fdc_res
 lda fdc_pcn
 and #$00FF
 bne :st3
 lda fdc_res
 ora #$0010                ; track 0
 sta fdc_res
:st3
 lda #1
 sta fdc_rn
 rts
* READ ID: the first sector header under the head.
fdc_readid
 mx %00
 lda fdc_cmd+1
 and #$0003
 bne fdc_notrdy
 lda fdc_pcn
 and #$00FF
 sta fdc_c
 cmp cur_cyls
 bcs fdc_nodata
 lda fdc_cmd+1
 lsr
 lsr
 and #$0001
 sta fdc_h
 lda #1
 sta fdc_r
 lda #2
 sta fdc_cmd+5
 jmp fdc_result
* FORMAT TRACK: the image has its sectors already.
fdc_format
 mx %00
 lda fdc_cmd+1
 and #$0003
 bne fdc_notrdy
 lda fdc_pcn
 and #$00FF
 sta fdc_c
 lda fdc_cmd+1
 lsr
 lsr
 and #$0001
 sta fdc_h
 lda #1
 sta fdc_r
 lda fdc_cmd+2
 sta fdc_cmd+5
 jmp fdc_result
* The ends of a command that did not transfer.
fdc_notrdy
 mx %00
 lda fdc_res
 ora #$0048                ; abnormal end, not ready
 sta fdc_res
 bra fdc_result
fdc_nodata
 mx %00
 lda fdc_res
 ora #$0440                ; abnormal end; ST1: no data
 sta fdc_res
* fdc_result - ST0 and ST1 are in fdc_res; ST2 clear, then C H R N.
fdc_result
 mx %00
 lda fdc_c
 xba
 and #$FF00                ; ST2 = 0, C
 sta fdc_res+2
 lda fdc_r
 xba
 ora fdc_h
 sta fdc_res+4             ; H, R
 lda fdc_cmd+5
 and #$00FF
 sta fdc_res+6             ; N
 lda #7
 sta fdc_rn
 stz fdc_ri
 jmp fdc_irq

* READ DATA and WRITE DATA: C H R N in the command, the address
* and length in the 8237, the image for the disk.
fdc_xfer
 mx %00
 lda fdc_cmd+2
 and #$00FF
 sta fdc_c
 lda fdc_cmd+3
 and #$00FF
 sta fdc_h
 lda fdc_cmd+4
 and #$00FF
 sta fdc_r
 lda fdc_cmd+1
 and #$0003
 bne :notrdy
 lda fdc_c
 cmp cur_cyls
 bcs :nodata
 lda fdc_pcn               ; the head has to be on that cylinder
 and #$00FF
 cmp fdc_c
 bne :nodata
 lda fdc_h
 cmp #DISK_HEADS
 bcs :nodata
 lda fdc_r
 beq :nodata
 dec
 cmp cur_spt
 bcs :nodata
 lda fdc_cmd+5             ; 512-byte sectors
 and #$00FF
 cmp #2
 bne :nodata
 bra :ok
:notrdy
 jmp fdc_notrdy
:nodata
 jmp fdc_nodata
:ok
 lda dma_cnt               ; sectors: the 8237's count ends the transfer
 xba
 and #$00FF
 lsr
 inc
 sta fdc_ns
 lda fdc_c
 asl
 clc
 adc fdc_h
 sta sv8
 jsr mul_track             ; (disk.s) tracks before this one * sectors a track
 clc
 adc fdc_r
 dec
 sta disk_lba
 stz disk_lba+2
 lda cur_cyls              ; not past the end of the disk
 asl
 sta sv8
 jsr mul_track
 sec
 sbc disk_lba
 cmp fdc_ns
 bcs :fits
 jmp fdc_nodata
:fits
 lda dma_addr
 sta pGST
 lda dma_page
 and #$000F
 ora #GUEST_BANK
 sta pGST+2
 stz fdc_part
 lda fdc_ns
 sta disk_cnt
 lda dma_cnt
 and #$01FF
 cmp #$01FF
 beq :whole
 inc
 sta fdc_part              ; the last sector in part
 dec disk_cnt
:whole
 lda fdc_cmd
 and #$001F
 cmp #$05
 beq :write
 jsr disk_copy_in
 lda fdc_part
 beq :moved
 jsr disk_src
 ldy #0
 sep #$20
 mx %10
:rb
 lda [pIMG],y
 sta [pGST],y
 iny
 cpy fdc_part
 bcc :rb
 rep #$20
 mx %00
 bra :moved
:write
 jsr disk_copy_out
 lda fdc_part
 beq :moved
 jsr disk_src
 ldy #0
 sep #$20
 mx %10
:wb
 lda [pGST],y
 sta [pIMG],y
 iny
 cpy fdc_part
 bcc :wb
 rep #$20
 mx %00
:moved
 lda dma_addr              ; the 8237 afterwards: past the data, count run out
 sec                       ; (count + 1 bytes)
 adc dma_cnt
 sta dma_addr
 lda #$FFFF
 sta dma_cnt
 lda dma_stat
 ora #$0004
 sta dma_stat
 lda fdc_r                 ; the sector after the last: over the end of a
 clc                       ; track to the other side, or the next cylinder
 adc fdc_ns
 sta fdc_r
:norm
 lda cur_spt
 cmp fdc_r
 bcs :done
 lda fdc_r
 sec
 sbc cur_spt
 sta fdc_r
 lda fdc_cmd
 and #$0080                ; multi-track
 beq :cyl
 lda fdc_h
 eor #$0001
 sta fdc_h
 bne :norm
:cyl
 inc fdc_c
 bra :norm
:done
 jmp fdc_result
