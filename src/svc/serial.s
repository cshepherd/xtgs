*----------------------------------------------------------
* serial.s - the IIGS's serial ports as the PC's COM1 and COM2
* (docs/serial.md). XTGS.CMD's lines COM1=MODEM and
* COM2=PRINTER (rd_readcfg), either or both.
*
* The PC has an 8250 at 3F8h-3FFh on IRQ4 (COM1) and one at
* 2F8h-2FFh on IRQ3 (COM2), and the BIOS's INT 14h. Behind
* them are the two channels of the IIGS's Z8530 SCC: B, the
* modem port, is COM1 and A, the printer port, COM2. A channel
* is taken at the guest's first use of its port (com_open) and
* given back when the guest ends (com_close, from
* svc_sndclose). Everywhere here a port is its index, 0 for
* COM1 and 2 for COM2 (com_p; half of it, com_c, is what is
* added to channel B's two addresses for the channel):
*
*   receive   the SCC interrupts for each character (com_irq,
*             ahead of the firmware's interrupt manager) and it
*             goes into the port's ring of 256 (COM_BUF), which
*             is what the guest reads at the port: so a
*             character is not lost while a service call runs,
*             as long as the guest takes them at the line's
*             rate on the whole.
*   transmit  a write to the port waits for the SCC's transmit
*             buffer and writes it; no ring, no interrupt.
*   the line  the divisor latch is the SCC's time constant
*             less 2 (both divide 115200: the SCC's clock is
*             the 3.6864 MHz crystal, x16), so 300 to 57600
*             baud; a divisor of 1 (115200) is run at 57600.
*             Data bits, stop bits, parity and break as the
*             line control register says.
*   modem     DTR (MCR bit 0) is the port's handshake output;
*             RTS stays on (it enables the IIGS's line driver).
*             CTS is the handshake input, DCD the port's
*             general-purpose input, DSR always on.
*   the IRQ   asked of the core (PIC_IRQ4 and, two bytes on,
*             PIC_IRQ3; the slot) while OUT2 is set and an
*             enabled cause is there: received data (the ring
*             is not empty), or the transmitter empty (after a
*             write to the port, or when the cause is
*             enabled). No modem-status or line-status
*             interrupts.
*
* The SCC is reached in two steps (a register number, then
* the value) and the interrupt uses it too: every access here
* is under SEI. Following Apple's Technical Note #18 and
* ../fgx's serial driver: no hardware reset, WR9 is written
* 0Ah only (master enable, no vector), RR3 is read on channel
* A, channel A keeps the crystal (WR11), and nothing of the
* firmware's is replaced: its manager still sees every
* interrupt that is not one of our channels'.
*----------------------------------------------------------
SCC_B_CMD  = $E0C038         ; channel B, the modem port; channel A, the printer
SCC_A_CMD  = $E0C039         ; port, is one address on (RR3 is read there)
SCC_B_DATA = $E0C03A
SERVEC     = $E10010         ; the firmware's JML to its interrupt manager: every interrupt
COM_TXWAIT = $4000           ; looks at the transmit buffer before a byte is given up

com_cfg    dw 0              ; XTGS.CMD: bit 0 COM1=MODEM, bit 1 COM2=PRINTER
com_old    ds 4              ; the vector's JML as it was
com_hook   dw 0              ; the vector is ours
com_p      dw 0              ; the port at hand: 0 COM1, 2 COM2
com_c      dw 0              ; and its channel: 0 B, 1 A
com_bit    dw 1,2            ; a port's bit in COM_ON and COM_OPEN (by com_p)
com_wr11   dw $50,$D0        ; WR11: the generator's clock; channel A has the crystal
u_ier      dw 0,0            ; the 8250s' registers as the guest wrote them
u_lcr      dw 3,3
u_mcr      dw 0,0
u_div      dw 12,12          ; the divisor latch: 9600
u_scr      dw 0,0
u_thre     dw 0,0            ; the transmitter-empty interrupt is waiting
u_msr      dw 0,0            ; CTS and DCD as last read (the delta bits)
u_lost     dw 0,0            ; COM_LOST as the line status last reported it
u_last     dw 0,0            ; the last character read
com_wr3    dw 0              ; the SCC's registers for the line at hand
com_wr4    dw 0
com_wr5    dw 0
com_tc     dw 0
com_t      dw 0
com_t2     dw 0
ci_p       dw 0              ; the interrupt's own: the port,
ci_c       dw 0              ; its channel,
ci_h       dw 0              ; the ring's head
ci_rr3     dw 0              ; and RR3 as it was read
ci_did     dw 0              ; a channel of ours was served
com_len3   dw $00,$80,$40,$C0   ; 5, 6, 7, 8 bits: WR3's bits 7-6
com_len5   dw $00,$40,$20,$60   ; and WR5's 6-5
com_bauds  dw 1047,768,384,192,96,48,24,12   ; INT 14h AH=0: 110 ... 9600

*--- com_bda: the BDA lists the ports XTGS.CMD named (rd_readcfg): the
* first at 40:00, as a PC lists the ones it finds.
com_bda
 mx %00
 lda com_cfg
 sta >COM_ON
 ldx #0
 lsr
 bcc :n1
 lda #$03F8
 sta >H_BDA,x
 inx
 inx
:n1
 lda com_cfg
 and #$0002
 beq :n2
 lda #$02F8
 sta >H_BDA,x
 inx
 inx
:n2
 txa                       ; how many: the equipment word's bits 9-11
 xba
 sta com_t
 lda >H_BDA+BDA_EQUIP
 and #$F1FF
 ora com_t
 sta >H_BDA+BDA_EQUIP
 rts

*--- com_sel: A = a port's base address (3F8h or 2F8h, the low three bits
* anything) -> com_p and com_c; C set if XTGS.CMD did not name that port.
com_sel
 mx %00
 ldx #0
 and #$0100                ; 3xxh: COM1
 bne :p
 ldx #2
:p
 stx com_p
 txa
 lsr
 sta com_c
 lda >COM_ON
 and com_bit,x
 beq :no
 lda >COM_OPEN             ; the channel is ours from here on
 and com_bit,x
 bne :ok
 jsr com_open
:ok
 clc
 rts
:no
 sec
 rts

com_open
 mx %00
 php
 sei
 ldx com_p
 lda #0
 sta >COM_HEAD,x
 sta >COM_TAIL,x
 sta >PIC_IRQ4,x
 lda com_hook
 bne :hooked
 lda >SERVEC               ; every interrupt comes here first
 sta com_old
 lda >SERVEC+2
 sta com_old+2
 lda #$005C
 sta >SERVEC
 lda #com_irq
 sta >SERVEC+1
 sep #$20
 mx %10
 lda #^com_irq
 sta >SERVEC+3
 rep #$20
 mx %00
 inc com_hook
:hooked
 jsr com_calc
 jsr com_prog
 sep #$30
 mx %11
 ldy #$01                  ; an interrupt for every character received
 lda #$10
 jsr scc_w
 ldy #$09                  ; master enable, no vector (as AppleTalk wants it left)
 lda #$0A
 jsr scc_w
 ldx com_c
 lda #$30                  ; error reset
 sta >SCC_B_CMD,x
 lda #$38                  ; reset highest IUS
 sta >SCC_B_CMD,x
 rep #$30
 mx %00
 ldx com_p
 lda >COM_OPEN
 ora com_bit,x
 sta >COM_OPEN
 plp
 rts

*--- com_close: the channels' interrupts off, the vector as it was.
com_close
 mx %00
 lda >COM_OPEN
 beq :out
 php
 sei
 ldx #2
:ch
 stx com_p
 txa
 lsr
 sta com_c
 lda >COM_OPEN
 and com_bit,x
 beq :next
 sep #$30
 mx %11
 ldx com_c
 lda >SCC_B_CMD,x
 ldy #$01
 lda #$00
 jsr scc_w
 rep #$30
 mx %00
:next
 ldx com_p
 lda #0
 sta >PIC_IRQ4,x
 dex
 dex
 bpl :ch
 lda com_hook
 beq :nohook
 lda com_old
 sta >SERVEC
 lda com_old+2
 sta >SERVEC+2
 stz com_hook
:nohook
 lda #0
 sta >COM_OPEN
 plp
:out
 rts

*--- scc_w: the channel's SCC register Y = A (8-bit both; interrupts off).
scc_w
 mx %11
 pha
 ldx com_c
 tya
 sta >SCC_B_CMD,x
 pla
 sta >SCC_B_CMD,x
 rts

*--- com_calc: the port's line control register, modem control register
* and divisor -> com_wr3, com_wr4, com_wr5, com_tc.
com_calc
 mx %00
 ldy com_p
 lda u_lcr,y
 and #$0003
 asl
 tax
 lda com_len3,x
 ora #$0001                ; receiver on
 sta com_wr3
 lda com_len5,x
 ora #$000A                ; transmitter on, RTS
 sta com_wr5
 lda u_mcr,y
 and #$0001
 beq :ndtr
 lda com_wr5
 ora #$0080
 sta com_wr5
:ndtr
 lda u_lcr,y
 and #$0040
 beq :nbrk
 lda com_wr5
 ora #$0010
 sta com_wr5
:nbrk
 lda #$0044                ; x16 clock, one stop bit
 sta com_wr4
 lda u_lcr,y
 and #$0004
 beq :stop1
 lda #$004C                ; two
 sta com_wr4
:stop1
 lda u_lcr,y
 and #$0008
 beq :npar
 lda com_wr4
 ora #$0001
 sta com_wr4
 lda u_lcr,y
 and #$0010
 beq :npar
 lda com_wr4
 ora #$0002                ; even
 sta com_wr4
:npar
 lda u_div,y
 sec
 sbc #2
 bcs :tc
 lda #0                    ; a divisor of 0 or 1: as fast as the SCC goes
:tc
 sta com_tc
 rts

*--- com_prog: the channel as com_calc left it (after ../fgx's
* scc_program_chanB: receiver and transmitter off while the clock changes).
com_prog
 mx %00
 php
 sei
 ldx com_p
 lda com_wr11,x
 sta com_t2
 sep #$30
 mx %11
 ldx com_c
 lda >SCC_B_CMD,x          ; (the register pointer to 0)
 ldy #$04
 lda com_wr4
 jsr scc_w
 ldy #$03
 lda com_wr3
 and #$FE
 jsr scc_w
 ldy #$05
 lda com_wr5
 and #$F7
 jsr scc_w
 ldy #$0B                  ; both clocks from the baud rate generator
 lda com_t2
 jsr scc_w
 ldy #$0C
 lda com_tc
 jsr scc_w
 ldy #$0D
 lda com_tc+1
 jsr scc_w
 ldy #$0E                  ; the generator off, then on
 lda #$00
 jsr scc_w
 ldy #$0E
 lda #$01
 jsr scc_w
 ldy #$03
 lda com_wr3
 jsr scc_w
 ldy #$05
 lda com_wr5
 jsr scc_w
 ldy #$0F                  ; no external/status interrupts
 lda #$00
 jsr scc_w
 plp
 mx %00
 rts

*--- com_irq: every interrupt, before the firmware's interrupt manager (any
* mode, any D and B; all given back). The firmware does not pass the
* SCC's interrupts on while its own serial firmware is idle: left to it,
* a received character interrupts for ever. So this looks at the SCC
* first: our channels' characters go into their rings, which takes the
* interrupt away, and it returns to what was interrupted (the firmware
* has pushed nothing by then: the processor's own frame is on the stack,
* three bytes from emulation mode and four from native). Passing it on
* as well would not do: under ProDOS 8 the firmware hands an interrupt it
* finds no cause for to ProDOS, which stops the machine at the 255th.
* Any other interrupt, and one of the SCC's that is not a channel of
* ours, goes to the firmware's manager as if this had not been here.
com_irq
 mx %00
 php
 clc
 xce                       ; native; C = the mode we came in
 php
 rep #$30
 mx %00
 pha
 phx
 phy
 phb
 phk
 plb
 sep #$20
 mx %10
 lda 8,s                   ; from emulation mode a BRK comes this way too:
 lsr                       ; that is never ours
 bcc :irq
 lda 10,s
 and #$10
 bne :pass
:irq
 lda #$03
 sta >SCC_A_CMD
 lda >SCC_A_CMD            ; RR3: who is asking
 sta ci_rr3
 stz ci_rr3+1
 stz ci_did
 stz ci_did+1
 and #$07                  ; channel B: COM1
 beq :na
 lda >COM_OPEN
 and #$01
 beq :na
 ldy #0
 jsr com_ch
 inc ci_did
 lda ci_rr3
 and #$F8
 sta ci_rr3
:na
 lda ci_rr3
 and #$38                  ; channel A: COM2
 beq :nb
 lda >COM_OPEN
 and #$02
 beq :nb
 ldy #2
 jsr com_ch
 inc ci_did
 lda ci_rr3
 and #$C7
 sta ci_rr3
 bra :nb
:pass
 stz ci_did
:nb
 rep #$20
 mx %00
 lda ci_did                ; not the SCC's at all: the firmware's
 beq :out
 lda ci_rr3                ; or something more there that was not ours
 and #$00FF
 bne :out
 plb                       ; it was the SCC's and it is dealt with: back to
 ply                       ; what was interrupted
 plx
 pla
 plp                       ; C = the mode we came in
 xce
 plp
 rti
:out
 plb
 ply
 plx
 pla
 plp
 xce
 plp
 jmp com_old

*--- com_ch: the interrupt's work for port Y: every character the channel
* has, into the port's ring. 8-bit A, 16-bit X and Y, B = this bank.
com_ch
 mx %10
 sty ci_p
 rep #$20
 mx %00
 tya
 lsr
 sta ci_c
 sep #$20
 mx %10
:rx
 ldx ci_c
 lda >SCC_B_CMD,x          ; RR0: a character there?
 and #$01
 beq :done
 lda #$01
 sta >SCC_B_CMD,x
 lda >SCC_B_CMD,x          ; RR1: how it arrived
 pha
 lda >SCC_B_DATA,x
 rep #$20
 mx %00
 and #$00FF
 pha
 ldx ci_p
 lda >COM_HEAD,x
 sta ci_h
 inc
 and #$00FF
 cmp >COM_TAIL,x
 beq :full
 sta >COM_HEAD,x
 lda ci_c                  ; the port's ring: 256 bytes a port
 xba
 ora ci_h
 tax
 pla
 sep #$20
 mx %10
 sta >COM_BUF,x
 bra :err
:full
 mx %00
 pla
 jsr :lost
 sep #$20
:err
 mx %10
 pla
 and #$70                  ; parity, overrun, framing
 beq :rx
 and #$20
 beq :nover
 rep #$20
 mx %00
 jsr :lost
 sep #$20
:nover
 mx %10
 ldx ci_c
 lda #$30                  ; error reset
 sta >SCC_B_CMD,x
 bra :rx
:done
 ldx ci_c
 lda #$38                  ; reset highest IUS
 sta >SCC_B_CMD,x
 rep #$20
 mx %00
 ldx ci_p
 lda >COM_IRQS,x
 inc
 sta >COM_IRQS,x
 lda u_ier,x               ; the PC's interrupt, if the guest wants one for this
 and #$0001
 beq :noirq
 lda u_mcr,x
 and #$0008
 beq :noirq
 lda #1
 sta >PIC_IRQ4,x
:noirq
 sep #$20
 mx %10
 rts
:lost
 mx %00
 ldx ci_p
 lda >COM_LOST,x
 inc
 sta >COM_LOST,x
 rts

*--- com_level: the port's interrupt line as the 8250 would have it now.
com_level
 mx %00
 php
 sei
 ldx com_p
 lda u_mcr,x
 and #$0008
 beq :low
 lda u_ier,x
 and #$0001
 beq :t
 lda >COM_HEAD,x
 cmp >COM_TAIL,x
 bne :high
:t
 lda u_ier,x
 and #$0002
 beq :low
 lda u_thre,x
 bne :high
:low
 lda #0
 sta >PIC_IRQ4,x
 plp
 rts
:high
 lda #1
 sta >PIC_IRQ4,x
 plp
 rts

*--- com_get: the ring's next character -> A, C clear; C set when it is empty.
com_get
 mx %00
 ldx com_p
 lda >COM_TAIL,x
 cmp >COM_HEAD,x
 beq :none
 sta com_t
 inc
 and #$00FF
 sta >COM_TAIL,x
 lda com_c
 xba
 ora com_t
 tax
 lda >COM_BUF,x
 and #$00FF
 ldx com_p
 sta u_last,x
 clc
 rts
:none
 sec
 rts

*--- com_tx: A = a byte for the line. Waits for the SCC's transmit buffer.
com_tx
 mx %00
 sta com_t
 ldy #COM_TXWAIT
:w
 jsr com_rr0
 and #$0004
 bne :go
 dey
 bne :w
:go
 ldx com_c
 sep #$20
 mx %10
 lda com_t
 sta >SCC_B_DATA,x
 rep #$20
 mx %00
 rts

*--- com_rr0: A = the channel's RR0 (bit 0 a character, 2 the transmit
* buffer empty, 3 DCD, 5 CTS). Keeps Y.
com_rr0
 mx %00
 ldx com_c
 php
 sei
 sep #$20
 mx %10
 lda >SCC_B_CMD,x
 plp
 mx %00
 and #$00FF
 rts

