*----------------------------------------------------------
* ops_misc.s - flag instructions, IN/OUT, WAIT, SALC, ESC.
*----------------------------------------------------------

op_F5                      ; cmc
 mx %00
 lda rFL
 eor #F_CF
 sta rFL
 jmp (NEXTVEC)
op_F8                      ; clc
 mx %00
 lda rFL
 and #$FFFF-F_CF
 sta rFL
 jmp (NEXTVEC)
op_F9                      ; stc
 mx %00
 lda rFL
 ora #F_CF
 sta rFL
 jmp (NEXTVEC)
op_FA                      ; cli
 mx %00
 lda rFL
 and #$FFFF-F_IF
 sta rFL
 jmp (NEXTVEC)
op_FB                      ; sti
 mx %00
 lda rFL
 ora #F_IF
 sta rFL
 jmp (NEXTVEC)
op_FC                      ; cld
 mx %00
 lda rFL
 and #$FFFF-F_DF
 sta rFL
 jmp (NEXTVEC)
op_FD                      ; std
 mx %00
 lda rFL
 ora #F_DF
 sta rFL
 jmp (NEXTVEC)
op_9B                      ; wait
 mx %00
 jmp (NEXTVEC)
op_D6                      ; salc (undocumented): AL = CF ? $FF : 0
 mx %00
 sep #$20
 mx %10
 lda rFL
 and #F_CF
 beq :z
 lda #$FF
:z
 sta rAX
 rep #$20
 mx %00
 jmp (NEXTVEC)

*--- ports: mostly open bus. The CGA status register 3DAh is
* special: GW-BASIC (and other CGA code) polls its display-enable
* (bit 0) and vertical-retrace (bit 3) bits and waits on the edges
* before touching video memory. Return a value that toggles both
* each read so those wait loops always terminate promptly.
cga_stat   dw 0
port_in8                   ; A = port -> A = value (8-bit in the low byte)
 mx %00
 cmp #$03DA
 beq :cgastat
 lda #$00FF
 rts
:cgastat
 lda cga_stat              ; free-running: all (bit0,bit3) states appear
 inc
 sta cga_stat
 and #$00FF
 rts
port_in16
 mx %00
 cmp #$03DA
 beq :cgastat
 lda #$FFFF
 rts
:cgastat
 lda cga_stat
 inc
 sta cga_stat
 and #$00FF
 ora #$FF00
 rts
port_out                   ; A = port, tmp0 = value
 mx %00
 rts
op_E4                      ; in AL, imm8
 mx %00
 lda [bCS],y
 iny
 and #$00FF
 jsr port_in8
 sep #$20
 mx %10
 sta rAX
 rep #$20
 mx %00
 jmp (NEXTVEC)
op_E5                      ; in AX, imm8
 mx %00
 lda [bCS],y
 iny
 and #$00FF
 jsr port_in16
 sta rAX
 jmp (NEXTVEC)
op_EC                      ; in AL, DX
 mx %00
 lda rDX
 jsr port_in8
 sep #$20
 mx %10
 sta rAX
 rep #$20
 mx %00
 jmp (NEXTVEC)
op_ED                      ; in AX, DX
 mx %00
 lda rDX
 jsr port_in16
 sta rAX
 jmp (NEXTVEC)
op_E6                      ; out imm8, AL
 mx %00
 lda rAX
 and #$00FF
 sta tmp0
 lda [bCS],y
 iny
 and #$00FF
 jsr port_out
 jmp (NEXTVEC)
op_E7                      ; out imm8, AX
 mx %00
 lda rAX
 sta tmp0
 lda [bCS],y
 iny
 and #$00FF
 jsr port_out
 jmp (NEXTVEC)
op_EE                      ; out DX, AL
 mx %00
 lda rAX
 and #$00FF
 sta tmp0
 lda rDX
 jsr port_out
 jmp (NEXTVEC)
op_EF                      ; out DX, AX
 mx %00
 lda rAX
 sta tmp0
 lda rDX
 jsr port_out
 jmp (NEXTVEC)

*--- ESC (8087): decode the operand, do nothing
op_D8
 mx %00
op_D9
op_DA
op_DB
op_DC
op_DD
op_DE
op_DF
 jsr modrm_w
 jmp (NEXTVEC)
