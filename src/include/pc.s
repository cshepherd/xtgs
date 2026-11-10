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
VID_DIRTY  = RES_BASE+$900       ; 64 bytes: a 256-byte page of the B800 bank was
                                 ; written (core hook). Text uses pages 0-15 (4 KB);
                                 ; CGA graphics use 0-63 (the 16 KB framebuffer).

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
EGA_SEQ    = RES_BASE+$958   ; 8 bytes: the sequencer (2 is the map mask)
EGA_GC     = RES_BASE+$960   ; 16 bytes: the graphics controller, 0-8
EGA_AC     = RES_BASE+$970   ; 32 bytes: the attribute controller (0-15 the palette)
EGA_LEN    = 8000            ; bytes of a plane on the screen: 40 a line
EGA_DIRTY  = RES_BASE+$C000  ; EGA_LEN flags (and a word to spare), by place on the
                             ; screen: the byte was written. VID_DIRTY's first 32
                             ; say which 256 of them hold one
