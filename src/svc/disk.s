*----------------------------------------------------------
* disk.s - Mode B (disk boot): INT 13h disk services against
* the raw image loaded into host banks from DISK_BASE, plus
* the boot setup and the timer-tick BIOS handler.
*
* svc_bootinit builds the same stub BIOS/IVT/BDA as Mode A,
* loads the image's sector 0 to guest 0000:7C00, and leaves
* the core to enter it with DL=0 (floppy A), DS=ES=SS=0.
* The guest's own DOS kernel then installs INT 20h-2Fh; our
* stubs keep serving INT 10h/13h/16h/1Ah/11h/12h and the
* IRQ0 timer (INT 08h).
*
* Under the S command there is no image: the shared folder
* is the boot drive (redir.s). svc_bootinit loads its
* KERNEL.SYS the way FreeDOS's boot sector would and
* returns 1 for the core to enter it (2: there is none),
* the PC has no disk drive, and INT 13h says so.
*----------------------------------------------------------
disk_lba   ds 4              ; working LBA (SVC bank)
disk_cnt   dw 0              ; sectors this call
cur_spt    dw 18             ; sectors/track: the image's size says, or its BPB
cur_cyls   dw 80             ; cylinders
cur_type   dw 4              ; INT 13h AH=08's drive type in BL
disk_have  dw 1              ; 0: no image (the S command)
boot_res   dw 0              ; what svc_bootinit returns

svc_bootinit
 mx %00
 phb
 phk
 plb
 stz rd_boot
 stz boot_res
 lda #1
 sta disk_have
 lda >MB_CMD+1
 and #$00FF
 cmp #'S'
 bne :img
 sta rd_boot
 stz disk_have
:img
 jsr init_diag
 lda #0
 sta >KBD_QHEAD            ; empty the hardware-keyboard scancode ring
 sta >KBD_QTAIL
 jsr kb_reset              ; no key down, no modifier sent
 jsr ports_init            ; the 8259 as a BIOS leaves it, the 765 idle
 jsr build_stubs
 jsr build_ivt
 jsr build_bda
 lda disk_have
 bne :fd
 lda >H_BDA+BDA_EQUIP      ; no floppy drive
 and #$FF3E
 sta >H_BDA+BDA_EQUIP
:fd
 jsr rd_setup              ; a shared ProDOS directory? (redir.s)
 lda #0
 sta >MB_INT13N
 sta >MB_BOOTTRC
 lda disk_have
 bne :sector
 lda #1                    ; S: the kernel from the share
 sta boot_res
 jsr rd_kernel
 bcc :loaded
 inc boot_res
:loaded
 lda >GUEST_BASE+KERNEL_LIN
 sta >MB_BOOTTRC
 bra :screen
:sector
* Load sector 0 (the boot sector) to guest 0000:7C00.
 stz disk_lba
 stz disk_lba+2
 lda #1
 sta disk_cnt
 lda #BOOT_LIN             ; guest linear 7C00 -> host $20:7C00
 sta pGST
 lda #GUEST_BANK
 sta pGST+2
 jsr disk_copy_in
 jsr disk_geom             ; 320K/360K/720K/1.2M/1.44M alike
 lda >GUEST_BASE+$7DFE     ; boot sector signature (AA55) -> boot trace
 sta >MB_BOOTTRC
:screen
 jsr init_shr
 jsr vid_clear
 jsr post_banner          ; PC-style BIOS sign-on at the top of the screen
 jsr rd_banner            ; the shared drive's line, and the blank one
 lda boot_res
 cmp #2
 bne :show
 jsr rd_nokernel
:show
 jsr flush
 plb
 lda >boot_res
 rtl

* disk_geom - the geometry of the image. A floppy's size names its
* format, and a disk need not have a BPB to say so (Minix's has code
* there); for any other size the BPB's sectors/track, or 1.44 MB's.
disk_geom
 mx %00
 lda >MB_FILELEN+1         ; bytes >> 9: sectors
 lsr
 sta sv0
 lda >MB_FILELEN+2
 and #$FF00
 beq :small
 lda #$FFFF
 sta sv0
:small
 ldx #0
:find
 lda geo_secs,x
 beq :bpb
 cmp sv0
 beq :got
 txa
 clc
 adc #8
 tax
 bra :find
:got
 lda geo_secs+2,x
 sta cur_spt
 lda geo_secs+4,x
 sta cur_cyls
 lda geo_secs+6,x
 sta cur_type
 rts
:bpb
 lda #DISK_CYLS
 sta cur_cyls
 lda #4
 sta cur_type
 lda >GUEST_BASE+$7C18     ; BPB sectors/track (offset 0x18)
 and #$00FF
 beq :dflt
 cmp #64
 bcc :spt
:dflt
 lda #DISK_SPT             ; a boot sector with no BPB: assume 1.44 MB
