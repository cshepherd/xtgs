*----------------------------------------------------------
* pc.s - the emulated PC (Mode A, the .COM runner): guest
* memory map, BIOS data area fields, and the host-side
* capture/diagnostic area in bank $05.
*----------------------------------------------------------
PSP_SEG    = $1000           ; program segment prefix; the program at PSP:0100
ENV_SEG    = $0FE0           ; environment block (256 bytes at phys FE00)
BIOS_SEG   = $F000           ; stub BIOS: 256 five-byte hypercall stubs
TOP_PARA   = $A000           ; 640 KB

H_IVT      = GUEST_BASE          ; $200000
H_BDA      = GUEST_BASE+$400     ; $200400
H_ENV      = GUEST_BASE+$FE00    ; $20FE00
H_MCB      = GUEST_BASE+$FFF0    ; the one memory control block, below the PSP
H_PSP      = GUEST_BASE+$10000   ; $210000
H_COM      = GUEST_BASE+$10100   ; $210100  (the loader puts the .COM here)
H_TXTBANK  = GUEST_BASE+$B0000            ; text buffer bank; cells at $8000 + row*160 + col*2
H_TXT      = GUEST_BASE+$B8000
H_BIOS     = GUEST_BASE+$F0000   ; $2F0000
STUB_LEN   = 5                   ; FE 38 lo hi CF
CALL5_OFF  = $0500               ; PSP:0005's far target: mov ah,cl / int 21h / retf
DOSDATA_SEG = $F800              ; DOS's visible data: the fake DPB and list of lists
H_DOSDATA  = GUEST_BASE+$F8000
DPB_OFF    = $0040               ; DPB at F800:0040
LOL_OFF    = $0082               ; list of lists at F800:0082 (first MCB word at -2)
MCB_FIRST  = $0FFF               ; our one MCB, just below the PSP
VID_DIRTY  = RES_BASE+$A00       ; 128 bytes: a 256-byte page of B800-BFFF was
                                 ; written (core hook). Text uses pages 0-15 (4 KB);
                                 ; CGA graphics use 0-63 (the 16 KB framebuffer);
                                 ; the Tandy's 32K window all 128 (64 on are BC00)

* Mode B (disk boot): the disk image is loaded into host banks from
* DISK_BASE; INT 13h serves sectors from there. A 1.44 MB floppy is 23
* banks ($50-$66).
BOOT_LIN   = $7C00               ; the boot sector loads to 0000:7C00
KERNEL_SEG = $0060               ; the S command: KERNEL.SYS of the shared folder
KERNEL_LIN = $0600               ; loads to 0060:0000, as FreeDOS's boot sector
KERNEL_MAX = $40000              ; puts it (256 KB of it at most), and is entered
BOOTSTK_SEG = $1FE0              ; there with BL = 80h and that sector's stack,
BOOTSTK_SP = $7BA0               ; 1FE0:7BA0
DISK_SPT   = 18                  ; 1.44 MB floppy geometry
DISK_HEADS = 2
DISK_CYLS  = 80
MB_DISKLEN = RES_BASE+$808       ; u32 bytes of the image loaded
MB_INT13N  = RES_BASE+$80C       ; u16 INT 13h calls served (diagnostic)
MB_BOOTTRC = RES_BASE+$80E       ; u16 boot trace / stage

* BIOS data area (offsets from 0040:0000)
BDA_EQUIP  = $10             ; u16 equipment word
BDA_MEMKB  = $13             ; u16 conventional memory in KB
BDA_KBFLAG = $17             ; u8 shift flags
BDA_KBHEAD = $1A             ; u16 keyboard buffer head (offset in the BDA)
BDA_KBTAIL = $1C             ; u16 tail
BDA_KBBUF  = $1E             ; 16 words: $1E-$3D
BDA_KBEND  = $3E
BDA_VMODE  = $49             ; u8 video mode
BDA_COLS   = $4A             ; u16 columns
BDA_PGSIZE = $4C             ; u16 page size in bytes
BDA_PGOFF  = $4E             ; u16 page offset
BDA_CURPOS = $50             ; 8 x u16: col | row<<8
BDA_CURSHP = $60             ; u16 cursor shape (start<<8 | end)
BDA_PAGE   = $62             ; u8 active page
BDA_CRTC   = $63             ; u16 CRTC base port
BDA_MODESET = $65            ; u8 what the BIOS wrote to 3D8h
BDA_PALETTE = $66            ; u8 and to 3D9h
BDA_TICKS  = $6C             ; u32 timer ticks since midnight
BDA_MIDNT  = $70             ; u8 midnight flag
BDA_ROWS   = $84             ; u8 rows - 1
BDA_CHARHT = $85             ; u16 character height