*--- com_lsr: A = the line status register.
com_lsr
 mx %00
 stz com_t2
 ldx com_p
 lda >COM_HEAD,x
 cmp >COM_TAIL,x
 beq :ndr
 inc com_t2                ; data ready
:ndr
 jsr com_rr0
 and #$0004
 beq :nth
 lda com_t2
 ora #$0060                ; holding register and transmitter empty
 sta com_t2
:nth
 ldx com_p
 lda >COM_LOST,x
 cmp u_lost,x
 beq :nov
 sta u_lost,x
 lda com_t2
 ora #$0002                ; overrun, once
 sta com_t2
:nov
 lda com_t2
 rts

*--- com_msr: A = the modem status register.
com_msr
 mx %00
 jsr com_rr0
 sta com_t
 lda #$0020                ; DSR
 sta com_t2
 lda com_t
 and #$0020                ; CTS
 beq :ncts
 lda com_t2
 ora #$0010
 sta com_t2
:ncts
 lda com_t
 and #$0008                ; DCD
 beq :ndcd
 lda com_t2
 ora #$0080
 sta com_t2
:ndcd
 ldx com_p
 lda com_t2
 eor u_msr,x
 sta com_t                 ; what changed since the last read
 lda com_t2
 sta u_msr,x
 lda com_t
 and #$0010
 beq :n1
 lda com_t2
 ora #$0001
 sta com_t2