:spt
 sta cur_spt
 rts
geo_secs   dw 640,8,40,1     ; sectors, sectors/track, cylinders, type
           dw 720,9,40,1
           dw 1440,9,80,3
           dw 2400,15,80,2
           dw 2880,18,80,4
           dw 0

* disk_copy_in - copy disk_cnt sectors from LBA disk_lba into
* [pGST] (host pointer). pGST advances. Clobbers A,X,Y,sv*.
disk_copy_in
 mx %00
 lda disk_cnt
 beq :done
:sector
 jsr disk_src             ; pIMG = DISK_BASE + LBA*512
 ldy #0
 ldx #0
:w
 lda [pIMG],y             ; 256 words = 512 bytes
 sta [pGST],y
 iny
 iny
 inx
 cpx #256
 bcc :w
 lda pGST                 ; advance guest by 512
 clc
 adc #512
 sta pGST
 bcc :ng
 inc pGST+2
:ng
 inc disk_lba             ; next LBA
 bne :nl
 inc disk_lba+2
:nl
 dec disk_cnt
 bne :sector
:done
 rts

* disk_src - pIMG = DISK_BASE + disk_lba*512. The image is at
* host bank DISK_BANK; LBA*512 = (LBA>>7) banks + (LBA&7F)<<9.
disk_src
 mx %00
 lda disk_lba
 and #$007F
 asl                      ; <<9 (but asl once here, then put <<8 via xba)
 xba                      ; (LBA&7F) << 9 as a 16-bit offset
 and #$FE00
 sta pIMG
 lda disk_lba
 lsr                      ; LBA >> 7 -> bank offset
 lsr
 lsr
 lsr
 lsr
 lsr
 lsr
 sta sv8
 lda disk_lba+1           ; high bits of LBA contribute banks too
 asl                      ; LBA bit 8.. -> (LBA>>7) high
 and #$01FE
 ora sv8
 clc
 adc #DISK_BANK
 and #$00FF
 sta pIMG+2
 rts

*----------------------------------------------------------
* int_13 - the disk BIOS.
*----------------------------------------------------------
int_13
 mx %00
 lda >MB_INT13N                   ; count served calls (diagnostic)
 inc
 sta >MB_INT13N
 lda disk_have
 bne :disk
 jsr ah_val                ; no drive at all: a reset is fine, the questions
 cmp #$00                  ; get "none", anything else "not ready"
 beq :reset
 cmp #$01
 beq :status
 cmp #$08
 beq :none
 cmp #$15
 beq :none
 lda #$80
 jsr set_ah
 jmp set_cf
:none                      ; AH=08: no drives, type 0; AH=15h: AH=0, no such drive
 stz rAX
 stz rBX
 stz rCX
 stz rDX
 stz rDI
 jmp clr_cf
:disk
 jsr ah_val
 cmp #$00
 beq :reset
 cmp #$02
 bne :lj1
 jmp :read
:lj1
 cmp #$03
 bne :lj2
 jmp :write
:lj2
 cmp #$08
 bne :lj3
 jmp :params
:lj3
 cmp #$15
 beq :type
 cmp #$01
 beq :status
 cmp #$18
 beq :setmedia
 cmp #$41
 bne :lj4
 jmp :ext_check
:lj4
 cmp #$42
 bne :lj5
 jmp :ext_read
:lj5
 lda #$01                 ; unsupported: CF, AH=1
 jsr set_ah
 jmp set_cf
:reset
 lda #0
 jsr set_ah
 jmp clr_cf
:status
 lda #0
 jsr set_ah
 lda #0
 jsr set_al
 jmp clr_cf
:setmedia
 lda #0
 jsr set_ah
 jmp clr_cf
:type                     ; AH=01 floppy without change-line
 lda #1
 jsr set_ah
 jmp clr_cf
:params                   ; the geometry of the image
 lda #$0000               ; CH = max cylinder low, CL bits: sectors
 sta rAX                  ; AH = 0
 lda cur_cyls             ; CH
 dec
 xba
 ora cur_spt              ; CL = sectors/track (cyl high bits 0)
 sta rCX
 lda #$0101               ; DH = heads-1 (1), DL = drive count (1)
 sta rDX
 lda cur_type              ; BL = the drive type, ES:DI -> DPT (left 0)
 sta rBX
 stz rDI
 stz rES
 jsr svc_set_es
 jmp clr_cf
:read
 jsr chs_to_lba
 bcc :lj6
 jmp :geo_err
:lj6
 lda rAX
 and #$00FF
 sta disk_cnt
 beq :read_done
 ldx #bES
 lda rBX
 jsr gptr
 lda pGST
 sta sv6                  ; keep ES:BX; disk_copy_in advances pGST
 lda pGST+2
 sta sv7
 jsr disk_copy_in