* Host-side capture and diagnostics (bank $05, after the harness header)
CAP_LEN    = RES_BASE+$800   ; u16 bytes captured
DIAG_UNH   = RES_BASE+$802   ; u16 first unhandled: vector | AH<<8 ($FFFF none)
DIAG_UNHN  = RES_BASE+$804   ; u16 unhandled calls
DIAG_LAST  = RES_BASE+$806   ; u16 last INT 21h function seen (AH)
DIAG_FNMAP = RES_BASE+$810   ; 16 bytes: bit AH set for each unhandled/failed INT 21h function
DIAG_INTMAP = RES_BASE+$820  ; 32 bytes: bit n set for each unhandled INT n
* Hardware keyboard: a scancode ring the core serves at port 0x60 and the
* slot check delivers as IRQ1/INT 09h. Shared by CORE (port read, IRQ) and
* SVC (kb_poll: make when a key goes down, break when it is released). 32 entries, head==tail = empty.
KBD_QHEAD  = RES_BASE+$844   ; u16 read index (0..31)
KBD_QTAIL  = RES_BASE+$846   ; u16 write index (0..31)
KBD_QBUF   = RES_BASE+$850   ; 32 scancode bytes
KBD_QMASK  = $001F
CGA_MODEREQ = RES_BASE+$870  ; last value written to CGA mode-control port 0x3D8
CGA_MODECHG = RES_BASE+$872  ; nonzero: that write is pending (svc_vbl applies it)
CRTC_IDX   = RES_BASE+$87C   ; u16 the 6845 register selected through port 0x3D4
CRTC_REG   = RES_BASE+$880   ; 32 bytes: the 6845's registers as written through 0x3D5
                             ; (acted on: R9, the maximum scan line; R12/R13, where
                             ; the text screen starts in the 16 KB; R14/R15, the cursor)