:n1
 lda com_t
 and #$0080
 beq :n2
 lda com_t2
 ora #$0008
 sta com_t2
:n2
 lda com_t2
 rts

*--- com_out: a write of tmp0 to port A, 3F8h-3FFh or 2F8h-2FFh.
com_out
 mx %00
 pha
 jsr com_sel
 pla
 bcc :have
 rts
:have
 and #$0007
 asl
 tax
 lda tmp0
 and #$00FF
 sta com_t
 ldy com_p
 jmp (:tab,x)
:tab da :thr,:ier,:none,:lcr,:mcr,:none,:none,:scr
:thr
 lda u_lcr,y
 and #$0080
 bne :dll
 lda com_t
 jsr com_tx
 ldx com_p
 lda #1
 sta u_thre,x
 jmp com_level
:dll
 lda u_div,y
 and #$FF00
 ora com_t
 sta u_div,y
 bra :line
:ier
 lda u_lcr,y
 and #$0080
 bne :dlm
 lda com_t
 and #$0002
 beq :ier2
 lda u_ier,y
 and #$0002
 bne :ier2
 lda #1                    ; enabled with the transmitter empty: it interrupts
 sta u_thre,y
:ier2
 lda com_t
 and #$000F
 sta u_ier,y
 jmp com_level