:read_done
 lda rAX                  ; AL = sectors (unchanged), AH = 0
 and #$00FF
 sta rAX
 jmp clr_cf
:write
 jsr chs_to_lba
 bcs :geo_err
 lda rAX
 and #$00FF
 sta disk_cnt
 beq :write_done
 ldx #bES
 lda rBX
 jsr gptr
 jsr disk_copy_out
:write_done
 lda rAX
 and #$00FF
 sta rAX
 jmp clr_cf
:geo_err
 lda #$04                 ; sector not found
 jsr set_ah
 jmp set_cf
:ext_check                ; INT 13h/41h: floppies have no LBA extensions
 lda #$01
 jsr set_ah
 jmp set_cf
:ext_read                 ; INT 13h/42h: no extensions on a floppy
 lda #$01
 jsr set_ah
 jmp set_cf
:ext_read_unused
 ldx #bDS
 lda rSI
 jsr gptr
 ldy #2
 lda [pGST],y             ; block count
 and #$00FF
 sta disk_cnt
 ldy #8                   ; starting LBA (low 32 bits used)
 lda [pGST],y
 sta disk_lba
 ldy #10
 lda [pGST],y
 sta disk_lba+2
 ldy #4                   ; transfer buffer offset
 lda [pGST],y
 sta sv0
 ldy #6                   ; segment
 lda [pGST],y
 sta sv1
 lda sv0                  ; host pointer of the buffer
 clc
 adc #0
 sta vEA
 lda sv1
 asl
 asl
 asl
 asl
 clc
 adc sv0
 sta pGST
 lda sv1
 xba
 lsr
 lsr
 lsr
 lsr
 and #$000F
 adc #0
 and #$000F
 ora #GUEST_BANK
 sta pGST+2
 jsr disk_copy_in
 lda #0
 jsr set_ah
 jmp clr_cf

* disk_copy_out - like disk_copy_in but guest -> image.
disk_copy_out
 mx %00
 lda disk_cnt
 beq :done
:sector
 jsr disk_src
 ldy #0
 ldx #0
:w
 lda [pGST],y
 sta [pIMG],y
 iny
 iny
 inx
 cpx #256
 bcc :w
 lda pGST
 clc
 adc #512
 sta pGST
 bcc :ng
 inc pGST+2
:ng
 inc disk_lba
 bne :nl
 inc disk_lba+2
:nl
 dec disk_cnt
 bne :sector
:done
 rts

* chs_to_lba - CH=cyl low, CL bits6-7=cyl high + bits0-5=sector(1..),
* DH=head, into disk_lba. C set on a bad geometry.
chs_to_lba
 mx %00
 lda rCX
 and #$003F               ; sector 1..63
 bne :lj7
 jmp :bad
:lj7
 dec
 sta sv2                  ; sector-1
 cmp cur_spt
 bcc :lj8
 jmp :bad                 ; a sector the track has not: "not found"
:lj8
 lda rCX
 and #$00C0               ; cyl high bits
 asl
 asl                      ; -> bits 8-9
 sta sv3
 lda rCX
 xba
 and #$00FF               ; CH = cyl low
 ora sv3
 sta sv4                  ; cylinder
 cmp cur_cyls
 bcs :bad
 lda rDX
 xba
 and #$00FF               ; DH = head
 sta sv5
 cmp #DISK_HEADS
 bcs :bad
 ; lba = (cyl*heads + head)*spt + sector-1
 lda sv4
 ldx #DISK_HEADS
 jsr mul_small            ; A = cyl*heads (heads=2 -> asl)
 clc
 adc sv5
 sta sv8                  ; cyl*heads+head
 jsr mul_track            ; sv8 * cur_spt -> A (16-bit; images are small)
 clc
 adc sv2
 sta disk_lba
 lda #0
 adc #0
 sta disk_lba+2
 clc
 rts
:bad
 sec
 rts
mul_small                  ; A * 2 (heads=2); X ignored (specialised)
 mx %00
 asl
 rts
mul_track                  ; sv8 * cur_spt -> A (cur_spt is 8/9/15/18...)
 mx %00
 lda #0
 ldx cur_spt
 beq :done                ; guard: never divide the geometry by zero
:loop
 clc
 adc sv8
 dex
 bne :loop
:done
 rts

*----------------------------------------------------------
* int_08 - IRQ0 timer: bump the BDA tick. The stub at
* F000:TICK_OFF (build_stubs) then chains INT 1Ch itself.
*----------------------------------------------------------
int_08
 mx %00
 jmp clk_tick              ; (clock.s: the count, midnight)

*----------------------------------------------------------
* int_19 - bootstrap loader: a guest that calls it wants to
* reboot. Treat it as "stop" (the run ends).
*----------------------------------------------------------
int_19
 mx %00
 lda #$B007               ; a marker exit code for "guest asked to reboot"
 sta exit_code
 lda #1
 sta stop_flag
 rts