T160_SHD   = RES_BASE+$8000  ; 16,000 bytes: the cells the 160x100 screen shows
T160_LEN   = 16000           ; 80 x 100 cells of two bytes
GFX_T160   = 160             ; gfx_mode in the 160x100 mode (4-6 are the BIOS's)
PIT_CTR    = RES_BASE+$874   ; free-running state for 8253 PIT reads (port 0x40/0x42)
SPK_PORT   = RES_BASE+$876   ; the 8255's port B (61h) as last written
DOC_IRQS   = RES_BASE+$878   ; u16 DOC timer interrupts taken (diagnostic)
DOC_DROPS  = RES_BASE+$87A   ; u16 of those, dropped with vTICK at TICK_MAX
CLK_PAID   = RES_BASE+$8A8   ; u16 times the tick count was moved up to the clock (clock.s)
CLK_MADE   = RES_BASE+$8AA   ; u16 ticks added in all (diagnostic, as CLK_PAID)
* The 8259 as far as it goes (ports.s, and the slot in cpu.s): where the
* guest put the interrupts and which it holds off. No priorities and
* nothing in service: an EOI is accepted and means nothing.
PIC_BASE   = RES_BASE+$8AC   ; u16 the vector of IRQ0 (ICW2): 8 on a PC, 28h under Minix
PIC_MASK   = RES_BASE+$8AE   ; u16 the mask register (port 21h): bit n set holds IRQn back
PIC_IRQ6   = RES_BASE+$8B0   ; u16 nonzero: the diskette controller's interrupt is waiting
CRTC_CUR   = RES_BASE+$8B2   ; u16 nonzero: the cursor is where the 6845's R14/R15 put it
                             ; (the guest wrote them after the BIOS last moved it)
TICK_OFF   = $0510           ; F000:0510, INT 08h: hypercall 8 / int 1Ch / iret
MS_OFF     = $0590           ; F000:0590, the mouse driver's stub, which calls the handler (mouse.s)
CTL_REQ    = RES_BASE+$954   ; u16 the desk accessory's request (control.s): 1 a soft
                             ; reboot, 2 a hard one; svc_vbl takes it
CTL_LIVE   = RES_BASE+$956   ; u16 nonzero: a PC is running (Mode B) that the front
                             ; end can start again
CTL_STAT   = RES_BASE+$A80   ; u16 the saved state (control.s): 0 none, 1 there, 2 the
                             ; last save found no memory for it
XMS_OFF    = $05C0           ; F000:05C0, the XMS driver's entry (xms.s)
RD_OFF     = $0540           ; F000:0540, the shared drive's stubs (redir.s)
RD_STATE   = RES_BASE+$8A0   ; u16 the shared drive: 0 none, 1-3 on the way,
                             ; 4 there, 5 it could not be installed
RD_DIAG    = RES_BASE+$8A2   ; u16 why not: 1 DOS before 4, 2 past LASTDRIVE, 3 taken
RD_CALLS   = RES_BASE+$8A4   ; u16 redirector calls seen
RD_LAST    = RES_BASE+$8A6   ; u16 the last one: function | DOS error << 8
RD_LOG     = RES_BASE+$8C0   ; 32 x u16: the last calls, the same way ($FF: passed on),
                             ; at index RD_CALLS mod 32
CAP_BUF    = RES_BASE+$1000
CAP_MAX    = $7000
* The EGA (docs/ega.md): mode 0Dh, 320x200 in 16 colours. Its four 64K
* planes are the guest's banks A, C, D and E: A000:xxxx is where the
* guest reaches them (the core traps that bank while EGA_ON, src/core/
* ega.s), and nothing of the PC lives in C000-EFFF here, so a guest that
* reads those segments sees planes 1-3. The registers are as the guest
* (the core's port handlers) or the BIOS (src/svc/ega.s) last wrote them.
H_EGA      = GUEST_BASE+$A0000   ; plane 0
H_EGA1     = GUEST_BASE+$C0000   ; plane 1
H_EGA2     = GUEST_BASE+$D0000   ; plane 2
H_EGA3     = GUEST_BASE+$E0000   ; plane 3
GFX_EGA    = $0D             ; gfx_mode in mode 0Dh
EGA_ON     = RES_BASE+$940   ; u16 nonzero: the screen is mode 0Dh
EGA_SYNC   = RES_BASE+$942   ; u16 nonzero: SVC changed EGA_ON or a register; the
                             ; core looks after every hypercall (ega_sync)
EGA_START  = RES_BASE+$944   ; u16 the screen's first byte in the planes (the 6845's
                             ; R12/R13 at the last flush)
EGA_PALD   = RES_BASE+$946   ; u16 nonzero: a palette register changed
EGA_ALLD   = RES_BASE+$948   ; u16 nonzero: the whole screen is to be drawn
EGA_SEQI   = RES_BASE+$94A   ; u16 the sequencer's index (port 3C4h)
EGA_GCI    = RES_BASE+$94C   ; u16 the graphics controller's (3CEh)
EGA_ACI    = RES_BASE+$94E   ; u16 the attribute controller's (3C0h)
EGA_ACFF   = RES_BASE+$950   ; u16 3C0h's flip-flop: 0 the index is next, 1 the data
EGA_WINLEN = RES_BASE+$952   ; u16 the bytes of a plane the screen can show, from
                             ; EGA_START: EGA_LEN, or more when the 6845's offset
                             ; register makes a line longer than 40 bytes or the
                             ; attribute controller pans it (ega_flush; a write
                             ; past EGA_LEN and within this sets VID_DIRTY's first)
EGA_SEQ    = RES_BASE+$958   ; 8 bytes: the sequencer (2 is the map mask)
EGA_GC     = RES_BASE+$960   ; 16 bytes: the graphics controller, 0-8
EGA_AC     = RES_BASE+$970   ; 32 bytes: the attribute controller (0-15 the palette)
EGA_LEN    = 8000            ; bytes of a plane on the screen: 40 a line
EGA_DIRTY  = RES_BASE+$C000  ; EGA_LEN flags (and a word to spare), by place on the
                             ; screen: the byte was written. VID_DIRTY's first 32
                             ; say which 256 of them hold one
* The Tandy 1000's video (docs/tandy.md; XTGS.CMD's VIDEO=TANDY): eight
* pages of 16K, of which the page register (3DFh) says which the CPU
* has at B800 (two when its number is even) and which the screen shows.
* Here a page is moved to the window when it is asked for, so the core
* knows nothing of it: nine 16K slots, 0-3 at A000-AFFF, 4 and 5 at
* C000 and C400, 6 and 7 the window, 8 at C800 (no EGA: its banks are
* free, and nothing writes there as a program looking for a monochrome
* card writes B000), eight pages in them and one slot to spare
* (src/svc/tandy.s).
GFX_TDY8   = 8               ; gfx_mode in mode 08h, 160x200 in 16 colours
GFX_TDY9   = 9               ; gfx_mode in mode 09h, 320x200 in 16 colours
 err GFX_TDY9-GFX_TDY8-1     ; (tdy_mode: bit 0 of 3D8h is the difference)
GFX_TDYA   = $0A             ; gfx_mode in mode 0Ah, 640x200 in 4 colours
 err GFX_TDYA-GFX_TDY9-1     ; (tdy_mode: the three are one range)
H_TDYA     = H_EGA           ; slots 0-3
H_TDYC     = H_EGA1          ; slots 4, 5 and 8
TDY_ON     = RES_BASE+$990   ; u16 nonzero: the PC is a Tandy 1000
TDY_IDX    = RES_BASE+$992   ; u16 the video array's register, as chosen at 3DAh
TDY_PAGE   = RES_BASE+$994   ; u16 the page register as last written (3DFh)
TDY_MOVES  = RES_BASE+$996   ; u16 16K moves made (diagnostic)
TDY_SLOT   = RES_BASE+$998   ; 8 bytes: the slot each page is in
TDY_REG    = RES_BASE+$9A0   ; 32 bytes: the array's registers (1 the palette mask,
                             ; 2 the border, 3 the mode, 10h-1Fh the palette)