:dlm
 lda com_t
 xba
 sta com_t
 lda u_div,y
 and #$00FF
 ora com_t
 sta u_div,y
 bra :line
:lcr
 lda com_t
 sta u_lcr,y
:line
 jsr com_calc
 jmp com_prog
:mcr
 lda com_t
 and #$001F
 sta u_mcr,y
 jsr com_calc
 php                       ; DTR: WR5 alone
 sei
 sep #$30
 mx %11
 ldx com_c
 lda >SCC_B_CMD,x
 ldy #$05
 lda com_wr5
 jsr scc_w
 plp
 mx %00
 jmp com_level
:scr
 lda com_t
 sta u_scr,y
:none
 rts

*--- com_in: a read of port A, 3F8h-3FFh or 2F8h-2FFh -> A (FFh for a
* port XTGS.CMD did not name).
com_in
 mx %00
 pha
 jsr com_sel
 pla
 bcc :have
 lda #$00FF
 rts
:have
 and #$0007
 asl
 tax
 ldy com_p
 jmp (:tab,x)
:tab da :rbr,:ier,:iir,:lcr,:mcr,:lsr,:msr,:scr
:rbr
 lda u_lcr,y
 and #$0080
 bne :dll
 jsr com_get
 bcc :got
 ldx com_p
 lda u_last,x              ; nothing new: the register still holds the last
 rts
:got
 pha
 jsr com_level             ; (the next one in the ring asks again)
 pla
 rts
:dll
 lda u_div,y
 and #$00FF
 rts
:ier
 lda u_lcr,y
 and #$0080
 bne :dlm
 lda u_ier,y
 rts
:dlm
 lda u_div,y
 xba
 and #$00FF
 rts
:iir
 lda u_ier,y
 and #$0001
 beq :i2
 ldx com_p
 lda >COM_HEAD,x
 cmp >COM_TAIL,x
 beq :i2
 lda #$0004                ; received data
 rts
:i2
 lda u_ier,y
 and #$0002
 beq :i0
 lda u_thre,y
 beq :i0
 lda #0                    ; reading it is what clears this one
 sta u_thre,y
 jsr com_level
 lda #$0002
 rts
:i0
 lda #$0001                ; none
 rts
:lcr
 lda u_lcr,y
 rts
:mcr
 lda u_mcr,y
 rts
:lsr
 jmp com_lsr
:msr
 jmp com_msr
:scr
 lda u_scr,y
 rts

*=== INT 14h: the BIOS's serial ports ========================
* DX = the port, as the BDA lists them (40:00 on). AH=0 set the line
* from AL, 1 send AL, 2 receive into AL (a second's wait), 3 status.
* AH = the line status (bit 7: timed out), and for 0 and 3 AL = the
* modem status. A port that is not there: AH = 80h.
int_14
 mx %00
 lda >COM_ON
 bne :have
 jmp int_default
:have
 lda rDX
 cmp #4
 bcs :noport
 asl
 tax
 lda >H_BDA,x
 beq :noport
 jsr com_sel
 bcc :port
:noport
 lda #$80
 jmp set_ah
:port
 jsr ah_val
 beq :init
 cmp #1
 beq :send
 cmp #2
 beq :recv
 cmp #3
 beq :stat
 rts
:init
 ldy com_p
 lda rAX
 and #$001F
 sta u_lcr,y
 lda rAX
 and #$00E0
 lsr
 lsr
 lsr
 lsr
 tax
 lda com_bauds,x
 sta u_div,y
 jsr com_calc
 jsr com_prog
:stat
 jsr com_msr
 jsr set_al
 jsr com_lsr
 jmp set_ah
:send
 lda rAX
 and #$00FF
 jsr com_tx
 jsr com_lsr
 jmp set_ah
:recv
 ldy #120                  ; a second: 120 edges of the vertical blank
:w
 jsr com_get
 bcc :got
 lda >VBLBAR
 and #$0080
 cmp sv9
 beq :w
 sta sv9
 dey
 bne :w
 lda #$80
 jmp set_ah
:got
 jsr set_al
 jsr com_level
 jsr com_lsr
 and #$001E
 jmp set_ah