* The Tandy's sound chip, the SN76496 at ports C0h-C7h (src/svc/sound.s,
* docs/tandy.md), as the guest last wrote it, and the DOC's registers as
* sound.s last wrote them (on any PC: the judge's view of the oscillators).
PSG_REG    = RES_BASE+$9C0   ; 8 x u16: the chip's registers (0, 2, 4 a tone's period;
                             ; 1, 3, 5, 7 an attenuation; 6 the noise)
PSG_LATCH  = RES_BASE+$9D0   ; u16 the register the last byte with bit 7 set named
PSG_WRITES = RES_BASE+$9D2   ; u16 bytes written to the chip
DOC_NOSC   = RES_BASE+$9D4   ; u16 oscillators enabled: 3, and 11 on a Tandy
DOC_SUM    = RES_BASE+$9D6   ; u16 the noise table's checksum as it went to DOC RAM
DOC_LOGN   = RES_BASE+$9D8   ; u16 entries written to DOC_LOG in all
* The joystick (src/svc/joystick.s): the IIGS's paddles as the game port's.
JOY_HAVE   = RES_BASE+$9DA   ; u16 nonzero once a stick has been seen
JOY_X      = RES_BASE+$9DC   ; u16 paddle 0 as last read, 0-255
JOY_Y      = RES_BASE+$9DE   ; u16 paddle 1
JOY_READS  = RES_BASE+$9E0   ; u16 times the paddles were read
* COM1 and COM2 (src/svc/serial.s): the IIGS's modem and printer ports as
* the PC's 8250s. What is a pair is COM1's word, then COM2's.
PIC_IRQ4   = RES_BASE+$9E2   ; u16 nonzero: COM1's interrupt is waiting (the slot)
PIC_IRQ3   = RES_BASE+$9E4   ; u16 and COM2's
 err PIC_IRQ3-PIC_IRQ4-2     ; (serial.s indexes the one from the other)
PIC_KBIS   = RES_BASE+$9EA   ; u16 nonzero: IRQ1 is in service: delivered, port 60h not read and no EOI since (cpu.s, ports.s)
PIC_MOUSE  = RES_BASE+$9EC   ; u16 nonzero: the mouse driver has an event for its handler (the slot enters F000:MS_OFF; mouse.s)
MS_RAW     = RES_BASE+$9EE   ; u16 the last X and Y bytes read from the mouse
COM_ON     = RES_BASE+$9E6   ; u16 XTGS.CMD: bit 0 COM1=MODEM, bit 1 COM2=PRINTER
COM_OPEN   = RES_BASE+$9E8   ; u16 the same bits: the SCC's channel is ours (from the
                             ; guest's first use of the port)
COM_HEAD   = RES_BASE+$9F0   ; 2 x u16 the receive rings: where the interrupt puts,
COM_TAIL   = RES_BASE+$9F4   ; 2 x u16 and where the guest takes
COM_IRQS   = RES_BASE+$9F8   ; 2 x u16 the SCC's receive interrupts
COM_LOST   = RES_BASE+$9FC   ; 2 x u16 characters lost: the ring full, or the SCC overrun
COM_BUF    = RES_BASE+$C00   ; 2 x 256 bytes: the rings
DOC_REG    = RES_BASE+$B00   ; 256 bytes: the DOC's registers as last written (doc_w)
DOC_LOG    = RES_BASE+$E000  ; a ring of DOC_LOGM+1 entries of two bytes: a DOC register
DOC_LOGM   = $0FFF           ; and the value written to it, in order; DOC_MARK and a
DOC_MARK   = $FE             ; byte the guest wrote to the sound chip, before what it led to
